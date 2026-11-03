import 'package:flutter/material.dart';

/// Wrapper around [Icon] that centralizes our Material Symbols defaults.
/// Defaults: fill=1 (filled) and weight=700 (bold). Update [AppIconDefaults]
/// to tweak app-wide icon appearance from one place.
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.fill,
    this.weight,
    this.grade,
    this.opticalSize,
    this.shadows,
    this.semanticLabel,
    this.textDirection,
    this.marksState = false,
  });

  final IconData? icon;
  final double? size;
  final Color? color;
  final double? fill;
  final double? weight;
  final double? grade;
  final double? opticalSize;
  final List<Shadow>? shadows;
  final String? semanticLabel;
  final TextDirection? textDirection;

  /// Whether [fill] tells a state — the place on show, a favourite that is
  /// set, a toggle that is on — rather than a habit of the code. The app's own
  /// glyphs keep a fill only then, for transport controls (filled by name) and
  /// for small inline markers; everything else is Apple's outline.
  final bool marksState;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    if (icon == null) return const SizedBox.shrink();
    final shown = AppIconDefaults.substitutes[icon] ?? icon;
    final glyph = AppIconDefaults.glyphs[shown];
    if (glyph != null) return _buildGlyph(context, glyph);
    final opticalSize =
        this.opticalSize ??
        AppIconDefaults.opticalSize ??
        (AppIconDefaults.opticalSizeFollowsSize
            // Material Symbols' optical size runs from 20 to 48.
            ? (size ?? IconTheme.of(context).size ?? 24).clamp(20.0, 48.0)
            : null);
    return Icon(
      shown,
      size: size,
      color: color,
      fill: fill ?? AppIconDefaults.fill,
      weight: weight ?? AppIconDefaults.weight,
      grade: grade ?? AppIconDefaults.grade,
      opticalSize: opticalSize,
      shadows: shadows ?? AppIconDefaults.shadows,
      semanticLabel: semanticLabel,
      textDirection: textDirection,
    );
  }

  /// [glyph] from the app's own set in place of the Material Symbol: one
  /// weight, so weight and optical size go unused and fill picks the filled
  /// twin by Apple's rule (Plebz, the user's call 2026-11-03): outlines beside
  /// words, fills for emphasis — a state ([marksState]) or a marker small
  /// enough to sit in a line of text (a rating's star, a lock). Drawn a little
  /// smaller inside the same square, since these glyphs run to the edge of
  /// their box where Material's leave a margin.
  Widget _buildGlyph(BuildContext context, IconData glyph) {
    final size = this.size ?? IconTheme.of(context).size ?? 24;
    final filled = (fill ?? AppIconDefaults.fill) >= 0.5 && (marksState || size <= AppIconDefaults.markerSize);
    return SizedBox.square(
      dimension: size,
      child: Center(
        child: Icon(
          filled ? AppIconDefaults.filledGlyphs[glyph] ?? glyph : glyph,
          size: size * AppIconDefaults.glyphScale,
          color: color,
          shadows: shadows ?? AppIconDefaults.shadows,
          semanticLabel: semanticLabel,
          textDirection: textDirection,
        ),
      ),
    );
  }
}

/// Central place to adjust default Material Symbol variations.
class AppIconDefaults {
  static double fill = 1;
  static double weight = 700;
  static double? grade;
  static double? opticalSize;
  static Color? color;
  static List<Shadow>? shadows;

  /// Glyphs drawn in place of others (Plebz: Apple's own on the Apple
  /// builds — see `applyIconDefaultsFor`).
  static Map<IconData, IconData> substitutes = {};

  /// The app's own glyph for a Material Symbol (Plebz: Apple's look, see
  /// `plebzGlyphs`), and the filled twin of each for `fill: 1`. Empty: every
  /// symbol keeps its Material glyph.
  static Map<IconData, IconData> glyphs = {};
  static Map<IconData, IconData> filledGlyphs = {};

  /// How much of the square a glyph from [glyphs] is drawn at: their ink runs
  /// to the edge of the box, Material's keeps about a sixth clear (measured
  /// over the app's most used pairs, 2026-11-03).
  static double glyphScale = 0.84;

  /// Up to this size a filled glyph from [glyphs] counts as a marker in a
  /// line of text and keeps its fill (see `AppIcon.marksState`).
  static double markerSize = 16;

  /// Whether an icon without an optical size of its own is drawn for the size
  /// it is shown at, rather than the font's 24.
  static bool opticalSizeFollowsSize = false;

  static void update({
    double? fill,
    double? weight,
    double? grade,
    double? opticalSize,
    Color? color,
    List<Shadow>? shadows,
  }) {
    if (fill != null) AppIconDefaults.fill = fill;
    if (weight != null) AppIconDefaults.weight = weight;
    if (grade != null) AppIconDefaults.grade = grade;
    if (opticalSize != null) AppIconDefaults.opticalSize = opticalSize;
    if (color != null) AppIconDefaults.color = color;
    if (shadows != null) AppIconDefaults.shadows = shadows;
  }
}
