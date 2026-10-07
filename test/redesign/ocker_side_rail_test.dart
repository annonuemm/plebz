import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/navigation/main_screen_scope.dart';
import 'package:plezy/navigation/navigation_tabs.dart';
import 'package:plezy/redesign/ocker_browse_page.dart';
import 'package:plezy/redesign/ocker_detail_panel.dart';
import 'package:plezy/redesign/ocker_filter_glyph.dart';
import 'package:plezy/redesign/ocker_header_slot.dart';
import 'package:plezy/redesign/ocker_library_column.dart';
import 'package:plezy/redesign/ocker_panel_frame.dart';
import 'package:plezy/redesign/ocker_poster_tile.dart';
import 'package:plezy/redesign/ocker_rail_shell.dart';
import 'package:plezy/redesign/ocker_side_rail.dart';
import 'package:plezy/redesign/ocker_skin.dart';
import 'package:plezy/redesign/ocker_submenu.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/app_icon.dart';
import 'package:plezy/widgets/app_menu.dart';

import '../test_helpers/media_items.dart';
import '../test_helpers/prefs.dart';

/// "Redesign – Glas": the redesign's screens beside its side rail — the
/// describing column on the right, the libraries in a column that opens beside
/// the page, and the focus paths to match.
ThemeData _railTheme() => monoTheme(dark: true, variant: AppThemeVariant.glas);

