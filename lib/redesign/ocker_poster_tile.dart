import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../focus/dpad_navigator.dart';
import '../focus/focus_theme.dart';
import '../focus/dpad_select_long_press_controller.dart';
import '../focus/paint_scale.dart';
import '../media/catalog_item_ref.dart';
import '../media/media_hub.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_item_types.dart';
import '../services/settings_service.dart';
import '../theme/mono_tokens.dart';
import '../utils/media_image_helper.dart';
import '../widgets/media_card.dart' show catalogPosterOverlays;
import '../widgets/media_context_menu.dart';
import '../widgets/optimized_media_image.dart';
import '../widgets/watched_indicator.dart';
import 'ocker_focus_bus.dart';
import 'ocker_info_sheet.dart';
import 'ocker_skin.dart';
import '../widgets/artwork_dim_scope.dart';

/// One title, as quietly as it can be drawn.
///
/// No corner, no shadow, no border, no caption. Everything a caption would have
/// said is in the detail panel, for whichever tile holds focus — which is what
/// buys the design the right to make the tiles this plain.
///
/// Shared by the rows on the home screen and the grids on the browsing pages,
/// so "what a title looks like" is answered in exactly one place.
class OckerPosterTile extends StatefulWidget {
  final MediaItem item;
  final MediaHub hub;
  final int index;
  final int itemCount;
  final EpisodePosterMode posterMode;
  final bool mixedHub;
  final bool hideSpoilers;
  final double tileWidth;
  final double tileHeight;

  final FocusNode focusNode;
  final OckerClientResolver resolveClient;
  final VoidCallback onPlay;
  final VoidCallback onFocused;
  final VoidCallback onExitUp;
  final VoidCallback onExitDown;

  /// Drawn instead of the artwork.
  ///
  /// Some shelves hold destinations rather than titles — a streaming service,
  /// a genre, a year — and those have no poster at all. Handing the tile the
  /// card the app already draws for them keeps the focus behaviour, the
  /// dimming and the reporting to the panel identical, and stops a row of
  /// broken-image glyphs where a row of names belongs.
  final Widget? content;

  /// Where RIGHT goes at the last column, when that is somewhere.
  ///
  /// A library grid has an alphabet bar past its right edge; without this the
  /// tile would stop there and the bar could not be reached by the D-pad.
  final VoidCallback? onExitRight;

  /// Off the left of the first column, where there is something to reach.
  ///
  /// §7 says LEFT out of column one does nothing, and on the redesign's own
  /// layout that is right: what lies left of the grid is the detail panel,
  /// which is a display and not a target, and the navigation is overhead. On
  /// the app's own layout the navigation *is* down the left, and swallowing
  /// LEFT there leaves BACK as the only way out of a grid — which is a key
  /// for leaving a page, not for crossing to the menu beside it.
  ///
  /// Null keeps the swallowing, so nothing can fall off the edge by default.
  final VoidCallback? onExitLeft;

  /// How many tiles to a row, when this tile is in a grid.
  ///
  /// Null means a row that scrolls sideways: LEFT and RIGHT are the only way
  /// along it, and UP or DOWN leave it altogether. A number turns the same
  /// tile into a grid cell, where UP and DOWN step a whole row and the ends of
  /// a row stop instead of wrapping — a wrap would send focus flying across
  /// the screen.
  final int? columns;

  /// The node [delta] places along this section, or null when that would step
  /// off its end.
  final FocusNode? Function(int delta) neighbour;

  const OckerPosterTile({
    super.key,
    required this.item,
    required this.hub,
    required this.index,
    required this.itemCount,
    required this.posterMode,
    required this.mixedHub,
    required this.hideSpoilers,
    required this.tileWidth,
    required this.tileHeight,
    required this.focusNode,
    required this.resolveClient,
    required this.onPlay,
    required this.onFocused,
    required this.onExitUp,
    required this.onExitDown,
    required this.neighbour,
    this.columns,
    this.content,
    this.onExitRight,
    this.onExitLeft,
  });

  /// The viewer's artwork choice, or the fallback `MediaItem.posterThumb`
  /// itself takes when no mode is given.
  static EpisodePosterMode posterModeOf(BuildContext context) =>
      SettingsService.instanceOrNull?.read(SettingsService.episodePosterMode) ?? EpisodePosterMode.seriesPoster;

  static bool hideSpoilersOf(BuildContext context) =>
      SettingsService.instanceOrNull?.read(SettingsService.hideSpoilers) ?? false;

  @override
  State<OckerPosterTile> createState() => OckerPosterTileState();
}

