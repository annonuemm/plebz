import 'package:flutter/material.dart';

import 'ocker_skin.dart';
import 'ocker_type.dart';

/// "Glas – v2" (Plebz) on the television: the type the theme hands out —
/// settings rows, menu rows, dialogs, list tiles — on the same ramp as the
/// redesign's own ([OckerType.v2Ramp]).
///
/// Those take Material's sizes, drawn for a phone and scaled with the screen,
/// and set the settings and menus a size or two off from the pages beside
/// them. Each size is read back at the 1920-wide reference ([ockerScale]),
/// taken to the nearest step and scaled again, so a style keeps its place in
/// the order and only loses the in-between sizes. Elsewhere [child] as it is.
class OckerV2TypeRamp extends StatelessWidget {
  const OckerV2TypeRamp({super.key, required this.child});

  final Widget child;

  static ThemeData? _from;
  static double? _fromScale;
  static ThemeData? _ramped;

  /// [theme] with its text theme on the ramp at [scale].
  static ThemeData rampedTheme(ThemeData theme, double scale) {
    if (identical(theme, _from) && scale == _fromScale) return _ramped!;
    TextStyle? onRamp(TextStyle? style) {
      final size = style?.fontSize;
      if (style == null || size == null) return style;
      return style.copyWith(fontSize: OckerType.onRamp(size / scale) * scale);
    }

    final text = theme.textTheme;
    final ramped = theme.copyWith(
      textTheme: TextTheme(
        displayLarge: onRamp(text.displayLarge),
        displayMedium: onRamp(text.displayMedium),
        displaySmall: onRamp(text.displaySmall),
        headlineLarge: onRamp(text.headlineLarge),
        headlineMedium: onRamp(text.headlineMedium),
        headlineSmall: onRamp(text.headlineSmall),
        titleLarge: onRamp(text.titleLarge),
        titleMedium: onRamp(text.titleMedium),
        titleSmall: onRamp(text.titleSmall),
        bodyLarge: onRamp(text.bodyLarge),
        bodyMedium: onRamp(text.bodyMedium),
        bodySmall: onRamp(text.bodySmall),
        labelLarge: onRamp(text.labelLarge),
        labelMedium: onRamp(text.labelMedium),
        labelSmall: onRamp(text.labelSmall),
      ),
    );
    _from = theme;
    _fromScale = scale;
    return _ramped = ramped;
  }

  @override
  Widget build(BuildContext context) {
    if (!ockerGlasV2(context) || !isOckerLayout(context)) return child;
    return Theme(data: rampedTheme(Theme.of(context), ockerScale(context)), child: child);
  }
}
