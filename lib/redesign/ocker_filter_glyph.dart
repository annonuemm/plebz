import 'package:flutter/material.dart';

import '../theme/mono_tokens.dart';
import '../widgets/app_icon.dart';
import 'ocker_skin.dart';

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

  const OckerFilterGlyph({super.key, required this.icon, required this.focused, this.size = glyphSize});

  /// The glyph's own size — deliberately a fixed number rather than one scaled
  /// with the viewport. These are the quietest marks on the screen, and below
  /// about this they stop being readable as a funnel or a pair of arrows at
  /// television distance whatever the arithmetic says.
  static const glyphSize = 16.0;

  /// What the row leaves around each glyph, so neighbours do not touch and the
  /// ring — which is drawn outside its box — has somewhere to be.
  static const gap = 4.0;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
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

/// The filters over a grid's top left: the glyphs on a band of glass, and
/// the gap to the first row of posters below it.
///
/// The watchlist's and a library's, drawn once: each built its own, and the
/// two need only drift a pixel apart for the page beneath them to be two
/// pages.
class OckerGridFilterBand extends StatelessWidget {
  const OckerGridFilterBand({super.key, required this.children, this.withGapBelow = true});

  final List<Widget> children;

  /// False where the band shares its line with something else and the line
  /// keeps the gap to the posters itself.
  final bool withGapBelow;

  /// Between the band and the first row of posters, at 1920.
  static const gapBelow = 18.0;

  @override
  Widget build(BuildContext context) {
    // The glyphs keep [OckerFilterGlyph.gap] round themselves; the band's
    // pane reaches that far past its row, so the row is set in by as much and
    // the pane's edge lines up with the posters' below.
    final overhang = ockerBandOverhang(context, wordInset: const EdgeInsets.all(OckerFilterGlyph.gap));
    return Padding(
      padding: EdgeInsets.only(left: overhang.left, bottom: withGapBelow ? gapBelow * ockerScale(context) : 0),
      child: OckerGlassBand(
        overhang: overhang,
        child: Row(mainAxisSize: .min, children: children),
      ),
    );
  }
}
