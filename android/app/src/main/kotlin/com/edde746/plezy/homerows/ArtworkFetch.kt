package com.edde746.plezy.homerows

import android.graphics.BitmapFactory
import java.io.File
import java.io.FileNotFoundException
import java.net.HttpURLConnection
import java.net.URL

/**
 * Fetches artwork the app named by key (Plebz): for [HomeRowsProvider] and for the screensaver
 * (`PlebzAmbientDream`), both of which keep the bytes in the app's own cache.
 */
internal object ArtworkFetch {
  private const val MAX_ART_BYTES = 4 * 1024 * 1024
  private const val TIMEOUT_MS = 10_000
  private const val MAX_REDIRECTS = 3

  /** Downloads [address] into [target], keeping it only when it is a whole, decodable image. */
  fun fetch(address: String, target: File) {
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
