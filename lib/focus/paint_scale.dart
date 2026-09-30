import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Applies a visual scale without changing hit-test or semantics geometry.
///
/// Focus scale is paint-only: animating a [Transform] marks the transformed
/// subtree's semantics dirty on every frame, which is costly for dense TV
/// grids. Keeping layout and semantics static preserves the same visible
/// motion without rebuilding the accessibility tree.
///
/// It also keeps a growing card from moving its neighbours: nothing is
/// re-laid out, so a row holds still and the focused tile simply paints a
/// little larger over it.
class PaintScale extends SingleChildRenderObjectWidget {
  const PaintScale({super.key, required this.scale, required super.child});

  final double scale;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderPaintScale(scale);

  @override
  void updateRenderObject(BuildContext context, RenderPaintScale renderObject) {
    renderObject.scale = scale;
  }
}

class RenderPaintScale extends RenderProxyBox {
  RenderPaintScale(double scale) : _scale = scale;

  final Matrix4 _transform = Matrix4.identity();
  double _scale;

  set scale(double value) {
    if (_scale == value) return;
    _scale = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    if (_scale == 1) {
      layer = null;
      super.paint(context, offset);
      return;
    }

    _transform
      ..setIdentity()
      ..setEntry(0, 0, _scale)
      ..setEntry(1, 1, _scale)
      ..setTranslationRaw((1 - _scale) * size.width / 2, (1 - _scale) * size.height / 2, 0);
    layer = context.pushTransform(
      needsCompositing,
      offset,
      _transform,
      super.paint,
      oldLayer: layer is TransformLayer ? layer as TransformLayer? : null,
    );
  }
}
