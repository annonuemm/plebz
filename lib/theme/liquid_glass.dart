import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../services/device_performance.dart';

/// "Liquid Glass" under "Redesign – Glas", when the viewer has switched it on
/// (`PlebzPrefs.glasLiquid`, fork option).
///
/// The plain glass only tints what lies behind it: a ground at part strength,
/// a sheen and a lit edge — three alpha layers, which cost nothing. Apple's
/// glass, since iOS 26, is a slab you look through: the picture behind it
/// blurred and its colour lifted, and at the rim bent inward, as through a
/// rounded edge, with a bevel that catches the light. That is what this gives
/// the menus and the side rail, Apple's "regular" glass for surfaces with
/// words on them, and a focused poster, whose artwork takes on a glass rim in
/// place of the focus ring, as tvOS gives an image Liquid Glass when it gains
/// focus (the user's calls, 2026-10-13). The bands with the gliding capsule —
/// tabs, filter and sort, the detail pages' buttons — go flat instead, as
/// Apple's plain buttons: a faint track and a white focus. Everything else
/// stays plain glass.
///
/// The bend is a fragment shader over the backdrop (`shaders/liquid_glass.frag`),
/// which only Impeller runs; where it does not load, the blur stands alone.
///
/// The cost is the blur and the lens: redrawn every frame for as long as the
/// pane is up. So it is off by default, never on the reduced tier, whatever
/// the switch says, and only on Apple's devices ([offeredHere]).
abstract final class OckerLiquidGlass {
  /// The viewer's switch; the theme provider keeps it in step with the pref.
  static final ValueNotifier<bool> setting = ValueNotifier(false);

  /// The viewer's switch for the fake glass where Liquid Glass is not offered
  /// (Android; `PlebzPrefs.glasFakeGlass`), kept in step by the theme
  /// provider: off, the glass that stands in for the lens is flat instead.
  static final ValueNotifier<bool> fakeGlass = ValueNotifier(true);

  /// Either switch: what the panes and capsules listen to.
  static final Listenable changes = Listenable.merge([setting, fakeGlass]);

  /// Where it is offered at all: the Apple builds only — Apple TV, the Mac,
  /// and iPhone and iPad once there is a build for them (the user's call,
  /// 2026-10-13). The APK never shows it; a backup carrying the switch from a
  /// Mac does nothing on Android. The tvOS engine reports itself as iOS.
  static bool get offeredHere => debugOfferedHere ?? (Platform.isIOS || Platform.isMacOS);

  @visibleForTesting
  static bool? debugOfferedHere;

  /// Whether the switch belongs on this device's settings: an Apple build, and
  /// not the reduced tier, where it never runs.
  static bool get offerable => offeredHere && !DevicePerformance.isReduced;

  /// Whether glass is liquid right now.
  static bool get active => setting.value && offerable;

  /// Whether Glas wears Liquid Glass's look (Plebz, the user's call,
  /// 2026-10-13): the navigation, the menus and the capsules as glass, the
  /// bands' words as Apple's flat buttons. While the lens runs, and always
  /// where it is not offered at all — on Android, where the fake glass (a
  /// sheen and a lit edge, no blur) stands in for the lens for good. On
  /// Apple's builds with Liquid Glass off, the same shapes are flat instead.
  static bool get look => active || (!offeredHere && fakeGlass.value);

  /// How much of a pane's ground stays when it is liquid: the blur now does
  /// some of what the ground did, keeping words readable over a busy picture.
  static const groundFactor = 0.4;

  /// A pane's ground at [opacity], thinned when [liquid].
  static double ground(double opacity, {required bool liquid}) => liquid ? opacity * groundFactor : opacity;

  /// Blur, then colour lifted: the saturation Apple's glass adds, so a blurred
  /// poster stays a colour rather than turning to grey.
  static final ui.ImageFilter blur = ui.ImageFilter.compose(
    outer: const ui.ColorFilter.matrix(_saturate),
    inner: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
  );

