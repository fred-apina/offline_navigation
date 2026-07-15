package io.github.fredapina.offline_navigation

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import app.organicmaps.sdk.OrganicMaps
import app.organicmaps.sdk.location.AndroidNativeProvider
import app.organicmaps.sdk.location.BaseLocationProvider
import app.organicmaps.sdk.location.LocationHelper
import app.organicmaps.sdk.location.LocationProviderFactory
import app.organicmaps.sdk.settings.UnitLocale
import app.organicmaps.sdk.util.ConnectionState

/**
 * Owns the single Organic Maps engine instance for the host application.
 *
 * The Organic Maps native core is a process-wide singleton, so this object
 * initializes it lazily on the main thread and queues callers arriving while
 * initialization is in flight.
 */
object OmEngine {
  private const val TAG = "OmEngine"

  private enum class State { IDLE, INITIALIZING, READY }

  private var organicMaps: OrganicMaps? = null
  private var state = State.IDLE
  private val onReadyQueue = mutableListOf<() -> Unit>()
  private val mainHandler = Handler(Looper.getMainLooper())

  val isReady: Boolean
    get() = state == State.READY

  val locationHelper: LocationHelper
    get() = requireNotNull(organicMaps) { "OmEngine is not initialized" }.locationHelper

  fun initialize(context: Context, onReady: () -> Unit, onError: (Throwable) -> Unit) {
    mainHandler.post {
      when (state) {
        State.READY -> onReady()
        State.INITIALIZING -> onReadyQueue.add(onReady)
        State.IDLE -> {
          state = State.INITIALIZING
          onReadyQueue.add(onReady)
          try {
            val om = organicMaps
              ?: createEngine(context.applicationContext).also { organicMaps = it }
            om.init { mainHandler.post { becomeReady() } }
          } catch (e: Throwable) {
            Log.e(TAG, "Organic Maps engine initialization failed", e)
            state = State.IDLE
            onReadyQueue.clear()
            onError(e)
          }
        }
      }
    }
  }

  private fun becomeReady() {
    Log.i(TAG, "Organic Maps engine is ready")
    // Initialize the measurement system. This also configures the turn-notification
    // units; without it the engine hard-aborts (CHECK in ComputeTurnDistanceM) the
    // first time turn notifications are generated during guidance. MwmActivity does
    // this at startup; since we bypass it, we must do it ourselves.
    try {
      UnitLocale.initializeCurrentUnits()
    } catch (e: Throwable) {
      Log.w(TAG, "UnitLocale init failed: ${e.message}")
    }
    state = State.READY
    val callbacks = onReadyQueue.toList()
    onReadyQueue.clear()
    callbacks.forEach { it() }
  }

  private fun createEngine(context: Context): OrganicMaps {
    ConnectionState.INSTANCE.initialize(context)
    val info = context.packageManager.getPackageInfo(context.packageName, 0)
    val versionCode =
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode.toInt()
      else @Suppress("DEPRECATION") info.versionCode
    return OrganicMaps(
      context,
      /* flavor = */ "",
      /* applicationId = */ context.packageName,
      versionCode,
      /* versionName = */ info.versionName ?: "0.0.0",
      /* fileProviderAuthority = */ "${context.packageName}.offline_navigation.provider",
      NativeLocationProviderFactory(),
    )
  }

  /** Always uses Android's own location stack; no Google Play Services dependency. */
  private class NativeLocationProviderFactory : LocationProviderFactory {
    override fun isGoogleLocationAvailable(context: Context) = false

    override fun getProvider(
      context: Context,
      listener: BaseLocationProvider.Listener,
    ): BaseLocationProvider = AndroidNativeProvider(context, listener)
  }
}
