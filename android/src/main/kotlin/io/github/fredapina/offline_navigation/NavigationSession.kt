package io.github.fredapina.offline_navigation

import android.location.Location
import android.os.Handler
import android.os.Looper
import android.util.Log
import app.organicmaps.sdk.Framework
import app.organicmaps.sdk.Router
import app.organicmaps.sdk.location.LocationListener
import app.organicmaps.sdk.routing.ResultCodes
import app.organicmaps.sdk.routing.RouteMarkType
import app.organicmaps.sdk.routing.RoutingInfo
import app.organicmaps.sdk.sound.TtsPlayer
import io.flutter.plugin.common.EventChannel

/**
 * Headless navigation session driving the Organic Maps routing engine.
 *
 * Replaces MwmActivity's routing logic: builds a route between two fixed points,
 * starts/stops turn-by-turn guidance, and pumps [RoutingInfo] snapshots to Flutter
 * over an event channel once per second while guiding.
 */
object NavigationSession {
  private const val TAG = "NavigationSession"
  private const val GUIDANCE_INTERVAL_MS = 1000L

  /**
   * Max distance between simulated route points, in meters. The simulation provider
   * emits one point per second, so this is also the simulated speed in m/s.
   * 15 m/s ≈ 54 km/h — realistic urban driving, and small enough hops that the
   * follow camera animates smoothly instead of triggering zoom-out "fly" arcs.
   */
  private const val SIMULATION_STEP_M = 15.0

  private val mainHandler = Handler(Looper.getMainLooper())

  private var routingListenerAttached = false
  private var pendingBuildCallback: ((Result<WireRouteBuildResult>) -> Unit)? = null

  var guidanceSink: EventChannel.EventSink? = null
  private var guiding = false
  private var voiceEnabled = false
  private var simulationActive = false

  // ── Route building ────────────────────────────────────────────

  fun buildRoute(
    start: WirePoint,
    destination: WirePoint,
    mode: WireTravelMode,
    callback: (Result<WireRouteBuildResult>) -> Unit,
  ) {
    if (pendingBuildCallback != null) {
      callback(Result.failure(FlutterError("build_in_progress", "Another route build is already in progress", null)))
      return
    }
    attachRoutingListener()
    pendingBuildCallback = callback

    Framework.nativeCloseRouting()
    Router.set(parseRouter(mode))
    Framework.nativeAddRoutePoint(
      start.name ?: "Start", "", RouteMarkType.Start, 0, false, start.latitude, start.longitude, true)
    Framework.nativeAddRoutePoint(
      destination.name ?: "Destination", "", RouteMarkType.Finish, 0, false,
      destination.latitude, destination.longitude, true)
    Framework.nativeBuildRoute()
  }

  private fun attachRoutingListener() {
    if (routingListenerAttached) return
    Framework.nativeSetRoutingListener { resultCode, missingMaps ->
      val pending = pendingBuildCallback
      if (pending == null) {
        // No build in flight: this is a mid-guidance rebuild (e.g. the position
        // deviated off route). The rebuild can deactivate the map camera's route
        // following (RoutingManager::OnRemoveRoute) while the session-level follow
        // flag stays set — so a plain FollowRoute would no-op at EnableFollowMode.
        Log.i(TAG, "mid-guidance routing event: code=$resultCode missing=${missingMaps?.size ?: 0}")
        if (guiding && (resultCode == ResultCodes.NO_ERROR || resultCode == ResultCodes.HAS_WARNINGS)) {
          Framework.nativeFollowRoute()
        }
        return@nativeSetRoutingListener
      }
      pendingBuildCallback = null
      when (resultCode) {
        ResultCodes.NO_ERROR, ResultCodes.HAS_WARNINGS -> {
          val info = safeFollowingInfo()
          pending(Result.success(WireRouteBuildResult(
            ok = true,
            cancelled = false,
            errorCode = 0,
            missingMaps = emptyList(),
            distanceText = info?.distToTarget?.mDistanceStr,
            distanceUnits = info?.distToTarget?.mUnits?.name,
            timeSeconds = (info?.totalTimeInSeconds ?: 0).toLong(),
          )))
        }
        else -> pending(Result.success(WireRouteBuildResult(
          ok = false,
          cancelled = false,
          errorCode = resultCode.toLong(),
          missingMaps = missingMaps?.toList() ?: emptyList(),
          timeSeconds = 0,
        )))
      }
    }
    routingListenerAttached = true
  }

