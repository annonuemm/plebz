import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/device_performance.dart';
import '../services/settings_service.dart';
import '../media/media_item.dart';
import '../media/media_server_client.dart';

import '../theme/mono_theme.dart' show ockerDisplayFontFamily;
import '../theme/mono_tokens.dart';
import '../utils/layout_constants.dart';
import '../utils/platform_detector.dart';
import '../widgets/artwork_dim_scope.dart';
import '../widgets/tv_browse_rail.dart' show TvBrowseRailLayout;

/// Who to ask for a given item's artwork.
typedef OckerClientResolver = MediaServerClient? Function(MediaItem? item);

/// Where the header's first word starts — and therefore where anything that
/// must line up under it starts.
///
/// Not one of the [OckerLayout] numbers: this is the app's own television
/// inset, the one the spotlight's words and the first poster of every rail
/// already use, and the redesign lines up with the app rather than with its
/// own reference frame. Taken from [TvBrowseRail.horizontalInsetForScale] so
/// the header and whatever sits under it cannot drift apart.
double ockerFlushLeftInset(BuildContext context) =>
    TvBrowseRailLayout.horizontalInsetForScale(TvLayoutConstants.scaleOf(context));

/// Whether the redesign's *look* is on: its three typefaces, its corners, its
/// one focus ring and its one accent.
///
/// True in both of its palettes — "Redesign – Ocker" and "Redesign – Schwarz",
/// which differ in nothing but colour, and colour is something every branch
/// here already takes from the theme rather than writing down. Every branch
/// that only repaints something reads this; a branch that moves something
/// reads [isOckerLayout].
///
/// It asks the theme rather than the settings service on purpose: a widget
/// under a `Theme` override — a preview, a test, a screenshot harness — then
/// answers for the theme it is actually drawn in, not for what the app has
/// saved.
///
/// Read off [MonoTokens.displayFontFamily] because that is the field only these
/// variants fill. Deliberately distinctive, so a `grep` after an upstream merge
/// finds every place the redesign hooks in.
bool isOcker(BuildContext context) =>
    Theme.of(context).extension<MonoTokens>()?.displayFontFamily == ockerDisplayFontFamily;

/// Whether the screens are also rearranged — navigation in the redesign's own
/// rail, the detail panel beside the grids, the rebuilt guide.
///
/// The gate for everything in this folder that *replaces* a screen, where
/// [isOcker] gates everything that only *repaints* one. There was briefly a
/// second variant that answered true to the one and false to the other — the
/// look without the rearranging — and while it is gone, the split is what
/// keeps the seventy-odd branches in this fork legible: a gate that moves
/// something and a gate that paints something are different decisions, and
/// the shared widgets serve phone and tablet, where this design has no
/// screens of its own yet.
///
/// Only where the app navigates by its side rail — a television, a desktop
/// window. A phone or tablet keeps its own arrangement and wears the look
/// alone: the screens below this gate drop their own headers in the belief
/// that the rail carries them, and on a phone nothing would.
bool isOckerLayout(BuildContext context) =>
    Theme.of(context).extension<MonoTokens>()?.redesignLayout == true && !PlatformDetector.isMobile(context);

/// Where a screen's content starts under the redesign: at the top safe
/// margin. The destinations stand in the rail down the left, so nothing lies
/// across the top for a screen to clear.
double ockerContentTop(BuildContext context) => OckerLayout.contentTop * ockerScale(context);

/// Reference frame the design was drawn in: 1920 x 1080, at 1x.
const ockerReferenceWidth = 1920.0;

/// How much to shrink the drawn-for-1920 geometry to fit this screen.
///
/// A 720p television reports 1280 logical pixels across, so everything here
/// lands at 0.667 — and at the same physical size on the panel, because the
/// box upscales the whole frame. Proportion is what the design depends on: the
/// detail panel holding a quarter of the width, six columns fitting the rest.
///
/// Clamped at 0.5, not 0.6.
///
/// The 0.6 was a guess, and the wrong one. It was meant to stop the type
/// becoming unreadable at television distance — but a television reporting 960
/// logical pixels is doing so on a 1920-pixel panel, two device pixels to the
/// logical one, so 0.5 renders every line at exactly the physical size it was
/// drawn at. Nothing was protected by the floor.
///
/// What it cost was real: everything sized from the scale — the panel, the
/// margins, the gutter — was drawn a fifth larger than the design asks for at
/// that width, and the only things left to pay for it were the posters. They
/// came out a fifth too small, which is precisely what the design says must
/// not happen to them.
///
/// Above 1.0 there is still no evidence the design was ever meant to grow.
///
/// A phone or tablet is not a smaller television: it is held, not watched
/// from across the room, and its logical pixels are already a reading size.
/// Scaled by width it came out at the floor — a menu heading at nine points —
/// so it takes [ockerHandheldScale] instead, whatever its width. Only the look
/// reaches it there; nothing laid out for the 1920 frame does (see
/// [isOckerLayout]).
double ockerScale(BuildContext context) {
  if (PlatformDetector.isMobile(context)) return ockerHandheldScale;
  final width = MediaQuery.sizeOf(context).width;
  return (width / ockerReferenceWidth).clamp(0.5, 1.0);
}

