import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../focus/dpad_navigator.dart';
import '../navigation/navigation_tabs.dart';
import '../theme/mono_tokens.dart';
import '../widgets/app_icon.dart';
import '../widgets/side_navigation_rail.dart' show SideNavigationRailState;
import 'ocker_skin.dart';
import 'ocker_submenu.dart';
import 'ocker_type.dart';

/// The destinations down the left, for "Redesign – Glas".
///
/// The standard theme's arrangement — a strip of symbols that opens into a
/// list of names while it holds focus — drawn in glass: the strip is bare, the
/// open list is a pane floating over the content, focus is the bright capsule
/// and the destination on show the quiet one washed with the accent, exactly
/// as on the band this replaces.
///
/// The same destinations, in the same order, as the band. What the band opened
/// as a sheet on a second press — Live TV's views and its channel management,
/// Explore's providers, Sport's leagues, a library's views, the watchlist's
/// lists — stands here as rows under the destination on show ([menuFor]): a
/// sheet rising from the bottom of the screen, away from the navigation it
/// was opened from, read as a second menu somewhere else. The libraries
/// themselves are not among them; they open beside the page.
///
/// It opens *over* the content rather than pushing it aside. The screens here
/// measure their columns from the room they are given; sliding them across
/// would re-lay every grid on the page twice for a glance at the menu.
class OckerSideRail extends StatefulWidget {
  /// The destinations to show, already filtered for offline and for features
  /// this install does not have.
  final List<NavigationTab> tabs;

  final NavigationTabId selectedTab;

  /// Open: the names beside the symbols, on a pane of glass. The host says
  /// so, because the host knows whether the navigation is where focus is.
  final bool expanded;

  final ValueChanged<NavigationTabId> onDestinationSelected;

  /// RIGHT, back into the content.
  final VoidCallback onNavigateToContent;

  /// SELECT on the destination already showing, where it has no rows to fold
  /// and that does something of its own — the libraries' column. Returns true
  /// when it handled the press.
  final bool Function(NavigationTabId)? onReselect;

  /// The rows listed under the destination on show while the rail is open.
  /// Asked on every build, so they follow the screen's state.
  final OckerRailMenu? Function(NavigationTabId)? menuFor;

  const OckerSideRail({
    super.key,
    required this.tabs,
    required this.selectedTab,
    required this.expanded,
    required this.onDestinationSelected,
    required this.onNavigateToContent,
    this.onReselect,
    this.menuFor,
  });

  /// The strip the rail keeps for itself while shut: the standard television
  /// rail's 48 on the 960-wide screen a television reports, and in proportion
  /// on any other — the symbols grow with the redesign's scale, and a strip
  /// that did not would stop fitting them.
  static double collapsedWidth(BuildContext context) => 96 * ockerScale(context);

  /// The open pane's width, in the same proportion.
  static double expandedWidth(BuildContext context) => 440 * ockerScale(context);

  /// The key of a destination's row, for tests.
  static Key itemKey(NavigationTabId id) => ValueKey('ocker_side_rail_${id.name}');

  /// The key of the [index]th row under the destination on show, for tests.
  static Key subItemKey(int index) => ValueKey('ocker_side_rail_sub_$index');

  /// The pane the open rail stands on, for tests.
  static const paneKey = Key('ocker_side_rail_pane');

  @override
  State<OckerSideRail> createState() => OckerSideRailState();
}

class OckerSideRailState extends State<OckerSideRail> {
  final Map<NavigationTabId, FocusNode> _nodes = {};

  /// The rows under the destination on show, by position.
  final List<FocusNode> _subNodes = [];

  /// The rows listed on the last build — what UP and DOWN walk.
  OckerRailMenu? _menu;

  /// Destinations whose rows the viewer folded away with a second press. Kept
  /// for as long as the app runs, as the standard rail keeps its sections.
  final Set<NavigationTabId> _folded = {};

  /// The rows showing under the destination on show, if any.
  OckerRailMenu? get _openMenu => _folded.contains(widget.selectedTab) ? null : _menu;

