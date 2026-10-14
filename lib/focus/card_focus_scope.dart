import 'package:flutter/material.dart';

import '../redesign/ocker_skin.dart' show OckerLiquidFocusRim;
import 'focus_theme.dart';

/// Exposes the focus state of an enclosing focus wrapper to a descendant
/// [CardFocusBorder] that draws the focus border itself.
///
/// The shared focus chrome ([buildFocusChrome]) inserts this instead of painting
/// a border when `delegateFocusBorder` is set, so cards can
/// put the border on the exact rect the design highlights (the poster image,
/// not the card-plus-captions rect — issue #1278). Only the [CardFocusBorder]
/// element registers a dependency, so a focus flip rebuilds just that border
/// box: a stable `child:` card subtree (e.g. the TV rail's MediaCard) is not
/// rebuilt.
class CardFocusScope extends InheritedWidget {
  const CardFocusScope({super.key, required this.showFocus, required super.child});

  /// Whether the enclosing wrapper currently shows focus visuals
  /// (focused while in keyboard/d-pad input mode).
  final bool showFocus;

  /// Null when no delegating wrapper is above (touch mode skips the focus
  /// wrappers entirely) — [CardFocusBorder] then renders its child bare.
  static bool? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<CardFocusScope>()?.showFocus;

  @override
  bool updateShouldNotify(CardFocusScope oldWidget) => showFocus != oldWidget.showFocus;
}

/// Draws the focus border around its child based on the enclosing
/// [CardFocusScope], letting the card decide which rect gets highlighted.
///
/// Defaults to an outside stroke so the border hugs the child exactly like the
/// full-bleed card treatment (the child's own corner radius nests inside it).
/// Decoration only — never affects layout. Renders the child unchanged when no
/// scope is present.
class CardFocusBorder extends StatelessWidget {
  const CardFocusBorder({
    super.key,
    this.borderRadius = FocusTheme.defaultBorderRadius,
    this.borderRadii,
    this.strokeAlign = BorderSide.strokeAlignOutside,
    this.liquidRim = false,
    this.glassRim = false,
    this.glassRimBends = false,
    required this.child,
  });

  /// Plebz: whether [child] lays a [CardLiquidRim] on its artwork. While
  /// Liquid Glass is on, the rim is the focus and the ring stands down.
  final bool liquidRim;

  /// Plebz: whether this border lays the Liquid Glass rim over the whole
  /// card itself — tiles, whose words and logos are part of the card — in
  /// place of the ring. It bends what lies under it only with
  /// [glassRimBends], for a card that is nothing but a picture.
  final bool glassRim;
  final bool glassRimBends;

  final double borderRadius;

  /// Per-corner radii; overrides [borderRadius] when set (M3E grouped cards).
  final BorderRadius? borderRadii;

  final double strokeAlign;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final showFocus = CardFocusScope.maybeOf(context);
    if (showFocus == null) return child;

    // Plebz: a card that wears the Liquid Glass rim needs no ring.
    final rim = (liquidRim || glassRim) && OckerLiquidFocusRim.showsInsteadOfRing(context);
    return AnimatedContainer(
      duration: FocusTheme.getAnimationDuration(context),
      curve: Curves.easeOutCubic,
      foregroundDecoration: FocusTheme.focusDecoration(
        context,
        isFocused: showFocus && !rim,
        borderRadius: borderRadius,
        radii: borderRadii,
        borderStrokeAlign: strokeAlign,
      ),
      child: glassRim && rim
          ? Stack(
              fit: StackFit.passthrough,
              children: [
                child,
                Positioned.fill(
                  child: OckerLiquidFocusRim(
                    focused: showFocus,
                    radii: borderRadii ?? BorderRadius.circular(borderRadius),
                    bend: glassRimBends,
                  ),
                ),
              ],
            )
          : child,
    );
  }
}

/// Plebz: the Liquid Glass rim on a card's artwork while it shows focus (see
/// OckerLiquidFocusRim). Laid over the picture and under what the card puts
/// on it — badges, labels — so only the picture bends. Reads the focus here,
/// so a focus flip rebuilds this slot and not the card.
class CardLiquidRim extends StatelessWidget {
  const CardLiquidRim({super.key, required this.radii});

  final BorderRadius radii;

  @override
  Widget build(BuildContext context) =>
      OckerLiquidFocusRim(focused: CardFocusScope.maybeOf(context) ?? false, radii: radii);
}
