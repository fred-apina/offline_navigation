package io.github.fredapina.offline_navigation

import android.content.Context
import android.util.Log
import android.view.View
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import app.organicmaps.sdk.MapController
import app.organicmaps.sdk.MapRenderingListener
import app.organicmaps.sdk.MapView
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class OmMapViewFactory(private val plugin: OfflineNavigationPlugin) :
  PlatformViewFactory(StandardMessageCodec.INSTANCE) {

  override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
    check(OmEngine.isReady) {
      "OfflineNavigation.initialize() must complete before showing the map view"
    }
    return OmMapPlatformView(context, plugin)
  }
}

/**
 * Hosts the Organic Maps [MapView] (a SurfaceView) inside a Flutter platform view.
 * Requires hybrid composition on the Dart side.
 */
private class OmMapPlatformView(
  context: Context,
  private val plugin: OfflineNavigationPlugin,
) : PlatformView, MapRenderingListener {
  companion object {
    private const val TAG = "OmMapPlatformView"
  }

  private val mapView = MapView(context)
  private val controller = MapController(
    mapView,
    OmEngine.locationHelper,
    /* mapRenderingListener = */ this,
    /* callbackUnsupported = */ null,
    /* launchByDeepLink = */ false,
  )

  init {
    // Drive the map's start/resume/pause/stop from the host activity's lifecycle,
    // the same way MwmActivity does. Adding the observer replays the current state,
    // so a view created on a resumed activity starts rendering immediately.
    plugin.activityLifecycle?.addObserver(controller)
      ?: Log.w(TAG, "No activity lifecycle available; map will not render")
  }

  override fun getView(): View = mapView

  override fun dispose() {
    plugin.activityLifecycle?.removeObserver(controller)
    // MapController.onDestroy only detaches listeners; the render surface itself is
    // torn down by MapView's SurfaceHolder callback when the view leaves the window.
    controller.onDestroy(NoopLifecycleOwner)
  }

  override fun onRenderingCreated() {
    Log.i(TAG, "Map rendering created")
  }

  override fun onRenderingRestored() {
    Log.i(TAG, "Map rendering restored")
  }

  override fun onRenderingInitializationFinished() {
    Log.i(TAG, "Map rendering initialization finished")
  }

  /** MapController ignores the owner argument; this satisfies the signature. */
  private object NoopLifecycleOwner : LifecycleOwner {
    override val lifecycle: Lifecycle
      get() = throw UnsupportedOperationException("not a real lifecycle owner")
  }
}
