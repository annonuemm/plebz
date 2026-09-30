import 'package:flutter/material.dart';

import '../theme/mono_tokens.dart';

import '../media/media_rating.dart';
import '../redesign/ocker_skin.dart';
import '../utils/text_measure_cache.dart';
import 'app_icon.dart';
import 'media_rating_badge.dart';

/// One slot on a [FittedMetadataLine].
sealed class MetadataLinePart {
  const MetadataLinePart({required this.dropPriority});

  /// Which parts give way first when the line overflows: higher values are
  /// dropped before lower ones, rightmost first among equals. A
  /// [MetadataLineRatings] slot sheds one badge at a time from the end before
  /// the slot disappears.
  final int dropPriority;
}

/// A plain text field: year, certification, runtime, a quality label.
class MetadataLineText extends MetadataLinePart {
  const MetadataLineText(this.text, {required super.dropPriority});

  final String text;
}

/// A text field led by a glyph instead of a word: the pre-play track summary
/// on the detail action row uses one per track kind so the line stays short
/// enough to share the row with the buttons.
///
/// [detail] is a second, separately droppable unit ("AAC · Stereo" after
/// "Japanese") with its own [detailDropPriority], so a tight line keeps the
/// language and sheds the codec before it sheds the whole track.
class MetadataLineIconText extends MetadataLinePart {
  const MetadataLineIconText(this.icon, this.text, {required super.dropPriority, this.detail, int? detailDropPriority})
    : detailDropPriority = detailDropPriority ?? dropPriority;

  final IconData icon;
  final String text;
  final String? detail;
  final int detailDropPriority;

  /// Separator between [text] and [detail]; the track labels' own joiner.
  static const String detailSeparator = ' · ';
}

/// The attributed-score slot. Every score shares this one slot so the bullet
/// separators don't multiply with the number of sources.
class MetadataLineRatings extends MetadataLinePart {
  const MetadataLineRatings(this.ratings, {required super.dropPriority});

  final List<MediaRatingSource> ratings;
}

