import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../i18n/strings.g.dart';
import '../theme/mono_tokens.dart';
import '../widgets/app_icon.dart';
import 'ocker_browse_grid.dart';
import 'ocker_skin.dart';
import 'ocker_type.dart';

/// A filter, a sort, a view switch: one glyph, no plate behind it, a hairline
/// ring when it holds focus.
///
/// Drawn here because it is drawn in two places. The watchlist reaches these
/// through the app bar's action row and a library through its own chip bar,
/// and while each styled its own they came out visibly different controls —
/// one a pale filled pill the size of a tap target, the other a small plated
/// chip. They do the same thing and they open the same sheets, so they are one
/// widget now and can only ever disagree by being changed here.
class OckerFilterGlyph extends StatelessWidget {
  final IconData icon;
  final bool focused;

  /// How big the glyph is drawn. Defaults to [glyphSize], which is the size
  /// the redesign wants where these sit on the same line as the tabs. A
  /// toolbar keeps the size a toolbar action has — the ring is the part of
  /// this that belongs to the look; the size belongs to the row.
  final double size;

  /// Under "Flach", the disc's diameter where a row wants a size of its own
  /// (Plebz: the Explore detail stage matches a detail page's buttons). Null
  /// for the toolbar's.
  final double? flatDiameter;

  const OckerFilterGlyph({
    super.key,
    required this.icon,
    required this.focused,
    this.size = glyphSize,
    this.flatDiameter,
  });

  /// The glyph's own size — deliberately a fixed number rather than one scaled
  /// with the viewport. These are the quietest marks on the screen, and below
  /// about this they stop being readable as a funnel or a pair of arrows at
  /// television distance whatever the arithmetic says.
  static const glyphSize = 16.0;

  /// What the row leaves around each glyph, so neighbours do not touch and the
  /// ring — which is drawn outside its box — has somewhere to be.
  static const gap = 4.0;

  /// Between one control and the next on "Flach"'s line, at 1920.
  static const flatGap = 20.0;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    if (tk.flat) return _buildFlat(context, tk);
    // These lie on a band with the words beside them, so they take its
    // weight: a heavier stroke and a brighter rest, which a hairline glyph on
    // glass did not have.
    return Padding(
      padding: const EdgeInsets.all(gap),
      // The band's gliding capsule — the same focus the words beside it show.
      // See [OckerWordFocus].
      child: OckerWordFocus(
        focused: focused,
        child: Padding(
          // The ring stands off the glyph by the same distance it stands off a
          // poster and a destination in the header.
          padding: EdgeInsets.all(tk.focusRingOffset),
          child: AppIcon(icon, fill: 0, size: size, weight: 400, color: focused ? tk.ink(1) : tk.ink(0.75)),
        ),
      ),
    );
  }
}

extension on OckerFilterGlyph {
  /// "Flach" (Plebz): a round button of its own, a faint disc of ink at rest
  /// and the white of focus when it holds it — the design's toolbar, where
  /// each control is a shape rather than a glyph on a shared band.
  Widget _buildFlat(BuildContext context, MonoTokens tk) {
    final scale = ockerScale(context);
    final diameter = flatDiameter ?? 52 * scale;
    return Padding(
      padding: EdgeInsets.only(right: OckerFilterGlyph.flatGap * scale),
      child: OckerFlatControl(
        focused: focused,
        shape: const CircleBorder(),
        child: SizedBox.square(
          dimension: diameter,
          child: Center(
            child: AppIcon(
              icon,
              fill: 0,
              size: flatDiameter == null ? math.max(24 * scale, 13) : diameter * 0.5,
              weight: 400,
              color: focused ? tk.bg : tk.ink(0.7),
            ),
          ),
        ),
      ),
    );
  }
}

/// A control on "Flach"'s toolbar: the shape filled with a faint ink at rest
/// and with the white of focus while it holds it. What stands on it picks its
/// own colour for the two.
class OckerFlatControl extends StatelessWidget {
  const OckerFlatControl({super.key, required this.focused, required this.child, this.shape = const StadiumBorder()});

  final bool focused;
  final ShapeBorder shape;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return DecoratedBox(
      decoration: ShapeDecoration(shape: shape, color: focused ? tk.ink(1) : tk.ink(0.06)),
      child: child,
    );
  }
}

/// A labelled control on "Flach"'s toolbar — a library's filter and sort: the
/// glyph and the word on a pill, 52 tall at 1920.
class OckerFlatLabelledControl extends StatelessWidget {
  const OckerFlatLabelledControl({super.key, required this.icon, required this.label, required this.focused});

