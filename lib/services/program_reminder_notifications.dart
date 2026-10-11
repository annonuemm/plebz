import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/app_logger.dart';
import '../utils/platform_detector.dart';

/// One reminder as Android's notification shows it (Plebz).
@immutable
class ProgramReminderNotice {
  const ProgramReminderNotice({
    required this.id,
    required this.at,
    required this.endsAt,
    required this.title,
    required this.text,
    required this.action,
  });

  final String id;

  /// When the notification is posted: the reminder's lead before the start.
  final DateTime at;

  /// When it is taken away again: the programme is over.
  final DateTime endsAt;
  final String title;
  final String text;

  /// The button's word ("Umschalten"); the notification itself opens the same.
  final String action;

  Map<String, Object?> toMap() => {
    'id': id,
    'at': at.millisecondsSinceEpoch,
    'endsAt': endsAt.millisecondsSinceEpoch,
    'title': title,
    'text': text,
    'action': action,
  };
}

/// Plebz: guide reminders as system notifications on phones and tablets, so
/// one comes when Plebz is closed too. Android posts them from alarms
/// (`ProgramReminderAlarms.kt`); the app hands over the whole list whenever it
/// changes and asks, on coming back, which were posted and which was tapped.
///
/// A television keeps the reminder inside the app: Google TV hardly shows
/// another app's notifications.
class ProgramReminderNotifications {
  ProgramReminderNotifications._();

  static final ProgramReminderNotifications instance = ProgramReminderNotifications._();

  static const _channel = MethodChannel('com.plebz/program_reminders');

  @visibleForTesting
  static bool? debugSupportedOverride;

  bool get supported => debugSupportedOverride ?? (Platform.isAndroid && !PlatformDetector.isTvDevice());

  /// [onOpened] runs when a notification is tapped while the app is running;
  /// [takeOpened] then names the reminder.
  void listen(VoidCallback onOpened) {
    if (!supported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'opened') onOpened();
    });
  }

  void stopListening() {
    if (!supported) return;
    _channel.setMethodCallHandler(null);
  }

  Future<void> replaceAll(List<ProgramReminderNotice> notices, {required String channelName}) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('replaceAll', {
        'entries': [for (final notice in notices) notice.toMap()],
        'channelName': channelName,
      });
    } catch (error) {
      appLogger.w('Reminders: notifications could not be scheduled', error: error);
    }
  }

  /// The reminders posted while the app was away; asking forgets them.
  Future<List<String>> takeFired() async {
    if (!supported) return const [];
    try {
      final fired = await _channel.invokeListMethod<String>('takeFired');
      return fired ?? const [];
    } catch (error) {
      appLogger.w('Reminders: posted notifications not readable', error: error);
      return const [];
    }
  }

  /// The reminder whose notification was tapped, once.
  Future<String?> takeOpened() async {
    if (!supported) return null;
    try {
      return await _channel.invokeMethod<String>('takeOpened');
    } catch (error) {
      appLogger.w('Reminders: tapped notification not readable', error: error);
      return null;
    }
  }
}
