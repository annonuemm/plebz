import 'dart:async';

import 'package:flutter/material.dart';

import '../../focus/dpad_navigator.dart';
import '../../focus/input_mode_tracker.dart';
import '../../focus/key_event_utils.dart';
import '../../redesign/ocker_skin.dart';
import '../../redesign/ocker_type.dart';
import '../../theme/mono_tokens.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/desktop_app_bar.dart';
import '../../widgets/focusable_list_tile.dart';
import '../../widgets/setting_tile.dart';
import '../../widgets/settings_section.dart';
import '../../widgets/system_bottom_inset.dart';

/// One topic of the settings (Plebz): a row in the column, its page beside it.
class PlebzSettingsSection {
  const PlebzSettingsSection({
    required this.id,
    required this.group,
    required this.icon,
    required this.title,
    required this.page,
    this.subtitle,
  });

  final String id;

  /// The heading the topic stands under in the column.
  final String group;
  final IconData icon;
  final String title;

  /// Said under the title on the phone's list; the column shows titles only.
  final String? subtitle;

  /// The topic's page — a whole settings page with its own title, as a phone
  /// pushes it. Built with the context it is shown in, so whatever it watches
  /// rebuilds it there.
  final WidgetBuilder page;
}

/// The settings (Plebz): every topic in a column down the left, the chosen
/// one's page beside it — so the whole of it is in view at once, and nothing
/// is more than one step in.
///
/// Walking the column shows each topic's page at once; RIGHT or SELECT goes
/// into it, and LEFT or BACK at its edge comes back to the column. What a page
/// opens — a sub-page, a source to edit — opens beside the column too, in the
/// page's own navigator, so the column stays where it is.
///
/// Too narrow for two columns (a phone), the column is the page, and a topic
/// opens as a page of its own.
///
/// Under the redesign the column is the redesign's: a pane like its library
/// column, focus and the topic on show marked as in its menus (white fill and
/// the accent's stroke under "Flach", glass under "Glas").
class PlebzSettingsShell extends StatefulWidget {
  const PlebzSettingsShell({super.key, required this.title, required this.sections, required this.onExitLeft});

  final String title;
  final List<PlebzSettingsSection> sections;

  /// LEFT off the column: on to the app's navigation.
  final VoidCallback onExitLeft;

  /// Below this width the column is a page of its own.
  static const twoPaneMinWidth = 720.0;

  /// A topic's row in the column, for tests.
  static Key rowKey(String id) => ValueKey('plebz_settings_section_$id');

  @override
  State<PlebzSettingsShell> createState() => PlebzSettingsShellState();
}

class PlebzSettingsShellState extends State<PlebzSettingsShell> {
  final _columnScope = FocusScopeNode(debugLabel: 'settings_column');
  final _paneScope = FocusScopeNode(debugLabel: 'settings_pane');
  final _paneNavigator = GlobalKey<NavigatorState>();
  final _columnScroll = ScrollController();
  final _rowNodes = <String, FocusNode>{};

  /// Bumped after every rebuild, for the pages a phone pushes: they are routes
  /// of their own, which this widget's rebuilds do not reach.
  final _revision = ValueNotifier<int>(0);

  String? _selectedId;

  /// Whether the cursor has gone into the page. Until then the page cannot
  /// take focus, so a page shown while the column is walked never pulls the
  /// cursor across.
  bool _paneActive = false;
  Timer? _showTimer;
  bool _twoPane = true;

  PlebzSettingsSection get _selected =>
      widget.sections.firstWhere((s) => s.id == _selectedId, orElse: () => widget.sections.first);

  FocusNode _nodeFor(String id) => _rowNodes.putIfAbsent(id, () => FocusNode(debugLabel: 'settings_section_$id'));

