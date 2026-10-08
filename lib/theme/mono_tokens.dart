import 'dart:ui';
import 'package:flutter/material.dart';

import 'glass_focus_decoration.dart' show GlassEdgeColors;

MonoTokens tokens(BuildContext context) => Theme.of(context).extension<MonoTokens>()!;

/// [radius], unless the theme draws square corners — then 0.
///
/// The app writes dozens of corner radii straight into widgets rather than
/// reading a token, each picked for its own surface. This wraps them so a
/// square theme can flatten the lot without any of those choices being
/// revisited one at a time.
///
/// No theme flattens them at the moment. The redesign did, for as long as its
/// pictures were square as well; once the posters were rounded, every box
/// beside them read as an oversight rather than as a decision, and the ladder
/// came back — see `monoTheme`. The wrapper stays: it is one line at each of
/// those three dozen sites, it costs nothing, and the next square theme gets
/// it for free.
///
/// Reads the extension nullably rather than through [tokens]: a widget must
/// still draw under a bare `ThemeData` that carries no [MonoTokens] at all,
/// and no theme means no square corners.
double flatRadius(BuildContext context, double radius) =>
    Theme.of(context).extension<MonoTokens>()?.squareCorners == true ? 0 : radius;

/// The corner artwork is drawn with — a poster, a still, a backdrop.
///
/// Where the redesign's corners started. §10 asked for square everywhere, and
/// artwork was the exception that broke it: a picture the interface is
/// *showing* is not a box the interface drew, and a picture with a corner reads
/// as an object lying on the page where a square one reads as a hole cut in it.
/// The boxes followed, through the radius ladder in `monoTheme`.
///
/// Still its own number rather than [MonoTokens.radiusSm]: artwork is drawn a
/// shade rounder than the boxes around it, which is the proportion a poster's
/// own corner comes out at. Elsewhere it *is* [MonoTokens.radiusSm], so
/// "Standard" is untouched.
///
/// Read off `displayFontFamily`, the field only the redesign palettes fill —
/// the same marker `isOcker` uses, restated here because the token layer cannot
/// import the redesign's own gates without a cycle.
double artworkRadius(BuildContext context) {
  final t = Theme.of(context).extension<MonoTokens>();
  if (t == null) return 8;
  return t.displayFontFamily == null ? t.radiusSm : 14;
}

/// [shadows], unless the theme forbids them — then none.
///
/// Decoration only: a halo around a focused card, the lift under a floating
/// panel. A shadow that exists so white text stays legible on top of artwork or
/// video is not decoration and is left alone, because removing it would cost
/// information rather than noise.
List<BoxShadow> flatShadows(BuildContext context, List<BoxShadow> shadows) =>
    Theme.of(context).extension<MonoTokens>()?.shadowsEnabled == false ? const [] : shadows;

/// M3E connected-group geometry for item [index] of a [count]-item group:
/// large radii on the group's outer corners, small radii between adjacent
/// items. Pair with `MonoTokens.groupGap` spacing for the hairline gaps.
BorderRadius groupItemRadii(BuildContext context, int index, int count) {
  final t = tokens(context);
  return BorderRadius.vertical(
    top: Radius.circular(index == 0 ? t.radiusLg : t.radiusXs),
    bottom: Radius.circular(index == count - 1 ? t.radiusLg : t.radiusXs),
  );
}

@immutable
class MonoTokens extends ThemeExtension<MonoTokens> {
  /// Effectively-stadium radius for pill shapes; the renderer proportionally
  /// clamps oversized RRect radii (same trick as FocusableButton).
  static const double radiusFull = 100;

  final double radiusSm;
  final double radiusMd;

  /// Outer corners of M3E grouped-list cards and connected button groups.
  final double radiusLg;

  /// Inner corners between adjacent items of an M3E group.
  final double radiusXs;

  /// Gap between adjacent items of an M3E group.
  final double groupGap;

  final double space;
  final Duration fast;
  final Duration normal;
  final Duration slow;

  /// M3E shape-morph duration (segment square→pill and friends).
  final Duration expressive;
  final Color bg;
  final Color surface;
  final Color outline;
  final Color text;
  final Color textMuted;

