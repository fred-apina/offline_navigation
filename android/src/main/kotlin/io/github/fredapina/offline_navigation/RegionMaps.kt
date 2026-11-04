package io.github.fredapina.offline_navigation

import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.util.Log
import app.organicmaps.sdk.Framework
import app.organicmaps.sdk.downloader.MapManager
import java.io.File
import java.io.IOException
import java.security.MessageDigest
import java.util.concurrent.Executors

/**
 * Installs, lists and removes *region maps*: map files that are not part of the
 * engine's country list (for example an extract of a single national park).
 *
 * Files live next to the engine's own maps, in `<writable dir>/<data version>/<id>.mwm`,
 * and are registered with the running engine, so routing and rendering use
 * them immediately — no engine restart is needed.
 *
 * Threading: engine calls (register/deregister) run on the main thread; hashing and
 * file copies run on a background thread. Callbacks are always invoked on the main thread.
 */
object RegionMaps {
  private const val TAG = "RegionMaps"
  private const val COPY_BUFFER_BYTES = 256 * 1024

  /** Extra free space required on top of the file size when copying, in bytes. */
  private const val FREE_SPACE_MARGIN = 16L * 1024 * 1024

  private val ID_PATTERN = Regex("^[A-Za-z0-9_-]{1,64}$")

  /** Base maps managed by the engine; a region map must never shadow them. */
  private val RESERVED_IDS = setOf("world", "worldcoasts")

  private val io = Executors.newSingleThreadExecutor { runnable ->
    Thread(runnable, "offline_navigation-io").apply { isDaemon = true }
  }
  private val main = Handler(Looper.getMainLooper())

  // ── Paths ─────────────────────────────────────────────────────

  private fun dataVersion(): Long =
    java.text.SimpleDateFormat("yyMMdd", java.util.Locale.ENGLISH).format(Framework.getDataVersion()).toLong()

  /** The engine's maps directory for its data version, created if missing. */
  fun directory(): File {
    requireReady()
    val dir = File(MapManager.nativeGetLocalMapsDirectory(dataVersion()))
    if (!dir.isDirectory && !dir.mkdirs() && !dir.isDirectory) {
      throw FlutterError("io_error", "Cannot create the maps directory ${dir.path}", null)
    }
    return dir
  }

  fun freeSpaceBytes(): Long = StatFs(directory().path).availableBytes

  // ── Queries ───────────────────────────────────────────────────

  fun isInstalled(id: String): Boolean {
    requireReady()
    return isValidId(id) && MapManager.nativeIsLocalMapRegistered(id)
  }

  fun list(): List<WireRegionMap> {
    requireReady()
    val dir = directory()
    return MapManager.nativeGetLocalMaps().sorted().map { name ->
      WireRegionMap(id = name, sizeBytes = File(dir, "$name.mwm").length())
    }
  }

  // ── Install ───────────────────────────────────────────────────

  fun install(
    id: String,
    sourcePath: String,
    sha256: String?,
    moveFile: Boolean,
    replace: Boolean,
    callback: (Result<WireRegionMap>) -> Unit,
  ) {
    fun fail(error: FlutterError) = callback(Result.failure(error))

    val source = File(sourcePath)
    val prepared = try {
      prepareInstall(id, source, replace)
    } catch (e: FlutterError) {
      fail(e)
      return
    }
    val (dir, target) = prepared

    io.execute {
      val placed: Result<Unit> = runCatching {
        sha256?.let { verifyChecksum(source, it) }
        place(source, dir, target, moveFile)
      }
      main.post {
        placed.onFailure { fail(it.asFlutterError()) }
        placed.onSuccess { register(id, dir, target, callback) }
      }
    }
  }

  /** Validates the request and frees the id for a replacement. Main thread. */
  private fun prepareInstall(id: String, source: File, replace: Boolean): Pair<File, File> {
    requireReady()
    validateId(id)
    val dir = directory()
    if (!source.isFile) throw FlutterError("file_not_found", "No such file: ${source.path}", null)

    if (MapManager.nativeIsLocalMapRegistered(id)) {
      if (!replace) throw FlutterError("already_installed", "Region map '$id' is already installed", null)
      // The engine deletes the old file when it deregisters the map. That is
      // only safe to wait for when nothing uses the map right now; otherwise the
      // delayed deletion would hit the new file that takes its place.
      if (!MapManager.nativeDeregisterLocalMap(id)) {
        throw FlutterError("in_use", "Region map '$id' is in use right now; close navigation and retry", null)
      }
    }
    return dir to File(dir, "$id.mwm")
  }