/// [ockerScale] on a phone or tablet: the drawn sizes a notch down, which
/// lands the redesign's type on the reading sizes those screens use — a
/// menu heading at sixteen, the small mono labels at eleven.
const ockerHandheldScale = 0.85;

/// The width one poster is drawn at — on every screen that draws one.
///
/// Not [OckerLayout.tileWidth] times the scale, which is what the rows used
/// and which is only the same number on a screen exactly 1920 wide. Below
/// that, [ockerScale] stops at 0.6 while the screen carries on shrinking — an
/// Android TV reports 960 logical pixels across — so the furniture that is
/// sized from the scale (panel, margins, gutter) keeps more of the width than
/// it was drawn to, and a grid that divides up what is left ends with smaller
/// posters than a row that multiplies a constant. On the television that came
/// out as a watchlist whose posters were two thirds the size of the home
/// screen's.
///
/// So the grid decides, and the rows follow: five columns in the column a grid
/// page gives them. On a 1920 screen this is exactly 210, as drawn.
///
/// Measured against the *drawn* gutter ([OckerLayout.columnGutter]), not the
/// narrower one the screens actually lay out with. The gap between the words
/// and the pictures is a matter of taste and has been tightened; the poster is
/// a size the viewer has settled on, and it must not move every time the gap
/// does. The grid simply leaves the difference unused at its right edge.
double ockerTileWidth(BuildContext context) => ockerTileWidthFor(
  context,
  MediaQuery.sizeOf(context).width -
      2 * OckerLayout.safeMargin * ockerScale(context) -
      OckerLayout.panelWidth * ockerScale(context) -
      OckerLayout.columnGutter * ockerScale(context),
);

/// The same width, for a column that has already been measured.
///
/// [ockerTileWidth] works the column out from the viewport, which is right
/// where this design owns the whole screen. It is wrong wherever something
/// else has taken a piece of it first — the app's own layout keeps a
/// navigation rail down the left, and a column worked out from the full width
/// is then wider than the column that exists. Five posters sized for it do not
/// fit, the grid wraps at four, and the focus arithmetic — which counts in
/// fives — starts landing a place off on every DOWN.
///
/// So a grid that can measure itself passes what it measured.
double ockerTileWidthFor(BuildContext context, double contentWidth) {
  final scale = ockerScale(context);
  final gaps = OckerLayout.tileGap * scale * (OckerLayout.gridColumns - 1);
  // The 2 px are the focus ring's bleed, which the grid reserves either side.
  //
  // The lower bound is a guard against a degenerate width, not a design
  // minimum, and it is deliberately far below any real one: a floor high
  // enough to bite would push five posters back over the width they were
  // measured against, and the grid would wrap at four while the focus
  // arithmetic went on counting in fives. A column too narrow for five of
  // these is not a shape this design is asked to draw.
  return ((contentWidth - 2 - gaps) / OckerLayout.gridColumns).clamp(40.0, OckerLayout.tileWidth);
}

/// The detail panel on a grid page, widened by whatever its flush-left margin
/// gave back.
///
/// A grid page starts at [ockerFlushLeftInset] rather than at the design's own
/// [OckerLayout.safeMargin], so the panel's words sit directly under the
/// destinations instead of stepping in from them. The difference goes to the
/// panel, which is why the column beside it — and therefore
/// every poster in it — does not move.
double ockerGridPanelWidth(BuildContext context) {
  final scale = ockerScale(context);
  // Never negative: the two insets come from different scales, and on a window
  // narrow enough the design's own margin falls below the app's television
  // inset. There is nothing to reclaim there, and a panel that shrank instead
  // would push the grid off its measured column.
  final reclaimed = (OckerLayout.safeMargin * scale - ockerFlushLeftInset(context)).clamp(0.0, double.infinity);
  return OckerLayout.panelWidth * scale + reclaimed;
}

/// [child] stepped back, unless it holds focus.
///
/// A shelf of catalogue artwork is a mosaic: every poster was drawn to shout,
/// and eight of them side by side shout over each other. "Ocker" answers that
/// the way it answers everything — by taking brightness away from what is not
/// being looked at, so the one title under the cursor is unmistakably the one
/// chosen and the rest still read as a row.
///
/// The pictures themselves are darkened, not the box they stand in — see
/// [ArtworkDimScope]. A wash of black over the box showed wherever the
/// picture did not fill it: a card's padding, a logo's clear corners, a tile
/// rounded more gently than the box, all read as a translucent black ground
/// behind the element. Still no Opacity, which allocates a save layer per
/// card — on the tiled GPUs in television boxes a full render pass.
Widget ockerUnfocusedWash({
  required BuildContext context,
  required bool isFocused,
  required Duration duration,
  required Widget child,
}) {
  if (!isOcker(context)) return child;
  return ArtworkDim(dimmed: !isFocused, amount: ockerUnfocusedDim, duration: duration, child: child);
}

/// How much darker what does not hold focus is drawn: 22 %, the old wash's
/// `0x38` of black.
const ockerUnfocusedDim = 0x38 / 255;

