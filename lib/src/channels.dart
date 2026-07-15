import 'package:flutter/services.dart';

import 'models.dart';

/// Internal wrapper around the plugin's platform channels.
abstract final class NavChannel {
  static const MethodChannel _channel = MethodChannel('offline_navigation/engine');
  static const EventChannel _downloads = EventChannel('offline_navigation/downloads');
  static const EventChannel _guidance = EventChannel('offline_navigation/guidance');

  /// Pseudo country id used on the downloads stream for base world maps.
  static const String baseMapId = '__base__';

  static Future<void> initialize() async {
    await _channel.invokeMethod<bool>('initialize');
  }

  /// Bytes of base world maps (World.mwm/WorldCoasts.mwm) still missing.
  /// 0 means they are present.
  static Future<int> getBaseMapBytes() async =>
      await _channel.invokeMethod<int>('getBaseMapBytes') ?? 0;

  /// Downloads the missing base world maps. Progress is streamed on
  /// [downloadEvents] under [baseMapId]. Throws a [PlatformException] on failure.
  static Future<void> downloadBaseMaps() =>
      _channel.invokeMethod<void>('downloadBaseMaps');

  static Future<void> cancelBaseMapDownload() =>
      _channel.invokeMethod<void>('cancelBaseMapDownload');

  static Future<bool> hasLocationPermission() async =>
      await _channel.invokeMethod<bool>('hasLocationPermission') ?? false;

  /// Requests location permission from the user if not already granted.
  static Future<bool> requestLocationPermission() async =>
      await _channel.invokeMethod<bool>('requestLocationPermission') ?? false;

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
