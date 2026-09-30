import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'glass_edge_spin.dart';

/// The three colours a glass focus edge runs through, top left to bottom
/// right: where the light falls on it, the middle, and the far end.
///
/// The middle colour stands from [midFrom] to [midTo] along the diagonal.
/// Both at the halfway point, the default, is a plain run from one end to the
/// other; a span holds the middle, so a highlight can stay in its corner and
/// the far colour in its own.
@immutable
class GlassEdgeColors {
  const GlassEdgeColors({required this.lit, required this.mid, required this.end, this.midFrom = 0.5, this.midTo = 0.5})
    : assert(0 < midFrom && midFrom <= midTo && midTo < 1);

  final Color lit;
  final Color mid;
  final Color end;
  final double midFrom;
  final double midTo;

  @override
  bool operator ==(Object other) =>
      other is GlassEdgeColors &&
      other.lit == lit &&
      other.mid == mid &&
      other.end == end &&
      other.midFrom == midFrom &&
      other.midTo == midTo;

  @override
  int get hashCode => Object.hash(lit, mid, end, midFrom, midTo);
}

/// The focus ring of "Redesign – Glas": a pane's edge catching the light.
///
/// Bright where the light falls on it at the top left, thinning through the
/// middle, and warming into the accent at the bottom right — one stroke, so it
/// reads as the edge of something rather than a line drawn round it. Which
/// colours those are is the palette's (`MonoTokens.glassFocusEdge`). A little
/// heavier than the redesign's hairline, because a gradient spends part of its
/// width on the faint stretch.
///
/// **A decoration, not a border.** Flutter animates a decoration's border only
/// between its own two border classes and throws on any other — and every
/// focus ring here sits in an animated container. So the ring is painted by
/// the decoration itself, and the border it reports is a plain transparent
/// one of the ring's width: whatever this is interpolated with, the part
/// Flutter interpolates is ordinary, and it keeps the same insets a ring of
/// that width always had. Between two of these, focus fades the edge in and
/// out.
class GlassFocusDecoration extends BoxDecoration {
  GlassFocusDecoration({
    required this.colors,
    required this.opacity,
    required double ringWidth,
    this.strokeAlign = BorderSide.strokeAlignInside,
    super.borderRadius,
    super.shape,
  }) : edgeWidth = ringWidth * 1.75,
       super(
         border: Border.all(color: Colors.transparent, width: ringWidth, strokeAlign: strokeAlign),
       );

  /// What the edge runs through, each at its full strength.
  final GlassEdgeColors colors;

  /// How much of the edge shows: 0 while the thing it surrounds has no focus.
  final double opacity;

  /// Inside, on, or outside the box's own edge, as for a [BorderSide].
  final double strokeAlign;

  /// The painted stroke: the theme's ring width, and three quarters again.
  final double edgeWidth;

  GlassFocusDecoration _at(double value) => GlassFocusDecoration(
    colors: colors,
    opacity: value,
    ringWidth: edgeWidth / 1.75,
    strokeAlign: strokeAlign,
    borderRadius: borderRadius,
    shape: shape,
  );

  @override
  BoxDecoration? lerpFrom(Decoration? a, double t) {
    if (a is GlassFocusDecoration) return _at(lerpDouble(a.opacity, opacity, t)!);
    return super.lerpFrom(a, t);
  }

  @override
  BoxDecoration? lerpTo(Decoration? b, double t) {
    if (b is GlassFocusDecoration) return b._at(lerpDouble(opacity, b.opacity, t)!);
    return super.lerpTo(b, t);
  }

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _GlassFocusPainter(this, onChanged);

  @override
  bool operator ==(Object other) =>
      other is GlassFocusDecoration &&
      super == other &&
      other.colors == colors &&
      other.opacity == opacity &&
      other.strokeAlign == strokeAlign &&
      other.edgeWidth == edgeWidth;

  @override
  int get hashCode => Object.hash(super.hashCode, colors, opacity, strokeAlign, edgeWidth);
}

class _GlassFocusPainter extends BoxPainter {
  _GlassFocusPainter(this._decoration, super.onChanged) {
    // Only a showing edge turns: one at rest never asks for a frame.
    if (_decoration.opacity > 0 && onChanged != null) {
      _spinListener = onChanged;
      GlassEdgeSpin.instance.addListener(_spinListener!);
    }
  }

  final GlassFocusDecoration _decoration;
  VoidCallback? _spinListener;

  @override
  void dispose() {
    if (_spinListener case final listener?) GlassEdgeSpin.instance.removeListener(listener);
    super.dispose();
  }

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    final d = _decoration;
    if (size == null || size.isEmpty || d.opacity <= 0) return;
    final spin = GlassEdgeSpin.instance;
    spin.notePainted();
    final turn = spin.turn;
    final rect = offset & size;
    // The stroke's centre line: inside, on, or outside the box's own edge.
    final shift = d.edgeWidth * d.strokeAlign / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = d.edgeWidth
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          for (final c in [d.colors.lit, d.colors.mid, d.colors.mid, d.colors.end])
            c.withValues(alpha: c.a * d.opacity),
        ],
        stops: [0, d.colors.midFrom, d.colors.midTo, 1],
        // The light going round the edge, when the viewer has asked for it.
        transform: turn == 0 ? null : GradientRotation(turn * 2 * math.pi),
      ).createShader(rect);
    switch (d.shape) {
      case BoxShape.circle:
        canvas.drawCircle(rect.center, rect.shortestSide / 2 + shift, paint);
      case BoxShape.rectangle:
        final radius = d.borderRadius?.resolve(configuration.textDirection) ?? BorderRadius.zero;
        canvas.drawRRect(radius.toRRect(rect).inflate(shift), paint);
    }
  }
}
