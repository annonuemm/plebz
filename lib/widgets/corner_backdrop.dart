import 'package:flutter/material.dart';

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
      child: ShaderMask(
        shaderCallback: (rect) => LinearGradient(
          colors: const [Colors.transparent, Colors.white],
          stops: [0.0, 0.35 * amount],
        ).createShader(rect),
        blendMode: BlendMode.dstIn,
        child: ShaderMask(
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [Colors.white, Colors.white, Colors.transparent],
            stops: [0.0, 1.0 - (0.45 * amount), 1.0],
          ).createShader(rect),
          blendMode: BlendMode.dstIn,
          child: child,
        ),
      ),
    );
  }
}

/// The share of the screen a [CornerBackdrop] covers on TV. Shared so the
/// spotlight and the catalog detail page cannot drift apart.
Size cornerBackdropSize(Size screen) => Size(screen.width * 0.68, screen.height * 0.72);
