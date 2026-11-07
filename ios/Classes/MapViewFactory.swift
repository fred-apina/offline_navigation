import Flutter
import OfflineNavEngine
import UIKit

final class MapViewFactory: NSObject, FlutterPlatformViewFactory {
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    MapPlatformView(frame: frame)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

/// Hosts the engine's Metal map view inside a Flutter platform view.
private final class MapPlatformView: NSObject, FlutterPlatformView {
  private let mapView: EngineMapView

  init(frame: CGRect) {
    mapView = EngineMapView(frame: frame)
    super.init()
  }

  func view() -> UIView { mapView }

  deinit {
    // Frees the engine's drawing surface as soon as Flutter drops the platform view.
    mapView.teardown()
  }
}
