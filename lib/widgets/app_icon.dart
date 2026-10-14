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

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    if (icon == null) return const SizedBox.shrink();
    final opticalSize =
        this.opticalSize ??
        AppIconDefaults.opticalSize ??
        (AppIconDefaults.opticalSizeFollowsSize
            // Material Symbols' optical size runs from 20 to 48.
            ? (size ?? IconTheme.of(context).size ?? 24).clamp(20.0, 48.0)
            : null);
    return Icon(
      AppIconDefaults.substitutes[icon] ?? icon,
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
