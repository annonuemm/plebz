import 'package:flutter/material.dart';

import '../focus/focus_theme.dart';
import '../media/media_hub.dart';
import '../media/media_item.dart';
import 'ocker_poster_tile.dart';
import 'ocker_skin.dart';

/// One long list of titles as a grid that wraps.
///
/// Wrapping is right here: a library, a watchlist or a search result is *one*
/// list, not a stack of sections, so there is nothing below it for a tall grid
/// to push off the page.
/// Six columns put eighteen titles on screen where a row showed six.
///
/// Focus follows §7: LEFT out of column one does nothing, UP out of the first
/// row leaves for the header, and a short last row is still reachable from
/// every column above it.
class OckerBrowseGrid extends StatefulWidget {
  final List<MediaItem> items;

  /// The section this grid stands for, only so the tiles have something to
  /// report to the detail panel. Its title becomes the eyebrow.
  final MediaHub hub;

  final OckerClientResolver resolveClient;

  /// OK on a tile.
  final void Function(MediaHub hub, MediaItem item) onPlay;

  /// Focus is leaving the top of the grid — §7 sends it to the header.
  final VoidCallback onExitUp;

  /// Off the left of the first column. Null swallows it; see
  /// [OckerPosterTile.onExitLeft].
  final VoidCallback? onExitLeft;

  /// The viewer has reached the last row; a paged list fetches more.
  final VoidCallback? onReachedEnd;

  const OckerBrowseGrid({
    super.key,
    required this.items,
    required this.hub,
    required this.resolveClient,
    required this.onPlay,
    required this.onExitUp,
    this.onExitLeft,
    this.onReachedEnd,
  });

  @override
  State<OckerBrowseGrid> createState() => OckerBrowseGridState();
}