  // Saturation 1.4 on Rec. 709 luminance.
  static const _saturate = <double>[
    1.3149, -0.2860, -0.0289, 0, 0, //
    -0.0851, 1.1140, -0.0289, 0, 0,
    -0.0851, -0.2860, 1.3711, 0, 0,
    0, 0, 0, 1, 0,
  ];

  /// The lens shader, once loaded; null where it cannot run (not Impeller,
  /// not an Apple build, not loaded yet), and the blur stands alone.
  static final ValueNotifier<ui.FragmentProgram?> lens = ValueNotifier(null);

  static bool _loading = false;

  /// Loads [lens] once, where it can run.
  static Future<void> loadLens() async {
    if (_loading || !offeredHere || !ui.ImageFilter.isShaderFilterSupported) return;
    _loading = true;
    try {
      lens.value = await ui.FragmentProgram.fromAsset('shaders/liquid_glass.frag');
    } catch (error) {
      debugPrint('Liquid glass: the lens shader did not load: $error');
    }
  }

  /// The lens, in logical pixels of the pane: how far in from the rim the
  /// bevel reaches, how far the picture bends at the rim, and how far its
  /// colours part, as a share of the bend.
  static const lensThickness = 28.0;
  static const lensStrength = 20.0;
  static const lensDispersion = 0.12;

  /// How soft the picture turns past the bevel, in logical pixels.
  static const lensFrost = 16.0;

  /// The focus bubble on a detail page's buttons: clear glass, no frost, what
  /// lies behind bending at its rim.
  static const bubbleThickness = 10.0;
  static const bubbleStrength = 7.0;

  /// A focused poster's rim: its own artwork bends there, as under the bevel
  /// of a slab of glass — tvOS gives an image Liquid Glass when it gains focus.
  static const rimThickness = 14.0;
  static const rimStrength = 6.0;
}

/// A pane of glass the switch reaches: [builder] draws it, told whether the
/// glass is liquid, and while it is the pane lies over the blurred picture
/// behind [shape], bent at its rim where the lens runs. [radius] is the
/// shape's corner, which the lens follows. Rebuilt when the switch turns.
class OckerLiquidBackdrop extends StatelessWidget {
  const OckerLiquidBackdrop({
    super.key,
    required this.shape,
    required this.radius,
    required this.builder,
    this.thickness = OckerLiquidGlass.lensThickness,
    this.strength = OckerLiquidGlass.lensStrength,
    this.frost = OckerLiquidGlass.lensFrost,
    this.lensBeyond = EdgeInsets.zero,
  });

  final ShapeBorder shape;
  final double radius;
  final Widget Function(BuildContext context, bool liquid) builder;

  /// The lens in logical pixels: the bevel's reach, the bend at the rim, and
  /// the frost past the bevel. A pane's by default; a band passes its own.
  final double thickness;
  final double strength;
  final double frost;

  /// How far the lens's own shape reaches past the box, in logical pixels:
  /// a pane flush with the screen's edge has its rim only on the open side,
  /// so the lens takes it as running on past the edges it meets.
  final EdgeInsets lensBeyond;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([OckerLiquidGlass.changes, OckerLiquidGlass.lens]),
    builder: (context, _) {
      final liquid = OckerLiquidGlass.active;
      final pane = builder(context, liquid);
      if (!liquid) return pane;
      final program = OckerLiquidGlass.lens.value;
      return ClipPath(
        clipper: ShapeBorderClipper(shape: shape, textDirection: Directionality.maybeOf(context)),
        // The lens frosts the picture itself, sharp at the rim and soft past
        // it. Where it cannot run (the Mac draws without Impeller) the plain
        // blur stands in — but only for a pane that frosts: a rim or a bubble
        // has no frost, and a blur there hid the whole poster under it.
        child: program == null
            ? (frost > 0 ? BackdropFilter(filter: OckerLiquidGlass.blur, child: pane) : pane)
            : _OckerLens(
                program: program,
                lens: (radius: radius, thickness: thickness, strength: strength, frost: frost, beyond: lensBeyond),
                devicePixelRatio: View.of(context).devicePixelRatio,
                child: pane,
              ),
      );
    },
  );
}

