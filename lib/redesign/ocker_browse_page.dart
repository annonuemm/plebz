import 'package:flutter/material.dart';

import '../media/media_hub.dart';
import '../media/media_item.dart';
import '../theme/mono_tokens.dart';
import '../widgets/focusable_tab_chip.dart' show TabChipStrip;
import 'ocker_browse_grid.dart';
import 'ocker_detail_panel.dart';
import 'ocker_filter_glyph.dart';
import 'ocker_focus_bus.dart';
import 'ocker_section_heading.dart';
import 'ocker_skin.dart';
import 'ocker_type.dart';

/// A page of one long list: the watchlist, a library, a search result, a hub.
///
/// Quiet tiles in a grid, and beside them, on the right, a panel that
/// describes whatever holds focus. A grid rather than a row, because there is
/// only one list and nothing underneath it for a tall grid to push away.
///
/// The filters stand on a band over the grid's top left, and the count sits
/// at the foot: `18 VON 428`. Between them the viewer can see both what is
/// being narrowed and how much is left. Not on the watchlist ([showCount]).
class OckerBrowsePage extends StatefulWidget {
  final String title;
  final List<MediaItem> items;

  /// How many the server says there are, when that is more than are loaded.
  final int? totalCount;

  final OckerClientResolver resolveClient;
  final void Function(MediaHub hub, MediaItem item) onPlay;

  /// Up out of the first row: the host's filters, or the navigation.
  final VoidCallback onExitToHeader;

  /// Off the left of the first column, where the navigation is over there.
  /// Null swallows it; see [OckerPosterTile.onExitLeft].
  final VoidCallback? onExitLeft;

  final VoidCallback? onReachedEnd;

  /// Sort and filter, on the band over the grid's top left.
  final List<Widget> filters;

  /// Shown instead of the grid when there is nothing to show.
  final Widget? emptyState;

  /// The host's own switcher, leading the line over the grid — Seerr's films
  /// and series. Null when this list has nothing to be switched between.
  final Widget? header;

  /// Whether to name the section above the grid.
  ///
  /// False where the navigation already says where you are: on a destination
  /// like the watchlist the rail has "Merkliste" lit up, and repeating it in
  /// mono over the grid says the same thing twice. A page pushed on top of
  /// another has no such cue and keeps its heading.
  final bool showHeading;

  /// Whether the count stands at the foot, under a hairline. Not on the
  /// watchlist, the viewer's call: a library, the page it is laid out like,
  /// has none.
  final bool showCount;

  /// Which list this is, over the right of the grid — see
  /// [OckerGridFilterBand.location]. Null where the page names itself.
  final String? location;

  const OckerBrowsePage({
    super.key,
    required this.title,
    required this.items,
    required this.resolveClient,
    required this.onPlay,
    required this.onExitToHeader,
    this.onExitLeft,
    this.totalCount,
    this.onReachedEnd,
    this.filters = const [],
    this.emptyState,
    this.header,
    this.showHeading = true,
    this.showCount = true,
    this.location,
  });

  @override
  State<OckerBrowsePage> createState() => OckerBrowsePageState();
}

class OckerBrowsePageState extends State<OckerBrowsePage> {
  final _bus = OckerFocusBus();
  final _gridKey = GlobalKey<OckerBrowseGridState>();
  @override
  void dispose() {
    _bus.dispose();
    super.dispose();
  }

  /// Where focus stood when [focusFirstItem] was asked for before there was
  /// a first title — the list still loading. It is honoured once the titles
  /// arrive, but only if focus has not moved on in the meantime.
  FocusNode? _firstItemFrom;
  bool _firstItemPending = false;

  /// Puts focus on the first title, for whoever comes into the page — or,
  /// while the list is still loading, as soon as it is there.
  void focusFirstItem() {
    final grid = _gridKey.currentState;
    if (widget.items.isEmpty || grid == null) {
      _firstItemPending = true;
      _firstItemFrom = FocusManager.instance.primaryFocus;
      return;
    }
    _firstItemPending = false;
    grid.focusFirstItem();
  }

