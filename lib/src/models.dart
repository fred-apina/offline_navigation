import 'package:flutter/foundation.dart';

/// A named geographic point used as a route endpoint.
@immutable
class NavPoint {
  const NavPoint({
    required this.latitude,
    required this.longitude,
    this.name,
  })  : assert(latitude >= -90 && latitude <= 90, 'latitude out of range'),
        assert(longitude >= -180 && longitude <= 180, 'longitude out of range');

  final double latitude;
  final double longitude;

  /// Optional display name, shown on the map pin and in the navigation UI.
  final String? name;

  @override
  String toString() => 'NavPoint(${name ?? ''} $latitude,$longitude)';
}

/// How the route is traveled.
enum TravelMode { drive, walk, cycle }

/// Where [OfflineNavigationPage] gets its map data from.
enum MapPolicy {
  /// Default. If the maps for the route are missing, the page downloads the
  /// map of the country the route is in (and the base world map on first run),
  /// showing a progress screen.
  autoDownloadCountry,

  /// Never use the network for map data. The page routes only with maps that
  /// are already on the device: the maps installed with
  /// [OfflineNavigation.installRegionMap] or by an earlier country download.
  /// It needs no base world map (72 MB): the map is drawn from the installed
  /// maps and is blank outside them, so use this for navigation that stays
  /// inside them.
  ///
  /// If something the route needs is missing, the page pops immediately with
  /// [NavigationOutcome.failed], [NavigationFailure.mapsMissing] and the list
  /// of missing map ids in [NavigationResult.missingMaps] — your app decides
  /// what to offer the user. Use this when maps are prepared ahead of time,
  /// for example in a "download for offline use" step.
  installedOnly,
}

/// Optional behavior tweaks for [OfflineNavigationPage].
@immutable
class NavOptions {
  const NavOptions({
    this.voiceGuidance = true,
    this.simulateRoute = false,
    this.mapPolicy = MapPolicy.autoDownloadCountry,
  });

  /// Speak turn-by-turn instructions using the device's text-to-speech engine.
  final bool voiceGuidance;

  /// Demo/testing mode: moves the position marker along the route
  /// automatically instead of following the device's real GPS location.
  final bool simulateRoute;

  /// Whether the page may download map data. See [MapPolicy].
  final MapPolicy mapPolicy;
}

/// Why the navigation page was closed.
enum NavigationOutcome { arrived, cancelledByUser, failed }

/// What went wrong when [NavigationResult.outcome] is
/// [NavigationOutcome.failed].
enum NavigationFailure {
  /// Map data the route needs is not on the device. [NavigationResult.missingMaps]
  /// lists the ids the engine asked for. With [MapPolicy.installedOnly] this
  /// also means "the installed maps do not cover this route".
  mapsMissing,

  /// Downloading map data failed (only with [MapPolicy.autoDownloadCountry]).
  downloadFailed,

  /// The maps are present but no route could be built between the points.
  noRoute,

  /// The map engine could not start.
  engineError,

  /// Anything else; see [NavigationResult.message].
  other,
}

/// Returned by [OfflineNavigationPage] when it pops.
@immutable
class NavigationResult {
  const NavigationResult(this.outcome, [this.message])
      : failure = null,
        missingMaps = const [];

  /// A failed navigation with a machine-readable [failure].
  const NavigationResult.failed(
    this.message, {
    this.failure = NavigationFailure.other,
    this.missingMaps = const [],
  }) : outcome = NavigationOutcome.failed;

  final NavigationOutcome outcome;

  /// Human-readable detail for a failure; not localized.
  final String? message;

  /// Set when [outcome] is [NavigationOutcome.failed] and the cause is known.
  final NavigationFailure? failure;

  /// Ids of the maps that were missing, for [NavigationFailure.mapsMissing].
  final List<String> missingMaps;

