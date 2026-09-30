import 'package:flutter/material.dart';

import '../focus/dpad_navigator.dart';
import '../focus/key_event_utils.dart';
import '../media/media_library.dart';
import '../navigation/main_screen_scope.dart';
import '../screens/libraries/library_server_label.dart';
import '../services/device_performance.dart';
import '../theme/mono_tokens.dart';
import '../widgets/focusable_list_tile.dart';
import 'ocker_skin.dart';
import 'ocker_type.dart';

/// The libraries, as a column that opens beside a library page — the way the
/// channel groups open beside the guide.
///
/// The standard rail hangs the libraries under its own entry, which in a rail
/// that opens over the content is fifteen names the viewer has to walk past
/// to reach Live TV. Here they
/// belong to the page they switch: LEFT out of its first column opens them,
/// as it opens the groups on the guide, and so does a second press on
/// "Mediatheken" in the rail.
///
/// It lies *over* the page rather than pushing it across. The groups can push
/// the guide, which only gets narrower; a library's grid would re-lay every
/// poster, twice, for a choice that replaces the whole page anyway.
///
/// Ways out, as on the guide's column: SELECT chooses and closes, RIGHT closes
/// and goes back to where the cursor came from, LEFT and BACK go on to the
/// rail, and focus leaving it any other way closes it too.
class OckerLibraryColumn extends StatefulWidget {
  const OckerLibraryColumn({
    super.key,
    required this.libraries,
    required this.selectedKey,
    required this.groupByServer,
    required this.onSelected,
    required this.onFocusContent,
    required this.child,
  });

  /// The libraries on offer — the hidden ones are not.
  final List<MediaLibrary> libraries;

  /// The library on show, where the column opens.
  final String? selectedKey;

  /// Group the list under its servers, as the viewer's setting says.
  final bool groupByServer;

  /// SELECT on a library other than the one on show.
  final ValueChanged<String> onSelected;

  /// Put the cursor back into the page, when the place it came from is gone.
  final VoidCallback onFocusContent;

  /// The page the column lies over.
  final Widget child;

  /// The pane, for tests.
  static const paneKey = Key('ocker_library_column_pane');

  /// A library's row, for tests.
  static Key rowKey(String globalKey) => ValueKey('ocker_library_column_$globalKey');

  @override
  State<OckerLibraryColumn> createState() => OckerLibraryColumnState();
}

/// Lets whatever a library page draws open the column from its left edge.
class OckerLibraryColumnScope extends InheritedWidget {
  const OckerLibraryColumnScope({super.key, required this.column, required super.child});

  final OckerLibraryColumnState column;

  /// Opens the libraries beside the page, where the page has them. False
  /// where it has none — every theme but the redesign — so the
  /// caller goes on to wherever LEFT went before.
  static bool open(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<OckerLibraryColumnScope>();
    return scope?.column.open() ?? false;
  }

  @override
  bool updateShouldNotify(OckerLibraryColumnScope oldWidget) => !identical(column, oldWidget.column);
}

class OckerLibraryColumnState extends State<OckerLibraryColumn> {
  final Map<String, FocusNode> _nodes = {};
  final _scroll = ScrollController();

  bool _open = false;

  /// Whether the cursor has been inside yet: not on the frame between opening
  /// and focusing a row, when a "focus left the column" rule would close it
  /// before anyone saw it.
  bool _hadFocus = false;

  /// Where the cursor was when the column opened, for RIGHT to go back to.
  FocusNode? _cameFrom;

  bool get isOpen => _open;

  FocusNode _nodeFor(String key) => _nodes.putIfAbsent(key, () => FocusNode(debugLabel: 'ocker_library_column_$key'));

  @override
  void didUpdateWidget(OckerLibraryColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    final keys = widget.libraries.map((library) => library.globalKey).toSet();
    for (final key in _nodes.keys.where((key) => !keys.contains(key)).toList()) {
      _nodes.remove(key)?.dispose();
    }
  }

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  /// Opens the column on the library on show. False when there is nothing to
  /// choose between.
  bool open() {
    if (widget.libraries.isEmpty) return false;
    if (!_open) {
      final from = FocusManager.instance.primaryFocus;
      // Only a place inside the page is somewhere to come back to: opened from
      // the rail, RIGHT goes into the page, not back onto the rail.
      _cameFrom = from != null && _isInsidePage(from) ? from : null;
      _hadFocus = false;
      setState(() => _open = true);
    }
    _focusChosen(attempt: 0);
    return true;
  }

  bool _isInsidePage(FocusNode node) {
    final nodeContext = node.context;
    if (nodeContext == null || !nodeContext.mounted) return false;
    return nodeContext.findAncestorStateOfType<OckerLibraryColumnState>() == this;
  }