/// The TV layout's fixed geometry, §5.1 of the styleguide, in the 1920 frame.
///
/// Multiply by [ockerScale] before use. Kept together so the numbers that have
/// to agree — the panel's width, the content column's left edge, and the gutter
/// that is what is left over — cannot drift apart.
class OckerLayout {
  OckerLayout._();

  /// Left and right safe margin.
  static const safeMargin = 96.0;

  /// Baseline of the home screen's chrome and the clock, top right.
  static const headerTop = 52.0;

  /// Where content starts: the destinations are in the side rail, so there is
  /// nothing to clear but the top of a television's safe area.
  static const contentTop = 72.0;

  /// The left panel that describes whatever holds focus.
  /// The describing column on the grid pages.
  ///
  /// 400, not the 480 the handoff draws. It was a quarter of a 1920 screen
  /// when it stood beside every row in the app; it now stands beside the grids
  /// alone — the rows describe the focused title in themselves — and a fifth
  /// carries the same words. The 80 go to the posters, which were the thing
  /// actually short of room on the television.
  static const panelWidth = 400.0;

  /// 16:9 on [panelWidth], and it has to follow it: the still is a photograph,
  /// and a photograph in a box of the wrong ratio is a cropped photograph.
  static const panelStillHeight = panelWidth * 9 / 16;
  static const panelStillHeightWithGroupBar = panelStillHeight * 0.89;

  /// The gap between the panel and a *grid* beside it.
  ///
  /// A number of its own, not the leftover between [panelWidth] and a drawn
  /// content edge — which is how it used to be written, and which meant that
  /// narrowing the panel to give the posters room quietly widened the gutter
  /// by exactly as much and gave them none.
  static const columnGutter = 124.0;

  /// Where the content column starts, and how wide it is. Both follow from the
  /// panel and the gutter rather than standing beside them, so there is one
  /// place to change and nothing that can disagree.
  static const contentLeft = safeMargin + panelWidth + columnGutter;
  static const contentWidth = ockerReferenceWidth - contentLeft - safeMargin;

  /// The gap between the panel and *rows* beside it.
  ///
  /// Half of [columnGutter]. A row does not end — it runs off the right edge —
  /// so every pixel taken off this gap becomes another sliver of poster
  /// instead of a bigger one. And at television distance 124 stopped reading
  /// as a separation and started reading as a hole: the eye has understood
  /// "words left, pictures right" from the hairline and the change of typeface
  /// long before the gap has to say it.
  static const rowGutter = columnGutter / 2;

  /// Poster grid: 2:3 tiles, five to a row in [contentWidth].
  ///
  /// The handoff draws six, at 172. Six was too small to read a poster's own
  /// title from the sofa — which is most of what a poster is for — and five at
  /// 210 turned out to be too small as well, once it was measured on the
  /// actual television rather than in the 1920 frame.
  ///
  /// Four was tried and overshot by half. The width came from [panelWidth]
  /// instead: the describing column is drawn for a screen it no longer has to
  /// share with the rows, and a fifth of the design is enough for it. Five
  /// stays — five posters and a description read as a page, four as a poster
  /// gallery — and each one gains about a third.
  ///
  /// [tileWidth] is the drawn size at 1920 and the ceiling; what a screen
  /// actually gets comes from `ockerTileWidth`, which divides the column that
  /// exists.
  static const tileWidth = 226.0;

  static const tileHeight = 339.0;
  static const tileGap = 18.0;
  static const gridColumns = 5;

  /// How far a poster's corner is taken off, as a share of the width it is
  /// drawn at.
  ///
  /// Where this design's corner was first cut. §10 said none anywhere, and
  /// artwork was the exception that broke it: a poster is not a box the
  /// interface drew but a picture it is *showing*, and a picture with a corner
  /// reads as an object lying on the page while a square one reads as a hole
  /// cut in it. The boxes followed a day later, in this same key — see the
  /// radius ladder in `monoTheme`.
  ///
  /// Taken as a share rather than a number so it holds at every size this is
  /// drawn: the shelf poster, the grid cell, and the thumbnails in the hero
  /// banner's strip, which are two thirds the size of the rest.
  static const posterCornerShare = 0.065;

  /// The fade at the foot of the content column, through which the next
  /// section's heading shows as a hint that there is more below.
  static const bottomFadeHeight = 150.0;

  /// Brightness of a poster that does not hold focus, and of everything
  /// behind an open context menu.
  static const tileDimmed = 0.78;
  static const menuBackdropTile = 0.40;
  static const menuBackdropGrid = 0.34;
}

/// The corner a picture is drawn with at [width], as the redesign rounds them.
///
/// Clamped at both ends: under about four pixels a corner is a smudge rather
/// than a shape, and past twenty the poster starts reading as a lozenge.
BorderRadius ockerPosterCorner(double width) =>
    BorderRadius.circular((width.isFinite ? width * OckerLayout.posterCornerShare : 12.0).clamp(4.0, 22.0));

