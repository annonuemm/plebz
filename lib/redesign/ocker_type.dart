import 'package:flutter/material.dart';

import '../theme/mono_theme.dart' show ockerMonoFontFamily, ockerUiFontFamily;
import 'ocker_skin.dart';

/// The type scale of the "Ocker" variant — §3.1 of the styleguide, drawn for
/// 1920 x 1080 and scaled from there by [ockerScale].
///
/// Two families and a weight. Mono sets everything that is a label, a counter,
/// a clock or a technical string; the grotesque sets everything else, with
/// bold reserved for the name of something you can watch. Which family a line
/// is in is therefore information, not decoration — you can tell what kind of
/// thing you are reading before you read it.
///
/// A serif held the title's job at first. It was the right drawing and the
/// wrong screen — see [detailTitle].
///
/// Colour is deliberately absent. It comes from the theme's ink ladder
/// (`tokens(context).ink(0.72)` and friends), so one style can serve a focused
/// and an unfocused row without forking.
class OckerType {
  /// 1.0 at 1920 wide; see [ockerScale].
  final double scale;

  /// "Redesign – Flach" (Plebz): one voice per level, no tracked-out capitals.
  /// The handful of styles it redraws ask this; the rest are shared.
  final bool flat;

  const OckerType(this.scale, {this.flat = false});

  factory OckerType.of(BuildContext context) => OckerType(ockerScale(context), flat: ockerFlat(context));

  double _px(double referenceSize) => referenceSize * scale;

  // ---------------------------------------------------------------- display

  /// The focused title in the detail panel. 60 rather than 64 when a group bar
  /// has taken height off the panel.
  ///
  /// The grotesque, bold — not the serif the design was drawn with.
  ///
  /// Instrument Serif is a display face with hairline strokes and a single
  /// weight, and a television is the one screen it cannot survive: read across
  /// a room, over a photograph, on a panel that softens every edge it draws,
  /// the thin strokes go first and the name of the thing becomes the hardest
  /// line on the page to read. The whole job of a title is to be read first.
  /// So it is set in the face every other line on the card is set in, at the
  /// one weight that holds at that distance.
  ///
  /// Set a fifth below the room it reserves — see [titleBoxHeight]. At the
  /// drawn size the serif was replaced at, a bold grotesque is a great deal
  /// louder than the face it took over from: same height, far more ink. The
  /// name still wants to be the first thing read and no longer wants to be
  /// the only thing seen.
  TextStyle detailTitle({bool withGroupBar = false}) => TextStyle(
    fontFamily: ockerUiFontFamily,
    fontWeight: .w700,
    fontSize: _px((withGroupBar ? 60 : 64) * titleTextScale),
    letterSpacing: _px(-1.1),
    height: 1.08,
  );

  /// How much smaller a title is drawn than the space it is given.
  ///
  /// The two are separate on purpose. [titleBoxHeight] is a *layout* figure —
  /// what a title costs a block, whether it turns out to be type or a
  /// wordmark, so the block measures the same either way. This is the *type*,
  /// and it sits inside that.
  static const double titleTextScale = 0.78;

  /// The room a title occupies, drawn or not.
  ///
  /// A block that holds a title has to reserve its height before it knows
  /// whether a logo will turn up in its place, or it would reflow under the
  /// reader when the answer arrives.
  double titleBoxHeight({bool withGroupBar = false}) => _px(withGroupBar ? 60 : 64) * 1.08;

  /// The name of the title the start page or a detail page is about, under
  /// "Flach": 60 on the start page, 76 on a detail page, set tight.
  ///
  /// Its own style rather than a larger [detailTitle]: that one is also the
  /// title of the guide band and the info sheet, which have no room to grow.
  TextStyle spotlightTitle({bool detail = false}) {
    final size = _px(detail ? 76 : 60);
    return TextStyle(
      fontFamily: ockerUiFontFamily,
      fontWeight: .w700,
      fontSize: size,
      letterSpacing: -0.027 * size,
      height: 1.04,
    );
  }

