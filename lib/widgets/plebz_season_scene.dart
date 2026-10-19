import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/plebz_season.dart';

/// The start screen's seasonal backdrop (fork addition), filling the screen
/// behind the logo: at Halloween a thunderstorm night — a full moon behind
/// passing clouds, bare trees on a hill, a swarm of bats coming out of the
/// moon and now and then a lightning flash; at Christmas a string of lights
/// along the top and light snow. The logo's own trim (the garland's lights,
/// baubles and star) is drawn by `PlebzStartAnimation`.
///
/// Everything moves on one loop of [loop], so nothing jumps when it starts
/// over. With animations switched off it stands still, without flashes.
///
/// At Halloween the start screen leaves with a strike of its own, aimed at
/// the logo: [PlebzSeasonSceneState.strike].
class PlebzSeasonScene extends StatefulWidget {
  const PlebzSeasonScene({super.key, required this.season});

  final PlebzSeason season;

  /// One turn of the scene's clock; every motion fits it a whole number of
  /// times.
  static const Duration loop = Duration(seconds: 48);

  @override
  State<PlebzSeasonScene> createState() => PlebzSeasonSceneState();
}

class PlebzSeasonSceneState extends State<PlebzSeasonScene> with TickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(vsync: this, duration: PlebzSeasonScene.loop);

  /// The farewell strike, its two flashes over [_StormPainter.strikeLength].
  late final AnimationController _farewell = AnimationController(vsync: this, duration: _StormPainter.strikeLength);
  bool _started = false;
  bool _still = false;

  /// How far into the farewell strike the logo starts to go: just past the
  /// first flash, so the second one lights its way out.
  static const Duration farewellLead = Duration(milliseconds: 120);

  /// Lightning strikes the logo (Halloween only), done once the first flash
  /// has lit: the moment for the start screen to step back. Returns at once
  /// at Christmas or with animations switched off.
  Future<void> strike() async {
    if (widget.season != PlebzSeason.halloween || _still || !mounted) return;
    unawaited(_farewell.forward(from: 0));
    await Future<void>.delayed(farewellLead);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _still = still;
    if (still) {
      _clock.stop();
    } else if (!_started) {
      _started = true;
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    _farewell.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final halloween = widget.season == PlebzSeason.halloween;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The night itself never moves: painted once.
          if (halloween) const RepaintBoundary(child: CustomPaint(painter: _NightPainter())),
          RepaintBoundary(
            child: CustomPaint(painter: halloween ? _StormPainter(_clock, _farewell) : _ChristmasPainter(_clock)),
          ),
        ],
      ),
    );
  }
}

/// A fixed pseudo-random number in 0..1 for [i] — the same scene every run.
double _rnd(double i) {
  final s = math.sin(i * 127.1) * 43758.5453;
  return s - s.floorToDouble();
}

double _frac(double v) => v - v.floorToDouble();

/// [cycles] whole turns over the scene's loop at [loop] of the way through it.
double _turns(double loop, num cycles) => 2 * math.pi * cycles * loop;

/// Where the moon stands and how big it is, for [size].
({Offset centre, double radius}) _moon(Size size) {
  final stacked = size.width < size.height;
  return stacked
      ? (centre: Offset(size.width * 0.72, size.height * 0.14), radius: size.height * 0.06)
      : (centre: Offset(size.width * 0.8, size.height * 0.22), radius: size.height * 0.11);
}

void _glow(Canvas canvas, Offset at, double radius, Color colour, double alpha) {
  canvas.drawRect(
    Rect.fromCircle(center: at, radius: radius),
    Paint()
      ..shader = RadialGradient(
        colors: [
          colour.withValues(alpha: alpha),
          colour.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: at, radius: radius)),
  );
}

/// Halloween's still part: the violet night sky, the moon and the trees.
class _NightPainter extends CustomPainter {
  const _NightPainter();

