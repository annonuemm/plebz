import 'package:flutter/widgets.dart';

/// How much darker the artwork beneath is drawn — for [OptimizedMediaImage],
/// which darkens its own pixels by it and nothing else.
///
/// The redesign steps back what does not hold focus. It used to do that with
/// a wash of black laid over the whole box a card or a tile stands in, and
/// wherever the picture did not fill that box — a card's padding, a logo with
/// clear corners, a tile rounded more gently than the box — the wash showed as
/// a translucent black ground behind the element, or as a darker shape with
/// the wrong corners. Darkening the picture itself has no shape to get wrong,
/// and costs no layer: the image's paint takes a colour in `srcATop`, exactly
/// as it already did for a rail's inactive rows.
class ArtworkDimScope extends InheritedWidget {
  const ArtworkDimScope({super.key, required this.dim, required super.child});

  /// From 0, as drawn, to 1, black.
  final Animation<double> dim;

  static Animation<double>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ArtworkDimScope>()?.dim;

  @override
  bool updateShouldNotify(ArtworkDimScope oldWidget) => dim != oldWidget.dim;
}

/// Draws the artwork in [child] [amount] darker while [dimmed], easing to it
/// and back over [duration].
class ArtworkDim extends StatefulWidget {
  const ArtworkDim({
    super.key,
    required this.dimmed,
    required this.amount,
    required this.duration,
    this.curve = Curves.easeOutCubic,
    required this.child,
  });

  final bool dimmed;
  final double amount;
  final Duration duration;
  final Curve curve;
  final Widget child;

  @override
  State<ArtworkDim> createState() => _ArtworkDimState();
}

class _ArtworkDimState extends State<ArtworkDim> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: widget.dimmed ? widget.amount : 0,
    upperBound: 1,
  );

  @override
  void didUpdateWidget(ArtworkDim oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dimmed == widget.dimmed && oldWidget.amount == widget.amount) return;
    final target = widget.dimmed ? widget.amount : 0.0;
    if (widget.duration == Duration.zero) {
      _controller.value = target;
    } else {
      _controller.animateTo(target, duration: widget.duration, curve: widget.curve);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ArtworkDimScope(dim: _controller, child: widget.child);
}
