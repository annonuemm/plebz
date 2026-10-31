package com.edde746.plezy.homerows

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Takes the home rows from Dart (Plebz, `HomeRows`) and keeps them for [HomeRowsProvider]:
 * `publish` replaces the snapshot and its artwork sources, `clear` empties both. Each change is
 * announced on [HomeRowsProvider.ROWS_URI], so a launcher watching it refreshes at once.
 *
 * While the engine runs it also takes a launcher's call for fresh rows ([ACTION_REFRESH], sent
 * only by apps holding the rows' signature permission) and passes it to Dart as `refresh`. The
 * receiver is registered here, not in the manifest, so the call never starts the app.
 */
class HomeRowsPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
  private companion object {
    const val TAG = "HomeRowsPlugin"
    const val CHANNEL = "app.plebz/home_rows"
    const val ACTION_REFRESH = "app.plebz.homerows.REFRESH"
    const val PERMISSION = "app.plebz.permission.HOME_ROWS"
  }

  private var requests: BroadcastReceiver? = null

  private var channel: MethodChannel? = null
  private var context: Context? = null
  private var executor: ExecutorService? = null
  private val main = Handler(Looper.getMainLooper())

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    executor = Executors.newSingleThreadExecutor()
    channel = MethodChannel(binding.binaryMessenger, CHANNEL).also { it.setMethodCallHandler(this) }
    val receiver = object : BroadcastReceiver() {
      override fun onReceive(context: Context, intent: Intent) {
        channel?.invokeMethod("refresh", null)
      }
    }
    try {
      val filter = IntentFilter(ACTION_REFRESH)
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        binding.applicationContext.registerReceiver(receiver, filter, PERMISSION, main, Context.RECEIVER_EXPORTED)
      } else {
        binding.applicationContext.registerReceiver(receiver, filter, PERMISSION, main)
      }
      requests = receiver
    } catch (e: Exception) {
      Log.w(TAG, "Launcher refresh calls unavailable", e)
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    requests?.let { runCatching { binding.applicationContext.unregisterReceiver(it) } }
    requests = null
    channel?.setMethodCallHandler(null)
    channel = null
    executor?.shutdown()
    executor = null
    context = null
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    val context = context
    val executor = executor
    if (context == null || executor == null) {
      result.success(false)
      return
    }
    when (call.method) {
      "publish" -> {
        val snapshot = call.argument<String>("snapshot")
        val sources = call.argument<Map<String, String>>("sources") ?: emptyMap()
        if (snapshot == null) {
          result.success(false)
          return
        }
        run(executor, result) {
          HomeRowsProvider.store(context).write(snapshot, sources)
          context.contentResolver.notifyChange(HomeRowsProvider.ROWS_URI, null)
        }
      }
      "clear" -> run(executor, result) {
        HomeRowsProvider.store(context).clear()
        context.contentResolver.notifyChange(HomeRowsProvider.ROWS_URI, null)
      }
      else -> result.notImplemented()
    }
  }

  private fun run(executor: ExecutorService, result: MethodChannel.Result, block: () -> Unit) {
    executor.execute {
      val ok = try {
        block()
        true
      } catch (e: Exception) {
        Log.w(TAG, "Home rows update failed", e)
        false
      }
      main.post { result.success(ok) }
    }
  }
}
