import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/models/livetv_channel.dart';
import 'package:plezy/models/livetv_program.dart';
import 'package:plezy/screens/live_now/live_now_loader.dart';
import 'package:plezy/screens/live_now/live_now_tile.dart';
import 'package:plezy/redesign/ocker_skin.dart';
import 'package:plezy/services/sport/club_colours.dart';
import 'package:plezy/services/sport/sport_models.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/focus/locked_hub_controller.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/focus/card_focus_scope.dart';
import 'package:plezy/focus/focus_theme.dart';
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
    Future<void> pumpTile(
      WidgetTester tester,
      LiveNowSnapshot snapshot, {
      AppThemeVariant variant = AppThemeVariant.glas,
      double textScale = 1,
    }) async {
      final hub = liveNowHub(snapshot);
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(MonoPalette.dark, variant: variant),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: LiveNowScope(
              snapshot: snapshot,
              child: Row(
                children: [
                  for (final item in hub.items)
                    LiveNowTileCard(item: item, width: 240, cardHeight: 135, captionHeight: 50),
                ],
              ),
            ),
          ),
        ),
      );
    }

    SportMatch liveGame({int homeId = 10, int awayId = 11}) => SportMatch(
      id: 1,
      season: 2026,
      matchday: const SportMatchday(order: 7, name: '7. Spieltag'),
      kickoff: DateTime(2026, 10, 3, 15, 30),
      home: _team(homeId, 'Bayern'),
      away: _team(awayId, 'Dortmund'),
      isFinished: false,
      goals: [const SportGoal(score: SportScore(1, 0), minute: 4, scorer: 'X')],
    );

    testWidgets('a game on now shows its score, and the league and kickoff under the pairing', (tester) async {
      await withClock(Clock.fixed(_now), () async {
        await pumpTile(
          tester,
          LiveNowSnapshot(
            entries: [LiveNowGame(match: liveGame(), league: SportLeague.bundesliga1)],
          ),
        );

        expect(find.text(t.sport.live), findsOneWidget);
        // The matchday asked for by number keeps the goals current.
        expect(find.text('1 : 0'), findsOneWidget);
        expect(find.text(t.sport.versus), findsNothing);
        expect(find.text('Bayern – Dortmund'), findsOneWidget);
        expect(find.text('${t.sport.bundesliga1} · 15:30'), findsOneWidget);
        expect(find.text(t.sport.bundesliga1), findsNothing, reason: 'the card is a picture, as a poster is');
      });
    });

    testWidgets('larger system text does not overflow the two-line caption (Plebz)', (tester) async {
      await withClock(Clock.fixed(_now), () async {
        await pumpTile(
          tester,
          LiveNowSnapshot(
            entries: [LiveNowGame(match: liveGame(), league: SportLeague.bundesliga1)],
          ),
          textScale: 1.4,
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Bayern – Dortmund'), findsOneWidget);
      });
    });

    testWidgets('a game still to come is the pairing, without a LIVE mark', (tester) async {
      await withClock(Clock.fixed(_now), () async {
        final match = _match(1, kickoff: DateTime(2026, 10, 3, 20, 30), home: 'Bayern', away: 'Dortmund');
        await pumpTile(
          tester,
          LiveNowSnapshot(
            entries: [LiveNowGame(match: match, league: SportLeague.bundesliga1)],
          ),
        );

        expect(find.text(t.sport.live), findsNothing);
        expect(find.text(t.sport.versus), findsOneWidget);
        expect(find.text('${t.sport.bundesliga1} · 20:30'), findsOneWidget);
      });
    });

    testWidgets('the original look keeps the league on the card and shows the score too', (tester) async {
      await withClock(Clock.fixed(_now), () async {
        await pumpTile(
          tester,
          LiveNowSnapshot(
            entries: [LiveNowGame(match: liveGame(), league: SportLeague.bundesliga1)],
          ),
          variant: AppThemeVariant.standard,
        );

        expect(find.text(t.sport.bundesliga1), findsOneWidget);
        expect(find.text('1 : 0'), findsOneWidget);
        expect(find.text('Bayern – Dortmund'), findsOneWidget);
      });
    });

    testWidgets('a game stands on its clubs\' colours: glass under Glas, a gradient under Flach', (tester) async {
      await withClock(Clock.fixed(_now), () async {
        // St. Pauli and Karlsruhe by their OpenLigaDB ids.
        final snapshot = LiveNowSnapshot(
          entries: [LiveNowGame(match: liveGame(homeId: 98, awayId: 105), league: SportLeague.bundesliga2)],
        );
        // The clubs' colours run into each other.
        Finder slant() => find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).gradient is LinearGradient &&
              // Home's colour held, then into away's — not the glass's sheen.
              ((widget.decoration as BoxDecoration).gradient! as LinearGradient).colors.length == 4,
        );

        await pumpTile(tester, snapshot);
        expect(find.byType(OckerGlass), findsOneWidget);
        expect(slant(), findsNothing);

        await pumpTile(tester, snapshot, variant: AppThemeVariant.flach);
        // The app's theme change is animated; let it arrive.
        await tester.pump(const Duration(seconds: 1));
        expect(slant(), findsOneWidget);
      });
    });

    test('club colours are the ones viewers know, not the crest\'s', () {
      expect(clubColourFor(_team(98, 'St. Pauli')), const Color(0xFF5C3C2C), reason: 'brown, though the crest is red');
      expect(clubColourFor(_team(7, 'Dortmund')), const Color(0xFFFDE100));
      expect(clubColourFor(_team(114, 'Verl')), isNull, reason: 'black and white keeps the plain ground');
      expect(clubColourFor(_team(999999, 'Unknown')), isNull);
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
        theme: monoTheme(MonoPalette.dark),
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

    test('a focused tile grows and rings past its slot, never into the next tile', () {
      // The tiles are wide and drawn edge to edge; with "tight" spacing the
      // next one painted over the focused tile's ring.
      final hub = liveNowHub(snapshot());
      for (final scale in [0.67, 1.0, 1.5, 2.0]) {
        for (final fullCards in [false, true]) {
          final metrics = TvBrowseRailLayout.metricsForHub(
            hub: hub,
            availableWidth: 1280 * scale,
            density: 3,
            episodePosterMode: EpisodePosterMode.seriesPoster,
            scale: scale,
            fullCardLayout: fullCards,
            gridSpacing: GridSpacing.tight,
          );
          final grow = fullCards ? FocusTheme.fullCardFocusScale : FocusTheme.focusScale;
          final reach = metrics.cardWidth * (grow - 1) / 2 + FocusTheme.focusBorderWidth * scale * grow;
          expect(metrics.itemGap, greaterThan(reach), reason: 'scale $scale, full cards $fullCards');
        }
      }
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
      expect(
        find.descendant(of: find.byType(LiveNowTileCard), matching: find.byType(CardFocusBorder)),
        findsOneWidget,
        reason: 'a keyboard\'s focus shows round the card here too',
      );
    });
  });
}