  // ── Guidance ──────────────────────────────────────────────────

  fun startGuidance(simulate: Boolean, voice: Boolean, callback: (Result<Unit>) -> Unit) {
    if (!Framework.nativeIsRouteBuilt()) {
      callback(Result.failure(FlutterError("no_route", "No route has been built", null)))
      return
    }
    voiceEnabled = voice
    // Enable/disable spoken turn notifications in the engine to match the request.
    try {
      TtsPlayer.setEnabled(voice)
    } catch (e: Exception) {
      Log.w(TAG, "TtsPlayer.setEnabled failed: ${e.message}")
    }
    // Use a fixed street-level navigation zoom. Auto-zoom scales the camera to the
    // current speed, which zooms far out during route simulation (which runs at
    // unrealistically high speed). A fixed zoom gives a stable follow camera.
    try {
      Framework.nativeSetAutoZoomEnabled(false)
    } catch (e: Exception) {
      Log.w(TAG, "nativeSetAutoZoomEnabled failed: ${e.message}")
    }

    // IMPORTANT: nativeFollowRoute() must run only after the map has its first
    // position fix. If it runs earlier, the first-ever fix resets the my-position
    // mode and keeps the current (wide) zoom — see MyPositionController::
    // OnLocationUpdate's !m_isPositionAssigned branch — leaving the nav camera
    // permanently zoomed out. So: start locations first, then follow on first fix
    // (with a timed fallback: the later fixes' branches recover the camera anyway).
    armFollowTrigger()

    val locationHelper = OmEngine.locationHelper
    try {
      if (simulate) {
        val junctions = Framework.nativeGetRouteJunctionPoints(SIMULATION_STEP_M)
        if (junctions == null || junctions.isEmpty()) {
          disarmFollowTrigger()
          callback(Result.failure(FlutterError("no_route_points", "Could not get route points for simulation", null)))
          return
        }
        locationHelper.startNavigationSimulation(junctions)
        simulationActive = true
      } else {
        locationHelper.start()
      }
    } catch (e: Exception) {
      // e.g. a SecurityException if a required location permission is missing.
      // Leave no armed listener or half-started provider behind.
      disarmFollowTrigger()
      simulationActive = false
      try {
        locationHelper.stop()
      } catch (_: Exception) {}
      callback(Result.failure(FlutterError("guidance_start_failed", e.message, null)))
      return
    }

    guiding = true
    mainHandler.post(guidancePump)
    callback(Result.success(Unit))
  }

  // ── Follow-camera engagement (one-shot) ───────────────────────

  /** Engage anyway if no fix arrives in time; the camera then recovers on the next fix. */
  private const val FOLLOW_FALLBACK_MS = 5000L

  /**
   * Delay between the first fix arriving in Java and engaging the follow camera.
   * The map renderer must have processed the position (m_isPositionAssigned) before
   * ActivateRouting runs, or the first fix resets the my-position mode and the nav
   * zoom is never applied. The renderer picks fixes up within a frame or two; this
   * covers even a slow (software-rendered) frame.
   */
  private const val FOLLOW_ENGAGE_DELAY_MS = 3000L

  private var followArmed = false
  private val followFallback = Runnable { engageFollow() }
  private val firstFixListener = object : LocationListener {
    override fun onLocationUpdated(location: Location) {
      engageFollow()
    }
  }

  private fun armFollowTrigger() {
    if (followArmed) return
    followArmed = true
    // NOTE: addListener replays a saved location synchronously, which is fine —
    // a real position is a real position.
    OmEngine.locationHelper.addListener(firstFixListener)
    mainHandler.postDelayed(followFallback, FOLLOW_FALLBACK_MS)
  }

  private fun disarmFollowTrigger() {
    if (!followArmed) return
    followArmed = false
    mainHandler.removeCallbacks(followFallback)
    try {
      OmEngine.locationHelper.removeListener(firstFixListener)
    } catch (e: Exception) {
      Log.w(TAG, "removeListener failed: ${e.message}")
    }
  }

