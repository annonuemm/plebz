import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/models/livetv_channel.dart';
import 'package:plezy/models/livetv_program.dart';
import 'package:plezy/screens/livetv/program_details_sheet.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/overlay_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('en'));
  setUp(() => LocaleSettings.setLocaleSync(AppLocale.en));

  final begins = DateTime(2026, 8, 29, 20, 15);

  LiveTvProgram program({bool airing = false}) {
    final start = airing ? DateTime.now().subtract(const Duration(minutes: 20)) : begins;
    return LiveTvProgram(
      title: 'Tatort',
      channelIdentifier: 'ard',
      beginsAt: start.millisecondsSinceEpoch ~/ 1000,
      endsAt: start.add(const Duration(minutes: 90)).millisecondsSinceEpoch ~/ 1000,
    );
  }

  Future<void> pumpSheet(
    WidgetTester tester, {
    VoidCallback? onWatchFromArchive,
    VoidCallback? onTuneChannel,
    bool airing = false,
  }) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: OverlaySheetHost(
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showProgramDetailsSheet(
                      context,
                      program: program(airing: airing),
                      channel: LiveTvChannel(key: 'c', identifier: 'ard', title: 'Das Erste'),
                      posterUrl: null,
                      onTuneChannel: onTuneChannel ?? () {},
                      onWatchFromArchive: onWatchFromArchive,
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a programme still in the archive can be played from it', (tester) async {
    var played = 0;
    await pumpSheet(tester, onWatchFromArchive: () => played++);

    expect(find.text(t.liveTv.watchFromArchive), findsOneWidget);

    await tester.tap(find.text(t.liveTv.watchFromArchive));
    await tester.pumpAndSettle();

    expect(played, 1);
  });

  testWidgets('a running programme is offered a restart, with the play button still first', (tester) async {
    var restarted = 0;
    await pumpSheet(tester, airing: true, onWatchFromArchive: () => restarted++);

    expect(find.text(t.liveTv.restartFromArchive), findsOneWidget);
    expect(find.text(t.liveTv.watchFromArchive), findsNothing, reason: 'nothing to fetch — it is on right now');

    await tester.tap(find.text(t.liveTv.restartFromArchive));
    await tester.pumpAndSettle();

    expect(restarted, 1);
  });

  testWidgets('a programme outside any archive is not offered one', (tester) async {
    await pumpSheet(tester);

    expect(find.text(t.liveTv.watchFromArchive), findsNothing);
    // The channel is still reachable — what is on now is a different thing to
    // want, not a replacement for the programme that was asked about.
    expect(find.text(t.liveTv.watchChannel), findsOneWidget);
  });
}
