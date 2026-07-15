import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';

/// Displays the offline map.
///
/// [OfflineNavigation.initialize] must have completed before this widget is
/// built. The map renders in a native view via hybrid composition, so all
/// gestures over it are forwarded to the map engine.
class OfflineMapView extends StatelessWidget {
  const OfflineMapView({super.key});

  static const String _viewType = 'offline_navigation/map_view';

  @override
  Widget build(BuildContext context) {
    assert(
      defaultTargetPlatform == TargetPlatform.android,
      'offline_navigation currently supports Android only',
    );
    return Stack(
      children: [
        Positioned.fill(
          child: PlatformViewLink(
            viewType: _viewType,
            surfaceFactory: (context, controller) => AndroidViewSurface(
              controller: controller as AndroidViewController,
              gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
              },
              hitTestBehavior: PlatformViewHitTestBehavior.opaque,
            ),
            onCreatePlatformView: (params) {
              // The map is a SurfaceView, which requires hybrid composition.
              final controller = PlatformViewsService.initExpensiveAndroidView(
                id: params.id,
                viewType: _viewType,
                layoutDirection: TextDirection.ltr,
                creationParamsCodec: const StandardMessageCodec(),
                onFocus: () => params.onFocusChanged(true),
              )
                ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
                ..create();
              return controller;
            },
          ),
        ),
        // Map data license requires visible attribution (ODbL).
        const Positioned(left: 8, bottom: 8, child: _OsmAttribution()),
      ],
    );
  }
}

class _OsmAttribution extends StatelessWidget {
  const _OsmAttribution();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        '© OpenStreetMap contributors',
        style: TextStyle(fontSize: 11, color: Colors.black87),
      ),
    );
  }
}
