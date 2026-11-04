// Pigeon schema for the offline_navigation platform channel contract.
//
// Regenerate with:
//   dart run pigeon --input pigeons/messages.dart
//
// The two event streams (map downloads, guidance updates) intentionally stay
// as plain EventChannels — see channels.dart / StreamHandlers.kt.
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/src/messages.g.dart',
  kotlinOut: 'android/src/main/kotlin/io/github/fredapina/offline_navigation/Messages.g.kt',
  kotlinOptions: KotlinOptions(package: 'io.github.fredapina.offline_navigation'),
  dartPackageName: 'offline_navigation',
))

/// Travel mode for routing.
enum WireTravelMode { drive, walk, cycle }

/// A geographic point with an optional display name.
class WirePoint {
  WirePoint({required this.latitude, required this.longitude, this.name});
  double latitude;
  double longitude;
  String? name;
}

/// Result of a route build attempt.
class WireRouteBuildResult {
  WireRouteBuildResult({
    required this.ok,
    required this.cancelled,
    required this.errorCode,
    required this.timeSeconds,
    required this.missingMaps,
    this.distanceText,
    this.distanceUnits,
  });

  bool ok;

  /// True when the build was aborted because the page is closing.
  bool cancelled;

  /// Native routing result code; meaningful when [ok] is false.
  int errorCode;

  /// Country ids that must be downloaded before this route can be built.
  List<String> missingMaps;

  String? distanceText;
  String? distanceUnits;
  int timeSeconds;
}

/// A regional map file installed in the engine's maps directory.
class WireRegionMap {
  WireRegionMap({required this.id, required this.sizeBytes});
  String id;
  int sizeBytes;
}

@HostApi()
abstract class OfflineNavApi {
  /// Initializes the native map engine; completes when the framework is ready.
  @async
  void initialize();

  bool isInitialized();

  /// Bytes of base world maps still missing (0 = present).
  int getBaseMapBytes();

  /// Downloads missing base world maps; progress streams on the downloads
  /// EventChannel under the `__base__` pseudo country id.
  @async
  void downloadBaseMaps();

  void cancelBaseMapDownload();

  bool hasLocationPermission();

  @async
  bool requestLocationPermission();

  /// The engine's bundled map-data version (e.g. "260111"). Downloads only
  /// work while the CDN still serves this version.
  String getDataVersion();

  /// Country map id covering the point, or null (e.g. open sea).
  String? resolveCountry(double latitude, double longitude);

  /// Native storage status code for the country (see MapStatus in models.dart).
  int getCountryStatus(String countryId);

  void startDownload(List<String> countryIds);

  void cancelDownload(List<String> countryIds);

  @async
  WireRouteBuildResult buildRoute(
    WirePoint start,
    WirePoint destination,
    WireTravelMode mode,
  );

  @async
  void startGuidance(bool simulate, bool voice);

  void stopGuidance();

  void closeRouting();

  void setViewport(double latitude, double longitude, int zoom);

  void setKeepScreenOn(bool on);

  /// Directory region map files are installed into (created on demand).
  /// Requires an initialized engine.
  String getRegionMapsDirectory();

  /// Free bytes on the volume holding [getRegionMapsDirectory].
  int getFreeSpaceBytes();

  /// Verifies [sha256] (when given), places the file into the maps directory
  /// as `<id>.mwm` and registers it with the running engine. With [moveFile]
  /// the source is moved instead of copied. With [replace] an installed map
  /// with the same id is removed first.
  ///
  /// Fails with a [FlutterError] whose code is one of: `invalid_id`,
  /// `reserved_name`, `file_not_found`, `checksum_mismatch`, `not_enough_space`,
  /// `already_installed`, `in_use`, `bad_file`, `unsupported_format`,
  /// `version_too_old`, `io_error`, `not_ready`.
  @async
  WireRegionMap installRegionMapFromFile(
    String id,
    String path,
    String? sha256,
    bool moveFile,
    bool replace,
  );

  /// Removes an installed region map (and its file).
  @async
  void removeRegionMap(String id);

  List<WireRegionMap> listRegionMaps();

  bool isRegionMapInstalled(String id);
}
