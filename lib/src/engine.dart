import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'channels.dart';
import 'models.dart';
import 'region_map_download.dart';
import 'region_maps.dart';

/// Controls the shared Organic Maps engine instance and the map data it uses.
///
/// Calling [initialize] is optional: [OfflineNavigationPage] initializes the
/// engine itself on first open. Use it to warm the engine up ahead of time
/// (e.g. from your app's splash screen) so the navigation page opens faster.
///
/// ## Preparing maps ahead of time
///
/// To navigate where there is no internet, install the maps beforehand:
///
/// ```dart
/// await OfflineNavigation.ensureBaseMaps();            // small, once per install
/// await OfflineNavigation.installRegionMap(RegionMapSource(
///   id: 'serengeti',
///   url: Uri.parse('https://example.com/maps/serengeti.mwm'),
///   sha256: '…',
///   sizeBytes: 2149600,
/// ));
/// ```
///
/// and open the page with `NavOptions(mapPolicy: MapPolicy.installedOnly)`.
/// If your app downloads files itself, hand the finished file to
/// [installRegionMapFromFile] instead.
class OfflineNavigation {
  OfflineNavigation._();

  /// Pseudo map id reported in [NavigationResult.missingMaps] when the base
  /// world map is missing.
  static const String baseMapsId = NavChannel.baseMapId;

  /// Initializes the native map engine.
  ///
  /// Safe to call multiple times: subsequent calls resolve as soon as the
  /// engine is ready.
  ///
  /// Throws a [PlatformException] with code `init_failed` if the native
  /// engine could not be initialized (for example when storage is unavailable).
  static Future<void> initialize() => NavChannel.initialize();

  /// Whether the native engine has finished initializing.
  static Future<bool> get isInitialized => NavChannel.isInitialized();

  /// The map-data version of the engine, e.g. `"260111"`. Region map files
  /// must be built with a map generator of the same release; see the README.
  static Future<String> get engineDataVersion async {
    await initialize();
    return NavChannel.getDataVersion();
  }

  // ── Base maps ────────────────────────────────────────────────

  /// Bytes of the base world maps that are still missing; 0 when present.
  ///
  /// The base maps (a few MB) are needed once per install, also for region
  /// maps: they draw everything outside the region.
  static Future<int> get baseMapsBytesMissing async {
    await initialize();
    return NavChannel.getBaseMapBytes();
  }

  /// Downloads the base world maps if they are missing. [onProgress] receives
  /// 0–100. Completes immediately when they are already present.
  ///
  /// Throws a [MapInstallException].
  static Future<void> ensureBaseMaps({void Function(int percent)? onProgress}) async {
    await initialize();
    if (await NavChannel.getBaseMapBytes() <= 0) return;

    final sub = NavChannel.downloadEvents().listen((event) {
      if (event.countryId == NavChannel.baseMapId && event.progress >= 0) {
        onProgress?.call(event.progress);
      }
    });
    try {
      await NavChannel.downloadBaseMaps();
    } on PlatformException catch (e) {
      throw MapInstallException(
        e.code == 'cancelled' ? MapInstallError.cancelled : MapInstallError.downloadFailed,
        e.message ?? 'Could not download the base world map',
      );
    } finally {
      await sub.cancel();
    }
  }

  // ── Region maps ──────────────────────────────────────────────

