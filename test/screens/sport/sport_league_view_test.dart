import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plezy/focus/focusable_wrapper.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/providers/iptv_sources_provider.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/screens/sport/sport_broadcast_finder.dart';
import 'package:plezy/screens/sport/sport_league_view.dart';
import 'package:plezy/screens/sport/sport_match_sheet.dart';
import 'package:plezy/services/iptv/iptv_live_tv_source.dart';
import 'package:plezy/services/iptv/iptv_source.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/sport/sport_models.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/widgets/app_menu.dart';

import '../../test_helpers/multi_server_fixtures.dart';
import '../../test_helpers/prefs.dart';
import '../../test_helpers/pump.dart';
import '../../test_helpers/sport_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('en'));

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  final bayern = openLigaTeam(40, 'FC Bayern München', shortName: 'Bayern');
  final bremen = openLigaTeam(134, 'Werder Bremen', shortName: 'Bremen');
  final dortmund = openLigaTeam(7, 'Borussia Dortmund', shortName: 'Dortmund');
  final leipzig = openLigaTeam(1635, 'RB Leipzig', shortName: 'Leipzig');
  final freiburg = openLigaTeam(112, 'SC Freiburg', shortName: 'Freiburg');
  final mainz = openLigaTeam(81, '1. FSV Mainz 05', shortName: 'Mainz');
  final hamburg = openLigaTeam(100, 'Hamburger SV', shortName: 'HSV');
  final koeln = openLigaTeam(65, '1. FC Köln', shortName: 'Köln');

  /// Matchday 4 is the current one: one game played yesterday, one being
  /// played now, one tomorrow. Matchday 5 is next week's.
  FakeOpenLigaDb provider() {
    final now = DateTime.now().toUtc();
    final api = FakeOpenLigaDb({
      '/getmatchdata/bl1': [
        openLigaMatch(
          id: 401,
          matchday: 4,
          kickoffUtc: now.subtract(const Duration(days: 1)),
          home: bayern,
          away: bremen,
          finished: true,
          halftime: (1, 0),
          result: (2, 1),
          goals: [
            openLigaGoal(home: 1, away: 0, minute: 12, scorer: 'Musiala'),
            openLigaGoal(home: 1, away: 1, minute: 61, scorer: 'Ducksch'),
            openLigaGoal(home: 2, away: 1, minute: 88, scorer: 'Kane', penalty: true),
          ],
          stadium: 'Allianz Arena',
          city: 'München',
          spectators: 75000,
        ),
        openLigaMatch(
          id: 402,
          matchday: 4,
          kickoffUtc: now.subtract(const Duration(minutes: 30)),
          home: dortmund,
          away: leipzig,
          goals: [openLigaGoal(home: 0, away: 1, minute: 20, scorer: 'Openda')],
        ),
        openLigaMatch(id: 403, matchday: 4, kickoffUtc: now.add(const Duration(days: 1)), home: freiburg, away: mainz),
      ],
      '/getmatchdata/bl1/2026/5': [
        openLigaMatch(id: 501, matchday: 5, kickoffUtc: now.add(const Duration(days: 7)), home: hamburg, away: koeln),
      ],
      '/getavailablegroups/bl1/2026': openLigaMatchdays(34),
      '/getbltable/bl1/2026': [
        openLigaTableRow(40, 'Bayern', points: 12, goals: 14, opponentGoals: 3),
        openLigaTableRow(7, 'Dortmund', points: 9, goals: 8, opponentGoals: 4),
        openLigaTableRow(1635, 'Leipzig', points: 7),
        openLigaTableRow(134, 'Bremen', points: 4),
      ],
    });
    // The current matchday by its number too, as the real provider serves it.
    api.routes['/getmatchdata/bl1/2026/4'] = api.routes['/getmatchdata/bl1'];
    return api;
  }

  Finder part(String debugLabel) =>
      find.byWidgetPredicate((w) => w is FocusableWrapper && w.focusNode?.debugLabel == debugLabel);

  Future<void> pumpLeague(
    WidgetTester tester,
    FakeOpenLigaDb api, {
    AppThemeVariant variant = AppThemeVariant.standard,
    Size size = const Size(1920, 1080),
    VoidCallback? onExitUp,
    GlobalKey<SportLeagueViewState>? key,
    SportBroadcastFinder? broadcastFinder,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true, variant: variant),
        home: Scaffold(
          body: SportLeagueView(
            key: key,
            league: SportLeague.bundesliga1,
            isActive: true,
            onExitUp: onExitUp ?? () {},
            repository: api.repository(),
            broadcastFinder: broadcastFinder,
          ),
        ),
      ),
    );
    await pumpUntil(tester, () => find.text(t.sport.matchday(n: 4)).evaluate().isNotEmpty);
  }

  Future<void> focusMatchday(WidgetTester tester, GlobalKey<SportLeagueViewState> key) async {
    key.currentState!.focusEntry();
    await tester.pump();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'sport_matchday');
  }

  testWidgets('entered from the navigation, the top match of the matchday takes focus', (tester) async {
    final key = GlobalKey<SportLeagueViewState>();
    await pumpLeague(tester, provider(), key: key, variant: AppThemeVariant.glas);

    key.currentState!.focusFirstMatch();
    expect(tester.binding.hasScheduledFrame, isTrue, reason: 'it asks for the frame it waits on');
    await tester.pump();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'sport_match_401');
  });

  testWidgets('asked for while the matchday is loading, the top match takes focus once it is there', (tester) async {
    final key = GlobalKey<SportLeagueViewState>();
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true, variant: AppThemeVariant.glas),
        home: Scaffold(
          body: SportLeagueView(
            key: key,
            league: SportLeague.bundesliga1,
            isActive: true,
            onExitUp: () {},
            repository: provider().repository(),
          ),
        ),
      ),
    );
    key.currentState!.focusFirstMatch();
    await pumpUntil(tester, () => find.text(t.sport.matchday(n: 4)).evaluate().isNotEmpty);
    await tester.pump();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'sport_match_401');
  });

  testWidgets('opens on the current matchday, with the fixtures and the table beside them', (tester) async {
    final api = provider();
    await pumpLeague(tester, api);

    expect(find.text('FC Bayern München'), findsOneWidget);
    expect(find.text('SC Freiburg'), findsOneWidget);
    expect(find.text('2 : 1'), findsOneWidget, reason: 'the finished game');
    expect(find.text('0 : 1'), findsOneWidget, reason: 'the running game, from its goals');
    expect(find.text('–:–'), findsOneWidget, reason: 'tomorrow’s game has no score yet');
    expect(find.text(t.sport.live), findsOneWidget);
    expect(find.text(t.sport.table.toUpperCase()), findsOneWidget);
    expect(find.text('Leipzig'), findsOneWidget, reason: 'the table names clubs short');

    // The current matchday's fixtures came with "current"; nothing else was
    // fetched for them.
    expect(api.requests, isNot(contains('/getmatchdata/bl1/2026/4')));

    // Table and fixtures side by side, not one under the other.
    final fixture = tester.getRect(find.text('FC Bayern München'));
    final tableRow = tester.getRect(find.text('Leipzig'));
    expect(tableRow.left, greaterThan(fixture.right));
  });

  testWidgets('the bar: the matchday in the middle, an arrow either side', (tester) async {
    await pumpLeague(tester, provider());

    expect(find.text(t.sport.matchday(n: 4)), findsOneWidget);
    expect(find.textContaining(t.sport.current), findsOneWidget, reason: 'the current matchday says so');
    // No row of numbers: the season is behind the button.
    expect(find.text('5'), findsNothing);
    expect(find.text('34'), findsNothing);

    final previous = tester.getRect(part('sport_matchday_previous'));
    final next = tester.getRect(part('sport_matchday_next'));
    final label = tester.getCenter(find.text(t.sport.matchday(n: 4)));
    expect(previous.right, lessThan(label.dx));
    expect(next.left, greaterThan(label.dx));
    expect(label.dx, moreOrLessEquals((previous.left + next.right) / 2, epsilon: 12), reason: 'centred between them');
    // Over the fixtures, not over the table.
    expect(next.right, lessThan(tester.getRect(find.text(t.sport.table.toUpperCase())).left));
  });

  testWidgets('RIGHT and LEFT walk the bar; an arrow steps one matchday and keeps the cursor', (tester) async {
    final api = provider();
    final key = GlobalKey<SportLeagueViewState>();
    await pumpLeague(tester, api, key: key);
    await focusMatchday(tester, key);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'sport_matchday_next');
    expect(api.requests, isNot(contains('/getmatchdata/bl1/2026/5')), reason: 'reaching the arrow loads nothing');

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await pumpUntil(tester, () => find.text('Hamburger SV').evaluate().isNotEmpty);
    expect(find.text(t.sport.matchday(n: 5)), findsOneWidget);
    expect(find.textContaining(t.sport.current), findsNothing);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'sport_matchday_next', reason: 'press again for the next');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'sport_matchday_previous');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await pumpUntil(tester, () => find.text('FC Bayern München').evaluate().isNotEmpty);
    expect(find.text(t.sport.matchday(n: 4)), findsOneWidget);
  });

  testWidgets('at the first matchday the left arrow stays, dimmed, and does nothing', (tester) async {
    final api = provider()..routes['/getmatchdata/bl1/2026/1'] = <Object?>[];
    final key = GlobalKey<SportLeagueViewState>();
    await pumpLeague(tester, api, key: key);
    await focusMatchday(tester, key);

    // Matchday 1 by way of the list.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AppMenuSheet<int>), matching: find.text(t.sport.matchday(n: 1))));
    await pumpUntil(tester, () => find.text(t.sport.matchday(n: 1)).evaluate().length == 1);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'sport_matchday_previous');
    final before = api.requests.length;
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(api.requests.length, before);
    expect(find.text(t.sport.matchday(n: 1)), findsOneWidget);
  });

  testWidgets('the button lists the season, opening on the matchday on show; choosing loads it', (tester) async {
    final api = provider();
    final key = GlobalKey<SportLeagueViewState>();
    await pumpLeague(tester, api, key: key);
    await focusMatchday(tester, key);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    final menu = find.byType(AppMenuSheet<int>);
    expect(menu, findsOneWidget);
    expect(find.descendant(of: menu, matching: find.text(t.sport.matchday(n: 1))), findsOneWidget);
    expect(find.descendant(of: menu, matching: find.text(t.sport.matchday(n: 34))), findsOneWidget);
    expect(
      find.descendant(of: menu, matching: find.text(t.sport.current)),
      findsOneWidget,
      reason: 'the current matchday is marked in the list',
    );
    expect(api.requests, isNot(contains('/getmatchdata/bl1/2026/5')), reason: 'opening the list loads nothing');

    // The cursor opens on matchday 4, so one step down is matchday 5.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await pumpUntil(tester, () => find.text('Hamburger SV').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(api.countOf('/getmatchdata/bl1/2026/5'), 1);
    expect(find.text('FC Bayern München'), findsNothing);
    expect(find.text(t.sport.matchday(n: 5)), findsOneWidget);
    expect(find.textContaining(t.sport.current), findsNothing, reason: 'matchday 5 is not the current one');
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'sport_matchday', reason: 'back on the button');
  });

  testWidgets('a game row does not grow on focus: its time would be clipped at the edge', (tester) async {
    await pumpLeague(tester, provider());

    final row = find.ancestor(of: find.text('FC Bayern München'), matching: find.byType(FocusableWrapper)).first;
    expect(tester.widget<FocusableWrapper>(row).disableScale, isTrue);
  });

  for (final television in [true, false]) {
    testWidgets(
      'glas on a ${television ? 'television' : 'phone'}: a game row keeps room between its plate and its time',
      (tester) async {
        TvDetectionService.debugSetAppleTVOverride(television);
        await pumpLeague(tester, provider(), variant: AppThemeVariant.glas);

        final row = find.ancestor(of: find.text('FC Bayern München'), matching: find.byType(FocusableWrapper)).first;
        final time = find.descendant(of: row, matching: find.byType(Text)).first;
        final gap = tester.getRect(time).left - tester.getRect(row).left;
        expect(gap, greaterThanOrEqualTo(12), reason: 'the time does not stand on the edge of the focus plate');
      },
    );
  }

  testWidgets('UP from the matchday leaves the league, DOWN reaches the first game', (tester) async {
    final api = provider();
    final key = GlobalKey<SportLeagueViewState>();
    var exitedUp = 0;
    await pumpLeague(tester, api, key: key, onExitUp: () => exitedUp++);
    await focusMatchday(tester, key);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(exitedUp, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'sport_match_401');

    // BACK from a game returns to the matchday rather than leaving the page.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'sport_matchday');
  });

  testWidgets('a game opens its window with the goals, the half-time score and the ground', (tester) async {
    final api = provider();
    final key = GlobalKey<SportLeagueViewState>();
    await pumpLeague(tester, api, key: key);
    await focusMatchday(tester, key);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    final sheet = find.byType(SportMatchDetail);
    expect(sheet, findsOneWidget);
    Finder inSheet(Finder finder) => find.descendant(of: sheet, matching: finder);

    expect(inSheet(find.text('${t.sport.finalScore} · ${t.sport.halftime} 1:0')), findsOneWidget);
    expect(inSheet(find.textContaining('Musiala')), findsOneWidget);
    expect(inSheet(find.textContaining('Ducksch')), findsOneWidget);
    expect(inSheet(find.textContaining('Kane (${t.sport.penalty})')), findsOneWidget);
    expect(inSheet(find.textContaining('Allianz Arena · München')), findsOneWidget);
    expect(
      inSheet(find.text('${t.sport.place(n: 1)} · 12 ${t.sport.points}')),
      findsOneWidget,
      reason: 'each club with its place in the table',
    );

    // Each goal on the side it counted for: Bremen's equaliser to the right
    // of the running score, Bayern's goals to the left of it.
    final running = tester.getCenter(inSheet(find.text('1 : 1')));
    expect(tester.getCenter(inSheet(find.textContaining('Ducksch'))).dx, greaterThan(running.dx));
    expect(tester.getCenter(inSheet(find.textContaining('Musiala'))).dx, lessThan(running.dx));
  });

  testWidgets('a game not yet played says so and lists no goals', (tester) async {
    final api = provider();
    final key = GlobalKey<SportLeagueViewState>();
    await pumpLeague(tester, api, key: key);
    await focusMatchday(tester, key);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'sport_match_403');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    final sheet = find.byType(SportMatchDetail);
    expect(find.descendant(of: sheet, matching: find.text(t.sport.notStarted)), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text(t.sport.goals.toUpperCase())), findsNothing);
  });

  testWidgets('an unreachable provider offers a retry, and the retry loads', (tester) async {
    final api = provider()..failing.add('/getmatchdata/bl1');
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(
          body: SportLeagueView(
            league: SportLeague.bundesliga1,
            isActive: true,
            onExitUp: () {},
            repository: api.repository(),
          ),
        ),
      ),
    );
    await pumpUntil(tester, () => find.text(t.sport.loadFailed).evaluate().isNotEmpty);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'sport_retry');

    api.failing.clear();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await pumpUntil(tester, () => find.text('Borussia Dortmund').evaluate().isNotEmpty);
    expect(find.text(t.sport.loadFailed), findsNothing);
  });

  for (final (club, looked) in [('FC Bayern München', false), ('SC Freiburg', true)]) {
    testWidgets(
      looked ? 'a game still to come says where to watch it' : 'a game that is over says nothing about the guide',
      (tester) async {
        final multiServer = testMultiServerProvider(MultiServerManager());
        addTearDown(multiServer.dispose);
        final finder = _FindingNothing(multiServer);
        await pumpLeague(tester, provider(), broadcastFinder: finder);

        await tester.tap(find.text(club));
        await tester.pumpAndSettle();

        expect(finder.searches, looked ? 1 : 0);
        expect(find.text(t.sport.broadcast.toUpperCase()), looked ? findsOneWidget : findsNothing);
        expect(find.text(t.sport.notInGuide), looked ? findsOneWidget : findsNothing);
      },
    );
  }

  testWidgets('a game opens with where to watch it, found in the IPTV guide', (tester) async {
    // Dortmund – Leipzig is being played; the provider's guide lists it.
    final now = DateTime.now().toUtc();
    String stamp(DateTime at) {
      String two(int n) => n.toString().padLeft(2, '0');
      return '${at.year}${two(at.month)}${two(at.day)}${two(at.hour)}${two(at.minute)}00 +0000';
    }

    final guide =
        '<tv><programme start="${stamp(now.subtract(const Duration(hours: 1)))}" '
        'stop="${stamp(now.add(const Duration(hours: 2)))}" channel="sky.bl1">'
        '<title>Bundesliga</title><sub-title>Borussia Dortmund – RB Leipzig</sub-title></programme></tv>';
    const playlist =
        '#EXTM3U\n#EXTINF:-1 tvg-id="sky.bl1" group-title="DE • Sport • Bundesliga",Sky Bundesliga 1\nhttp://provider/bl1\n';
    final multiServer = testMultiServerProvider(MultiServerManager());
    addTearDown(multiServer.dispose);
    final iptv = IptvSourcesProvider(
      profileId: 'profile-1',
      buildSource: (source) => IptvLiveTvSource(
        source,
        httpClient: MockClient(
          (request) async =>
              http.Response.bytes(utf8.encode(request.url.path.endsWith('.m3u') ? playlist : guide), 200),
        ),
      ),
    );
    addTearDown(iptv.dispose);
    await tester.runAsync(
      () => iptv.save(
        const IptvSource(
          id: 'src',
          name: 'IPTV',
          kind: IptvSourceKind.m3u,
          playlistUrl: 'http://provider/list.m3u',
          epgUrls: ['http://provider/guide.xml'],
        ),
      ),
    );

    final watched = <String>[];
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(
          body: SportLeagueView(
            league: SportLeague.bundesliga1,
            isActive: true,
            onExitUp: () {},
            repository: provider().repository(),
            broadcastFinder: SportBroadcastFinder(multiServer: multiServer, iptv: iptv),
            onWatch: (broadcast, channels, {startAtEpoch}) => watched.add(broadcast.channel.displayName),
          ),
        ),
      ),
    );
    await pumpUntil(tester, () => find.text('Borussia Dortmund').evaluate().isNotEmpty);

    await tester.tap(find.text('Borussia Dortmund'));
    await pumpUntil(tester, () => find.text('Sky Bundesliga 1').evaluate().isNotEmpty);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'sport_watch_0_0');

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(watched, ['Sky Bundesliga 1']);
  });

  group('fits the screen in every theme', () {
    for (final variant in [AppThemeVariant.standard, AppThemeVariant.glas]) {
      for (final size in const [Size(1920, 1080), Size(1280, 720)]) {
        testWidgets('${variant.name} at ${size.width.toInt()}x${size.height.toInt()} on a television', (tester) async {
          TvDetectionService.debugSetAppleTVOverride(true);
          await pumpLeague(tester, provider(), variant: variant, size: size);

          expect(tester.takeException(), isNull);
          // The whole table stands beside the fixtures: it is read, not
          // walked, so a club below the edge could never be scrolled to.
          final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
          expect(tester.getRect(find.text('Bremen')).bottom, lessThanOrEqualTo(screen.height));
        });
      }
    }

    testWidgets('a phone: the bar across the screen, its arrows a tap each', (tester) async {
      final api = provider();
      await pumpLeague(tester, api, size: const Size(400, 860));

      expect(tester.takeException(), isNull);
      final previous = tester.getRect(part('sport_matchday_previous'));
      final next = tester.getRect(part('sport_matchday_next'));
      expect(previous.left, lessThan(24));
      expect(next.right, greaterThan(376));
      expect(next.width, greaterThanOrEqualTo(44), reason: 'a finger-sized target');

      await tester.tap(part('sport_matchday_next'));
      await pumpUntil(tester, () => find.text('HSV').evaluate().isNotEmpty);
      expect(find.text(t.sport.matchday(n: 5)), findsOneWidget);

      await tester.tap(find.text('HSV'));
      await tester.pumpAndSettle();
      expect(find.byType(SportMatchDetail), findsOneWidget, reason: 'a game opens with a tap too');
    });

    testWidgets('a phone puts the table under the fixtures', (tester) async {
      await pumpLeague(tester, provider(), size: const Size(400, 860));

      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('Bremen').last, 200, scrollable: find.byType(Scrollable).last);
      final fixture = tester.getRect(find.text('Freiburg'));
      final tableRow = tester.getRect(find.text('Bremen').last);
      expect(tableRow.top, greaterThan(fixture.bottom));
    });

    testWidgets('a phone names the clubs short, so no name is cut off', (tester) async {
      await pumpLeague(tester, provider(), size: const Size(400, 860));

      expect(find.text('Borussia Dortmund'), findsNothing);
      expect(find.text('Freiburg'), findsOneWidget);
      expect(find.text('Mainz'), findsOneWidget);
    });
  });
}

/// A finder with Live TV whose guide never names a game, counting the
/// searches it is asked for.
class _FindingNothing extends SportBroadcastFinder {
  _FindingNothing(MultiServerProvider multiServer) : super(multiServer: multiServer);

  int searches = 0;

  @override
  Future<SportBroadcastSearch?> search(SportMatch match, SportLeague league) async {
    searches++;
    return const SportBroadcastSearch(broadcasts: [], leagueChannels: [], channels: []);
  }
}
