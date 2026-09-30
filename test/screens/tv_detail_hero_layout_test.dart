import 'dart:math' as math;

import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/screens/media_detail/tv_detail_header_layout.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/widgets/tv_browse_rail.dart';

/// A 1080p television at its 0.85 layout scale, the viewport the trial exists
/// for. The fixed layout leaves the header ~197pt once two rails have taken
/// their share; the hero layout leaves it all but a peek.
const _tvScale = 0.85;
const _viewportHeight = 540.0;
const _fixedHeaderHeight = 197.0;

TvDetailHeaderMetrics _metrics(double availableHeight, {bool heroLayout = false}) => TvDetailHeaderMetrics(
  availableHeight: availableHeight,
  scale: _tvScale,
  hasDescription: true,
  hasGenres: true,
  heroLayout: heroLayout,
);

/// What the page keeps free above the title area. The hero layout matches it
/// to the left inset so the logo sits the same distance from both edges.
double get _topInset => (_viewportHeight * 0.08).clamp(44.0 * _tvScale, 110.0 * _tvScale);
double get _heroTopInset => (56 * _tvScale).clamp(36.0, 72.0);

/// What the hero layout leaves the header: everything but the top inset, the
/// peeking rail edge, the gap above it and the lift that keeps the block clear
/// of the bottom.
double get _heroHeaderHeight => _viewportHeight - _heroTopInset - (26 * _tvScale + 4 * _tvScale + 64 * _tvScale);

