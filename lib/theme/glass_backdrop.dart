import 'package:flutter/material.dart';

import '../services/settings_service.dart' show GlasAccent;
import 'mono_theme.dart' show glasPalette, isFlachPresetGround;
import 'mono_tokens.dart';

/// The ground of "Redesign – Glas", in the manner of Apple TV's own: a flat
/// dark across the top fifth, lifting at half height, and settling a shade
/// above the top at the foot — with a flat oval of light to the left, behind
/// where Apple sets its logo.
///
/// Glass shows what lies behind it. Over one flat colour a pane of it reads as
/// a slightly different flat colour; over a ground that lifts and falls, the
/// sheen and the lit edge have something to be seen against.
///
/// The grey palette stands on the values read off Apple's screen. The others
/// take the same steps from their own ground, the light washed with their
/// accent — so each is that screen in its colour. A ground with no hue of its
/// own takes none from its accent: red over a grey lift reads as brown, and
/// the black of black, white and red should stay black.
///
/// With a plain ground chosen — OLED, off-black, a colour of the viewer's own —
/// there is no ground to speak of: the one colour, flat, and no light on it.
LinearGradient glassBackdropGradient(MonoTokens tk) {
  if (_plain(tk)) return LinearGradient(colors: [tk.bg, tk.bg]);
  if (_neutral(tk)) return neutralGlassBackdropGradient;
  // Black, flat: the light on it is the accent's own glow from below.
  if (_hueless(tk.bg)) return LinearGradient(colors: [tk.bg, tk.bg]);
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      tk.bg,
      tk.bg,
      _lift(tk, light: 0.025, tint: 0.035),
      _lift(tk, light: 0.02, tint: 0.028),
      _lift(tk, light: 0.014, tint: 0.02),
      _lift(tk, light: 0.018, tint: 0.02),
    ],
    stops: const [0, 0.22, 0.5, 0.62, 0.78, 1],
  );
}

/// The oval of light on that ground, in the palette's accent.
///
/// A ground with no hue takes its accent as a light of its own instead: the
/// pure colour, unmixed with any grey, rising from below the foot — a red
/// glow on black rather than a reddish grey, which is what read as brown.
RadialGradient glassBackdropGlow(MonoTokens tk) {
  if (_plain(tk)) return const RadialGradient(colors: [Color(0x00000000), Color(0x00000000)]);
  if (_neutral(tk)) return neutralGlassBackdropGlow;
  if (_hueless(tk.bg)) {
    return RadialGradient(
      center: const Alignment(0, 1.08),
      radius: 1.15,
      colors: [tk.accent.withValues(alpha: 0.34), tk.accent.withValues(alpha: 0.12), tk.accent.withValues(alpha: 0)],
      stops: const [0, 0.45, 1],
      transform: const _SquashedVertically(0.42, about: 1.08),
    );
  }
  // As much light as Apple's grey has: about sixteen steps above the top.
  final light = _lift(tk, light: 0.05, tint: 0.075);
  return RadialGradient(
    center: const Alignment(-0.78, 0),
    radius: 0.82,
    colors: [light.withValues(alpha: 0.8), light.withValues(alpha: 0)],
    transform: const _SquashedVertically(0.36),
  );
}

/// The palette's ground brought up towards white by [light] and washed with
/// its accent by [tint] — unless the ground has no hue to wash.
Color _lift(MonoTokens tk, {required double light, required double tint}) =>
    Color.lerp(Color.lerp(tk.bg, Colors.white, light)!, tk.accent, _hueless(tk.bg) ? 0 : tint)!;

bool _hueless(Color c) => c.r == c.g && c.g == c.b;

/// The grey glass's ground, taken off Apple TV's own settings screen: a flat
/// dark grey across the top fifth, lifting to a lighter grey at half height,
/// and settling a shade above the top's grey at the foot — with a slight cool
/// in it, as there is.
const LinearGradient neutralGlassBackdropGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    Color(0xFF1A1A1C),
    Color(0xFF1A1A1C),
    Color(0xFF232428),
    Color(0xFF212226),
    Color(0xFF1F1F23),
    Color(0xFF212124),
  ],
  stops: [0, 0.22, 0.5, 0.62, 0.78, 1],
);

/// The light in that ground: brightest to the left at half height, behind
/// where Apple sets its logo, and gone by the middle of the screen — a flat
/// oval, wide across and shallow up and down, so the top and the foot keep
/// their grey.
const RadialGradient neutralGlassBackdropGlow = RadialGradient(
  center: Alignment(-0.78, 0),
  radius: 0.82,
  colors: [Color(0xCC2D2E32), Color(0x002D2E32)],
  transform: _SquashedVertically(0.36),
);