/// The accent rule under the destination on show — exactly as wide as the word
/// it belongs to.
///
/// Measured rather than stretched. The word sits inside a box that is wider
/// than it is: the focus ring's own offset either side, and on a destination
/// that opens a menu the little chevron after it as well. A rule that filled
/// that box ran out past both, which read as a mark under the *slot* rather
/// than under the name in it.
///
/// Drawn whether or not it is active — transparent when it is not — so a row
/// of these never changes height as the selection moves along it.
Widget ockerActiveMark(BuildContext context, {required String label, required TextStyle style, required bool active}) {
  final tk = tokens(context);
  final scale = ockerScale(context);
  final painter = TextPainter(
    text: TextSpan(text: label, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final width = painter.width;
  painter.dispose();

  return Padding(
    // The ring's own offset, so the rule starts under the first letter rather
    // than under the air the ring keeps around it.
    padding: EdgeInsets.only(left: tk.focusRingOffset),
    child: Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: width,
        height: 2 * scale,
        child: ColoredBox(color: active ? tk.accent : Colors.transparent),
      ),
    ),
  );
}

/// Whether the floating surfaces are glass — "Redesign – Glas" and no other.
///
/// Asks the theme, like [isOcker], so a widget under a `Theme` override
/// answers for the theme it is drawn in.
bool ockerGlass(BuildContext context) => Theme.of(context).extension<MonoTokens>()?.glass == true;

/// The two strengths the glass comes in.
///
/// Light, for what is only focused, never read at length: bands, chips,
/// buttons — whatever lies behind comes through. And [ockerReadingGroundOpacity]
/// for what holds words to read: cards, sheets, columns. There were three —
/// cards stood between the two at .78 — and the difference read as a mistake
/// rather than a rank.
const ockerBandGroundOpacity = 0.46;

/// The glass's own body: the ground at under half its strength, so whatever
/// lies behind comes through.
Color ockerGlassGround(BuildContext context) => tokens(context).bg.withValues(alpha: ockerBandGroundOpacity);

/// The sheen across the glass, corner to corner: brightest at the top left,
/// almost nothing through the middle, a little again at the bottom right —
/// light falling on a pane rather than a wash over it.
LinearGradient ockerGlassSheen(BuildContext context) {
  final tk = tokens(context);
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [tk.ink(0.16), tk.ink(0.03), tk.ink(0.10)],
    stops: const [0, 0.45, 1],
  );
}

/// The firmer ground behind the words on the glass.
///
/// A fixed transparency does not hold over pale artwork — a near-white poster
/// behind a menu took its rows below reading contrast. So the words get a
/// ground of their own, a shade deeper than the page's, while the rim around
/// them stays glass. Over the glass it comes to about three quarters ground,
/// which keeps even the muted ink legible over a white poster.
BoxDecoration ockerGlassScrim(BuildContext context, {BorderRadius? borderRadius}) => BoxDecoration(
  color: Color.lerp(tokens(context).bg, Colors.black, 0.35)!.withValues(alpha: 0.55),
  borderRadius: borderRadius,
);

/// A floating surface made of glass: a darker ground than a band's, the
/// sheen, and a lit edge, its words held [scrimInset] in from it.
///
/// There was a firmer ground inset behind the words, the rim left as glass.
/// It read as a dark box inside the pane, so the whole pane is darker now
/// instead: over a near-white poster that still keeps the words legible, and
/// the pane stays one surface.
///
/// No blur. A backdrop filter recomputes every frame for as long as the
/// surface is up, and on the boxes this runs on that is the whole budget;
/// three alpha layers cost nothing and read as glass from across the room.
///
/// The edge is light, not a border: one hairline round the shape, bright
/// along the top, fading down the sides and dark along the bottom, as a pane
/// catches the room's light.
/// Marks what stands on a pane of glass — a hosted sheet's body — so its rows
/// mark focus and the chosen one with glass of their own, as the menus do,
/// without each list having to ask for it.
class OckerOnGlass extends InheritedWidget {
  const OckerOnGlass({super.key, required super.child});

  static bool appliesAt(BuildContext context) => context.getInheritedWidgetOfExactType<OckerOnGlass>() != null;

  @override
  bool updateShouldNotify(OckerOnGlass oldWidget) => false;
}

/// How much of the ground glass that is read holds — a card, a sheet, a
/// column: more than a band's, because it carries rows of words over a busy
/// grid of posters. See [ockerBandGroundOpacity].
const ockerReadingGroundOpacity = 0.88;

class OckerGlass extends StatelessWidget {
  const OckerGlass({
    super.key,
    required this.borderRadius,
    required this.child,
    this.scrimInset = 8,
    this.groundOpacity = ockerReadingGroundOpacity,
  });

  final BorderRadius borderRadius;
  final double scrimInset;

  /// How much of the ground the pane holds; [ockerReadingGroundOpacity], as
  /// everything read on glass, unless a pane has a reason of its own.
  final double groundOpacity;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _OckerGlassEdge(
        RoundedRectangleBorder(borderRadius: borderRadius),
        Directionality.of(context),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens(context).bg.withValues(alpha: groundOpacity),
          borderRadius: borderRadius,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: ockerGlassSheen(context), borderRadius: borderRadius),
          child: Padding(padding: EdgeInsets.all(scrimInset), child: child),
        ),
      ),
    );
  }
}