void main() {
  group('what the two layouts leave the header', () {
    test('the fixed layout cannot hold three lines beside a logo', () {
      final layout = resolveTvDetailHeaderLayout(_metrics(_fixedHeaderHeight));

      expect(layout.summaryLines, lessThan(3), reason: 'this is the squeeze the trial exists to answer');
      expect(layout.titleMode, TvDetailTitleMode.logo);
    });

    test('the hero layout holds six lines and still a large logo', () {
      final metrics = _metrics(_heroHeaderHeight, heroLayout: true);
      final layout = resolveTvDetailHeaderLayout(metrics);

      expect(layout.summaryLines, 6);
      expect(layout.titleMode, TvDetailTitleMode.logo);
      expect(layout.titleHeight, greaterThan(metrics.minLogoHeight * 2), reason: 'not a remainder scraped together');
    });

    test('the summary stops at six lines even with height to spare', () {
      final layout = resolveTvDetailHeaderLayout(_metrics(900, heroLayout: true));

      expect(layout.summaryLines, 6);
    });

    test('the hero layout gives the summary more air and the logo less width', () {
      final hero = _metrics(_heroHeaderHeight, heroLayout: true);
      final fixed = _metrics(_fixedHeaderHeight);

      expect(hero.summaryGap, greaterThan(fixed.summaryGap));
      expect(hero.actionGap, greaterThan(fixed.actionGap));
      expect(hero.desiredLogoWidth, lessThan(fixed.desiredLogoWidth));
    });

    test('both states keep the title above the facts', () {
      // One stack, not two ends of the screen: the mark reads as the heading of
      // the block it names.
      for (final metrics in [_metrics(_heroHeaderHeight, heroLayout: true), _metrics(_fixedHeaderHeight)]) {
        final layout = resolveTvDetailHeaderLayout(metrics);

        expect(layout.showsTitle, isTrue);
        expect(layout.titleHeight, lessThanOrEqualTo(metrics.desiredLogoHeight));
      }
    });

    test('the expanded state still gives the logo its full height', () {
      final metrics = _metrics(_heroHeaderHeight, heroLayout: true);

      expect(resolveTvDetailHeaderLayout(metrics).titleHeight, metrics.desiredLogoHeight);
    });

    test('the summary gives way before the logo does', () {
      // Six lines never fit here. The logo keeps a readable height and the text
      // pays — the artwork is the page's identity, the synopsis is a press away.
      final metrics = _metrics(260, heroLayout: true);
      final layout = resolveTvDetailHeaderLayout(metrics);

      expect(layout.summaryLines, lessThan(6));
      expect(layout.titleHeight, greaterThanOrEqualTo(metrics.minLogoHeight));
    });

    test('a squeezed header is given the height three lines need', () {
      // What the screen computes as the rows' give: the shortfall between the
      // header it would have had and the one three lines want. Applies to both
      // layouts — the fixed one is where an episode's summary vanished too.
      double linesAfterGive(double header) {
        final drop = tvDetailRailDrop(availableHeight: header, scale: _tvScale, maxDrop: 86 * _tvScale);
        return resolveTvDetailHeaderLayout(_metrics(header + drop)).summaryLines.toDouble();
      }

      expect(resolveTvDetailHeaderLayout(_metrics(170)).summaryLines, 0, reason: 'swallowed without the give');
      for (final header in [170.0, 185.0, _fixedHeaderHeight, 210.0]) {
        expect(linesAfterGive(header), 3, reason: 'at ${header}pt');
      }
    });

    test('a show keeps its three lines when focus lands on an episode', () {
      // The regression this exists for: the give was measured without the
      // focused episode's own title line, so the summary had three lines until
      // the first press into the rail and one after it.
      // Both the give and the layout budget for the line, so one number
      // answers for both focus states — which is the point.
      int linesAfterGive(double header) {
        final drop = tvDetailRailDrop(
          availableHeight: header,
          scale: _tvScale,
          maxDrop: 120 * _tvScale,
          hasEpisodeTitle: true,
        );
        return resolveTvDetailHeaderLayout(
          TvDetailHeaderMetrics(
            availableHeight: header + drop,
            scale: _tvScale,
            hasDescription: true,
            hasGenres: true,
            hasEpisodeTitle: true,
          ),
        ).summaryLines;
      }

      // What the old give produced on the same headers, for contrast: it
      // measured a film's header and left the episode title unpaid for.
      int linesWithFilmGive(double header) {
        final drop = tvDetailRailDrop(availableHeight: header, scale: _tvScale, maxDrop: 86 * _tvScale);
        return resolveTvDetailHeaderLayout(
          TvDetailHeaderMetrics(
            availableHeight: header + drop,
            scale: _tvScale,
            hasDescription: true,
            hasGenres: true,
            hasEpisodeTitle: true,
          ),
        ).summaryLines;
      }

      for (final header in [170.0, 185.0, _fixedHeaderHeight, 210.0]) {
        expect(linesAfterGive(header), 3, reason: 'at ${header}pt');
        expect(linesWithFilmGive(header), lessThan(3), reason: 'the give this replaces, at ${header}pt');
      }
    });

    test('reserving the episode line spends the logo height up front', () {
      // Why a show reserves the line rather than measuring the moment: without
      // the reservation the logo takes height it has to give straight back the
      // first time a name appears above the facts, and the box visibly jumps.
      final drop = tvDetailRailDrop(
        availableHeight: _fixedHeaderHeight,
        scale: _tvScale,
        maxDrop: 120 * _tvScale,
        hasEpisodeTitle: true,
      );
      final header = _fixedHeaderHeight + drop;
      TvDetailHeaderLayout at({required bool episodeLine}) => resolveTvDetailHeaderLayout(
        TvDetailHeaderMetrics(
          availableHeight: header,
          scale: _tvScale,
          hasDescription: true,
          hasGenres: true,
          hasEpisodeTitle: episodeLine,
        ),
      );

      expect(at(episodeLine: false).titleHeight, greaterThan(at(episodeLine: true).titleHeight));
      expect(at(episodeLine: true).summaryLines, 3);
      expect(at(episodeLine: true).titleHeight, greaterThanOrEqualTo(_metrics(200).minLogoHeight));
    });

    test('the squeezed state keeps a summary, because it drops the hero spacing', () {
      // Standing on an episode: the header is back to its small budget. With
      // the hero gaps still applied it spent that budget on air and showed no
      // description at all.
      expect(
        resolveTvDetailHeaderLayout(_metrics(_fixedHeaderHeight, heroLayout: true)).summaryLines,
        lessThan(resolveTvDetailHeaderLayout(_metrics(_fixedHeaderHeight)).summaryLines),
        reason: 'the wider gaps come straight off the summary',
      );

      // And all the way down to the tightest headers: wider gaps can cost the
      // summary lines, never win it any. Stated as the rule rather than as one
      // height, because the height where the last line goes moves with every
      // change to the block. It stops holding above ~260pt, where the fixed
      // layout has hit its three-line ceiling and the hero's six-line one has
      // not — a difference of ceilings, not of spacing.
      for (final header in [210.0, 230.0, 250.0]) {
        expect(
          resolveTvDetailHeaderLayout(_metrics(header, heroLayout: true)).summaryLines,
          lessThanOrEqualTo(resolveTvDetailHeaderLayout(_metrics(header)).summaryLines),
          reason: 'at ${header}pt',
        );
      }
    });

    test('the rails decide the header in one layout and not in the other', () {
      // The point of the trial in one assertion: the fixed layout subtracts
      // the rail stack from the header, so a section loading late takes lines
      // off the summary. The hero layout subtracts a fixed peek instead, and
      // whatever grows below the edge cannot reach up.
      double fixedHeader(double railHeight) =>
          _viewportHeight - _topInset - ((railHeight - 12 * _tvScale) + 4 * _tvScale);
      double heroHeader(double railHeight) =>
          _viewportHeight - _topInset - (26 * _tvScale + 4 * _tvScale + 64 * _tvScale);

      const oneRail = 230.8;
      const twoRails = 306.3;

      expect(fixedHeader(twoRails), lessThan(fixedHeader(oneRail)));
      expect(resolveTvDetailHeaderLayout(_metrics(fixedHeader(twoRails))).summaryLines, lessThan(3));

      expect(heroHeader(twoRails), heroHeader(oneRail));
      expect(resolveTvDetailHeaderLayout(_metrics(heroHeader(twoRails), heroLayout: true)).summaryLines, 6);
    });
  });

  group('the rows the page pushes down to make room', () {
    // A show's page at a television's 960 × 540, as on a typical box: a
    // season of episodes, and "Auch verfügbar auf" — upright posters with the
    // library and server under them, the tallest row on the page.
    const width = 960.0;
    MediaHub hub(String id, MediaKind kind, String type) => MediaHub(
      id: id,
      title: '',
      type: type,
      items: [MediaItem(id: '$id-1', backend: MediaBackend.plex, kind: kind)],
    );
    final hubs = [
      hub('detail_season_1', MediaKind.episode, 'episode'),
      hub('detail_other_copies', MediaKind.show, 'mixed'),
    ];
    final copiesRow = TvBrowseRailLayout.metricsForHub(
      hub: hubs.last,
      availableWidth: width - TvBrowseRailLayout.horizontalInsetForScale(_tvScale),
      density: 3,
      episodePosterMode: EpisodePosterMode.seriesPoster,
      scale: _tvScale,
      tallPosterScale: 0.72,
    );

    /// Where the copies' labels end, from the top of the screen, on a page
    /// that reckons the rail with [countsGlimpse] and caps the push at [cap].
    double labelsFoot({required bool countsGlimpse, required double cap}) {
      double rail(bool peek) => TvBrowseRailLayout.estimateHeight(
        size: const Size(width, _viewportHeight),
        hubs: hubs,
        density: 3,
        episodePosterMode: EpisodePosterMode.seriesPoster,
        episodePosterModeForHub: (h) =>
            h == hubs.first ? EpisodePosterMode.episodeThumbnail : EpisodePosterMode.seriesPoster,
        widePosterScaleForHub: (_) => 0.72,
        tallPosterScale: 0.72,
        peekNext: peek,
      );
      final top = TvBrowseRailLayout.railTopPaddingForScale(_tvScale);
      final reckoned = rail(countsGlimpse);
      final drawn = rail(false); // under glass the rail glimpses nothing
      final headerTop = 17 + 40 * _tvScale; // below the home button
      final available = _viewportHeight - headerTop - (reckoned - top + 4 * _tvScale);
      final drop = tvDetailRailDrop(availableHeight: available, scale: _tvScale, maxDrop: cap, hasEpisodeTitle: true);
      final railTop = _viewportHeight + drop - drawn;
      return railTop +
          top +
          TvBrowseRailLayout.hubStripHeightForScale(_tvScale) +
          2 * _tvScale +
          copiesRow.containerHeight;
    }

    test('under glass keep the labels of the tallest row on screen', () {
      final cap = math.min(
        120.0 * _tvScale,
        TvBrowseRailLayout.pushableBelowEdgeFor(hubCount: hubs.length, scale: _tvScale, peekNext: false),
      );
      expect(labelsFoot(countsGlimpse: false, cap: cap), lessThanOrEqualTo(_viewportHeight));
    });

    test('where a glimpse the rail never draws was counted, they went over the edge', () {
      expect(labelsFoot(countsGlimpse: true, cap: 120.0 * _tvScale), greaterThan(_viewportHeight + 10));
    });

    test('the push can go as far as the room under the row and the breath under its labels', () {
      expect(
        TvBrowseRailLayout.pushableBelowEdgeFor(hubCount: 2, scale: 1, peekNext: false),
        TvBrowseRailLayout.footMarginForScale(1) + 8,
      );
      expect(
        TvBrowseRailLayout.pushableBelowEdgeFor(hubCount: 1, scale: 1),
        8,
        reason: 'a single row keeps nothing under it',
      );
    });
  });
}
