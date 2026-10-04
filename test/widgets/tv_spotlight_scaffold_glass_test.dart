import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/ultra_blur_colors.dart';
import 'package:plezy/redesign/ultra_blur_backdrop.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/rasterized_gradient.dart';
import 'package:plezy/widgets/tv_browse_rail.dart';
import 'package:plezy/widgets/tv_spotlight_scaffold.dart';

import '../test_helpers/media_items.dart';
import '../test_helpers/prefs.dart';

/// Home and Explore under "Glas": the spotlight's words stand directly on the
/// rows — the row in use and the glimpse of the next along the foot — which
/// leaves the air under the navigation instead of a gap above the rows.
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

  testWidgets('with the ground in the title\'s colours the scrims no longer cover it', (tester) async {
    await SettingsService.getInstance();
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final spotlight = ValueNotifier<MediaItem?>(null);
    addTearDown(spotlight.dispose);
    final ambient = UltraBlurAmbient((owner: (_) => null, any: () => null));
    addTearDown(ambient.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true, variant: AppThemeVariant.glas),
        home: UltraBlurScope(
          ambient: ambient,
          child: TvSpotlightScaffold(
            hubs: [hub('first')],
            spotlightListenable: spotlight,
            resolveSpotlight: () => null,
            resolveClient: (_) => null,
            foreground: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    double heaviest() => tester
        .widgetList<RasterizedGradient>(find.byType(RasterizedGradient))
        .expand((widget) => widget.gradient.colors)
        .map((color) => color.a)
        .fold(0.0, (a, b) => a > b ? a : b);
    // Without colours: the ground's own flat colour, nearly opaque at the foot.
    expect(heaviest(), greaterThan(0.9));

    ambient.debugShow(
      const UltraBlurColors(
        topLeft: Color(0xFF3D3021),
        topRight: Color(0xFF6E4D2D),
        bottomRight: Color(0xFF222C26),
        bottomLeft: Color(0xFF1B1F1C),
      ),
    );
    await tester.pump();
    expect(heaviest(), lessThanOrEqualTo(0.7), reason: 'the colours show through');
  });

  test('the rail keeps the glimpse of the next row in every theme', () {
    expect(
      TvBrowseRailLayout.viewportHeightFor(hubCount: 2, scale: 1, sectionHeight: 300),
      300 + TvBrowseRailLayout.nextHubPeekHeightForScale(1),
    );
  });

  testWidgets('under glass the spotlight\'s words come down onto the rows', (tester) async {
    final standard = await spotlightBottom(tester, AppThemeVariant.standard);
    final glass = await spotlightBottom(tester, AppThemeVariant.glas);
    expect(glass, lessThan(standard), reason: 'the words stand lower, closer to the rows');
  });
}
