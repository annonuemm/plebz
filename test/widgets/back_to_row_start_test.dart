import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/focus/locked_hub_controller.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/widgets/hub_section.dart';
import 'package:plezy/widgets/tv_browse_rail.dart';
import 'package:provider/provider.dart';

import '../test_helpers/media_items.dart';
import '../test_helpers/multi_server_fixtures.dart';
import '../test_helpers/prefs.dart';

/// "Zurück zum Reihenanfang" (Plebz, the user's call 2026-10-25, after a
/// viewer's suggestion): on a television, Back on a row's later title first
/// returns to the row's first one, as Prime Video does; only Back there does
/// what it always did — the side navigation, or leaving a detail page.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HubFocusMemory focusMemory;

  setUp(() async {
    LocaleSettings.setLocaleSync(AppLocale.en);
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    focusMemory = HubFocusMemory();
    await SettingsService.getInstance();
    PlatformDetector.setLayoutMode(LayoutMode.tv);
  });

  tearDown(() {
    PlatformDetector.setLayoutMode(LayoutMode.auto);
    TvDetectionService.debugSetAppleTVOverride(null);
  });

  List<MediaItem> movies(int count) => [
    for (var i = 0; i < count; i++)
      testMediaItem(id: 'movie_$i', backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Movie $i'),
  ];

  Future<void> pressBack(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  }

  Future<void> pressRight(WidgetTester tester, int times) async {
    for (var i = 0; i < times; i++) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    }
    await tester.pumpAndSettle();
  }

  ScrollPosition rowPosition(WidgetTester tester) => tester
      .stateList<ScrollableState>(find.byType(Scrollable))
      .map((state) => state.position)
      .where((position) => axisDirectionToAxis(position.axisDirection) == Axis.horizontal)
      .where((position) => position.maxScrollExtent > 0)
      .reduce((a, b) => a.maxScrollExtent > b.maxScrollExtent ? a : b);

  group('TvBrowseRail', () {
    late List<String> focused;
    late int backs;
    late int bubbledBacks;

    Future<void> pumpRail(
      WidgetTester tester, {
      required List<MediaHub> hubs,
      AppThemeVariant variant = AppThemeVariant.standard,
      bool withOnBack = true,
      MediaItem? Function(MediaHub hub)? leadingItemForHub,
    }) async {
      focused = [];
      backs = 0;
      bubbledBacks = 0;
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1280, 720);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      await tester.pumpWidget(
        TranslationProvider(
          child: ChangeNotifierProvider<MultiServerProvider>(
            create: (_) => testMultiServerProvider(MultiServerManager()),
            child: InputModeTracker(
              child: MaterialApp(
                theme: monoTheme(MonoPalette.dark, variant: variant),
                home: Scaffold(
                  // What lies past the rail: MainScreen's own Back handler
                  // for a rail without onBack (the home screen's).
                  body: Focus(
                    onKeyEvent: (_, event) {
                      if (event is KeyUpEvent && event.logicalKey == LogicalKeyboardKey.escape) bubbledBacks++;
                      return KeyEventResult.ignored;
                    },
                    child: SizedBox(
                      width: 1280,
                      height: 720,
                      child: TvBrowseRail(
                        focusMemory: focusMemory,
                        hubs: hubs,
                        autofocus: true,
                        iconForHub: (_, _) => Icons.movie_rounded,
                        leadingItemForHub: leadingItemForHub,
                        onFocusedItemChanged: (item) => focused.add(item.id),
                        onBack: withOnBack ? () => backs++ : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      tester.state<TvBrowseRailState>(find.byType(TvBrowseRail)).requestFocus();
      await tester.pumpAndSettle();
    }

    MediaHub row(String id, int count) => MediaHub(id: id, title: id, type: 'movie', items: movies(count), size: count);

    for (final variant in AppThemeVariant.values) {
      testWidgets('Back returns to the first title and scrolls there, then leaves (${variant.name})', (tester) async {
        await pumpRail(tester, hubs: [row('watchlist', 12)], variant: variant);

        await pressRight(tester, 6);
        expect(focused.last, 'movie_6');
        expect(rowPosition(tester).pixels, greaterThan(0), reason: 'the row scrolled along');

        await pressBack(tester);
        expect(focused.last, 'movie_0', reason: 'the first press goes to the start of the row');
        expect(rowPosition(tester).pixels, 0, reason: 'and the row scrolls back to its start');
        expect(backs, 0, reason: 'without leaving the row');

        await pressBack(tester);
        expect(backs, 1, reason: 'on the first title Back does what it always did');
        expect(focused.last, 'movie_0');
      });
    }

    testWidgets('on the first title Back leaves at once', (tester) async {
      await pumpRail(tester, hubs: [row('watchlist', 6)]);

      await pressBack(tester);
      expect(backs, 1);
    });

    testWidgets('only the active row returns; the start of another row is kept', (tester) async {
      await pumpRail(tester, hubs: [row('first', 8), row('second', 8)]);

      await pressRight(tester, 3);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await pressRight(tester, 2);
      expect(focused.last, 'movie_2');

      await pressBack(tester);
      expect(focused.last, 'movie_0');
      expect(backs, 0);

      // The first row still remembers where it was left.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(focused.last, 'movie_3');
    });

    testWidgets('a rail without its own Back keeps the first press and passes the second on', (tester) async {
      await pumpRail(tester, hubs: [row('home', 8)], withOnBack: false);

      await pressRight(tester, 4);
      await pressBack(tester);
      expect(focused.last, 'movie_0');
      expect(bubbledBacks, 0, reason: 'the side navigation does not open yet');

      await pressBack(tester);
      expect(bubbledBacks, 1, reason: 'now Back reaches the screen around the rail');
    });

    testWidgets('a row with an options slot returns to its first title, and the slot leaves', (tester) async {
      final season = testMediaItem(id: 'season_1', backend: MediaBackend.plex, kind: MediaKind.season, title: 'S1');
      await pumpRail(tester, hubs: [row('episodes', 6)], leadingItemForHub: (_) => season);
      expect(focused.last, 'movie_0', reason: 'focus starts on the first title, past the slot');

      await pressRight(tester, 3);
      await pressBack(tester);
      expect(focused.last, 'movie_0', reason: 'the first title, not the options slot');
      expect(backs, 0);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      await pressBack(tester);
      expect(backs, 1, reason: 'the slot stands before the first title');
    });

    testWidgets('with the switch off Back leaves from anywhere in the row', (tester) async {
      await SettingsService.instanceOrNull!.write(PlebzPrefs.backToRowStart, false);
      await pumpRail(tester, hubs: [row('watchlist', 8)]);

      await pressRight(tester, 4);
      await pressBack(tester);
      expect(backs, 1);
      expect(focused.last, 'movie_4');
    });

    testWidgets('off a television Back keeps its old way', (tester) async {
      PlatformDetector.setLayoutMode(LayoutMode.tablet);
      await pumpRail(tester, hubs: [row('watchlist', 8)]);

      await pressRight(tester, 4);
      await pressBack(tester);
      expect(backs, 1);
      expect(focused.last, 'movie_4');
    });

    testWidgets('the Apple TV returns on the press itself', (tester) async {
      TvDetectionService.debugSetAppleTVOverride(true);
      await pumpRail(tester, hubs: [row('watchlist', 8)]);

      await pressRight(tester, 4);
      await pressBack(tester);
      expect(focused.last, 'movie_0');
      expect(backs, 0);

      await pressBack(tester);
      expect(backs, 1);
    });
  });

  group('HubSection (Live TV "Was läuft")', () {
    Future<(GlobalKey<HubSectionState>, List<String>, List<int>)> pumpSection(WidgetTester tester) async {
      final key = GlobalKey<HubSectionState>();
      final focused = <String>[];
      final backs = [0];
      final items = movies(10);
      await tester.pumpWidget(
        InputModeTracker(
          child: MaterialApp(
            theme: monoTheme(MonoPalette.dark),
            home: Scaffold(
              body: ListView(
                children: [
                  HubSection(
                    key: key,
                    hub: MediaHub(id: 'whats_on', title: 'On now', type: 'movie', items: items, size: items.length),
                    focusMemory: focusMemory,
                    icon: Symbols.live_tv_rounded,
                    onFocusedItemChanged: (item) => focused.add(item.id),
                    onBack: () => backs[0]++,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      key.currentState!.requestFocusAt(0);
      await tester.pumpAndSettle();
      return (key, focused, backs);
    }

    testWidgets('Back returns to the first title, then leaves', (tester) async {
      final (_, focused, backs) = await pumpSection(tester);

      await pressRight(tester, 5);
      expect(focused.last, 'movie_5');

      await pressBack(tester);
      expect(focused.last, 'movie_0');
      expect(backs[0], 0);

      await pressBack(tester);
      expect(backs[0], 1);
    });

    testWidgets('a phone or a tablet keeps Back as it was', (tester) async {
      PlatformDetector.setLayoutMode(LayoutMode.phone);
      final (_, focused, backs) = await pumpSection(tester);

      await pressRight(tester, 3);
      await pressBack(tester);
      expect(backs[0], 1);
      expect(focused.last, 'movie_3');
    });
  });
}
