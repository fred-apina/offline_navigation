package io.github.fredapina.offline_navigation

import android.util.Log
import app.organicmaps.sdk.DownloadResourcesLegacyActivity

/**
 * Downloads the base world maps (World.mwm / WorldCoasts.mwm) on first run.
 *
 * These files are not bundled in the SDK assets; without them the map is blank
 * outside downloaded countries. The SDK exposes the same headless native API the
 * Organic Maps app drives from its resource-download screen: query missing bytes,
 * then download file after file until ERR_NO_MORE_FILES.
 *
 * Progress is streamed over the shared download event channel with the pseudo
 * country id [BASE_ID].
 */
object ResourceBootstrap {
  /** Pseudo country id used for base-map events on the downloads channel. */
  const val BASE_ID = "__base__"

  private const val TAG = "ResourceBootstrap"

  private var pendingCallback: ((Result<Unit>) -> Unit)? = null
  private var totalBytes: Int = 0

  /** Bytes still missing (0 = base maps present); negative values are engine errors. */
  fun bytesToDownload(): Int = DownloadResourcesLegacyActivity.nativeGetBytesToDownload()

  fun download(callback: (Result<Unit>) -> Unit) {
    if (pendingCallback != null) {
      callback(Result.failure(FlutterError("in_progress", "Base map download already in progress", null)))
      return
    }
    pendingCallback = callback
    totalBytes = bytesToDownload().coerceAtLeast(1)

    val listener = object : DownloadResourcesLegacyActivity.Listener {
      // NOTE: despite the interface's parameter name, JNI passes CUMULATIVE
      // BYTES downloaded, not a percentage (the OM app feeds it to a progress
      // bar whose max is set to the total byte count).
      override fun onProgress(percent: Int) {
        val pct = ((percent.toLong() * 100) / totalBytes).toInt().coerceIn(0, 100)
        DownloadEventBus.send(
          mapOf("countryId" to BASE_ID, "status" to 1, "progress" to pct)
        )
      }

      override fun onFinish(errorCode: Int) {
        if (errorCode == DownloadResourcesLegacyActivity.ERR_DOWNLOAD_SUCCESS) {
          val next = DownloadResourcesLegacyActivity.nativeStartNextFileDownload(this)
          if (next == DownloadResourcesLegacyActivity.ERR_NO_MORE_FILES) complete(0)
          // else: next file started; wait for its callbacks.
        } else {
          complete(errorCode)
        }
      }
    }

    val res = DownloadResourcesLegacyActivity.nativeStartNextFileDownload(listener)
    if (res == DownloadResourcesLegacyActivity.ERR_NO_MORE_FILES) complete(0)
  }

  fun cancel() {
    if (pendingCallback == null) return
    try {
      DownloadResourcesLegacyActivity.nativeCancelCurrentFile()
    } catch (e: Exception) {
      Log.w(TAG, "cancel failed: ${e.message}")
    }
    val pending = pendingCallback
    pendingCallback = null
    pending?.invoke(Result.failure(FlutterError("cancelled", "Base map download cancelled", null)))
  }

  private fun complete(errorCode: Int) {
    val pending = pendingCallback ?: return // cancelled, or a late callback
    pendingCallback = null
    if (errorCode == 0) {
      DownloadEventBus.send(mapOf("countryId" to BASE_ID, "status" to 6, "progress" to 100))
      pending(Result.success(Unit))
    } else {
      Log.w(TAG, "Base map download failed: $errorCode")
      DownloadEventBus.send(mapOf("countryId" to BASE_ID, "status" to 4, "progress" to -1))
      pending(Result.failure(FlutterError("base_map_download_failed", describe(errorCode), errorCode.toLong())))
    }
  }

  private fun describe(errorCode: Int): String = when (errorCode) {
    DownloadResourcesLegacyActivity.ERR_NOT_ENOUGH_FREE_SPACE -> "Not enough free storage space"
    DownloadResourcesLegacyActivity.ERR_STORAGE_DISCONNECTED -> "Storage is not available"
    DownloadResourcesLegacyActivity.ERR_DISK_ERROR -> "Storage error"
    else -> "Could not download the base world map (check your connection)"
  }
}
