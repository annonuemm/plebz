import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/screens/media_detail/tv_detail_header_layout.dart';

/// A 1080p television reports roughly 960x540 logical pixels at a device pixel
/// ratio of 2, which puts the layout scale at its 0.85 floor. That viewport is
/// where the header runs out of room, so it is the one the rules are read
/// against.
const _tvScale = 0.85;

TvDetailHeaderMetrics _metrics(double availableHeight, {bool hasGenres = true, bool hasDescription = true}) =>
    TvDetailHeaderMetrics(
      availableHeight: availableHeight,
      scale: _tvScale,
      hasDescription: hasDescription,
      hasGenres: hasGenres,
    );

void main() {
  group('resolveTvDetailHeaderLayout', () {
    test('a roomy header keeps the logo and all three lines', () {
      final layout = resolveTvDetailHeaderLayout(_metrics(520));

      expect(layout.summaryLines, 3);
      expect(layout.titleMode, TvDetailTitleMode.logo);
      expect(layout.titleHeight, greaterThanOrEqualTo(_metrics(520).minLogoHeight));
    });

    test('a squeezed header keeps the logo and gives up summary lines', () {
      // ~197pt is what is left on a 540pt viewport once an episode rail and an
      // other-copies rail have taken their share. The logo stays: it is the
      // page's identity, and the info button holds the full text.
      final metrics = _metrics(197);
      final layout = resolveTvDetailHeaderLayout(metrics);

      expect(layout.titleMode, TvDetailTitleMode.logo);
      expect(layout.titleHeight, greaterThanOrEqualTo(metrics.minLogoHeight));
      expect(layout.summaryLines, lessThan(3));
    });

    test('type takes over only where no logo could be read', () {
      // Far below anything a wordmark survives — and still the page names
      // itself rather than showing an empty block.
      final layout = resolveTvDetailHeaderLayout(_metrics(120));

      expect(layout.titleMode, TvDetailTitleMode.text);
      expect(layout.showsTitle, isTrue);
    });

    test('the text title is sized to its box, not to a constant', () {
      final tight = resolveTvDetailHeaderLayout(_metrics(120));
      final tighter = resolveTvDetailHeaderLayout(_metrics(115));

      expect(tight.titleMode, TvDetailTitleMode.text);
      expect(tighter.titleFontSize, lessThan(tight.titleFontSize));
      expect(tighter.titleFontSize * 1.2, lessThanOrEqualTo(tighter.titleHeight + 0.01));
    });

    test('a logo survives a squeeze that costs every summary line', () {
      // 150pt still leaves the logo its floor once the summary is gone.
      final layout = resolveTvDetailHeaderLayout(_metrics(150));

      expect(layout.summaryLines, 0);
      expect(layout.titleMode, TvDetailTitleMode.logo);
    });

    test('a title with no description spends nothing on summary lines', () {
      final layout = resolveTvDetailHeaderLayout(_metrics(520, hasDescription: false));

      expect(layout.summaryLines, 0);
      expect(layout.titleMode, TvDetailTitleMode.logo);
    });

    test('dropping the genre line buys the summary its room back', () {
      final withGenres = resolveTvDetailHeaderLayout(_metrics(190, hasGenres: true));
      final without = resolveTvDetailHeaderLayout(_metrics(190, hasGenres: false));

      expect(without.summaryLines, greaterThanOrEqualTo(withGenres.summaryLines));
    });

    test('a short summary reserves only what it needs, and the title gets the rest', () {
      // The fixed layout, where the logo is what is left over. In the expanded
      // state the title band is a fixed size and does not grow.
      //
      // 250, not 230: below that the three-line ceiling no longer fits in the
      // first place — the outlined facts row takes its share — and a ceiling
      // that has already given a line up has nothing left to hand the logo,
      // which would make this pass for the wrong reason.
      const height = 250.0;
      final ceiling = TvDetailHeaderMetrics(
        availableHeight: height,
        scale: _tvScale,
        hasDescription: true,
        hasGenres: true,
      );
      final measured = TvDetailHeaderMetrics(
        availableHeight: height,
        scale: _tvScale,
        hasDescription: true,
        hasGenres: true,
        descriptionLines: 2,
      );

      expect(ceiling.maxSummaryLines, 3);
      expect(measured.maxSummaryLines, 2);
      expect(
        resolveTvDetailHeaderLayout(measured).titleHeight,
        greaterThan(resolveTvDetailHeaderLayout(ceiling).titleHeight),
        reason: 'the lines the text does not need go to the logo',
      );
    });

    test('a long summary is still capped at the ceiling', () {
      final metrics = TvDetailHeaderMetrics(
        availableHeight: 420,
        scale: _tvScale,
        hasDescription: true,
        hasGenres: true,
        heroLayout: true,
        descriptionLines: 12,
      );

      expect(metrics.maxSummaryLines, 6);
    });

    test('the resolved pieces fit the height they were given', () {
      final metrics = _metrics(197);
      final layout = resolveTvDetailHeaderLayout(metrics);
      final used = layout.titleHeight + metrics.fixedHeightFor(layout.summaryLines);

      expect(used, lessThanOrEqualTo(metrics.availableHeight + 0.01));
    });
  });
}
