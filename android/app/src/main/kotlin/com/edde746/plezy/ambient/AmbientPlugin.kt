package com.edde746.plezy.ambient

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import com.edde746.plezy.homerows.HomeRowsStore
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * The screensaver's side of the app (Plebz, `AmbientFeed` in Dart): `publish` keeps the scenes and
 * their picture sources for [PlebzAmbientDream], `setPaused` hands over the paused title (in memory
 * only — its picture address may carry a server's credentials), and the settings calls lead the
 * viewer to Android's screensaver choice. The dream asks back through [requestResume] when OK is
 * pressed on the pause scene. `showInApp`, `hideInApp` and `setKeepAwake` drive the app's own
 * screensaver ([AmbientInApp]), which says `inAppClosed` when a key has ended it.
 */
class AmbientPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {
  companion object {
    private const val TAG = "AmbientPlugin"
    private const val CHANNEL = "app.plebz/ambient"

    @Volatile private var active: MethodChannel? = null
    private val main = Handler(Looper.getMainLooper())

    internal fun store(context: Context) =
      HomeRowsStore(File(context.noBackupFilesDir, "ambient"), File(context.cacheDir, "ambient_art"))

    /** Asks the app to play the paused title on; does nothing when the app is not running. */
    fun requestResume() {
      main.post { active?.invokeMethod("resume", null) }
    }

    private fun dreamSettings() = Intent(Settings.ACTION_DREAM_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
  }

  /** The paused title, while the player holds one. */
  internal object State {
    @Volatile var pause: AmbientPause? = null
  }

  private var channel: MethodChannel? = null
  private var context: Context? = null
  private var executor: ExecutorService? = null
  private var inApp: AmbientInApp? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    executor = Executors.newSingleThreadExecutor()
    channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
      it.setMethodCallHandler(this)
      active = it
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel?.setMethodCallHandler(null)
    if (active === channel) active = null
    channel = null
    State.pause = null
    executor?.shutdown()
    executor = null
    context = null
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    inApp?.detach()
    inApp = AmbientInApp(binding.activity) { active?.invokeMethod("inAppClosed", null) }.also { it.attach() }
  }

  override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

  override fun onDetachedFromActivity() {
    inApp?.detach()
    inApp = null
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    val context = context
    if (context == null) {
      result.success(false)
      return
    }
    when (call.method) {
      "publish" -> {
        val snapshot = call.argument<String>("snapshot")
        val sources = call.argument<Map<String, String>>("sources") ?: emptyMap()
        val executor = executor
        if (snapshot == null || executor == null) {
          result.success(false)
          return
        }
        executor.execute {
          val ok = try {
            store(context).write(snapshot, sources)
            true
          } catch (e: Exception) {
            Log.w(TAG, "Ambient update failed", e)
            false
          }
          main.post { result.success(ok) }
        }
      }
      "setPaused" -> {
        State.pause = AmbientJson.pause(call.arguments as? Map<*, *>)
        result.success(true)
      }
      "canOpenSettings" -> result.success(canOpenSettings(context))
      "openSettings" -> result.success(
        canOpenSettings(context) && try {
          context.startActivity(dreamSettings())
          true
        } catch (e: Exception) {
          Log.w(TAG, "Screensaver settings unavailable", e)
          false
        }
      )
      "showInApp" -> result.success(inApp?.show() ?: false)
      "hideInApp" -> {
        inApp?.hide()
        result.success(true)
      }
      "setKeepAwake" -> {
        inApp?.setKeepAwake(call.argument<Boolean>("on") == true)
        result.success(inApp != null)
      }
      else -> result.notImplemented()
    }
  }

  private fun canOpenSettings(context: Context): Boolean =
    context.packageManager.resolveActivity(dreamSettings(), PackageManager.MATCH_DEFAULT_ONLY) != null
}