  /// The one colour the theme is allowed to be loud in: focus rings and the
  /// active entry in the navigation.
  ///
  /// Standard sets it to [text], which is what those surfaces already used, so
  /// nothing moves there; the redesign takes its palette's accent.
  final Color accent;

  /// Stroke of a focus ring: 2.5 in Standard, a hairline in the redesign.
  final double focusBorderWidth;

  /// Whether a catalog poster may draw its focus ring in its own artwork
  /// colour instead of [accent].
  ///
  /// False in the redesign: it earns its clarity from one accent, and a ring
  /// that changes hue per poster spends exactly that.
  final bool itemAccentFocusRing;

  /// Whether a section heading carries an icon before its title.
  ///
  /// The rows say what they are in words; the glyph beside them repeats that
  /// and adds a second thing to look at. The redesign drops it, and the
  /// heading is then carried by type alone.
  final bool sectionIcons;

  /// Whether the app bar's profile button shows the profile's own avatar.
  ///
  /// False falls back to a plain person glyph. What that trades away is which
  /// profile is active — with one profile the initial says nothing anyway,
  /// with several it does. The menu behind the button names them either way.
  final bool profileAvatar;

  /// Typeface for content titles. Null means the platform's own.
  ///
  /// Ocker splits type into three jobs so each one can be recognised without
  /// reading it: a serif means "this is the name of something you can watch",
  /// mono means "this is a label, a counter or a time". Standard
  /// leaves all three null and keep one family for everything.
  final String? displayFontFamily;

  /// Typeface for the interface itself — navigation, body copy, buttons.
  final String? uiFontFamily;

  /// Typeface for labels, counters, timecodes and technical strings.
  final String? monoFontFamily;

  /// Colour of a focus ring, when that is not [accent].
  ///
  /// Ocker is the case that needs the two apart: the ring is bone white so it
  /// reads on any poster, while ocher is spent only on progress, the now-line
  /// and the active navigation entry. Left null everywhere else, which is why
  /// [focusRingColor] falls back to [accent] and nothing moves.
  final Color? focusRing;

  /// The colour a focus ring is actually drawn in.
  Color get focusRingColor => focusRing ?? accent;

  /// Gap between a focus ring and the thing it surrounds.
  ///
  /// Zero draws the ring on the edge, which is what the app has always done.
  /// Ocker holds it off by 5 px so the artwork keeps its own outline — the
  /// tiles have no border of their own to hide behind.
  final double focusRingOffset;

  /// Whether surfaces may carry a drop shadow.
  ///
  /// False flattens them: separation then has to come from a hairline, from
  /// spacing, or from nothing at all.
  final bool shadowsEnabled;

  /// Whether a focused card grows a little.
  ///
  /// It was false under "Ocker", on the grounds that the design has exactly
  /// one focus mark and means it. The objection it rested on — that a growing
  /// tile nudges its neighbours — turned out not to hold: the growth is
  /// paint-only ([PaintScale]), so nothing is re-laid out and the row holds
  /// still while the focused tile paints a little larger over it. Asked for
  /// on the television, where the ring alone reads as less than the movement
  /// does.
  final bool focusScaleEnabled;

  /// Whether this variant also rearranges the screens, or only repaints them.
  ///
  /// Two variants wear the "Ocker" look. One of them moves the navigation into
  /// the header, replaces the hero banner with a detail panel and rebuilds the
  /// guide; the other keeps every screen exactly where the app has always put
  /// it and changes nothing but colour, type and shape.
  ///
  /// The distinction is a token rather than a settings lookup so a widget under
  /// a `Theme` override — a preview, a test, a screenshot harness — answers for
  /// the theme it is drawn in. Read it through `isOckerLayout`.
  final bool redesignLayout;

  /// Whether the floating surfaces — sheets, the up-next card, the player's
  /// control bar — are drawn as glass rather than filled. Only "Redesign –
  /// Glas" says yes; read it through `ockerGlass`.
  final bool glass;

  /// "Redesign – Flach" (Plebz): the glass surfaces keep their structure and
  /// behaviour — [glass] stays true — but are painted flat: no sheen, no lit
  /// edge, solid fills, focus a white fill with what stands on it inverted.
  final bool flat;