  FocusNode _nodeFor(NavigationTabId id) =>
      _nodes.putIfAbsent(id, () => FocusNode(debugLabel: 'ocker_side_rail_${id.name}'));

  FocusNode _subNodeFor(int index) {
    while (_subNodes.length <= index) {
      _subNodes.add(FocusNode(debugLabel: 'ocker_side_rail_sub_${_subNodes.length}'));
    }
    return _subNodes[index];
  }

  @override
  void initState() {
    super.initState();
    // A row's value can change behind the rail — a filter toggled, a sheet
    // opened from a row and closed again — and the rail is asked afresh
    // whenever the cursor moves while it is open.
    FocusManager.instance.addListener(_onFocusMoved);
  }

  void _onFocusMoved() {
    if (!mounted || !widget.expanded) return;
    setState(() {});
  }

  @override
  void didUpdateWidget(OckerSideRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A destination that went away (offline, a source disconnected) takes its
    // node with it: a node left behind is somewhere focus can be sent and not
    // come back from.
    final ids = widget.tabs.map((tab) => tab.id).toSet();
    for (final id in _nodes.keys.where((id) => !ids.contains(id)).toList()) {
      _nodes.remove(id)?.dispose();
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusMoved);
    for (final node in [..._nodes.values, ..._subNodes]) {
      node.dispose();
    }
    super.dispose();
  }

  /// Puts focus where someone arriving from the content expects to land: on
  /// the row on show under the destination — Plex under "Erkunden", the guide
  /// under "Live-TV" — where its rows are unfolded and one of them is, and on
  /// the destination itself otherwise. The viewer's call: landing on the
  /// destination left the choice they had made one press further away.
  void focusSelected() {
    final menu = widget.expanded ? _openMenu : null;
    final row = menu?.items.indexWhere((item) => item.selected) ?? -1;
    if (row < 0) return focusTab(widget.selectedTab);
    _subNodeFor(row).requestFocus();
  }

  void focusTab(NavigationTabId id) {
    final known = widget.tabs.any((tab) => tab.id == id);
    final target = known ? id : widget.tabs.firstOrNull?.id;
    if (target != null) _nodeFor(target).requestFocus();
  }

  /// Every row UP and DOWN can reach, top to bottom: the destinations, and the
  /// rows under the one on show.
  List<FocusNode> get _order => [
    for (final tab in widget.tabs) ...[
      _nodeFor(tab.id),
      if (tab.id == widget.selectedTab && widget.expanded)
        for (var i = 0; i < (_openMenu?.items.length ?? 0); i++) _subNodeFor(i),
    ],
  ];

  void _step(int delta) {
    final order = _order;
    final focused = order.indexWhere((node) => node.hasFocus);
    if (focused < 0) return;
    final next = focused + delta;
    // The ends stop rather than wrap: a column that wraps sends the cursor
    // from the bottom of the screen to the top on one press.
    if (next < 0 || next >= order.length) return;
    order[next].requestFocus();
  }

  /// SELECT on a destination. On the one already showing, with rows under
  /// it, a second press folds them away or back — the cursor stays where it
  /// is, and RIGHT is the way into the page. The viewer's call: going back
  /// into the page and shutting the rail was a second way to do what RIGHT
  /// already does, and no way at all to put the rows away.
  void _select(NavigationTabId id) {
    if (id == widget.selectedTab && _menu != null) {
      setState(() => _folded.contains(id) ? _folded.remove(id) : _folded.add(id));
      return;
    }
    if (id == widget.selectedTab && (widget.onReselect?.call(id) ?? false)) return;
    widget.onDestinationSelected(id);
  }

