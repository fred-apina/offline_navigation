import Flutter
import OfflineNavEngine
import UIKit

/// Entry point of the offline_navigation plugin on iOS.
///
/// Implements the Pigeon-generated `OfflineNavApi` host interface on top of the
/// Organic Maps engine (OfflineNavEngine.framework) and registers the map platform
/// view and the download / guidance event channels.
public final class OfflineNavigationPlugin: NSObject, FlutterPlugin, OfflineNavApi {
  static let downloadsChannel = "offline_navigation/downloads"
  static let guidanceChannel = "offline_navigation/guidance"
  static let mapViewType = "offline_navigation/map_view"

  /// Name of the resource bundle with the engine's shared data (fonts, symbols, style rules...).
  private static let dataBundleName = "offline_navigation_data"

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = OfflineNavigationPlugin()
    let messenger = registrar.messenger()
    OfflineNavApiSetup.setUp(binaryMessenger: messenger, api: instance)
    FlutterEventChannel(name: downloadsChannel, binaryMessenger: messenger)
      .setStreamHandler(DownloadStreamHandler())
    FlutterEventChannel(name: guidanceChannel, binaryMessenger: messenger)
      .setStreamHandler(GuidanceStreamHandler())
    registrar.register(MapViewFactory(), withId: mapViewType)
  }

  // MARK: Engine

  func initialize(completion: @escaping (Result<Void, Error>) -> Void) {
    guard let dataDirectory = Self.dataDirectory() else {
      completion(.failure(PigeonError(
        code: "init_failed",
        message: "The engine's data bundle \(Self.dataBundleName).bundle is missing from the app",
        details: nil)))
      return
    }
    Engine.dataDirectory = dataDirectory
    Engine.initialize { error in
      if let error {
        completion(.failure(PigeonError(code: "init_failed", message: error.localizedDescription, details: nil)))
      } else {
        completion(.success(()))
      }
    }
  }

  func isInitialized() throws -> Bool { Engine.isInitialized }

  /// The data bundle sits inside this plugin's framework when the app uses frameworks, and in the
  /// app bundle when it links the plugin statically.
  private static func dataDirectory() -> String? {
    let candidates = [Bundle(for: OfflineNavigationPlugin.self), Bundle.main]
    for bundle in candidates {
      if let url = bundle.url(forResource: dataBundleName, withExtension: "bundle") {
        return url.path
      }
    }
    return nil
  }

  // MARK: Base maps

  func getBaseMapBytes() throws -> Int64 { Engine.baseMapBytesToDownload() }

  func downloadBaseMaps(completion: @escaping (Result<Void, Error>) -> Void) {
    Engine.downloadBaseMaps { error in completion(Self.result(error)) }
  }

  func cancelBaseMapDownload() throws { Engine.cancelBaseMapDownload() }

  // MARK: Location

  func hasLocationPermission() throws -> Bool { Engine.hasLocationPermission() }

  func requestLocationPermission(completion: @escaping (Result<Bool, Error>) -> Void) {
    Engine.requestLocationPermission { granted in completion(.success(granted)) }
  }

  func setKeepScreenOn(on: Bool) throws {
    UIApplication.shared.isIdleTimerDisabled = on
  }

  // MARK: Country maps

  func getDataVersion() throws -> String { Engine.dataVersion() }

  func resolveCountry(latitude: Double, longitude: Double) throws -> String? {
    Engine.countryId(atLatitude: latitude, longitude: longitude)
  }

  func getCountryStatus(countryId: String) throws -> Int64 {
    Int64(Engine.status(ofCountry: countryId))
  }

  func startDownload(countryIds: [String]) throws {
    if !countryIds.isEmpty { Engine.startDownload(ofCountries: countryIds) }
  }

  func cancelDownload(countryIds: [String]) throws {
    Engine.cancelDownload(ofCountries: countryIds)
  }

  // MARK: Navigation

  func buildRoute(
    start: WirePoint,
    destination: WirePoint,
    mode: WireTravelMode,
    completion: @escaping (Result<WireRouteBuildResult, Error>) -> Void
  ) {
    Engine.buildRoute(
      from: EnginePoint(latitude: start.latitude, longitude: start.longitude, name: start.name),
      to: EnginePoint(latitude: destination.latitude, longitude: destination.longitude, name: destination.name),
      mode: Self.travelMode(mode)
    ) { result, error in
      if let error {
        completion(.failure(Self.pigeonError(error)))
        return
      }
      guard let result else {
        completion(.failure(PigeonError(code: "route_failed", message: "No route result", details: nil)))
        return
      }
      completion(.success(WireRouteBuildResult(
        ok: result.ok,
        cancelled: result.cancelled,
        errorCode: Int64(result.errorCode),
        missingMaps: result.missingMaps,
        distanceText: result.distanceText,
        distanceUnits: result.distanceUnits,
        timeSeconds: Int64(result.timeSeconds))))
    }
  }

  func startGuidance(simulate: Bool, voice: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
    Engine.startGuidanceSimulated(simulate, voice: voice) { error in completion(Self.result(error)) }
  }

  func stopGuidance() throws { Engine.stopGuidance() }

  func closeRouting() throws { Engine.closeRouting() }

  func setViewport(latitude: Double, longitude: Double, zoom: Int64) throws {
    Engine.setViewportLatitude(latitude, longitude: longitude, zoom: Int(zoom))
  }

  // MARK: Region maps

  func getRegionMapsDirectory() throws -> String {
    do {
      return try Engine.regionMapsDirectory()
    } catch {
      throw Self.pigeonError(error)
    }
  }

  func getFreeSpaceBytes() throws -> Int64 { Engine.freeSpaceBytes() }

  func installRegionMapFromFile(
    id: String,
    path: String,
    sha256: String?,
    moveFile: Bool,
    replace: Bool,
    completion: @escaping (Result<WireRegionMap, Error>) -> Void
  ) {
    Engine.installRegionMap(withId: id, path: path, sha256: sha256, moveFile: moveFile, replace: replace) { map, error in
      if let error {
        completion(.failure(Self.pigeonError(error)))
      } else if let map {
        completion(.success(WireRegionMap(id: map.mapId, sizeBytes: map.sizeBytes)))
      } else {
        completion(.failure(PigeonError(code: "io_error", message: "No result", details: nil)))
      }
    }
  }

  func removeRegionMap(id: String, completion: @escaping (Result<Void, Error>) -> Void) {
    Engine.removeRegionMap(withId: id) { error in completion(Self.result(error)) }
  }

  func listRegionMaps() throws -> [WireRegionMap] {
    Engine.listRegionMaps().map { WireRegionMap(id: $0.mapId, sizeBytes: $0.sizeBytes) }
  }

  func isRegionMapInstalled(id: String) throws -> Bool { Engine.isRegionMapInstalled(id) }

  // MARK: Helpers

  private static func travelMode(_ mode: WireTravelMode) -> OMNTravelMode {
    switch mode {
    case .drive: return .drive
    case .walk: return .walk
    case .cycle: return .cycle
    }
  }

  /// Keeps the engine's stable error code, so Dart sees the same codes as on Android.
  private static func pigeonError(_ error: Error) -> PigeonError {
    let nsError = error as NSError
    let code = nsError.userInfo[OMNErrorCodeKey] as? String ?? "engine_error"
    return PigeonError(code: code, message: nsError.localizedDescription, details: nsError.userInfo["details"] as? Int)
  }

  private static func result(_ error: Error?) -> Result<Void, Error> {
    if let error { return .failure(pigeonError(error)) }
    return .success(())
  }
}
