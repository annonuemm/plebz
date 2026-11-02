import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../redesign/ocker_skin.dart';
import '../../theme/mono_tokens.dart';

/// What a game stands on in its clubs' colours (Plebz): the "Jetzt live"
/// tiles and the favourite club's stage on the Sport page. Under Glas the
/// glass the redesign's surfaces are made of, the clubs' colours glowing
/// through it from either side; elsewhere the home club's colour running
/// into the away club's, on a slight slant — a gradient at the viewer's
/// word, where a hard split stood first. A club without a colour of its own
/// — black and white, or not known — leaves its side plain, and with neither
/// there is the plain tile, glass under Glas.
class ClubColourGround extends StatelessWidget {
  const ClubColourGround({
    super.key,
    required this.child,
    this.home,
    this.away,
    this.borderRadius,
    this.plainGroundOpacity = ockerReadingGroundOpacity,
  });

  final Color? home;
  final Color? away;

  /// The glass's corner under Glas; the posters' own when not given.
  final BorderRadius? borderRadius;

  /// How much of the ground the plain tile's glass holds.
  final double plainGroundOpacity;
  final Widget child;

  /// The clubs' colours brought down to one depth, whatever their own: the
  /// score and the crests stand on them, and a bright yellow beside a navy
  /// would make one half shout.
  static Color flatColour(Color colour) {
    final hsl = HSLColor.fromColor(colour);
    return hsl.withSaturation(math.min(hsl.saturation, 0.85)).withLightness(0.24).toColor();
  }

  static Color _glow(Color colour) {
    final hsl = HSLColor.fromColor(colour);
    return hsl.withSaturation(math.min(hsl.saturation, 0.85)).withLightness(0.45).toColor().withValues(alpha: 0.6);
  }

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final glass = ockerGlass(context) && !ockerFlat(context);
    final radius = borderRadius ?? BorderRadius.circular(artworkRadius(context));
    if (home == null && away == null) {
      return glass
          ? OckerGlass(borderRadius: radius, scrimInset: 0, groundOpacity: plainGroundOpacity, child: child)
          : ColoredBox(color: tk.tileFill, child: child);
    }
    if (!glass) {
      final left = home == null ? tk.tileFill : flatColour(home!);
      final right = away == null ? tk.tileFill : flatColour(away!);
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: const Alignment(-1, -0.4),
            end: const Alignment(1, 0.4),
            colors: [left, left, right, right],
            stops: const [0, 0.3, 0.7, 1],
          ),
        ),
        child: child,
      );
    }
    Widget glow(Color colour, Alignment centre) => Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: centre,
            radius: 0.95,
            colors: [_glow(colour), _glow(colour).withValues(alpha: 0)],
          ),
        ),
      ),
    );
    // "Glas – v2" (Plebz): the clubs run straight into each other. A glow's
    // reach follows a tile's height, so on a flat one a dark band stood
    // between the two.
    Widget blend() {
      final fallback = (home ?? away)!;
      final left = home == null ? _glow(fallback).withValues(alpha: 0) : _glow(home!);
      final right = away == null ? _glow(fallback).withValues(alpha: 0) : _glow(away!);
      return Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [left, left, right, right], stops: const [0, 0.2, 0.8, 1]),
          ),
        ),
      );
    }

    return OckerGlass(
      borderRadius: radius,
      scrimInset: 0,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (tk.v2)
            blend()
          else ...[
            if (home case final colour?) glow(colour, const Alignment(-0.7, 0.15)),
            if (away case final colour?) glow(colour, const Alignment(0.7, 0.15)),
          ],
          child,
        ],
      ),
    );
  }
}

/// A club's colour as a mark of its own — an edge, a dot — on the dark
/// ground: bright enough to be seen there, St. Pauli's brown included, and no
/// brighter than the rest.
Color clubMarkColour(Color colour) {
  final hsl = HSLColor.fromColor(colour);
  return hsl
      .withSaturation(math.min(hsl.saturation, 0.85))
      .withLightness(hsl.lightness.clamp(0.38, 0.55).toDouble())
      .toColor();
}
