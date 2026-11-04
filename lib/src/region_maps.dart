import 'package:flutter/foundation.dart';

/// Why installing, removing or preparing map data failed.
enum MapInstallError {
  /// The id is not `[A-Za-z0-9_-]{1,64}`.
  invalidId,

  /// The id is reserved for a built-in map (`World`, `WorldCoasts`) or is the
  /// id of a country map the engine manages itself.
  reservedName,

  /// A region map with this id is already installed. Pass `replace: true` to
  /// swap it.
  alreadyInstalled,

  /// The map is being used (for example by a running navigation) and cannot be
  /// replaced right now. Close the navigation page and retry.
  inUse,

  /// The source file does not exist.
  fileNotFound,

  /// The download did not complete (network error, HTTP error, wrong size).
  /// A partial download is kept, so retrying resumes it.
  downloadFailed,

  /// The file's SHA-256 does not match the expected value.
  checksumMismatch,

  /// There is not enough free storage.
  notEnoughSpace,

  /// The engine could not read the file.
  badFile,

  /// The file was built with a map generator that does not match the engine.
  /// See [OfflineNavigation.engineDataVersion] and the README.
  unsupportedFormat,

  /// A newer version of this map is already installed.
  versionTooOld,

  /// The caller cancelled through a [MapInstallCancelToken].
  cancelled,

  /// Any other failure (storage I/O, engine not available).
  other,
}

/// Thrown by the map installation methods of [OfflineNavigation].
class MapInstallException implements Exception {
  const MapInstallException(this.error, this.message);

  final MapInstallError error;
  final String message;

  @override
  String toString() => 'MapInstallException(${error.name}): $message';
}

/// Allowed region map ids: letters, digits, `_` and `-`, 1–64 characters.
final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
final RegExp _sha256Pattern = RegExp(r'^[A-Fa-f0-9]{64}$');

/// Whether [id] can be used as a region map id.
bool isValidRegionMapId(String id) => _idPattern.hasMatch(id);

/// A region map file the app wants on the device.
///
/// A *region map* is an Organic Maps `.mwm` file covering an area you choose —
/// a national park, a city, a company campus — instead of a whole country.
/// See the README for how to produce one.
@immutable
class RegionMapSource {
  const RegionMapSource({
    required this.id,
    required this.url,
    required this.sha256,
    this.sizeBytes,
    this.headers = const {},
  });

  /// Stable identifier, also the file name (`<id>.mwm`). `[A-Za-z0-9_-]{1,64}`.
  final String id;

  /// Where to download the file from (`http` or `https`).
  final Uri url;

  /// Hex SHA-256 of the file. Required: a map that is silently corrupt would
  /// otherwise surface as a confusing routing failure far from the cause.
  final String sha256;

  /// Expected size. Used for progress, for the free-space check and to detect
  /// truncated downloads. Strongly recommended.
  final int? sizeBytes;

  /// Extra request headers, for example `Authorization`.
  final Map<String, String> headers;

  /// Throws a [MapInstallException] when the source is malformed.
  void validate() {
    if (!isValidRegionMapId(id)) {
      throw MapInstallException(
          MapInstallError.invalidId, 'A region map id must match [A-Za-z0-9_-]{1,64}: "$id"');
    }
    if (!_sha256Pattern.hasMatch(sha256)) {
      throw const MapInstallException(
          MapInstallError.other, 'sha256 must be 64 hexadecimal characters');
    }
    if (url.scheme != 'http' && url.scheme != 'https') {
      throw MapInstallException(MapInstallError.other, 'Unsupported URL scheme: ${url.scheme}');
    }
    if (sizeBytes != null && sizeBytes! <= 0) {
      throw const MapInstallException(MapInstallError.other, 'sizeBytes must be positive');
    }
  }
}

/// An installed region map.
@immutable
class RegionMapInfo {
  const RegionMapInfo({required this.id, required this.sizeBytes});

  final String id;
  final int sizeBytes;

  @override
  bool operator ==(Object other) =>
      other is RegionMapInfo && other.id == id && other.sizeBytes == sizeBytes;

  @override
  int get hashCode => Object.hash(id, sizeBytes);

  @override
  String toString() => 'RegionMapInfo($id, $sizeBytes bytes)';
}

/// Download progress of [OfflineNavigation.installRegionMap].
@immutable
class MapInstallProgress {
  const MapInstallProgress({required this.bytesReceived, this.totalBytes});

  final int bytesReceived;

  /// Null when the server did not report a size and none was given.
  final int? totalBytes;

  /// 0.0–1.0, or null when the total is unknown.
  double? get fraction =>
      totalBytes == null || totalBytes! <= 0 ? null : (bytesReceived / totalBytes!).clamp(0.0, 1.0);
}

/// Lets the caller cancel a download. A cancelled download keeps its partial
/// file so the next attempt resumes it.
class MapInstallCancelToken {
  bool _cancelled = false;
  final List<VoidCallback> _listeners = [];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  /// Internal: runs [listener] when cancelled (immediately if already so).
  void addListener(VoidCallback listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }

  void removeListener(VoidCallback listener) => _listeners.remove(listener);
}