  static const Color _moonColour = Color(0xFFF3E3B0);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final stacked = w < h;
    final all = Offset.zero & size;
    canvas.drawRect(
      all,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1D1033), Color(0xFF0A0612), Color(0xFF040207)],
          stops: [0, 0.7, 1],
        ).createShader(all),
    );

    final moon = _moon(size);
    _glow(canvas, moon.centre, moon.radius * 3.2, _moonColour, 0.16);
    canvas.drawCircle(moon.centre, moon.radius, Paint()..color = _moonColour.withValues(alpha: 0.92));
    final crater = Paint()..color = const Color(0x59968C78);
    for (final (dx, dy, r) in const [(-0.3, -0.2, 0.2), (0.28, 0.15, 0.13), (-0.05, 0.38, 0.1), (0.2, -0.4, 0.08)]) {
      canvas.drawCircle(moon.centre + Offset(dx, dy) * moon.radius, r * moon.radius, crater);
    }

    final unit = size.shortestSide / 270;
    final bark = Paint()
      ..color = Colors.black
      ..strokeCap = StrokeCap.round;
    for (final (x, length, angle, depth, seed) in [
      (stacked ? w * 0.08 : w * 0.07, stacked ? w * 0.17 : h * 0.2, -1.57, 7, 3.0),
      (stacked ? w * 0.95 : w * 0.93, stacked ? w * 0.16 : h * 0.19, -1.62, 7, 9.0),
      if (!stacked) (w * 0.2, h * 0.1, -1.5, 5, 15.0),
    ]) {
      _branch(canvas, bark, Offset(x, h), length, angle, depth, seed, unit);
    }
    canvas.drawPath(
      Path()
        ..moveTo(0, h)
        ..quadraticBezierTo(w * 0.3, h * 0.9, w * 0.55, h * 0.96)
        ..quadraticBezierTo(w * 0.8, h * 0.88, w, h * 0.94)
        ..lineTo(w, h)
        ..close(),
      Paint()..color = Colors.black,
    );
  }

  /// A bare tree: each limb forks into two thinner, shorter ones.
  static void _branch(
    Canvas canvas,
    Paint paint,
    Offset from,
    double length,
    double angle,
    int depth,
    double seed,
    double unit,
  ) {
    if (depth == 0 || length < 1.5 * unit) return;
    final to = from + Offset(math.cos(angle), math.sin(angle)) * length;
    canvas.drawLine(from, to, paint..strokeWidth = math.max(0.6, depth * 1.1) * unit);
    _branch(canvas, paint, to, length * 0.72, angle - 0.45 - _rnd(seed) * 0.3, depth - 1, seed * 1.7 + 1, unit);
    _branch(canvas, paint, to, length * 0.68, angle + 0.4 + _rnd(seed + 3) * 0.35, depth - 1, seed * 2.3 + 2, unit);
  }

  @override
  bool shouldRepaint(_NightPainter old) => false;
}

/// Halloween's moving part: clouds over the moon, the bats, the lightning.
class _StormPainter extends CustomPainter {
  _StormPainter(this.clock, this.farewell) : super(repaint: Listenable.merge([clock, farewell]));

  final Animation<double> clock;

  /// The strike the start screen leaves with, 0 before it.
  final Animation<double> farewell;

  /// Seconds between two strikes; the loop holds a whole number of them.
  static const double _strikeEvery = 6;

  /// How long one strike's flashes last.
  static const Duration strikeLength = Duration(milliseconds: 400);

  /// A strike's light [into] seconds after it began: two quick flashes, the
  /// first brighter.
  static double _flash(double into) =>
      math.max(0.0, 1 - (into - 0.05).abs() / 0.08) + 0.8 * math.max(0.0, 1 - (into - 0.22).abs() / 0.1);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final stacked = w < h;
    final loop = clock.value;
    final seconds = loop * PlebzSeasonScene.loop.inSeconds;
    final moon = _moon(size);

    final cloud = Paint()..color = const Color(0xD9100A1A);
    for (var i = 0; i < 4; i++) {
      final x = (_frac(loop + i * 0.29) * 1.4 - 0.2) * w;
      final y = (stacked ? h * 0.06 : 0) + size.shortestSide * (0.12 + 0.08 * i);
      final thick = size.shortestSide;
      canvas
        ..drawOval(Rect.fromCenter(center: Offset(x, y), width: w * 0.24, height: thick * 0.05), cloud)
        ..drawOval(
          Rect.fromCenter(center: Offset(x + w * 0.05, y - thick * 0.02), width: w * 0.14, height: thick * 0.06),
          cloud,
        );
    }

    // The swarm leaves the moon towards the left, growing as it comes near.
    final batSize = size.shortestSide * (stacked ? 0.04 : 0.033);
    final bats = stacked ? 4 : 7;
    for (var i = 0; i < bats; i++) {
      final u = _frac(loop * (2 + i % 2) + _rnd(i.toDouble()) * 0.9);
      final x = moon.centre.dx - u * (i.isOdd ? 1 : 0.6) * w * 0.9 + math.sin(_turns(loop, 16) + i) * w * 0.017;
      final y = moon.centre.dy + u * h * (0.1 + 0.25 * _rnd(i + 4.0)) - math.sin(u * 3) * h * 0.05;
      _bat(canvas, Offset(x, y), batSize * (0.4 + u * 0.9), math.cos(_turns(loop, 76) + i * 2));
    }

