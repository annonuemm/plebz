import 'package:flutter/material.dart';

/// Erases the pixels behind it, so a native video surface composited under
/// the Flutter view shows through.
///
/// `Colors.transparent` would not do: it means *paint nothing*, which leaves
/// whatever was painted earlier — a page's background, the route below a
/// growing player — exactly where it was.
class VideoSurfaceHole extends StatelessWidget {
  const VideoSurfaceHole({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.expand(child: CustomPaint(painter: _ClearPainter()));
}

class _ClearPainter extends CustomPainter {
  const _ClearPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..blendMode = BlendMode.clear);
  }

  @override
  bool shouldRepaint(_ClearPainter oldDelegate) => false;
}
