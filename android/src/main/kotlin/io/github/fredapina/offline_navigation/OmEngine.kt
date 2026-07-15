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
import app.organicmaps.sdk.util.StorageUtils

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
            val appContext = context.applicationContext
            selfHealIfPreviousInitCrashed(appContext)
            markInitInFlight(appContext, true)
            val om = organicMaps
              ?: createEngine(appContext).also { organicMaps = it }
            om.init {
              mainHandler.post {
                markInitInFlight(appContext, false)
                becomeReady()
              }
            }
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

  // ── Crash-loop self-heal ────────────────────────────────────────
  //
  // A native abort during engine init (e.g. corrupt persisted state) kills the
  // process before Java can react, so it can't be caught. Instead: set a marker
  // before init and clear it on success. If the marker is still set on the next
  // launch, the previous init died mid-flight — delete the engine's settings
  // file (best-effort) so a corrupt one can't crash us forever. Downloaded maps
  // and host-app files are never touched.

  private const val PREFS_NAME = "offline_navigation_engine"
  private const val KEY_INIT_IN_FLIGHT = "engine_init_in_flight"

  private fun selfHealIfPreviousInitCrashed(context: Context) {
    val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    if (!prefs.getBoolean(KEY_INIT_IN_FLIGHT, false)) return
    Log.w(TAG, "Previous engine init never completed — clearing engine settings (self-heal)")
    try {
      val settings = java.io.File(StorageUtils.getSettingsPath(context), "settings.ini")
      if (settings.exists() && settings.delete()) {
        Log.w(TAG, "Deleted possibly-corrupt ${settings.absolutePath}")
      }
    } catch (e: Exception) {
      Log.w(TAG, "Settings self-heal failed: ${e.message}")
    }
  }

  @Suppress("ApplySharedPref") // must survive an immediate native crash
  private fun markInitInFlight(context: Context, inFlight: Boolean) {
    context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
      .edit().putBoolean(KEY_INIT_IN_FLIGHT, inFlight).commit()
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