    // A strike: two quick flashes, the bolt seen while they are bright. The
    // farewell's bolt comes down onto the logo.
    final leaving = farewell.value > 0;
    final strike = leaving ? -1 : (seconds + 1.2) ~/ _strikeEvery;
    final flash = leaving
        ? _flash(farewell.value * strikeLength.inMilliseconds / 1000)
        : _flash((seconds + 1.2) % _strikeEvery);
    if (flash <= 0) return;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFD2C8FF).withValues(alpha: 0.32 * flash));
    if (flash > 0.5) {
      var at = leaving
          ? Offset(w * (stacked ? 0.46 : 0.31), 0)
          : Offset(w * (stacked ? 0.3 : 0.18) + _rnd(strike * 3.0) * w * 0.22, 0);
      final bolt = Path()..moveTo(at.dx, at.dy);
      for (var i = 0; i < 7; i++) {
        at += Offset((_rnd(i + 7.0 + strike * 13) - 0.5) * w * 0.08, h * 0.06);
        bolt.lineTo(at.dx, at.dy);
      }
      canvas.drawPath(
        bolt,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.shortestSide * 0.006
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white.withValues(alpha: math.min(1, flash)),
      );
    }
  }

  /// A bat [size] from wing tip to body, its wings at [flap] (-1 down, 1 up).
  static void _bat(Canvas canvas, Offset at, double size, double flap) {
    const outline = [
      (-0.35, -0.35), (-1.0, -0.25), (-0.8, 0.1), (-0.6, 0.0), (-0.42, 0.18), (-0.22, 0.06), (0.0, 0.22), //
      (0.22, 0.06), (0.42, 0.18), (0.6, 0.0), (0.8, 0.1), (1.0, -0.25), (0.35, -0.35),
    ];
    final path = Path()..moveTo(at.dx, at.dy - 0.1 * size);
    for (final (i, (x, y)) in outline.indexed) {
      // Only the leading edge of each wing lifts and falls.
      final lifts = i <= 1 || i >= 11;
      path.lineTo(at.dx + x * size, at.dy + (lifts ? y * flap : y) * size);
    }
    path
      ..close()
      ..addOval(Rect.fromCenter(center: at, width: 0.24 * size, height: 0.4 * size));
    canvas.drawPath(path, Paint()..color = Colors.black);
  }

  @override
  bool shouldRepaint(_StormPainter old) => old.clock != clock || old.farewell != farewell;
}

/// Christmas: a string of lights along the top and light snow.
class _ChristmasPainter extends CustomPainter {
  _ChristmasPainter(this.clock) : super(repaint: clock);

  final Animation<double> clock;

  static const List<Color> _bulbs = [Color(0xFFE0393E), Color(0xFFF4C05A), Color(0xFF3FAE5A), Color(0xFF4C8DF0)];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final stacked = w < h;
    final loop = clock.value;
    final unit = size.shortestSide / 270;

    // The wire sags between hooks, a bulb hangs from it every so often.
    final segments = stacked ? 2 : 4;
    final wire = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = unit
      ..color = const Color(0xB35A6E5A);
    final top = h * 0.02, sag = h * (stacked ? 0.035 : 0.06);
    final bulbRadius = size.shortestSide * 0.01;
    for (var k = 0; k < segments; k++) {
      final a = k * w / segments, b = (k + 1) * w / segments;
      canvas.drawPath(
        Path()
          ..moveTo(a, top)
          ..quadraticBezierTo((a + b) / 2, top + sag * 2, b, top),
        wire,
      );
      for (var j = 1; j < 6; j++) {
        final u = j / 6;
        final at = Offset(a + (b - a) * u, top + 4 * sag * u * (1 - u) + bulbRadius);
        final colour = _bulbs[(k * 5 + j) % 4];
        final shine = 0.55 + 0.45 * math.sin(_turns(loop, 20) + k * 1.7 + j * 2.3);
        _glow(canvas, at, bulbRadius * 5, colour, 0.5 * shine);
        canvas.drawOval(
          Rect.fromCenter(center: at, width: bulbRadius * 1.4, height: bulbRadius * 2),
          Paint()..color = colour.withValues(alpha: 0.5 + 0.5 * shine),
        );
      }
    }

    final flakes = stacked ? 30 : 60;
    final flake = Paint();
    for (var i = 0; i < flakes; i++) {
      final near = i % 3 == 0;
      final speed = (near ? 7 : 3) + (_rnd(i.toDouble()) * 4).floor();
      final u = _frac(loop * speed + _rnd(i + 11.0));
      final x = _rnd(i + 30.0) * w + math.sin(_turns(loop, 6) + i) * 8 * unit;
      final y = u * h * 1.05 - 5 * unit;
      flake.color = Colors.white.withValues(alpha: (near ? 0.75 : 0.35) + _rnd(i + 4.0) * 0.25);
      canvas.drawCircle(Offset(x, y), ((near ? 1.6 : 0.6) + _rnd(i + 6.0) * 1.2) * unit, flake);
    }
  }

  @override
  bool shouldRepaint(_ChristmasPainter old) => old.clock != clock;
}
