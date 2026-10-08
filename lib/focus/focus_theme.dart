import 'package:flutter/material.dart';
import '../services/device_performance.dart';
import '../redesign/ocker_skin.dart' show ockerScale;
import '../theme/flat_focus_ring.dart';
import '../theme/glass_focus_decoration.dart';
import '../theme/mono_tokens.dart';
import '../utils/platform_detector.dart';

class FocusTheme {
  FocusTheme._();

  static const double focusScale = 1.02;

  /// [scale], unless the theme does not grow things on focus — then 1.0.
  ///
  /// Reads the extension nullably: a widget must still draw under a bare
  /// `ThemeData` that carries no [MonoTokens], and no theme means the app's
  /// own behaviour.
  static double focusScaleFor(BuildContext context, [double scale = focusScale]) =>
      Theme.of(context).extension<MonoTokens>()?.focusScaleEnabled == false ? 1.0 : scale;
  static const double fullCardFocusScale = 1.03;

  /// How much a focused poster grows: [focusScale], or under "Redesign –
  /// Flach" (Plebz) the design's 1.06 — there the movement comes from the
  /// growth, and the ring around it stays thin.
  static double posterFocusScaleFor(BuildContext context) {
    final tk = Theme.of(context).extension<MonoTokens>();
    return focusScaleFor(context, tk?.flat == true ? flatPosterFocusScale : focusScale);
  }

  static const double flatPosterFocusScale = 1.06;

  /// "Flach"'s ring around a picture, at the 1920-wide reference
  /// ([ockerScale]): the band of ground, then the ring.
  static const double flatRingGap = 4;
  static const double flatRingWidth = 3;

  /// Round 40px player controls: the card scale is imperceptible on a
  /// control that small, so the focused disc grows enough to be seen move.
  static const double playerControlFocusScale = 1.12;
  static const double focusBorderWidth = 2.5;
  static const double defaultBorderRadius = 8.0;
  static const double focusGlowInnerBlurRadius = 18;
  static const double focusGlowOuterBlurRadius = 34;
  static const double focusGlowSpreadRadius = 1.5;

  static Color getFocusBorderColor(BuildContext context) {
    // The theme's ring colour, which falls back to its accent — Standard sets
    // that to the same colour this used to read from. The redesign is the one
    // variant that keeps ring and accent apart:
    // white so it survives a bright poster, while ocher stays reserved.
    return Theme.of(context).extension<MonoTokens>()?.focusRingColor ?? Theme.of(context).colorScheme.primary;
  }

  static Duration getAnimationDuration(BuildContext context) {
    // Reduced tier: snap focus transitions (scale/border/glow) instead of
    // animating — each animation frame re-rasterizes the focused card.
    if (DevicePerformance.isReduced) return Duration.zero;
    return Theme.of(context).extension<MonoTokens>()?.fast ?? const Duration(milliseconds: 150);
  }

  /// How long a TV row (or the hub list) glides after one D-pad focus step.
  ///
  /// Apple TV keeps the ~500ms ease-out measured from the native focus
  /// engine's scrollable containers (issue #2006): Siri Remote swipes chain
  /// steps into one continuous glide and users expect that inertia. D-pad
  /// platforms have no such reference: Leanback's `GridLayoutManager` prices a
  /// one-card step at roughly 100-150ms, so a 500ms glide there trails the
  /// focus border on every press and reads as input lag next to the launcher.
  /// Successive presses (including hold-repeats) retarget the animation from
  /// wherever the row currently is, so a fast series still glides continuously.
  static Duration navigationScrollDuration() =>
      PlatformDetector.isAppleTV() ? const Duration(milliseconds: 500) : const Duration(milliseconds: 150);

