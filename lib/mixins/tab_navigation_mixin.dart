import 'package:flutter/material.dart';
import '../services/gamepad_service.dart';
import '../screens/main_screen.dart';
import '../widgets/overlay_sheet.dart';
import '../widgets/focusable_tab_chip.dart';

/// Mixin that provides common tab navigation infrastructure.
///
/// Handles:
/// - [TabController] creation and disposal
/// - L1/R1 gamepad registration for tab switching
/// - [suppressAutoFocus] flag management
/// - Tab chip focus node lookup
/// - Tab bar back navigation to sidebar
///
/// Subclasses must provide [tabChipFocusNodes] — one [FocusNode] per tab.
mixin TabNavigationMixin<T extends StatefulWidget> on State<T>, TickerProviderStateMixin<T> {
  /// Mutable so [initTabNavigation] can be called more than once during a
  /// single State lifetime — the libraries screen rebuilds the controller
  /// when the visible tab set changes (Jellyfin shows Browse only;
  /// switching back to a Plex library goes from 1 tab to 4).
  late TabController tabController;

  /// When true, suppress auto-focus in tabs (used when navigating via tab bar).
  bool suppressAutoFocus = false;

  /// Subclasses provide focus nodes as a list indexed by tab position.
  List<FocusNode> get tabChipFocusNodes;

  /// Number of tabs — derived from [tabChipFocusNodes].
  int get tabCount => tabChipFocusNodes.length;

  /// Initialise the [TabController] and register owner-scoped gamepad callbacks.
  /// Call from [initState].
  void initTabNavigation() {
    tabController = TabController(length: tabCount, vsync: this);
    tabController.addListener(onTabChanged);
    GamepadService.registerTabNavigation(
      this,
      previous: goToPreviousTab,
      next: goToNextTab,
      isActive: _acceptsTabNavigation,
    );
  }

  /// Bumpers switch tabs only while this screen is the visible one and owns
  /// the input: a dialog route or an overlay sheet on top keeps TickerMode
  /// enabled for the screen underneath, which must not change tab behind it.
  bool _acceptsTabNavigation() {
    if (!mounted || !TickerMode.getValuesNotifier(context).value.enabled) return false;
    if (!(ModalRoute.isCurrentOf(context) ?? true)) return false;
    return OverlaySheetController.openSheetCount.value == 0;
  }

  /// Dispose the [TabController] and remove only this screen's callbacks.
  /// Call from [dispose].
  void disposeTabNavigation() {
    GamepadService.unregisterTabNavigation(this);
    tabController.removeListener(onTabChanged);
    tabController.dispose();
  }

  void goToPreviousTab() {
    if (tabController.index > 0) {
      setState(() {
        suppressAutoFocus = true;
        tabController.index = tabController.index - 1;
      });
      getTabChipFocusNode(tabController.index).requestFocus();
    }
  }

  void goToNextTab() {
    if (tabController.index < tabController.length - 1) {
      setState(() {
        suppressAutoFocus = true;
        tabController.index = tabController.index + 1;
      });
      getTabChipFocusNode(tabController.index).requestFocus();
    }
  }

  /// Called when the tab index changes. Override to add custom behaviour
  /// (e.g. persisting the tab index), then call `super.onTabChanged()`.
  void onTabChanged() {
    // ignore: no-empty-block - setState triggers rebuild to reflect new tab
    setState(() {});
  }

  FocusNode getTabChipFocusNode(int index) => tabChipFocusNodes[index];

  void focusTabBar() {
    final node = getTabChipFocusNode(tabController.index);
    // Ask before the rebuild, not after it. The setState below replaces the
    // widgets of the row this node lives in, and where that row is drawn by
    // the screen rather than by an app bar — the Ocker layouts put it inside
    // the content column, beside the posters — the rebuild can detach and
    // re-attach the node within the frame. A request made while it is still
    // attached survives that; one made into the gap is simply dropped.
    node.requestFocus();
    setState(() {
      suppressAutoFocus = true;
    });
    _reassertTabBarFocus(node, 3);
  }

  /// Ask again, for a few frames, until it takes.
  ///
  /// One retry was not enough: the row can settle over more than a frame when
  /// the tab content is still mounting under it, and the first frame after the
  /// request is sometimes the one where the node is between parents. Bounded
  /// rather than a listener, so a tab row that genuinely cannot be focused —
  /// there is none today — cannot turn this into a loop. Costs nothing once
  /// the node has focus: the first check ends it.
  void _reassertTabBarFocus(FocusNode node, int framesLeft) {
    if (framesLeft <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || node.hasFocus) return;
      node.requestFocus();
      _reassertTabBarFocus(node, framesLeft - 1);
    });
  }

  void onTabBarBack() {
    MainScreenFocusScope.focusSidebarOf(context);
  }

  /// Shared tab chip builder — eliminates duplication between screens.
  ///
  /// [onNavigateToActions] moves focus into the app bar's right-aligned
  /// [FocusableActionBar]. It fires both on RIGHT from the last tab and on UP
  /// from any tab, so every screen with that layout gets a consistent remote
  /// path to its app bar actions.
  Widget buildTabChip(
    String label,
    int index, {
    required VoidCallback onSelectWhenActive,
    required VoidCallback onNavigateDown,
    VoidCallback? onNavigateToActions,

    /// Where UP goes, when that is not the same place as RIGHT-past-the-last.
    ///
    /// They used to be one destination because the only thing above or beside
    /// a tab row was the action bar. With the filters on the same line, RIGHT
    /// reaches them and UP has to carry on past the row entirely.
    VoidCallback? onNavigateUp,
  }) {
    final isSelected = tabController.index == index;
    return FocusableTabChip(
      label: label,
      isSelected: isSelected,
      focusNode: getTabChipFocusNode(index),
      onSelect: () {
        if (isSelected) {
          onSelectWhenActive();
        } else {
          // The tab changes here and only here. Focus stays on the chip, so a
          // second press is what walks into what was opened.
          setState(() {
            suppressAutoFocus = true;
            tabController.index = index;
          });
        }
      },
      // Walking the row moves the cursor and nothing else.
      //
      // It used to switch the tab under the cursor on every step, which made
      // the row unusable as a *route*: anything past the last chip — the
      // filters that narrow "Durchsuchen" sit there — could only be reached by
      // walking over every tab in between, and arriving with the last one open
      // instead of the one being narrowed. The shoulder buttons still step
      // through tabs directly; that is what they are for.
      onNavigateLeft: index > 0 ? () => getTabChipFocusNode(index - 1).requestFocus() : onTabBarBack,
      onNavigateRight: index < tabCount - 1 ? () => getTabChipFocusNode(index + 1).requestFocus() : onNavigateToActions,
      onNavigateDown: onNavigateDown,
      onNavigateUp: onNavigateUp ?? onNavigateToActions,
      onBack: onTabBarBack,
    );
  }
}
