import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/models/livetv_channel.dart';
import 'package:plezy/models/livetv_program.dart';
import 'package:plezy/screens/live_now/live_now_loader.dart';
import 'package:plezy/screens/live_now/live_now_tile.dart';
import 'package:plezy/services/sport/sport_models.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/focus/locked_hub_controller.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/focus/card_focus_scope.dart';
import 'package:plezy/widgets/hub_section.dart';
import 'package:plezy/widgets/media_card.dart';
import 'package:plezy/widgets/tv_browse_rail.dart';
import 'package:provider/provider.dart';
import '../../test_helpers/multi_server_fixtures.dart';
import '../../test_helpers/prefs.dart';

/// Saturday 15:40, local time: the Bundesliga's afternoon.
final _now = DateTime(2026, 10, 3, 15, 40);

SportTeam _team(int id, String name) => SportTeam(id: id, name: name, shortName: name);

SportMatch _match(
  int id, {
  required DateTime kickoff,
  bool finished = false,
  List<SportGoal> goals = const [],
  String home = 'Heim',
  String away = 'Gast',
}) => SportMatch(
  id: id,
  season: 2026,
  matchday: const SportMatchday(order: 7, name: '7. Spieltag'),
  kickoff: kickoff,
  home: _team(id * 10, home),
  away: _team(id * 10 + 1, away),
  isFinished: finished,
  goals: goals,
);

LiveTvChannel _channel(String key, {String source = 'src'}) =>
    LiveTvChannel(key: key, title: 'Channel $key', serverId: 'server', favoriteSource: source);

LiveTvProgram _program(String channelKey, String title, {required DateTime begins, required DateTime ends}) =>
    LiveTvProgram(
      title: title,
      channelIdentifier: channelKey,
      serverId: 'server',
      beginsAt: begins.millisecondsSinceEpoch ~/ 1000,
      endsAt: ends.millisecondsSinceEpoch ~/ 1000,
    );

List<int> _ids(List<LiveNowGame> games) => [for (final game in games) game.match.id];