  /// The row of the library on show — or the first — once the column has its
  /// width and the row is no longer shut out of focus.
  void _focusChosen({required int attempt}) {
    WidgetsBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_open) return;
      final key = widget.libraries.any((library) => library.globalKey == widget.selectedKey)
          ? widget.selectedKey!
          : widget.libraries.first.globalKey;
      final node = _nodeFor(key);
      final rowContext = node.context;
      if (rowContext == null || !node.canRequestFocus) {
        if (attempt < 3) _focusChosen(attempt: attempt + 1);
        return;
      }
      Scrollable.ensureVisible(rowContext, alignment: 0.5);
      node.requestFocus();
    });
  }

  void _close({required bool returnFocus}) {
    if (!_open) return;
    _hadFocus = false;
    setState(() => _open = false);
    final from = _cameFrom;
    _cameFrom = null;
    if (!returnFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (from != null && from.context != null && from.canRequestFocus) {
        from.requestFocus();
        return;
      }
      widget.onFocusContent();
    });
  }

  void _choose(String key) {
    _close(returnFocus: key == widget.selectedKey);
    if (key != widget.selectedKey) widget.onSelected(key);
  }

  /// On to the rail: the column sits right beside it, and stepping off its
  /// left edge should feel like stepping onto it.
  void _leaveForNavigation() {
    _close(returnFocus: false);
    MainScreenFocusScope.focusSidebarOf(context);
  }

  void _onFocusChange(bool hasFocus) {
    if (hasFocus) {
      _hadFocus = true;
      return;
    }
    if (!_hadFocus || !_open) return;
    // It has already gone wherever it went; nothing to hand back.
    _close(returnFocus: false);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event.logicalKey.isBackKey) return handleBackKeyAction(event, _leaveForNavigation);
    if (!event.isActionable) return KeyEventResult.ignored;
    if (event.logicalKey.isLeftKey) {
      _leaveForNavigation();
      return KeyEventResult.handled;
    }
    if (event.logicalKey.isRightKey) {
      _close(returnFocus: true);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// A quarter of the screen within reason, as the guide's column: room for a
  /// library's name, and the page still in view beside it.
  double _width(BuildContext context) => (MediaQuery.sizeOf(context).width * 0.22).clamp(220.0, 360.0).toDouble();

  @override
  Widget build(BuildContext context) {
    return OckerLibraryColumnScope(
      column: this,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          Positioned(left: 0, top: 0, bottom: 0, child: _buildColumn(context)),
        ],
      ),
    );
  }

  Widget _buildColumn(BuildContext context) {
    final tk = tokens(context);
    final scale = ockerScale(context);
    final width = _width(context);
    final radius = BorderRadius.circular(tk.radiusSm + 8);
    final rows = buildLibraryServerEntries<Widget>(
      widget.libraries,
      groupByServer: widget.groupByServer,
      buildHeader: (library, fallbackServerName) => Padding(
        padding: EdgeInsets.fromLTRB(26 * scale, 22 * scale, 26 * scale, 8 * scale),
        child: LibraryServerLabel(
          library: library,
          fallbackServerName: fallbackServerName,
          badgeSize: 13 * scale,
          style: OckerType.of(context).sourceLabel.copyWith(color: tk.ink(0.45)),
          uppercase: true,
          constrainText: true,
        ),
      ),
      buildItem: (library, {required bool showServerName}) => Padding(
        // Under glass the marks are panes, and a pane wants air round it.
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: FocusableListTile(
          key: OckerLibraryColumn.rowKey(library.globalKey),
          focusNode: _nodeFor(library.globalKey),
          selected: library.globalKey == widget.selectedKey,
          glassMarks: true,
          title: Text(library.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: showServerName
              ? LibraryServerLabel(
                  library: library,
                  badgeSize: 10,
                  style: TextStyle(color: tk.ink(0.5)),
                  constrainText: true,
                )
              : null,
          onTap: () => _choose(library.globalKey),
        ),
      ),
    );

    // Every row built, not just the ones in view: a library list is short,
    // and a row the list has not built is one the cursor cannot be put on —
    // the trap the guide's column had to be taught its way round.
    final list = Material(
      type: MaterialType.transparency,
      child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: .stretch, children: rows),
      ),
    );

    return AnimatedContainer(
      duration: DevicePerformance.reducedDuration(const Duration(milliseconds: 180)),
      curve: Curves.easeOutCubic,
      width: _open ? width : 0,
      // Clipped rather than laid out narrower: the rows keep their width and
      // slide in instead of squeezing.
      child: ClipRect(
        // Shut, the rows are still there and still focusable, and the cursor
        // could walk into a column nobody can see.
        child: ExcludeFocus(
          excluding: !_open,
          child: OverflowBox(
            alignment: .centerLeft,
            minWidth: width,
            maxWidth: width,
            child: Focus(
              onFocusChange: _onFocusChange,
              onKeyEvent: _onKey,
              child: Padding(
                padding: EdgeInsets.fromLTRB(12 * scale, ockerContentTop(context) + 12 * scale, 12 * scale, 12 * scale),
                child: OckerGlass(
                  key: OckerLibraryColumn.paneKey,
                  borderRadius: radius,
                  scrimInset: 0,
                  child: ClipRRect(borderRadius: radius, child: list),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