  @override
  void didUpdateWidget(OckerBrowsePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_firstItemPending || widget.items.isEmpty) return;
    _firstItemPending = false;
    final from = _firstItemFrom;
    _firstItemFrom = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final now = FocusManager.instance.primaryFocus;
      if (now != null && now != from) return;
      _gridKey.currentState?.focusFirstItem();
    });
  }

  /// Up and out of the grid, to whatever the host arranged.
  void _exitToHeader() {
    _bandReturn = FocusManager.instance.primaryFocus;
    widget.onExitToHeader();
  }

  /// Where the cursor left the grid for the filters over it — for DOWN off
  /// them to come back to, rather than to the first title.
  FocusNode? _bandReturn;

  /// Back into the grid from the filters: where the cursor left it, or the
  /// first title.
  void focusGridFromBand() {
    final node = _bandReturn;
    _bandReturn = null;
    if (node != null && node.context != null && node.canRequestFocus) {
      node.requestFocus();
      return;
    }
    focusFirstItem();
  }

  /// The list, as a hub, so the tiles have something to report to the panel
  /// and the panel has an eyebrow to write.
  MediaHub get _hub => MediaHub(
    id: 'ocker:${widget.title}',
    title: widget.title,
    type: 'mixed',
    items: widget.items,
    size: widget.totalCount ?? widget.items.length,
  );

  void _describeFirstIfIdle() {
    if (_bus.value != null || widget.items.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _bus.value != null) return;
      _bus.report(OckerFocused(item: widget.items.first, hub: _hub, index: 0));
    });
  }

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final scale = ockerScale(context);
    _describeFirstIfIdle();

    return OckerFocusScope(
      bus: _bus,
      // No fill of its own: the page sits on the glass ground — the shell's,
      // or the route's when it is pushed — and a flat fill here covered it.
      child: Padding(
        // Margins on both sides: a grid ends, and taking its right margin
        // away would only have stretched its columns into wider posters than
        // every other screen's. The narrow inset goes where the content meets
        // the rail, the design's margin to the far edge.
        padding: EdgeInsets.fromLTRB(
          ockerFlushLeftInset(context),
          ockerContentTop(context),
          OckerLayout.safeMargin * scale,
          0,
        ),
        // The describing column stands on the right, from the top; the
        // filters, or a host's own row, over the grid.
        child: Row(
          crossAxisAlignment: .start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  _buildChrome(scale),
                  Expanded(child: _buildContentColumn(tk, scale)),
                ],
              ),
            ),
            SizedBox(width: OckerLayout.rowGutter * scale),
            OckerDetailPanel(resolveClient: widget.resolveClient, width: ockerGridPanelWidth(context)),
          ],
        ),
      ),
    );
  }

  /// What stands over the grid's top left: the filters on their band, and —
  /// where the host has one — its own switcher leading the line.
  Widget _buildChrome(double scale) {
    final header = widget.header;
    if (header == null) {
      return widget.filters.isEmpty
          ? const SizedBox.shrink()
          : OckerGridFilterBand(location: widget.location, children: widget.filters);
    }
    // The switcher's pane reaches past its row; set in by as much, its edge
    // lines up with the posters' below, as the filters' does.
    final overhang = ockerGlass(context) ? TabChipStrip.overhangOf(context) : EdgeInsets.zero;
    return Padding(
      padding: EdgeInsets.only(bottom: OckerGridFilterBand.gapBelow * scale),
      child: Row(
        children: [
          Flexible(
            child: Padding(
              padding: EdgeInsets.only(left: overhang.left),
              child: header,
            ),
          ),
          if (widget.filters.isNotEmpty) ...[
            SizedBox(width: overhang.right + 14 * scale),
            OckerGridFilterBand(withGapBelow: false, children: widget.filters),
          ],
        ],
      ),
    );
  }

  Widget _buildContentColumn(MonoTokens tk, double scale) {
    final type = OckerType.of(context);
    final total = widget.totalCount ?? widget.items.length;

    return Column(
      crossAxisAlignment: .start,
      children: [
        // A page the navigation already names does not name itself again; a
        // page pushed on top of another has no such cue and keeps its heading.
        if (widget.showHeading) ...[OckerSectionHeading(title: widget.title), SizedBox(height: 22 * scale)],
        Expanded(
          child: widget.items.isEmpty
              ? (widget.emptyState ?? const SizedBox.shrink())
              : Stack(
                  children: [
                    OckerBrowseGrid(
                      key: _gridKey,
                      items: widget.items,
                      hub: _hub,
                      resolveClient: widget.resolveClient,
                      onPlay: widget.onPlay,
                      onExitUp: _exitToHeader,
                      onExitLeft: widget.onExitLeft,
                      onReachedEnd: widget.onReachedEnd,
                    ),
                  ],
                ),
        ),
        if (widget.showCount && widget.items.isNotEmpty) ...[
          Container(height: 1, color: tk.ink(0.12)),
          SizedBox(height: 12 * scale),
          Text(
            total > widget.items.length ? '${widget.items.length} / $total' : '${widget.items.length}',
            style: type.counter.copyWith(color: tk.ink(0.35)),
          ),
          SizedBox(height: 16 * scale),
        ],
      ],
    );
  }
}
