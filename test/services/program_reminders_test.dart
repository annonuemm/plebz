import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/models/livetv_channel.dart';
import 'package:plezy/models/livetv_program.dart';
import 'package:plezy/services/base_shared_preferences_service.dart';
import 'package:plezy/services/program_reminders.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/program_reminder_host.dart';

import '../test_helpers/prefs.dart';

void main() {
  final channel = LiveTvChannel(key: 'c', identifier: 'ard', title: 'Das Erste', serverId: 'iptv:src');
  final start = DateTime(2026, 10, 5, 20, 15);
  int epoch(DateTime at) => at.millisecondsSinceEpoch ~/ 1000;
  final tatort = LiveTvProgram(
    title: 'Tatort',
    channelIdentifier: 'ard',
    beginsAt: epoch(start),
    endsAt: epoch(start.add(const Duration(minutes: 90))),
  );
  final reminders = ProgramReminders.instance;

  setUpAll(() => initializeDateFormatting('en'));

  setUp(() {
    LocaleSettings.setLocaleSync(AppLocale.en);
    resetSharedPreferencesForTest();
    reminders.debugReset();
  });

  test('a reminder is kept, read back, and taken away again', () async {
    await withClock(Clock.fixed(start.subtract(const Duration(hours: 3))), () async {
      await reminders.add(channel, tatort);
      expect(reminders.isSet(channel, tatort), isTrue);

      reminders.debugReset();
      await reminders.ensureLoaded();
      expect(reminders.isSet(channel, tatort), isTrue);
      expect(reminders.entries.single.title, 'Tatort');
      expect(reminders.entries.single.channelTitle, 'Das Erste');

      await reminders.remove(reminders.entries.single.key);
      expect(reminders.isSet(channel, tatort), isFalse);
      final prefs = await BaseSharedPreferencesService.sharedCache();
      expect(prefs.getString(ProgramReminders.prefsKey), isNull);
    });
  });

  test('it comes due a minute before the start, and stays due while the programme runs', () async {
    await withClock(Clock.fixed(start.subtract(const Duration(hours: 3))), () => reminders.add(channel, tatort));

    expect(withClock(Clock.fixed(start.subtract(const Duration(minutes: 2))), reminders.due), isEmpty);
    expect(
      withClock(Clock.fixed(start.subtract(const Duration(minutes: 3))), reminders.nextDueAt),
      start.subtract(ProgramReminders.lead),
    );
    expect(withClock(Clock.fixed(start.subtract(ProgramReminders.lead)), reminders.due), hasLength(1));
    // Missed while the app was closed: still worth saying while it runs.
    expect(withClock(Clock.fixed(start.add(const Duration(minutes: 30))), reminders.due), hasLength(1));
    expect(withClock(Clock.fixed(start.add(const Duration(minutes: 91))), reminders.due), isEmpty);
  });

  test('a programme that ended while the app was closed is forgotten', () async {
    await withClock(Clock.fixed(start.subtract(const Duration(hours: 3))), () => reminders.add(channel, tatort));
    reminders.debugReset();
    await withClock(Clock.fixed(start.add(const Duration(hours: 2))), reminders.ensureLoaded);
    expect(reminders.entries, isEmpty);
  });

  test('only a programme still ahead can be reminded of', () {
    withClock(Clock.fixed(start.subtract(const Duration(minutes: 1))), () {
      expect(ProgramReminders.canRemind(tatort), isTrue);
    });
    withClock(Clock.fixed(start.add(const Duration(minutes: 1))), () {
      expect(ProgramReminders.canRemind(tatort), isFalse);
    });
  });

  testWidgets('the reminder comes up over the screen when it is due, once', (tester) async {
    final now = DateTime.now();
    final soon = LiveTvProgram(
      title: 'Sportschau',
      channelIdentifier: 'ard',
      beginsAt: epoch(now.add(const Duration(minutes: 1, seconds: 30))),
      endsAt: epoch(now.add(const Duration(minutes: 60))),
    );
    await tester.runAsync(() => reminders.add(channel, soon));

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: const ProgramReminderHost(child: Scaffold(body: Text('watching'))),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Sportschau'), findsNothing, reason: 'not due yet');

    await tester.pump(const Duration(seconds: 31));
    await tester.pump();
    expect(find.text(t.reminders.soonTitle), findsOneWidget);
    expect(find.text('Sportschau'), findsOneWidget);
    expect(find.textContaining('Das Erste'), findsOneWidget);
    expect(find.text(t.reminders.tune), findsOneWidget);
    expect(reminders.entries, isEmpty, reason: 'shown once, then gone');

    await tester.tap(find.text(t.common.close));
    await tester.pumpAndSettle();
    expect(find.text('Sportschau'), findsNothing);
  });

  testWidgets('an unanswered reminder goes away by itself', (tester) async {
    final now = DateTime.now();
    await tester.runAsync(
      () => reminders.add(
        channel,
        LiveTvProgram(
          title: 'Tagesschau',
          channelIdentifier: 'ard',
          beginsAt: epoch(now.add(const Duration(seconds: 30))),
          endsAt: epoch(now.add(const Duration(minutes: 15))),
        ),
      ),
    );
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: const ProgramReminderHost(child: Scaffold(body: Text('watching'))),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Tagesschau'), findsOneWidget);

    await tester.pump(ProgramReminderHost.showFor);
    await tester.pumpAndSettle();
    expect(find.text('Tagesschau'), findsNothing);
  });
}
