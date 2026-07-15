import 'package:flutter/services.dart';

/// Controls the shared Organic Maps engine instance.
class OfflineNavigation {
  OfflineNavigation._();

  static const MethodChannel _channel = MethodChannel('offline_navigation/engine');

  /// Initializes the native map engine.
  ///
  /// Must complete successfully before any map widget is shown. Safe to call
  /// multiple times: subsequent calls resolve as soon as the engine is ready.
  ///
  /// Throws a [PlatformException] with code `init_failed` if the native
  /// engine could not be initialized (for example when storage is unavailable).
  static Future<void> initialize() async {
    await _channel.invokeMethod<bool>('initialize');
  }

  /// Whether the native engine has finished initializing.
  static Future<bool> get isInitialized async =>
      await _channel.invokeMethod<bool>('isInitialized') ?? false;
}