/// Scales a gradient up and down about its box's middle — or about the height
/// [about] names, as an alignment does — leaving it as wide.
class _SquashedVertically extends GradientTransform {
  const _SquashedVertically(this.factor, {this.about = 0});

  final double factor;
  final double about;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    final middle = bounds.center.dy + about * bounds.height / 2;
    return Matrix4.translationValues(0, middle, 0)
      ..multiply(Matrix4.diagonal3Values(1, factor, 1))
      ..multiply(Matrix4.translationValues(0, -middle, 0));
  }
}

bool _neutral(MonoTokens tk) => tk.bg == glasPalette(GlasAccent.grau).bg;

/// OLED's black, the off-black or the viewer's own colour: a ground chosen to
/// be one flat colour — anything but the palette's own.
bool _plain(MonoTokens tk) =>
    tk.flat ? !isFlachPresetGround(tk.bg) : !GlasAccent.values.any((accent) => glasPalette(accent).bg == tk.bg);

/// "Flach" on its own ground: the accent, faint, in two lights — one at the
/// top left behind the logo, one at the bottom right — so the plain dark
/// carries the colour the viewer picked (the user's call). Nothing on a plain
/// ground — off-black, OLED, the viewer's own colour.
///
/// Public because the start page's spotlight covers the whole screen with its
/// picture and scrims of solid ground, and lays these over them again.
List<RadialGradient> flachGroundGlows(MonoTokens tk) {
  // The design's own ground and every look's ([flachPresets]) — the looks were
  // picked with these lights on.
  if (!tk.flat || !isFlachPresetGround(tk.bg)) return const [];
  RadialGradient light(Alignment center, double radius, double alpha) => RadialGradient(
    center: center,
    radius: radius,
    colors: [
      tk.accent.withValues(alpha: alpha),
      tk.accent.withValues(alpha: alpha * 0.4),
      tk.accent.withValues(alpha: 0),
    ],
    stops: const [0, 0.45, 1],
  );
  return [light(const Alignment(-0.95, -1), 0.9, 0.16), light(const Alignment(1, 1), 1.0, 0.12)];
}

/// [flachGroundGlows] as a layer over whatever is under it.
class FlachGroundGlow extends StatelessWidget {
  const FlachGroundGlow({super.key, required this.glows});

  final List<RadialGradient> glows;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [for (final glow in glows) DecoratedBox(decoration: BoxDecoration(gradient: glow))],
  );
}

/// [child] on the glass ground, where the theme is glass; [child] alone
/// everywhere else.
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tk = Theme.of(context).extension<MonoTokens>();
    if (tk == null || !tk.glass) return child;
    // Flat (Plebz): no gradient, only the accent's two faint lights — and the
    // same widgets on every ground, so switching it keeps the page under it.
    if (tk.flat) {
      return ColoredBox(
        color: tk.bg,
        child: Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(child: FlachGroundGlow(glows: flachGroundGlows(tk))),
            child,
          ],
        ),
      );
    }
    if (_plain(tk)) return ColoredBox(color: tk.bg, child: child);
    return DecoratedBox(
      decoration: BoxDecoration(gradient: glassBackdropGradient(tk)),
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: glassBackdropGlow(tk)),
        child: child,
      ),
    );
  }
}

/// A page transition that lays the page on the glass ground and otherwise
/// moves it exactly as [base] does.
///
/// The ground travels with its page, inside the transition, which is what an
/// opaque scaffold colour did: a page coming in covers the one beneath as it
/// arrives, and never lets it show through while both are on screen.
class GlassBackdropTransitions extends PageTransitionsBuilder {
  const GlassBackdropTransitions(this.base);

  final PageTransitionsBuilder base;

  @override
  DelegatedTransitionBuilder? get delegatedTransition => base.delegatedTransition;

  @override
  Duration get transitionDuration => base.transitionDuration;

  @override
  Duration get reverseTransitionDuration => base.reverseTransitionDuration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => base.buildTransitions(route, context, animation, secondaryAnimation, GlassBackdrop(child: child));
}

/// Flutter's own transitions, each on the glass ground.
final PageTransitionsTheme glassPageTransitionsTheme = PageTransitionsTheme(
  builders: {
    for (final entry in const PageTransitionsTheme().builders.entries) entry.key: GlassBackdropTransitions(entry.value),
  },
);