  final IconData icon;
  final String label;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final scale = ockerScale(context);
    final ink = focused ? tk.bg : tk.ink(0.85);
    return Padding(
      padding: EdgeInsets.only(right: 12 * scale),
      child: OckerFlatControl(
        focused: focused,
        child: SizedBox(
          height: 52 * scale,
          child: Padding(
            padding: EdgeInsets.only(left: 16 * scale, right: 20 * scale),
            child: Row(
              mainAxisSize: .min,
              children: [
                AppIcon(icon, fill: 0, size: math.max(24 * scale, 13), weight: 400, color: ink),
                SizedBox(width: 10 * scale),
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: OckerType.of(context).groupEntry(active: false).fontFamily,
                    fontSize: 19 * scale,
                    fontWeight: FontWeight.w500,
                    height: 1,
                    color: ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The filters over a grid's top left: the glyphs on a band of glass, and
/// the gap to the first row of posters below it.
///
/// The watchlist's and a library's, drawn once: each built its own, and the
/// two need only drift a pixel apart for the page beneath them to be two
/// pages.
class OckerGridFilterBand extends StatelessWidget {
  const OckerGridFilterBand({super.key, required this.children, this.withGapBelow = true, this.location, this.count});

  final List<Widget> children;

  /// False where the band shares its line with something else and the line
  /// keeps the gap to the posters itself.
  final bool withGapBelow;

  /// Where the viewer is — "Merkliste · Plex", a library's name — on the same
  /// line, its end flush with the last column of posters. The rail names the
  /// destination, but not which list or library of it is on show. Null draws
  /// the band alone.
  final String? location;

  /// How many titles the list holds, beside [location] under "Flach".
  final int? count;

  /// Between the band and the first row of posters, at 1920.
  static const gapBelow = 18.0;

  @override
  Widget build(BuildContext context) {
    // The glyphs keep [OckerFilterGlyph.gap] round themselves; the band's
    // pane reaches that far past its row, so the row is set in by as much and
    // the pane's edge lines up with the posters' below.
    // Flat: no band to reach past; each control is its own shape, the first
    // flush with the posters.
    final overhang = ockerFlat(context)
        ? EdgeInsets.zero
        : ockerBandOverhang(context, wordInset: const EdgeInsets.all(OckerFilterGlyph.gap));
    final band = OckerGlassBand(
      overhang: overhang,
      child: Row(mainAxisSize: .min, children: children),
    );
    final location = this.location;
    return Padding(
      padding: EdgeInsets.only(left: overhang.left, bottom: withGapBelow ? gapBelow * ockerScale(context) : 0),
      child: location == null || location.isEmpty
          ? band
          : LayoutBuilder(
              builder: (context, constraints) {
                // The posters start a pixel in from the column's left edge and
                // run five wide; whatever the column has past them stays clear
                // of the words, so their end lines up with the last poster's.
                final column = constraints.maxWidth + overhang.left;
                final geometry = OckerGridGeometry.of(context, column);
                final pastPosters = (column - 1 - geometry.gridWidth(context)).clamp(0.0, column);
                return Row(
                  children: [
                    band,
                    SizedBox(width: 24 * ockerScale(context)),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: pastPosters),
                        child: OckerLocationLabel(location, count: count),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

/// Where the viewer is, over the right of a grid: the section headings' mono
/// capitals, a step quieter, since the posters below are what is being read.
class OckerLocationLabel extends StatelessWidget {
  const OckerLocationLabel(this.text, {super.key, this.count});

  final String text;

  /// Shown after the source under "Flach"; null leaves it out.
  final int? count;

  @override
  Widget build(BuildContext context) {
    final type = OckerType.of(context);
    if (type.flat) return _buildFlat(context, type);
    return Text(
      type.headingCase(text),
      textAlign: TextAlign.right,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      // Under "Flach" a filter word is quieter than the row name beside it.
      style: (type.flat ? type.counter : type.sectionHeading).copyWith(color: tokens(context).ink(0.6)),
    );
  }
}

extension on OckerLocationLabel {
  /// "Flach" (Plebz): the page's name is a title, not a label — "Merkliste"
  /// large and bold, its source and length quietly beside it ("Plex · 42").
  Widget _buildFlat(BuildContext context, OckerType type) {
    final tk = tokens(context);
    final scale = ockerScale(context);
    final cut = text.indexOf(' · ');
    final name = cut < 0 ? text : text.substring(0, cut);
    final source = cut < 0 ? null : text.substring(cut + 3);
    final length = count == null
        ? null
        : NumberFormat.decimalPattern(LocaleSettings.currentLocale.languageCode).format(count);
    final quiet = [?source, ?length].join(' · ');
    return Row(
      mainAxisAlignment: .end,
      crossAxisAlignment: .baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: type.sectionHeading.fontFamily,
              fontSize: 28 * scale,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5 * scale,
              height: 1,
              color: tk.ink(1),
            ),
          ),
        ),
        if (quiet.isNotEmpty) ...[
          SizedBox(width: 12 * scale),
          Text(quiet, maxLines: 1, style: type.counter.copyWith(color: tk.ink(0.42))),
        ],
      ],
    );
  }
}
