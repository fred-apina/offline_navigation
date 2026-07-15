import 'package:flutter/services.dart';

import 'messages.g.dart';
import 'models.dart';

/// Internal wrapper around the plugin's platform channels.
///
/// Method calls go through the Pigeon-generated [OfflineNavApi]; the two
/// event streams (downloads, guidance) are plain EventChannels.
abstract final class NavChannel {
  static final OfflineNavApi _api = OfflineNavApi();
  static const EventChannel _downloads = EventChannel('offline_navigation/downloads');
  static const EventChannel _guidance = EventChannel('offline_navigation/guidance');

  /// Pseudo country id used on the downloads stream for base world maps.
  static const String baseMapId = '__base__';

  static Future<void> initialize() => _api.initialize();

  static Future<bool> isInitialized() => _api.isInitialized();

  /// Bytes of base world maps (World.mwm/WorldCoasts.mwm) still missing.
  /// 0 means they are present.
  static Future<int> getBaseMapBytes() => _api.getBaseMapBytes();

  /// Downloads the missing base world maps. Progress is streamed on
  /// [downloadEvents] under [baseMapId]. Throws a [PlatformException] on failure.
  static Future<void> downloadBaseMaps() => _api.downloadBaseMaps();

  static Future<void> cancelBaseMapDownload() => _api.cancelBaseMapDownload();

  static Future<bool> hasLocationPermission() => _api.hasLocationPermission();

  /// Requests location permission from the user if not already granted.
  static Future<bool> requestLocationPermission() => _api.requestLocationPermission();

  /// Returns the country map ID covering the point, or null (e.g. open sea).
  static Future<String?> resolveCountry(double lat, double lon) =>
      _api.resolveCountry(lat, lon);

  static Future<int> getCountryStatus(String countryId) =>
      _api.getCountryStatus(countryId);

  static Future<void> startDownload(List<String> countryIds) =>
      _api.startDownload(countryIds);

  static Future<void> cancelDownload(List<String> countryIds) =>
      _api.cancelDownload(countryIds);

  static Future<WireRouteBuildResult> buildRoute({
    required NavPoint start,
    required NavPoint destination,
    required TravelMode mode,
  }) =>
      _api.buildRoute(
        WirePoint(latitude: start.latitude, longitude: start.longitude, name: start.name),
        WirePoint(
            latitude: destination.latitude, longitude: destination.longitude, name: destination.name),
        switch (mode) {
          TravelMode.drive => WireTravelMode.drive,
          TravelMode.walk => WireTravelMode.walk,
          TravelMode.cycle => WireTravelMode.cycle,
        },
      );

  static Future<void> startGuidance({required bool simulate, required bool voice}) =>
      _api.startGuidance(simulate, voice);

  static Future<void> stopGuidance() => _api.stopGuidance();

  static Future<void> closeRouting() => _api.closeRouting();

  static Future<void> setViewport(double lat, double lon, int zoom) =>
      _api.setViewport(lat, lon, zoom);

  static Future<void> setKeepScreenOn(bool on) => _api.setKeepScreenOn(on);

  static Stream<MapDownloadEvent> downloadEvents() => _downloads
      .receiveBroadcastStream()
      .map((event) => MapDownloadEvent.fromMap(event as Map<dynamic, dynamic>));

  static Stream<GuidanceUpdate> guidanceEvents() => _guidance
      .receiveBroadcastStream()
      .map((event) => GuidanceUpdate.fromMap(event as Map<dynamic, dynamic>));
}