class OckerBrowseGridState extends State<OckerBrowseGrid> {
  final Map<int, FocusNode> _nodes = {};
  final _scroll = ScrollController();

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(OckerBrowseGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length <= widget.items.length) return;
    // The list shrank — a filter, a removal. A node left behind for a position
    // that no longer exists is somewhere focus can be sent and not come back
    // from.
    for (final index in _nodes.keys.where((i) => i >= widget.items.length).toList()) {
      _nodes.remove(index)?.dispose();
    }
  }

  FocusNode _nodeFor(int index) => _nodes.putIfAbsent(index, () => FocusNode(debugLabel: 'ockerGrid:$index'));

  /// Puts focus on the first title — where someone arriving from the header
  /// expects to land.
  void focusFirstItem() {
    if (widget.items.isEmpty) return;
    _nodeFor(0).requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final scale = ockerScale(context);
    final gap = OckerLayout.tileGap * scale;

    // Measured, not worked out from the viewport. The arithmetic in
    // [ockerTileWidth] assumes this design owns the whole screen; on the app's
    // own layout a navigation rail has taken a strip of it first, and five
    // posters sized for the full width do not fit the column that is left.
    // The grid then wrapped at four while its focus arithmetic went on
    // counting in fives, which is what sent DOWN one place to the right.
    return LayoutBuilder(
      builder: (context, constraints) {
        final geometry = OckerGridGeometry.of(context, constraints.maxWidth);
        return _buildGrid(context, scale, gap, geometry.tileWidth, geometry.tileHeight, geometry.bleed);
      },
    );
  }

  Widget _buildGrid(BuildContext context, double scale, double gap, double tileWidth, double tileHeight, Offset bleed) {
    const columns = OckerLayout.gridColumns;

    // The scroll view is moved out by the room it keeps, so the room lies
    // outside the column and the first poster stands exactly where it always
    // stood — flush with the panel and the header above it.
    return Transform.translate(
      offset: Offset(-(bleed.dx - 1), -(bleed.dy - 1)),
      child: SingleChildScrollView(
        controller: _scroll,
        padding: EdgeInsets.only(
          bottom: OckerLayout.bottomFadeHeight * scale,
          left: bleed.dx,
          right: bleed.dx,
          top: bleed.dy,
        ),
        // Exactly five columns wide, and no wider. The focus arithmetic below
        // counts in fives; a Wrap left free in a roomier column could fit a
        // sixth, and every UP and DOWN would then land a row off.
        child: SizedBox(
          width: columns * tileWidth + gap * (columns - 1),
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (var i = 0; i < widget.items.length; i++)
                OckerPosterTile(
                  item: widget.items[i],
                  hub: widget.hub,
                  index: i,
                  itemCount: widget.items.length,
                  posterMode: OckerPosterTile.posterModeOf(context),
                  mixedHub: false,
                  hideSpoilers: OckerPosterTile.hideSpoilersOf(context),
                  tileWidth: tileWidth,
                  tileHeight: tileHeight,
                  focusNode: _nodeFor(i),
                  resolveClient: widget.resolveClient,
                  onPlay: () => widget.onPlay(widget.hub, widget.items[i]),
                  onFocused: () {
                    // Ask for the next page a row before the end, so the grid is
                    // never the thing the viewer is waiting on.
                    if (i >= widget.items.length - columns) widget.onReachedEnd?.call();
                  },
                  onExitUp: widget.onExitUp,
                  onExitDown: () {},
                  onExitLeft: widget.onExitLeft,
                  columns: columns,
                  neighbour: (delta) {
                    final next = i + delta;
                    if (next < 0 || next >= widget.items.length) return null;
                    return _nodeFor(next);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A grid of posters in a column [columnWidth] wide: how big a poster is, and
/// the room a focused one needs round it — the watchlist's grid and a
/// library's alike, so the two cannot come out different sizes again.
@immutable
class OckerGridGeometry {
  const OckerGridGeometry._({
    required this.columnWidth,
    required this.tileWidth,
    required this.tileHeight,
    required this.bleed,
  });

  factory OckerGridGeometry.of(BuildContext context, double columnWidth) {
    // What a focused tile draws past its own box: it grows by the theme's
    // focus scale — paint only, from its centre — and its ring sits outside
    // that. The grid's edge clips whatever reaches past it, and the tiles
    // along the top and the sides are the ones that reach: at the old one
    // pixel the ring vanished on those sides, and the lit edge of "Glas" lost
    // exactly its brightest stretch, top left.
    final growth = FocusTheme.focusScaleFor(context) - 1;
    final estimate = ockerTileWidthFor(context, columnWidth);
    final bleed = Offset(
      (estimate * growth / 2 + _ringReach).ceilToDouble(),
      (estimate * OckerLayout.tileHeight / OckerLayout.tileWidth * growth / 2 + _ringReach).ceilToDouble(),
    );
    // The room comes out of the tiles, not out of the page: they narrow by a
    // pixel or two so five still fit the same column.
    final tileWidth = ockerTileWidthFor(context, columnWidth - 2 * (bleed.dx - 1));
    return OckerGridGeometry._(
      columnWidth: columnWidth,
      tileWidth: tileWidth,
      tileHeight: tileWidth * OckerLayout.tileHeight / OckerLayout.tileWidth,
      bleed: bleed,
    );
  }

  /// How far past a tile its focus ring reaches — the widest ring any
  /// variant draws, "Glas"'s lit edge, with a pixel to spare.
  static const _ringReach = 2.5;

  final double columnWidth;
  final double tileWidth;
  final double tileHeight;

  /// The room kept round the posters for the one that holds focus. The grid
  /// stands this far out of its column, less a pixel, so its first poster
  /// sits one pixel in from the column's edge and the room lies outside it.
  final Offset bleed;

  /// The width of a poster over its height: the drawn 226 by 339.
  static const aspectRatio = OckerLayout.tileWidth / OckerLayout.tileHeight;

  /// Five posters and their four gaps.
  double gridWidth(BuildContext context) =>
      OckerLayout.gridColumns * tileWidth + OckerLayout.tileGap * ockerScale(context) * (OckerLayout.gridColumns - 1);

  @override
  bool operator ==(Object other) =>
      other is OckerGridGeometry &&
      other.columnWidth == columnWidth &&
      other.tileWidth == tileWidth &&
      other.tileHeight == tileHeight &&
      other.bleed == bleed;

  @override
  int get hashCode => Object.hash(columnWidth, tileWidth, tileHeight, bleed);
}

/// Room outside a column for a grid of posters that scrolls inside something
/// clipping it to that column — a library's tabs.
///
/// [OckerBrowseGrid] keeps the room a focused poster needs outside its column
/// by moving its scroll view out by as much. A library's grid scrolls inside
/// the tab view and a nested scroll view, which clip to the column, and could
/// only keep that room inside it: its first poster stood 8 px in and 6 px down
/// from where the watchlist's stands. This widens its child by the room
/// instead — left and above, and [trailing] to the right — so the grid inside
/// can keep it as padding and still begin where the watchlist's begins.
///
/// [enabled] false keeps the child in the column exactly. The widget stays in
/// the tree either way: taking it out would rebuild everything under it.
class OckerGridRoom extends StatelessWidget {
  const OckerGridRoom({super.key, required this.enabled, this.trailing = 0, required this.child});

  final bool enabled;

  /// Beyond the column's right edge: where a library's letter bar stands, so
  /// it stands beside the last column of posters rather than over it.
  final double trailing;

  final Widget child;

  /// The grid's measures and the room this widget gives, where it gives any.
  static OckerGridRoomData? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_OckerGridRoomScope>()?.data;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final data = enabled
            ? OckerGridRoomData(geometry: OckerGridGeometry.of(context, constraints.maxWidth), trailing: trailing)
            : null;
        return CustomSingleChildLayout(
          delegate: _OckerGridRoomLayout(data?.room ?? EdgeInsets.zero),
          child: _OckerGridRoomScope(data: data, child: child),
        );
      },
    );
  }
}

/// What [OckerGridRoom] tells the grid inside it.
@immutable
class OckerGridRoomData {
  const OckerGridRoomData({required this.geometry, required this.trailing});

  final OckerGridGeometry geometry;
  final double trailing;

  /// How far the child reaches past the column on each side.
  EdgeInsets get room => EdgeInsets.fromLTRB(geometry.bleed.dx - 1, geometry.bleed.dy - 1, trailing, 0);

  /// The padding that puts the grid where [OckerBrowseGrid] puts its own: the
  /// first poster a pixel in from the column's top left, five of them wide,
  /// whatever is left over at the right.
  EdgeInsets gridPadding(BuildContext context, {double bottom = 0}) {
    final bleed = geometry.bleed;
    final right = room.left + geometry.columnWidth + room.right - bleed.dx - geometry.gridWidth(context);
    return EdgeInsets.fromLTRB(bleed.dx, bleed.dy, right.clamp(0.0, double.infinity), bottom);
  }

  @override
  bool operator ==(Object other) =>
      other is OckerGridRoomData && other.geometry == geometry && other.trailing == trailing;

  @override
  int get hashCode => Object.hash(geometry, trailing);
}

class _OckerGridRoomScope extends InheritedWidget {
  const _OckerGridRoomScope({required this.data, required super.child});

  final OckerGridRoomData? data;

  @override
  bool updateShouldNotify(_OckerGridRoomScope oldWidget) => data != oldWidget.data;
}

class _OckerGridRoomLayout extends SingleChildLayoutDelegate {
  const _OckerGridRoomLayout(this.room);

  final EdgeInsets room;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => BoxConstraints.tight(
    Size(constraints.maxWidth + room.left + room.right, constraints.maxHeight + room.top + room.bottom),
  );

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(-room.left, -room.top);

  @override
  bool shouldRelayout(_OckerGridRoomLayout oldDelegate) => room != oldDelegate.room;
}
