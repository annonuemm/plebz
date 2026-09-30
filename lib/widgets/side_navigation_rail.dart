import 'dart:async';
import 'dart:ui' show lerpDouble;
import '../media/ids.dart';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:plezy/widgets/app_icon.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../focus/dpad_navigator.dart';
import '../focus/focus_memory_tracker.dart';
import '../focus/input_mode_tracker.dart';
import '../media/media_item.dart';
import '../media/media_library.dart';
import '../mixins/mounted_set_state_mixin.dart';
import '../navigation/navigation_tabs.dart';
import '../providers/iptv_sources_provider.dart';
import '../providers/catalog_sources_provider.dart';
import '../providers/hidden_libraries_provider.dart';
import '../screens/livetv/live_tv_sidebar_actions.dart';
import '../providers/libraries_provider.dart';
import '../services/device_performance.dart';
import '../services/music/music_playback_service.dart';
import '../services/settings_service.dart';
import '../utils/music_navigation.dart';
import '../utils/content_utils.dart';
import '../utils/platform_detector.dart';
import '../utils/scroll_utils.dart';
import '../utils/library_grouping.dart';
import 'music/equalizer_icon.dart';
import '../providers/multi_server_provider.dart';
import '../services/fullscreen_state_manager.dart';
import '../redesign/ocker_skin.dart';
import '../theme/mono_tokens.dart';
import '../widgets/backend_badge.dart';
import '../i18n/strings.g.dart';

enum _LibraryNavSection { visible, hidden }

sealed class _LibraryNavRow {
  final _LibraryNavSection section;

  const _LibraryNavRow({required this.section});
}

final class _LibraryServerHeaderRow extends _LibraryNavRow {
  final String serverId;
  final String serverName;

  const _LibraryServerHeaderRow({required super.section, required this.serverId, required this.serverName});
}

final class _LibraryItemRow extends _LibraryNavRow {
  final MediaLibrary library;
  final bool showServerName;

  const _LibraryItemRow({required super.section, required this.library, this.showServerName = false});
}