class OckerPosterTileState extends State<OckerPosterTile> {
  final _menuKey = GlobalKey<MediaContextMenuState>();
  final _longPress = DpadSelectLongPressController();
  bool _focused = false;

  @override
  void dispose() {
    _longPress.dispose();
    super.dispose();
  }

  /// Anchored at the tile's lower-left corner, which is what "directly under
  /// the focused tile" means — the menu opens where the eye already is rather
  /// than in the middle of the screen.
  void _openMenu() {
    final box = context.findRenderObject() as RenderBox?;
    final anchor = box?.localToGlobal(Offset(0, box.size.height));
    _menuKey.currentState?.showContextMenu(context, position: anchor);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // SELECT is owned by the long-press controller: a short press plays, a
    // held one opens the options. It must see the up event too, so it is
    // asked before the direction keys are considered.
    final selectResult = _longPress.handleKeyEvent(
      event,
      isOwnerActive: () => mounted && widget.focusNode.hasFocus,
      onShortPress: widget.onPlay,
      onLongPress: _openMenu,
    );
    if (selectResult != KeyEventResult.ignored) return selectResult;

    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key.isContextMenuKey) {
      _openMenu();
      return KeyEventResult.handled;
    }
    // The "i" on the remote asks what this is. A tile is a poster and nothing
    // else, so the key that asks gets a panel of its own — see
    // [showOckerInfoSheet].
    //
    // The letter I does it too, for a keyboard and for an emulator without a
    // remote. It is kept here rather than in [DpadKeyExtension.isInfoKey],
    // because a printable character has no business in a set named for remote
    // keys — this is the one place it is safe, since a focused poster is never
    // a place text is being typed.
    if (key.isInfoKey || key == LogicalKeyboardKey.keyI) {
      unawaited(showOckerInfoSheet(context, item: widget.item, resolveClient: widget.resolveClient));
      return KeyEventResult.handled;
    }
    final columns = widget.columns;

