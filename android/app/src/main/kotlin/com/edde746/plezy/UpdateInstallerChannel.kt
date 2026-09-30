package com.edde746.plezy

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Plebz: hands a downloaded update to Android's own installer.
 *
 * An app installed by hand cannot update itself silently; the installer asks the viewer once per
 * update, and before that Android wants Plebz allowed to install apps at all ("install unknown
 * apps"). This channel answers whether that is allowed, opens the switch when it is not, and
 * starts the installer on the APK. Android checks the signature itself: an APK not signed with
 * the installed app's key is refused, whatever the download claimed.
 */
internal class UpdateInstallerChannel(private val activity: Activity) {
  companion object {
    private const val CHANNEL = "com.plebz/update_installer"
    private const val APK_MIME = "application/vnd.android.package-archive"
  }

  fun attach(messenger: BinaryMessenger) {
    MethodChannel(messenger, CHANNEL).setMethodCallHandler(::onMethodCall)
  }

  private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "canInstall" -> result.success(canInstall())
      "openInstallPermission" -> result.success(openInstallPermission())
      "install" -> {
        val path = call.argument<String>("path")
        if (path == null) {
          result.error("NO_PATH", "path is required", null)
        } else {
          result.success(install(File(path)))
        }
      }
      else -> result.notImplemented()
    }
  }

  private fun canInstall(): Boolean =
    Build.VERSION.SDK_INT < Build.VERSION_CODES.O || activity.packageManager.canRequestPackageInstalls()

  /** The per-app "install unknown apps" switch; false where a box has no such screen. */
  private fun openInstallPermission(): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
    return try {
      activity.startActivity(
        Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}"))
      )
      true
    } catch (_: ActivityNotFoundException) {
      false
    }
  }

  private fun install(apk: File): Boolean {
    if (!apk.isFile) return false
    val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.fileprovider", apk)
    val intent = Intent(Intent.ACTION_VIEW).apply {
      setDataAndType(uri, APK_MIME)
      addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    return try {
      activity.startActivity(intent)
      true
    } catch (_: ActivityNotFoundException) {
      false
    }
  }
}
