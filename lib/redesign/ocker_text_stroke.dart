import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The accent stroke beside a row on show under "Flach" (Plebz), as tall as
/// the row's words: from the top of the capitals of its first line to the
/// baseline of its last — one line for a library, the group's name and its
/// count for an IPTV group. Centred on the row at a fixed height, it sat low
/// beside one line and covered only the first of two (the viewer's report).
///
/// The words are measured once laid out, so the stroke follows whatever the
/// row holds; until then, and in a row without words, it stands centred at
/// [fallbackHeight].
class OckerTextStroke extends StatefulWidget {
  const OckerTextStroke({
    super.key,
    required this.child,
    required this.left,
    required this.width,
    required this.fallbackHeight,
    required this.colour,
    this.show = true,
    this.strokeKey,
  });

  final Widget child;

  /// Whether the row is the one on show. The stroke comes and goes; the row
  /// keeps its place in the tree, and with it its focus.
  final bool show;

  /// From the row's left edge.
  final double left;
  final double width;
  final double fallbackHeight;
  final Color colour;

  /// The stroke's own key, for tests.
  final Key? strokeKey;

  @override
  State<OckerTextStroke> createState() => _OckerTextStrokeState();
}

class _OckerTextStrokeState extends State<OckerTextStroke> {
  final _rowKey = GlobalKey();

  /// Top and bottom of the words, in the row; null until measured.
  (double, double)? _span;

  void _measure() {
    if (!mounted || !widget.show) return;
    final row = _rowKey.currentContext?.findRenderObject();
    if (row is! RenderBox || !row.hasSize) return;
    final placed = <(RenderParagraph, Offset)>[];
    void visit(RenderObject object) {
      if (object is RenderParagraph) {
        if (object.hasSize && object.attached) placed.add((object, object.localToGlobal(Offset.zero, ancestor: row)));
        return;
      }
      object.visitChildren(visit);
    }

    row.visitChildren(visit);
    if (placed.isEmpty) {
      if (_span != null) setState(() => _span = null);
      return;
    }
    // The row's words are the column of text furthest left; a value or a
    // count at the far side is not part of them.
    final left = placed.map((entry) => entry.$2.dx).reduce(math.min);
    final column = [
      for (final entry in placed)
        if (entry.$2.dx - left < 8) entry,
    ]..sort((a, b) => a.$2.dy.compareTo(b.$2.dy));
    final (first, firstAt) = column.first;
    final (last, lastAt) = column.last;
    final firstLines = _lines(first);
    final lastLines = _lines(last);
    if (firstLines.isEmpty || lastLines.isEmpty) return;
    // Capitals stand about seven tenths of the type's size above the line.
    final capitals = first.textScaler.scale(first.text.style?.fontSize ?? 14) * 0.72;
    final top = firstAt.dy + firstLines.first.baseline - capitals;
    final bottom = lastAt.dy + lastLines.last.baseline;
    final span = _span;
    if (span != null && (span.$1 - top).abs() < 0.5 && (span.$2 - bottom).abs() < 0.5) return;
    setState(() => _span = (top, bottom));
  }

  /// The lines [paragraph] is set in. Asked of a painter of its own: a laid
  /// out paragraph answers for its baseline only to its parent, mid-layout.
  static List<LineMetrics> _lines(RenderParagraph paragraph) {
    final painter = TextPainter(
      text: paragraph.text,
      textDirection: paragraph.textDirection,
      textScaler: paragraph.textScaler,
      maxLines: paragraph.maxLines,
      locale: paragraph.locale,
      strutStyle: paragraph.strutStyle,
      textHeightBehavior: paragraph.textHeightBehavior,
      textWidthBasis: paragraph.textWidthBasis,
    )..layout(maxWidth: paragraph.size.width);
    final lines = painter.computeLineMetrics();
    painter.dispose();
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.show) WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    final stroke = Container(
      key: widget.strokeKey,
      width: widget.width,
      height: _span == null ? widget.fallbackHeight : null,
      decoration: BoxDecoration(color: widget.colour, borderRadius: BorderRadius.circular(widget.width)),
    );
    final span = _span;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        KeyedSubtree(key: _rowKey, child: widget.child),
        if (!widget.show)
          const SizedBox.shrink()
        else if (span == null)
          Positioned(
            left: widget.left,
            top: 0,
            bottom: 0,
            child: IgnorePointer(child: Center(child: stroke)),
          )
        else
          Positioned(
            left: widget.left,
            top: span.$1,
            height: math.max(span.$2 - span.$1, widget.width),
            child: IgnorePointer(child: stroke),
          ),
      ],
    );
  }
}
