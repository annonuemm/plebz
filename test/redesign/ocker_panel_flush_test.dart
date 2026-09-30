import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/redesign/ocker_skin.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';

/// The describing panel on a grid page — the watchlist, a library's browse
/// tab — starts where the header's words start, not at the design's own safe
/// margin: two texts a hand's breadth apart, one under the other, read as two
/// pages laid over each other.
///
/// What that reclaims goes to the panel. The column of posters beside it must
/// not move, because its width is what the tile arithmetic was measured
/// against — five posters sized for a wider column wrap at four, and the focus
/// arithmetic goes on counting in fives.
void main() {
  Future<T> at<T>(WidgetTester tester, Size size, T Function(BuildContext context) read) async {
    late T result;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size),
        child: Theme(
          data: monoTheme(dark: true, variant: AppThemeVariant.glas),
          child: Builder(
            builder: (context) {
              result = read(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    return result;
  }

  for (final size in const [Size(1920, 1080), Size(1280, 720), Size(960, 540)]) {
    testWidgets('the column beside the panel stays put at ${size.width.toInt()}', (tester) async {
      final measured = await at(tester, size, (context) {
        final scale = ockerScale(context);
        return (
          contentLeftNow: ockerFlushLeftInset(context) + ockerGridPanelWidth(context),
          contentLeftBefore: OckerLayout.safeMargin * scale + OckerLayout.panelWidth * scale,
          panelWidth: ockerGridPanelWidth(context),
          baseWidth: OckerLayout.panelWidth * scale,
        );
      });

      // The whole point: the page gives the panel exactly what it took off its
      // own left margin, so the grid begins on the same pixel as before.
      expect(measured.contentLeftNow, closeTo(measured.contentLeftBefore, 0.01));
      // And the panel really is wider — on a television the words gain the
      // difference between the design's margin and the app's own inset.
      expect(measured.panelWidth, greaterThan(measured.baseWidth));
    });
  }

  testWidgets('a window too narrow to have anything to give back keeps the drawn width', (tester) async {
    final measured = await at(tester, const Size(360, 640), (context) {
      final scale = ockerScale(context);
      return (panel: ockerGridPanelWidth(context), base: OckerLayout.panelWidth * scale);
    });

    // The two insets come from different scales; where the design's margin is
    // the smaller one there is nothing to reclaim, and the panel must not come
    // out *narrower* than drawn.
    expect(measured.panel, greaterThanOrEqualTo(measured.base));
  });
}
