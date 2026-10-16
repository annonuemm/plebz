package com.edde746.plezy.homerows

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.MatrixCursor
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.ParcelFileDescriptor
import java.io.File
import java.io.FileNotFoundException
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ConcurrentHashMap

/**
 * The app's home rows for a launcher signed with its key: `content://app.plebz.homerows/rows` is
 * one row with a `json` column holding the latest snapshot, `content://app.plebz.homerows/art/<key>`
 * the artwork it names.
 *
 * Reachable only with `app.plebz.permission.HOME_ROWS`, a signature permission: apps signed with
 * the app's own key hold it without asking, every other app is refused by the system before this
 * provider sees the call. It answers from what the app last wrote, so a launcher can read it while
 * the app itself is not running.
 */
class HomeRowsProvider : ContentProvider() {
  companion object {
    const val AUTHORITY = "app.plebz.homerows"
    val ROWS_URI: Uri = Uri.parse("content://$AUTHORITY/rows")
    private const val MAX_ART_BYTES = 4 * 1024 * 1024
    private const val TIMEOUT_MS = 10_000
    private const val MAX_REDIRECTS = 3

    internal fun store(context: Context) =
      HomeRowsStore(File(context.noBackupFilesDir, "home_rows"), File(context.cacheDir, "home_rows_art"))
  }

  private val fetchLocks = ConcurrentHashMap<String, Any>()

  override fun onCreate(): Boolean = context != null

  override fun query(
    uri: Uri,
    projection: Array<out String>?,
    selection: String?,
    selectionArgs: Array<out String>?,
    sortOrder: String?
  ): Cursor? {
    val context = context ?: return null
    if (uri.pathSegments != listOf("rows")) return null
    val cursor = MatrixCursor(arrayOf("json"))
    store(context).snapshot()?.let { cursor.addRow(arrayOf(it)) }
    cursor.setNotificationUri(context.contentResolver, ROWS_URI)
    return cursor
  }

  override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
    if (mode != "r") throw SecurityException("Home rows are read-only")
    val segments = uri.pathSegments
    if (segments.size != 2 || segments[0] != "art") throw FileNotFoundException(uri.toString())
    val key = segments[1]
    val store = store(context ?: throw FileNotFoundException(uri.toString()))
    val file = store.artFile(key) ?: throw FileNotFoundException(uri.toString())
    if (!file.isFile) {
      synchronized(fetchLocks.getOrPut(key) { Any() }) {
        if (!file.isFile) fetch(store.source(key) ?: throw FileNotFoundException(uri.toString()), file)
      }
    }
    return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
  }

  override fun getType(uri: Uri): String? = when (uri.pathSegments.firstOrNull()) {
    "rows" -> "vnd.android.cursor.item/vnd.app.plebz.homerows"
    "art" -> "image/*"
    else -> null
  }

  override fun insert(uri: Uri, values: ContentValues?): Uri? = null
  override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0
  override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

  /** Downloads [address] into [target], keeping it only when it is a whole, decodable image. */
  private fun fetch(address: String, target: File) {
    target.parentFile?.mkdirs()
    val staging = File(target.parentFile, "${target.name}.tmp")
    try {
      var url = URL(address)
      var redirects = 0
      while (true) {
        val connection = url.openConnection() as HttpURLConnection
        connection.connectTimeout = TIMEOUT_MS
        connection.readTimeout = TIMEOUT_MS
        connection.instanceFollowRedirects = false
        try {
          val status = connection.responseCode
          if (status in 300..399 && redirects < MAX_REDIRECTS) {
            val location = connection.getHeaderField("Location") ?: throw FileNotFoundException(address)
            url = URL(url, location)
            redirects++
            continue
          }
          if (status != HttpURLConnection.HTTP_OK) throw FileNotFoundException("HTTP $status")
          connection.inputStream.use { input ->
            staging.outputStream().use { output ->
              val buffer = ByteArray(16 * 1024)
              var total = 0
              while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                total += read
                if (total > MAX_ART_BYTES) throw FileNotFoundException("Artwork too large")
                output.write(buffer, 0, read)
              }
            }
          }
        } finally {
          connection.disconnect()
        }
        break
      }
      val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
      BitmapFactory.decodeFile(staging.path, bounds)
      if (bounds.outWidth <= 0 || bounds.outHeight <= 0) throw FileNotFoundException("Not an image")
      if (!staging.renameTo(target)) throw FileNotFoundException("Could not keep artwork")
    } catch (e: FileNotFoundException) {
      throw e
    } catch (e: Exception) {
      throw FileNotFoundException(e.message ?: "Artwork unavailable")
    } finally {
      staging.delete()
    }
  }
}