  /// How much of the [accent] the glass capsule wears on the one chosen — the
  /// destination on show, the chosen row of a menu. A faint wash in most
  /// palettes; one that is only black, white and red spends its red there.
  final double accentWash;

  /// What a glass focus edge runs through: the ink, white round the most of
  /// it, and a little of the accent in the bottom right corner only.
  ///
  /// It has been ink thinning into the accent, and then black with a glint;
  /// white reads best, with the accent as a small share.
  GlassEdgeColors get glassFocusEdge =>
      GlassEdgeColors(lit: text, mid: text.withValues(alpha: 0.9), end: accent, midFrom: 0.4, midTo: 0.78);

  /// Whether this theme draws square corners throughout.
  ///
  /// Read off the largest radius rather than carried as its own flag: a theme
  /// whose outer corners are 0 has no rounded corner anywhere, and one source
  /// of truth cannot disagree with itself.
  ///
  /// False in all four variants now. It is kept because it is the honest way to
  /// ask the question, and because the redesign was square for most of its life
  /// and could be again.
  bool get squareCorners => radiusLg == 0;

  /// A step on the ink opacity ladder — [text] at [opacity].
  ///
  /// One derivation instead of a token per grey: the design asks for eleven
  /// steps between 0.32 and 1.0, and eleven named fields would be eleven
  /// chances to introduce a twelfth.
  Color ink(double opacity) => text.withValues(alpha: opacity);

  /// The fill of a tile, chip or card that stands on the page's ground.
  ///
  /// [surface] is opaque: under glass it is the block fill composited over
  /// the palette's flat ground, but the page behind is a gradient that lifts
  /// and glows. Painted opaque, a tile there was a flat patch, darker than the
  /// light around it — the "dark area behind" that kept being reported. Under
  /// glass the fill is the same ink step laid over whatever is behind it.
  Color get tileFill => glass ? ink(0.06) : surface;

  const MonoTokens({
    required this.radiusSm,
    required this.radiusMd,
    required this.radiusLg,
    required this.radiusXs,
    required this.groupGap,
    required this.space,
    required this.fast,
    required this.normal,
    required this.slow,
    required this.expressive,
    required this.bg,
    required this.surface,
    required this.outline,
    required this.text,
    required this.textMuted,
    required this.accent,
    this.focusBorderWidth = 2.5,
    this.itemAccentFocusRing = true,
    this.sectionIcons = true,
    this.profileAvatar = true,
    this.displayFontFamily,
    this.uiFontFamily,
    this.monoFontFamily,
    this.focusRing,
    this.focusRingOffset = 0,
    this.shadowsEnabled = true,
    this.focusScaleEnabled = true,
    this.redesignLayout = false,
    this.glass = false,
    this.flat = false,
    this.accentWash = 0.22,
  });

  @override
  MonoTokens copyWith({
    double? radiusSm,
    double? radiusMd,
    double? radiusLg,
    double? radiusXs,
    double? groupGap,
    double? space,
    Duration? fast,
    Duration? normal,
    Duration? slow,
    Duration? expressive,
    Color? bg,
    Color? surface,
    Color? outline,
    Color? text,
    Color? textMuted,
    Color? accent,
    double? focusBorderWidth,
    bool? itemAccentFocusRing,
    bool? sectionIcons,
    bool? profileAvatar,
    String? displayFontFamily,
    String? uiFontFamily,
    String? monoFontFamily,
    Color? focusRing,
    double? focusRingOffset,
    bool? shadowsEnabled,
    bool? focusScaleEnabled,
    bool? redesignLayout,
    bool? glass,
    bool? flat,
    double? accentWash,
  }) => MonoTokens(
    radiusSm: radiusSm ?? this.radiusSm,
    radiusMd: radiusMd ?? this.radiusMd,
    radiusLg: radiusLg ?? this.radiusLg,
    radiusXs: radiusXs ?? this.radiusXs,
    groupGap: groupGap ?? this.groupGap,
    space: space ?? this.space,
    fast: fast ?? this.fast,
    normal: normal ?? this.normal,
    slow: slow ?? this.slow,
    expressive: expressive ?? this.expressive,
    bg: bg ?? this.bg,
    surface: surface ?? this.surface,
    outline: outline ?? this.outline,
    text: text ?? this.text,
    textMuted: textMuted ?? this.textMuted,
    accent: accent ?? this.accent,
    focusBorderWidth: focusBorderWidth ?? this.focusBorderWidth,
    itemAccentFocusRing: itemAccentFocusRing ?? this.itemAccentFocusRing,
    sectionIcons: sectionIcons ?? this.sectionIcons,
    profileAvatar: profileAvatar ?? this.profileAvatar,
    displayFontFamily: displayFontFamily ?? this.displayFontFamily,
    uiFontFamily: uiFontFamily ?? this.uiFontFamily,
    monoFontFamily: monoFontFamily ?? this.monoFontFamily,
    focusRing: focusRing ?? this.focusRing,
    focusRingOffset: focusRingOffset ?? this.focusRingOffset,
    shadowsEnabled: shadowsEnabled ?? this.shadowsEnabled,
    focusScaleEnabled: focusScaleEnabled ?? this.focusScaleEnabled,
    redesignLayout: redesignLayout ?? this.redesignLayout,
    glass: glass ?? this.glass,
    flat: flat ?? this.flat,
    accentWash: accentWash ?? this.accentWash,
  );