  /// [radii] overrides [borderRadius] when per-corner radii are needed
  /// (M3E grouped cards: large outer / small inner corners).
  static BoxDecoration focusDecoration(
    BuildContext context, {
    required bool isFocused,
    double borderRadius = defaultBorderRadius,
    BorderRadius? radii,
    double borderStrokeAlign = BorderSide.strokeAlignInside,
    Color? color,
  }) {
    final corner = radii ?? BorderRadius.circular(flatRadius(context, borderRadius));
    final tk = Theme.of(context).extension<MonoTokens>();
    final strokeWidth = tk?.focusBorderWidth ?? focusBorderWidth;
    // Under "Redesign – Flach" (Plebz) a plain white frame — unless the
    // caller names a colour of its own. Aligned as the caller asks: a row in
    // a list draws it inside, where its card does not clip it away.
    if (tk != null && tk.flat && color == null) {
      // Around a picture — a ring outside its edge — the design's thin ring
      // with air between it and the artwork.
      if (borderStrokeAlign == BorderSide.strokeAlignOutside) {
        final scale = ockerScale(context);
        return FlatFocusRingDecoration(
          ink: tk.ink(1),
          ground: tk.bg,
          gap: flatRingGap * scale,
          ringWidth: flatRingWidth * scale,
          opacity: isFocused ? 1 : 0,
          borderRadius: corner,
        );
      }
      return BoxDecoration(
        borderRadius: corner,
        border: Border.all(color: isFocused ? tk.ink(1) : Colors.transparent, width: 3, strokeAlign: borderStrokeAlign),
      );
    }
    // Under "Redesign – Glas" the ring is the pane's lit edge — unless the
    // caller names a colour of its own, which then means something and is kept.
    if (tk != null && tk.glass && color == null) {
      return GlassFocusDecoration(
        colors: tk.glassFocusEdge,
        opacity: isFocused ? 1 : 0,
        ringWidth: strokeWidth,
        strokeAlign: borderStrokeAlign,
        borderRadius: corner,
      );
    }
    return BoxDecoration(
      borderRadius: corner,
      border: Border.all(
        color: isFocused ? (color ?? getFocusBorderColor(context)) : Colors.transparent,
        width: strokeWidth,
        strokeAlign: borderStrokeAlign,
      ),
    );
  }

  /// The focus glow as a list of [BoxShadow]s.
  ///
  /// Rendered by [FocusGlowOverlay] in the root overlay so the glow paints
  /// above sibling cards on all four sides (an in-tree background shadow is
  /// occluded by later-painted neighbours, which produced the one-sided halo).
  static List<BoxShadow> focusGlowShadows(Color color) {
    return [
      BoxShadow(
        color: color.withValues(alpha: 0.34),
        blurRadius: focusGlowInnerBlurRadius,
        spreadRadius: focusGlowSpreadRadius,
      ),
      BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: focusGlowOuterBlurRadius),
    ];
  }

  /// How far the focus glow visibly reaches beyond the card edge. Used to size
  /// the overlay paint area so the blur is not clipped.
  static double get focusGlowExtent => focusGlowOuterBlurRadius * 2 + focusGlowSpreadRadius;

  /// Build focus decoration with background color instead of border.
  /// Useful for video controls where it should match the native hover style.
  /// [radii] overrides [borderRadius] when per-corner radii are needed.
  ///
  /// Deliberately *not* flattened by a square theme: it is the video overlay's
  /// hover fill, drawn on top of the picture rather than as part of the app's
  /// chrome, and giving it a BuildContext would mean a required parameter on
  /// ten call sites for one corner.
  static BoxDecoration focusBackgroundDecoration({
    required bool isFocused,
    double borderRadius = defaultBorderRadius,
    BorderRadius? radii,
  }) {
    return BoxDecoration(
      borderRadius: radii ?? BorderRadius.circular(borderRadius),
      color: isFocused ? Colors.white.withValues(alpha: 0.2) : Colors.transparent,
    );
  }

  /// Focus background fill derived from the theme's text color, so it stays
  /// visible on BOTH light and dark surfaces — the white-based
  /// [focusBackgroundDecoration] disappears on light ones. This is the mono
  /// convention used by [TrackRow], the navigation rail, and the music player
  /// surfaces. Prefer this for any new mono-themed surface.
  static BoxDecoration textFillFocusDecoration(
    BuildContext context, {
    required bool isFocused,
    double borderRadius = defaultBorderRadius,
    BorderRadius? radii,
  }) {
    return BoxDecoration(
      borderRadius: radii ?? BorderRadius.circular(flatRadius(context, borderRadius)),
      color: isFocused ? tokens(context).text.withValues(alpha: 0.12) : Colors.transparent,
    );
  }
}
