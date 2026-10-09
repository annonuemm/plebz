import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../i18n/strings.g.dart';
import '../media/media_item.dart';
import '../media/media_item_types.dart';
import '../utils/content_utils.dart';
import '../utils/formatters.dart';
import '../utils/media_image_helper.dart';
import '../theme/mono_tokens.dart';
import '../widgets/fitted_metadata_line.dart';
import '../widgets/media_rating_badge.dart';
import '../widgets/optimized_media_image.dart';
import '../screens/media_detail/tv_detail_credits.dart';
import '../widgets/tv_spotlight_background.dart' show SpotlightSummary;
import 'ocker_enriched_item.dart';
import 'ocker_focus_bus.dart';
import 'ocker_skin.dart';
import 'ocker_type.dart';

/// Everything the old hero banner said, for whatever currently holds focus.
///
/// **It is never a focus target.** That is the whole idea, and the thing that
/// makes the rest of the layout possible: because the panel only ever
/// describes, LEFT out of column 1 has nowhere to go and nothing to reach, and
/// there is no state in which the panel describes something that is not
/// focused. A banner could say this for one title; this says it for all of
/// them, and costs half the screen less.
class OckerDetailPanel extends StatelessWidget {
  final OckerClientResolver resolveClient;

  /// True when a group bar has taken height off the top of the page; the still
  /// and the title both come down a size to pay for it.
  final bool withGroupBar;

  /// Wider than [OckerLayout.panelWidth] where the page has room to give it.
  ///
  /// A grid page sets its left margin flush with the header's words rather
  /// than at the design's own safe margin, and hands the panel what that
  /// reclaimed — so the words under the navigation start where the navigation
  /// starts, and the grid beside them does not move a pixel.
  final double? width;

  /// How far the card runs on past [width] to the screen's right edge, square
  /// there (Plebz): the page's right margin, which left more air outside the
  /// card than between it and the posters (the viewer's call). What it adds
  /// goes to the card's contents.
  final double bleedRight;

  const OckerDetailPanel({
    super.key,
    required this.resolveClient,
    this.withGroupBar = false,
    this.width,
    this.bleedRight = 0,
  });

  /// The card's whole width, [bleedRight] included.
  double _cardWidth(double scale) => (width ?? OckerLayout.panelWidth * scale) + bleedRight;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final type = OckerType.of(context);
    final scale = ockerScale(context);
    final focused = OckerFocusScope.watch(context)?.value;

    if (focused == null) {
      // The card stands from the first frame, empty: it is the one thing on
      // this side that does not move.
      return _glassCard(context, tk, scale, const SizedBox.shrink());
    }

