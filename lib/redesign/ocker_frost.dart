import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../services/settings_service.dart';
import '../utils/app_logger.dart';
import 'ocker_skin.dart';

/// "Glas – v2" (Plebz): whether the panes and the play button are frosted,
/// a switch of its own: real blur asks more of a weak box than plain glass.
/// The television arrangement alone, the one place the switch is offered.
bool ockerFrost(BuildContext context) =>
    ockerGlasV2(context) && isOckerLayout(context) && SettingsService.instance.read(PlebzPrefs.glasV2Frost);

/// How long a pane takes to open: [usual], and under Milchglas a glide of its
/// own where the reduced tier has none. A dimmed page and a frosted pane
/// arriving in one frame read as a hard cut (the user's report), and all that
/// moves is one small picture.
Duration ockerFrostGlide(BuildContext context, Duration usual) =>
    usual == Duration.zero && ockerFrost(context) ? const Duration(milliseconds: 180) : usual;

/// How much ink lies on a frosted button, the page showing through the rest.
const ockerFrostButtonTint = 0.07;

/// What the frosted panes above it take their picture of.
class OckerFrostSource extends SingleChildRenderObjectWidget {
  const OckerFrostSource({super.key, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFrostSource();
}

class _RenderFrostSource extends RenderRepaintBoundary {}

/// The page behind [OckerFrostSource], blurred once, as it was last painted:
/// a small picture, taken before a pane opens and shown as it stands. Nothing
/// is blurred frame by frame, and the page holds still behind an open pane.
/// A video on its own plane is not in the picture.
///
/// Not awaited: the raster thread draws it ahead of the frame that shows it,
/// so a pane is frosted from its first frame. A picture that came in after
/// the pane read as a hard step from plain ground to frost (the user's
/// report).
ui.Image? ockerFrostPicture(BuildContext context) {
  const width = 384.0;
  const sigma = 5.0;
  final source = context.findAncestorRenderObjectOfType<_RenderFrostSource>();
  if (source == null || !source.attached || source.size.isEmpty) return null;
  try {
    final small = source.toImageSync(pixelRatio: width / source.size.width);
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImage(
      small,
      Offset.zero,
      Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp),
    );
    final picture = recorder.endRecording();
    final blurred = picture.toImageSync(small.width, small.height);
    picture.dispose();
    small.dispose();
    return blurred;
  } catch (error) {
    appLogger.d('Frost: no picture of the page', error: error);
    return null;
  }
}

/// The picture of a pane, held by whatever opens the pane.
///
/// [take] has to come before the pane is painted: a rail that opens without a
/// glide (the reduced tier) would otherwise be in its own picture, and show
/// nothing but its own ground.
class OckerFrostShot {
  ui.Image? _image;

  ui.Image? get image => _image;

  void take(BuildContext context) {
    _drop();
    _image = ockerFrostPicture(context);
  }

  /// Once no painter holds it: a disposed picture draws nothing.
  void _drop() {
    final old = _image;
    _image = null;
    if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  void dispose() => _drop();
}

/// A live blur of what lies behind [child], in [shape] and washed with [tint].
/// For what is small or stands over a still picture: it runs on every frame
/// the screen is drawn. Nothing behind it to blur inside a faded layer, so a
/// row must not dim it ([FocusableAction.staysLit]).
class OckerFrostBlur extends StatelessWidget {
  const OckerFrostBlur({super.key, required this.shape, required this.tint, required this.child});

  final ShapeBorder shape;
  final Color tint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: ClipPath(
            clipper: ShapeBorderClipper(shape: shape),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: DecoratedBox(
                decoration: ShapeDecoration(color: tint, shape: shape),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// A pane of frosted glass: [ground], [picture] over it, and a veil of
/// [ground] for what stands on the pane. Plain ground with no picture.
class OckerFrostPane extends StatelessWidget {
  const OckerFrostPane({super.key, required this.ground, required this.picture, this.veil = 0.5, this.child});

  final Color ground;
  final ui.Image? picture;

  /// How much of [ground] lies over the picture.
  final double veil;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: ground),
        CustomPaint(painter: _FrostPainter(picture, context)),
        ColoredBox(color: ground.withValues(alpha: veil)),
        ?child,
      ],
    );
  }
}

/// The part of the picture that lies behind the pane, so the pane reads as
/// glass over the page however far it has opened.
class _FrostPainter extends CustomPainter {
  _FrostPainter(this.picture, this.pane);

  final ui.Image? picture;
  final BuildContext pane;

  @override
  void paint(Canvas canvas, Size size) {
    final picture = this.picture;
    final box = pane.findRenderObject();
    final source = pane.findAncestorRenderObjectOfType<_RenderFrostSource>();
    if (picture == null || box is! RenderBox || source == null) return;
    final bounds = Offset.zero & Size(picture.width.toDouble(), picture.height.toDouble());
    final share = picture.width / source.size.width;
    final behind = box.localToGlobal(Offset.zero, ancestor: source) & size;
    final src = Rect.fromLTRB(behind.left * share, behind.top * share, behind.right * share, behind.bottom * share);
    final shown = src.intersect(bounds);
    if (shown.isEmpty) return;
    final dst = Rect.fromLTRB(
      (shown.left - src.left) / share,
      (shown.top - src.top) / share,
      (shown.right - src.left) / share,
      (shown.bottom - src.top) / share,
    );
    canvas.drawImageRect(picture, shown, dst, Paint()..filterQuality = FilterQuality.low);
  }

  @override
  bool shouldRepaint(_FrostPainter oldDelegate) => oldDelegate.picture != picture;
}