/// The lens as a backdrop filter over its child's box.
///
/// The shader works in the screen's physical pixels, so the pane tells it
/// where it is. A pane can move without painting again — a sheet sliding in
/// moves its layer, not its pixels — so after every frame the box checks
/// where it now lies and repaints if that changed.
/// A lens in logical pixels: the shape's corner, the bevel's reach, the bend
/// at the rim and the frost past the bevel.
typedef _LensSpec = ({double radius, double thickness, double strength, double frost, EdgeInsets beyond});

class _OckerLens extends SingleChildRenderObjectWidget {
  const _OckerLens({required this.program, required this.lens, required this.devicePixelRatio, super.child});

  final ui.FragmentProgram program;
  final _LensSpec lens;
  final double devicePixelRatio;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderOckerLens(program, lens, devicePixelRatio);

  @override
  void updateRenderObject(BuildContext context, _RenderOckerLens renderObject) => renderObject
    ..program = program
    ..lens = lens
    ..devicePixelRatio = devicePixelRatio;
}

class _RenderOckerLens extends RenderProxyBox {
  _RenderOckerLens(this._program, this._lens, this._devicePixelRatio);

  ui.FragmentProgram _program;
  set program(ui.FragmentProgram value) {
    if (identical(value, _program)) return;
    _program = value;
    _shader?.dispose();
    _shader = null;
    markNeedsPaint();
  }

  _LensSpec _lens;
  set lens(_LensSpec value) {
    if (value == _lens) return;
    _lens = value;
    markNeedsPaint();
  }

  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  ui.FragmentShader? _shader;
  Rect? _painted;
  bool _watching = false;

  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  BackdropFilterLayer? get layer => super.layer as BackdropFilterLayer?;

  /// The box on the screen, in physical pixels.
  Rect _onScreen() {
    final r = MatrixUtils.transformRect(getTransformTo(null), Offset.zero & size);
    final k = _devicePixelRatio;
    return Rect.fromLTRB(r.left * k, r.top * k, r.right * k, r.bottom * k);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    if (_watching) return;
    _watching = true;
    SchedulerBinding.instance.addPostFrameCallback(_check);
  }

  @override
  void detach() {
    _watching = false;
    super.detach();
  }

  @override
  void dispose() {
    _shader?.dispose();
    _shader = null;
    super.dispose();
  }

  void _check(Duration _) {
    if (!_watching) return;
    if (attached && hasSize && _painted != null && _onScreen() != _painted) markNeedsPaint();
    SchedulerBinding.instance.addPostFrameCallback(_check);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null || size.isEmpty) {
      layer = null;
      return;
    }
    final box = _onScreen();
    _painted = box;
    // Physical pixels per logical pixel of this box: the device's, and any
    // scale on the way (the Apple TV draws its surface at twice the size).
    final scale = box.width / size.width;
    final beyond = _lens.beyond * scale;
    final rect = Rect.fromLTRB(
      box.left - beyond.left,
      box.top - beyond.top,
      box.right + beyond.right,
      box.bottom + beyond.bottom,
    );
    final shader = _shader ??= _program.fragmentShader();
    shader
      // 0 and 1 are the texture's size, which the engine sets.
      ..setFloat(2, rect.left)
      ..setFloat(3, rect.top)
      ..setFloat(4, rect.width)
      ..setFloat(5, rect.height)
      ..setFloat(6, _lens.radius * scale)
      ..setFloat(7, _lens.thickness * scale)
      ..setFloat(8, _lens.strength * scale)
      ..setFloat(9, OckerLiquidGlass.lensDispersion)
      ..setFloat(10, _lens.frost * scale);
    final filterLayer = layer ??= BackdropFilterLayer();
    filterLayer.filter = ui.ImageFilter.shader(shader);
    context.pushLayer(filterLayer, super.paint, offset);
  }
}