    // A catalog row arrives with a poster and a title and nothing else, so it
    // is filled out from its own provider before anything is drawn — otherwise
    // the panel is blank on the whole of Explore.
    return OckerEnrichedItem(
      item: focused.item,
      builder: (context, item, _) => _buildPanel(context, item, tk, type, scale),
    );
  }

  Widget _buildPanel(BuildContext context, MediaItem item, MonoTokens tk, OckerType type, double scale) {
    final width = _cardWidth(scale);
    // The room inside the pane.
    final wordsInset = 18 * scale;
    final wordsWidth = width - 2 * wordsInset;
    // A film's tagline goes: its line of marketing beside its own title and
    // synopsis said the same thing a third time. An episode keeps its show.
    final subtitle = _episodeSubtitle(item);
    final words = <Widget>[
      // The name is type, never a wordmark — logos in every colour and shape
      // broke the card up — and smaller than the panel's own, since it shares
      // the card with the still and the synopsis. No eyebrow over it: in a
      // card that is one element, the section's name and count over the title
      // were one line too many.
      Text(
        item.displayTitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: _glassTitle(type).copyWith(color: tk.ink(1)),
      ),
      if (subtitle != null) ...[
        SizedBox(height: 6 * scale),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: type.detailSubtitle(withGroupBar: withGroupBar).copyWith(color: tk.ink(0.55)),
        ),
      ],
      SizedBox(height: 16 * scale),
      OckerFacts(item: item),
      if (_progress(item) case final progress?) ...[
        SizedBox(height: 18 * scale),
        OckerProgress(item: item, fraction: progress),
      ],
      // Not `item.summary` on its own: a catalog row — Explore, a
      // watchlist, most hubs — carries no overview at all, so a panel
      // that only printed what the row held would be blank on most of
      // what it describes. This is the same lookup the spotlight used,
      // and it answers from the same cache.
      //
      // The card runs to the foot of the page and the credits stand at its
      // foot, so the synopsis takes the room between — as many whole lines
      // as fit there, never a line cut through.
      Expanded(
        child: LayoutBuilder(
          builder: (context, box) {
            // Flach's size in both redesigns (Plebz, the viewer's call).
            final style = type.spotlightSynopsis.copyWith(color: tk.ink(0.72));
            final line = MediaQuery.textScalerOf(context).scale(style.fontSize ?? 18) * (style.height ?? 1.2);
            final gap = 20 * scale;
            // No ceiling: the card runs to the foot of the page, and the
            // synopsis has every whole line down to the credits.
            final lines = math.max(0, ((box.maxHeight - gap) / line).floor());
            if (lines == 0) return const SizedBox.shrink();
            return Align(
              alignment: Alignment.topLeft,
              child: SpotlightSummary(
                item: item,
                client: resolveClient(item),
                summary: item.summary,
                allowFillIn: !item.shouldHideSpoiler,
                gap: gap,
                maxLines: lines,
                style: style,
              ),
            );
          },
        ),
      ),
      _GlassCredits(item: item),
    ];

    // The still and the words are one card of glass, rounded and lit at its
    // edge as the channel groups are — the still inset in it, its corner
    // concentric with the card's. The card itself stands still, down to the
    // foot of the page, and only what is in it crosses over: a card that grew
    // and shrank with each synopsis was the thing moving most while the grid
    // scrolled.
    return _glassCard(
      context,
      tk,
      scale,
      AnimatedSwitcher(
        duration: tk.normal,
        switchInCurve: Curves.easeOut,
        layoutBuilder: (current, previous) =>
            Stack(fit: StackFit.expand, alignment: Alignment.topLeft, children: [...previous, ?current]),
        child: Column(
          key: ValueKey(item.id),
          crossAxisAlignment: .start,
          children: [
            _Still(
              item: item,
              width: wordsWidth,
              resolveClient: resolveClient,
              withGroupBar: withGroupBar,
              corner: BorderRadius.circular(tk.radiusSm + 8 - wordsInset),
            ),
            SizedBox(height: 16 * scale),
            ...words,
          ],
        ),
      ),
    );
  }

  /// How far the glass card stops short of the foot of the page.
  static const glassCardFoot = 40.0;

  /// The glass card, the panel's full width and down to [glassCardFoot] above
  /// the foot of the page, holding [child].
  Widget _glassCard(BuildContext context, MonoTokens tk, double scale, Widget child) {
    final corner = Radius.circular(tk.radiusSm + 8);
    return SizedBox(
      width: _cardWidth(scale),
      height: double.infinity,
      child: Padding(
        padding: EdgeInsets.only(bottom: glassCardFoot * scale),
        child: OckerGlass(
          // Square where it runs into the screen's edge.
          borderRadius: bleedRight > 0 ? BorderRadius.horizontal(left: corner) : BorderRadius.all(corner),
          scrimInset: 18 * scale,
          child: child,
        ),
      ),
    );
  }

  /// How big the title is set under glass, against the panel's own title:
  /// half first, then 30 % up from that, and a fifth up again (Plebz, the
  /// viewer's call).
  static const glassTitleScale = 0.78;

  /// The title as type under glass: the panel's own title at [glassTitleScale].
  TextStyle _glassTitle(OckerType type) {
    final full = type.detailTitle(withGroupBar: withGroupBar);
    return full.copyWith(
      fontSize: (full.fontSize ?? 50) * glassTitleScale,
      letterSpacing: (full.letterSpacing ?? 0) * glassTitleScale,
      height: 1.12,
    );
  }

  static String? _episodeSubtitle(MediaItem item) {
    if (!item.isEpisode) return null;
    final label = formatSeasonEpisodeLabel(item.parentIndex, item.index);
    final show = item.grandparentTitle;
    if (label != null && show != null) return '$show · $label';
    return label ?? show;
  }

  static double? _progress(MediaItem item) {
    final duration = item.durationMs;
    final offset = item.viewOffsetMs;
    if (duration == null || duration <= 0 || offset == null || offset <= 0) return null;
    return (offset / duration).clamp(0.0, 1.0);
  }
}

