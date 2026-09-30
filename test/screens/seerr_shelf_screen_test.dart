import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/models/catalog/catalog_item.dart';
import 'package:plezy/providers/catalog_sources_provider.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/screens/seerr_shelf_screen.dart';
import 'package:plezy/services/catalog/catalog_source.dart';
import 'package:plezy/services/catalog/seerr_shelves.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/widgets/hub_section.dart';
import 'package:plezy/widgets/tv_browse_rail.dart';
import 'package:provider/provider.dart';

import '../test_helpers/multi_server_fixtures.dart';
import '../test_helpers/prefs.dart';

CatalogItem _item(String title) => CatalogItem(
  source: CatalogSourceId.seerr,
  ids: CatalogItemIds(slug: title),
  kind: MediaKind.movie,
  title: title,
);

SeerrShelf _shelf(String id, String title) => SeerrShelf(
  id: id,
  title: title,
  kind: MediaKind.movie,
  load: (page) async => CatalogPage(items: [_item('$id-$page')], hasMore: true),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  Future<void> pumpShelf(WidgetTester tester) async {
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
          providers: [
            ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
            // The TV layout reads it for the spotlight's request/watchlist
            // affordances; an empty one is enough to build the page.
            ChangeNotifierProvider<CatalogSourcesProvider>(create: (_) => CatalogSourcesProvider()),
          ],
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: SeerrShelfScreen(
              title: 'Netflix',
              shelves: [_shelf('all', 'Everything'), _shelf('movie:popular', 'Popular films')],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('on TV the rows are the same widget the home screen uses', (tester) async {
    // Card sizes and spacing come from the widget, so a different one is a
    // different-looking page — which is what a stack of HubSections was.
    TvDetectionService.debugSetAppleTVOverride(true);

    await pumpShelf(tester);

    expect(find.byType(TvBrowseRail), findsOneWidget);
    expect(find.byType(HubSection), findsNothing);
  });

  testWidgets('off TV the rows are stacked sections, as on the home screen there', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(false);

    await pumpShelf(tester);

    expect(find.byType(HubSection), findsWidgets);
    expect(find.byType(TvBrowseRail), findsNothing);
  });
}