/// A single-line metadata strip that sheds its least useful parts instead of
/// clipping at the edge (#1893).
///
/// Parts render in list order, separated by bullets. When the assembled line
/// is wider than the incoming constraints, whole units — a text part, or one
/// rating badge — are removed by [MetadataLinePart.dropPriority] until the
/// rest fits, so the tail of the line never silently vanishes under a hard
/// cutoff.
/// [style], set the way the theme wants a line of counters set.
///
/// A year, a runtime, an age rating and a score are counters and timecodes,
/// not a sentence. The redesign used to mark that by putting them in a
/// monospace; now that the whole design is one face, what remains is the part
/// that was always doing the work: **tabular figures**, so the line does not
/// shift under the title as its numbers tick.
///
/// The caller's weight is kept. It forced 400 for as long as the facts were
/// monospace — a bold monospace at label size closes up — and that override
/// quietly swallowed the `w700` its two biggest callers had always asked for.
TextStyle monoFacts(BuildContext context, TextStyle style) {
  final mono = Theme.of(context).extension<MonoTokens>()?.monoFontFamily;
  if (mono == null) return style;
  return style.copyWith(
    fontFamily: mono,
    fontWeight: style.fontWeight ?? FontWeight.w400,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

class FittedMetadataLine extends StatelessWidget {
  const FittedMetadataLine({
    super.key,
    required this.textStyle,
    required this.parts,
    this.ratingIconSize,
    this.ratingSpacing,
    this.ratingEntrySpacing,
    this.chipped = false,
    this.chipSpacing,
  });

  /// Style shared by every text part, the separators, and the badge values.
  final TextStyle textStyle;
  final List<MetadataLinePart> parts;

  /// Icon size inside the ratings slot; defaults to the text's font size.
  final double? ratingIconSize;

  /// Gap between a badge's icon and its value.
  final double? ratingSpacing;

  /// Gap between adjacent badges inside the ratings slot.
  final double? ratingEntrySpacing;

  /// Draw each part inside a thin outline instead of separating them with
  /// bullets — under "Glas" a small capsule of glass instead of the outline.
  ///
  /// The box does the separating, so the bullets go: two devices for one job
  /// read as clutter. Opt-in, because a card's subtitle is a sentence of
  /// facts and wants to stay one.
  final bool chipped;

  /// Gap between the boxes. Defaults to half the font size, which keeps them
  /// apart at every scale without being measured per screen.
  final double? chipSpacing;

  /// Also for callers that append their own trailing widget to the line.
  static const String separator = '  •  ';

  /// The same bullet, half the air, where the line is set in mono.
  ///
  /// Every glyph in a monospaced face occupies one advance, a space included —
  /// so two spaces either side of a bullet, which reads as a comfortable gap
  /// in a proportional face, opens into a visible hole between every pair of
  /// facts and the line stops reading as one line.
  static const String monoSeparator = ' • ';

  /// Which of the two this theme sets its fact lines with. Public because a
  /// caller that builds one *string* of facts — rather than a list of parts —
  /// has to join it the same way, or two lines of the same kind would be
  /// spaced differently on the same card.
  static String separatorFor(BuildContext context) =>
      Theme.of(context).extension<MonoTokens>()?.monoFontFamily == null ? separator : monoSeparator;

  /// Gap between a [MetadataLineIconText] glyph and its text.
  static const double iconTextGap = 4;

  @override
  Widget build(BuildContext context) {
    if (parts.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        // A capsule of glass rather than an outline: rounder, so it wants more
        // room at its ends and a little more above and below the words.
        final glass = chipped && ockerGlass(context);
        // Every glass chip in the same weight, whoever draws it: bold, as the
        // detail page and the spotlight set theirs. A thin fact on one card
        // and a bold one on the next read as two different things.
        final textStyle = glass ? this.textStyle.copyWith(fontWeight: FontWeight.w700) : this.textStyle;
        // Text merges its style over the ambient default, so measuring with
        // the bare style would drop the theme's font metrics.
        final effectiveStyle = DefaultTextStyle.of(context).style.merge(textStyle);
        final textScaler = MediaQuery.textScalerOf(context);
        final textDirection = Directionality.of(context);
        final iconSize = ratingIconSize ?? effectiveStyle.fontSize ?? 13;
        final badgeGap = ratingSpacing ?? 4;
        final entryGap = ratingEntrySpacing ?? 10;

        double textWidth(String text) => cachedSingleLineTextSize(
          text,
          style: effectiveStyle,
          textScaler: textScaler,
          textDirection: textDirection,
        ).width;

        // Units are the droppable atoms: a text part is one unit, a ratings
        // slot is one unit per badge, an icon part is its text plus an
        // optional detail.
        final unitWidths = <List<double>>[
          for (final part in parts)
            switch (part) {
              MetadataLineText(:final text) => <double>[textWidth(text)],
              MetadataLineIconText(:final text, :final detail) => <double>[
                iconSize + iconTextGap + textWidth(text),
                if (detail != null) textWidth('${MetadataLineIconText.detailSeparator}$detail'),
              ],
              MetadataLineRatings(:final ratings) => <double>[
                for (final rating in ratings)
                  inlineRatingBadgeWidth(
                    rating,
                    textStyle: effectiveStyle,
                    textScaler: textScaler,
                    textDirection: textDirection,
                    iconSize: iconSize,
                    spacing: badgeGap,
                  ),
              ],
            },
        ];
        final keptUnits = [for (final widths in unitWidths) widths.length];
        final fontSize = effectiveStyle.fontSize ?? 13;
        // The outline costs width too, and a line that measured only its text
        // would shed nothing until the boxes were already over the edge.
        final chipPaddingH = fontSize * (glass ? 0.75 : 0.5);
        final chipPaddingV = fontSize * (glass ? 0.3 : 0.2);
        final chipOverhead = chipped ? (chipPaddingH + 1) * 2 : 0.0;
        final gap = separatorFor(context);
        final gapWidth = chipped ? (chipSpacing ?? fontSize * 0.5) : textWidth(gap);

        double partWidth(int index) {
          final kept = keptUnits[index];
          var width = 0.0;
          for (var unit = 0; unit < kept; unit++) {
            width += unitWidths[index][unit];
          }
          // Badges sit apart; an icon part's detail is glued to its text.
          if (kept > 1 && parts[index] is MetadataLineRatings) width += entryGap * (kept - 1);
          return width + chipOverhead;
        }

        // Priority of the unit that would go next if [index] is chosen.
        int nextUnitDropPriority(int index) {
          final part = parts[index];
          if (part is MetadataLineIconText && keptUnits[index] == 2) return part.detailDropPriority;
          return part.dropPriority;
        }

        double totalWidth() {
          var total = 0.0;
          var keptParts = 0;
          for (var index = 0; index < parts.length; index++) {
            if (keptUnits[index] == 0) continue;
            total += partWidth(index);
            keptParts++;
          }
          if (keptParts > 1) total += gapWidth * (keptParts - 1);
          return total;
        }

        if (constraints.hasBoundedWidth) {
          while (totalWidth() > constraints.maxWidth) {
            var dropIndex = -1;
            for (var index = 0; index < parts.length; index++) {
              if (keptUnits[index] == 0) continue;
              if (dropIndex == -1 || nextUnitDropPriority(index) >= nextUnitDropPriority(dropIndex)) dropIndex = index;
            }
            if (dropIndex == -1) break;
            keptUnits[dropIndex]--;
          }
        }

        final children = <Widget>[];
        for (var index = 0; index < parts.length; index++) {
          final kept = keptUnits[index];
          if (kept == 0) continue;
          if (children.isNotEmpty) {
            children.add(chipped ? SizedBox(width: gapWidth) : Text(gap, maxLines: 1, style: textStyle));
          }
          final content = switch (parts[index]) {
            MetadataLineText(:final text) => Text(text, maxLines: 1, style: textStyle),
            MetadataLineIconText(:final icon, :final text, :final detail) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(icon, size: iconSize, color: textStyle.color),
                const SizedBox(width: iconTextGap),
                Text(
                  kept == 2 && detail != null ? '$text${MetadataLineIconText.detailSeparator}$detail' : text,
                  maxLines: 1,
                  style: textStyle,
                ),
              ],
            ),
            MetadataLineRatings(:final ratings) => InlineRatingBadges(
              ratings: kept == ratings.length ? ratings : ratings.sublist(0, kept),
              textStyle: textStyle,
              foregroundColor: textStyle.color,
              iconSize: iconSize,
              spacing: badgeGap,
              entrySpacing: entryGap,
            ),
          };
          children.add(
            glass
                ? OckerGlassPlate(
                    shape: const StadiumBorder(),
                    lit: false,
                    // The band's own glass, as light as the buttons below.
                    firm: false,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: chipPaddingH + 1, vertical: chipPaddingV),
                      child: content,
                    ),
                  )
                : chipped
                ? Container(
                    padding: EdgeInsets.symmetric(horizontal: chipPaddingH, vertical: chipPaddingV),
                    decoration: BoxDecoration(
                      // From the text's own colour, so the outline stays a
                      // whisper of it on any background this line sits on.
                      border: Border.all(color: (textStyle.color ?? effectiveStyle.color!).withValues(alpha: 0.45)),
                      borderRadius: BorderRadius.circular(fontSize * 0.4),
                    ),
                    child: content,
                  )
                : content,
          );
        }
        if (children.isEmpty) return const SizedBox.shrink();
        return Row(mainAxisSize: MainAxisSize.min, children: children);
      },
    );
  }
}