void main() {
  setUpAll(() {
    LocaleSettings.setLocaleSync(AppLocale.en);
    return initializeDateFormatting('en');
  });

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  void tvView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('the rail', () {
    final tabs = NavigationTab.getVisibleTabs(isOffline: false);

    Future<({List<NavigationTabId> selected, List<NavigationTabId> reselected, int Function() toContent})> pumpRail(
      WidgetTester tester, {
      required GlobalKey<OckerSideRailState> key,
      bool expanded = true,
      NavigationTabId selectedTab = NavigationTabId.libraries,
      OckerRailMenu? menu,
      bool settle = true,
    }) async {
      tvView(tester);
      final selected = <NavigationTabId>[];
      final reselected = <NavigationTabId>[];
      var toContent = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: _railTheme(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                height: 720,
                child: OckerSideRail(
                  key: key,
                  tabs: tabs,
                  selectedTab: selectedTab,
                  expanded: expanded,
                  onDestinationSelected: selected.add,
                  onNavigateToContent: () => toContent++,
                  onReselect: (id) {
                    reselected.add(id);
                    return true;
                  },
                  menuFor: (id) => id == selectedTab ? menu : null,
                ),
              ),
            ),
          ),
        ),
      );
      if (settle) await tester.pumpAndSettle();
      return (selected: selected, reselected: reselected, toContent: () => toContent);
    }

    bool hasFocus(WidgetTester tester, NavigationTabId id) => Focus.of(
      tester.element(find.descendant(of: find.byKey(OckerSideRail.itemKey(id)), matching: find.byType(Text)).first),
    ).hasFocus;

    testWidgets('it lands on the destination on show and walks up and down', (tester) async {
      final key = GlobalKey<OckerSideRailState>();
      await pumpRail(tester, key: key);
      key.currentState!.focusSelected();
      await tester.pump();

      final index = tabs.indexWhere((tab) => tab.id == NavigationTabId.libraries);
      expect(hasFocus(tester, NavigationTabId.libraries), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(hasFocus(tester, tabs[index + 1].id), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(hasFocus(tester, tabs[index - 1].id), isTrue);
    });

    testWidgets('the ends stop rather than wrap', (tester) async {
      final key = GlobalKey<OckerSideRailState>();
      await pumpRail(tester, key: key);
      key.currentState!.focusTab(tabs.first.id);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(hasFocus(tester, tabs.first.id), isTrue);
    });

    testWidgets('SELECT goes to a destination; again on the one on show it opens what is behind it', (tester) async {
      final key = GlobalKey<OckerSideRailState>();
      final calls = await pumpRail(tester, key: key);
      key.currentState!.focusSelected();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(calls.reselected, [NavigationTabId.libraries]);
      expect(calls.selected, isEmpty);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      final index = tabs.indexWhere((tab) => tab.id == NavigationTabId.libraries);
      expect(calls.selected, [tabs[index - 1].id]);
    });

    testWidgets('RIGHT goes back into the content; LEFT goes nowhere', (tester) async {
      final key = GlobalKey<OckerSideRailState>();
      final calls = await pumpRail(tester, key: key);
      key.currentState!.focusSelected();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(hasFocus(tester, NavigationTabId.libraries), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(calls.toContent(), 1);
    });

    group('the rows under the destination on show', () {
      late List<String> chosen;
      OckerRailMenu menu() => OckerRailMenu([
        OckerRailItem(label: 'Empfohlen', onSelect: () => chosen.add('Empfohlen')),
        OckerRailItem(label: 'Durchsuchen', selected: true, onSelect: () => chosen.add('Durchsuchen')),
        OckerRailItem(label: 'Sammlungen', onSelect: () => chosen.add('Sammlungen')),
      ]);

      setUp(() => chosen = []);

      bool subHasFocus(WidgetTester tester, int index) => Focus.of(
        tester.element(find.descendant(of: find.byKey(OckerSideRail.subItemKey(index)), matching: find.byType(Text))),
      ).hasFocus;

      testWidgets('stand in the rail, not in a sheet, and only while it is open', (tester) async {
        final key = GlobalKey<OckerSideRailState>();
        await pumpRail(tester, key: key, expanded: false, menu: menu());
        expect(find.text('Durchsuchen'), findsNothing);

        await pumpRail(tester, key: key, menu: menu());
        for (final label in ['Empfohlen', 'Durchsuchen', 'Sammlungen']) {
          expect(find.text(label), findsOneWidget);
        }
        final parent = tester.getRect(find.byKey(OckerSideRail.itemKey(NavigationTabId.libraries)));
        final first = tester.getRect(find.byKey(OckerSideRail.subItemKey(0)));
        expect(first.top, closeTo(parent.bottom, 1), reason: 'directly under the destination they belong to');
        final next = tabs[tabs.indexWhere((tab) => tab.id == NavigationTabId.libraries) + 1];
        expect(
          tester.getRect(find.byKey(OckerSideRail.itemKey(next.id))).top,
          greaterThanOrEqualTo(tester.getRect(find.byKey(OckerSideRail.subItemKey(2))).bottom),
          reason: 'the destinations below make room',
        );
      });

      testWidgets('arriving from the page lands on the row on show, not on its destination', (tester) async {
        final key = GlobalKey<OckerSideRailState>();
        await pumpRail(tester, key: key, expanded: false, menu: menu());
        // As the host does it: the rail asked open, and the cursor put on it
        // after that frame — before the pane has begun to move.
        await pumpRail(tester, key: key, menu: menu(), settle: false);
        key.currentState!.focusSelected();
        await tester.pumpAndSettle();
        expect(subHasFocus(tester, 1), isTrue, reason: '"Durchsuchen" is on show');
        expect(hasFocus(tester, NavigationTabId.libraries), isFalse);

        // From there the rows walk as ever.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        expect(subHasFocus(tester, 0), isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        expect(hasFocus(tester, NavigationTabId.libraries), isTrue);
      });

      testWidgets('with none on show, or the rows folded away, it lands on the destination', (tester) async {
        final key = GlobalKey<OckerSideRailState>();
        await pumpRail(
          tester,
          key: key,
          menu: OckerRailMenu([
            OckerRailItem(label: 'Suche', onSelect: () {}),
            OckerRailItem(label: 'Aktualisieren', onSelect: () {}),
          ]),
        );
        key.currentState!.focusSelected();
        await tester.pump();
        expect(hasFocus(tester, NavigationTabId.libraries), isTrue);

        final folded = GlobalKey<OckerSideRailState>();
        await pumpRail(tester, key: folded, menu: menu());
        folded.currentState!.focusTab(NavigationTabId.libraries);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        folded.currentState!.focusSelected();
        await tester.pump();
        expect(hasFocus(tester, NavigationTabId.libraries), isTrue);
      });

      testWidgets('DOWN walks into them and on to the next destination; LEFT goes back up to theirs', (tester) async {
        final key = GlobalKey<OckerSideRailState>();
        await pumpRail(tester, key: key, menu: menu());
        key.currentState!.focusTab(NavigationTabId.libraries);
        await tester.pump();

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(subHasFocus(tester, 0), isTrue);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        final next = tabs[tabs.indexWhere((tab) => tab.id == NavigationTabId.libraries) + 1];
        expect(hasFocus(tester, next.id), isTrue);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        expect(subHasFocus(tester, 2), isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(hasFocus(tester, NavigationTabId.libraries), isTrue);
      });

      testWidgets('it says when the cursor is on one of the rows, for a page loading behind it', (tester) async {
        final key = GlobalKey<OckerSideRailState>();
        await pumpRail(tester, key: key, menu: menu());
        key.currentState!.focusTab(NavigationTabId.libraries);
        await tester.pump();
        expect(OckerSideRail.subRowFocused, isFalse, reason: 'on the destination itself');

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(OckerSideRail.subRowFocused, isTrue);
      });

      testWidgets('a second press on the destination folds its rows and back, and the cursor stays', (tester) async {
        final key = GlobalKey<OckerSideRailState>();
        final calls = await pumpRail(tester, key: key, menu: menu());
        key.currentState!.focusTab(NavigationTabId.libraries);
        await tester.pump();

        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(find.text('Durchsuchen'), findsNothing, reason: 'folded away');
        expect(hasFocus(tester, NavigationTabId.libraries), isTrue, reason: 'not sent back into the page');
        expect(calls.selected, isEmpty);
        expect(calls.reselected, isEmpty);
        expect(calls.toContent(), 0);

        // Folded, DOWN goes straight on to the next destination.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        final next = tabs[tabs.indexWhere((tab) => tab.id == NavigationTabId.libraries) + 1];
        expect(hasFocus(tester, next.id), isTrue);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(find.text('Durchsuchen'), findsOneWidget, reason: 'and back');
      });

      testWidgets('SELECT on a row does what choosing it in the sheet did', (tester) async {
        final key = GlobalKey<OckerSideRailState>();
        final calls = await pumpRail(tester, key: key, menu: menu());
        key.currentState!.focusTab(NavigationTabId.libraries);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pump();
        expect(chosen, ['Sammlungen']);
        expect(calls.selected, isEmpty);
        expect(calls.reselected, isEmpty);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        expect(calls.toContent(), 1, reason: 'RIGHT from a row is the content, as from a destination');
      });

      testWidgets('a row is a tile in the middle of the pane, its words flush with the destination\'s name', (
        tester,
      ) async {
        final key = GlobalKey<OckerSideRailState>();
        await pumpRail(tester, key: key, menu: menu());
        final pane = tester.getRect(find.byKey(OckerSideRail.paneKey));
        // The chosen row wears its quiet capsule.
        final tile = tester.getRect(
          find.descendant(of: find.byKey(OckerSideRail.subItemKey(1)), matching: find.byType(OckerGlassFocusFill)),
        );
        expect(tile.left - pane.left, closeTo(pane.right - tile.right, 1), reason: 'the same room either side');
        final parent = tester.getRect(
          find.descendant(
            of: find.byKey(OckerSideRail.itemKey(NavigationTabId.libraries)),
            matching: find.byType(OckerGlassFocusFill),
          ),
        );
        expect(tile.width, lessThan(parent.width), reason: 'narrower than the destination above it');
        final words = tester.getRect(find.text('Durchsuchen'));
        final name = tester.getRect(find.text(t.navigation.libraries));
        expect(words.left, closeTo(name.left, 1), reason: 'left-aligned with the name above, not centred');
      });

      testWidgets('a row with a symbol keeps its words on the same line; the symbol goes in the symbols\' column', (
        tester,
      ) async {
        final key = GlobalKey<OckerSideRailState>();
        await pumpRail(
          tester,
          key: key,
          menu: OckerRailMenu([
            OckerRailItem(label: 'Programm', onSelect: () {}),
            OckerRailItem(label: 'Sender verwalten', icon: Icons.tune, gapBefore: true, onSelect: () {}),
          ]),
        );
        final name = tester.getRect(find.text(t.navigation.libraries));
        expect(tester.getRect(find.text('Programm')).left, closeTo(name.left, 1));
        expect(tester.getRect(find.text('Sender verwalten')).left, closeTo(name.left, 1));
        final parentIcon = tester.getRect(
          find
              .descendant(
                of: find.byKey(OckerSideRail.itemKey(NavigationTabId.libraries)),
                matching: find.byType(AppIcon),
              )
              .first,
        );
        final glyph = tester.getRect(
          find.descendant(of: find.byKey(OckerSideRail.subItemKey(1)), matching: find.byType(AppIcon)),
        );
        expect(glyph.center.dx, closeTo(parentIcon.center.dx, 1));
      });

      test('a sheet\'s entries become the rows, dividers a gap', () {
        final picked = <int>[];
        final built = OckerRailMenu.fromEntries<int>([
          const AppMenuItem<int>(value: 0, label: 'Programm', selected: true),
          const AppMenuItem<int>(value: 1, label: 'Jetzt im TV'),
          const AppMenuDivider<int>(),
          const AppMenuItem<int>(value: -1, label: 'Sender verwalten'),
        ], picked.add)!;
        expect(built.items.map((item) => item.label), ['Programm', 'Jetzt im TV', 'Sender verwalten']);
        expect(built.items.map((item) => item.gapBefore), [false, false, true]);
        expect(built.items.first.selected, isTrue);
        built.items.last.onSelect();
        expect(picked, [-1]);
      });
    });

    testWidgets('shut it is a strip of symbols; open, a pane with the names', (tester) async {
      final key = GlobalKey<OckerSideRailState>();
      await pumpRail(tester, key: key, expanded: false);
      expect(find.byKey(OckerSideRail.paneKey), findsNothing);
      expect(find.text(t.navigation.libraries), findsNothing);
      expect(
        tester.getSize(find.byType(OckerSideRail)).width,
        OckerSideRail.collapsedWidth(tester.element(find.byType(OckerSideRail))),
      );

      await pumpRail(tester, key: key);
      expect(find.byKey(OckerSideRail.paneKey), findsOneWidget);
      expect(find.text(t.navigation.libraries), findsOneWidget);
    });
  });

  group('the shell', () {
    testWidgets('a screen is told it is as wide as the room beside the rail', (tester) async {
      tvView(tester);
      final contentScope = FocusScopeNode();
      final railScope = FocusScopeNode();
      addTearDown(contentScope.dispose);
      addTearDown(railScope.dispose);
      Size? told;
      WidgetBuilder? chrome;

      await tester.pumpWidget(
        MaterialApp(
          theme: _railTheme(),
          home: OckerRailShell(
            tabs: NavigationTab.getVisibleTabs(isOffline: false),
            selectedTab: NavigationTabId.discover,
            onDestinationSelected: (_) {},
            onNavigateToContent: () {},
            expanded: false,
            railKey: GlobalKey(),
            railFocusScope: railScope,
            contentFocusScope: contentScope,
            content: Builder(
              builder: (context) {
                told = MediaQuery.sizeOf(context);
                chrome ??= (_) => const Text('chrome');
                OckerHeaderSlot.publish(context, chrome);
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final rail = OckerSideRail.collapsedWidth(tester.element(find.byType(OckerSideRail)));
      expect(told!.width, 1280 - rail);
      // A screen's own chrome, with the clock, top right — where the band
      // carried it.
      expect(find.byKey(OckerRailShell.chromeKey), findsOneWidget);
      expect(tester.getTopRight(find.byKey(OckerRailShell.chromeKey)).dx, greaterThan(1280 * 0.8));
    });

    testWidgets('home\'s chrome stays on home — it stood over the watchlist\'s band', (tester) async {
      tvView(tester);
      final contentScope = FocusScopeNode();
      final railScope = FocusScopeNode();
      addTearDown(contentScope.dispose);
      addTearDown(railScope.dispose);
      WidgetBuilder? chrome;

      Future<void> pumpOn(NavigationTabId tab) => tester.pumpWidget(
        MaterialApp(
          theme: _railTheme(),
          home: OckerRailShell(
            tabs: NavigationTab.getVisibleTabs(isOffline: false),
            selectedTab: tab,
            onDestinationSelected: (_) {},
            onNavigateToContent: () {},
            expanded: false,
            railKey: GlobalKey(),
            railFocusScope: railScope,
            contentFocusScope: contentScope,
            content: Builder(
              builder: (context) {
                chrome ??= (_) => const Text('chrome');
                OckerHeaderSlot.publish(context, chrome);
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      await pumpOn(NavigationTabId.discover);
      await tester.pumpAndSettle();
      expect(find.byKey(OckerRailShell.chromeKey), findsOneWidget);

      await pumpOn(NavigationTabId.watchlist);
      await tester.pumpAndSettle();
      expect(find.byKey(OckerRailShell.chromeKey), findsNothing);
    });
  });

  group('the describing column', () {
    testWidgets('stands right of a library grid, the filters over the grid', (tester) async {
      tvView(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: _railTheme(),
          home: Scaffold(
            body: OckerPanelFrame(
              resolveClient: (_) => null,
              header: const SizedBox(height: 40, key: ValueKey('band')),
              child: const SizedBox.expand(key: ValueKey('grid')),
            ),
          ),
        ),
      );
      await tester.pump();

      final grid = tester.getRect(find.byKey(const ValueKey('grid')));
      final panel = tester.getRect(find.byType(OckerDetailPanel));
      final band = tester.getRect(find.byKey(const ValueKey('band')));
      expect(panel.left, greaterThan(grid.right), reason: 'the rail holds the left edge');
      expect(band.left, grid.left, reason: 'the filters over the top left of the posters they narrow');
      expect(band.bottom, lessThanOrEqualTo(grid.top));
      final context = tester.element(find.byType(OckerPanelFrame));
      expect(band.top, ockerContentTop(context), reason: 'no band of destinations to clear');
      expect(panel.top, band.top, reason: 'the column runs from the top');
    });

    testWidgets('the band over a tab of rows stands at its top left too', (tester) async {
      tvView(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: _railTheme(),
          home: Scaffold(
            body: OckerPanelFrame(
              resolveClient: (_) => null,
              showPanel: false,
              header: const SizedBox(width: 50, height: 40, key: ValueKey('band')),
              child: const SizedBox.expand(key: ValueKey('rows')),
            ),
          ),
        ),
      );
      await tester.pump();

      final band = tester.getRect(find.byKey(const ValueKey('band')));
      final rows = tester.getRect(find.byKey(const ValueKey('rows')));
      expect(band.left, rows.left);
      expect(band.bottom, lessThanOrEqualTo(rows.top));
    });
  });

  group('a browse page', () {
    Future<({int Function() up, GlobalKey<OckerBrowsePageState> key})> pumpPage(
      WidgetTester tester, {
      int items = 7,
      bool pushed = false,
      Widget? header,
    }) async {
      tvView(tester);
      var up = 0;
      final key = GlobalKey<OckerBrowsePageState>();
      await tester.pumpWidget(
        MaterialApp(
          theme: _railTheme(),
          home: OckerBrowsePage(
            key: key,
            title: 'Merkliste',
            items: [for (var i = 0; i < items; i++) testMediaItem(id: 'i$i', title: 'Title $i', serverId: 'srv')],
            resolveClient: (_) => null,
            onPlay: (_, _) {},
            onExitToHeader: () => up++,
            showHeading: pushed,
            header: header,
            filters: [Focus(child: const SizedBox(width: 30, height: 30, key: ValueKey('filter')))],
          ),
        ),
      );
      await tester.pump();
      return (up: () => up, key: key);
    }

    bool tileHasFocus(WidgetTester tester, int index) =>
        tester.widgetList<OckerPosterTile>(find.byType(OckerPosterTile)).elementAt(index).focusNode.hasFocus;

    testWidgets('puts the column right of the grid, the filters over its top left', (tester) async {
      await pumpPage(tester);
      final grid = tester.getRect(find.byType(OckerPosterTile).first);
      final panel = tester.getRect(find.byType(OckerDetailPanel));
      expect(panel.left, greaterThan(grid.right));
      final filter = tester.getRect(find.byKey(const ValueKey('filter')));
      expect(filter.right, lessThan(grid.right), reason: 'over the first poster, not beside the grid');
      expect(filter.bottom, lessThanOrEqualTo(grid.top));
      expect(filter.left, closeTo(grid.left, OckerFilterGlyph.gap + 8));
    });

    testWidgets("a host's own switcher leads the filters' line, over the grid", (tester) async {
      await pumpPage(tester, header: const SizedBox(width: 200, height: 30, key: ValueKey('switcher')));
      final grid = tester.getRect(find.byType(OckerPosterTile).first);
      final switcher = tester.getRect(find.byKey(const ValueKey('switcher')));
      final filter = tester.getRect(find.byKey(const ValueKey('filter')));
      expect(switcher.bottom, lessThanOrEqualTo(grid.top));
      expect(switcher.left, greaterThanOrEqualTo(grid.left));
      expect(filter.left, greaterThan(switcher.right), reason: 'the filters after it, on the same line');
      expect(filter.center.dy, closeTo(switcher.center.dy, 1));
      expect(filter.bottom, lessThanOrEqualTo(grid.top));
    });

    testWidgets('UP out of the first row reaches the filters; DOWN comes back where it left', (tester) async {
      final page = await pumpPage(tester);
      page.key.currentState!.focusFirstItem();
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(page.up(), 1);

      // The host puts the cursor on the filters; DOWN off them asks for the grid.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      page.key.currentState!.focusGridFromBand();
      await tester.pump();
      expect(tileHasFocus(tester, 3), isTrue);
    });

    testWidgets('the watchlist has no count at its foot; a page pushed over the shell keeps it', (tester) async {
      tvView(tester);
      Future<void> pump({required bool showCount}) => tester.pumpWidget(
        MaterialApp(
          theme: _railTheme(),
          home: OckerBrowsePage(
            title: 'Merkliste',
            items: [for (var i = 0; i < 7; i++) testMediaItem(id: 'i$i', title: 'Title $i', serverId: 'srv')],
            resolveClient: (_) => null,
            onPlay: (_, _) {},
            onExitToHeader: () {},
            showCount: showCount,
          ),
        ),
      );

      await pump(showCount: false);
      expect(find.text('7'), findsNothing);
      await pump(showCount: true);
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('UP out of the first row of a pushed page goes to the host', (tester) async {
      final page = await pumpPage(tester, pushed: true);

      page.key.currentState!.focusFirstItem();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(page.up(), 1);
    });
  });

  group('the library column', () {
    const libraries = [
      MediaLibrary(id: '1', backend: MediaBackend.plex, title: 'Filme', kind: MediaKind.movie, serverId: 's'),
      MediaLibrary(id: '2', backend: MediaBackend.plex, title: 'Serien', kind: MediaKind.show, serverId: 's'),
      MediaLibrary(id: '3', backend: MediaBackend.plex, title: 'Doku', kind: MediaKind.movie, serverId: 's'),
    ];

    Future<({List<String> chosen, int Function() rail, FocusNode poster})> pumpColumn(WidgetTester tester) async {
      tvView(tester);
      final chosen = <String>[];
      var rail = 0;
      final poster = FocusNode(debugLabel: 'poster');
      addTearDown(poster.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: _railTheme(),
          home: MainScreenFocusScope(
            focusSidebar: () => rail++,
            sideNavigationWidth: 0,
            child: Scaffold(
              body: OckerLibraryColumn(
                libraries: libraries,
                selectedKey: libraries[1].globalKey,
                groupByServer: false,
                onSelected: chosen.add,
                onFocusContent: () {},
                child: Center(
                  child: Builder(
                    builder: (context) => Focus(
                      focusNode: poster,
                      autofocus: true,
                      // LEFT off the page's first column, as the tabs do it.
                      onKeyEvent: (_, event) {
                        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                          OckerLibraryColumnScope.open(context);
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: const SizedBox(width: 20, height: 20),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (chosen: chosen, rail: () => rail, poster: poster);
    }

    bool rowHasFocus(WidgetTester tester, MediaLibrary library) {
      final row = find.byKey(OckerLibraryColumn.rowKey(library.globalKey));
      return Focus.of(tester.element(find.descendant(of: row, matching: find.byType(Text)).first)).hasFocus;
    }

    testWidgets('is shut and out of reach until LEFT opens it on the library on show', (tester) async {
      final column = await pumpColumn(tester);
      expect(tester.getSize(find.byType(AnimatedContainer).first).width, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(find.byKey(OckerLibraryColumn.paneKey), findsOneWidget);
      expect(rowHasFocus(tester, libraries[1]), isTrue);
      expect(column.poster.hasFocus, isFalse);
    });

    testWidgets('RIGHT shuts it and puts the cursor back where it was', (tester) async {
      final column = await pumpColumn(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(column.poster.hasFocus, isTrue);
      expect(column.chosen, isEmpty);
    });

    testWidgets('LEFT goes on to the rail', (tester) async {
      final column = await pumpColumn(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(column.rail(), 1);
      expect(rowHasFocus(tester, libraries[1]), isFalse, reason: 'shut behind the cursor');
    });

    testWidgets('SELECT on another library chooses it', (tester) async {
      final column = await pumpColumn(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(rowHasFocus(tester, libraries[2]), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(column.chosen, [libraries[2].globalKey]);
      expect(rowHasFocus(tester, libraries[2]), isFalse, reason: 'choosing shuts it');
    });

    testWidgets('where no column stands there is none to open', (tester) async {
      tvView(tester);
      var opened = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: true, variant: AppThemeVariant.glas),
          home: Builder(
            builder: (context) {
              opened = OckerLibraryColumnScope.open(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(opened, isFalse);
    });
  });
}
