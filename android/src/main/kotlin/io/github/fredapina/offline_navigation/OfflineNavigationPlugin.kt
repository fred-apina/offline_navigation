package io.github.fredapina.offline_navigation

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import app.organicmaps.sdk.Framework
import app.organicmaps.sdk.downloader.MapManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.embedding.engine.plugins.lifecycle.FlutterLifecycleAdapter
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * Entry point of the offline_navigation plugin.
 *
 * Implements the Pigeon-generated [OfflineNavApi] host interface and registers
 * the map platform view plus the download/guidance event channels.
 */
class OfflineNavigationPlugin :
  FlutterPlugin,
  ActivityAware,
  OfflineNavApi,
  PluginRegistry.RequestPermissionsResultListener {
  companion object {
    const val DOWNLOADS_CHANNEL = "offline_navigation/downloads"
    const val GUIDANCE_CHANNEL = "offline_navigation/guidance"
    const val MAP_VIEW_TYPE = "offline_navigation/map_view"
    private const val LOCATION_PERMISSION_REQUEST = 24371
  }

  private var downloadsChannel: EventChannel? = null
  private var guidanceChannel: EventChannel? = null
  private var flutterBinding: FlutterPlugin.FlutterPluginBinding? = null

  /** Lifecycle of the host activity; null while detached. */
  var activityLifecycle: Lifecycle? = null
    private set

  private var activity: Activity? = null
  private var pendingPermissionCallback: ((Result<Boolean>) -> Unit)? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    flutterBinding = binding
    OfflineNavApi.setUp(binding.binaryMessenger, this)
    downloadsChannel = EventChannel(binding.binaryMessenger, DOWNLOADS_CHANNEL).apply {
      setStreamHandler(DownloadStreamHandler())
    }
    guidanceChannel = EventChannel(binding.binaryMessenger, GUIDANCE_CHANNEL).apply {
      setStreamHandler(GuidanceStreamHandler())
    }
    binding.platformViewRegistry.registerViewFactory(MAP_VIEW_TYPE, OmMapViewFactory(this))
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    OfflineNavApi.setUp(binding.binaryMessenger, null)
    downloadsChannel?.setStreamHandler(null)
    guidanceChannel?.setStreamHandler(null)
    flutterBinding = null
  }

  // ── OfflineNavApi ─────────────────────────────────────────────

  override fun initialize(callback: (Result<Unit>) -> Unit) {
    val context = flutterBinding?.applicationContext
    if (context == null) {
      callback(Result.failure(FlutterError("no_context", "Plugin is not attached to a Flutter engine", null)))
      return
    }
    OmEngine.initialize(
      context,
      onReady = { callback(Result.success(Unit)) },
      onError = { e -> callback(Result.failure(FlutterError("init_failed", e.message, null))) },
    )
  }

  override fun isInitialized(): Boolean = OmEngine.isReady

  override fun getBaseMapBytes(): Long = ResourceBootstrap.bytesToDownload().toLong()

  override fun downloadBaseMaps(callback: (Result<Unit>) -> Unit) = ResourceBootstrap.download(callback)

  override fun cancelBaseMapDownload() = ResourceBootstrap.cancel()

  override fun resolveCountry(latitude: Double, longitude: Double): String? =
    MapManager.nativeFindCountry(latitude, longitude)

  override fun getCountryStatus(countryId: String): Long =
    MapManager.nativeGetStatus(countryId).toLong()

  override fun startDownload(countryIds: List<String>) {
    if (countryIds.isNotEmpty()) MapManager.startDownload(*countryIds.toTypedArray())
  }

  override fun cancelDownload(countryIds: List<String>) {
    countryIds.forEach { MapManager.nativeCancel(it) }
  }

  override fun buildRoute(
    start: WirePoint,
    destination: WirePoint,
    mode: WireTravelMode,
    callback: (Result<WireRouteBuildResult>) -> Unit,
  ) = NavigationSession.buildRoute(start, destination, mode, callback)

  override fun startGuidance(simulate: Boolean, voice: Boolean, callback: (Result<Unit>) -> Unit) =
    NavigationSession.startGuidance(simulate, voice, callback)

  override fun stopGuidance() = NavigationSession.stopGuidance()

  override fun closeRouting() = NavigationSession.closeRouting()

  override fun setViewport(latitude: Double, longitude: Double, zoom: Long) {
    Framework.nativeSetViewportCenter(latitude, longitude, zoom.toInt())
  }

  override fun setKeepScreenOn(on: Boolean) {
    activity?.window?.let { window ->
      if (on) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
      else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
  }

  // ── Location permission ───────────────────────────────────────

  override fun hasLocationPermission(): Boolean {
    val context = flutterBinding?.applicationContext ?: return false
    return ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
      PackageManager.PERMISSION_GRANTED ||
      ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) ==
      PackageManager.PERMISSION_GRANTED
  }

  override fun requestLocationPermission(callback: (Result<Boolean>) -> Unit) {
    if (hasLocationPermission()) {
      callback(Result.success(true))
      return
    }
    val currentActivity = activity
    if (currentActivity == null) {
      callback(Result.failure(FlutterError("no_activity", "Plugin is not attached to an activity", null)))
      return
    }
    if (pendingPermissionCallback != null) {
      callback(Result.failure(FlutterError("in_progress", "A permission request is already in progress", null)))
      return
    }
    pendingPermissionCallback = callback
    ActivityCompat.requestPermissions(
      currentActivity,
      arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
      LOCATION_PERMISSION_REQUEST,
    )
  }

  override fun onRequestPermissionsResult(
    requestCode: Int,
    permissions: Array<out String>,
    grantResults: IntArray,
  ): Boolean {
    if (requestCode != LOCATION_PERMISSION_REQUEST) return false
    val granted = grantResults.any { it == PackageManager.PERMISSION_GRANTED }
    pendingPermissionCallback?.invoke(Result.success(granted))
    pendingPermissionCallback = null
    return true
  }

  // ── ActivityAware ─────────────────────────────────────────────

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
    activityLifecycle = FlutterLifecycleAdapter.getActivityLifecycle(binding)
    binding.addRequestPermissionsResultListener(this)
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activity = null
    activityLifecycle = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activity = binding.activity
    activityLifecycle = FlutterLifecycleAdapter.getActivityLifecycle(binding)
    binding.addRequestPermissionsResultListener(this)
  }

  override fun onDetachedFromActivity() {
    activity = null
    activityLifecycle = null
  }
}
