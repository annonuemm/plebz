import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/settings_service.dart' show GlasAccent;
import '../theme/mono_theme.dart' show glasPalette;
import '../theme/mono_tokens.dart';
import '../utils/plebz_season.dart';

/// The logo's own colours, violet to pink.
const List<Color> plebzLogoColours = [Color(0xFF7356F5), Color(0xFFA866EE), Color(0xFFEE8BD2)];

/// The mark's colours in the theme of [context]: Glas draws it in its accent —
/// a little darker at the stem's top, lighter towards the open end, as the
/// logo turns from violet to pink. The Plebz palette, and the original look,
/// whose accent is only its ink, keep the logo's own.
List<Color> plebzMarkColours(BuildContext context) {
  final tk = Theme.of(context).extension<MonoTokens>();
  if (tk == null || !tk.glass || tk.accent == glasPalette(GlasAccent.plebz).accent) return plebzLogoColours;
  final hsl = HSLColor.fromColor(tk.accent);
  HSLColor shifted(double hue, double lightness) =>
      hsl.withHue((hsl.hue + hue) % 360).withLightness((hsl.lightness + lightness).clamp(0.0, 1.0));
  return [shifted(-12, -0.12).toColor(), tk.accent, shifted(18, 0.12).toColor()];
}

/// The start screen's logo (fork addition): the mark draws itself the way a
/// pen would — up the stem, round the point, down to the open end — lands with
/// a bloom of light, and "Plebz" slides out from behind it. While the servers
/// connect a sheen runs along the stroke and the glow breathes; [PlebzStartAnimationState.leave]
/// steps it back when the app comes in.
///
/// The mark's geometry and colours are the ones `scripts/brand/make_brand_assets.py`
/// draws every icon from.
class PlebzStartAnimation extends StatefulWidget {
  const PlebzStartAnimation({
    super.key,
    required this.markHeight,
    this.stacked = false,
    this.colours = plebzLogoColours,
    this.season,
  });

  /// How tall the mark is drawn.
  final double markHeight;

  /// The name under the mark rather than beside it — portrait screens.
  final bool stacked;

  /// The mark's gradient, three stops; see [plebzMarkColours]. The name is
  /// always white.
  final List<Color> colours;

  /// The season the logo dresses up for, or null: it then takes the season's
  /// colours over [colours] and glow, and at Christmas wears the garland's
  /// lights, baubles and star. The scene behind it is `PlebzSeasonScene`.
  final PlebzSeason? season;

  /// "Plebz" from cap top to baseline, for a mark [markHeight] tall.
  static double textHeightFor(double markHeight) => markHeight / 1.42;

  /// How tall the whole logo stands.
  static double heightFor(double markHeight, {required bool stacked}) {
    if (!stacked) return markHeight;
    final text = textHeightFor(markHeight);
    return markHeight + text * _stackedGap + text;
  }

  static const double _sideGap = 0.61;
  static const double _stackedGap = 0.6;

  @override
  State<PlebzStartAnimation> createState() => PlebzStartAnimationState();
}

class PlebzStartAnimationState extends State<PlebzStartAnimation> with TickerProviderStateMixin {
  static const Duration introDuration = Duration(milliseconds: 2100);
  static const Duration leaveDuration = Duration(milliseconds: 450);

