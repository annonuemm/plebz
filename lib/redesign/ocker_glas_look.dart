import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/mono_tokens.dart';
import '../utils/platform_detector.dart';
import 'ocker_skin.dart';

// Glas after Apple's own apps (Plebz): first fitted to the Apple builds from
// Apple's guidelines, then made Glas's own on every device (the user's call,
// 2026-10-13). Flach and Original stay as they were; the system face SF Pro
// and Apple's glyphs stay on Apple's builds (`ockerAppleLook`).

/// A phone or tablet under Glas: the floating tab bar, the rail that shows
/// where one is, iOS-sized settings rows and touch targets of at least
/// [appleMinTouchTarget].
bool ockerGlasTouch(BuildContext context) => ockerGlasLookOnly(context) && PlatformDetector.isMobile(context);

/// A tablet under Glas: room enough that every place stands in the
/// navigation — no "Mehr", and the settings among them. A phone keeps "Mehr".
bool ockerGlasTablet(BuildContext context) => ockerGlasTouch(context) && MediaQuery.sizeOf(context).shortestSide >= 600;

/// A phone, a tablet or a desktop window under Glas: the screens that keep
/// the app's own arrangement, where the page bars fade softly into what
/// scrolls under them.
bool ockerGlasLookOnly(BuildContext context) => isOcker(context) && !ockerFlat(context) && ockerLookOnly(context);

/// Apple's smallest touch target, 44 × 44 points.
const double appleMinTouchTarget = 44;

/// A page bar's ground as Apple's scroll edge effect lays it (Plebz, see
/// [ockerGlasLookOnly]): clear while nothing is under the bar, and once
/// content scrolls under it the page's ground, nearly opaque, fading out over
/// the bar's last [fade] points — a soft edge where the solid bar had a hard
/// one. Goes in a [SliverAppBar]'s flexible space, which knows whether
/// anything is under it, over [child] (the bar's own flexible space, if any).
class OckerScrollEdge extends StatelessWidget {
  const OckerScrollEdge({super.key, this.child});

  final Widget? child;

  /// How far the ground fades out at the bar's foot: under the title and the
  /// buttons, which keep the full ground behind them.
  static const double fade = 16;

  /// How much of the ground the bar keeps: a trace of what lies under it shows.
  static const double groundOpacity = 0.94;

  @override
  Widget build(BuildContext context) {
    final under = context.dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>()?.isScrolledUnder ?? false;
    final tk = tokens(context);
    final ground = tk.bg;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Never in the way of a pointer: on the Mac the bar's empty space is
        // where the window is dragged.
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: under ? 1 : 0,
            duration: tk.normal,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final height = constraints.maxHeight;
                final solid = height <= fade ? 0.0 : (height - fade) / height;
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        ground.withValues(alpha: groundOpacity),
                        ground.withValues(alpha: groundOpacity),
                        ground.withValues(alpha: 0),
                      ],
                      stops: [0, solid, 1],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        ?child,
      ],
    );
  }
}

/// The room Glas's floating tab bar takes at a page's foot on iPhone and iPad
/// (Plebz): the shell lets the page run on under the bar, as Apple's apps do
/// (`Scaffold.extendBody`), which hands the page the bar's height as its
/// bottom padding. A page's scroll ends with this much room so its last row
/// scrolls clear of the bar. 0 everywhere else, where the bar sits below the
/// page as before.
double ockerFloatingBottomInset(BuildContext context) =>
    ockerGlasTouch(context) ? MediaQuery.paddingOf(context).bottom : 0;

/// [ockerFloatingBottomInset] at the end of a scroll view. Reads its own
/// context, so it is right below anything that removes padding.
class SliverFloatingBarSpace extends StatelessWidget {
  const SliverFloatingBarSpace({super.key});

  @override
  Widget build(BuildContext context) =>
      SliverPadding(padding: EdgeInsets.only(bottom: ockerFloatingBottomInset(context)));
}

/// How far a page's resting content keeps clear of Glas's floating rail on
/// iPhone and iPad in landscape (Plebz): the shell lets the page run on
/// beneath the rail, as Apple's sidebar does, and hands the page the rail's
/// extent as its leading padding. Titles, grids and the first card of a row
/// start past it; the rows scroll on beneath the glass. 0 everywhere else.
double ockerFloatingStartInset(BuildContext context) {
  if (!ockerGlasTouch(context)) return 0;
  final padding = MediaQuery.paddingOf(context);
  return Directionality.of(context) == TextDirection.rtl ? padding.right : padding.left;
}

