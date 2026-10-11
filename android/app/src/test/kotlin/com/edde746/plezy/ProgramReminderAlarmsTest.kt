package com.edde746.plezy

import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf

@RunWith(RobolectricTestRunner::class)
class ProgramReminderAlarmsTest {
  private lateinit var context: Context
  private val now = 1_800_000_000_000L

  private fun entry(id: String, inMinutes: Long, lastsMinutes: Long = 30) = ProgramReminderAlarms.Entry(
    id = id,
    atMillis = now + inMinutes * 60_000,
    endsAtMillis = now + (inMinutes + 1 + lastsMinutes) * 60_000,
    title = "Tagesschau",
    text = "Gleich geht’s los · Das Erste HD · 20:00",
    action = "Umschalten"
  )

  private val alarms get() = shadowOf(context.getSystemService(Context.ALARM_SERVICE) as AlarmManager)
  private val notifications get() = shadowOf(context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)

  @Before
  fun setUp() {
    context = RuntimeEnvironment.getApplication()
    ProgramReminderAlarms.appInForeground = false
  }

  @After
  fun tearDown() {
    ProgramReminderAlarms.appInForeground = false
  }

  @Test
  fun schedulesAnAlarmPerReminderAndDropsOnesNoLongerWanted() {
    ProgramReminderAlarms.replaceAll(context, listOf(entry("a", 10), entry("b", 20)), "Erinnerungen", now)
    assertEquals(2, alarms.scheduledAlarms.size)
    assertEquals(now + 10 * 60_000, alarms.scheduledAlarms.minOf { it.triggerAtTime })

    ProgramReminderAlarms.replaceAll(context, listOf(entry("b", 20)), "Erinnerungen", now)
    assertEquals(1, alarms.scheduledAlarms.size)
    assertEquals(listOf("b"), ProgramReminderAlarms.stored(context).map { it.id })
  }

  @Test
  fun aReminderWhoseProgrammeIsOverIsNotScheduled() {
    ProgramReminderAlarms.replaceAll(context, listOf(entry("over", -120, lastsMinutes = 30)), null, now)

    assertTrue(alarms.scheduledAlarms.isEmpty())
  }

  @Test
  fun aFiringAlarmPostsTheNotificationAndIsRememberedAsFired() {
    ProgramReminderAlarms.replaceAll(context, listOf(entry("a", 10)), "Erinnerungen", now)

    ProgramReminderAlarms.onAlarm(context, "a")

    val posted = notifications.allNotifications.single()
    assertEquals("Tagesschau", posted.extras.getString("android.title"))
    assertEquals(listOf("a"), ProgramReminderAlarms.takeFired(context))
    assertEquals("asking forgets them", emptyList<String>(), ProgramReminderAlarms.takeFired(context))
  }

  @Test
  fun withTheAppOnScreenNothingIsPosted() {
    ProgramReminderAlarms.replaceAll(context, listOf(entry("a", 10)), null, now)
    ProgramReminderAlarms.appInForeground = true

    ProgramReminderAlarms.onAlarm(context, "a")

    assertTrue(notifications.allNotifications.isEmpty())
    assertEquals(emptyList<String>(), ProgramReminderAlarms.takeFired(context))
  }

  @Test
  fun afterARebootTheStoredRemindersAreScheduledAgain() {
    ProgramReminderAlarms.replaceAll(context, listOf(entry("a", 10)), null, now)
    val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    for (alarm in alarms.scheduledAlarms.toList()) alarm.operation?.let(manager::cancel)
    assertTrue(alarms.scheduledAlarms.isEmpty())

    ProgramReminderReceiver().onReceive(context, Intent(Intent.ACTION_BOOT_COMPLETED))

    assertEquals(1, alarms.scheduledAlarms.size)
  }

  @Test
  fun aTappedNotificationIsHandedToDartOnce() {
    val channel = ProgramReminderChannel(context)

    channel.handleIntent(Intent(Intent.ACTION_VIEW).putExtra(ProgramReminderAlarms.EXTRA_ID, "x"))
    assertNull("another intent is not a reminder", channel.takeOpened())

    channel.handleIntent(Intent(ProgramReminderAlarms.ACTION_OPEN).putExtra(ProgramReminderAlarms.EXTRA_ID, "a"))
    assertEquals("a", channel.takeOpened())
    assertNull(channel.takeOpened())
  }
}
