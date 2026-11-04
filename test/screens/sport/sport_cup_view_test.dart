import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:plezy/focus/focusable_wrapper.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/navigation/main_screen_scope.dart';
import 'package:plezy/screens/sport/sport_board_widgets.dart';
import 'package:plezy/screens/sport/sport_league_management_sheet.dart';
import 'package:plezy/screens/sport/sport_league_view.dart';
import 'package:plezy/screens/sport/sport_screen.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/sport/sport_models.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/platform_detector.dart';

import '../../test_helpers/prefs.dart';
import '../../test_helpers/pump.dart';
import '../../test_helpers/sport_fixtures.dart';

/// The cups (Plebz): switched on under "Ligen verwalten", the DFB-Pokal
/// without a table, a European cup's table as a view of its own in two
/// columns.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('en'));

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

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

  FakeOpenLigaDb provider() => FakeOpenLigaDb({
    ...league('bl1', 'FC Bayern München', 'Werder Bremen'),
    ...league('bl2', 'Hertha BSC', 'FC Schalke 04'),
    ...league('bl3', 'TSV 1860 München', 'Alemannia Aachen'),
    '/getmatchdata/dfb': [
      openLigaMatch(
        id: 9001,
        matchday: 2,
        groupName: '2. Runde',
        kickoffUtc: DateTime.now().toUtc().subtract(const Duration(days: 1)),
        home: openLigaTeam(9001, 'Eintracht Frankfurt'),
        away: openLigaTeam(9002, 'Borussia Dortmund'),
        finished: true,
        result: (1, 1),
        extraTime: (1, 1),
        penalties: (3, 5),
      ),
    ],
    '/getavailablegroups/dfb/2026': [
      {'groupName': '1. Runde', 'groupOrderID': 1, 'groupID': 1},
      {'groupName': '2. Runde', 'groupOrderID': 2, 'groupID': 2},
      {'groupName': 'Achtelfinale', 'groupOrderID': 3, 'groupID': 3},
    ],
    '/getmatchdata/ucl': [
      openLigaMatch(
        id: 7001,
        matchday: 3,
        groupName: '3.Spieltag',
        kickoffUtc: kickoff,
        home: openLigaTeam(7001, 'Real Madrid'),
        away: openLigaTeam(7002, 'Juventus'),
      ),
    ],
    '/getavailablegroups/ucl/2026': [
      for (var i = 1; i <= 8; i++) {'groupName': '$i. Spieltag', 'groupOrderID': i, 'groupID': i},
      {'groupName': 'Achtelfinale Hinspiele', 'groupOrderID': 10, 'groupID': 10},
    ],
    '/getbltable/ucl/2026': [for (var i = 1; i <= 36; i++) openLigaTableRow(7100 + i, 'Club $i', points: 40 - i)],
  });

  Future<void> pump(WidgetTester tester, Widget child, {AppThemeVariant variant = AppThemeVariant.standard}) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(MonoPalette.dark, variant: variant),
        home: MainScreenFocusScope(
          focusSidebar: () {},
          sideNavigationWidth: 0,
          child: Scaffold(body: child),
        ),
      ),
    );
  }

  Widget view(SportLeague league, FakeOpenLigaDb api) =>
      SportLeagueView(league: league, isActive: true, onExitUp: () {}, repository: api.repository());

  testWidgets('a cup switched on under "Ligen verwalten" joins the leagues, a hidden league leaves', (tester) async {
    final api = provider();
    await pump(tester, SportScreen(repository: api.repository()));
    await pumpUntil(tester, () => find.textContaining('FC Bayern München').evaluate().isNotEmpty);
    expect(find.text(t.sport.championsLeague), findsNothing);

    final layout = SportLeagueLayout.decode(
      '',
    ).withHidden(SportLeague.championsLeague, false).withHidden(SportLeague.liga3, true);
    await SettingsService.instance.write(PlebzPrefs.sportLeagueLayout, layout.encode());
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text(t.sport.championsLeague), findsOneWidget);
    expect(find.text(t.sport.liga3), findsNothing);

    await tester.tap(find.text(t.sport.championsLeague));
    await pumpUntil(tester, () => find.textContaining('Real Madrid').evaluate().isNotEmpty);
  });

  testWidgets('"Ligen verwalten" lists every competition and switches one on', (tester) async {
    await pump(tester, const SportLeagueManagementList(isDialog: true));
    await tester.pump();

    expect(find.text(t.sport.manageLeagues), findsOneWidget);
    for (final name in [t.sport.bundesliga1, t.sport.championsLeague, t.sport.europaLeague, t.sport.dfbPokal]) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text(t.sport.europaLeagueLate), findsOneWidget, reason: 'its results come late, and it says so');

    final cupRow = find.ancestor(of: find.text(t.sport.dfbPokal), matching: find.byType(ListTile));
    await tester.tap(find.descendant(of: cupRow, matching: find.byTooltip(t.sport.showLeague)));
    await tester.pump();
    final stored = SportLeagueLayout.decode(SettingsService.instance.read(PlebzPrefs.sportLeagueLayout));
    expect(stored.visible, contains(SportLeague.dfbPokal));
  });

  testWidgets('the DFB-Pokal shows its round by name, no table, and how a tie was decided', (tester) async {
    final api = provider();
    await pump(tester, view(SportLeague.dfbPokal, api));
    await pumpUntil(tester, () => find.textContaining('Eintracht Frankfurt').evaluate().isNotEmpty);

    expect(tester.takeException(), isNull);
    expect(find.text('2. Runde'), findsOneWidget);
    expect(find.text(t.sport.table), findsNothing);
    expect(find.text(t.sport.onPenalties(score: '3:5')), findsOneWidget);
  });

  testWidgets('standard: a European cup\'s table is a view of its own, in two columns', (tester) async {
    final api = provider();
    await pump(tester, view(SportLeague.championsLeague, api));
    await pumpUntil(tester, () => find.textContaining('Real Madrid').evaluate().isNotEmpty);
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(find.text(t.sport.matchday(n: 3)), findsOneWidget, reason: 'the league phase counts its matchdays');
    expect(find.text('Club 1'), findsNothing, reason: 'the fixtures take the page; the table waits');

    await tester.tap(find.text(t.sport.table));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Real Madrid'), findsNothing);
    final first = tester.getTopLeft(find.text('Club 1'));
    final nineteenth = tester.getTopLeft(find.text('Club 19'));
    expect(nineteenth.dx, greaterThan(first.dx + 400), reason: 'places 19 to 36 stand in a column of their own');
    expect((nineteenth.dy - first.dy).abs(), lessThan(2), reason: 'side by side, level with places 1 to 18');
    expect(find.text('Club 36'), findsOneWidget);
    expect(find.text(t.sport.fixtures), findsOneWidget, reason: 'and the bar leads back to the games');
  });

  for (final variant in [AppThemeVariant.glasV2, AppThemeVariant.flach]) {
    testWidgets('${variant.name} on a television: a European cup\'s table at the foot, four panels to walk (Plebz)', (
      tester,
    ) async {
      TvDetectionService.debugSetAppleTVOverride(true);
      addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
      final api = provider();
      await pump(tester, view(SportLeague.championsLeague, api), variant: variant);
      await pumpUntil(tester, () => find.textContaining('Real Madrid').evaluate().isNotEmpty);
      await tester.pump(const Duration(seconds: 1));

      expect(tester.takeException(), isNull);
      expect(
        find.byWidgetPredicate((w) => w is FocusableWrapper && w.focusNode?.debugLabel == 'sport_view_toggle'),
        findsNothing,
        reason: 'no switch: the table is on the page',
      );
      // Nine places a panel, two side by side on the screen.
      expect(sportTablePanels(List.generate(36, (i) => i)).map((panel) => panel.length), [9, 9, 9, 9]);
      final first = tester.getTopLeft(find.text('Club 1'));
      final tenth = tester.getTopLeft(find.text('Club 10'));
      expect(tenth.dx, greaterThan(first.dx + 400), reason: 'places 10 to 18 on the panel beside');
      expect((tenth.dy - first.dy).abs(), lessThan(2), reason: 'level with places 1 to 9');
      expect(first.dy, greaterThan(tester.getRect(find.byType(SportGameTile)).bottom));
    });
  }

  testWidgets('a European cup\'s German clubs\' row tells each game\'s day under its kickoff (Plebz)', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    final api = provider();
    api.routes['/getmatchdata/ucl'] = [
      ...api.routes['/getmatchdata/ucl']! as List,
      openLigaMatch(
        id: 7003,
        matchday: 3,
        groupName: '3.Spieltag',
        kickoffUtc: kickoff,
        home: openLigaTeam(40, 'FC Bayern München'),
        away: openLigaTeam(7004, 'Paris Saint-Germain'),
      ),
    ];
    await pump(tester, view(SportLeague.championsLeague, api), variant: AppThemeVariant.glasV2);
    await pumpUntil(tester, () => find.textContaining('Real Madrid').evaluate().isNotEmpty);
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    Finder tile(String label) =>
        find.byWidgetPredicate((w) => w is FocusableWrapper && w.focusNode?.debugLabel == label);
    final date = DateFormat.MMMEd('en').format(kickoff.toLocal());
    expect(find.text(t.sport.withGermanClubs), findsOneWidget);
    expect(find.descendant(of: tile('sport_tile_0_7003'), matching: find.text(date)), findsOneWidget);
    expect(
      find.descendant(of: tile('sport_tile_1_7003'), matching: find.text(date)),
      findsNothing,
      reason: 'a row of one day has its date in its name',
    );
  });

  testWidgets('the DFB-Pokal on a television ends on its rounds, the one being played marked (Plebz)', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    final api = provider();
    await pump(tester, view(SportLeague.dfbPokal, api), variant: AppThemeVariant.glasV2);
    await pumpUntil(tester, () => find.textContaining('Eintracht Frankfurt').evaluate().isNotEmpty);
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(find.text(t.sport.roadToFinal), findsOneWidget);
    for (final round in ['1. Runde', 'Achtelfinale']) {
      expect(find.text(round), findsOneWidget);
    }
    expect(find.text(t.sport.roundPlayed), findsOneWidget, reason: 'the round behind says so');
    expect(find.text(t.sport.onPenalties(score: '3:5')), findsWidgets, reason: 'how the tie was decided');
  });
}