void main() {
  setUp(() => LocaleSettings.setLocaleSync(AppLocale.en));

  group('the games', () {
    final halfPast3 = DateTime(2026, 10, 3, 15, 30);
    final evening = DateTime(2026, 10, 3, 20, 30);

    test('on now comes first, and within it the higher league', () {
      final games = liveNowGames({
        SportLeague.bundesliga2: [_match(2, kickoff: halfPast3)],
        SportLeague.bundesliga1: [_match(1, kickoff: halfPast3)],
        SportLeague.liga3: [_match(3, kickoff: evening)],
      }, _now);

      expect(_ids(games), [1, 2, 3], reason: 'live 1. Liga, live 2. Liga, then later today');
    });

    test('games still to come today follow, the higher league ahead of an earlier kickoff', () {
      final games = liveNowGames({
        SportLeague.liga3: [_match(3, kickoff: DateTime(2026, 10, 3, 18))],
        SportLeague.bundesliga1: [_match(1, kickoff: evening)],
      }, _now);

      expect(_ids(games), [1, 3]);
    });

    test('a finished game, and one on another day, are left out', () {
      final games = liveNowGames({
        SportLeague.bundesliga1: [
          _match(1, kickoff: DateTime(2026, 10, 3, 13, 30), finished: true),
          _match(2, kickoff: DateTime(2026, 10, 4, 15, 30)),
          _match(3, kickoff: halfPast3),
        ],
      }, _now);

      expect(_ids(games), [3]);
    });
  });

  group('the favourites', () {
    test('keep the viewer\'s order, each with what is on it now', () {
      final channels = [_channel('a'), _channel('b'), _channel('c')];
      final favorites = [FavoriteChannel(source: 'src', id: 'c'), FavoriteChannel(source: 'src', id: 'a')];
      final programs = [
        _program('a', 'Earlier', begins: DateTime(2026, 10, 3, 14), ends: DateTime(2026, 10, 3, 15)),
        _program('a', 'Tagesschau', begins: DateTime(2026, 10, 3, 15), ends: DateTime(2026, 10, 3, 16)),
      ];

      final result = liveNowFavorites(channels, favorites, programs, _now);

      expect([for (final entry in result) entry.channel.key], ['c', 'a']);
      expect(result.last.program?.title, 'Tagesschau', reason: 'what is on now, not what was on');
      expect(result.first.program, isNull, reason: 'a channel without a guide is still a tile');
    });

    test('a favourite whose channel is hidden or gone is left out', () {
      final result = liveNowFavorites(
        [_channel('a')],
        [FavoriteChannel(source: 'src', id: 'gone'), FavoriteChannel(source: 'other', id: 'a')],
        const [],
        _now,
      );

      expect(result, isEmpty, reason: 'a channel is its source and its key together');
    });
  });

  group('the tile', () {
    Future<void> pumpTile(WidgetTester tester, LiveNowSnapshot snapshot) async {
      final hub = liveNowHub(snapshot);
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: true, variant: AppThemeVariant.glas),
          home: Scaffold(
            body: LiveNowScope(
              snapshot: snapshot,
              child: Row(
                children: [
                  for (final item in hub.items)
                    LiveNowTileCard(item: item, width: 240, cardHeight: 135, captionHeight: 32),
                ],
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('a game on now says so, with its score and its pairing', (tester) async {
      await withClock(Clock.fixed(_now), () async {
        final match = _match(
          1,
          kickoff: DateTime(2026, 10, 3, 15, 30),
          home: 'Bayern',
          away: 'Dortmund',
          goals: [const SportGoal(score: SportScore(1, 0), minute: 4, scorer: 'X')],
        );
        await pumpTile(
          tester,
          LiveNowSnapshot(
            entries: [LiveNowGame(match: match, league: SportLeague.bundesliga1)],
          ),
        );

        expect(find.text(t.sport.live), findsOneWidget);
        expect(find.text('1:0'), findsOneWidget);
        expect(find.text('Bayern – Dortmund'), findsOneWidget);
        expect(find.text(t.sport.bundesliga1), findsOneWidget);
      });
    });

    testWidgets('a channel is captioned with what is on it', (tester) async {
      await pumpTile(
        tester,
        LiveNowSnapshot(
          entries: [
            LiveNowChannel(
              channel: _channel('a'),
              program: _program('a', 'Tagesschau', begins: DateTime(2026, 10, 3, 15), ends: DateTime(2026, 10, 3, 16)),
            ),
          ],
        ),
      );

      expect(find.text('Tagesschau'), findsOneWidget);
    });
  });

  group('in the rows', () {
    setUp(() async {
      resetSharedPreferencesForTest();
      SettingsService.resetForTesting();
      await SettingsService.getInstance();
    });
    tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

    LiveNowSnapshot snapshot() => LiveNowSnapshot(
      entries: [
        LiveNowChannel(
          channel: _channel('a'),
          program: _program('a', 'Tagesschau', begins: DateTime(2026, 10, 3, 15), ends: DateTime(2099)),
        ),
      ],
    );

    Widget host(LiveNowSnapshot snapshot, Widget child) => ChangeNotifierProvider<MultiServerProvider>(
      create: (_) => testMultiServerProvider(MultiServerManager()),
      child: MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(
          body: LiveNowScope(snapshot: snapshot, child: child),
        ),
      ),
    );

    testWidgets('the television rail draws the live tile, its caption and a focus ring', (tester) async {
      TvDetectionService.debugSetAppleTVOverride(true);
      final live = snapshot();
      await tester.pumpWidget(
        host(
          live,
          SizedBox(
            width: 1280,
            height: 720,
            child: TvBrowseRail(
              focusMemory: HubFocusMemory(),
              hubs: [liveNowHub(live)],
              iconForHub: (_, _) => Icons.tv_rounded,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(LiveNowTileCard), findsOneWidget);
      expect(find.byType(MediaCard), findsNothing, reason: 'not a poster with a year and a rating');
      expect(find.text('Tagesschau'), findsOneWidget);
      expect(find.descendant(of: find.byType(LiveNowTileCard), matching: find.byType(CardFocusBorder)), findsOneWidget);
    });

    testWidgets('on a phone a tap hands the tile to the host', (tester) async {
      final live = snapshot();
      final tapped = <String>[];
      await tester.pumpWidget(
        host(
          live,
          ListView(
            children: [
              HubSection(
                hub: liveNowHub(live),
                focusMemory: HubFocusMemory(),
                icon: Icons.live_tv,
                onItemTap: (item) => tapped.add(item.id),
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(LiveNowTileCard));
      await tester.pump();

      expect(tapped, [live.entries.single.id]);
    });
  });
}
