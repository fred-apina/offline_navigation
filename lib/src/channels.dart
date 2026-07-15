import 'package:flutter/services.dart';

import 'models.dart';

/// Internal wrapper around the plugin's platform channels.
abstract final class NavChannel {
  static const MethodChannel _channel = MethodChannel('offline_navigation/engine');
  static const EventChannel _downloads = EventChannel('offline_navigation/downloads');
  static const EventChannel _guidance = EventChannel('offline_navigation/guidance');

  static Future<void> initialize() async {
    await _channel.invokeMethod<bool>('initialize');
  }

  /// Returns the country map ID covering the point, or null (e.g. open sea).
  static Future<String?> resolveCountry(double lat, double lon) =>
      _channel.invokeMethod<String>('resolveCountry', {'lat': lat, 'lon': lon});

  static Future<int> getCountryStatus(String countryId) async =>
      await _channel.invokeMethod<int>('getCountryStatus', {'countryId': countryId}) ??
      MapStatus.unknown;

  static Future<void> startDownload(List<String> countryIds) =>
      _channel.invokeMethod<void>('startDownload', {'countryIds': countryIds});

  static Future<void> cancelDownload(List<String> countryIds) =>
      _channel.invokeMethod<void>('cancelDownload', {'countryIds': countryIds});

  /// Resolves with {ok: true, distance, distanceUnits, timeSeconds}
  /// or {ok: false, code, missingMaps}.
  static Future<Map<dynamic, dynamic>> buildRoute({
    required NavPoint start,
    required NavPoint destination,
    required TravelMode mode,
  }) async =>
      (await _channel.invokeMapMethod<dynamic, dynamic>('buildRoute', {
        'startLat': start.latitude,
        'startLon': start.longitude,
        'startName': start.name ?? 'Start',
        'destLat': destination.latitude,
        'destLon': destination.longitude,
        'destName': destination.name ?? 'Destination',
        'travelMode': mode.wireName,
      }))!;

  static Future<void> startGuidance({required bool simulate, required bool voice}) =>
      _channel.invokeMethod<void>('startGuidance', {'simulate': simulate, 'voice': voice});

  static Future<void> stopGuidance() => _channel.invokeMethod<void>('stopGuidance');

  static Future<void> closeRouting() => _channel.invokeMethod<void>('closeRouting');

  static Future<void> setViewport(double lat, double lon, int zoom) =>
      _channel.invokeMethod<void>('setViewport', {'lat': lat, 'lon': lon, 'zoom': zoom});

  static Future<void> setKeepScreenOn(bool on) =>
      _channel.invokeMethod<void>('setKeepScreenOn', {'on': on});

  static Stream<MapDownloadEvent> downloadEvents() => _downloads
      .receiveBroadcastStream()
      .map((event) => MapDownloadEvent.fromMap(event as Map<dynamic, dynamic>));

  static Stream<GuidanceUpdate> guidanceEvents() => _guidance
      .receiveBroadcastStream()
      .map((event) => GuidanceUpdate.fromMap(event as Map<dynamic, dynamic>));
}
