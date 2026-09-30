import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/redesign/ocker_skin.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';

/// One poster width, whatever the screen. The watchlist, the home rows and a
/// library all ask [ockerTileWidth] now, so the only thing that can make them
/// disagree is the arithmetic itself.
void main() {
  // The poster arithmetic is the television's; a phone takes a fixed scale.
  setUp(() => TvDetectionService.debugSetAppleTVOverride(true));
  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  Future<double> widthAt(WidgetTester tester, Size size) async {
    late double result;
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
              result = ockerTileWidth(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    return result;
  }

  testWidgets('a 1920 screen gives exactly the drawn size', (tester) async {
    expect(await widthAt(tester, const Size(1920, 1080)), closeTo(OckerLayout.tileWidth, 0.5));
  });

  testWidgets('the 960-logical television every Android TV reports still fits a full row', (tester) async {
    const scale = 0.5;
    final width = await widthAt(tester, const Size(960, 540));
    // A full row plus its gaps has to fit what is left beside the panel. The
    // scale is 0.5 there, not the clamped 0.6 it used to be: the television is
    // drawing 960 logical pixels on a 1920-pixel panel, so 0.5 is the size the
    // design was drawn at and a floor above it only took width from the
    // posters.
    final column =
        960 - 2 * OckerLayout.safeMargin * scale - OckerLayout.panelWidth * scale - OckerLayout.columnGutter * scale;
    expect(OckerLayout.gridColumns * width + (OckerLayout.gridColumns - 1) * 18 * scale, lessThanOrEqualTo(column));
    expect(width, greaterThan(110), reason: 'and big enough to read a poster from the sofa');
  });

  testWidgets('it never grows past the drawn size on a very wide screen', (tester) async {
    expect(await widthAt(tester, const Size(3840, 2160)), closeTo(OckerLayout.tileWidth, 0.5));
  });

  testWidgets('a measured column fits a full row, even when something took width first', (tester) async {
    // The app's own layout keeps a navigation rail down the left, so the
    // column a grid gets is narrower than the viewport implies. Sized from the
    // viewport, five posters did not fit: the grid wrapped at four while its
    // focus arithmetic went on counting in fives, and DOWN landed one place to
    // the right of where it should.
    const viewport = Size(960, 540);
    const rail = 80.0;
    const gridColumns = OckerLayout.gridColumns;
    late double tile;
    late double gap;
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: viewport),
        child: Theme(
          data: monoTheme(dark: true, variant: AppThemeVariant.glas),
          child: Builder(
            builder: (context) {
              final scale = ockerScale(context);
              final column =
                  viewport.width -
                  rail -
                  2 * OckerLayout.safeMargin * scale -
                  OckerLayout.panelWidth * scale -
                  OckerLayout.rowGutter * scale;
              tile = ockerTileWidthFor(context, column);
              gap = OckerLayout.tileGap * scale;
              expect(
                gridColumns * tile + (gridColumns - 1) * gap,
                lessThanOrEqualTo(column),
                reason: 'the whole row has to fit the column that actually exists',
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(tile, greaterThan(60), reason: 'and still be a poster');
    // A rail costs width, and the posters pay for it — honestly: narrower
    // than the same screen would give them with nothing in the way.
    expect(tile, lessThan(ockerTileWidthFor(tester.element(find.byType(SizedBox)), 960 - 96 - 200 - 31)));
  });
}