/// [child] kept wholly clear of Glas's floating rail (Plebz; see
/// [ockerFloatingStartInset]): for a page with nothing that should run on
/// beneath the glass — the guide, whose channel column stays put, or a list.
/// Takes the rail's room as padding and hands the content no leading padding
/// of its own, so nothing inside adds it a second time.
class OckerClearOfRail extends StatelessWidget {
  const OckerClearOfRail({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final inset = ockerFloatingStartInset(context);
    if (inset == 0) return child;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Padding(
      padding: EdgeInsetsDirectional.only(start: inset),
      child: MediaQuery.removePadding(context: context, removeLeft: !rtl, removeRight: rtl, child: child),
    );
  }
}

/// Rows one under the other with a hairline between each two that show, as
/// iOS separates a list's rows (Plebz, Glas's settings on phones and
/// tablets): a row that draws nothing — a setting hidden on this device —
/// takes no line with it, so no two lines meet. Each line takes [hairline] of
/// its own and starts [inset] in from the leading edge, where the words do.
class AppleSeparatedRows extends MultiChildRenderObjectWidget {
  const AppleSeparatedRows({super.key, required this.color, required this.inset, super.children});

  final Color color;
  final double inset;

  /// iOS's hairline.
  static const double hairline = 0.5;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderAppleSeparatedRows(color, inset, Directionality.of(context));

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderAppleSeparatedRows)
        ..color = color
        ..inset = inset
        ..textDirection = Directionality.of(context);
}

class _AppleRowParentData extends ContainerBoxParentData<RenderBox> {
  /// Whether a line stands above this row: it shows, and so does one before.
  bool separated = false;
}

class _RenderAppleSeparatedRows extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _AppleRowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _AppleRowParentData> {
  _RenderAppleSeparatedRows(this._color, this._inset, this._textDirection);

  Color _color;
  set color(Color value) {
    if (value == _color) return;
    _color = value;
    markNeedsPaint();
  }

  double _inset;
  set inset(double value) {
    if (value == _inset) return;
    _inset = value;
    markNeedsPaint();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsPaint();
  }

  static const _hairline = AppleSeparatedRows.hairline;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _AppleRowParentData) child.parentData = _AppleRowParentData();
  }

  BoxConstraints _rowConstraints(BoxConstraints constraints) => BoxConstraints.tightFor(width: constraints.maxWidth);

  /// The rows' heights laid end to end, with a line between each two that
  /// show.
  double _stack(Iterable<double> heights) {
    var total = 0.0;
    var shown = false;
    for (final height in heights) {
      if (height <= 0) continue;
      if (shown) total += _hairline;
      total += height;
      shown = true;
    }
    return total;
  }

  Iterable<RenderBox> get _rows sync* {
    for (var child = firstChild; child != null; child = childAfter(child)) {
      yield child;
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final height = _stack([for (final row in _rows) row.getDryLayout(_rowConstraints(constraints)).height]);
    return constraints.constrain(Size(constraints.maxWidth, height));
  }

  @override
  void performLayout() {
    var y = 0.0;
    var shown = false;
    for (final row in _rows) {
      row.layout(_rowConstraints(constraints), parentUsesSize: true);
      final data = row.parentData! as _AppleRowParentData;
      final shows = row.size.height > 0;
      data.separated = shows && shown;
      if (data.separated) y += _hairline;
      data.offset = Offset(0, y);
      y += row.size.height;
      shown = shown || shows;
    }
    size = constraints.constrain(Size(constraints.maxWidth, y));
  }

  @override
  double computeMinIntrinsicHeight(double width) => _stack([for (final row in _rows) row.getMinIntrinsicHeight(width)]);

  @override
  double computeMaxIntrinsicHeight(double width) => _stack([for (final row in _rows) row.getMaxIntrinsicHeight(width)]);

  @override
  double computeMinIntrinsicWidth(double height) => _rows.fold(
    0.0,
    (widest, row) => widest > row.getMinIntrinsicWidth(height) ? widest : row.getMinIntrinsicWidth(height),
  );

  @override
  double computeMaxIntrinsicWidth(double height) => _rows.fold(
    0.0,
    (widest, row) => widest > row.getMaxIntrinsicWidth(height) ? widest : row.getMaxIntrinsicWidth(height),
  );

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
    final line = Paint()..color = _color;
    final rtl = _textDirection == TextDirection.rtl;
    for (final row in _rows) {
      final data = row.parentData! as _AppleRowParentData;
      if (!data.separated) continue;
      final top = offset.dy + data.offset.dy - _hairline;
      context.canvas.drawRect(Rect.fromLTWH(offset.dx + (rtl ? 0 : _inset), top, size.width - _inset, _hairline), line);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