  late final AnimationController _intro = AnimationController(vsync: this, duration: introDuration);
  late final AnimationController _sheen = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  );
  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  late final AnimationController _leave = AnimationController(vsync: this, duration: leaveDuration);

  /// The garland's twinkle, one loop of [_MarkPainter.garlandLoop].
  late final AnimationController _garland = AnimationController(vsync: this, duration: _MarkPainter.garlandLoop);
  final Completer<void> _introDone = Completer<void>();
  bool _started = false;
  bool _still = false;

  /// Done once the mark is drawn and the name is out.
  Future<void> get introDone => _introDone.future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_still) {
      _intro.value = 1;
      _introDone.complete();
      return;
    }
    _intro.forward().whenCompleteOrCancel(() {
      if (!_introDone.isCompleted) _introDone.complete();
      if (!mounted || _leave.value > 0) return;
      unawaited(_sheen.repeat());
      unawaited(_breathe.repeat(reverse: true));
      if (widget.season == PlebzSeason.christmas) unawaited(_garland.repeat());
    });
  }

  /// Steps the logo back: it grows a little and fades, with its glow.
  Future<void> leave() async {
    if (_still || !mounted) return;
    _sheen.stop();
    _breathe.stop();
    _garland.stop();
    try {
      await _leave.forward().orCancel;
    } on TickerCanceled {
      // Disposed on the way out; nothing left to wait for.
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _sheen.dispose();
    _breathe.dispose();
    _leave.dispose();
    _garland.dispose();
    super.dispose();
  }

  /// [t]'s progress through the part of the intro from [startMs] to [endMs].
  static double _phase(double t, int startMs, int endMs) {
    final total = introDuration.inMilliseconds;
    return ((t * total - startMs) / (endMs - startMs)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final markHeight = widget.markHeight;
    final textHeight = PlebzStartAnimation.textHeightFor(markHeight);
    final season = widget.season;
    final colours = season?.markColours ?? widget.colours;
    final glowColour = season?.glowColour ?? colours[1];
    return AnimatedBuilder(
      animation: Listenable.merge([_intro, _sheen, _breathe, _leave, _garland]),
      builder: (context, _) {
        final t = _intro.value;
        final drawn = Curves.easeInOutCubic.transform(_phase(t, 150, 1200));
        final land = math.sin(math.pi * Curves.easeOut.transform(_phase(t, 1120, 1670)));
        final word = Curves.easeOutCubic.transform(_phase(t, 1400, 2100));
        final leave = Curves.easeIn.transform(_leave.value);

        // The glow blooms as the mark lands, settles, then breathes while
        // the servers connect.
        final bloom = _phase(t, 1100, 2100);
        var glowOpacity = bloom < 0.35 ? bloom / 0.35 : 1 - 0.45 * (bloom - 0.35) / 0.65;
        var glowScale = bloom < 0.35 ? 0.5 + 0.55 * bloom / 0.35 : 1.05 - 0.1 * (bloom - 0.35) / 0.65;
        if (_breathe.isAnimating) {
          final b = Curves.easeInOut.transform(_breathe.value);
          glowOpacity = 0.4 + 0.35 * b;
          glowScale = 0.9 + 0.12 * b;
        }
        glowOpacity *= 1 - leave;
        glowScale *= 1 + 0.4 * leave;

        final mark = Transform.scale(
          scale: 1 + 0.08 * land,
          child: SizedBox(
            width: markHeight * _MarkPainter.viewBox.width / _MarkPainter.viewBox.height,
            height: markHeight,
            child: CustomPaint(
              painter: _MarkPainter(
                drawn: drawn,
                sheen: _sheen.isAnimating ? _sheen.value : null,
                colours: colours,
                garland: season == PlebzSeason.christmas
                    ? (shown: Curves.easeOut.transform(_phase(t, 1300, 2100)), loop: _garland.value)
                    : null,
              ),
            ),
          ),
        );
        final name = Image.asset('assets/plebz_wordmark.png', height: textHeight, filterQuality: FilterQuality.medium);
        final Widget lockup;
        if (widget.stacked) {
          lockup = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              mark,
              SizedBox(height: textHeight * PlebzStartAnimation._stackedGap),
              Opacity(
                opacity: word,
                child: Transform.translate(offset: Offset(0, (1 - word) * textHeight * 0.4), child: name),
              ),
            ],
          );
        } else {
          lockup = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              mark,
              ClipRect(
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: word,
                  child: Opacity(
                    opacity: word,
                    child: Padding(
                      padding: EdgeInsets.only(left: textHeight * PlebzStartAnimation._sideGap),
                      child: name,
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        final glowSize = markHeight * 3.4;
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: OverflowBox(
                  minWidth: glowSize,
                  maxWidth: glowSize,
                  minHeight: glowSize,
                  maxHeight: glowSize,
                  child: Opacity(
                    opacity: glowOpacity.clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: glowScale,
                      child: Container(
                        width: glowSize,
                        height: glowSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [glowColour.withValues(alpha: 0.3), glowColour.withValues(alpha: 0)],
                            stops: const [0, 0.62],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Opacity(
              opacity: 1 - leave,
              child: Transform.scale(scale: 1 + 0.12 * leave, child: lockup),
            ),
          ],
        );
      },
    );
  }
}

/// The mark at rest, [height] tall — the anchor at the top of "Flach"'s
/// navigation (Plebz).
class PlebzMark extends StatelessWidget {
  const PlebzMark({super.key, required this.height, this.colours = plebzLogoColours});

  final double height;
  final List<Color> colours;

  /// How wide the mark stands at [height].
  static double widthFor(double height) => height * _MarkPainter.viewBox.width / _MarkPainter.viewBox.height;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(widthFor(height), height),
    painter: _MarkPainter(drawn: 1, colours: colours),
  );
}

/// The mark with "Plebz" beside it, the name shown to [name] of the way —
/// the open navigation's head, laid out as the start screen sets the two.
class PlebzLockup extends StatelessWidget {
  const PlebzLockup({super.key, required this.markHeight, this.colours = plebzLogoColours, this.name = 1});

  final double markHeight;
  final List<Color> colours;

  /// 0 for the mark alone, 1 for the name in full.
  final double name;

  @override
  Widget build(BuildContext context) {
    final textHeight = PlebzStartAnimation.textHeightFor(markHeight);
    final shown = name.clamp(0.0, 1.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PlebzMark(height: markHeight, colours: colours),
        if (shown > 0)
          ClipRect(
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: shown,
              child: Opacity(
                opacity: shown,
                child: Padding(
                  padding: EdgeInsets.only(left: textHeight * PlebzStartAnimation._sideGap),
                  child: Image.asset(
                    'assets/plebz_wordmark.png',
                    height: textHeight,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The mark, drawn up to [drawn] of its stroke, with a sheen at [sheen] of
/// its run when one is passing.
class _MarkPainter extends CustomPainter {
  _MarkPainter({required this.drawn, this.sheen, required this.colours, this.garland});

  final double drawn;
  final List<Color> colours;
  final double? sheen;

  /// Christmas's garland, [shown] of the way in, its twinkle at [loop] of
  /// [garlandLoop]; null for none.
  final ({double shown, double loop})? garland;

  /// One turn of the garland's twinkle; every motion in it fits a whole
  /// number of times.
  static const Duration garlandLoop = Duration(seconds: 6);

  static const Rect viewBox = Rect.fromLTWH(-15, -15, 119, 134);
  static const double _stroke = 27;
  static const List<double> _stops = [0, 0.55, 1];

  static final Path _path = Path()
    ..moveTo(0, 104)
    ..lineTo(0, 11)
    ..quadraticBezierTo(0, 0, 9.62, 5.34)
    ..lineTo(80.38, 44.66)
    ..quadraticBezierTo(90, 50, 80.94, 56.25)
    ..lineTo(32, 90);
  static final ui.PathMetric _metric = _path.computeMetrics().first;

  /// How much of the run the sheen covers.
  static const double _sheenLength = 0.14;

  @override
  void paint(Canvas canvas, Size size) {
    if (drawn <= 0) return;
    final scale = size.height / viewBox.height;
    canvas
      ..save()
      ..scale(scale)
      ..translate(-viewBox.left, -viewBox.top);
    final length = _metric.length;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..shader = ui.Gradient.linear(const Offset(0, 3.6), const Offset(85.34, 104), colours, _stops);
    canvas.drawPath(drawn >= 1 ? _path : _metric.extractPath(0, length * drawn), stroke);
    final trim = garland;
    if (trim != null && trim.shown > 0) _paintGarland(canvas, trim.shown, trim.loop);

    final at = sheen;
    if (at != null) {
      // Runs from just before the stem's foot to just past the open end.
      final start = (at * (1 + _sheenLength) - _sheenLength) * length;
      final from = math.max(0.0, start);
      final to = math.min(length, start + _sheenLength * length);
      if (to > from) {
        canvas.drawPath(
          _metric.extractPath(from, to),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 15
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = const Color(0x8CFFFFFF)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2),
        );
      }
    }
    canvas.restore();
  }

  static const List<Color> _bulbColours = [Color(0xFFFFD25A), Color(0xFFFFFFFF), Color(0xFF7FD18B), Color(0xFF5AB0FF)];
  static const Color _gold = Color(0xFFF4C05A);
  static const Color _silver = Color(0xFFF2F2F2);
  static const Color _starColour = Color(0xFFFFD25A);

  /// Where the baubles hang from, in the mark's own units: under the run
  /// down to the open end, and off the stem's outer side.
  static const List<(double, double, Color)> _baubles = [
    (40, 82, _gold),
    (56, 71, _silver),
    (72, 60, _gold),
    (-14, 40, _silver),
    (-14, 78, _gold),
  ];

  /// The garland: lights along the stroke, baubles under it and a star at
  /// the point, [shown] of the way in.
  void _paintGarland(Canvas canvas, double shown, double loop) {
    double turn(int cycles) => 2 * math.pi * cycles * loop;
    final length = _metric.length;
    for (var i = 0; i <= 16; i++) {
      final at = _metric.getTangentForOffset(length * (0.03 + 0.94 * i / 16))!.position;
      final colour = _bulbColours[i % 4];
      final shine = 0.45 + 0.55 * math.sin(turn(2) + i * 1.3).abs();
      _glowAt(canvas, at, 11, colour, 0.7 * shine * shown);
      canvas.drawCircle(at, 2.6, Paint()..color = colour.withValues(alpha: (0.6 + 0.4 * shine) * shown));
    }
    for (final (i, (x, y, colour)) in _baubles.indexed) {
      final thread = 10.0 + (i.isOdd ? 4 : 0);
      canvas
        ..save()
        ..translate(x, y)
        ..rotate(math.sin(turn(2) + i) * 0.12)
        ..drawLine(
          Offset.zero,
          Offset(0, thread),
          Paint()
            ..strokeWidth = 1
            ..color = const Color(0xFFFFE6A0).withValues(alpha: 0.7 * shown),
        )
        ..drawCircle(Offset(0, thread + 5.5), 6, Paint()..color = colour.withValues(alpha: shown))
        ..drawCircle(Offset(-2, thread + 3.5), 1.6, Paint()..color = Colors.white.withValues(alpha: 0.6 * shown))
        ..restore();
    }
    const star = Offset(104, 50);
    _glowAt(canvas, star, 34, _starColour, (0.55 + 0.2 * math.sin(turn(1))) * shown);
    final points = Path();
    final rotation = math.sin(turn(1)) * 0.08;
    for (var i = 0; i < 10; i++) {
      final angle = rotation + i * math.pi / 5;
      final radius = i.isOdd ? 14 * 0.45 : 14.0;
      final point = star + Offset(math.cos(angle), math.sin(angle)) * radius;
      i == 0 ? points.moveTo(point.dx, point.dy) : points.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(points..close(), Paint()..color = _starColour.withValues(alpha: shown));
  }

  static void _glowAt(Canvas canvas, Offset at, double radius, Color colour, double alpha) {
    final box = Rect.fromCircle(center: at, radius: radius);
    canvas.drawRect(
      box,
      Paint()
        ..shader = RadialGradient(
          colors: [
            colour.withValues(alpha: alpha),
            colour.withValues(alpha: 0),
          ],
        ).createShader(box),
    );
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.drawn != drawn || old.sheen != sheen || old.colours != colours || old.garland != garland;
}
