package com.edde746.plezy

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.storage.StorageManager
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Plebz: what choosing a local file needs on Android (fork addition).
 *
 * Many Android TV boxes ship without the system's document picker, so a file
 * there can only be chosen through the app's own browser — which may read the
 * shared storage only with "all files access" (API 30+) or the old storage
 * permission (API 29 and below). The Dart side asks for the picker first and
 * falls back to the browser; this channel answers both questions and opens the
 * grant.
 */
internal class StorageAccessChannel(private val activity: Activity) {
  companion object {
    private const val CHANNEL = "com.plebz/storage_access"
    private const val LEGACY_PERMISSION_REQUEST = 4711
  }

  fun attach(messenger: BinaryMessenger) {
    MethodChannel(messenger, CHANNEL).setMethodCallHandler(::onMethodCall)
  }

  private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "hasDocumentPicker" -> result.success(hasDocumentPicker())
      "hasFileAccess" -> result.success(hasFileAccess())
      "requestFileAccess" -> result.success(requestFileAccess())
      "storageRoots" -> result.success(storageRoots())
      else -> result.notImplemented()
    }
  }

  private fun hasDocumentPicker(): Boolean {
    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*")
    return intent.resolveActivity(activity.packageManager) != null
  }

  private fun hasFileAccess(): Boolean =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
      Environment.isExternalStorageManager()
    } else {
      activity.checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
    }

  /**
   * Opens the grant. False when this box has no screen for it — some Android
   * TV builds leave the "all files access" page out, and then only adb can
   * grant it.
   */
  private fun requestFileAccess(): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
      activity.requestPermissions(arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE), LEGACY_PERMISSION_REQUEST)
      return true
    }
    val forThisApp = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
      .setData(Uri.parse("package:${activity.packageName}"))
    val forAll = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
    for (intent in listOf(forThisApp, forAll)) {
      if (intent.resolveActivity(activity.packageManager) == null) continue
      return try {
        activity.startActivity(intent)
        true
      } catch (_: Exception) {
        false
      }
    }
    return false
  }

  /** The mounted volumes' roots: internal shared storage first, then cards and USB sticks. */
  private fun storageRoots(): List<Map<String, Any>> {
    val manager = activity.getSystemService(Context.STORAGE_SERVICE) as StorageManager
    val roots = mutableListOf<Map<String, Any>>()
    val seen = mutableSetOf<String>()
    for (volume in manager.storageVolumes) {
      if (volume.state != Environment.MEDIA_MOUNTED && volume.state != Environment.MEDIA_MOUNTED_READ_ONLY) continue
      val directory = volumeDirectory(volume) ?: continue
      if (!seen.add(directory.absolutePath)) continue
      roots.add(
        mapOf(
          "path" to directory.absolutePath,
          "label" to (volume.getDescription(activity) ?: directory.name),
          "removable" to volume.isRemovable
        )
      )
    }
    return roots
  }

  private fun volumeDirectory(volume: android.os.storage.StorageVolume): File? {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) return volume.directory
    // Before API 30 the root is read off the app's own folder on that volume:
    // <root>/Android/data/<package>/files.
    if (volume.isPrimary) return Environment.getExternalStorageDirectory()
    val uuid = volume.uuid ?: return null
    return File("/storage/$uuid").takeIf { it.exists() }
  }
}