  /// Downloads a region map and installs it. Routing and rendering use it
  /// right away; the engine does not need a restart.
  ///
  /// The download resumes a partial file left by an earlier attempt, checks
  /// the SHA-256 and the size, and the file is only moved into place once it is
  /// complete and valid.
  ///
  /// Pass a [cancelToken] to be able to cancel; the partial file is kept for
  /// the next attempt. With [replace] an installed map with the same id is
  /// swapped for the new one.
  ///
  /// Throws a [MapInstallException].
  static Future<RegionMapInfo> installRegionMap(
    RegionMapSource source, {
    bool replace = false,
    void Function(MapInstallProgress progress)? onProgress,
    MapInstallCancelToken? cancelToken,
    HttpClientFactory? httpClientFactory,
  }) async {
    source.validate();
    await _initializeForInstall();

    if (!replace && await NavChannel.isRegionMapInstalled(source.id)) {
      throw MapInstallException(
          MapInstallError.alreadyInstalled, 'Region map "${source.id}" is already installed');
    }

    final dir = await _call(() => NavChannel.getRegionMapsDirectory());
    final part = File('$dir${Platform.pathSeparator}${source.id}.mwm.part');

    final size = source.sizeBytes;
    if (size != null) {
      final already = part.existsSync() ? part.lengthSync() : 0;
      final free = await _call(() => NavChannel.getFreeSpaceBytes());
      // Room for the rest of the download plus a safety margin.
      if (free < (size - already) + 16 * 1024 * 1024) {
        throw const MapInstallException(MapInstallError.notEnoughSpace, 'Not enough free storage space');
      }
    }

    await downloadMapFile(
      url: source.url,
      partFile: part,
      headers: source.headers,
      expectedSize: size,
      onProgress: onProgress == null
          ? null
          : (received, total) => onProgress(MapInstallProgress(bytesReceived: received, totalBytes: total)),
      cancelToken: cancelToken,
      clientFactory: httpClientFactory,
    );

    try {
      return await installRegionMapFromFile(
        source.id,
        part.path,
        sha256: source.sha256,
        moveFile: true,
        replace: replace,
      );
    } on MapInstallException catch (e) {
      // A corrupt download must not be resumed: start clean next time.
      if (e.error == MapInstallError.checksumMismatch ||
          e.error == MapInstallError.badFile ||
          e.error == MapInstallError.unsupportedFormat) {
        if (part.existsSync()) part.deleteSync();
      }
      rethrow;
    }
  }

  /// Installs a region map from a file your app already has, for example one
  /// downloaded by your own download manager.
  ///
  /// The file is verified against [sha256] when given. With [moveFile] it is
  /// moved into the maps directory (free on the same volume) instead of
  /// copied; the original is left alone otherwise.
  ///
  /// Throws a [MapInstallException].
  static Future<RegionMapInfo> installRegionMapFromFile(
    String id,
    String path, {
    String? sha256,
    bool moveFile = false,
    bool replace = false,
  }) async {
    if (!isValidRegionMapId(id)) {
      throw MapInstallException(
          MapInstallError.invalidId, 'A region map id must match [A-Za-z0-9_-]{1,64}: "$id"');
    }
    await _initializeForInstall();
    final map = await _call(() => NavChannel.installRegionMapFromFile(
          id: id,
          path: path,
          sha256: sha256,
          moveFile: moveFile,
          replace: replace,
        ));
    return RegionMapInfo(id: map.id, sizeBytes: map.sizeBytes);
  }

  /// The installed region maps.
  static Future<List<RegionMapInfo>> listRegionMaps() async {
    await _initializeForInstall();
    final maps = await _call(() => NavChannel.listRegionMaps());
    return [for (final m in maps) RegionMapInfo(id: m.id, sizeBytes: m.sizeBytes)];
  }

  /// Whether a region map with this id is installed.
  static Future<bool> isRegionMapInstalled(String id) async {
    if (!isValidRegionMapId(id)) return false;
    await _initializeForInstall();
    return NavChannel.isRegionMapInstalled(id);
  }

  /// Removes an installed region map and frees its storage. Removing an
  /// unknown id is not an error. If the map is being used right now, the file
  /// is deleted as soon as the navigation that uses it ends.
  static Future<void> removeRegionMap(String id) async {
    if (!isValidRegionMapId(id)) {
      throw MapInstallException(
          MapInstallError.invalidId, 'A region map id must match [A-Za-z0-9_-]{1,64}: "$id"');
    }
    await _initializeForInstall();
    await _call(() => NavChannel.removeRegionMap(id));
  }

  // ── Internals ────────────────────────────────────────────────

  static Future<void> _initializeForInstall() async {
    try {
      await NavChannel.initialize();
    } on PlatformException catch (e) {
      throw MapInstallException(MapInstallError.other, e.message ?? 'The map engine could not start');
    }
  }

  static Future<T> _call<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PlatformException catch (e) {
      throw MapInstallException(_errorFor(e.code), e.message ?? e.code);
    }
  }

  static MapInstallError _errorFor(String code) => switch (code) {
        'invalid_id' => MapInstallError.invalidId,
        'reserved_name' => MapInstallError.reservedName,
        'already_installed' => MapInstallError.alreadyInstalled,
        'in_use' => MapInstallError.inUse,
        'file_not_found' => MapInstallError.fileNotFound,
        'checksum_mismatch' => MapInstallError.checksumMismatch,
        'not_enough_space' => MapInstallError.notEnoughSpace,
        'bad_file' => MapInstallError.badFile,
        'unsupported_format' => MapInstallError.unsupportedFormat,
        'version_too_old' => MapInstallError.versionTooOld,
        _ => MapInstallError.other,
      };
}
