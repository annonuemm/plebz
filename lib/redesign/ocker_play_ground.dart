import 'package:flutter/material.dart';

import '../focus/focus_theme.dart';
import '../theme/flat_focus_ring.dart';
import '../theme/mono_tokens.dart';
import 'ocker_frost.dart';
import 'ocker_skin.dart';

/// What a page's one main action stands on under the redesigns (Plebz): the
/// detail page's play button, and the Sport stage's "Zum Spiel" — one
/// button, drawn in one place, so the two cannot drift apart.
///
/// - "Glas – v2" on the television ([v2]): filled with the accent at rest, a
///   ring standing off it on focus; under Milchglas glass rather than the
///   accent.
/// - "Flach": one flat fill of the accent, as Apple's buttons are (the
///   user's call, 2026-11-03: the gradient from the mark read as busy, on
///   the television too), and focus a thin ring standing off it, as round a
///   poster.
/// - Glas: the accent's (or the Plebz palette's) tinted glass.
/// - Elsewhere the button as it is.
///
/// [radius] is a capsule's corner — half the button's height — for the ring
/// where [shape] has no corner of its own.
class OckerPlayGround extends StatelessWidget {
  const OckerPlayGround({
    super.key,
    required this.v2,
    required this.focused,
    required this.shape,
    required this.radius,
    required this.child,
  });

  final bool v2;
  final bool focused;
  final OutlinedBorder shape;
  final double radius;
  final Widget child;

  /// Whether the label on it is white or the ground: on the accent's fill
  /// (v2's and Flach's) a light accent takes the dark, Milchglas's glass
  /// always white.
  static Color foreground(BuildContext context, {required bool v2}) {
    final tk = tokens(context);
    if (!v2 && !ockerFlat(context)) return Colors.white;
    final glass = v2 && ockerFrost(context);
    return !glass && ThemeData.estimateBrightnessForColor(tk.accent) == Brightness.light ? tk.bg : Colors.white;
  }

  BorderRadius _ringRadius(BuildContext context) {
    final shape = this.shape;
    return shape is RoundedRectangleBorder
        ? shape.borderRadius.resolve(Directionality.of(context))
        : BorderRadius.circular(radius);
  }

  Widget _ring(BuildContext context, Widget child) {
    final tk = tokens(context);
    final scale = ockerScale(context);
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: FlatFocusRingDecoration(
        ink: tk.ink(1),
        ground: tk.bg,
        gap: FocusTheme.flatRingGap * scale,
        ringWidth: FocusTheme.flatRingWidth * scale,
        opacity: focused ? 1 : 0,
        borderRadius: _ringRadius(context),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    if (v2) {
      final frost = ockerFrost(context);
      // Frosted: glass rather than the accent, clipped apart from the ring,
      // which stands outside the shape.
      return DecoratedBox(
        decoration: ShapeDecoration(shape: shape, color: frost ? null : tk.accent),
        position: DecorationPosition.background,
        child: _ring(
          context,
          frost
              ? OckerFrostBlur(
                  shape: shape.copyWith(side: BorderSide(color: tk.ink(0.28))),
                  tint: tk.ink(ockerFrostButtonTint),
                  child: child,
                )
              : child,
        ),
      );
    }
    if (ockerFlat(context)) {
      return DecoratedBox(
        decoration: ShapeDecoration(shape: shape, color: tk.accent),
        position: DecorationPosition.background,
        child: _ring(context, child),
      );
    }
    if (ockerPlebzPlay(context) || ockerGlasTintedPlay(context)) {
      return OckerPlebzPlayGround(focused: focused, shape: shape, child: child);
    }
    return child;
  }
}
