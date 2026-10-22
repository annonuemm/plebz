package com.edde746.plezy

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/**
 * Plebz: guide reminders as system notifications on phones and tablets.
 *
 * Dart owns the reminders; it hands over the full list whenever it changes ([replaceAll]), and
 * this side keeps it in its own preferences so an alarm can still be posted after the process has
 * gone, and set again after a reboot. While the app is on screen a firing alarm posts nothing: the
 * app shows its own reminder there. A posted one is remembered as fired, so the app does not show
 * it a second time when it comes back ([takeFired]); a tap on it opens the app on the reminder
 * ([takeOpened]).
 */
internal object ProgramReminderAlarms {
  private const val TAG = "ProgramReminders"
  private const val PREFS = "plebz_program_reminders"
  private const val KEY_SCHEDULED = "scheduled"
  private const val KEY_FIRED = "fired"
  private const val KEY_CHANNEL_NAME = "channel_name"
  const val CHANNEL_ID = "program_reminders"
  const val ACTION_FIRE = "app.plebz.action.PROGRAM_REMINDER"
  const val ACTION_OPEN = "app.plebz.action.OPEN_PROGRAM_REMINDER"
  const val EXTRA_ID = "plebz.program_reminder_id"

  /** Set by PlezyActivity between onStart and onStop. */
  @Volatile
  var appInForeground = false

  data class Entry(
    val id: String,
    val atMillis: Long,
    val endsAtMillis: Long,
    val title: String,
    val text: String,
    val action: String
  ) {
    fun toJson(): JSONObject = JSONObject()
      .put("id", id)
      .put("at", atMillis)
      .put("endsAt", endsAtMillis)
      .put("title", title)
      .put("text", text)
      .put("action", action)

    companion object {
      fun fromJson(json: JSONObject): Entry? {
        val id = json.optString("id").ifEmpty { return null }
        return Entry(
          id = id,
          atMillis = json.optLong("at"),
          endsAtMillis = json.optLong("endsAt"),
          title = json.optString("title"),
          text = json.optString("text"),
          action = json.optString("action")
        )
      }
    }
  }

  /** The whole list from Dart: alarms for what is new, none any more for what is gone. */
  fun replaceAll(context: Context, entries: List<Entry>, channelName: String?, now: Long = System.currentTimeMillis()) {
    val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    if (!channelName.isNullOrEmpty()) prefs.edit().putString(KEY_CHANNEL_NAME, channelName).apply()
    val wanted = entries.filter { it.endsAtMillis > now }
    val wantedIds = wanted.map { it.id }.toSet()
    for (old in stored(context)) {
      if (old.id !in wantedIds) cancelAlarm(context, old.id)
    }
    store(context, wanted)
    for (entry in wanted) scheduleAlarm(context, entry, now)
  }

  /** After a reboot or an update: Android has dropped every alarm. */
  fun rescheduleStored(context: Context, now: Long = System.currentTimeMillis()) {
    val kept = stored(context).filter { it.endsAtMillis > now }
    store(context, kept)
    for (entry in kept) scheduleAlarm(context, entry, now)
  }

  fun onAlarm(context: Context, id: String) {
    val entry = stored(context).firstOrNull { it.id == id } ?: return
    store(context, stored(context).filter { it.id != id })
    // On screen the app shows the reminder itself, in its own window.
    if (appInForeground) return
    if (!post(context, entry)) return
    val fired = firedIds(context) + id
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
      .putString(KEY_FIRED, JSONArray(fired.toList()).toString())
      .apply()
  }

  /** The reminders posted as notifications since the app last asked; it drops them. */
  fun takeFired(context: Context): List<String> {
    val fired = firedIds(context).toList()
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(KEY_FIRED).apply()
    return fired
  }

  fun cancelNotification(context: Context, id: String) {
    NotificationManagerCompat.from(context).cancel(TAG, id.hashCode())
  }