/// Who made it and who is in it, at the foot of the glass card — the same
/// credits the detail page sets over its backdrop, chosen the same way
/// ([tvDetailCredits]).
///
/// Only what the row already carries. A Plex library's list brings its
/// directors and first few roles along, and a watchlist title's detail body
/// (fetched for its synopsis anyway) brings its own; a Jellyfin library leaves
/// them out of its lists, and this does not go and ask — the card then simply
/// ends with the synopsis.
/// The hairline over the credits in the glass card.
const glassCreditsRuleKey = Key('ocker-glass-credits-rule');

class _GlassCredits extends StatelessWidget {
  final MediaItem item;

  const _GlassCredits({required this.item});

  @override
  Widget build(BuildContext context) {
    final credits = tvDetailCredits(
      directorLabel: t.discover.director,
      directorsLabel: t.discover.directors,
      studioLabel: t.discover.studio,
      castLabel: t.discover.cast,
      directors: item.directors,
      studio: item.studio,
      cast: item.roles?.map((role) => role.tag).toList(),
    );
    if (credits.isEmpty) return const SizedBox.shrink();

    final tk = tokens(context);
    final scale = ockerScale(context);
    return Padding(
      padding: EdgeInsets.only(top: 16 * scale),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        children: [
          // A hairline over them, the card's width inside its inset: the
          // credits are a second block, not the synopsis running on.
          SizedBox(
            key: glassCreditsRuleKey,
            width: double.infinity,
            height: 1,
            child: ColoredBox(color: tk.ink(0.12)),
          ),
          SizedBox(height: 14 * scale),
          for (final credit in credits)
            Padding(
              padding: EdgeInsets.only(top: credit == credits.first ? 0 : 5 * scale),
              child: Text.rich(
                TextSpan(
                  children: [
                    // As over the detail page's backdrop: the label mono and
                    // quiet, set apart by its face, the names in the body's.
                    TextSpan(
                      text: '${credit.label} ',
                      style: TextStyle(color: tk.ink(0.45), fontFamily: tk.monoFontFamily, letterSpacing: 0.8),
                    ),
                    TextSpan(
                      text: credit.value,
                      style: TextStyle(color: tk.ink(0.82)),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: .ellipsis,
                style: TextStyle(fontSize: 14 * scale, height: 1.3, fontWeight: .w500),
              ),
            ),
        ],
      ),
    );
  }
}

/// The 16:9 still at the top of the glass card.
class _Still extends StatelessWidget {
  final MediaItem item;
  final double width;
  final OckerClientResolver resolveClient;
  final bool withGroupBar;

  /// The still's own corner, concentric with the card's. No foot running out
  /// into the page: the card is its ground.
  final BorderRadius corner;

  const _Still({
    required this.item,
    required this.width,
    required this.resolveClient,
    required this.withGroupBar,
    required this.corner,
  });

  @override
  Widget build(BuildContext context) {
    final scale = ockerScale(context);
    final height = (withGroupBar ? OckerLayout.panelStillHeightWithGroupBar : OckerLayout.panelStillHeight) * scale;
    final path = item.heroBackdropPaths.firstOrNull ?? item.thumbPath;
    if (path == null || path.isEmpty) return SizedBox(width: width, height: height);

    return ClipRRect(
      borderRadius: corner,
      child: OptimizedMediaImage(
        client: resolveClient(item),
        imagePath: path,
        width: width,
        height: height,
        fit: BoxFit.cover,
        imageType: ImageType.art,
      ),
    );
  }
}

/// One line of facts that never becomes two.
///
/// [FittedMetadataLine] measures itself and drops the least important fact
/// first when the panel is narrower than the words — which is exactly the
/// machinery the typeface change has to be checked against, because a wider
/// face pays for itself by dropping a field.
/// The one line of facts under a title, in the detail page's order: year, kind,
/// age rating, length, edition, score, genres.
///
/// Public because the info sheet writes the same line — see
/// [showOckerInfoSheet]. Two copies would be two chances to describe the same
/// title differently on two screens.
/// How tall the line of facts stands, as a multiple of its type size: on
/// capsules of glass the capsule's padding adds to the line.
const ockerFactsLineFactor = 1.6;

class OckerFacts extends StatelessWidget {
  final MediaItem item;

  /// Ink strength. The default is what the panel wants, sitting on the page;
  /// the block that opens in a row sits on a photograph and asks for more.
  final double opacity;

  /// Set first on the line, ahead of the year. `S1 E7` goes here where there
  /// is no room for a line of its own — it is a fact about the thing, and it
  /// was costing a whole row to say four characters.
  final String? leading;

  /// Size against the panel's own. The block that opens in a row is read
  /// across a room and off a photograph, and takes the same step up its
  /// synopsis takes, so the two keep their relationship.
  final double sizeScale;

  const OckerFacts({super.key, required this.item, this.opacity = 0.72, this.leading, this.sizeScale = 1});

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final type = OckerType.of(context);

    // The detail page's order, so a title is described the same way on every
    // screen that shows it: which episode, when, what kind, for whom, how
    // long, which cut, how it scored, what it is about. The kind is said here
    // because this panel describes films and shows side by side; the detail
    // page is about one of them and leaves it out.
    final parts = <MetadataLinePart>[];
    // Never dropped: on an episode this is the only thing on the line that
    // says *which* episode, and the line drops its least important fact first
    // when it runs out of room.
    if (leading case final label? when label.isNotEmpty) parts.add(MetadataLineText(label, dropPriority: 0));
    if (item.year != null) parts.add(MetadataLineText('${item.year}', dropPriority: 1));
    if (item.isMovie) {
      parts.add(MetadataLineText(t.discover.movie, dropPriority: 3));
    } else if (item.isShow) {
      parts.add(MetadataLineText(t.discover.tvShow, dropPriority: 3));
    }
    if (item.contentRating case final rating?) {
      parts.add(MetadataLineText(formatContentRating(rating), dropPriority: 2, badge: true));
    }
    if (item.hasRuntime) parts.add(MetadataLineText(formatDurationTextual(item.durationMs!), dropPriority: 1));
    if (item.editionTitle case final edition? when edition.trim().isNotEmpty) {
      parts.add(MetadataLineText(edition.trim(), dropPriority: 3));
    }
    final ratings = mediaRatingsFor(item);
    if (ratings.isNotEmpty) parts.add(MetadataLineRatings(ratings, dropPriority: 4));
    // Each on its own chip, as on the detail page, and two at most: past two
    // they stop narrowing anything down. The first to go when the line runs
    // out of room.
    if (!item.isEpisode) {
      for (final genre in (item.genres ?? const <String>[]).take(2)) {
        if (genre.trim().isNotEmpty) parts.add(MetadataLineText(genre.trim(), dropPriority: 5, quiet: true));
      }
    }

    if (parts.isEmpty) return const SizedBox.shrink();
    return FittedMetadataLine(
      textStyle: type.metadata.copyWith(color: tk.ink(opacity), fontSize: (type.metadata.fontSize ?? 15) * sizeScale),
      parts: parts,
      // Each fact on a capsule of glass, which does the separating itself.
      chipped: true,
      chipSpacing: 8 * ockerScale(context),
    );
  }
}

/// How far into something the viewer is, and how much is left.
///
/// Public because the info sheet draws the same thing — see
/// [showOckerInfoSheet]. One bar, one wording, whichever describes the title.
class OckerProgress extends StatelessWidget {
  final MediaItem item;
  final double fraction;