  /// The line of facts under [spotlightTitle]: plain words with dots between.
  ///
  /// 23, a step over the design's 19: the viewer found it small on the
  /// television.
  TextStyle get spotlightFacts => TextStyle(
    fontFamily: ockerUiFontFamily,
    fontSize: _px(23),
    fontWeight: .w500,
    height: 1,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// The line under a title: an episode, a subtitle, a second name.
  ///
  /// The italic went with the serif. A grotesque has no drawn italic, so the
  /// renderer slants it — and a slanted grotesque at this size reads as a
  /// mistake rather than as a second voice. What sets it apart from the title
  /// above is weight, which is the distinction this face is built to make.
  TextStyle detailSubtitle({bool withGroupBar = false}) =>
      TextStyle(fontFamily: ockerUiFontFamily, fontSize: _px(withGroupBar ? 25 : 27), height: 1.2);

  // -------------------------------------------------------------- interface

  TextStyle get wordmark => TextStyle(
    fontFamily: ockerUiFontFamily,
    fontSize: _px(23),
    fontWeight: .w700,
    letterSpacing: _px(-0.7),
    height: 1,
  );

  /// A destination in the header. The active one is the same size in a heavier
  /// weight — never a different size, or the row would reflow as focus moves.
  /// 24, not the 18 the handoff draws. The drawing is a picture of a 1920-wide
  /// screen seen from a desk; a television reports half that and is read from
  /// a sofa, and at 18 the row of destinations was the smallest type on the
  /// screen rather than the first thing found on it.
  TextStyle navWord({required bool active}) =>
      TextStyle(fontFamily: ockerUiFontFamily, fontSize: _px(24), fontWeight: active ? .w600 : .w400, height: 1);

  /// An entry in the group bar: a library, or a channel group. Just under the
  /// destinations above them, for the same reason and by the same amount.
  TextStyle groupEntry({required bool active}) =>
      TextStyle(fontFamily: ockerUiFontFamily, fontSize: _px(22), fontWeight: active ? .w600 : .w500, height: 1);

  TextStyle get body => TextStyle(fontFamily: ockerUiFontFamily, fontSize: _px(18), height: 1.6);

  /// How much larger prose is set than the interface around it.
  ///
  /// Body copy that is genuinely *read* — a synopsis — is the smallest type on
  /// the screen and sits in the least favourable place on it: across a room,
  /// and often over a photograph. A step up is what makes it a sentence rather
  /// than a texture. The line of facts beside it takes the same step, so the
  /// two keep their relationship wherever a description appears.
  ///
  /// A sixth, not a third. It was a third while the only place a description
  /// appeared was a block twice as wide as it is tall; in the upright card the
  /// same type fills half the line length, and a third over turned four short
  /// lines into a wall. One size for prose everywhere is worth more than a
  /// size tuned to one shape of box.
  static const double readingScale = 1.17;

  /// The description of a title, wherever one is shown: in the panel at the
  /// left of a page, and on the backdrop a focused row unfolds into. One size,
  /// because they are the same sentence about the same thing — and a reader
  /// who looks from one to the other should not have to change focus.
  ///
  /// "Flach" sets it at 25 with a line and a half: the wider leading was what
  /// made four short lines read as a texture rather than a sentence, and the
  /// design's 21 read small on the television (the viewer's call).
  TextStyle get synopsis => flat
      ? TextStyle(fontFamily: ockerUiFontFamily, fontSize: _px(25), height: 1.5, letterSpacing: 0)
      : TextStyle(fontFamily: ockerUiFontFamily, fontSize: _px(18 * readingScale), height: 1.6);

  /// Credits, and anything else that is body copy one notch down.
  TextStyle get secondary => TextStyle(fontFamily: ockerUiFontFamily, fontSize: _px(15), height: 1.6);

  /// The single line of facts under a title. Never wraps — see the widget that
  /// draws it — so its figures are tabular and cannot change its width as the
  /// numbers tick.
  TextStyle get metadata => TextStyle(
    fontFamily: ockerUiFontFamily,
    fontSize: _px(15),
    height: 1,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// The facts inside the Live-TV band — the window, what is left of it, what
  /// follows — and its description.
  ///
  /// Bigger than the [metadata] and [body] they would otherwise take, for the
  /// same reason [sectionHeading] is bigger than the handoff draws it: a
  /// television reports half the width this design was drawn at, so the shared
  /// 15 lands at ten pixels on the panel and the shared 18 at twelve. Read
  /// from a sofa that is not a size, it is a footnote. The band has the height
  /// to spare — it is fixed at [OckerLayout.panelStillHeight] and the text
  /// beside the picture did not fill it.
  ///
  /// "Flach" sets them as its start page sets its facts and its prose, 23 and
  /// 25: the design's 19 and 21 read small on the television there too (the
  /// viewer's call).
  TextStyle get guideFacts => metadata.copyWith(fontSize: _px(flat ? 23 : 19));

  /// Two lines of programme description, one notch under the facts beside it.
  TextStyle get guideSummary => TextStyle(fontFamily: ockerUiFontFamily, fontSize: _px(flat ? 25 : 21), height: 1.5);

  TextStyle get primaryButton =>
      TextStyle(fontFamily: ockerUiFontFamily, fontSize: _px(19), fontWeight: .w700, height: 1);

  /// The clock at the end of the header. 22, a step under the destinations it
  /// shares the row with: it is the one thing up there that is never pressed,
  /// but it is also the one thing up there read at a glance from across the
  /// room, and at 18 it was the smallest type on the band.
  TextStyle get clock => TextStyle(
    fontFamily: ockerUiFontFamily,
    fontSize: _px(22),
    height: 1,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  // ------------------------------------------------------------------- mono

  /// A section heading, and the eyebrow above a title in the detail panel:
  /// the same style, because they are the same kind of thing said twice.
  ///
  /// 19, not the 14 the handoff draws — the same correction the destinations
  /// above them got, for the same reason. A television reports half the width
  /// the design was drawn at and is read from a sofa; at 14 the name of a
  /// shelf was seven points on the panel, which is a size for a footnote.
  ///
  /// "Flach" sets a row's name in sentence case, semibold: tracked capitals
  /// competed with the title above them. Callers leave the case alone there
  /// ([headingCase]).
  TextStyle get sectionHeading => flat
      ? TextStyle(
          fontFamily: ockerUiFontFamily,
          fontSize: _px(23),
          fontWeight: .w600,
          letterSpacing: _px(-0.2),
          height: 1,
        )
      : _monoLabel;

  /// [text] as a heading is written: in capitals everywhere but "Flach".
  String headingCase(String text) => flat ? text : text.toUpperCase();

  /// The eyebrow keeps the mono label in every variant: it names a kind of
  /// thing above a title, which is what a label is for.
  TextStyle get eyebrow => _monoLabel;

  TextStyle get _monoLabel =>
      TextStyle(fontFamily: ockerMonoFontFamily, fontSize: _px(19), letterSpacing: _px(2.4), height: 1);

  /// The source label at the left of a group-bar row.
  TextStyle get sourceLabel =>
      TextStyle(fontFamily: ockerMonoFontFamily, fontSize: _px(13), letterSpacing: _px(1.8), height: 1);

  /// The count beside a heading or a group entry. A step under the heading it
  /// belongs to, and it moved up with it.
  TextStyle get counter => flat
      ? TextStyle(
          fontFamily: ockerUiFontFamily,
          fontSize: _px(17),
          fontWeight: .w500,
          height: 1,
          fontFeatures: const [FontFeature.tabularFigures()],
        )
      : TextStyle(
          fontFamily: ockerMonoFontFamily,
          fontSize: _px(16),
          letterSpacing: _px(1.4),
          height: 1,
          fontFeatures: const [FontFeature.tabularFigures()],
        );

  /// A broadcast time inside the Live-TV grid: the hour a programme starts and
  /// how long it runs, and the scale along the top.
  ///
  /// 15, not the 11 the handoff draws. That number is measured against a
  /// 1920-wide screen seen from a desk, and beside a title set in the app's own
  /// unscaled `bodySmall` it came out at less than half the height of the line
  /// above it — a footnote where it is the only fact in the block that says
  /// *when*.
  TextStyle get timecode => TextStyle(
    fontFamily: ockerMonoFontFamily,
    fontSize: _px(15),
    height: 1,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// The chip riding on top of the now-line, and the LIVE badge.
  TextStyle get nowChip => TextStyle(
    fontFamily: ockerMonoFontFamily,
    fontSize: _px(12),
    fontWeight: .w600,
    height: 1,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// The letters inside a drawn key: OK, ZURÜCK, GRÜN.
  TextStyle get keycap =>
      TextStyle(fontFamily: ockerMonoFontFamily, fontSize: _px(12), letterSpacing: _px(1), height: 1);

  /// The technical strip at the foot of a context menu: codec, size, audio.
  TextStyle get technical => TextStyle(fontFamily: ockerMonoFontFamily, fontSize: _px(13), height: 1.4);
}
