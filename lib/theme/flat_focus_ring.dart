import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// The focus ring of "Redesign – Flach" (Plebz) around a picture: a thin ring
/// of ink standing off the edge, with a band of the ground between.
///
/// The air is what lifts the poster without framing it; the band is painted
/// in the ground's own colour so the picture's edge stays crisp against
/// whatever is behind it. Decoration only — it never changes layout, and it
/// paints outside the box it decorates.
class FlatFocusRingDecoration extends BoxDecoration {
  const FlatFocusRingDecoration({
    required this.ink,
    required this.ground,
    required this.gap,
    required this.ringWidth,
    required this.opacity,
    super.borderRadius,
  });

  final Color ink;
  final Color ground;

  /// The band of ground between the picture and the ring.
  final double gap;
  final double ringWidth;

  /// How much of the ring shows: 0 while the picture has no focus.
  final double opacity;

  FlatFocusRingDecoration _at(double value) => FlatFocusRingDecoration(
    ink: ink,
    ground: ground,
    gap: gap,
    ringWidth: ringWidth,
    opacity: value,
    borderRadius: borderRadius,
  );

  @override
  BoxDecoration? lerpFrom(Decoration? a, double t) {
    if (a is FlatFocusRingDecoration) return _at(lerpDouble(a.opacity, opacity, t)!);
    return super.lerpFrom(a, t);
  }

  @override
  BoxDecoration? lerpTo(Decoration? b, double t) {
    if (b is FlatFocusRingDecoration) return b._at(lerpDouble(opacity, b.opacity, t)!);
    return super.lerpTo(b, t);
  }

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _FlatFocusRingPainter(this);

  @override
  bool operator ==(Object other) =>
      other is FlatFocusRingDecoration &&
      other.ink == ink &&
      other.ground == ground &&
      other.gap == gap &&
      other.ringWidth == ringWidth &&
      other.opacity == opacity &&
      other.borderRadius == borderRadius;

  @override
  int get hashCode => Object.hash(ink, ground, gap, ringWidth, opacity, borderRadius);
}

class _FlatFocusRingPainter extends BoxPainter {
  _FlatFocusRingPainter(this._decoration);

  final FlatFocusRingDecoration _decoration;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    final d = _decoration;
    if (size == null || size.isEmpty || d.opacity <= 0) return;
    final radius = d.borderRadius?.resolve(configuration.textDirection) ?? BorderRadius.zero;
    final edge = radius.toRRect(offset & size);
    canvas.drawRRect(
      edge.inflate(d.gap / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = d.gap
        ..color = d.ground.withValues(alpha: d.ground.a * d.opacity),
    );
    canvas.drawRRect(
      edge.inflate(d.gap + d.ringWidth / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = d.ringWidth
        ..color = d.ink.withValues(alpha: d.ink.a * d.opacity),
    );
  }
}