  /// Ink strength for the words beside the bar. The default is what the panel
  /// wants on the page; the block sits on a photograph and asks for more.
  final double opacity;

  /// How long the bar is. The default is the panel's; a narrow card sets its
  /// own, since the bar shares that row with what OK will do.
  final double barWidth;

  const OckerProgress({
    super.key,
    required this.item,
    required this.fraction,
    this.opacity = 0.60,
    this.barWidth = 210,
  });

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final type = OckerType.of(context);
    final scale = ockerScale(context);
    final remainingMs = (item.durationMs ?? 0) - (item.viewOffsetMs ?? 0);

    return Row(
      children: [
        SizedBox(
          width: barWidth * scale,
          child: Stack(
            children: [
              Container(height: 3 * scale, color: tk.ink(0.20)),
              FractionallySizedBox(
                widthFactor: fraction,
                // Ink, like the bar on a poster. The accent names the *row* —
                // one rule under the resume heading, where the eye lands
                // first — and ink measures the title. One colour for the
                // question "which row is this", one for "how far in am I",
                // and neither of them said twice.
                child: Container(height: 3 * scale, color: tk.ink(1)),
              ),
            ],
          ),
        ),
        SizedBox(width: 14 * scale),
        // Gives way where the row is narrower than the bar and the words —
        // inside the glass pane, which takes its inset from the panel.
        if (remainingMs > 0)
          Flexible(
            child: Text(
              t.discover.minutesLeft(minutes: (remainingMs / 60000).round()),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: type.metadata.copyWith(color: tk.ink(opacity)),
            ),
          ),
      ],
    );
  }
}
