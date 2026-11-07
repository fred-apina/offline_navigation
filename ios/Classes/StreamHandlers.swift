import Flutter
import OfflineNavEngine

/// Streams map download status and progress events (including the base world maps, under the
/// `__base__` pseudo country id) to Dart. Event shape:
/// `{countryId, status, progress, errorCode?, localSize?, remoteSize?}`.
final class DownloadStreamHandler: NSObject, FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    Engine.downloadEventHandler = { event in events(event) }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    Engine.downloadEventHandler = nil
    return nil
  }
}

/// Streams a guidance snapshot about once a second while guiding.
final class GuidanceStreamHandler: NSObject, FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    Engine.guidanceEventHandler = { info in events(info) }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    Engine.guidanceEventHandler = nil
    return nil
  }
}
