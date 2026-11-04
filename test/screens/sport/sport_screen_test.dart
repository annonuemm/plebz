import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/navigation/main_screen_scope.dart';
import 'package:plezy/navigation/navigation_tabs.dart';
import 'package:plezy/focus/focusable_wrapper.dart';
import 'package:plezy/redesign/ocker_glide_edge.dart';
import 'package:plezy/screens/sport/sport_board_widgets.dart';
import 'package:plezy/screens/sport/sport_screen.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/theme/mono_tokens.dart';

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

  FakeOpenLigaDb provider() {
    final kickoff = DateTime.now().toUtc().add(const Duration(days: 1));
    Map<String, Object?> league(String shortcut, String home, String away) => {
      '/getmatchdata/$shortcut': [
        openLigaMatch(
          id: shortcut.hashCode,
          matchday: 4,
          kickoffUtc: kickoff,
          home: openLigaTeam(shortcut.hashCode, home),
          away: openLigaTeam(shortcut.hashCode + 1, away),
        ),
      ],
      '/getavailablegroups/$shortcut/2026': openLigaMatchdays(34),
      '/getbltable/$shortcut/2026': [openLigaTableRow(shortcut.hashCode, home, points: 3)],
    };
    return FakeOpenLigaDb({
      ...league('bl1', 'FC Bayern München', 'Werder Bremen'),
      ...league('bl2', 'Hertha BSC', 'FC Schalke 04'),
      ...league('bl3', 'TSV 1860 München', 'Alemannia Aachen'),
    });
  }

  Future<GlobalKey<SportScreenState>> pumpScreen(
    WidgetTester tester,
    AppThemeVariant variant, {
    VoidCallback? onSidebar,
  }) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final key = GlobalKey<SportScreenState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(MonoPalette.dark, variant: variant),
        home: MainScreenFocusScope(
          focusSidebar: onSidebar ?? () {},
          sideNavigationWidth: 0,
          child: Scaffold(
            body: SportScreen(key: key, repository: provider().repository()),
          ),
        ),
      ),
    );
    await pumpUntil(tester, () => find.text('FC Bayern München').evaluate().isNotEmpty);
    return key;
  }

  testWidgets('standard: the three leagues are chips across the top', (tester) async {
    await pumpScreen(tester, AppThemeVariant.standard);

    expect(tester.takeException(), isNull);
    expect(find.text(t.sport.bundesliga1), findsOneWidget);
    expect(find.text(t.sport.bundesliga2), findsOneWidget);
    expect(find.text(t.sport.liga3), findsOneWidget);
    expect(find.text(t.sport.bundesliga1.toUpperCase()), findsNothing, reason: 'the chip already says which');
  });

  testWidgets('standard: a chip is opened by confirming it', (tester) async {
    await pumpScreen(tester, AppThemeVariant.standard);

    await tester.tap(find.text(t.sport.bundesliga2));
    await pumpUntil(tester, () => find.text('Hertha BSC').evaluate().isNotEmpty);
  });

  testWidgets('redesign: no chips; the league on show is named, and the rail chooses another', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    final key = await pumpScreen(tester, AppThemeVariant.glas);

    expect(tester.takeException(), isNull);
    // Glas names the league as Flach does, in sentence case over the page.
    expect(find.text(t.sport.bundesliga1).hitTestable(), findsOneWidget);
    expect(find.text(t.sport.bundesliga2).hitTestable(), findsNothing);

    key.currentState!.ockerRailMenu!.items[2].onSelect();
    await pumpUntil(tester, () => find.textContaining('TSV 1860 München').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    // Each league names itself in its own bar (Plebz); the one left behind
    // stays alive off screen.
    expect(find.text(t.sport.liga3).hitTestable(), findsOneWidget);
    expect(find.text(t.sport.bundesliga1).hitTestable(), findsNothing);
  });

  testWidgets('redesign: the page lays no flat ground over the glass one', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    await pumpScreen(tester, AppThemeVariant.glas);

    final screen = find.byType(SportScreen);
    final ground = Theme.of(tester.element(screen)).extension<MonoTokens>()!.bg;
    expect(
      find.descendant(of: screen, matching: find.byWidgetPredicate((w) => w is ColoredBox && w.color == ground)),
      findsNothing,
      reason: 'a flat fill covered the gradient everywhere but under the rail',
    );
  });

  testWidgets(
    'Glas on the television: the stage\'s ground is drawn once and the page glides as the start page (Plebz)',
    (tester) async {
      TvDetectionService.debugSetAppleTVOverride(true);
      addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final kickoff = DateTime.now().toUtc().add(const Duration(days: 1));
      final api = provider();
      // Two clubs with colours of their own, on three days: three rows to walk.
      api.routes['/getmatchdata/bl1'] = [
        for (var i = 0; i < 3; i++)
          openLigaMatch(
            id: 500 + i,
            matchday: 4,
            kickoffUtc: kickoff.add(Duration(days: i)),
            home: openLigaTeam(40, 'FC Bayern München'),
            away: openLigaTeam(7, 'Borussia Dortmund'),
          ),
      ];
      final key = GlobalKey<SportScreenState>();
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(MonoPalette.dark, variant: AppThemeVariant.glasV2),
          home: MainScreenFocusScope(
            focusSidebar: () {},
            sideNavigationWidth: 0,
            child: Scaffold(
              body: SportScreen(key: key, repository: api.repository()),
            ),
          ),
        ),
      );
      await pumpUntil(tester, () => find.textContaining('Borussia Dortmund').evaluate().isNotEmpty);
      key.currentState!.focusActiveTabIfReady();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(SportStageGrounds.debugPrepared, greaterThan(0), reason: 'the clubs\' ground is a prepared picture');
      expect(tester.layers.whereType<ShaderMaskLayer>(), isEmpty, reason: 'at rest nothing is masked offscreen');

      final prepared = SportStageGrounds.debugPrepared;
      ScrollController board() => tester
          .widget<SingleChildScrollView>(
            find.descendant(of: find.byType(OckerGlideEdge), matching: find.byType(SingleChildScrollView)).first,
          )
          .controller!;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.layers.whereType<ShaderMaskLayer>(), isNotEmpty, reason: 'while it glides, the top edge is soft');
      await tester.pumpAndSettle();

      expect(FocusManager.instance.primaryFocus?.debugLabel, 'sport_tile_1_501');
      expect(board().offset, greaterThan(0), reason: 'the row the cursor went to glides up to the top');
      final above = tester.getRect(
        find.byWidgetPredicate((w) => w is FocusableWrapper && w.focusNode?.debugLabel == 'sport_tile_0_500'),
      );
      expect(
        above.bottom,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(OckerGlideEdge)).dy + 0.5),
        reason: 'the row above is out of sight, not a strip under the bar',
      );
      expect(tester.layers.whereType<ShaderMaskLayer>(), isEmpty, reason: 'and settles whole, the edge gone');
      expect(
        SportStageGrounds.debugPrepared,
        prepared,
        reason: 'fading the ground as the page scrolls draws nothing anew',
      );
    },
  );

  for (final named in [true, false]) {
    testWidgets(
      'a handheld under Glas: ${named ? 'named by the navigation, no title, the leagues up' : 'not named by it, the title stays'} (Plebz)',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: monoTheme(MonoPalette.dark, variant: AppThemeVariant.glasV2),
            home: MainScreenNamedPlaces(
              places: named ? const {NavigationTabId.sport} : const {},
              child: MainScreenFocusScope(
                focusSidebar: () {},
                sideNavigationWidth: 0,
                child: Scaffold(body: SportScreen(repository: provider().repository())),
              ),
            ),
          ),
        );
        await pumpUntil(tester, () => find.textContaining('Bayern').evaluate().isNotEmpty);

        expect(tester.takeException(), isNull);
        expect(find.text(t.navigation.sport), named ? findsNothing : findsOneWidget);
        final league = tester.getRect(find.text(t.sport.bundesliga1));
        final refresh = tester.getRect(find.byTooltip(t.common.refresh));
        if (named) {
          expect(
            (league.center.dy - refresh.center.dy).abs(),
            lessThan(8),
            reason: 'the leagues in the bar, beside its buttons',
          );
        } else {
          expect(league.top, greaterThan(refresh.bottom), reason: 'the leagues on a line under the title');
        }
      },
    );
  }

  testWidgets('a phone upright: the leagues in the bar stop where its buttons begin (Plebz)', (tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(MonoPalette.dark, variant: AppThemeVariant.glasV2),
        home: MainScreenNamedPlaces(
          places: const {NavigationTabId.sport},
          child: MainScreenFocusScope(
            focusSidebar: () {},
            sideNavigationWidth: 0,
            child: Scaffold(body: SportScreen(repository: provider().repository())),
          ),
        ),
      ),
    );
    await pumpUntil(tester, () => find.textContaining('Bayern').evaluate().isNotEmpty);

    expect(tester.takeException(), isNull);
    final strip = find.ancestor(of: find.text(t.sport.liga3), matching: find.byType(ClipRect)).first;
    final buttons = tester.getRect(find.byTooltip(t.sport.manageLeagues));
    expect(tester.getRect(strip).right, lessThanOrEqualTo(buttons.left), reason: 'the tabs end before the buttons');
  });

  testWidgets('redesign: LEFT off a match goes to the rail, not only UP off the top', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    var rail = 0;
    final key = await pumpScreen(tester, AppThemeVariant.glas, onSidebar: () => rail++);
    key.currentState!.focusActiveTabIfReady();
    await tester.pumpAndSettle();
    // The stage's button first, on the television's board (Plebz).
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'sport_board_stage');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(rail, 1);
  });

  testWidgets('redesign: the leagues are rows for the rail, and choosing one goes to its top match', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    final key = await pumpScreen(tester, AppThemeVariant.glas);
    final menu = key.currentState!.ockerRailMenu!;
    expect(menu.items.map((item) => item.label), [
      t.sport.bundesliga1,
      t.sport.bundesliga2,
      t.sport.liga3,
      t.sport.manageLeagues,
      t.common.refresh,
    ]);
    expect(menu.items.first.selected, isTrue);
    expect(menu.items[3].gapBefore, isTrue, reason: 'a gap divides the leagues from what else the page has');

    menu.items[2].onSelect();
    await pumpUntil(tester, () => find.text('TSV 1860 München').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'sport_board_stage');
  });
}
