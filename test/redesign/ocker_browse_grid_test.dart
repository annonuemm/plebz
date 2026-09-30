import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/focus_theme.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/redesign/ocker_browse_grid.dart';
import 'package:plezy/redesign/ocker_poster_tile.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';

import '../test_helpers/media_items.dart';
import '../test_helpers/prefs.dart';

void main() {
  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  for (final variant in [AppThemeVariant.glas, AppThemeVariant.glas]) {
    testWidgets('${variant.name}: a focused tile on the edge keeps all of its ring', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const columnLeft = 400.0, columnTop = 200.0;
      final items = [for (var i = 0; i < 10; i++) testMediaItem(id: 'g$i', title: 'Titel $i')];

      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: true, variant: variant),
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: columnLeft,
                  top: columnTop,
                  width: 1400,
                  height: 800,
                  child: OckerBrowseGrid(
                    items: items,
                    hub: MediaHub(id: 'w', title: 'Merkliste', type: 'mixed', items: items),
                    resolveClient: (_) => null,
                    onPlay: (_, _) {},
                    onExitUp: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final first = tester.getRect(find.byType(OckerPosterTile).first);
      expect(first.left, columnLeft + 1, reason: 'the first poster stands where it always stood');
      expect(first.top, columnTop + 1);

      // What the focused tile paints: grown by the focus scale, ring outside.
      final context = tester.element(find.byType(OckerPosterTile).first);
      final growth = FocusTheme.focusScaleFor(context) - 1;
      final painted = Rect.fromCenter(
        center: first.center,
        width: first.width * (1 + growth) + 2 * 1.75,
        height: first.height * (1 + growth) + 2 * 1.75,
      );
      final clip = tester.getRect(find.byType(SingleChildScrollView));
      expect(clip.left, lessThanOrEqualTo(painted.left));
      expect(clip.top, lessThanOrEqualTo(painted.top));

      final fifth = tester.getRect(find.byType(OckerPosterTile).at(4));
      expect(fifth.top, first.top, reason: 'five across still');
      final fifthPainted = Rect.fromCenter(
        center: fifth.center,
        width: fifth.width * (1 + growth) + 2 * 1.75,
        height: fifth.height,
      );
      expect(clip.right, greaterThanOrEqualTo(fifthPainted.right));
    });
  }
}
