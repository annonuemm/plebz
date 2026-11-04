import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plezy/focus/focusable_wrapper.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/providers/iptv_sources_provider.dart';
import 'package:plezy/redesign/ocker_skin.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/screens/sport/sport_board_widgets.dart';
import 'package:plezy/screens/sport/sport_broadcast_finder.dart';
import 'package:plezy/screens/sport/sport_league_view.dart';
import 'package:plezy/screens/sport/sport_match_sheet.dart';
import 'package:plezy/services/iptv/iptv_live_tv_source.dart';
import 'package:plezy/services/iptv/iptv_source.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/sport/sport_models.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/theme/mono_tokens.dart';
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
    bool tracksInput = false,
    TargetPlatform? platform,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Widget app(Widget child) => tracksInput ? InputModeTracker(child: child) : child;
    await tester.pumpWidget(
      app(
        MaterialApp(
          theme: monoTheme(MonoPalette.dark, variant: variant).copyWith(platform: platform),
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
      ),
    );
    // The television's bar sets the matchday in one line with its dates (Plebz).
    await pumpUntil(
      tester,
      () => find.textContaining(t.sport.matchday(n: 4), findRichText: true).evaluate().isNotEmpty,
    );
  }

  Future<void> focusMatchday(WidgetTester tester, GlobalKey<SportLeagueViewState> key) async {
    key.currentState!.focusEntry();
    await tester.pump();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'sport_matchday');
  }

  testWidgets('a running game is not asked for again while another destination is in front', (tester) async {
    final api = provider();
    var now = DateTime.now();
    await withClock(Clock(() => now), () async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      // The main screen keeps a hidden destination mounted with its tickers off.
      final inFront = ValueNotifier(true);
      addTearDown(inFront.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(MonoPalette.dark),
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: inFront,
              builder: (context, enabled, child) => TickerMode(enabled: enabled, child: child!),
              child: SportLeagueView(
                league: SportLeague.bundesliga1,
                isActive: true,
                onExitUp: () {},
                repository: api.repository(),
              ),
            ),
          ),
        ),
      );
      await pumpUntil(tester, () => find.text(t.sport.matchday(n: 4)).evaluate().isNotEmpty);
      final asked = api.countOf('/getmatchdata/bl1/2026/4');

      inFront.value = false;
      await tester.pump();
      now = now.add(const Duration(seconds: 61));
      await tester.pump(const Duration(seconds: 61));
      await tester.pump();
      expect(api.countOf('/getmatchdata/bl1/2026/4'), asked);

      inFront.value = true;
      await tester.pump();
      now = now.add(const Duration(seconds: 61));
      await tester.pump(const Duration(seconds: 61));
      await tester.pump();
      expect(api.countOf('/getmatchdata/bl1/2026/4'), asked + 1);
    });
  });

  testWidgets('entered from the navigation, the top match of the matchday takes focus', (tester) async {
    final key = GlobalKey<SportLeagueViewState>();
    // A Mac's page (Plebz): a phone and a tablet have the board for touch.
    await pumpLeague(tester, provider(), key: key, variant: AppThemeVariant.glas, platform: TargetPlatform.macOS);

    key.currentState!.focusFirstMatch();
    expect(tester.binding.hasScheduledFrame, isTrue, reason: 'it asks for the frame it waits on');
    await tester.pump();
    await tester.pump();
    // The game on now stands on the stage over the rest (Plebz).
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'sport_favourite_stage');
  });

  testWidgets('asked for while the matchday is loading, the top match takes focus once it is there', (tester) async {
    final key = GlobalKey<SportLeagueViewState>();
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(MonoPalette.dark, variant: AppThemeVariant.glas).copyWith(platform: TargetPlatform.macOS),
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
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'sport_favourite_stage');
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

    // "Current" says which matchday it is; its scores are asked for by number,
    // once — the provider keeps its "current" answer for hours.
    expect(api.countOf('/getmatchdata/bl1/2026/4'), 1);

    // Table and fixtures side by side, not one under the other.
    final fixture = tester.getRect(find.text('FC Bayern München'));
    final tableRow = tester.getRect(find.text('Leipzig'));
    expect(tableRow.left, greaterThan(fixture.right));
  });

  for (final variant in [AppThemeVariant.glasV2, AppThemeVariant.flach]) {
    testWidgets(
      '${variant.name} on a television: the stage, the games as tiles by day, the table at the foot (Plebz)',
      (tester) async {
        TvDetectionService.debugSetAppleTVOverride(true);
        final key = GlobalKey<SportLeagueViewState>();
        await pumpLeague(tester, provider(), key: key, variant: variant);
        await tester.pump(const Duration(seconds: 1));

        expect(tester.takeException(), isNull);
        expect(find.byType(SportStageHero), findsOneWidget);
        expect(find.text('Borussia Dortmund\nRB Leipzig'), findsOneWidget, reason: 'the game on now on the stage');
        // Yesterday's, today's and tomorrow's games, a row each.
        expect(find.byType(SportGameTile), findsNWidgets(3));
        expect(find.text('2 : 1'), findsOneWidget, reason: 'a result on its tile');

        key.currentState!.focusFirstMatch();
        await tester.pump();
        await tester.pump();
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'sport_board_stage');
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'sport_tile_0_401');
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'sport_board_table', reason: 'DOWN reaches the table');

        // A small table on one panel: four clubs need no second (Plebz).
        expect(find.byType(SportTablePanel), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'sport_tile_2_403');
      },
    );
  }

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
    await pumpUntil(tester, () => find.textContaining('Hamburger SV').evaluate().isNotEmpty);
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

  testWidgets('under Flach the matchday is a title on the left, the arrows after it, the table on a panel', (
    tester,
  ) async {
    final key = GlobalKey<SportLeagueViewState>();
    await pumpLeague(tester, provider(), key: key, variant: AppThemeVariant.flach, platform: TargetPlatform.macOS);

    final label = tester.getRect(find.text(t.sport.matchday(n: 4)));
    final previous = tester.getRect(part('sport_matchday_previous'));
    final next = tester.getRect(part('sport_matchday_next'));
    expect(label.right, lessThan(previous.left));
    expect(previous.right, lessThan(next.left));
    expect(find.text(t.sport.table), findsOneWidget, reason: 'a title, not a label in capitals');

    await focusMatchday(tester, key);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'sport_matchday_previous');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'sport_matchday_next');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'sport_matchday');
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
    await pumpUntil(tester, () => find.textContaining('Hamburger SV').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(api.countOf('/getmatchdata/bl1/2026/5'), 1);
    expect(find.text('FC Bayern München'), findsNothing);
    expect(find.text(t.sport.matchday(n: 5)), findsOneWidget);
    expect(find.textContaining(t.sport.current), findsNothing, reason: 'matchday 5 is not the current one');
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'sport_matchday', reason: 'back on the button');
  });

  testWidgets('under Flach a running game on the focus fill keeps its LIVE badge and its scoreboard as they are', (
    tester,
  ) async {
    // A second game on now: the first takes the stage, this one stays a line.
    final api = provider();
    final now = DateTime.now().toUtc();
    (api.routes['/getmatchdata/bl1']! as List).insert(
      2,
      openLigaMatch(
        id: 404,
        matchday: 4,
        kickoffUtc: now.subtract(const Duration(minutes: 20)),
        home: hamburg,
        away: koeln,
        goals: [openLigaGoal(home: 1, away: 0, minute: 9, scorer: 'Glatzel')],
      ),
    );
    // Focus shows as the white fill only while the remote is in use.
    await pumpLeague(tester, api, variant: AppThemeVariant.flach, tracksInput: true, platform: TargetPlatform.macOS);
    Color scoreColour() => tester.widget<Text>(find.text('1 : 0')).style!.color!;
    final tk = tokens(tester.element(find.text('1 : 0')));
    expect(scoreColour(), isNot(tk.ink(1)), reason: 'off focus, the running score in the live colour');

    // DOWN from the game above: a key that navigates is what shows focus.
    tester.widget<FocusableWrapper>(part('sport_match_401')).focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'sport_match_404');

    // The names turn with the fill; the board keeps its own colours.
    expect(OckerFlatFocusInk.invertingAt(tester.element(find.text('Hamburger SV'))), isTrue);
    expect(
      find.ancestor(of: find.text('1 : 0'), matching: find.byType(OckerKeepColours)),
      findsOneWidget,
      reason: 'a scoreboard stays one: black, the score in the live colour, not turned to its complement',
    );
    expect(scoreColour(), isNot(tk.ink(1)));
    expect(
      find.ancestor(of: find.text(t.sport.live), matching: find.byType(OckerKeepColours)),
      findsWidgets,
      reason: 'the badge in its own colours',
    );
  });

  testWidgets('a favourite club\'s game stands on a stage over the rest, and the cursor starts there (Plebz)', (
    tester,
  ) async {
    await SettingsService.instance.write(PlebzPrefs.sportFavouriteClub, dortmund['teamId'] as int);
    final key = GlobalKey<SportLeagueViewState>();
    await pumpLeague(tester, provider(), key: key, variant: AppThemeVariant.flach, platform: TargetPlatform.macOS);

    expect(find.text('Borussia Dortmund – RB Leipzig'), findsOneWidget, reason: 'the pairing under the stage');
    expect(part('sport_match_402'), findsNothing, reason: 'not a second time in the list');
    expect(part('sport_match_401'), findsOneWidget);

    key.currentState!.focusFirstMatch();
    await tester.pump();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'sport_favourite_stage');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'sport_match_401');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'sport_favourite_stage');
  });

  testWidgets('where the favourite does not play, the game on now takes the stage (Plebz)', (tester) async {
    await SettingsService.instance.write(PlebzPrefs.sportFavouriteClub, koeln['teamId'] as int);
    await pumpLeague(tester, provider(), variant: AppThemeVariant.flach, platform: TargetPlatform.macOS);

    expect(find.text('Borussia Dortmund – RB Leipzig'), findsOneWidget);
    expect(part('sport_match_402'), findsNothing, reason: 'not a second time in the list');
  });

  testWidgets('under the redesign the table\'s zones are coloured, with a key under it', (tester) async {
    await pumpLeague(tester, provider(), variant: AppThemeVariant.flach);

    expect(find.text(t.sport.zoneChampionsLeague), findsOneWidget);
    expect(find.text(t.sport.zoneEurope), findsOneWidget);
    expect(find.text(t.sport.zoneRelegation), findsOneWidget);
  });

  testWidgets('under Flach the current matchday\'s "current" turns dark on the focus fill, not its complement', (
    tester,
  ) async {
    final key = GlobalKey<SportLeagueViewState>();
    await pumpLeague(
      tester,
      provider(),
      variant: AppThemeVariant.flach,
      key: key,
      tracksInput: true,
      platform: TargetPlatform.macOS,
    );
    Color currentColour() => tester.widget<Text>(find.text(t.sport.current)).style!.color!;
    final tk = tokens(tester.element(find.text(t.sport.current)));
    expect(currentColour(), isNot(tk.ink(1)), reason: 'off focus, in the live colour');

    await focusMatchday(tester, key);
    // LEFT leads nowhere from the title under Flach; it shows the focus.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'sport_matchday');

    expect(currentColour(), tk.ink(1));
  });

  testWidgets('a game row does not grow on focus: its time would be clipped at the edge', (tester) async {
    await pumpLeague(tester, provider());

    final row = find.ancestor(of: find.text('FC Bayern München'), matching: find.byType(FocusableWrapper)).first;
    expect(tester.widget<FocusableWrapper>(row).disableScale, isTrue);
  });

  // The television draws tiles, not rows (Plebz).
  for (final television in [false]) {
    testWidgets(
      'glas on a ${television ? 'television' : 'Mac'}: a game row keeps room between its plate and its time',
      (tester) async {
        TvDetectionService.debugSetAppleTVOverride(television);
        await pumpLeague(tester, provider(), variant: AppThemeVariant.glas, platform: TargetPlatform.macOS);

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
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'sport_favourite_stage');
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

    // Past the stage, to yesterday's game.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
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
        theme: monoTheme(MonoPalette.dark),
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
    await pumpUntil(tester, () => find.textContaining('Borussia Dortmund').evaluate().isNotEmpty);
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
        theme: monoTheme(MonoPalette.dark),
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
    await pumpUntil(tester, () => find.textContaining('Borussia Dortmund').evaluate().isNotEmpty);

    // The game on now, on the stage.
    await tester.tap(find.textContaining('Borussia Dortmund'));
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
          final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
          if (variant == AppThemeVariant.standard) {
            // The whole table stands beside the fixtures: it is read, not
            // walked, so a club below the edge could never be scrolled to.
            expect(tester.getRect(find.text('Bremen')).bottom, lessThanOrEqualTo(screen.height));
          } else {
            // The board (Plebz): the stage and the first row of tiles on the
            // first screen, the table further down for the cursor to reach.
            expect(tester.getRect(find.byType(SportGameTile).first).bottom, lessThanOrEqualTo(screen.height));
          }
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
      // The table's switch stands last, at the right edge (Plebz).
      expect(next.right, greaterThan(300));
      expect(tester.getRect(part('sport_view_toggle')).right, greaterThan(376));
      expect(next.width, greaterThanOrEqualTo(44), reason: 'a finger-sized target');

      await tester.tap(part('sport_matchday_next'));
      await pumpUntil(tester, () => find.textContaining('Hamburger SV').evaluate().isNotEmpty);
      expect(find.text(t.sport.matchday(n: 5)), findsOneWidget);

      // Its one game stands on the stage.
      await tester.tap(find.textContaining('Hamburger SV'));
      await tester.pumpAndSettle();
      expect(find.byType(SportMatchDetail), findsOneWidget, reason: 'a game opens with a tap too');
    });

    testWidgets('a phone shows the table as a view of its own, switched in the bar (Plebz)', (tester) async {
      await pumpLeague(tester, provider(), size: const Size(400, 860));

      expect(tester.takeException(), isNull);
      expect(find.text('Leipzig'), findsNothing, reason: 'the table is not under the fixtures');
      // A phone's switch is its symbol alone.
      await tester.tap(part('sport_view_toggle'));
      await tester.pumpAndSettle();
      expect(find.text('Leipzig'), findsOneWidget);
      expect(find.text('Freiburg'), findsNothing, reason: 'the fixtures give way to it');
      await tester.tap(part('sport_view_toggle'));
      await tester.pumpAndSettle();
      expect(find.text('Freiburg'), findsOneWidget);
    });

    group('under the redesigns a phone (Plebz)', () {
      Finder tileOf(String club) => find.ancestor(of: find.text(club), matching: find.byType(SportGameTile));

      for (final variant in [AppThemeVariant.glas, AppThemeVariant.flach]) {
        testWidgets('${variant.name}: the games as tiles under one another, the bar inside the screen', (tester) async {
          await pumpLeague(tester, provider(), size: const Size(400, 860), variant: variant);
          await tester.pump(const Duration(seconds: 1));

          expect(tester.takeException(), isNull);
          final first = tester.getRect(tileOf('Freiburg'));
          final second = tester.getRect(tileOf('Bayern').first);
          expect(first.right, lessThanOrEqualTo(400));
          expect((first.left - second.left).abs(), lessThan(1), reason: 'one column');
          expect(first.top != second.top, isTrue, reason: 'under one another, not side by side');
          final next = tester.getRect(part('sport_matchday_next'));
          expect(next.right, lessThanOrEqualTo(400));
          expect(next.width, greaterThanOrEqualTo(44), reason: 'a finger-sized target');
        });
      }

      for (final variant in [AppThemeVariant.glas, AppThemeVariant.flach]) {
        testWidgets('${variant.name}: a day named as the start page names a row, "current" in the accent', (
          tester,
        ) async {
          await pumpLeague(tester, provider(), size: const Size(400, 860), variant: variant);
          await tester.pump(const Duration(seconds: 1));

          // Glas's bold sentence case, Flach's label in capitals (HubSection).
          if (variant == AppThemeVariant.glas) {
            final heading = tester.widget<Text>(find.textContaining(t.sport.yesterday));
            expect(heading.style?.fontWeight, FontWeight.w700);
          } else {
            expect(find.textContaining(t.sport.yesterday.toUpperCase()), findsOneWidget);
          }
          final bar = tester.widget<RichText>(
            find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains(t.sport.current)),
          );
          Color? current;
          bar.text.visitChildren((span) {
            if (span is TextSpan && span.text == t.sport.current) current = span.style?.color;
            return true;
          });
          expect(current, tokens(tester.element(find.byType(SportTouchStage))).accent);
        });
      }

      testWidgets('the switch under the stage turns the page to the table and back', (tester) async {
        await pumpLeague(tester, provider(), size: const Size(400, 860), variant: AppThemeVariant.glas);
        await tester.pump(const Duration(seconds: 1));

        expect(find.text(t.sport.zoneChampionsLeague), findsNothing, reason: 'the games first');
        await tester.tap(find.text(t.sport.table));
        await tester.pumpAndSettle();
        expect(find.text(t.sport.zoneChampionsLeague), findsOneWidget);
        expect(find.byType(SportGameTile), findsNothing, reason: 'the games give way to it');
        await tester.tap(find.text(t.sport.fixtures));
        await tester.pumpAndSettle();
        expect(find.byType(SportGameTile), findsWidgets);
      });

      testWidgets('on its side keeps the table off the fixtures\' side, a view of its own', (tester) async {
        await pumpLeague(tester, provider(), size: const Size(860, 400), variant: AppThemeVariant.glas);
        await tester.pump(const Duration(seconds: 1));

        expect(tester.takeException(), isNull);
        expect(find.text(t.sport.zoneChampionsLeague), findsNothing, reason: 'not squeezed in beside the fixtures');
        expect(find.text(t.sport.table), findsOneWidget, reason: 'the switch to it');
      });

      testWidgets('the stage starts right under the bar, with no status bar\'s gap between', (tester) async {
        tester.view.padding = const FakeViewPadding(top: 80);
        addTearDown(tester.view.resetPadding);
        await pumpLeague(tester, provider(), size: const Size(400, 860), variant: AppThemeVariant.glas);
        await tester.pump(const Duration(seconds: 1));

        final bar = tester.getRect(part('sport_matchday_next'));
        final stage = tester.getRect(find.byType(SportTouchStage)).top;
        expect(stage - bar.bottom, lessThan(40));
      });

      testWidgets('a game opens with a tap on its tile', (tester) async {
        await pumpLeague(tester, provider(), size: const Size(400, 860), variant: AppThemeVariant.glas);
        await tester.pump(const Duration(seconds: 1));

        await tester.ensureVisible(tileOf('Freiburg'));
        await tester.pumpAndSettle();
        await tester.tap(tileOf('Freiburg'));
        await tester.pumpAndSettle();
        expect(find.byType(SportMatchDetail), findsOneWidget);
      });

      testWidgets('the stage\'s game opens with "Zum Spiel"', (tester) async {
        await pumpLeague(tester, provider(), size: const Size(400, 860), variant: AppThemeVariant.glas);
        await tester.pump(const Duration(seconds: 1));

        await tester.tap(find.text(t.sport.toMatch));
        await tester.pumpAndSettle();
        expect(find.byType(SportMatchDetail), findsOneWidget);
      });

      testWidgets('a swipe on the stage steps to the next game, and says where it stands', (tester) async {
        await pumpLeague(tester, provider(), size: const Size(400, 860), variant: AppThemeVariant.glas);
        await tester.pump(const Duration(seconds: 1));

        // The game on now stands there first.
        expect(find.text('Borussia Dortmund – RB Leipzig'), findsOneWidget);
        await tester.fling(find.byType(SportTouchStage), const Offset(-300, 0), 1000);
        await tester.pumpAndSettle();
        expect(find.text('SC Freiburg – 1. FSV Mainz 05'), findsOneWidget);
        expect(find.text(t.sport.stagePosition(n: 3, total: 3)), findsOneWidget);
      });
    });

    group('under the redesigns a tablet (Plebz)', () {
      testWidgets('held across: the table beside the games, no switch', (tester) async {
        await pumpLeague(tester, provider(), size: const Size(1280, 800), variant: AppThemeVariant.glas);
        await tester.pump(const Duration(seconds: 1));

        expect(tester.takeException(), isNull);
        expect(find.text(t.sport.zoneChampionsLeague), findsOneWidget);
        expect(find.text(t.sport.fixtures), findsNothing, reason: 'nothing to switch');
        final table = tester.getRect(find.text(t.sport.zoneChampionsLeague));
        final tile = tester.getRect(find.byType(SportGameTile).first);
        expect(table.left, greaterThan(tile.right), reason: 'the table at the right of the games');
        expect(
          tester.getRect(find.text(t.sport.zoneRelegation)).bottom,
          lessThanOrEqualTo(800),
          reason: 'the whole table fits the page, its key included',
        );
      });

      testWidgets('upright: a phone\'s page, the tiles in pairs', (tester) async {
        await pumpLeague(tester, provider(), size: const Size(800, 1280), variant: AppThemeVariant.glas);
        await tester.pump(const Duration(seconds: 1));

        expect(tester.takeException(), isNull);
        expect(find.text(t.sport.table), findsOneWidget, reason: 'the switch to the table');
        // The day before yesterday's and today's game share no row; the two
        // of matchday 4 on one day stand side by side where there are two.
        final tiles = find.byType(SportGameTile);
        expect(tiles, findsWidgets);
        expect(tester.getRect(tiles.first).width, lessThan(400), reason: 'two to a row');
      });
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
