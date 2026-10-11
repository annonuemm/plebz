import 'package:flutter/material.dart';

import '../theme/mono_tokens.dart';
import '../utils/platform_detector.dart';
import 'ocker_skin.dart';

/// A strip of the page's ground behind the status bar (Plebz), for a page
/// whose bar floats away as it scrolls: once the bar has gone, the rows ran
/// on under the clock and the status icons. The strip fades in over the
/// first stretch of the scroll, so at the top the page's ground shows through
/// as before. The user's pick of two (2026-10-11); the other kept the bar on
/// screen for good.
///
/// Only under the redesign on a phone or tablet — the looks whose bars are
/// clear over the ground. A television has no status bar, and the original
/// look is left as it was.
class OckerStatusBarGround extends StatefulWidget {
  const OckerStatusBarGround({super.key, required this.child});

  final Widget child;

  /// How far the page scrolls before the strip is fully there.
  static const double fadeDistance = 80;

  @override
  State<OckerStatusBarGround> createState() => _OckerStatusBarGroundState();
}

class _OckerStatusBarGroundState extends State<OckerStatusBarGround> {
  double _cover = 0;

  bool _onScroll(ScrollNotification notification) {
    // The page's own scroll, and the one a nested scroll view hands its body:
    // rows that scroll sideways are not the page moving under the clock.
    if (notification.depth > 1 || notification.metrics.axis != Axis.vertical) return false;
    final cover = (notification.metrics.pixels / OckerStatusBarGround.fadeDistance).clamp(0.0, 1.0);
    if (cover != _cover) setState(() => _cover = cover);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final statusBar = MediaQuery.paddingOf(context).top;
    if (statusBar <= 0 || PlatformDetector.isTV() || !isOcker(context)) return widget.child;
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Stack(
        children: [
          widget.child,
          if (_cover > 0)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: statusBar,
              child: IgnorePointer(
                child: ColoredBox(color: tokens(context).bg.withValues(alpha: _cover)),
              ),
            ),
        ],
      ),
    );
  }
}