  @override
  String toString() =>
      'NavigationResult(${outcome.name}${failure == null ? '' : ', ${failure!.name}'}${message == null ? '' : ': $message'})';
}

/// Summary of a successfully built route.
@immutable
class RouteSummary {
  const RouteSummary({required this.distanceText, required this.duration});

  /// Localized distance, e.g. "42 km".
  final String distanceText;
  final Duration duration;
}

/// Turn kinds, matching the engine's CarDirection enum order.
enum CarTurn {
  noTurn,
  goStraight,
  turnRight,
  turnSharpRight,
  turnSlightRight,
  turnLeft,
  turnSharpLeft,
  turnSlightLeft,
  uTurnLeft,
  uTurnRight,
  enterRoundAbout,
  leaveRoundAbout,
  stayOnRoundAbout,
  startAtEndOfStreet,
  reachedYourDestination,
  exitHighwayToLeft,
  exitHighwayToRight;

  static CarTurn fromOrdinal(int? ordinal) =>
      (ordinal == null || ordinal < 0 || ordinal >= values.length) ? noTurn : values[ordinal];
}

/// One tick of turn-by-turn guidance state.
@immutable
class GuidanceUpdate {
  const GuidanceUpdate({
    required this.distanceToTargetText,
    required this.distanceToTurnText,
    required this.nextStreet,
    required this.currentStreet,
    required this.timeRemaining,
    required this.completionPercent,
    required this.turn,
    required this.roundaboutExit,
  });

  factory GuidanceUpdate.fromMap(Map<dynamic, dynamic> map) {
    String dist(String? value, String? units) =>
        value == null || value.isEmpty ? '' : '$value ${_unitSuffix(units)}';
    return GuidanceUpdate(
      distanceToTargetText: dist(map['distToTarget'] as String?, map['distToTargetUnits'] as String?),
      distanceToTurnText: dist(map['distToTurn'] as String?, map['distToTurnUnits'] as String?),
      nextStreet: (map['nextStreet'] as String?) ?? '',
      currentStreet: (map['currentStreet'] as String?) ?? '',
      timeRemaining: Duration(seconds: (map['timeSeconds'] as int?) ?? 0),
      completionPercent: ((map['completionPercent'] as num?) ?? 0).toDouble(),
      turn: CarTurn.fromOrdinal(map['carDirection'] as int?),
      roundaboutExit: (map['exitNum'] as int?) ?? 0,
    );
  }

  final String distanceToTargetText;
  final String distanceToTurnText;
  final String nextStreet;
  final String currentStreet;
  final Duration timeRemaining;
  final double completionPercent;
  final CarTurn turn;
  final int roundaboutExit;

  static String _unitSuffix(String? unitsName) => switch (unitsName) {
        'Meters' => 'm',
        'Kilometers' => 'km',
        'Feet' => 'ft',
        'Miles' => 'mi',
        _ => '',
      };
}

/// Download status codes reported by the map storage (mirrors CountryItem).
abstract final class MapStatus {
  static const int unknown = 0;
  static const int inProgress = 1;
  static const int applying = 2;
  static const int enqueued = 3;
  static const int failed = 4;
  static const int updatable = 5;
  static const int done = 6;
  static const int downloadable = 7;
  static const int partly = 8;

  static bool isDownloaded(int status) => status == done || status == updatable;
  static bool isActive(int status) => status == inProgress || status == applying || status == enqueued;
}

/// One download progress event for a country map file.
@immutable
class MapDownloadEvent {
  const MapDownloadEvent({
    required this.countryId,
    required this.status,
    required this.progress,
  });

  factory MapDownloadEvent.fromMap(Map<dynamic, dynamic> map) => MapDownloadEvent(
        countryId: (map['countryId'] as String?) ?? '',
        status: (map['status'] as int?) ?? MapStatus.unknown,
        progress: (map['progress'] as int?) ?? 0,
      );

  final String countryId;
  final int status;

  /// 0–100.
  final int progress;
}
