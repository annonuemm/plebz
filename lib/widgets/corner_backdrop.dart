import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Artwork in a box of its own, with the left and bottom edges feathered away.
///
/// The alternative — artwork behind the whole screen — needs heavy scrims so
/// text stays readable, and a dark photograph then survives as barely anything.
/// Feathering into the background instead keeps the picture at full strength
/// where it is shown and gives the text a calm surface to sit on beside it.
///
/// The caller places it; on TV that is the top-right corner of the spotlight
/// and of a catalog detail page, driven by the same setting.
class CornerBackdrop extends StatelessWidget {
  const CornerBackdrop({super.key, required this.width, required this.height, required this.child, this.feather = 1});

  final double width;
  final double height;
  final Widget child;

  /// How far the edges are faded away, 0 to 1.
  ///
  /// Below 1 for the move between a full-screen backdrop and this corner box:
  /// at full size the feather would eat a third of the picture, so it comes in
  /// as the box shrinks.
  final double feather;

  @override
  Widget build(BuildContext context) {
    final amount = feather.clamp(0.0, 1.0);
    final sized = SizedBox(width: width, height: height, child: child);
    if (amount <= 0.01) return sized;

    return SizedBox(
      width: width,
      height: height,
      // Plebz: the feathered picture is drawn once and then shown as an
      // image — see [_FeatherRaster].
      child: _FeatherRaster(feather: amount, child: child),
    );
  }
}

/// The picture with its left and bottom edges feathered away, drawn once
/// into an image and shown as that image until the picture paints again
/// (Plebz).
///
/// The two masks each need an offscreen pass over two thirds of the screen,
/// and a layer tree is drawn whole on every frame: left live, they were paid
/// for on every frame anything moved, and held a 32-bit Amlogic box at about
/// 20 frames a second while the rows scrolled beside a still picture
/// (measured 2026-10-15). As an image they cost one plain draw.
///
/// It is a repaint boundary, so it paints only when the picture does —
/// arriving, changing or fading — or [feather] changes; each such paint
/// renders a fresh image. The masks are its own rather than two
/// [ShaderMask]s, whose callbacks are new closures on every build and so
/// repainted it whenever the page rebuilt. A picture holding a boundary of its
/// own, or one that cannot be rendered to an image (a platform view), would
/// change without telling this box: it is then masked live, as before.
class _FeatherRaster extends SingleChildRenderObjectWidget {
  const _FeatherRaster({required this.feather, required super.child});

  final double feather;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFeatherRaster(feather, View.of(context).devicePixelRatio);

  @override
  void updateRenderObject(BuildContext context, _RenderFeatherRaster renderObject) => renderObject
    ..feather = feather
    ..devicePixelRatio = View.of(context).devicePixelRatio;
}

class _RenderFeatherRaster extends RenderProxyBox {
  _RenderFeatherRaster(this._feather, this._devicePixelRatio);

  double _feather;
  set feather(double value) {
    if (value == _feather) return;
    _feather = value;
    markNeedsPaint();
  }

  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  ui.Image? _raster;

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  void paint(PaintingContext context, Offset offset) {
    _raster?.dispose();
    _raster = null;
    if (child == null || size.isEmpty) return;
    final raster = _hasOwnBoundaries(child!) ? null : _render();
    if (raster == null) {
      _paintMasked(context, offset);
      return;
    }
    _raster = raster;
    context.canvas.drawImageRect(
      raster,
      Rect.fromLTWH(0, 0, raster.width.toDouble(), raster.height.toDouble()),
      offset & size,
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  /// The child under both masks: the left edge fading in over the first
  /// 35 %, the foot fading out over the last 45 %, at full [_feather].
  void _paintMasked(PaintingContext context, Offset offset) {
    final shaderRect = Offset.zero & size;
    final across = LinearGradient(
      colors: const [Colors.transparent, Colors.white],
      stops: [0.0, 0.35 * _feather],
    ).createShader(shaderRect);
    final down = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: const [Colors.white, Colors.white, Colors.transparent],
      stops: [0.0, 1.0 - (0.45 * _feather), 1.0],
    ).createShader(shaderRect);
    ShaderMaskLayer mask(Shader shader) => ShaderMaskLayer()
      ..shader = shader
      ..maskRect = offset & size
      ..blendMode = BlendMode.dstIn;
    context.pushLayer(
      mask(across),
      (context, offset) =>
          context.pushLayer(mask(down), (context, offset) => context.paintChild(child!, offset), offset),
      offset,
    );
  }

  ui.Image? _render() {
    final layer = OffsetLayer();
    final context = PaintingContext(layer, Offset.zero & size);
    _paintMasked(context, Offset.zero);
    // Protected for the painting machinery; [SnapshotWidget] does the same.
    // ignore: invalid_use_of_protected_member
    context.stopRecordingIfNeeded();
    final image = layer.supportsRasterization()
        ? layer.toImageSync(Offset.zero & size, pixelRatio: _devicePixelRatio)
        : null;
    layer.dispose();
    return image;
  }

  static bool _hasOwnBoundaries(RenderObject node) {
    if (node.isRepaintBoundary) return true;
    var found = false;
    void visit(RenderObject child) {
      if (found) return;
      if (child.isRepaintBoundary) {
        found = true;
        return;
      }
      child.visitChildren(visit);
    }

    node.visitChildren(visit);
    return found;
  }

  @override
  void dispose() {
    _raster?.dispose();
    _raster = null;
    super.dispose();
  }
}

/// The share of the screen a [CornerBackdrop] covers on TV. Shared so the
/// spotlight and the catalog detail page cannot drift apart.
Size cornerBackdropSize(Size screen) => Size(screen.width * 0.68, screen.height * 0.72);
