import 'package:flutter/services.dart';

import 'channels.dart';

/// Controls the shared Organic Maps engine instance.
///
/// Calling this directly is optional: [OfflineNavigationPage] initializes the
/// engine itself on first open. Use it to warm the engine up ahead of time
/// (e.g. from your app's splash screen) so the navigation page opens faster.
class OfflineNavigation {
  OfflineNavigation._();

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
}