  void _selectSub(OckerRailItem item) {
    item.onSelect();
    // What the row changed — a filter switched, a view chosen — shows at
    // once, and again once the screen has rebuilt with it.
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  /// The keys every row shares; [onSelect] and [onLeft] are its own.
  KeyEventResult _onKey(KeyEvent event, {required VoidCallback onSelect, VoidCallback? onLeft}) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key.isUpKey) {
      _step(-1);
    } else if (key.isDownKey) {
      _step(1);
    } else if (key.isRightKey) {
      widget.onNavigateToContent();
    } else if (key.isLeftKey) {
      // The screen's edge for a destination; for a row under one, back up to
      // it.
      onLeft?.call();
    } else if (key.isSelectKey && event is KeyDownEvent) {
      onSelect();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    _menu = widget.menuFor?.call(widget.selectedTab);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: widget.expanded ? 1.0 : 0.0),
      duration: SideNavigationRailState.expandDuration,
      curve: SideNavigationRailState.expandCurve,
      builder: (context, t, _) => _buildAt(context, t),
    );
  }

  /// The rail [t] of the way open: 0 is the bare strip, 1 the pane.
  Widget _buildAt(BuildContext context, double t) {
    final tk = tokens(context);
    final scale = ockerScale(context);
    final collapsed = OckerSideRail.collapsedWidth(context);
    final margin = 16 * scale;
    final paneWidth = OckerSideRail.expandedWidth(context);
    final width = lerpDouble(collapsed, paneWidth + 2 * margin, t)!;
    final radius = BorderRadius.circular(tk.radiusSm + 8);
    final top = MediaQuery.paddingOf(context).top + ockerContentTop(context);
    final geometry = _RailGeometry(
      t: t,
      scale: scale,
      collapsedWidth: collapsed,
      paneLeft: margin * t,
      paneWidth: lerpDouble(collapsed, paneWidth, t)!,
      labelRight: margin + paneWidth,
    );
    final menu = _openMenu;

    return SizedBox(
      width: width,
      child: Stack(
        // Clipped to the width the rail has reached: the names are laid out
        // at their open width from the start and only come into view as the
        // rail opens, rather than being squeezed into a sliver of it.
        clipBehavior: Clip.hardEdge,
        children: [
          if (t > 0)
            Positioned(
              left: margin * t,
              top: margin * t,
              bottom: margin * t,
              width: lerpDouble(collapsed, paneWidth, t),
              child: Opacity(
                opacity: t.clamp(0.0, 1.0),
                // Nearly the whole ground, above even the reading strength
                // (ockerReadingGroundOpacity): the rail opens over a schedule,
                // and at .9 the guide's words still read through its names —
                // a second menu under the first.
                child: OckerGlass(
                  key: OckerSideRail.paneKey,
                  borderRadius: radius,
                  scrimInset: 0,
                  groundOpacity: 0.97,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            top: top,
            bottom: margin,
            child: SingleChildScrollView(
              clipBehavior: Clip.none,
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  for (final tab in widget.tabs) ...[
                    _RailItem(
                      key: OckerSideRail.itemKey(tab.id),
                      tab: tab,
                      geometry: geometry,
                      active: tab.id == widget.selectedTab,
                      // Rows to fold, and which way they are.
                      folding: tab.id == widget.selectedTab && _menu != null ? (menu != null) : null,
                      focusNode: _nodeFor(tab.id),
                      onKey: (event) => _onKey(event, onSelect: () => _select(tab.id)),
                      onTap: () => _select(tab.id),
                    ),
                    // Unfolding with the pane, so the destinations below make
                    // room as it opens rather than jumping. There, still
                    // folded shut, from the moment the rail is asked open:
                    // the cursor is put on one of them then, before the pane
                    // has begun to move.
                    if (tab.id == widget.selectedTab && menu != null && (t > 0 || widget.expanded))
                      ClipRect(
                        // Top left, not top centre: centred, the rows' block —
                        // as wide as the pane, narrower than the rail with its
                        // margin — slid right by half that margin.
                        child: Align(
                          alignment: Alignment.topLeft,
                          heightFactor: t.clamp(0.0, 1.0),
                          child: Column(
                            crossAxisAlignment: .start,
                            children: [
                              for (var i = 0; i < menu.items.length; i++) ...[
                                if (menu.items[i].gapBefore) SizedBox(height: 12 * scale),
                                _RailSubItem(
                                  key: OckerSideRail.subItemKey(i),
                                  item: menu.items[i],
                                  geometry: geometry,
                                  focusNode: _subNodeFor(i),
                                  onKey: (event) => _onKey(
                                    event,
                                    onSelect: () => _selectSub(menu.items[i]),
                                    onLeft: () => _nodeFor(tab.id).requestFocus(),
                                  ),
                                  onTap: () => _selectSub(menu.items[i]),
                                ),
                              ],
                              SizedBox(height: 8 * scale),
                            ],
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Where things stand in a rail [t] of the way open, shared by every row.
class _RailGeometry {
  const _RailGeometry({
    required this.t,
    required this.scale,
    required this.collapsedWidth,
    required this.paneLeft,
    required this.paneWidth,
    required this.labelRight,
  });

  final double t;
  final double scale;
  final double collapsedWidth;
  final double paneLeft;
  final double paneWidth;

  /// Where the open pane ends: the names are laid out against it at every
  /// stage of the opening, so nothing reflows as it moves.
  final double labelRight;

  double get inset => 10 * scale;
  double get iconSize => 44 * scale;
  double get rowHeight => 88 * scale;
  double get subRowHeight => 72 * scale;

  double get _shutCapsule => (collapsedWidth - 8).clamp(0.0, 80 * scale).toDouble();
  double get capsuleLeft => lerpDouble((collapsedWidth - _shutCapsule) / 2, paneLeft + inset, t)!;
  double get capsuleWidth => lerpDouble(_shutCapsule, paneWidth - 2 * inset, t)!;
  double get iconLeft => lerpDouble((collapsedWidth - iconSize) / 2, capsuleLeft + 22 * scale, t)!;
  double get labelLeft => iconLeft + iconSize + 22 * scale;
  double get labelWidth => (labelRight - inset - labelLeft - 16 * scale).clamp(0.0, double.infinity);
}

/// Scrolls a row the cursor has just reached into view: the list can run
/// taller than the screen once a destination's rows are open under it.
void _revealOnFocus(BuildContext context, bool hasFocus) {
  if (!hasFocus) return;
  Scrollable.ensureVisible(
    context,
    alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    alignment: 0.5,
    duration: const Duration(milliseconds: 120),
  );
}

/// One destination: its symbol, and — as the rail opens — its name.
class _RailItem extends StatefulWidget {
  const _RailItem({
    super.key,
    required this.tab,
    required this.geometry,
    required this.active,
    required this.folding,
    required this.focusNode,
    required this.onKey,
    required this.onTap,
  });

  final NavigationTab tab;
  final _RailGeometry geometry;
  final bool active;

  /// Whether the rows under it are open, where it has any; null where it has
  /// none.
  final bool? folding;
  final FocusNode focusNode;
  final KeyEventResult Function(KeyEvent event) onKey;
  final VoidCallback onTap;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final type = OckerType.of(context);
    final g = widget.geometry;
    final scale = g.scale;
    final height = g.rowHeight;
    final capsuleHeight = lerpDouble(64 * scale, height - 8 * scale, g.t)!;
    final lit = _focused || widget.active;

    return Semantics(
      button: true,
      selected: widget.active,
      label: widget.tab.getLabel(),
      child: Focus(
        focusNode: widget.focusNode,
        onKeyEvent: (_, event) => widget.onKey(event),
        onFocusChange: (has) {
          setState(() => _focused = has);
          _revealOnFocus(context, has);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: SizedBox(
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (_focused || widget.active)
                  Positioned(
                    left: g.capsuleLeft,
                    width: g.capsuleWidth,
                    top: (height - capsuleHeight) / 2,
                    height: capsuleHeight,
                    child: OckerGlassFocusFill(
                      shape: const StadiumBorder(),
                      bright: _focused,
                      tint: widget.active ? 1 : 0,
                    ),
                  ),
                Positioned(
                  left: g.iconLeft,
                  top: (height - g.iconSize) / 2,
                  child: OckerInk(
                    color: lit ? tk.ink(1) : tk.ink(0.55),
                    builder: (context, ink) => AppIcon(
                      widget.tab.icon,
                      size: g.iconSize,
                      fill: navIconFill,
                      weight: navIconWeight,
                      color: ink,
                    ),
                  ),
                ),
                if (g.t > 0)
                  Positioned(
                    left: g.labelLeft,
                    width: g.labelWidth,
                    top: 0,
                    bottom: 0,
                    child: Opacity(
                      opacity: g.t.clamp(0.0, 1.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: OckerInk(
                              color: lit ? tk.ink(1) : tk.ink(0.55),
                              builder: (context, ink) => Text(
                                widget.tab.getLabel(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                                style: type.navWord(active: widget.active).copyWith(fontSize: 26 * scale, color: ink),
                              ),
                            ),
                          ),
                          // Pressing this one again folds its rows, and it
                          // says which way.
                          if (widget.folding case final open?)
                            AppIcon(
                              open ? Symbols.expand_less_rounded : Symbols.expand_more_rounded,
                              size: 30 * scale,
                              color: lit ? tk.ink(0.72) : tk.ink(0.35),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One row under the destination on show: a view, a list, an action.
///
/// A tile under the destination's capsule, a step smaller, its words flush
/// with the destination's name and its symbol in the column of symbols.
class _RailSubItem extends StatefulWidget {
  const _RailSubItem({
    super.key,
    required this.item,
    required this.geometry,
    required this.focusNode,
    required this.onKey,
    required this.onTap,
  });

  final OckerRailItem item;
  final _RailGeometry geometry;
  final FocusNode focusNode;
  final KeyEventResult Function(KeyEvent event) onKey;
  final VoidCallback onTap;

  @override
  State<_RailSubItem> createState() => _RailSubItemState();
}

class _RailSubItemState extends State<_RailSubItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final type = OckerType.of(context);
    final g = widget.geometry;
    final scale = g.scale;
    final height = g.subRowHeight;
    final item = widget.item;
    final lit = _focused || item.selected;
    // A tile under the destination's capsule, the same small room either side,
    // its words starting where the destination's name starts and its symbol —
    // where it has one — in the destination's column of symbols. The viewer's
    // calls, in turn: the tile centred rather than pushed to the right, and
    // the words not centred in it but flush with the name above.
    final indent = 12 * scale;
    final tileLeft = g.capsuleLeft + indent;
    final tileWidth = (g.capsuleWidth - 2 * indent).clamp(0.0, double.infinity).toDouble();
    final glyphSize = 30 * scale;
    final glyph =
        item.leading ??
        (item.icon == null
            ? null
            : OckerInk(
                color: lit ? tk.ink(0.9) : tk.ink(0.5),
                // Outlines, as the destinations' symbols are: a filled glyph
                // under them read as the one standing out.
                builder: (context, ink) =>
                    AppIcon(item.icon!, size: glyphSize, fill: navIconFill, weight: navIconWeight, color: ink),
              ));

    return Semantics(
      button: true,
      selected: item.selected,
      label: item.label,
      child: Focus(
        focusNode: widget.focusNode,
        onKeyEvent: (_, event) => widget.onKey(event),
        onFocusChange: (has) {
          setState(() => _focused = has);
          _revealOnFocus(context, has);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: SizedBox(
            height: height,
            width: g.labelRight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (_focused || item.selected)
                  Positioned(
                    left: tileLeft,
                    width: tileWidth,
                    top: 4 * scale,
                    bottom: 4 * scale,
                    child: OckerGlassFocusFill(
                      shape: const StadiumBorder(),
                      bright: _focused,
                      tint: item.selected ? 1 : 0,
                    ),
                  ),
                if (glyph != null)
                  Positioned(
                    left: g.iconLeft + (g.iconSize - glyphSize) / 2,
                    top: (height - glyphSize) / 2,
                    width: glyphSize,
                    height: glyphSize,
                    child: FittedBox(child: glyph),
                  ),
                Positioned(
                  left: g.labelLeft,
                  width: g.labelWidth,
                  top: 0,
                  bottom: 0,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OckerInk(
                      color: lit ? tk.ink(1) : tk.ink(0.62),
                      builder: (context, ink) => Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: type.navWord(active: item.selected).copyWith(fontSize: 22 * scale, color: ink),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