/// A button made of glass: the glass and its firmer ground in one, edge to
/// edge — a button is all words, so there is no rim to keep. The sheen lies
/// over it, and the lit edge round it. [lit] is focus: the pane fills with
/// ink, as the redesign's buttons have always shown it, and keeps its edge.
///
/// Fits a [ButtonStyle.backgroundBuilder]: sized by the button, clipped to
/// [shape], [child] on top.
class OckerGlassPlate extends StatelessWidget {
  const OckerGlassPlate({super.key, required this.shape, required this.lit, this.child, this.firm = true});

  final ShapeBorder shape;
  final bool lit;
  final Widget? child;

  /// Whether the firmer inner ground lies under the sheen. A button wants it;
  /// a fact standing beside a band of buttons does not — with it, the facts
  /// read darker than the band they sit over. Without, the plate is the
  /// band's own glass: ground, sheen and edge.
  final bool firm;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final Widget body = lit
        ? ColoredBox(color: tk.ink(1))
        : ColoredBox(
            color: ockerGlassGround(context),
            child: firm
                ? DecoratedBox(
                    decoration: ockerGlassScrim(context),
                    child: DecoratedBox(decoration: BoxDecoration(gradient: ockerGlassSheen(context))),
                  )
                : DecoratedBox(decoration: BoxDecoration(gradient: ockerGlassSheen(context))),
          );
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: ClipPath(
            clipper: ShapeBorderClipper(shape: shape, textDirection: Directionality.of(context)),
            child: CustomPaint(
              foregroundPainter: _OckerGlassEdge(shape, Directionality.of(context)),
              child: SizedBox.expand(child: body),
            ),
          ),
        ),
        ?child,
      ],
    );
  }
}

/// Focus on a word in one of the redesign's rows of words — the header's
/// destinations, a screen's tabs, a group bar.
///
/// A brighter capsule of glass behind the word, with the pane's lit edge —
/// not a ring: a ring round a word on a pane read as a second, smaller pane.
///
/// The capsule also says which one is on show, the way Apple's glass marks a
/// selected tab: a quiet capsule faintly tinted with the accent, in place of a
/// rule under the word. On a band the band draws both — the focus capsule
/// glides, and swallows the quiet one as it passes over it, taking on its
/// tint.
///
/// The capsule stands off the word by [ockerWordCapsuleOutset]. Focused, it
/// stands taller by [ockerWordFocusLift] and so rises a little out of the band
/// it lies on, top and bottom — lifted off the glass, as Apple's lifts under a
/// finger. A capsule, as Apple's glass draws its own: half its height for a
/// corner. It takes no room, so a row never moves as focus walks along it.
class OckerWordFocus extends StatefulWidget {
  const OckerWordFocus({super.key, required this.focused, required this.child, this.active = false, this.outset});

  final bool focused;

  /// How far the capsule stands off the child; [ockerWordCapsuleOutset] when
  /// null. A button that is already its own shape takes none.
  final EdgeInsets? outset;

  /// Whether this is the one on show: the quiet, tinted capsule.
  final bool active;

  final Widget child;

  @override
  State<OckerWordFocus> createState() => _OckerWordFocusState();
}

class _OckerWordFocusState extends State<OckerWordFocus> {
  _OckerBandScope? _band;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _band = _OckerBandScope.maybeOf(context);
  }

  @override
  void didUpdateWidget(OckerWordFocus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focused && !widget.focused) _releaseSoon();
    if (oldWidget.active && !widget.active) _band?.unmarkActive(this);
  }

  @override
  void dispose() {
    _band?.release(this);
    _band?.unmarkActive(this);
    super.dispose();
  }

  /// Focus has moved on. A frame later the next word has claimed the band's
  /// capsule — which then glides there — or nothing has, and it fades out.
  void _releaseSoon() {
    final band = _band;
    if (band == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => band.release(this));
  }

  /// Tells the band where this word's capsules belong, once it is laid out:
  /// the focus capsule, lifted, if it holds focus; the quiet one if it is on
  /// show.
  void _reportSoon(BuildContext context) {
    final band = _band;
    if (band == null) return;
    final outset = widget.outset ?? ockerWordCapsuleOutset(context);
    final lift = ockerWordFocusLift(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final word = context.findRenderObject() as RenderBox?;
      final place = band.stackKey.currentContext?.findRenderObject() as RenderBox?;
      if (word == null || place == null || !word.hasSize || !word.attached || !place.attached) return;
      final box = word.localToGlobal(Offset.zero, ancestor: place) & word.size;
      final resting = Rect.fromLTRB(
        box.left - outset.left,
        box.top - outset.top,
        box.right + outset.right,
        box.bottom + outset.bottom,
      );
      if (widget.focused) {
        band.claim(this, Rect.fromLTRB(resting.left, resting.top - lift, resting.right, resting.bottom + lift));
      }
      if (widget.active) band.markActive(this, resting);
    });
  }

  @override
  Widget build(BuildContext context) {
    // On a band, the band draws both capsules; the word only says where.
    if (_band != null) {
      if (widget.focused || widget.active) _reportSoon(context);
      return widget.child;
    }
    final outset = widget.outset ?? ockerWordCapsuleOutset(context);
    final lift = widget.focused ? ockerWordFocusLift(context) : 0.0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (widget.focused || widget.active)
          Positioned(
            left: -outset.left,
            right: -outset.right,
            top: -(outset.top + lift),
            bottom: -(outset.bottom + lift),
            child: _OckerGlassCapsule(bright: widget.focused, tint: widget.active ? 1 : 0),
          ),
        widget.child,
      ],
    );
  }
}

