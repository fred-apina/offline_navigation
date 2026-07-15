package io.github.fredapina.offline_navigation

import android.app.Activity
import android.view.WindowManager
import androidx.lifecycle.Lifecycle
import app.organicmaps.sdk.Framework
import app.organicmaps.sdk.downloader.MapManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.embedding.engine.plugins.lifecycle.HiddenLifecycleReference
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Entry point of the offline_navigation plugin.
 *
 * Registers the map platform view, the engine method channel, and the
 * download/guidance event channels.
 */
class OfflineNavigationPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {
  companion object {
    const val ENGINE_CHANNEL = "offline_navigation/engine"
    const val DOWNLOADS_CHANNEL = "offline_navigation/downloads"
    const val GUIDANCE_CHANNEL = "offline_navigation/guidance"
    const val MAP_VIEW_TYPE = "offline_navigation/map_view"
  }

  private lateinit var channel: MethodChannel
  private var downloadsChannel: EventChannel? = null
  private var guidanceChannel: EventChannel? = null
  private var flutterBinding: FlutterPlugin.FlutterPluginBinding? = null

  /** Lifecycle of the host activity; null while detached. */
  var activityLifecycle: Lifecycle? = null
    private set

  private var activity: Activity? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    flutterBinding = binding
    channel = MethodChannel(binding.binaryMessenger, ENGINE_CHANNEL)
    channel.setMethodCallHandler(this)
    downloadsChannel = EventChannel(binding.binaryMessenger, DOWNLOADS_CHANNEL).apply {
      setStreamHandler(DownloadStreamHandler())
    }
    guidanceChannel = EventChannel(binding.binaryMessenger, GUIDANCE_CHANNEL).apply {
      setStreamHandler(GuidanceStreamHandler())
    }
    binding.platformViewRegistry.registerViewFactory(MAP_VIEW_TYPE, OmMapViewFactory(this))
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    downloadsChannel?.setStreamHandler(null)
    guidanceChannel?.setStreamHandler(null)
    flutterBinding = null
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "initialize" -> {
        val context = flutterBinding?.applicationContext
        if (context == null) {
          result.error("no_context", "Plugin is not attached to a Flutter engine", null)
          return
        }
        OmEngine.initialize(
          context,
          onReady = { result.success(true) },
          onError = { e -> result.error("init_failed", e.message, null) },
        )
      }
      "isInitialized" -> result.success(OmEngine.isReady)

      // ── Map data ────────────────────────────────────────────
      "resolveCountry" -> {
        val lat = call.argument<Double>("lat")
        val lon = call.argument<Double>("lon")
        if (lat == null || lon == null) {
          result.error("bad_args", "lat and lon are required", null)
          return
        }
        result.success(MapManager.nativeFindCountry(lat, lon))
      }
      "getCountryStatus" -> {
        val countryId = call.argument<String>("countryId")
        if (countryId.isNullOrEmpty()) {
          result.error("bad_args", "countryId is required", null)
          return
        }
        result.success(MapManager.nativeGetStatus(countryId))
      }
      "startDownload" -> {
        val ids = call.argument<List<String>>("countryIds").orEmpty()
        if (ids.isEmpty()) {
          result.error("bad_args", "countryIds is required", null)
          return
        }
        MapManager.startDownload(*ids.toTypedArray())
        result.success(true)
      }
      "cancelDownload" -> {
        call.argument<List<String>>("countryIds").orEmpty().forEach { MapManager.nativeCancel(it) }
        result.success(true)
      }

      // ── Routing ─────────────────────────────────────────────
      "buildRoute" -> {
        val startLat = call.argument<Double>("startLat")
        val startLon = call.argument<Double>("startLon")
        val destLat = call.argument<Double>("destLat")
        val destLon = call.argument<Double>("destLon")
        if (startLat == null || startLon == null || destLat == null || destLon == null) {
          result.error("bad_args", "startLat/startLon/destLat/destLon are required", null)
          return
        }
        NavigationSession.buildRoute(
          startLat, startLon, call.argument<String>("startName") ?: "Start",
          destLat, destLon, call.argument<String>("destName") ?: "Destination",
          call.argument<String>("travelMode") ?: "drive",
          result,
        )
      }
      "startGuidance" -> NavigationSession.startGuidance(
        simulate = call.argument<Boolean>("simulate") ?: false,
        voice = call.argument<Boolean>("voice") ?: true,
        result = result,
      )
      "stopGuidance" -> {
        NavigationSession.stopGuidance()
        result.success(true)
      }
      "closeRouting" -> {
        NavigationSession.closeRouting()
        result.success(true)
      }
      "setViewport" -> {
        val lat = call.argument<Double>("lat")
        val lon = call.argument<Double>("lon")
        val zoom = call.argument<Int>("zoom") ?: 12
        if (lat == null || lon == null) {
          result.error("bad_args", "lat and lon are required", null)
          return
        }
        Framework.nativeSetViewportCenter(lat, lon, zoom)
        result.success(true)
      }
      "setKeepScreenOn" -> {
        val on = call.argument<Boolean>("on") ?: false
        activity?.window?.let { window ->
          if (on) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
          else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        result.success(true)
      }
      else -> result.notImplemented()
    }
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
    activityLifecycle = (binding.lifecycle as HiddenLifecycleReference).lifecycle
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activity = null
    activityLifecycle = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activity = binding.activity
    activityLifecycle = (binding.lifecycle as HiddenLifecycleReference).lifecycle
  }

  override fun onDetachedFromActivity() {
    activity = null
    activityLifecycle = null
  }
}
