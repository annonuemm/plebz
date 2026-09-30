import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/tv_browse_rail.dart';
import 'package:plezy/widgets/tv_spotlight_scaffold.dart';

import '../test_helpers/media_items.dart';
import '../test_helpers/prefs.dart';

/// Home and Explore under "Glas": the rows below the one in use are hidden,
/// so their glimpse is not kept either — the row goes down to the foot of the
/// screen and the spotlight's words stand directly on it, which leaves the air
/// under the navigation instead of a gap above the rows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
  });

  MediaHub hub(String id) => MediaHub(
    id: id,
    title: id,
    type: 'movie',
    items: [testMediaItem(id: '${id}_1', backend: MediaBackend.plex, kind: MediaKind.movie, title: '$id 1')],
    size: 1,
  );

  Future<double> spotlightBottom(WidgetTester tester, AppThemeVariant variant) async {
    await SettingsService.getInstance();
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final spotlight = ValueNotifier<MediaItem?>(null);
    addTearDown(spotlight.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true, variant: variant),
        home: TvSpotlightScaffold(
          hubs: [hub('first'), hub('second')],
          spotlightListenable: spotlight,
          resolveSpotlight: () => null,
          resolveClient: (_) => null,
          foreground: const SizedBox.shrink(),
        ),
      ),
    );
    // Past the theme's own cross-fade from the variant pumped before.
    await tester.pump(const Duration(seconds: 1));
    return tester.widget<CatalogSpotlightBackground>(find.byType(CatalogSpotlightBackground)).contentBottom;
  }

  test('without the glimpse the rail keeps only a margin below the row in use', () {
    final withGlimpse = TvBrowseRailLayout.viewportHeightFor(hubCount: 2, scale: 1, sectionHeight: 300);
    final without = TvBrowseRailLayout.viewportHeightFor(hubCount: 2, scale: 1, sectionHeight: 300, peekNext: false);
    expect(without, 300 + TvBrowseRailLayout.footMarginForScale(1));
    expect(without, lessThan(withGlimpse));
  });

  testWidgets('under glass the spotlight\'s words come down onto the rows', (tester) async {
    final standard = await spotlightBottom(tester, AppThemeVariant.standard);
    final glass = await spotlightBottom(tester, AppThemeVariant.glas);
    expect(glass, lessThan(standard), reason: 'the words stand lower, closer to the rows');
  });
}