/// How long a word's ink takes between asleep and awake under glass: about
/// as long as the capsule's glide, and late in it, so the word lights as the
/// capsule arrives rather than a moment before. Instant everywhere else, and
/// on the reduced tier.
Duration ockerInkFade(BuildContext context) =>
    ockerGlass(context) ? ockerGlassMotion(const Duration(milliseconds: 240)) : Duration.zero;

/// [full] for the glass focus's own motion — the capsule's glide and the ink
/// fading with it: on the full tier, or wherever the viewer switched them on
/// on their own ([SettingsService.glasSmoothFocus]); nothing on a reduced tier
/// otherwise.
Duration ockerGlassMotion(Duration full) =>
    SettingsService.instanceOrNull?.read(SettingsService.glasSmoothFocus) ?? false
    ? full
    : DevicePerformance.reducedDuration(full);

/// Builds with [color], faded to it over [ockerInkFade] when it changes.
class OckerInk extends StatelessWidget {
  const OckerInk({super.key, required this.color, required this.builder});

  final Color color;
  final Widget Function(BuildContext context, Color color) builder;

  @override
  Widget build(BuildContext context) {
    final fade = ockerInkFade(context);
    if (fade == Duration.zero) return builder(context, color);
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: color),
      duration: fade,
      curve: Curves.easeIn,
      builder: (context, value, _) => builder(context, value ?? color),
    );
  }
}

/// How far a focused word's glass capsule stands off the word's own box — so
/// a band round a row of them can keep one even margin round any capsule.
EdgeInsets ockerWordCapsuleOutset(BuildContext context) {
  final scale = ockerScale(context);
  return EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 6 * scale);
}

/// The band's even margin round a resting capsule.
double ockerBandMargin(BuildContext context) => 4 * ockerScale(context);

/// How far a band reaches past its row so it stands [ockerBandMargin] off a
/// capsule on every side — the same above, below and at the ends, which is
/// what makes the band's curve and the capsule's concentric. [wordInset] is
/// how far the row's own edge already lies from a word's box: the chip's
/// padding, the room the rule gave up.
EdgeInsets ockerBandOverhang(BuildContext context, {EdgeInsets wordInset = EdgeInsets.zero}) {
  final reach = ockerWordCapsuleOutset(context) + EdgeInsets.all(ockerBandMargin(context));
  double past(double a, double b) => (a - b).clamp(0.0, double.infinity);
  return EdgeInsets.fromLTRB(
    past(reach.left, wordInset.left),
    past(reach.top, wordInset.top),
    past(reach.right, wordInset.right),
    past(reach.bottom, wordInset.bottom),
  );
}

/// Focus as a pane of brighter glass behind whatever holds it, lit at its
/// edge — the capsule a focused word gets, in any [shape]. For controls that
/// have always shown focus as a plate behind them.
class OckerGlassFocusFill extends StatelessWidget {
  const OckerGlassFocusFill({super.key, required this.shape, this.bright = true, this.tint = 0});

  final ShapeBorder shape;

  /// Focus. Without it the pane is the quiet one that marks what is chosen.
  final bool bright;

  /// How much of the accent's wash it wears: 1 on the one chosen.
  final double tint;

  @override
  Widget build(BuildContext context) => _OckerGlassCapsule(bright: bright, tint: tint, shape: shape);
}

/// [child] with a pane of bright glass of [shape] behind it while [focused]
/// — focus on a cell under "Glas", in place of a ring or a white plate.
///
/// The cell keeps exactly the size it is given: the stack passes its
/// constraints through, where a loose one let a focused cell shrink to its
/// contents and its logo jump to the top.
class OckerGlassFocusBehind extends StatelessWidget {
  const OckerGlassFocusBehind({super.key, required this.focused, required this.shape, required this.child});

  /// [child] as it is when not [focused].
  static Widget wrap(bool focused, ShapeBorder shape, Widget child) =>
      focused ? OckerGlassFocusBehind(focused: true, shape: shape, child: child) : child;

  final bool focused;
  final ShapeBorder shape;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!focused) return child;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(child: OckerGlassFocusFill(shape: shape)),
        child,
      ],
    );
  }
}

/// How much taller a focused word's capsule stands than a resting one, each
/// way: past the band's even margin round a resting capsule, and a few pixels
/// out of the band.
double ockerWordFocusLift(BuildContext context) => ockerBandMargin(context) + 4 * ockerScale(context);