  internal fun stored(context: Context): List<Entry> {
    val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_SCHEDULED, null) ?: return emptyList()
    return try {
      val array = JSONArray(raw)
      (0 until array.length()).mapNotNull { Entry.fromJson(array.getJSONObject(it)) }
    } catch (e: Exception) {
      Log.w(TAG, "Stored reminders unreadable", e)
      emptyList()
    }
  }

  private fun store(context: Context, entries: List<Entry>) {
    val array = JSONArray()
    for (entry in entries) array.put(entry.toJson())
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY_SCHEDULED, array.toString()).apply()
  }

  private fun firedIds(context: Context): Set<String> {
    val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_FIRED, null) ?: return emptySet()
    return try {
      val array = JSONArray(raw)
      (0 until array.length()).map { array.getString(it) }.toSet()
    } catch (_: Exception) {
      emptySet()
    }
  }

  private fun alarmIntent(context: Context, id: String): PendingIntent = PendingIntent.getBroadcast(
    context,
    id.hashCode(),
    Intent(context, ProgramReminderReceiver::class.java).setAction(ACTION_FIRE).putExtra(EXTRA_ID, id),
    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
  )

  private fun scheduleAlarm(context: Context, entry: Entry, now: Long) {
    val alarms = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
    // A reminder already due fires at once: its programme is still on.
    val at = maxOf(entry.atMillis, now)
    val pending = alarmIntent(context, entry.id)
    // To the minute where Android allows it (USE_EXACT_ALARM from Android 13, granted with the
    // install), otherwise as close as it lets an app without the right come.
    val exact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarms.canScheduleExactAlarms()
    try {
      if (exact) {
        alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
      } else {
        alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
      }
    } catch (e: SecurityException) {
      Log.w(TAG, "Exact alarm refused; scheduling an inexact one", e)
      alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
    }
  }

  private fun cancelAlarm(context: Context, id: String) {
    val alarms = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
    alarms.cancel(alarmIntent(context, id))
  }

  private fun ensureChannel(context: Context) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
    val name = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_CHANNEL_NAME, null) ?: "Reminders"
    val existing = manager.getNotificationChannel(CHANNEL_ID)
    if (existing != null) {
      if (existing.name != name) existing.name = name
      manager.createNotificationChannel(existing)
      return
    }
    manager.createNotificationChannel(NotificationChannel(CHANNEL_ID, name, NotificationManager.IMPORTANCE_HIGH))
  }

  /** False where notifications are off for the app: then nothing was shown. */
  private fun post(context: Context, entry: Entry): Boolean {
    val notifications = NotificationManagerCompat.from(context)
    if (!notifications.areNotificationsEnabled()) return false
    ensureChannel(context)
    val open = PendingIntent.getActivity(
      context,
      entry.id.hashCode(),
      Intent(context, PlezyActivity::class.java)
        .setAction(ACTION_OPEN)
        .putExtra(EXTRA_ID, entry.id)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )
    val builder = NotificationCompat.Builder(context, CHANNEL_ID)
      .setSmallIcon(R.drawable.ic_stat_notification)
      .setContentTitle(entry.title)
      .setContentText(entry.text)
      .setCategory(NotificationCompat.CATEGORY_REMINDER)
      .setPriority(NotificationCompat.PRIORITY_HIGH)
      .setAutoCancel(true)
      .setContentIntent(open)
    if (entry.action.isNotEmpty()) builder.addAction(0, entry.action, open)
    // Gone once the programme is over: there is nothing left to switch to.
    val remaining = entry.endsAtMillis - System.currentTimeMillis()
    if (remaining > 0) builder.setTimeoutAfter(remaining)
    return try {
      notifications.notify(TAG, entry.id.hashCode(), builder.build())
      true
    } catch (e: SecurityException) {
      Log.w(TAG, "Notification refused", e)
      false
    }
  }
}

/** The alarm firing, and Android having dropped every alarm (boot, app update). */
class ProgramReminderReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    when (intent.action) {
      ProgramReminderAlarms.ACTION_FIRE -> {
        val id = intent.getStringExtra(ProgramReminderAlarms.EXTRA_ID) ?: return
        ProgramReminderAlarms.onAlarm(context, id)
      }
      Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> ProgramReminderAlarms.rescheduleStored(context)
    }
  }
}

/** Dart's side of the reminders: the list, what was posted, and which one was tapped. */
internal class ProgramReminderChannel(private val context: Context) {
  companion object {
    private const val CHANNEL = "com.plebz/program_reminders"
  }

  private var channel: MethodChannel? = null

  /** The reminder a tapped notification opened the app on, until Dart takes it. */
  private var opened: String? = null

  fun attach(messenger: BinaryMessenger) {
    channel = MethodChannel(messenger, CHANNEL).also { it.setMethodCallHandler(::onMethodCall) }
  }

  /** A notification's tap reaching the activity, at launch or while it runs. */
  fun handleIntent(intent: Intent?) {
    if (intent?.action != ProgramReminderAlarms.ACTION_OPEN) return
    val id = intent.getStringExtra(ProgramReminderAlarms.EXTRA_ID) ?: return
    opened = id
    ProgramReminderAlarms.cancelNotification(context, id)
    channel?.invokeMethod("opened", null)
  }

  fun takeOpened(): String? {
    val id = opened
    opened = null
    return id
  }

  private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "replaceAll" -> {
        val raw = call.argument<List<Map<String, Any?>>>("entries").orEmpty()
        val entries = raw.mapNotNull { map ->
          val id = map["id"] as? String ?: return@mapNotNull null
          ProgramReminderAlarms.Entry(
            id = id,
            atMillis = (map["at"] as? Number)?.toLong() ?: return@mapNotNull null,
            endsAtMillis = (map["endsAt"] as? Number)?.toLong() ?: return@mapNotNull null,
            title = map["title"] as? String ?: "",
            text = map["text"] as? String ?: "",
            action = map["action"] as? String ?: ""
          )
        }
        ProgramReminderAlarms.replaceAll(context, entries, call.argument<String>("channelName"))
        result.success(null)
      }
      "takeFired" -> result.success(ProgramReminderAlarms.takeFired(context))
      "takeOpened" -> result.success(takeOpened())
      else -> result.notImplemented()
    }
  }
}