    if (key.isLeftKey) {
      // §7: LEFT out of the first column does nothing. There is nothing to the
      // left to reach — the panel is a display, not a target — so a dead end
      // there would be a place focus could fall into and not come back from.
      // Unless the host says otherwise: a library grid has a menu down its
      // left, and the hero banner has the button that says what OK will do.
      final atLeftEdge = columns == null ? widget.index == 0 : widget.index % columns == 0;
      if (atLeftEdge) {
        widget.onExitLeft?.call();
        return KeyEventResult.handled;
      }
      widget.neighbour(-1)?.requestFocus();
      return KeyEventResult.handled;
    }
    if (key.isRightKey) {
      if (columns != null && widget.index % columns == columns - 1) {
        widget.onExitRight?.call();
        return KeyEventResult.handled;
      }
      widget.neighbour(1)?.requestFocus();
      return KeyEventResult.handled;
    }
    if (key.isUpKey) {
      final above = columns == null ? null : widget.neighbour(-columns);
      if (above == null) {
        widget.onExitUp();
      } else {
        above.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (key.isDownKey) {
      if (columns == null) {
        widget.onExitDown();
        return KeyEventResult.handled;
      }
      final below = widget.neighbour(columns);
      if (below != null) {
        below.requestFocus();
      } else if (widget.index ~/ columns < (widget.itemCount - 1) ~/ columns) {
        // The row below exists but is short of this column. Land on its last
        // title rather than stepping over the row, which would leave those
        // titles unreachable from every column to the right of them.
        widget.neighbour(widget.itemCount - 1 - widget.index)?.requestFocus();
      } else {
        widget.onExitDown();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _handleFocus(bool has) {
    setState(() => _focused = has);
    if (!has) {
      _longPress.reset();
      return;
    }
    widget.onFocused();
    OckerFocusScope.read(context)?.report(OckerFocused(item: widget.item, hub: widget.hub, index: widget.index));
    // In a row: sideways only — the page scrolls the vertical axis itself, by
    // section, because centring a 258-px poster would push its own heading off
    // the top. In a grid there is no section to scroll to, so the grid's own
    // vertical viewport follows the tile.
    //
    // `Scrollable.ensureVisible` is deliberately not used: it walks *every*
    // enclosing scrollable with one alignment, and the two axes want different
    // ones.
    _reveal();
  }

  void _reveal() {
    final box = context.findRenderObject();
    if (box == null) return;
    final axis = widget.columns == null ? Axis.horizontal : Axis.vertical;
    Scrollable.maybeOf(context, axis: axis)?.position.ensureVisible(
      box,
      alignment: widget.columns == null ? 0.5 : 0.3,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    // A row or a browsing grid hands the tile a measured size. A library's
    // virtualised grid measures its own cells instead and passes infinity —
    // there the tile fills what it is given, and the image sizes itself from
    // the layout rather than from a number.
    final width = widget.tileWidth;
    final height = widget.tileHeight;
    final imageWidth = width.isFinite ? width : null;
    final imageHeight = height.isFinite ? height : null;
    // Which artwork a title shows is the viewer's setting, not this tile's
    // choice: season poster, series poster or the episode's own still.
    final path =
        widget.item.posterThumb(mode: widget.posterMode, mixedHubContext: widget.mixedHub) ??
        widget.item.posterThumbFallback(mode: widget.posterMode, mixedHubContext: widget.mixedHub);
    final blurSpoiler =
        widget.hideSpoilers && widget.item.shouldHideSpoiler && widget.posterMode == EpisodePosterMode.episodeThumbnail;

    return MediaContextMenu(
      key: _menuKey,
      item: widget.item,
      child: Focus(
        focusNode: widget.focusNode,
        onKeyEvent: _onKey,
        onFocusChange: _handleFocus,
        child: GestureDetector(
          onTap: widget.onPlay,
          onLongPress: _openMenu,
          onSecondaryTap: _openMenu,
          // A focused poster grows a little, the way the standard theme's
          // cards do. Paint-only, so the row holds still under it — see
          // [PaintScale].
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: _focused ? FocusTheme.focusScaleFor(context) : 1.0),
            duration: tk.fast,
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => PaintScale(scale: value, child: child!),
            child: _buildPoster(context, tk, width, height, path, blurSpoiler, imageWidth, imageHeight),
          ),
        ),
      ),
    );
  }

  Widget _buildPoster(
    BuildContext context,
    MonoTokens tk,
    double width,
    double height,
    String? path,
    bool blurSpoiler,
    double? imageWidth,
    double? imageHeight,
  ) {
    // The corner the whole design carries on exactly one kind of thing — see
    // [OckerLayout.posterCornerShare]. The ring takes it too: a square ring
    // around a rounded picture would show four slivers of page at the corners.
    final corner = ockerPosterCorner(width);

    return AnimatedContainer(
      duration: tk.fast,
      curve: Curves.easeOutCubic,
      width: width,
      height: height,
      // Outside, with the theme's offset around it: the artwork runs to its
      // own edge, so a ring drawn on that edge would sit on the picture
      // instead of around it.
      foregroundDecoration: FocusTheme.focusDecoration(
        context,
        isFocused: _focused,
        radii: corner,
        borderStrokeAlign: BorderSide.strokeAlignOutside,
      ),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: corner),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The tiles that do not hold focus step back rather than
          // disappear: at 0.78 the row is still legible as a row, and the
          // one at full strength is unmistakably the one chosen. The
          // picture itself is darkened — see [ArtworkDimScope] — not a box
          // laid over the tile, which showed as a dark ground wherever the
          // picture did not fill it: a service's logo with clear corners,
          // rounded more gently than the tile.
          ArtworkDim(
            dimmed: !_focused,
            amount: ockerUnfocusedDim,
            duration: tk.fast,
            child:
                widget.content ??
                (blurSpoiler
                    ? blurArtwork(
                        OptimizedMediaImage(
                          client: widget.resolveClient(widget.item),
                          imagePath: path,
                          width: imageWidth,
                          height: imageHeight,
                          fit: BoxFit.cover,
                          imageType: MediaImageHelper.cardImageType(
                            widget.item,
                            widget.posterMode,
                            mixedHubContext: widget.mixedHub,
                          ),
                        ),
                      )
                    : OptimizedMediaImage(
                        client: widget.resolveClient(widget.item),
                        imagePath: path,
                        width: imageWidth,
                        height: imageHeight,
                        fit: BoxFit.cover,
                        imageType: MediaImageHelper.cardImageType(
                          widget.item,
                          widget.posterMode,
                          mixedHubContext: widget.mixedHub,
                        ),
                      )),
          ),
          // Whether a title has been watched is information, not
          // decoration: the design takes the caption away, and this is
          // the one thing under it that the caption never said anyway.
          if (widget.item.kind != MediaKind.artist) WatchedIndicator(item: widget.item),
          // Availability, requests, episode counts, when the next one
          // airs. Drawn from the same list the ordinary card draws, so
          // a title says the same thing on Explore whichever design is
          // on — these went missing here for as long as this tile had
          // its own idea of what a poster carries.
          if (widget.content == null) ...catalogPosterOverlays(widget.item.catalogItem),
        ],
      ),
    );
  }
}
