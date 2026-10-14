import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A soft top edge over a list of rows while they glide (Plebz, the
/// television's rail under the redesigns): rows going up dissolve into the
/// edge instead of being cut by it, and one coming down rises out of it.
///
/// Only while [strength] is above nothing: at rest the edge is gone, the row
/// on top shows whole, and nothing is drawn offscreen. [strength] is read at
/// paint whenever [listenable] changes — the list's scroll position and
/// whatever eases the edge in and out — so it can follow the glide without a
/// rebuild.
class OckerGlideEdge extends SingleChildRenderObjectWidget {
  const OckerGlideEdge({
    super.key,
    required this.listenable,
    required this.strength,
    required this.fadeHeight,
    this.leftOverflow = 0,
    super.child,
  });

  final Listenable listenable;

  /// 0 for no edge, 1 for the full fade from clear at the top.
  final double Function() strength;

  /// How far down the fade reaches.
  final double fadeHeight;

  /// How far the rows paint past the box on the left, which the edge covers
  /// as well.
  final double leftOverflow;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderOckerGlideEdge(listenable, strength, fadeHeight, leftOverflow);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) => (renderObject as _RenderOckerGlideEdge)
    ..listenable = listenable
    ..strength = strength
    ..fadeHeight = fadeHeight
    ..leftOverflow = leftOverflow;
}

class _RenderOckerGlideEdge extends RenderProxyBox {
  _RenderOckerGlideEdge(this._listenable, this.strength, this._fadeHeight, this._leftOverflow);

  Listenable _listenable;
  set listenable(Listenable value) {
    if (identical(value, _listenable)) return;
    if (attached) _listenable.removeListener(markNeedsPaint);
    _listenable = value;
    if (attached) _listenable.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  double Function() strength;

  double _fadeHeight;
  set fadeHeight(double value) {
    if (value == _fadeHeight) return;
    _fadeHeight = value;
    markNeedsPaint();
  }

  double _leftOverflow;
  set leftOverflow(double value) {
    if (value == _leftOverflow) return;
    _leftOverflow = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _listenable.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _listenable.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  ShaderMaskLayer? get layer => super.layer as ShaderMaskLayer?;

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    final edge = strength().clamp(0.0, 1.0);
    if (edge <= 0.001 || _fadeHeight <= 0) {
      layer = null;
      context.paintChild(child, offset);
      return;
    }
    final mask = Rect.fromLTWH(offset.dx - _leftOverflow, offset.dy, size.width + _leftOverflow, size.height);
    // Clear at the very top, eased to whole at the fade's foot; whole below.
    final shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color.fromRGBO(255, 255, 255, 1 - edge),
        Color.fromRGBO(255, 255, 255, 1 - edge * 0.35),
        const Color(0xFFFFFFFF),
      ],
      stops: const [0, 0.55, 1],
    ).createShader(Rect.fromLTWH(0, 0, mask.width, _fadeHeight));
    layer = (layer ?? ShaderMaskLayer())
      ..shader = shader
      ..maskRect = mask
      ..blendMode = BlendMode.dstIn;
    context.pushLayer(layer!, (context, offset) => context.paintChild(child, offset), offset);
  }
}