  private fun engageFollow() {
    if (!followArmed) return
    disarmFollowTrigger()
    mainHandler.postDelayed({
      if (!guiding) return@postDelayed
      // Plain FollowRoute, exactly once, after the renderer has the position.
      // Do NOT toggle nativeDisableFollowing() first: that flips the session to
      // RouteNoFollowing, which stops route matching entirely (frozen ETA/turns).
      Framework.nativeFollowRoute()
    }, FOLLOW_ENGAGE_DELAY_MS)
  }

  fun stopGuidance() {
    guiding = false
    disarmFollowTrigger()
    mainHandler.removeCallbacks(guidancePump)
    try {
      val locationHelper = OmEngine.locationHelper
      if (simulationActive) {
        simulationActive = false
        // NOTE: this restores AND RESTARTS the pre-simulation location provider.
        locationHelper.stopNavigationSimulation()
      }
      // Stop all providers outside guidance. A leftover provider keeps feeding
      // positions (e.g. the emulator's default far-away location) into the routing
      // session; a position far off a built route triggers a rebuild from there,
      // which can fail and silently REMOVE the route — breaking the next
      // "Start navigation" with no_route.
      locationHelper.stop()
    } catch (e: Exception) {
      Log.w(TAG, "stopping location providers failed: ${e.message}")
    }
    Framework.nativeDisableFollowing()
  }

  fun closeRouting() {
    // A build may still be in flight (e.g. the page was closed while a large
    // region was calculating). Complete it as cancelled so the callback isn't
    // orphaned — an orphaned callback would block every later build with
    // "build_in_progress".
    pendingBuildCallback?.invoke(Result.success(WireRouteBuildResult(
      ok = false,
      cancelled = true,
      errorCode = 0,
      missingMaps = emptyList(),
      timeSeconds = 0,
    )))
    pendingBuildCallback = null
    stopGuidance()
    Framework.nativeCloseRouting()
    Framework.nativeRemoveRoutePoints()
  }

  private val guidancePump = object : Runnable {
    override fun run() {
      if (!guiding) return
      val info = safeFollowingInfo()
      if (info != null) {
        guidanceSink?.success(serialize(info))
        if (voiceEnabled) speakPendingNotifications()
      }
      mainHandler.postDelayed(this, GUIDANCE_INTERVAL_MS)
    }
  }

  private fun speakPendingNotifications() {
    try {
      // Only generate notifications when the TTS engine is fully initialized.
      // Without it the engine's notification locale may be unset, and
      // nativeGenerateNotifications hard-aborts (GetTtsText::GetLocale CHECK).
      if (!TtsPlayer.isEnabled()) return
      val notifications = Framework.nativeGenerateNotifications(false) ?: return
      TtsPlayer.INSTANCE.playTurnNotifications(notifications)
    } catch (e: Exception) {
      Log.w(TAG, "TTS failed: ${e.message}")
    }
  }

  private fun safeFollowingInfo(): RoutingInfo? = try {
    Framework.nativeGetRouteFollowingInfo()
  } catch (e: Exception) {
    Log.w(TAG, "nativeGetRouteFollowingInfo failed: ${e.message}")
    null
  }

  private fun serialize(info: RoutingInfo): Map<String, Any?> = mapOf(
    "distToTarget" to info.distToTarget?.mDistanceStr,
    "distToTargetUnits" to info.distToTarget?.mUnits?.name,
    "distToTurn" to info.distToTurn?.mDistanceStr,
    "distToTurnUnits" to info.distToTurn?.mUnits?.name,
    "currentStreet" to info.currentStreet,
    "nextStreet" to info.nextStreet,
    "timeSeconds" to info.totalTimeInSeconds,
    "completionPercent" to info.completionPercent,
    "carDirection" to info.carDirection?.ordinal,
    "exitNum" to info.exitNum,
    "speedLimitMps" to info.speedLimitMps,
  )

  private fun parseRouter(mode: WireTravelMode): Router = when (mode) {
    WireTravelMode.WALK -> Router.Pedestrian
    WireTravelMode.CYCLE -> Router.Bicycle
    WireTravelMode.DRIVE -> Router.Vehicle
  }
}
