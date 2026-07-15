package io.github.fredapina.offline_navigation

import android.os.Handler
import android.os.Looper
import app.organicmaps.sdk.downloader.MapManager
import io.flutter.plugin.common.EventChannel

/**
 * Shared sink for download-related events. Fed both by the native storage
 * callbacks (country downloads) and by [ResourceBootstrap] (base world maps).
 * Event shape: {countryId, status, progress, errorCode?, localSize?, remoteSize?}
 */
object DownloadEventBus {
  private val mainHandler = Handler(Looper.getMainLooper())

  @Volatile
  var sink: EventChannel.EventSink? = null

  fun send(event: Map<String, Any?>) {
    mainHandler.post { sink?.success(event) }
  }
}

/** Streams map download status/progress events from the native storage to Flutter. */
class DownloadStreamHandler : EventChannel.StreamHandler {
  private var subscriptionSlot: Int = -1

  private val storageCallback = object : MapManager.StorageCallback {
    override fun onStatusChanged(data: MutableList<MapManager.StorageCallbackData>) {
      // NOTE: Do not call MapManager.nativeGetOverallProgress() here. It hard-aborts
      // (native CHECK) when given a group node (e.g. "Switzerland" with many child maps),
      // and status changes fire for ancestor groups too. Byte progress comes from
      // onProgress() instead; here we only report the status transition. progress = -1
      // is a sentinel meaning "no progress info in this event".
      for (item in data) {
        DownloadEventBus.send(
          mapOf(
            "countryId" to item.countryId,
            "status" to item.newStatus,
            "errorCode" to item.errorCode,
            "progress" to -1,
          )
        )
      }
    }

    override fun onProgress(countryId: String, localSize: Long, remoteSize: Long) {
      val progress = if (remoteSize > 0) ((localSize * 100.0) / remoteSize).toInt() else 0
      DownloadEventBus.send(
        mapOf(
          "countryId" to countryId,
          "status" to 1, // in progress
          "progress" to progress,
          "localSize" to localSize,
          "remoteSize" to remoteSize,
        )
      )
    }
  }

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    DownloadEventBus.sink = events
    try {
      subscriptionSlot = MapManager.nativeSubscribe(storageCallback)
    } catch (e: Exception) {
      events?.error("subscribe_error", "Failed to subscribe to download progress: ${e.message}", null)
    }
  }

  override fun onCancel(arguments: Any?) {
    if (subscriptionSlot >= 0) {
      try {
        MapManager.nativeUnsubscribe(subscriptionSlot)
      } catch (_: Exception) {}
      subscriptionSlot = -1
    }
    DownloadEventBus.sink = null
  }
}

/** Hands the guidance event sink to [NavigationSession]. */
class GuidanceStreamHandler : EventChannel.StreamHandler {
  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    NavigationSession.guidanceSink = events
  }

  override fun onCancel(arguments: Any?) {
    NavigationSession.guidanceSink = null
  }
}
