import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/navigation/main_screen_scope.dart';
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
        theme: monoTheme(dark: true, variant: variant),
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
    expect(find.text(t.sport.bundesliga1.toUpperCase()), findsOneWidget);
    expect(find.text(t.sport.bundesliga2), findsNothing);

    key.currentState!.ockerRailMenu!.items[2].onSelect();
    await pumpUntil(tester, () => find.text('TSV 1860 München').evaluate().isNotEmpty);
    expect(find.text(t.sport.liga3.toUpperCase()), findsOneWidget);
    expect(find.text(t.sport.bundesliga1.toUpperCase()), findsNothing);
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

  testWidgets('redesign: LEFT off a match goes to the rail, not only UP off the top', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    var rail = 0;
    final key = await pumpScreen(tester, AppThemeVariant.glas, onSidebar: () => rail++);
    key.currentState!.focusActiveTabIfReady();
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'sport_match_${'bl1'.hashCode}');

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
      t.common.refresh,
    ]);
    expect(menu.items.first.selected, isTrue);
    expect(menu.items.last.gapBefore, isTrue, reason: 'a gap divides the leagues from refresh');

    menu.items[2].onSelect();
    await pumpUntil(tester, () => find.text('TSV 1860 München').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'sport_match_${'bl3'.hashCode}');
  });
}
