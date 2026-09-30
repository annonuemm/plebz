import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/focus/focusable_action_bar.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/redesign/ocker_poster_tile.dart';
import 'package:plezy/screens/hub_detail_screen.dart';
import 'package:plezy/screens/seerr_filtered_hub_screen.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:provider/provider.dart';

import '../test_helpers/media_items.dart';
import '../test_helpers/multi_server_fixtures.dart';
import '../test_helpers/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  SeerrFilterTab tab(String id, String label) => SeerrFilterTab(
    id: id,
    label: label,
    load: (start, size) async => LibraryPage(
      items: [testMediaItem(id: '$id-1', backend: MediaBackend.plex, kind: MediaKind.movie, title: '$id title')],
      totalCount: 1,
      offset: start,
    ),
  );

  Future<void> pumpPushed(
    WidgetTester tester, {
    required List<SeerrFilterTab> tabs,
    AppThemeVariant variant = AppThemeVariant.standard,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final multiServer = testMultiServerProvider(MultiServerManager());
    addTearDown(multiServer.dispose);

    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer)],
          child: MaterialApp(
            theme: monoTheme(dark: true, variant: variant),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SeerrFilteredHubScreen(title: 'Netflix', hubKey: 'network:213', tabs: tabs),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('the page can be left again — with tabs and without', (tester) async {
    // It is a pushed route, so back has to pop it. Marking it "embedded"
    // dropped the pop and sent back to a sidebar that is not above this
    // route: the page could not be left at all.
    for (final tabs in [
      [tab('movie', 'Films'), tab('tv', 'Series')],
      [tab('tv', 'Series')],
    ]) {
      await pumpPushed(tester, tabs: tabs);
      expect(find.byType(HubDetailScreen), findsOneWidget);
      expect(
        tester.widget<HubDetailScreen>(find.byType(HubDetailScreen)).isEmbedded,
        isFalse,
        reason: 'a route that owns the screen must keep its pop',
      );

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byType(HubDetailScreen), findsNothing, reason: '${tabs.length} tab(s) must not trap the viewer');
    }
  });

  testWidgets('two kinds get a tab each, one kind gets none', (tester) async {
    await pumpPushed(tester, tabs: [tab('movie', 'Films'), tab('tv', 'Series')]);
    expect(find.text('Films'), findsOneWidget);
    expect(find.text('Series'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await pumpPushed(tester, tabs: [tab('tv', 'Series')]);
    expect(find.text('Series'), findsNothing, reason: 'one tab is no choice, so no strip');
  });

  testWidgets('under the redesign the tabs lead the filters over the grid, and the D-pad reaches them', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    await pumpPushed(tester, tabs: [tab('movie', 'Films'), tab('tv', 'Series')], variant: AppThemeVariant.glas);
    expect(tester.takeException(), isNull);
    expect(find.text('Films'), findsOneWidget);
    expect(find.text('Series'), findsOneWidget);
    expect(find.text('movie title'), findsWidgets);

    final poster = tester.getRect(find.byType(OckerPosterTile).first);
    final films = tester.getRect(find.text('Films'));
    final bar = tester.getRect(find.byType(FocusableActionBar));
    expect(films.bottom, lessThanOrEqualTo(poster.top), reason: 'over the grid');
    expect(bar.left, greaterThan(tester.getRect(find.text('Series')).right), reason: 'the filters after the tabs');

    // A keyboard session, so the tiles take and move focus as on a TV.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    tester.widget<OckerPosterTile>(find.byType(OckerPosterTile).first).focusNode.requestFocus();
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(
      find.ancestor(
        of: find.byWidgetPredicate((w) => w is Focus && w.focusNode == FocusManager.instance.primaryFocus),
        matching: find.byType(FocusableActionBar),
      ),
      findsOneWidget,
      reason: 'UP out of the first row reaches the filters',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'seerr_filter_chip_0',
      reason: 'LEFT of them, the tab on show',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'seerr_filter_chip_1');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('tv title'), findsWidgets, reason: 'the other kind is on show');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(
      find.ancestor(
        of: find.byWidgetPredicate((w) => w is Focus && w.focusNode == FocusManager.instance.primaryFocus),
        matching: find.byType(FocusableActionBar),
      ),
      findsOneWidget,
      reason: 'past the last tab lie the filters',
    );
  });
}
