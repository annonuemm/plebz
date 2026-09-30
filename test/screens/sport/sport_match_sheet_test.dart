import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/models/livetv_channel.dart';
import 'package:plezy/models/livetv_program.dart';
import 'package:plezy/screens/sport/sport_broadcast_finder.dart';
import 'package:plezy/screens/sport/sport_match_sheet.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/sport/sport_broadcast_matching.dart';
import 'package:plezy/services/sport/sport_models.dart';
import 'package:plezy/theme/mono_theme.dart';

import '../../test_helpers/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('en'));
  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  int epoch(DateTime at) => at.millisecondsSinceEpoch ~/ 1000;
  final now = DateTime.now();

  const dortmund = SportTeam(id: 7, name: 'Borussia Dortmund', shortName: 'Dortmund');
  const bremen = SportTeam(id: 134, name: 'SV Werder Bremen', shortName: 'Bremen');
  SportMatch game(DateTime kickoff) => SportMatch(
    id: 1,
    season: 2026,
    matchday: const SportMatchday(order: 7, name: '7. Spieltag'),
    kickoff: kickoff,
    home: dortmund,
    away: bremen,
    isFinished: false,
  );

  final sky = LiveTvChannel(key: 'sky', title: 'Sky Bundesliga 1', serverId: 'iptv', catchupDays: 7);
  final noArchive = LiveTvChannel(key: 'dazn', title: 'DAZN 1', serverId: 'iptv');

  LiveTvProgram program(LiveTvChannel channel, DateTime begins, {Duration length = const Duration(hours: 2)}) =>
      LiveTvProgram(
        title: 'Bundesliga',
        subtitle: 'Borussia Dortmund - Werder Bremen',
        beginsAt: epoch(begins),
        endsAt: epoch(begins.add(length)),
        channelIdentifier: channel.key,
        serverId: 'iptv',
      );

  SportBroadcast broadcast(
    LiveTvChannel channel,
    DateTime begins, {
    SportBroadcastKind kind = SportBroadcastKind.match,
  }) => SportBroadcast(channel: channel, program: program(channel, begins), kind: kind);

  final watched = <({String channel, int? startAt})>[];
  setUp(watched.clear);

  Future<void> pumpSheet(WidgetTester tester, SportMatch match, Future<SportBroadcastSearch?>? search) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(
          body: SportMatchDetail(
            match: match,
            league: SportLeague.bundesliga1,
            table: const [],
            broadcasts: search,
            onWatch: (broadcast, channels, {startAtEpoch}) =>
                watched.add((channel: broadcast.channel.key, startAt: startAtEpoch)),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  SportBroadcastSearch found(List<SportBroadcast> broadcasts, {List<SportBroadcast> leagueChannels = const []}) =>
      SportBroadcastSearch(broadcasts: broadcasts, leagueChannels: leagueChannels, channels: [sky, noArchive]);

  String? focused() => FocusManager.instance.primaryFocus?.debugLabel;

  testWidgets('a game on air: play it, or from its start where the archive has it', (tester) async {
    final kickoff = now.subtract(const Duration(minutes: 20));
    await pumpSheet(tester, game(kickoff), Future.value(found([broadcast(sky, kickoff)])));

    expect(find.text(t.sport.broadcast.toUpperCase()), findsOneWidget);
    expect(find.text('Sky Bundesliga 1'), findsOneWidget);
    expect(find.textContaining('Borussia Dortmund - Werder Bremen'), findsOneWidget);
    expect(find.text(t.common.play), findsOneWidget);
    expect(find.text(t.liveTv.restartFromArchive), findsOneWidget);
    expect(focused(), 'sport_watch_0_0', reason: 'the cursor goes to the first way to watch');

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(watched.single, (channel: 'sky', startAt: null));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(focused(), 'sport_watch_0_1');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(watched.last, (channel: 'sky', startAt: epoch(kickoff)));
  });

  testWidgets('a game still to come tunes the channel', (tester) async {
    final kickoff = now.add(const Duration(hours: 1));
    await pumpSheet(tester, game(kickoff), Future.value(found([broadcast(sky, kickoff)])));

    expect(find.text(t.liveTv.watchChannel), findsOneWidget);
    expect(find.text(t.liveTv.restartFromArchive), findsNothing);
  });

  testWidgets('a game over comes from the archive, and is left out where the archive does not reach', (tester) async {
    final kickoff = now.subtract(const Duration(days: 1));
    await pumpSheet(
      tester,
      game(kickoff),
      Future.value(found([broadcast(sky, kickoff), broadcast(noArchive, kickoff)])),
    );

    expect(find.text(t.liveTv.watchFromArchive), findsOneWidget);
    expect(find.text('DAZN 1'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(watched.single, (channel: 'sky', startAt: epoch(kickoff)));
  });

  testWidgets('a Konferenz says so', (tester) async {
    final kickoff = now.add(const Duration(minutes: 30));
    await pumpSheet(
      tester,
      game(kickoff),
      Future.value(found([broadcast(sky, kickoff, kind: SportBroadcastKind.conference)])),
    );

    expect(find.textContaining(t.sport.conference.toUpperCase(), findRichText: true), findsOneWidget);
  });

  testWidgets('not in the guide: says so, and offers the league\'s channels', (tester) async {
    final kickoff = now.add(const Duration(minutes: 30));
    await pumpSheet(
      tester,
      game(kickoff),
      Future.value(
        found(
          const [],
          leagueChannels: [SportBroadcast(channel: sky, program: null, kind: SportBroadcastKind.leagueChannel)],
        ),
      ),
    );

    expect(find.text(t.sport.notInGuide), findsOneWidget);
    expect(find.text(t.sport.leagueChannels(league: t.sport.bundesliga1)), findsOneWidget);
    expect(find.text(t.common.play), findsOneWidget);
  });

  testWidgets('while the guide is searched it says so; without Live TV nothing is said', (tester) async {
    final kickoff = now.add(const Duration(minutes: 30));
    final pending = Completer<SportBroadcastSearch?>();
    await pumpSheet(tester, game(kickoff), pending.future);
    expect(find.text(t.sport.searchingGuide), findsOneWidget);

    pending.complete(null);
    await tester.pump();
    expect(find.text(t.sport.searchingGuide), findsNothing);
    expect(find.text(t.sport.broadcast.toUpperCase()), findsNothing);
  });

  testWidgets('DOWN from the last way to watch reads on; UP at the top comes back', (tester) async {
    final kickoff = now.add(const Duration(minutes: 30));
    await pumpSheet(tester, game(kickoff), Future.value(found([broadcast(sky, kickoff)])));
    expect(focused(), 'sport_watch_0_0');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focused(), 'sport_match_sheet');

    await tester.pumpAndSettle();
    // Back to the top first, then onto the button.
    for (var i = 0; i < 4 && focused() == 'sport_match_sheet'; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
    }
    expect(focused(), 'sport_watch_0_0');
  });

  testWidgets('taps work too', (tester) async {
    final kickoff = now.subtract(const Duration(minutes: 20));
    await pumpSheet(tester, game(kickoff), Future.value(found([broadcast(sky, kickoff)])));

    await tester.tap(find.text(t.liveTv.restartFromArchive));
    expect(watched.single, (channel: 'sky', startAt: epoch(kickoff)));
  });
}