  @override
  void didUpdateWidget(PlebzSettingsShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _revision.value++);
  }

  @override
  void dispose() {
    _showTimer?.cancel();
    _columnScope.dispose();
    _paneScope.dispose();
    _columnScroll.dispose();
    for (final node in _rowNodes.values) {
      node.dispose();
    }
    _revision.dispose();
    super.dispose();
  }

  /// The cursor onto the topic on show — the way in from the navigation.
  void focusColumn() {
    if (!_twoPane) {
      _nodeFor(_selected.id).requestFocus();
      return;
    }
    if (_paneActive) setState(() => _paneActive = false);
    _nodeFor(_selected.id).requestFocus();
  }

  void _show(String id) {
    _showTimer?.cancel();
    if (id == _selectedId) return;
    setState(() => _selectedId = id);
  }

  /// A row taking focus shows its page once the cursor rests there, so
  /// walking past a heavy page does not build it on the way.
  void _onRowFocus(String id, bool focused) {
    if (!focused || !_twoPane) return;
    _showTimer?.cancel();
    _showTimer = Timer(const Duration(milliseconds: 120), () {
      if (mounted) _show(id);
    });
  }

  void _choose(PlebzSettingsSection section) {
    if (!_twoPane) {
      _push(section);
      return;
    }
    _show(section.id);
    if (InputModeTracker.isKeyboardMode(context, listen: false)) _enterPane();
  }

  void _push(PlebzSettingsSection section) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ValueListenableBuilder<int>(
          valueListenable: _revision,
          builder: (context, _, _) {
            final current = widget.sections.where((s) => s.id == section.id).firstOrNull ?? section;
            return current.page(context);
          },
        ),
      ),
    );
  }

  void _enterPane() {
    _showTimer?.cancel();
    final focused = FocusManager.instance.primaryFocus;
    final row = _rowNodes.entries.where((e) => e.value == focused).firstOrNull;
    if (row != null && row.key != _selectedId) setState(() => _selectedId = row.key);
    setState(() => _paneActive = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_paneActive) return;
      // Back where the cursor last was in the page, if that is still there;
      // otherwise its first row.
      FocusScopeNode scope = _paneScope;
      while (scope.focusedChild is FocusScopeNode) {
        scope = scope.focusedChild! as FocusScopeNode;
      }
      final remembered = scope.focusedChild;
      if (remembered != null && remembered.canRequestFocus) {
        remembered.requestFocus();
        return;
      }
      scope.requestFocus();
      scope.nextFocus();
    });
  }

  void _leavePane() {
    setState(() => _paneActive = false);
    _nodeFor(_selected.id).requestFocus();
  }

  KeyEventResult _onColumnKey(FocusNode _, KeyEvent event) {
    if (!event.isActionable) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key.isLeftKey) {
      widget.onExitLeft();
      return KeyEventResult.handled;
    }
    if (key.isRightKey) {
      if (_twoPane) _enterPane();
      return KeyEventResult.handled;
    }
    // UP and DOWN walk the rows and stop at either end: past them there is
    // nothing in this column, and traversal would go looking beside it.
    if (key.isUpKey || key.isDownKey) {
      final order = [for (final s in widget.sections) s.id];
      final at = order.indexWhere((id) => _rowNodes[id] == FocusManager.instance.primaryFocus);
      if (at < 0) return KeyEventResult.ignored;
      final next = at + (key.isDownKey ? 1 : -1);
      if (next < 0 || next >= order.length) return KeyEventResult.handled;
      final node = _nodeFor(order[next]);
      node.requestFocus();
      if (node.context case final rowContext?) {
        Scrollable.ensureVisible(
          rowContext,
          alignmentPolicy: next > at
              ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
              : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        );
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onPaneKey(FocusNode _, KeyEvent event) {
    if (!_paneActive) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key.isBackKey) {
      // A sub-page that does not close itself on BACK is closed here; the
      // topic's own page hands the cursor back to the column.
      final navigator = _paneNavigator.currentState;
      if (navigator != null && navigator.canPop()) {
        return handleBackKeyAction(event, () => navigator.maybePop());
      }
      return handleBackKeyAction(event, _leavePane);
    }
    // A field being typed in keeps its arrows for the caret.
    if (event.isActionable && key.isLeftKey && !isTextEditingFocused()) {
      // A row of buttons in the page walks left first; off its edge is the
      // column.
      final focused = FocusManager.instance.primaryFocus;
      if (focused != null && focused.focusInDirection(TraversalDirection.left)) return KeyEventResult.handled;
      _leavePane();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _twoPane = constraints.maxWidth >= PlebzSettingsShell.twoPaneMinWidth;
        return _twoPane ? _buildTwoPane(context, constraints.maxWidth) : _buildList(context);
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Two panes

  Widget _buildTwoPane(BuildContext context, double width) {
    final columnWidth = (width * 0.27).clamp(240.0, 340.0).toDouble();
    final keyboard = InputModeTracker.isKeyboardMode(context);
    final section = _selected;
    return Row(
      crossAxisAlignment: .stretch,
      children: [
        SizedBox(width: columnWidth, child: _buildColumn(context)),
        Expanded(
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: _onPaneKey,
            child: ExcludeFocus(
              excluding: keyboard && !_paneActive,
              child: FocusScope(
                node: _paneScope,
                child: ClipRect(
                  child: Navigator(
                    key: _paneNavigator,
                    pages: [
                      _PanePage(
                        key: ValueKey(section.id),
                        child: Builder(builder: section.page),
                      ),
                    ],
                    onDidRemovePage: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildColumn(BuildContext context) {
    final glass = ockerGlass(context);
    final rows = <Widget>[_ColumnTitle(widget.title)];
    String? group;
    for (final section in widget.sections) {
      if (section.group != group) {
        group = section.group;
        rows.add(_ColumnHeading(group));
      }
      rows.add(_buildColumnRow(context, section));
    }

    // Every row built, not just the ones in view: a row the list has not built
    // is one the cursor cannot be put on.
    final list = Material(
      type: MaterialType.transparency,
      child: FocusScope(
        node: _columnScope,
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _onColumnKey,
          child: SingleChildScrollView(
            controller: _columnScroll,
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(crossAxisAlignment: .stretch, children: rows),
          ),
        ),
      ),
    );

    if (!glass) return list;
    if (ockerFlat(context)) {
      // Flach: one flat surface the full height, as its library column.
      return OckerGlass(borderRadius: BorderRadius.zero, scrimInset: 0, child: list);
    }
    // Glas: a pane with the screen's edge round it, as its library column.
    final scale = ockerScale(context);
    final radius = BorderRadius.circular(tokens(context).radiusSm + 8);
    return Padding(
      padding: EdgeInsets.fromLTRB(12 * scale, 12 * scale, 0, 12 * scale),
      child: OckerGlass(
        borderRadius: radius,
        scrimInset: 0,
        child: ClipRRect(borderRadius: radius, child: list),
      ),
    );
  }

  Widget _buildColumnRow(BuildContext context, PlebzSettingsSection section) {
    final selected = section.id == _selected.id;
    final tk = tokens(context);
    final glass = ockerGlass(context);
    Widget row = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) => _onRowFocus(section.id, focused),
      child: FocusableListTile(
        key: PlebzSettingsShell.rowKey(section.id),
        focusNode: _nodeFor(section.id),
        selected: selected,
        glassMarks: true,
        leading: AppIcon(section.icon, fill: 1),
        title: Text(section.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        horizontalTitleGap: 12,
        onTap: () => _choose(section),
      ),
    );
    // The original look has no mark of its own for the topic on show: a
    // plate of the cards' surface behind it.
    if (!glass) {
      row = Material(
        color: selected ? tk.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(tk.radiusSm),
        clipBehavior: Clip.antiAlias,
        child: row,
      );
    }
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1), child: row);
  }

  // ---------------------------------------------------------------------------
  // One pane: the column as the page

  Widget _buildList(BuildContext context) {
    final groups = <String, List<PlebzSettingsSection>>{};
    for (final section in widget.sections) {
      groups.putIfAbsent(section.group, () => []).add(section);
    }
    return CustomScrollView(
      primary: false,
      slivers: [
        ExcludeFocus(child: CustomAppBar(title: Text(widget.title), pinned: true)),
        SliverList(
          delegate: SliverChildListDelegate([
            for (final entry in groups.entries)
              SettingsGroup(
                title: entry.key,
                children: [
                  for (final section in entry.value)
                    SettingNavigationTile(
                      key: PlebzSettingsShell.rowKey(section.id),
                      focusNode: _nodeFor(section.id),
                      icon: section.icon,
                      title: section.title,
                      subtitle: section.subtitle,
                      onTap: () => _choose(section),
                    ),
                ],
              ),
            const SizedBox(height: 24),
          ]),
        ),
        const SliverSystemBottomInset(),
      ],
    );
  }
}

/// "Einstellungen" over the column, on the line the page beside it puts its
/// own title on.
class _ColumnTitle extends StatelessWidget {
  const _ColumnTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    // Set as an app bar sets its title, so the two read as one line.
    final style = Theme.of(context).appBarTheme.titleTextStyle ?? Theme.of(context).textTheme.titleLarge!;
    return SizedBox(
      height: kToolbarHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Align(
          alignment: Alignment.centerLeft,
          child: DefaultTextStyle(
            style: style,
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      ),
    );
  }
}

/// A group's heading in the column: the redesign's label under the
/// redesign, as over its library column's servers; a settings heading
/// elsewhere.
class _ColumnHeading extends StatelessWidget {
  const _ColumnHeading(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    if (!ockerGlass(context)) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 16, 6),
        child: Text(title, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: tokens(context).textMuted)),
      );
    }
    final type = OckerType.of(context);
    final scale = ockerScale(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 20 * scale, 16, 8 * scale),
      child: Text(
        type.headingCase(title),
        style: type.sourceLabel.copyWith(color: tokens(context).ink(0.45)),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// The topic's page in the pane: swapped in place, without a transition, as
/// the cursor walks the column.
class _PanePage extends Page<void> {
  const _PanePage({required LocalKey super.key, required this.child});

  final Widget child;

  @override
  Route<void> createRoute(BuildContext context) => _PaneRoute(this);
}

class _PaneRoute extends PageRoute<void> {
  _PaneRoute(_PanePage page) : super(settings: page);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) =>
      (settings as _PanePage).child;

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  bool get maintainState => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;
}