/// The wash every palette started with; the sheen stands whole up to it.
const _faintWash = 0.22;

/// The capsule behind a word: the glass again, lit at its edge.
///
/// [bright] is focus — twice the band's sheen over a thinner ground. Without
/// it the capsule is quiet, a shade of sheen, there only to say, through
/// [tint], that this one is on show: washed faintly with the accent — the
/// accent's job of marking the destination on show, done by the glass instead
/// of a rule. [tint] runs from 0 to 1, so a focus capsule can take it on
/// gradually as it swallows the quiet one.
///
/// A palette whose wash is more than faint ([MonoTokens.accentWash]) fills the
/// capsule with its colour, and the sheen gives way to it by as much as the
/// wash goes past faint: over solid red a full sheen reads as pink.
class _OckerGlassCapsule extends StatelessWidget {
  const _OckerGlassCapsule({required this.bright, required this.tint, this.shape = const StadiumBorder()});

  final bool bright;
  final double tint;
  final ShapeBorder shape;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final wash = tk.accentWash * tint;
    final giveWay = 1 - 0.6 * math.max(0, wash - _faintWash);
    final sheen = [
      for (final a in bright ? const [0.34, 0.12, 0.22] : const [0.12, 0.03, 0.07]) a * giveWay,
    ];
    return IgnorePointer(
      child: CustomPaint(
        foregroundPainter: _OckerGlassEdge(shape, Directionality.of(context)),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            shape: shape,
            color: Color.alphaBlend(tk.accent.withValues(alpha: wash), tk.bg.withValues(alpha: 0.30)),
          ),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              shape: shape,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [for (final a in sheen) tk.ink(a)],
                stops: const [0, 0.45, 1],
              ),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

/// A row of words — the header's destinations, a screen's tabs — laid on a
/// pane of glass under "Redesign – Glas", and left as it is everywhere else.
///
/// The pane reaches [overhang] past the row on every side without taking any
/// room: the row keeps its place to the pixel, flush with what lines up under
/// it. Whatever holds the row must not clip it — a scroll view around one
/// passes `Clip.none` under glass.
///
/// A capsule, like the focus inside it, so the two are concentric: an even
/// margin all round the one within the other. Plain glass — no firmer ground
/// inside: a band of words over the page is not a menu over a poster, and the
/// darker inner box read as a second band.
class OckerGlassBand extends StatefulWidget {
  const OckerGlassBand({super.key, required this.overhang, required this.child});

  /// The band's focus capsule, and the quiet one for the word on show.
  @visibleForTesting
  static const focusCapsuleKey = ValueKey('ockerBandFocusCapsule');
  @visibleForTesting
  static const activeCapsuleKey = ValueKey('ockerBandActiveCapsule');

  final EdgeInsets overhang;
  final Widget child;

  @override
  State<OckerGlassBand> createState() => _OckerGlassBandState();
}

/// Where one of the band's capsules belongs, and for which word.
@immutable
class _OckerBandMark {
  const _OckerBandMark(this.owner, this.rect);

  final State owner;
  final Rect rect;

  bool same(_OckerBandMark other) => other.owner == owner && other.rect == rect;
}

/// How a word on a band reaches the band's two capsules: the focus capsule,
/// which glides, and the quiet one for the word on show.
class _OckerBandScope extends InheritedWidget {
  const _OckerBandScope({
    required this.focus,
    required this.active,
    required this.stackKey,
    required this.isAlive,
    required super.child,
  });

  /// Whether the band is still there to be told anything.
  final bool Function() isAlive;

  final ValueNotifier<_OckerBandMark?> focus;
  final ValueNotifier<_OckerBandMark?> active;

  /// The band's own box, which a word measures itself against.
  final GlobalKey stackKey;

  static _OckerBandScope? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<_OckerBandScope>();

  static void _set(ValueNotifier<_OckerBandMark?> slot, _OckerBandMark next) {
    final current = slot.value;
    if (current != null && current.same(next)) return;
    slot.value = next;
  }

  void claim(State owner, Rect rect) => _set(focus, _OckerBandMark(owner, rect));

  /// Focus has left [owner]. Another word may claim the capsule in the same
  /// frame — focus moving along the band rather than leaving it — and the
  /// order the two land in is only the order of the words in the tree: a word
  /// to the right claims after the one it came from lets go. So letting go
  /// waits for every claim of the frame; had it not, moving right looked like
  /// leaving and arriving, and the capsule appeared at the next word instead
  /// of gliding there.
  void release(State owner) {
    scheduleMicrotask(() {
      if (!isAlive()) return;
      if (focus.value?.owner == owner) focus.value = null;
    });
  }

  void markActive(State owner, Rect rect) => _set(active, _OckerBandMark(owner, rect));

  void unmarkActive(State owner) {
    if (active.value?.owner == owner) active.value = null;
  }

  @override
  bool updateShouldNotify(_OckerBandScope oldWidget) => false;
}

class _OckerGlassBandState extends State<OckerGlassBand> with TickerProviderStateMixin {
  final _focus = ValueNotifier<_OckerBandMark?>(null);
  final _active = ValueNotifier<_OckerBandMark?>(null);
  final _stackKey = GlobalKey();