/// SELECT activates the rail row, RIGHT hands off to the content area.
KeyEventResult _handleRailItemKey(KeyEvent event, {required VoidCallback onSelect, VoidCallback? onNavigateRight}) {
  if (event is! KeyDownEvent) return KeyEventResult.ignored;
  if (event.logicalKey.isSelectKey) {
    onSelect();
    return KeyEventResult.handled;
  }
  if (event.logicalKey == LogicalKeyboardKey.arrowRight && onNavigateRight != null) {
    onNavigateRight();
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}

/// Reusable navigation rail item widget that handles focus, selection, and interaction.
///
/// Renders the two M3 Expressive destination layouts and morphs between them:
/// collapsed is an icon-only 56x32 pill indicator centered in the strip
/// (announced via [collapsedLabel]); expanded is a full-width stadium row
/// with leading icon and [label]. Items that never render collapsed
/// (library rows) leave [collapsedLabel] null and always use the expanded
/// layout.
class NavigationRailItem extends StatelessWidget {
  /// M3E collapsed-rail active indicator geometry.
  static const double collapsedIndicatorWidth = 56;
  static const double collapsedIndicatorHeight = 32;

  /// Fixed collapsed item height so the collapse morph interpolates between
  /// known extents (32px pill + breathing room).
  static const double collapsedItemHeight = 40;

  final IconData icon;
  final IconData? selectedIcon;

  /// Custom leading widget rendered instead of the [icon] (e.g. the Now
  /// Playing item's equalizer). Should be at most [iconSize] tall/wide.
  final Widget? iconWidget;
  final Widget label;

  /// Base color inherited by single-style text labels. During the morph its
  /// alpha is changed at the leaf, avoiding an opacity layer for the row.
  final Color? labelColor;

  /// Builds labels with more than one text color at [opacity]. Non-text
  /// labels without a builder use one opacity layer only while morphing.
  final Widget Function(double opacity)? labelBuilder;

  /// Semantic label for the icon-only collapsed pill. Null means the item
  /// has no collapsed representation and always lays out expanded.
  final String? collapsedLabel;

  /// Widget rendered after the [label] (e.g. a section header's chevron).
  /// Expanded layout only.
  final Widget? trailing;

  /// Builds a trailing leaf at [opacity] when it should fade with the label.
  final Widget Function(double opacity)? trailingBuilder;
  final bool isSelected;
  final bool isCollapsed;
  final VoidCallback onTap;
  final FocusNode focusNode;
  final bool autofocus;
  final double iconSize;

  /// Horizontal content padding of the expanded row.
  final double horizontalPadding;

  /// Fixed content width of the expanded layout, so the collapse morph and
  /// the rail width animation stay in lockstep.
  final double expandedContentWidth;

  /// Expanded row height: fixed for collapsible items, a minimum for
  /// expanded-only items (whose labels may add a second line).
  final double expandedHeight;
  final bool suppressSelectedBackground;

  /// How solid the icon is drawn, and how heavy its strokes are. Outlines at
  /// the regular weight by default ([navIconFill], [navIconWeight]) — see
  /// there for why the rail is drawn that way. A toggle that is *on* passes 1,
  /// so the filled glyph says so on its own.
  final double iconFill;
  final double iconWeight;

  /// Background tint while keyboard-focused, and its stronger variant used
  /// when the item also shows its selected background.
  final double focusAlpha;
  final double selectedFocusAlpha;

  /// Called when RIGHT arrow is pressed to navigate to content area.
  final VoidCallback? onNavigateRight;

  const NavigationRailItem({
    super.key,
    required this.icon,
    this.selectedIcon,
    this.iconWidget,
    required this.label,
    this.collapsedLabel,
    this.labelColor,
    this.labelBuilder,
    this.trailing,
    this.trailingBuilder,
    required this.isSelected,
    this.isCollapsed = false,
    required this.onTap,
    required this.focusNode,
    this.autofocus = false,
    this.iconSize = 22,
    this.horizontalPadding = 17,
    this.expandedContentWidth = SideNavigationRailState.expandedWidth - 24,
    this.expandedHeight = 48,
    this.suppressSelectedBackground = false,
    this.iconFill = navIconFill,
    this.iconWeight = navIconWeight,
    this.focusAlpha = 0.12,
    this.selectedFocusAlpha = 0.15,
    this.onNavigateRight,
  });

  Color? _indicatorColorForLayout(MonoTokens t, {required bool focused, required bool collapsedLayout}) {
    // The collapsed TV rail is a transparent overlay strip; a persistent
    // active pill over artwork is noise there, so it shows focus only.
    final showSelected = isSelected && !suppressSelectedBackground && !(collapsedLayout && PlatformDetector.isTV());
    if (focused) return t.text.withValues(alpha: showSelected ? selectedFocusAlpha : focusAlpha);
    if (showSelected) return t.accent.withValues(alpha: 0.1);
    return null;
  }

  Color? _indicatorColor(MonoTokens t, {required bool focused, required double expansion}) {
    return Color.lerp(
      _indicatorColorForLayout(t, focused: focused, collapsedLayout: true),
      _indicatorColorForLayout(t, focused: focused, collapsedLayout: false),
      expansion,
    );
  }

  /// The plate behind a destination — or, under "Ocker", the ring around it.
  ///
  /// The rail marked focus with a filled pill on a fully rounded shape. In a
  /// design whose every corner is square and whose every focus is a hairline
  /// ring held off the edge, that is not a variation — it is the one place the
  /// old language survived, and beside the rest of the screen it read as
  /// borrowed from another app.
  ///
  /// Selection keeps no plate here either: the accent bar on the rail's edge
  /// and the accent in the icon and the label already say which destination
  /// this is, and a third mark for one state is a third thing to look at.
  BoxDecoration _indicatorDecoration(
    BuildContext context,
    MonoTokens t, {
    required bool focused,
    required double expansion,
  }) {
    final radius = BorderRadius.circular(flatRadius(context, MonoTokens.radiusFull));
    if (isOcker(context)) {
      return BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: focused ? t.focusRingColor : Colors.transparent,
          width: t.focusBorderWidth,
          strokeAlign: BorderSide.strokeAlignOutside,
        ),
      );
    }
    return BoxDecoration(
      color: _indicatorColor(t, focused: focused, expansion: expansion),
      borderRadius: radius,
    );
  }

  Widget _leadingIcon(MonoTokens t) =>
      iconWidget ??
      AppIcon(
        isSelected && selectedIcon != null ? selectedIcon! : icon,
        fill: iconFill,
        weight: iconWeight,
        size: iconSize,
        color: isSelected ? t.accent : t.textMuted,
      );

  /// Whether the collapsed layout has to say "this is the one" on its own.
  ///
  /// The pill is the indicator wherever it is drawn, and the television is the
  /// one place it is not: a persistent fill over artwork is noise there, so
  /// the collapsed strip was left with the accent colour alone — thin
  /// across a room, and nothing at all for a viewer who reads red as grey.
  /// The expanded rail keeps its pill and its label and needs no marker.
  bool _needsSelectionBar(BuildContext context) => isSelected && PlatformDetector.isTV();

  /// Identifies the marker for tests; there is at most one on screen.
  static const Key selectionBarKey = Key('rail_selection_bar');

  /// The marker itself: a short bar on the rail's own edge, beside the icon.
  /// [opacity] fades it out as the rail expands and the pill takes over.
  Widget _selectionBar(BuildContext context, MonoTokens t, {required double opacity}) => Positioned(
    left: 0,
    top: 0,
    bottom: 0,
    child: Center(
      child: Container(
        key: selectionBarKey,
        width: 3,
        height: 18,
        decoration: BoxDecoration(
          color: t.accent.withValues(alpha: t.accent.a * opacity),
          borderRadius: BorderRadius.circular(flatRadius(context, MonoTokens.radiusFull)),
        ),
      ),
    ),
  );

  static double _collapsedItemWidth(BuildContext context) =>
      SideNavigationRailState.collapsedWidthForContext(context) -
      2 * SideNavigationRailState.horizontalPaddingForContext(context, isCollapsed: true);

  /// M3E collapsed destination: an icon-only pill indicator.
  Widget _buildCollapsedLayout(BuildContext context, MonoTokens t, {required bool focused}) {
    final width = _collapsedItemWidth(context);
    return SizedBox(
      width: width,
      height: collapsedItemHeight,
      child: Stack(
        children: [
          if (_needsSelectionBar(context)) _selectionBar(context, t, opacity: 1),
          Center(
            child: Semantics(
              label: collapsedLabel,
              child: Container(
                width: width < collapsedIndicatorWidth ? width : collapsedIndicatorWidth,
                height: collapsedIndicatorHeight,
                alignment: .center,
                decoration: _indicatorDecoration(context, t, focused: focused, expansion: 0),
                child: _leadingIcon(t),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// M3E expanded destination: full-width stadium indicator behind the row.
  Widget _labelAtOpacity(BuildContext context, double opacity) {
    final builder = labelBuilder;
    if (builder != null) return builder(opacity);

    final textStyle = label is Text ? (label as Text).style : null;
    final inheritsTextColor =
        label is Text &&
        (textStyle == null || (textStyle.inherit && textStyle.color == null && textStyle.foreground == null));
    final color = inheritsTextColor ? labelColor ?? DefaultTextStyle.of(context).style.color : null;
    if (color != null) {
      return DefaultTextStyle.merge(
        style: TextStyle(color: color.withValues(alpha: color.a * opacity)),
        child: label,
      );
    }
    if (opacity >= 1) return label;

    // The reconnect progress indicator is the only production caller of this
    // path. It cannot inherit text color, so retain one small opacity layer
    // rather than a layer for every destination row.
    return Opacity(opacity: opacity, child: label);
  }

  Widget? _trailingAtOpacity(double opacity) {
    final builder = trailingBuilder;
    return builder == null ? trailing : builder(opacity);
  }

  Widget _buildExpandedContent(
    BuildContext context,
    MonoTokens t, {
    required double labelOpacity,
    required bool showLeading,
  }) {
    return Row(
      children: [
        if (showLeading) _leadingIcon(t) else SizedBox(width: iconSize, height: iconSize),
        const SizedBox(width: 11),
        Expanded(child: _labelAtOpacity(context, labelOpacity)),
        ?_trailingAtOpacity(labelOpacity),
      ],
    );
  }

  Widget _buildExpandedLayout(BuildContext context, MonoTokens t, {required bool focused, required bool fixedHeight}) {
    return Container(
      constraints: fixedHeight ? null : BoxConstraints(minHeight: expandedHeight),
      alignment: .centerLeft,
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: fixedHeight ? 0 : 8),
      decoration: _indicatorDecoration(context, t, focused: focused, expansion: 1),
      child: _buildExpandedContent(context, t, labelOpacity: 1, showLeading: true),
    );
  }

  /// At the endpoints only the active layout exists in the tree. Mid-morph a
  /// single icon moves with the pill geometry while label and indicator color
  /// alpha provide the crossfade without subtree opacity layers.
  Widget _buildMorphingLayouts(BuildContext context, MonoTokens t, {required bool focused, required double expansion}) {
    if (expansion <= 0) return _buildCollapsedLayout(context, t, focused: focused);
    if (expansion >= 1) {
      return SizedBox(
        width: expandedContentWidth,
        height: expandedHeight,
        child: _buildExpandedLayout(context, t, focused: focused, fixedHeight: true),
      );
    }

    final collapsedWidth = _collapsedItemWidth(context);
    const collapsedHeight = collapsedItemHeight;
    final collapsedPillWidth = collapsedWidth < collapsedIndicatorWidth ? collapsedWidth : collapsedIndicatorWidth;
    final indicatorLeft = lerpDouble((collapsedWidth - collapsedPillWidth) / 2, 0, expansion);
    final indicatorTop = lerpDouble((collapsedHeight - collapsedIndicatorHeight) / 2, 0, expansion);
    final iconLeft = lerpDouble((collapsedWidth - iconSize) / 2, horizontalPadding, expansion);
    final iconTop = lerpDouble((collapsedHeight - iconSize) / 2, (expandedHeight - iconSize) / 2, expansion);

    return SizedBox(
      width: lerpDouble(collapsedWidth, expandedContentWidth, expansion),
      height: lerpDouble(collapsedHeight, expandedHeight, expansion),
      child: Stack(
        children: [
          if (_needsSelectionBar(context))
            // Under "Ocker" the bar does not hand over to a pill as the rail
            // opens, because there is no pill to hand over to. It is the mark,
            // at both widths.
            _selectionBar(context, t, opacity: isOcker(context) ? 1 : 1 - expansion),
          Positioned(
            left: indicatorLeft,
            top: indicatorTop,
            child: Container(
              width: lerpDouble(collapsedPillWidth, expandedContentWidth, expansion),
              height: lerpDouble(collapsedIndicatorHeight, expandedHeight, expansion),
              decoration: _indicatorDecoration(context, t, focused: focused, expansion: expansion),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            child: SizedBox(
              width: expandedContentWidth,
              height: expandedHeight,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: _buildExpandedContent(context, t, labelOpacity: expansion, showLeading: false),
              ),
            ),
          ),
          Positioned(
            left: iconLeft,
            top: iconTop,
            child: SizedBox(
              width: iconSize,
              height: iconSize,
              child: Center(child: _leadingIcon(t)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);

    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, _) {
        final focused = focusNode.hasFocus && InputModeTracker.isKeyboardMode(context);
        final content = collapsedLabel == null
            ? SizedBox(
                width: expandedContentWidth,
                child: _buildExpandedLayout(context, t, focused: focused, fixedHeight: false),
              )
            : TweenAnimationBuilder<double>(
                tween: Tween(end: isCollapsed ? 0.0 : 1.0),
                duration: SideNavigationRailState.expandDuration,
                curve: SideNavigationRailState.expandCurve,
                builder: (context, expansion, _) =>
                    _buildMorphingLayouts(context, t, focused: focused, expansion: expansion),
              );
        return Focus(
          focusNode: focusNode,
          autofocus: autofocus,
          onKeyEvent: (node, event) => _handleRailItemKey(event, onSelect: onTap, onNavigateRight: onNavigateRight),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              canRequestFocus: false,
              onTap: onTap,
              borderRadius: BorderRadius.circular(flatRadius(context, MonoTokens.radiusFull)),
              child: UnconstrainedBox(
                alignment: .centerLeft,
                constrainedAxis: Axis.vertical,
                clipBehavior: Clip.hardEdge,
                child: content,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Side navigation rail for Desktop and Android TV platforms
class SideNavigationRail extends StatefulWidget {
  final NavigationTabId selectedTab;
  final String? selectedLibraryKey;
  final bool isOfflineMode;
  final bool isSidebarFocused;
  final bool alwaysExpanded;
  final bool isReconnecting;
  final ValueChanged<NavigationTabId> onDestinationSelected;
  final ValueChanged<String> onLibrarySelected;

  /// Called when RIGHT arrow is pressed to navigate to content without selecting.
  final VoidCallback? onNavigateToContent;

  /// Called when the user taps the reconnect button in offline mode.
  final VoidCallback? onReconnect;

  /// Called when the rail starts or stops floating over the content as an
  /// M3E modal panel, so the shell can scrim the content it covers. Docked
  /// expansion (always-open, D-pad focus) displaces content and never scrims.
  final ValueChanged<bool>? onFloatingPanelChanged;

  /// The Live TV screen, when it is the one on show. Its channel arrangement,
  /// favourites filter and reload live here rather than in an app bar of its
  /// own: on a television that bar costs a whole row for three icons, and the
  /// rail already has the room.
  final LiveTvSidebarActions? liveTvActions;

  const SideNavigationRail({
    super.key,
    required this.selectedTab,
    this.selectedLibraryKey,
    this.isOfflineMode = false,
    this.isSidebarFocused = false,
    this.alwaysExpanded = false,
    this.isReconnecting = false,
    required this.onDestinationSelected,
    required this.onLibrarySelected,
    this.onNavigateToContent,
    this.onFloatingPanelChanged,
    this.onReconnect,
    this.liveTvActions,
  });

  @override
  State<SideNavigationRail> createState() => SideNavigationRailState();
}

class SideNavigationRailState extends State<SideNavigationRail> with MountedSetStateMixin {
  /// Libraries section expansion, held in settings rather than widget state so
  /// it survives relaunch, remount and layout switches (#1896). The rail's
  /// [ListenableBuilder] below listens to the pref, so the toggle just writes.
  bool get _librariesExpanded => SettingsService.instance.read(SettingsService.librariesSectionExpanded);

  bool get _liveTvExpanded => SettingsService.instance.read(SettingsService.liveTvSectionExpanded);

  /// The Live TV entries the rail can offer right now. Empty unless Live TV is
  /// the screen on show — the actions belong to it, and it is the only one
  /// that can answer for them.
  List<({String key, IconData icon, double fill, String label, VoidCallback onTap})> get _liveTvActionRows {
    final actions = widget.liveTvActions;
    if (actions == null) return const [];
    final t = Translations.of(context);
    return [
      if (actions.canManageChannels)
        (
          key: _kLiveTvManage,
          icon: Symbols.tune_rounded,
          fill: 0.0,
          label: t.liveTv.manageChannels,
          onTap: actions.openChannelManagement,
        ),
      (
        key: _kLiveTvFavorites,
        icon: actions.showsFavoritesOnly ? Symbols.star_rounded : Symbols.star_outline_rounded,
        fill: actions.showsFavoritesOnly ? 1.0 : 0.0,
        label: t.liveTv.favorites,
        onTap: actions.toggleFavoritesFilter,
      ),
      if (actions.canReorderFavorites)
        (
          key: _kLiveTvReorder,
          icon: Symbols.swap_vert_rounded,
          fill: 0.0,
          label: t.liveTv.reorderFavorites,
          onTap: actions.reorderFavorites,
        ),
      (
        key: _kLiveTvRefresh,
        icon: Symbols.refresh_rounded,
        fill: 0.0,
        label: t.liveTv.reloadGuide,
        onTap: actions.reloadLiveTv,
      ),
    ];
  }

  bool _isHovered = false;
  bool _isTouchExpanded = false;
  bool _lastReportedFloatingPanel = false;
  Timer? _collapseTimer;
  static const double collapsedWidth = 80.0;
  static const double tvCollapsedWidth = 48.0;
  static const double expandedWidth = 220.0;
  static const double _horizontalPadding = 12.0;
  static const double _collapsedHorizontalPadding = 4.0;
  static const double _itemGap = 4.0;
  static const Duration _collapseDelay = Duration(milliseconds: 150);

  /// Trailing corner radius of the floating (hover/touch) overlay panel; the
  /// docked open rail keeps the regular radiusLg card rounding.
  static const double overlayCornerRadius = 32.0;

  /// Collapse/expand morph timing, shared by the rail width, every item's
  /// layout morph, and the shell's content translate + bleed counter
  /// animations (MainScreen and SideNavigationBleedBuilder) so they all
  /// track tick for tick.
  /// Reduced-tier devices resolve this to zero; keep every consumer on this
  /// getter so the shell and rail continue to move in lockstep.
  static Duration get expandDuration => DevicePerformance.reducedDuration(const Duration(milliseconds: 250));
  static const Curve expandCurve = Curves.easeInOutCubicEmphasized;

  static double collapsedWidthForContext(BuildContext _) => PlatformDetector.isTV() ? tvCollapsedWidth : collapsedWidth;

  /// Edge padding around the item column; collapsed rails center their items
  /// (72px in the 80px desktop strip, 40px in the 48px TV strip).
  static double horizontalPaddingForContext(BuildContext _, {required bool isCollapsed}) {
    return isCollapsed ? _collapsedHorizontalPadding : _horizontalPadding;
  }

  static const _kHome = 'home';
  static const _kWatchlist = 'watchlist';
  static const _kExplore = 'explore';
  static const _kSport = 'sport';
  static const _kNowPlaying = 'nowPlaying';
  static const _kLibraries = 'libraries';
  static const _kLiveTv = 'liveTv';
  static const _kLiveTvManage = 'liveTvManage';
  static const _kLiveTvFavorites = 'liveTvFavorites';
  static const _kLiveTvReorder = 'liveTvReorder';
  static const _kLiveTvRefresh = 'liveTvRefresh';
  static const _kSearch = 'search';
  static const _kDownloads = 'downloads';
  static const _kSettings = 'settings';
  static const _kReconnect = 'reconnect';
  static const _kFullscreen = 'fullscreen';
  static const _kHiddenLibraries = 'hiddenLibraries';
  static const _kServerHeaderPrefix = 'serverHeader';
  static const _kLibraryItemPrefix = 'library';

  bool _hiddenLibrariesExpanded = false;
  final Set<String> _collapsedServerGroupKeys = {};

  // Unified focus state tracker for all nav items (main + libraries)
  late final FocusMemoryTracker _focusTracker;

  /// Whether the sidebar should be expanded (always, hover, or focus)
  bool get _shouldExpand => widget.alwaysExpanded || _isHovered || _isTouchExpanded || widget.isSidebarFocused;

  bool get _interactionExpanded => _isHovered || _isTouchExpanded;

  /// True while the rail floats over the content as an M3E modal panel.
  ///
  /// Hover/touch expansion leaves the shell at its collapsed content offset,
  /// so a floating panel covers content and owns its own opaque surface and
  /// edge shadow. Every docked shape — collapsed, always-open, or D-pad
  /// focus-expanded — displaces content instead and stays transparent on TV.
  bool get _isFloatingPanel => _interactionExpanded && !widget.alwaysExpanded;

  /// Mirrors [NavigationTab.getVisibleTabs]: off by setting hides the
  /// section, except offline where it is the only thing to watch.
  /// Read live, like [_showDownloads]: the shell rebuilds this rail when the
  /// switch flips, so the answer is never older than the frame.
  bool get _showSport => SettingsService.instance.read(SettingsService.showSportTab);

  bool get _showDownloads =>
      !PlatformDetector.isAppleTV() &&
      (widget.isOfflineMode || SettingsService.instance.read(SettingsService.showDownloadAction));

  /// macOS has the system green button; mobile/TV have no OS fullscreen toggle.
  bool get _showFullscreenToggle => Platform.isWindows || Platform.isLinux;

  @override
  void initState() {
    super.initState();
    _focusTracker = FocusMemoryTracker(debugLabelPrefix: 'nav');
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    _focusTracker.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SideNavigationRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-collapse after navigation (selection changed)
    if (oldWidget.selectedTab != widget.selectedTab || oldWidget.selectedLibraryKey != widget.selectedLibraryKey) {
      final wasInteractionExpanded = _interactionExpanded;
      _isTouchExpanded = false;
      if (wasInteractionExpanded != _interactionExpanded) {
        _scheduleFloatingPanelNotification();
      }
    }
    // Toggling always-open while hovered/touched converts a floating panel
    // into a docked rail (or back) without any interaction-state change.
    if (oldWidget.alwaysExpanded != widget.alwaysExpanded) {
      _scheduleFloatingPanelNotification();
    }
  }

  /// didUpdateWidget runs during build, where notifying the parent would
  /// setState mid-build; defer that report to the next frame.
  void _scheduleFloatingPanelNotification() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _notifyFloatingPanelIfNeeded();
    });
  }

  void _notifyFloatingPanelIfNeeded() {
    final floating = _isFloatingPanel;
    if (_lastReportedFloatingPanel == floating) return;
    _lastReportedFloatingPanel = floating;
    widget.onFloatingPanelChanged?.call(floating);
  }

  void _onHoverEnter() {
    _collapseTimer?.cancel();
    if (_isHovered && !_isTouchExpanded) return;
    setState(() {
      _isTouchExpanded = false; // Mouse takes over
      _isHovered = true;
    });
    _notifyFloatingPanelIfNeeded();
  }

  void _onHoverExit() {
    _collapseTimer?.cancel();
    _collapseTimer = Timer(_collapseDelay, () {
      if (mounted && _isHovered) {
        setState(() => _isHovered = false);
        _notifyFloatingPanelIfNeeded();
      }
    });
  }

  void _expandForTouch() {
    if (_isTouchExpanded) return;
    setState(() => _isTouchExpanded = true);
    _notifyFloatingPanelIfNeeded();
  }

  /// The key of the last focused sidebar item (for pre-capture before focus shifts).
  String? get lastFocusedKey => _focusTracker.lastFocusedKey;

  /// Focus the last focused nav item, or Home as fallback.
  /// If [targetKey] is provided, try it first (used when the caller captured
  /// the intended target before a focus-scope switch overwrote it).
  void focusActiveItem({String? targetKey}) {
    final node = _resolveFocusNode(targetKey) ?? _mountedFocusNodeFor(_kHome);
    if (node == null) return;
    _requestFocusAndReveal(node);
  }

  /// Focus the Home nav item (Back returning to the home tab).
  void focusHomeItem() {
    final node = _mountedFocusNodeFor(_kHome);
    if (node == null) return;
    _requestFocusAndReveal(node);
  }

  /// Resolve the best mounted focus node in priority order:
  /// 1. Explicit [targetKey] (captured before scope switch)
  /// 2. Last focused key still in the tracker
  /// 3. Currently selected navigation item (tab / library)
  /// 4. Home fallback
  FocusNode? _resolveFocusNode(String? targetKey) {
    return _mountedFocusNodeFor(targetKey) ??
        _mountedFocusNodeFor(_focusTracker.lastFocusedKey) ??
        _mountedFocusNodeFor(_resolveSelectedFocusKey());
  }

  FocusNode? _mountedFocusNodeFor(String? key) {
    if (key == null) return null;
    final node = _focusTracker.nodeFor(key);
    return node != null && _isMounted(node) ? node : null;
  }

  /// Whether [node] is attached to a mounted row. A detached node keeps its
  /// last context after the row unmounts (a collapsed library section or
  /// server group), so a null check alone lets focus land on a row that is
  /// gone and the request goes nowhere.
  static bool _isMounted(FocusNode node) => node.context?.mounted ?? false;

  /// Derive a focus key from the current selection state (tab + library).
  /// Returns null if no meaningful selected item exists.
  String? _resolveSelectedFocusKey() {
    switch (widget.selectedTab) {
      case NavigationTabId.discover:
        return _kHome;
      case NavigationTabId.watchlist:
        return _kWatchlist;
      case NavigationTabId.explore:
        return _kExplore;
      case NavigationTabId.sport:
        return _showSport ? _kSport : null;
      case NavigationTabId.libraries:
        final libKey = widget.selectedLibraryKey;
        if (libKey != null && _librariesExpanded) {
          final visibleKey = '$_kLibraryItemPrefix:${_LibraryNavSection.visible.name}:$libKey';
          if (_mountedFocusNodeFor(visibleKey) != null) return visibleKey;
          if (_hiddenLibrariesExpanded) {
            final hiddenKey = '$_kLibraryItemPrefix:${_LibraryNavSection.hidden.name}:$libKey';
            if (_mountedFocusNodeFor(hiddenKey) != null) return hiddenKey;
          }
        }
        return _kLibraries;
      case NavigationTabId.search:
        return _kSearch;
      case NavigationTabId.downloads:
        return _showDownloads ? _kDownloads : null;
      case NavigationTabId.settings:
        return _kSettings;
      case NavigationTabId.liveTv:
        return _kLiveTv;
    }
  }

  /// Request focus on [node] and scroll it into view after the next frame.
  void _requestFocusAndReveal(FocusNode node) {
    node.requestFocus();
    scrollContextToCenter(node.context);
  }

  String _serverHeaderFocusKey(_LibraryNavSection section, ServerId serverId) =>
      '$_kServerHeaderPrefix:${section.name}:$serverId';

  String _libraryItemFocusKey(_LibraryNavSection section, MediaLibrary library) =>
      '$_kLibraryItemPrefix:${section.name}:${library.globalKey}';

  String _serverGroupStateKey(_LibraryNavSection section, ServerId serverId) => '${section.name}:$serverId';

  String _focusKeyForLibraryRow(_LibraryNavRow row) => switch (row) {
    _LibraryServerHeaderRow(:final section, :final serverId) => _serverHeaderFocusKey(section, ServerId(serverId)),
    _LibraryItemRow(:final section, :final library) => _libraryItemFocusKey(section, library),
  };

  Iterable<String> _focusKeysForLibraryRows(List<_LibraryNavRow> rows) => rows.map(_focusKeyForLibraryRow);

  /// Build the set of valid focus keys (main nav + currently rendered library rows).
  Set<String> _buildValidFocusKeys({
    required List<_LibraryNavRow> visibleRows,
    required List<_LibraryNavRow> hiddenRows,
    required bool hasHiddenLibraries,
    required bool hasLiveTv,
    required bool hasNowPlaying,
    required bool hasExplore,
    required bool hasWatchlist,
  }) {
    return {
      _kHome,
      if (hasWatchlist) _kWatchlist,
      if (hasNowPlaying) _kNowPlaying,
      _kLibraries,
      if (hasExplore) _kExplore,
      if (_showSport) _kSport,
      _kSearch,
      if (_showDownloads) _kDownloads,
      _kSettings,
      _kReconnect,
      if (hasHiddenLibraries) _kHiddenLibraries,
      if (_showFullscreenToggle) _kFullscreen,
      if (hasLiveTv) _kLiveTv,
      ..._focusKeysForLibraryRows(visibleRows),
      if (_hiddenLibrariesExpanded) ..._focusKeysForLibraryRows(hiddenRows),
    };
  }

  /// Build rendered rows inside one library section. This is the single source
  /// of truth for both widget rendering and D-pad focus ordering.
  List<_LibraryNavRow> _buildLibraryRows(
    List<MediaLibrary> libs, {
    required _LibraryNavSection section,
    required bool showServerHeaders,
  }) {
    if (!showServerHeaders) {
      final nonUniqueNames = _getNonUniqueLibraryNames(libs);
      return libs.map((lib) {
        return _LibraryItemRow(
          section: section,
          library: lib,
          showServerName: nonUniqueNames.contains(lib.title) && lib.serverName != null,
        );
      }).toList();
    }
    final grouped = groupLibrariesByFirstAppearance(libs);
    final result = <_LibraryNavRow>[];
    for (final serverKey in grouped.serverOrder) {
      final bucket = grouped.byServer[serverKey]!;
      if (serverKey.isNotEmpty) {
        result.add(
          _LibraryServerHeaderRow(
            section: section,
            serverId: serverKey,
            serverName: bucket.first.serverName ?? serverKey,
          ),
        );
      }
      if (serverKey.isEmpty ||
          !_collapsedServerGroupKeys.contains(_serverGroupStateKey(section, ServerId(serverKey)))) {
        for (final lib in bucket) {
          result.add(_LibraryItemRow(section: section, library: lib));
        }
      }
    }
    return result;
  }

  Set<String> _buildServerGroupStateKeys(
    List<MediaLibrary> visibleLibraries,
    List<MediaLibrary> hiddenLibraries, {
    required bool showServerHeaders,
  }) {
    if (!showServerHeaders) return {};

    return {
      for (final lib in visibleLibraries)
        if (lib.serverId != null) _serverGroupStateKey(_LibraryNavSection.visible, ServerId(lib.serverId!)),
      for (final lib in hiddenLibraries)
        if (lib.serverId != null) _serverGroupStateKey(_LibraryNavSection.hidden, ServerId(lib.serverId!)),
    };
  }

  /// Ordered list of focusable keys matching visual top-to-bottom order.
  List<String> _buildFocusOrder(
    List<_LibraryNavRow> visibleRows,
    List<_LibraryNavRow> hiddenRows, {
    required bool hasHiddenLibraries,
    required bool hasLiveTv,
    required bool hasNowPlaying,
    required bool hasExplore,
    required bool hasWatchlist,
    required bool isCollapsed,
  }) {
    return [
      if (widget.isOfflineMode && widget.onReconnect != null) _kReconnect,
      if (!widget.isOfflineMode) ...[
        _kHome,
        if (hasWatchlist) _kWatchlist,
        if (hasNowPlaying) _kNowPlaying,
        _kLibraries,
        // Library rows render inside ExcludeFocus(excluding: !_librariesExpanded
        // || isCollapsed); keep the D-pad order in lockstep with that render
        // condition so a collapsed rail never targets a focus-excluded row.
        if (_librariesExpanded && !isCollapsed) ...[
          ..._focusKeysForLibraryRows(visibleRows),
          if (hasHiddenLibraries) ...[
            _kHiddenLibraries,
            if (_hiddenLibrariesExpanded) ..._focusKeysForLibraryRows(hiddenRows),
          ],
        ],
        if (hasLiveTv) ...[
          _kLiveTv,
          if (_liveTvExpanded) ...[for (final row in _liveTvActionRows) row.key],
        ],
        if (hasExplore) _kExplore,
        if (_showSport) _kSport,
        _kSearch,
      ],
      if (_showDownloads) _kDownloads,
      _kSettings,
      if (_showFullscreenToggle) _kFullscreen,
    ];
  }

  void _debugAssertUniqueFocusOrder(List<String> focusOrder) {
    assert(() {
      final seen = <String>{};
      for (final key in focusOrder) {
        if (!seen.add(key)) {
          throw FlutterError('SideNavigationRail focus order contains duplicate key: $key');
        }
      }
      return true;
    }());
  }

  /// Handle D-pad UP/DOWN by explicitly moving focus to the next/previous item.
  KeyEventResult _handleVerticalNavigation(FocusNode _, KeyEvent event, List<String> focusOrder) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isDown = event.logicalKey == LogicalKeyboardKey.arrowDown;
    final isUp = event.logicalKey == LogicalKeyboardKey.arrowUp;
    if (!isDown && !isUp) return KeyEventResult.ignored;

    final currentKey = _focusTracker.lastFocusedKey;
    if (currentKey == null) return KeyEventResult.ignored;

    final currentIndex = focusOrder.indexOf(currentKey);
    if (currentIndex == -1) return KeyEventResult.ignored;

    // Scan onward past keys whose node is unmounted or focus-excluded (a row
    // can outlive its focusability, e.g. under an ExcludeFocus ancestor).
    // Returning handled without moving focus would swallow the key and also
    // suppress the framework's own directional traversal, so yield ignored
    // when no viable candidate remains in the requested direction.
    final step = isDown ? 1 : -1;
    for (var index = currentIndex + step; index >= 0 && index < focusOrder.length; index += step) {
      final node = _focusTracker.nodeFor(focusOrder[index]);
      if (node == null || !_isMounted(node) || !node.canRequestFocus) continue;
      _requestFocusAndReveal(node);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Collapse the sidebar (resets touch-expand state).
  void collapse() {
    if (_isTouchExpanded) {
      setState(() => _isTouchExpanded = false);
      _notifyFloatingPanelIfNeeded();
    }
  }

  /// Reload libraries (called when servers change or profile switches)
  void reloadLibraries() {
    final librariesProvider = context.read<LibrariesProvider>();
    librariesProvider.refresh();
  }

  /// Calculate top padding for macOS traffic lights
  double _getTopPadding(BuildContext context) {
    double basePadding = MediaQuery.paddingOf(context).top + 16;

    // On macOS, add extra padding for traffic lights (when not fullscreen)
    if (Platform.isMacOS) {
      final isFullscreen = FullscreenStateManager().isFullscreen;
      if (!isFullscreen) {
        // Traffic lights area is approximately 52 pixels high
        basePadding = basePadding < 52 ? 52 : basePadding;
      }
    }

    return basePadding;
  }

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    final librariesProvider = context.watch<LibrariesProvider>();
    final hiddenLibrariesProvider = context.watch<HiddenLibrariesProvider>();
    final hiddenKeys = hiddenLibrariesProvider.hiddenLibraryKeys;

    final allLibraries = librariesProvider.libraries;
    final visibleLibraries = <MediaLibrary>[];
    final hiddenLibraries = <MediaLibrary>[];
    final serverIds = <String>{};
    for (final lib in allLibraries) {
      if (lib.serverId != null) serverIds.add(lib.serverId!);
      if (hiddenKeys.contains(lib.globalKey)) {
        hiddenLibraries.add(lib);
      } else {
        visibleLibraries.add(lib);
      }
    }

    final isCollapsed = !_shouldExpand;
    final effectiveCollapsedWidth = collapsedWidthForContext(context);
    final horizontalPadding = horizontalPaddingForContext(context, isCollapsed: isCollapsed);
    // A configured IPTV source is Live TV too, with no media server behind it,
    // so the rail must not gate the entry on the servers alone. Nullable
    // watch: hosts without the profile scope (rail tests) simply see none.
    final hasLiveTv =
        context.watch<MultiServerProvider>().hasLiveTv ||
        (context.watch<IptvSourcesProvider?>()?.liveTvSources.isNotEmpty ?? false);
    // Nullable watch: rail tests (and any host without the profile session
    // scope) simply never show the Explore item.
    final catalogSources = context.watch<CatalogSourcesProvider?>();
    final hasExploreSource = catalogSources?.hasAnySource ?? false;
    // Independent of the Explore tab's own toggle: the Watchlist destination
    // only needs a connected source that has a watchlist to show.
    final hasWatchlist = catalogSources?.watchlistCapableSource != null;
    // Nullable watch: rail tests (and any host without the profile session
    // scope) simply never show the Now Playing item. TV-only — it is the
    // way back into the now-playing screen there; desktop already has the
    // mini-player for that.
    final musicService = context.watch<MusicPlaybackService?>();
    final nowPlayingTrack = widget.isOfflineMode || !PlatformDetector.isTV() ? null : musicService?.currentTrack;

    // Listen to fullscreen + the groupLibrariesByServer / showExploreTab /
    // showSportTab settings so the rail rebuilds when they are toggled in
    // Appearance, and to
    // both section-expanded settings so a header toggle repaints. Live TV's
    // needs it in its own right: its toggle no longer changes the tab, so
    // nothing else rebuilds the rail for it.
    return ListenableBuilder(
      listenable: Listenable.merge([
        FullscreenStateManager(),
        SettingsService.instance.listenable(SettingsService.groupLibrariesByServer),
        SettingsService.instance.listenable(SettingsService.showExploreTab),
        SettingsService.instance.listenable(SettingsService.showSportTab),
        SettingsService.instance.listenable(SettingsService.librariesSectionExpanded),
        SettingsService.instance.listenable(SettingsService.liveTvSectionExpanded),
      ]),
      builder: (context, _) {
        final hasExplore = hasExploreSource && SettingsService.instance.read(SettingsService.showExploreTab);
        // Server grouping: only when multi-server AND the user-facing toggle is on.
        final groupByServerSetting = SettingsService.instance.read(SettingsService.groupLibrariesByServer);
        final showServerHeaders = serverIds.length > 1 && groupByServerSetting;
        _collapsedServerGroupKeys.retainAll(
          _buildServerGroupStateKeys(visibleLibraries, hiddenLibraries, showServerHeaders: showServerHeaders),
        );
        final visibleRows = _buildLibraryRows(
          visibleLibraries,
          section: _LibraryNavSection.visible,
          showServerHeaders: showServerHeaders,
        );
        final hiddenRows = _buildLibraryRows(
          hiddenLibraries,
          section: _LibraryNavSection.hidden,
          showServerHeaders: showServerHeaders,
        );
        _focusTracker.pruneExcept(
          _buildValidFocusKeys(
            visibleRows: visibleRows,
            hiddenRows: hiddenRows,
            hasHiddenLibraries: hiddenLibraries.isNotEmpty,
            hasLiveTv: hasLiveTv,
            hasNowPlaying: nowPlayingTrack != null,
            hasExplore: hasExplore,
            hasWatchlist: hasWatchlist,
          ),
        );
        final focusOrder = _buildFocusOrder(
          visibleRows,
          hiddenRows,
          hasHiddenLibraries: hiddenLibraries.isNotEmpty,
          hasLiveTv: hasLiveTv,
          hasNowPlaying: nowPlayingTrack != null,
          hasExplore: hasExplore,
          hasWatchlist: hasWatchlist,
          isCollapsed: isCollapsed,
        );
        _debugAssertUniqueFocusOrder(focusOrder);
        return TapRegion(
          onTapOutside: (_) {
            if (_isTouchExpanded) {
              setState(() => _isTouchExpanded = false);
              _notifyFloatingPanelIfNeeded();
            }
          },
          child: MouseRegion(
            cursor: isCollapsed ? SystemMouseCursors.click : MouseCursor.defer,
            onEnter: (_) => _onHoverEnter(),
            onExit: (_) => _onHoverExit(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: isCollapsed ? _expandForTouch : null,
              child: AnimatedContainer(
                duration: expandDuration,
                curve: expandCurve,
                width: isCollapsed ? effectiveCollapsedWidth : expandedWidth,
                clipBehavior: Clip.hardEdge,
                decoration: const BoxDecoration(),
                child: Stack(
                  children: [
                    // Rail surface. A docked rail is transparent on TV so the
                    // full-bleed backdrop continues behind it; content is
                    // pushed clear of it, never covered. A floating panel
                    // covers content, so it paints its surface on every
                    // platform (#2079).
                    Positioned.fill(
                      child: AnimatedOpacity(
                        opacity: PlatformDetector.isTV() && !_isFloatingPanel ? 0.0 : 1.0,
                        // Shares the width morph's duration/curve: a shorter
                        // fade strands a fully grown, fully transparent panel
                        // over the content part-way through the collapse.
                        duration: expandDuration,
                        curve: expandCurve,
                        child: AnimatedContainer(
                          duration: expandDuration,
                          curve: expandCurve,
                          decoration: BoxDecoration(
                            color: t.surface,
                            // Open rails read as an M3E panel: rounded
                            // trailing corners, extra-rounded plus an edge
                            // shadow while floating over content (modal)
                            // instead of pushing it.
                            borderRadius: isCollapsed
                                ? BorderRadius.zero
                                : BorderRadius.horizontal(
                                    right: Radius.circular(_isFloatingPanel ? overlayCornerRadius : t.radiusLg),
                                  ),
                            boxShadow: _isFloatingPanel
                                ? flatShadows(context, [
                                    BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 24),
                                  ])
                                : const [],
                          ),
                        ),
                      ),
                    ),
                    IgnorePointer(
                      ignoring: isCollapsed,
                      child: Focus(
                        canRequestFocus: false,
                        skipTraversal: true,
                        onKeyEvent: (node, event) => _handleVerticalNavigation(node, event, focusOrder),
                        child: Column(
                          children: [
                            SizedBox(height: _getTopPadding(context)),
                            Expanded(
                              child: AnimatedPadding(
                                padding: .symmetric(horizontal: horizontalPadding),
                                duration: expandDuration,
                                curve: expandCurve,
                                child: ListView(
                                  padding: EdgeInsets.zero,
                                  clipBehavior: Clip.hardEdge,
                                  children: [
                                    if (widget.isOfflineMode && widget.onReconnect != null) ...[
                                      _buildReconnectItem(isCollapsed: isCollapsed),
                                      const SizedBox(height: _itemGap),
                                    ],
                                    if (!widget.isOfflineMode) ...[
                                      _buildNavItem(
                                        icon: NavigationTab.iconFor(NavigationTabId.discover),
                                        label: Translations.of(context).common.home,
                                        isSelected: widget.selectedTab == NavigationTabId.discover,
                                        onTap: () => widget.onDestinationSelected(NavigationTabId.discover),
                                        focusNode: _focusTracker.get(_kHome),
                                        isCollapsed: isCollapsed,
                                      ),
                                      const SizedBox(height: _itemGap),
                                      if (hasWatchlist) ...[
                                        _buildNavItem(
                                          icon: NavigationTab.iconFor(NavigationTabId.watchlist),
                                          label: Translations.of(context).explore.rows.watchlist,
                                          isSelected: widget.selectedTab == NavigationTabId.watchlist,
                                          onTap: () => widget.onDestinationSelected(NavigationTabId.watchlist),
                                          focusNode: _focusTracker.get(_kWatchlist),
                                          isCollapsed: isCollapsed,
                                        ),
                                        const SizedBox(height: _itemGap),
                                      ],
                                      // Now Playing — only while a music session is live.
                                      if (nowPlayingTrack != null && musicService != null) ...[
                                        _buildNowPlayingItem(nowPlayingTrack, musicService, isCollapsed: isCollapsed),
                                        const SizedBox(height: _itemGap),
                                      ],
                                      _buildLibrariesSection(
                                        visibleRows,
                                        hiddenRows,
                                        hiddenLibraries.length,
                                        t,
                                        isCollapsed: isCollapsed,
                                      ),
                                      const SizedBox(height: _itemGap),
                                      if (hasLiveTv) ...[
                                        // Redrawn when the screen's answers
                                        // change: the star and the arrangement
                                        // row depend on state it owns.
                                        ListenableBuilder(
                                          listenable:
                                              widget.liveTvActions?.sidebarRevision ?? const AlwaysStoppedAnimation(0),
                                          builder: (context, _) => _buildLiveTvSection(t, isCollapsed: isCollapsed),
                                        ),
                                        const SizedBox(height: _itemGap),
                                      ],
                                      if (hasExplore) ...[
                                        _buildNavItem(
                                          icon: NavigationTab.iconFor(NavigationTabId.explore),
                                          label: Translations.of(context).navigation.explore,
                                          isSelected: widget.selectedTab == NavigationTabId.explore,
                                          onTap: () => widget.onDestinationSelected(NavigationTabId.explore),
                                          focusNode: _focusTracker.get(_kExplore),
                                          isCollapsed: isCollapsed,
                                        ),
                                        const SizedBox(height: _itemGap),
                                      ],
                                      if (_showSport) ...[
                                        _buildNavItem(
                                          icon: NavigationTab.iconFor(NavigationTabId.sport),
                                          label: Translations.of(context).navigation.sport,
                                          isSelected: widget.selectedTab == NavigationTabId.sport,
                                          onTap: () => widget.onDestinationSelected(NavigationTabId.sport),
                                          focusNode: _focusTracker.get(_kSport),
                                          isCollapsed: isCollapsed,
                                        ),
                                        const SizedBox(height: _itemGap),
                                      ],
                                      _buildNavItem(
                                        icon: NavigationTab.iconFor(NavigationTabId.search),
                                        label: Translations.of(context).common.search,
                                        isSelected: widget.selectedTab == NavigationTabId.search,
                                        onTap: () => widget.onDestinationSelected(NavigationTabId.search),
                                        focusNode: _focusTracker.get(_kSearch),
                                        isCollapsed: isCollapsed,
                                      ),
                                      const SizedBox(height: _itemGap),
                                    ],
                                    // Downloads (hidden on Apple TV — no user
                                    // file storage)
                                    if (_showDownloads) ...[
                                      _buildNavItem(
                                        icon: NavigationTab.iconFor(NavigationTabId.downloads),
                                        label: Translations.of(context).navigation.downloads,
                                        isSelected: widget.selectedTab == NavigationTabId.downloads,
                                        onTap: () => widget.onDestinationSelected(NavigationTabId.downloads),
                                        focusNode: _focusTracker.get(_kDownloads),
                                        isCollapsed: isCollapsed,
                                      ),
                                      const SizedBox(height: _itemGap),
                                    ],
                                    _buildNavItem(
                                      icon: NavigationTab.iconFor(NavigationTabId.settings),
                                      label: Translations.of(context).common.settings,
                                      isSelected: widget.selectedTab == NavigationTabId.settings,
                                      onTap: () => widget.onDestinationSelected(NavigationTabId.settings),
                                      focusNode: _focusTracker.get(_kSettings),
                                      isCollapsed: isCollapsed,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_showFullscreenToggle)
                              AnimatedPadding(
                                padding: .fromLTRB(horizontalPadding, 0, horizontalPadding, 12),
                                duration: expandDuration,
                                curve: expandCurve,
                                child: _buildFullscreenItem(isCollapsed: isCollapsed),
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
      },
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    IconData? selectedIcon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required FocusNode focusNode,
    required bool isCollapsed,
    bool autofocus = false,
    Widget? trailing,
    double iconFill = navIconFill,
  }) {
    final t = tokens(context);

    return NavigationRailItem(
      icon: icon,
      selectedIcon: selectedIcon,
      label: Text(
        label,
        style: TextStyle(fontSize: 14, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400),
        overflow: .ellipsis,
        maxLines: 1,
      ),
      labelColor: isSelected ? t.text : t.textMuted,
      collapsedLabel: label,
      trailing: trailing,
      iconFill: iconFill,
      isSelected: isSelected,
      isCollapsed: isCollapsed,
      onTap: onTap,
      focusNode: focusNode,
      autofocus: autofocus,
      suppressSelectedBackground: widget.isSidebarFocused,
      onNavigateRight: widget.onNavigateToContent,
    );
  }

  /// "Now Playing" rail item — the shared equalizer as its icon (animating
  /// while audio plays), the current track's title as its label. SELECT/tap
  /// opens the now-playing screen.
  Widget _buildNowPlayingItem(MediaItem track, MusicPlaybackService musicService, {required bool isCollapsed}) {
    final t = tokens(context);
    final nowPlayingLabel = Translations.of(context).music.nowPlaying;
    final trackTitle = track.title ?? '';

    Widget buildLabel(double opacity) {
      return Column(
        crossAxisAlignment: .start,
        mainAxisSize: .min,
        children: [
          Text(
            nowPlayingLabel,
            style: TextStyle(
              fontSize: 14,
              fontWeight: .w600,
              color: t.text.withValues(alpha: t.text.a * opacity),
            ),
            overflow: .ellipsis,
            maxLines: 1,
          ),
          Text(
            trackTitle,
            style: TextStyle(fontSize: 11, color: t.textMuted.withValues(alpha: t.textMuted.a * opacity)),
            overflow: .ellipsis,
            maxLines: 1,
          ),
        ],
      );
    }

    return NavigationRailItem(
      icon: Symbols.music_note_rounded,
      iconWidget: SizedBox(
        width: 22,
        child: Center(
          child: EqualizerIcon(animate: musicService.isPlaying, color: t.text),
        ),
      ),
      label: buildLabel(1),
      labelBuilder: buildLabel,
      collapsedLabel: Translations.of(context).music.nowPlaying,
      isSelected: false,
      isCollapsed: isCollapsed,
      onTap: () => unawaited(openNowPlaying(context)),
      focusNode: _focusTracker.get(_kNowPlaying),
      onNavigateRight: widget.onNavigateToContent,
    );
  }

  Widget _buildReconnectItem({required bool isCollapsed}) {
    final t = tokens(context);

    return NavigationRailItem(
      icon: widget.isReconnecting ? Symbols.sync_rounded : Symbols.wifi_rounded,
      label: widget.isReconnecting
          ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: t.text))
          : Text(
              Translations.of(context).common.reconnect,
              style: const TextStyle(fontSize: 14, fontWeight: .w400),
              overflow: .ellipsis,
              maxLines: 1,
            ),
      labelColor: widget.isReconnecting ? null : t.textMuted,
      collapsedLabel: Translations.of(context).common.reconnect,
      isSelected: false,
      isCollapsed: isCollapsed,
      // ignore: no-empty-block - no-op tap handler while reconnecting
      onTap: widget.isReconnecting ? () {} : () => widget.onReconnect?.call(),
      focusNode: _focusTracker.get(_kReconnect),
      onNavigateRight: widget.onNavigateToContent,
    );
  }

  Widget _buildFullscreenItem({required bool isCollapsed}) {
    final t = tokens(context);
    final isFullscreen = FullscreenStateManager().isFullscreen;
    final label = isFullscreen
        ? Translations.of(context).common.exitFullscreen
        : Translations.of(context).common.fullscreen;

    return NavigationRailItem(
      icon: isFullscreen ? Symbols.fullscreen_exit_rounded : Symbols.fullscreen_rounded,
      label: Text(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: .w400),
        overflow: .ellipsis,
        maxLines: 1,
      ),
      labelColor: t.textMuted,
      collapsedLabel: label,
      isSelected: false,
      isCollapsed: isCollapsed,
      onTap: () => unawaited(FullscreenStateManager().toggleFullscreen()),
      focusNode: _focusTracker.get(_kFullscreen),
      onNavigateRight: widget.onNavigateToContent,
    );
  }

  Widget _buildLibrariesSection(
    List<_LibraryNavRow> visibleRows,
    List<_LibraryNavRow> hiddenRows,
    int hiddenLibraryCount,
    dynamic t, {
    bool isCollapsed = false,
  }) {
    final librariesProvider = context.watch<LibrariesProvider>();
    final isLoading = librariesProvider.isLoading;
    final isLibrariesTabSelected = widget.selectedTab == NavigationTabId.libraries;
    final allEmpty = visibleRows.isEmpty && hiddenLibraryCount == 0;
    final headerLabelColor = isLibrariesTabSelected ? t.text : t.textMuted;

    Widget buildChevron(double opacity) {
      return AppIcon(
        _librariesExpanded ? Symbols.expand_less_rounded : Symbols.expand_more_rounded,
        fill: 1,
        size: 18,
        color: t.textMuted.withValues(alpha: t.textMuted.a * opacity),
      );
    }

    return Column(
      crossAxisAlignment: .start,
      children: [
        // A destination-sized row like Home/Search — same height, icon and
        // label metrics — with the chevron as the expand affordance. The
        // smaller header type is reserved for the nested sub-headers.
        NavigationRailItem(
          icon: NavigationTab.iconFor(NavigationTabId.libraries),
          label: Text(
            Translations.of(context).navigation.libraries,
            style: TextStyle(fontSize: 14, fontWeight: isLibrariesTabSelected ? FontWeight.w600 : FontWeight.w400),
            overflow: .ellipsis,
            maxLines: 1,
          ),
          labelColor: headerLabelColor,
          collapsedLabel: Translations.of(context).navigation.libraries,
          trailing: buildChevron(1),
          trailingBuilder: buildChevron,
          isSelected: isLibrariesTabSelected,
          isCollapsed: isCollapsed,
          onTap: () =>
              unawaited(SettingsService.instance.write(SettingsService.librariesSectionExpanded, !_librariesExpanded)),
          focusNode: _focusTracker.get(_kLibraries),
          // A selected library owns the highlight; the header only shows it
          // for the bare Libraries tab.
          suppressSelectedBackground: widget.isSidebarFocused || widget.selectedLibraryKey != null,
          focusAlpha: 0.08,
          selectedFocusAlpha: 0.1,
          onNavigateRight: widget.onNavigateToContent,
        ),

        TweenAnimationBuilder<double>(
          tween: Tween(end: (_librariesExpanded && !isCollapsed) ? 1.0 : 0.0),
          duration: expandDuration,
          curve: expandCurve,
          builder: (context, value, child) {
            return ClipRect(
              child: Align(alignment: .topCenter, heightFactor: value, child: child),
            );
          },
          child: ExcludeFocus(
            excluding: !_librariesExpanded || isCollapsed,
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .start,
              children: [
                const SizedBox(height: 4),
                if (isLoading)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: t.textMuted),
                      ),
                    ),
                  )
                else if (allEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      Translations.of(context).libraries.noLibrariesFound,
                      style: TextStyle(fontSize: 12, color: t.textMuted),
                    ),
                  )
                else ...[
                  if (visibleRows.isNotEmpty) _buildLibraryGroupedColumn(visibleRows, t),
                  if (hiddenLibraryCount > 0) ...[
                    _buildHiddenLibrariesHeader(hiddenLibraryCount, t),
                    if (_hiddenLibrariesExpanded) _buildLibraryGroupedColumn(hiddenRows, t),
                  ],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Live TV as a section: the tab itself, and under it what the screen used
  /// to keep in an app bar.
  ///
  /// The header is a destination, unlike the Libraries one, so it cannot be a
  /// bare toggle — but unfolding is still its own act. Going *to* Live TV
  /// leaves the section as the viewer left it; pressing the entry you are
  /// already on opens and closes the rows. Otherwise every trip back to the
  /// sidebar from the guide reopened a list nobody asked for, and the way out
  /// of it was three more presses.
  Widget _buildLiveTvSection(dynamic t, {required bool isCollapsed}) {
    final rows = _liveTvActionRows;
    final isSelected = widget.selectedTab == NavigationTabId.liveTv;
    final expanded = _liveTvExpanded && rows.isNotEmpty;

    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      children: [
        _buildNavItem(
          icon: NavigationTab.iconFor(NavigationTabId.liveTv),
          label: Translations.of(context).navigation.liveTv,
          trailing: rows.isEmpty
              ? null
              : AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: tokens(context).fast,
                  child: AppIcon(Symbols.expand_more_rounded, fill: 1, size: 20, color: t.textMuted),
                ),
          isSelected: isSelected,
          onTap: () {
            // Already here: the press is about the rows, and nothing else can
            // ask for them. With no rows to show there is nothing to toggle,
            // so it stays a plain destination.
            if (isSelected && rows.isNotEmpty) {
              unawaited(SettingsService.instance.write(SettingsService.liveTvSectionExpanded, !_liveTvExpanded));
              return;
            }
            widget.onDestinationSelected(NavigationTabId.liveTv);
          },
          focusNode: _focusTracker.get(_kLiveTv),
          isCollapsed: isCollapsed,
        ),
        TweenAnimationBuilder<double>(
          tween: Tween(end: (expanded && !isCollapsed) ? 1.0 : 0.0),
          duration: tokens(context).normal,
          curve: Curves.easeOutCubic,
          builder: (context, value, child) => ClipRect(
            child: Align(alignment: .topCenter, heightFactor: value, child: child),
          ),
          child: ExcludeFocus(
            excluding: !expanded || isCollapsed,
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .start,
              children: [
                const SizedBox(height: 4),
                for (final row in rows)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 2),
                    child: _buildNavItem(
                      icon: row.icon,
                      selectedIcon: row.icon,
                      iconFill: row.fill,
                      label: row.label,
                      isSelected: false,
                      onTap: row.onTap,
                      focusNode: _focusTracker.get(row.key),
                      isCollapsed: isCollapsed,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Get set of library names that appear more than once (not globally unique)
  Set<String> _getNonUniqueLibraryNames(List<MediaLibrary> libraries) {
    final nameCounts = <String, int>{};
    for (final lib in libraries) {
      nameCounts[lib.title] = (nameCounts[lib.title] ?? 0) + 1;
    }
    return nameCounts.entries.where((e) => e.value > 1).map((e) => e.key).toSet();
  }

  Widget _buildLibraryGroupedColumn(List<_LibraryNavRow> rows, dynamic t) {
    return Column(
      crossAxisAlignment: .start,
      children: rows.map((row) {
        return switch (row) {
          _LibraryServerHeaderRow(:final section, :final serverId, :final serverName) => _buildServerHeader(
            section,
            ServerId(serverId),
            serverName,
            t,
          ),
          _LibraryItemRow(:final section, :final library, :final showServerName) => _buildLibraryItem(
            section,
            library,
            t,
            showServerName: showServerName,
          ),
        };
      }).toList(),
    );
  }

  Widget _buildServerHeader(_LibraryNavSection section, ServerId serverId, String serverName, dynamic t) {
    // Resolve backend per server so the badge matches the brand. Falls back
    // to the generic `dns` icon if the client isn't registered yet (rare —
    // can happen during a profile switch before the manager rehydrates).
    final backend = context.read<MultiServerProvider>().serverManager.getClient(serverId)?.backend;
    return _buildCollapsibleHeader(
      focusKey: _serverHeaderFocusKey(section, serverId),
      icon: Symbols.dns_rounded,
      iconSize: 14,
      leading: backend == null ? null : BackendBadge(backend: backend, size: 14, color: t.textMuted),
      label: serverName,
      labelStyle: TextStyle(fontSize: 11, fontWeight: .w600, letterSpacing: 0.4, color: t.textMuted),
      verticalPadding: 6,
      isExpanded: !_collapsedServerGroupKeys.contains(_serverGroupStateKey(section, serverId)),
      onToggle: () => _toggleServerCollapse(section, serverId),
      t: t,
    );
  }

  void _toggleServerCollapse(_LibraryNavSection section, ServerId serverId) {
    final groupKey = _serverGroupStateKey(section, serverId);
    setState(() {
      if (!_collapsedServerGroupKeys.add(groupKey)) {
        _collapsedServerGroupKeys.remove(groupKey);
      }
    });
  }

  Widget _buildHiddenLibrariesHeader(int count, dynamic t) {
    return _buildCollapsibleHeader(
      focusKey: _kHiddenLibraries,
      icon: Symbols.visibility_off_rounded,
      iconSize: 16,
      label: Translations.of(context).libraries.hiddenLibrariesCount(count: count),
      labelStyle: TextStyle(fontSize: 12, fontWeight: .w500, color: t.textMuted),
      verticalPadding: 8,
      isExpanded: _hiddenLibrariesExpanded,
      onToggle: () => setState(() => _hiddenLibrariesExpanded = !_hiddenLibrariesExpanded),
      t: t,
    );
  }

  Widget _buildCollapsibleHeader({
    required String focusKey,
    required IconData icon,
    required double iconSize,
    Widget? leading,
    required String label,
    required TextStyle labelStyle,
    required double verticalPadding,
    required bool isExpanded,
    required VoidCallback onToggle,
    required dynamic t,
  }) {
    final focusNode = _focusTracker.get(focusKey);
    final radius = BorderRadius.circular(MonoTokens.radiusFull);
    // Sub-section header at full rail width; the smaller type alone carries
    // the hierarchy, matching M3E expanded-rail sections.
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, _) => Focus(
        focusNode: focusNode,
        onKeyEvent: (node, event) =>
            _handleRailItemKey(event, onSelect: onToggle, onNavigateRight: widget.onNavigateToContent),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            canRequestFocus: false,
            onTap: onToggle,
            borderRadius: radius,
            child: Container(
              decoration: BoxDecoration(
                color: focusNode.hasFocus && InputModeTracker.isKeyboardMode(context)
                    ? t.text.withValues(alpha: 0.08)
                    : null,
                borderRadius: radius,
              ),
              clipBehavior: Clip.hardEdge,
              child: UnconstrainedBox(
                alignment: .centerLeft,
                constrainedAxis: Axis.vertical,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: expandedWidth - 24,
                  child: Padding(
                    padding: .symmetric(vertical: verticalPadding, horizontal: 17),
                    child: Row(
                      children: [
                        leading ?? AppIcon(icon, fill: 1, size: iconSize, color: t.textMuted),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text(label, style: labelStyle, overflow: .ellipsis),
                        ),
                        AppIcon(
                          isExpanded ? Symbols.expand_less_rounded : Symbols.expand_more_rounded,
                          fill: 1,
                          size: 16,
                          color: t.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLibraryItem(_LibraryNavSection section, MediaLibrary library, dynamic t, {bool showServerName = false}) {
    final isSelected =
        widget.selectedTab == NavigationTabId.libraries && widget.selectedLibraryKey == library.globalKey;
    final focusKey = _libraryItemFocusKey(section, library);
    final focusNode = _focusTracker.get(focusKey);

    return NavigationRailItem(
      icon: ContentTypeHelper.getLibraryIcon(library.kind.id),
      selectedIcon: ContentTypeHelper.getLibraryIcon(library.kind.id),
      label: Column(
        crossAxisAlignment: .start,
        mainAxisSize: .min,
        children: [
          Text(
            library.title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected ? t.text : t.textMuted,
            ),
            overflow: .ellipsis,
          ),
          if (showServerName)
            Text(
              library.serverName!,
              style: TextStyle(fontSize: 9, color: t.textMuted.withValues(alpha: 0.4)),
              overflow: .ellipsis,
            ),
        ],
      ),
      isSelected: isSelected,
      onTap: () => widget.onLibrarySelected(library.globalKey),
      focusNode: focusNode,
      iconSize: 18,
      expandedHeight: 40,
      suppressSelectedBackground: widget.isSidebarFocused,
      onNavigateRight: widget.onNavigateToContent,
    );
  }
}
