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

/// Optional behavior tweaks for [OfflineNavigationPage].
@immutable
class NavOptions {
  const NavOptions({
    this.voiceGuidance = true,
    this.simulateRoute = false,
  });

  /// Speak turn-by-turn instructions using the device's text-to-speech engine.
  final bool voiceGuidance;

  /// Demo/testing mode: moves the position marker along the route
  /// automatically instead of following the device's real GPS location.
  final bool simulateRoute;
}

/// Why the navigation page was closed.
enum NavigationOutcome { arrived, cancelledByUser, failed }

/// Returned by [OfflineNavigationPage] when it pops.
@immutable
class NavigationResult {
  const NavigationResult(this.outcome, [this.message]);

  final NavigationOutcome outcome;
  final String? message;

  @override
  String toString() => 'NavigationResult(${outcome.name}${message == null ? '' : ': $message'})';
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