  /// The focus capsule's way from where it was to where it is going.
  late final AnimationController _glide = AnimationController(vsync: this);

  /// The focus capsule coming and going as focus enters and leaves the band.
  late final AnimationController _presence = AnimationController(vsync: this);

  RectTween? _path;

  /// Whether some word holds the focus capsule now.
  bool _held = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_follow);
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_follow)
      ..dispose();
    _active.dispose();
    _glide.dispose();
    _presence.dispose();
    super.dispose();
  }

  /// Where the focus capsule is at this moment of its glide.
  Rect? get _focusRect => _path?.transform(Curves.easeOutCubic.transform(_glide.value));

  void _follow() {
    _glide.duration = ockerGlassMotion(const Duration(milliseconds: 220));
    _presence.duration = ockerGlassMotion(const Duration(milliseconds: 140));
    final to = _focus.value;
    if (to == null) {
      _held = false;
      _presence.reverse();
      return;
    }
    if (!_held || _path == null) {
      // Focus arriving from outside the band: the capsule appears at its word
      // rather than flying in from wherever it was last.
      _path = RectTween(begin: to.rect, end: to.rect);
      _glide.value = 1;
      _held = true;
      _presence.forward();
      return;
    }
    _path = RectTween(begin: _focusRect ?? to.rect, end: to.rect);
    _glide.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    if (!ockerGlass(context)) return widget.child;
    const shape = StadiumBorder();
    final overhang = widget.overhang;
    return _OckerBandScope(
      focus: _focus,
      active: _active,
      stackKey: _stackKey,
      isAlive: () => mounted,
      child: Stack(
        key: _stackKey,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -overhang.left,
            top: -overhang.top,
            right: -overhang.right,
            bottom: -overhang.bottom,
            child: IgnorePointer(
              child: CustomPaint(
                foregroundPainter: _OckerGlassEdge(shape, Directionality.of(context)),
                child: DecoratedBox(
                  decoration: ShapeDecoration(shape: shape, color: ockerGlassGround(context)),
                  child: DecoratedBox(
                    decoration: ShapeDecoration(shape: shape, gradient: ockerGlassSheen(context)),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: Listenable.merge([_glide, _presence, _active]),
                builder: (context, _) {
                  final focus = _focusRect;
                  final present = _presence.value;
                  final mark = _active.value?.rect;
                  // How much of the quiet capsule the focus capsule covers
                  // now: that much of it is swallowed, and that much of its
                  // tint the focus capsule has taken on.
                  var swallowed = 0.0;
                  if (focus != null && mark != null && mark.width > 0 && present > 0) {
                    final shared = math.min(focus.right, mark.right) - math.max(focus.left, mark.left);
                    swallowed = (shared / mark.width).clamp(0.0, 1.0) * present;
                  }
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (mark != null && swallowed < 1)
                        Positioned.fromRect(
                          key: OckerGlassBand.activeCapsuleKey,
                          rect: mark,
                          child: Opacity(
                            opacity: 1 - swallowed,
                            child: const _OckerGlassCapsule(bright: false, tint: 1),
                          ),
                        ),
                      if (focus != null && present > 0)
                        Positioned.fromRect(
                          key: OckerGlassBand.focusCapsuleKey,
                          rect: focus,
                          child: Opacity(
                            opacity: present,
                            child: _OckerGlassCapsule(bright: true, tint: swallowed),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _OckerGlassEdge extends CustomPainter {
  _OckerGlassEdge(this.shape, this.textDirection);

  /// Where the light comes from: down and to the right, 55° below the
  /// horizontal — top left bright, bottom right in shade.
  static const _lightAngle = 55 * math.pi / 180;

  final ShapeBorder shape;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    // One hairline along the shape itself, its light running down it: bright
    // across the top, fading down the sides — a touch brighter on the left,
    // where the light comes from — and dark along the bottom. Three straight
    // lines clipped to a rounded shape stopped short in every corner.
    final rect = (Offset.zero & size).deflate(0.5);
    // The light falls at one fixed angle, whatever the shape's proportions.
    // Laid out corner to corner instead, it ran almost straight down a long
    // band and cut it into a light top and a dark bottom; at a fixed slant the
    // line between light and dark crosses a band on the diagonal, and a small
    // button still gets its lit top left and shaded bottom right.
    final along = Offset(math.cos(_lightAngle), math.sin(_lightAngle));
    final reach = (size.width * along.dx.abs() + size.height * along.dy.abs()) / 2;
    canvas.drawPath(
      shape.getOuterPath(rect, textDirection: textDirection),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = ui.Gradient.linear(
          rect.center - along * reach,
          rect.center + along * reach,
          const [Color(0x59FFFFFF), Color(0x1AFFFFFF), Color(0x0AFFFFFF), Color(0x66000000)],
          const [0, 0.35, 0.6, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(_OckerGlassEdge oldDelegate) =>
      oldDelegate.shape != shape || oldDelegate.textDirection != textDirection;
}
