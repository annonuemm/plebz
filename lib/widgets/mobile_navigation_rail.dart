import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../i18n/strings.g.dart';
import '../redesign/ocker_skin.dart' show isOcker;
import '../theme/mono_tokens.dart';
import '../navigation/navigation_tabs.dart';
import 'app_icon.dart';
import 'navigation_label_fit.dart';

/// The mobile shell's navigation in landscape: the bottom [NavigationBar]'s
/// destinations on a leading Material [NavigationRail], so a wide, short
/// viewport keeps its height for content. Deliberately not the desktop/TV
/// sidebar — it carries no libraries, no expansion, no focus choreography.
///
/// Mirrors the bottom bar's extras: the offline reconnect affordance (as the
/// rail's leading action) and the long-press library quick picker on the
/// Libraries destination.
class MobileNavigationRail extends StatelessWidget {
  const MobileNavigationRail({
    super.key,
    required this.tabs,
    required this.selectedTab,
    required this.showLabels,
    required this.onDestinationSelected,
    this.onLibrariesLongPress,
    this.isOffline = false,
    this.isReconnecting = false,
    this.onReconnect,
  });

  final List<NavigationTab> tabs;
  final NavigationTabId selectedTab;
  final bool showLabels;
  final ValueChanged<NavigationTabId> onDestinationSelected;
  final VoidCallback? onLibrariesLongPress;
  final bool isOffline;
  final bool isReconnecting;
  final VoidCallback? onReconnect;

  /// Material 3 rail indicator size; the long-press target matches it so the
  /// hold works anywhere on the visible pill, not only on the glyph.
  static const Size _indicatorSize = Size(56, 32);

  /// Material 3 labelled-destination extent (indicator, label, spacing) and
  /// the leading action's extent, used to decide whether labels fit.
  /// Estimates: the scroll view below is the exact fallback.
  static const double _labelledExtent = 72;
  static const double _leadingExtent = 56;

  /// Whether every destination fits at once with labels on a rail of
  /// [height]: a phone in landscape has ~410dp, six labelled destinations
  /// need more, so labels give way before anything has to scroll.
  @visibleForTesting
  static bool labelsFit({required int destinations, required bool hasLeading, required double height}) {
    final needed = destinations * _labelledExtent + (hasLeading ? _leadingExtent : 0);
    return needed <= height;
  }

  /// How wide the redesigns' rail is on a phone or a tablet (Plebz).
  static const double redesignRailWidth = 96;

  /// Its glyphs, a step up from Material's 24: at that size, on a rail the
  /// screen's height, the places read small (the user's call).
  static const double redesignIconSize = 28;

  @override
  Widget build(BuildContext context) {
    if (isOcker(context)) return _buildRedesign(context);
    return _buildRail(context);
  }

  /// Plebz: under the redesigns the television's rail stood upright on a
  /// phone or a tablet (the user's call, 2026-11-03: a phone or a tablet
  /// looks as the television does, as far as it can). The screen's full
  /// height at its leading edge, the palette's own solid ground with a
  /// hairline on its open side — no column of glass floating clear of the
  /// edges — larger glyphs, and the place on show told as on the
  /// television: its glyph filled, its word bright and bold, the others
  /// quieter, no capsule behind it.
  Widget _buildRedesign(BuildContext context) {
    final tk = tokens(context);
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final ground = Color.alphaBlend(tk.ink(0.03), tk.bg);
    final quiet = tk.ink(0.62);
    final label = (Theme.of(context).textTheme.labelMedium ?? const TextStyle(fontSize: 12)).copyWith(fontSize: 13);
    final hairline = BorderSide(color: tk.ink(0.10));
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ground,
        border: isRtl ? Border(left: hairline) : Border(right: hairline),
      ),
      child: SafeArea(
        left: !isRtl,
        right: isRtl,
        child: SizedBox(
          width: redesignRailWidth,
          child: NavigationRailTheme(
            data: NavigationRailTheme.of(context).copyWith(
              minWidth: redesignRailWidth,
              backgroundColor: Colors.transparent,
              indicatorColor: Colors.transparent,
              selectedIconTheme: IconThemeData(color: tk.ink(1), fill: 1, size: redesignIconSize),
              unselectedIconTheme: IconThemeData(color: quiet, size: redesignIconSize),
              selectedLabelTextStyle: label.copyWith(color: tk.ink(1), fontWeight: FontWeight.w700),
              unselectedLabelTextStyle: label.copyWith(color: quiet),
            ),
            // One line per label, as on the bar: a word broken in two
            // ("Mediathek-en") read as two places.
            child: NavigationLabelScale(
              labels: [for (final tab in tabs) tab.getLabel()],
              // A few points either side of a label; the chosen one is set
              // heavier.
              labelWidth: redesignRailWidth - 16,
              style: label,
              child: _buildRail(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRail(BuildContext context) {
    final selectedIndex = tabs.indexWhere((tab) => tab.id == selectedTab);
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final labelled = showLabels && labelsFit(destinations: tabs.length, hasLeading: isOffline, height: height);
        final rail = NavigationRail(
          selectedIndex: selectedIndex >= 0 ? selectedIndex : null,
          onDestinationSelected: (index) => onDestinationSelected(tabs[index].id),
          labelType: labelled ? NavigationRailLabelType.all : NavigationRailLabelType.none,
          groupAlignment: 0,
          leading: isOffline ? _reconnectAction(context) : null,
          destinations: [for (final tab in tabs) _destination(context, tab)],
        );
        // NavigationRail needs a bounded height. Give it at least the viewport
        // and let it grow past that inside a scroll view when even icon-only
        // destinations cannot fit (seven tabs plus reconnect on a small phone).
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: height),
            child: IntrinsicHeight(child: rail),
          ),
        );
      },
    );
  }

  Widget _reconnectAction(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: IconButton(
        tooltip: t.common.reconnect,
        onPressed: isReconnecting ? null : onReconnect,
        icon: isReconnecting
            ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: primary))
            : AppIcon(Symbols.wifi_rounded, size: 18, color: primary),
      ),
    );
  }

  NavigationRailDestination _destination(BuildContext context, NavigationTab tab) {
    // The redesigns' rail fills the glyph of the place one is at, as the
    // television's does.
    final redesign = isOcker(context);
    Widget glyph(double fill) {
      Widget icon = AppIcon(tab.icon, fill: fill, weight: navIconWeight, marksState: true);
      final onLongPress = onLibrariesLongPress;
      if (tab.id == NavigationTabId.libraries && onLongPress != null) {
        // Only a long-press recogniser: taps fall through to the rail's own
        // destination handling, exactly like the bottom bar's overlay.
        icon = GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onLongPress: () {
            Feedback.forLongPress(context);
            onLongPress();
          },
          child: SizedBox.fromSize(
            size: _indicatorSize,
            child: Center(child: icon),
          ),
        );
      }
      return icon;
    }

    return NavigationRailDestination(
      icon: glyph(navIconFill),
      selectedIcon: redesign ? glyph(1) : null,
      label: Text(tab.getLabel()),
    );
  }
}