  /** Registers the placed file with the engine. Main thread. */
  private fun register(id: String, dir: File, target: File, callback: (Result<WireRegionMap>) -> Unit) {
    val code = try {
      MapManager.nativeRegisterLocalMap(dir.path, dataVersion(), id)
    } catch (e: Throwable) {
      Log.e(TAG, "nativeRegisterLocalMap failed", e)
      MapManager.LOCAL_MAP_BAD_FILE
    }
    if (code == MapManager.LOCAL_MAP_REGISTERED) {
      callback(Result.success(WireRegionMap(id = id, sizeBytes = target.length())))
      return
    }
    target.delete()
    val error = when (code) {
      MapManager.LOCAL_MAP_ALREADY_REGISTERED ->
        FlutterError("already_installed", "Region map '$id' is already installed", null)
      MapManager.LOCAL_MAP_VERSION_TOO_OLD ->
        FlutterError("version_too_old", "The map file is older than the installed one", null)
      MapManager.LOCAL_MAP_UNSUPPORTED_FORMAT ->
        FlutterError(
          "unsupported_format",
          "The map file was built with a different engine version. Rebuild it with a generator that matches the engine.",
          null,
        )
      MapManager.LOCAL_MAP_FILE_NOT_FOUND -> FlutterError("file_not_found", "The map file disappeared", null)
      MapManager.LOCAL_MAP_RESERVED_NAME ->
        FlutterError("reserved_name", "'$id' is the id of a built-in map region", null)
      else -> FlutterError("bad_file", "The engine could not read the map file", null)
    }
    callback(Result.failure(error))
  }

  // ── Remove ────────────────────────────────────────────────────

  fun remove(id: String, callback: (Result<Unit>) -> Unit) {
    try {
      requireReady()
      validateId(id)
      val target = File(directory(), "$id.mwm")
      // When the map is in use the engine keeps it until the user is done and
      // deletes the file then; for the caller the map is gone either way.
      MapManager.nativeDeregisterLocalMap(id)
      if (!MapManager.nativeIsLocalMapRegistered(id)) {
        // Leftovers of an unregistered or partially installed map.
        listOf(target, File(target.path + ".tmp")).forEach {
          if (it.exists() && !it.delete()) Log.w(TAG, "Could not delete ${it.path}")
        }
      }
      callback(Result.success(Unit))
    } catch (e: FlutterError) {
      callback(Result.failure(e))
    }
  }

  // ── Helpers ───────────────────────────────────────────────────

  private fun requireReady() {
    if (!OmEngine.isReady) throw FlutterError("not_ready", "The map engine is not initialized", null)
  }

  private fun isValidId(id: String) = ID_PATTERN.matches(id) && id.lowercase() !in RESERVED_IDS

  private fun validateId(id: String) {
    if (!ID_PATTERN.matches(id)) {
      throw FlutterError("invalid_id", "A region map id must match [A-Za-z0-9_-]{1,64}", null)
    }
    if (id.lowercase() in RESERVED_IDS) {
      throw FlutterError("reserved_name", "'$id' is reserved for built-in base maps", null)
    }
  }

  private fun verifyChecksum(file: File, expectedHex: String) {
    val digest = MessageDigest.getInstance("SHA-256")
    file.inputStream().buffered(COPY_BUFFER_BYTES).use { input ->
      val buffer = ByteArray(COPY_BUFFER_BYTES)
      while (true) {
        val read = input.read(buffer)
        if (read < 0) break
        digest.update(buffer, 0, read)
      }
    }
    val actual = digest.digest().joinToString("") { "%02x".format(it) }
    if (!actual.equals(expectedHex.trim(), ignoreCase = true)) {
      throw FlutterError("checksum_mismatch", "SHA-256 mismatch for ${file.name}", null)
    }
  }

  /** Puts [source] at [target] atomically: write to `<target>.tmp`, then rename. */
  private fun place(source: File, dir: File, target: File, moveFile: Boolean) {
    // A stale file of an unregistered map (e.g. from an interrupted install).
    if (target.exists() && !target.delete()) throw IOException("Cannot replace ${target.path}")

    if (moveFile && source.renameTo(target)) return // same volume: atomic and free

    if (dir.usableSpace < source.length() + FREE_SPACE_MARGIN) {
      throw FlutterError("not_enough_space", "Not enough free storage space", null)
    }
    val temp = File(target.path + ".tmp")
    try {
      source.inputStream().use { input -> temp.outputStream().use { output -> input.copyTo(output, COPY_BUFFER_BYTES) } }
      if (!temp.renameTo(target)) throw IOException("Cannot rename ${temp.path}")
    } catch (e: Throwable) {
      temp.delete()
      throw e
    }
    if (moveFile) source.delete()
  }

  private fun Throwable.asFlutterError(): FlutterError = when (this) {
    is FlutterError -> this
    else -> FlutterError("io_error", message ?: javaClass.simpleName, null)
  }
}
