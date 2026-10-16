package com.edde746.plezy.homerows

import android.content.Context
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
 */
class HomeRowsPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
  private companion object {
    const val TAG = "HomeRowsPlugin"
    const val CHANNEL = "app.plebz/home_rows"
  }

  private var channel: MethodChannel? = null
  private var context: Context? = null
  private var executor: ExecutorService? = null
  private val main = Handler(Looper.getMainLooper())

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    executor = Executors.newSingleThreadExecutor()
    channel = MethodChannel(binding.binaryMessenger, CHANNEL).also { it.setMethodCallHandler(this) }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
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