  @override
  ThemeExtension<MonoTokens> lerp(covariant MonoTokens? other, double t) {
    if (other == null) return this;
    Color lerpC(Color a, Color b) => Color.lerp(a, b, t)!;
    Duration lerpD(Duration a, Duration b) =>
        Duration(milliseconds: lerpDouble(a.inMilliseconds.toDouble(), b.inMilliseconds.toDouble(), t)!.round());
    return MonoTokens(
      radiusSm: lerpDouble(radiusSm, other.radiusSm, t)!,
      radiusMd: lerpDouble(radiusMd, other.radiusMd, t)!,
      radiusLg: lerpDouble(radiusLg, other.radiusLg, t)!,
      radiusXs: lerpDouble(radiusXs, other.radiusXs, t)!,
      groupGap: lerpDouble(groupGap, other.groupGap, t)!,
      space: lerpDouble(space, other.space, t)!,
      fast: lerpD(fast, other.fast),
      normal: lerpD(normal, other.normal),
      slow: lerpD(slow, other.slow),
      expressive: lerpD(expressive, other.expressive),
      bg: lerpC(bg, other.bg),
      surface: lerpC(surface, other.surface),
      outline: lerpC(outline, other.outline),
      text: lerpC(text, other.text),
      textMuted: lerpC(textMuted, other.textMuted),
      accent: lerpC(accent, other.accent),
      focusBorderWidth: lerpDouble(focusBorderWidth, other.focusBorderWidth, t)!,
      itemAccentFocusRing: t < 0.5 ? itemAccentFocusRing : other.itemAccentFocusRing,
      // Nothing to interpolate: an icon is there or it is not, and switching
      // it at the halfway point is the least visible moment to do it.
      sectionIcons: t < 0.5 ? sectionIcons : other.sectionIcons,
      profileAvatar: t < 0.5 ? profileAvatar : other.profileAvatar,
      // Type cannot be interpolated either — a half-serif does not exist —
      // and a family that swaps mid-fade reflows every line it sets twice.
      displayFontFamily: t < 0.5 ? displayFontFamily : other.displayFontFamily,
      uiFontFamily: t < 0.5 ? uiFontFamily : other.uiFontFamily,
      monoFontFamily: t < 0.5 ? monoFontFamily : other.monoFontFamily,
      focusRing: Color.lerp(focusRing ?? accent, other.focusRing ?? other.accent, t),
      focusRingOffset: lerpDouble(focusRingOffset, other.focusRingOffset, t)!,
      shadowsEnabled: t < 0.5 ? shadowsEnabled : other.shadowsEnabled,
      focusScaleEnabled: t < 0.5 ? focusScaleEnabled : other.focusScaleEnabled,
      redesignLayout: t < 0.5 ? redesignLayout : other.redesignLayout,
      glass: t < 0.5 ? glass : other.glass,
      flat: t < 0.5 ? flat : other.flat,
      accentWash: lerpDouble(accentWash, other.accentWash, t)!,
    );
  }
}
