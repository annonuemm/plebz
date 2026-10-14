import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../i18n/strings.g.dart';
import '../redesign/ocker_glas_look.dart';
import '../redesign/ocker_skin.dart' show OckerGlass;
import '../theme/liquid_glass.dart';
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
  static const double _compactExtent = 56;
  static const double _leadingExtent = 56;

  /// Whether every destination fits at once with labels on a rail of
  /// [height]: a phone in landscape has ~410dp, six labelled destinations
  /// need more, so labels give way before anything has to scroll.
  @visibleForTesting
  static bool labelsFit({required int destinations, required bool hasLeading, required double height}) {
    final needed = destinations * _labelledExtent + (hasLeading ? _leadingExtent : 0);
    return needed <= height;
  }

  /// How far Apple's floating rail ([ockerGlasTouch]) stays from the
  /// screen's edges, and how wide it is.
  static const double appleMargin = 8;
  static const double appleRailWidth = 88;

  /// How much of the page Apple's floating rail covers from the leading
  /// edge, with the same gap again before the page's own content: what the
  /// shell hands the page as its leading padding.
  static double appleExtent(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final edge = Directionality.of(context) == TextDirection.rtl ? padding.right : padding.left;
    return (edge > appleMargin ? edge : appleMargin) + appleRailWidth + appleMargin;
  }

  @override
  Widget build(BuildContext context) {
    if (ockerGlasTouch(context)) return _buildApple(context);
    return _buildRail(context);
  }

  /// Plebz: on iPhone and iPad under the redesign on Apple's build, the same
  /// rail as a column of glass floating clear of the screen's edges — Apple's
  /// sidebar — and the place one is at on the accent's capsule, in the
  /// accent. Material's own rail painted its marker in the rail's colour, so
  /// nothing showed where one was.
  Widget _buildApple(BuildContext context) {
    final tk = tokens(context);
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    // The places not chosen at 85 %: over a bright poster under the glass a
    // quieter ink was lost.
    final quiet = tk.ink(0.85);
    final labelStyle = Theme.of(context).textTheme.labelMedium;
    return SafeArea(
      left: !isRtl,
      right: isRtl,
      minimum: const EdgeInsets.all(appleMargin),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // As tall as its places and no taller, centred: the bottom bar
          // stood on its side, not a column of glass the screen's height
          // with a few glyphs in its middle.
          final available = constraints.maxHeight;
          final labelled =
              showLabels &&
              labelsFit(destinations: tabs.length, hasLeading: isOffline, height: available - 2 * _applePadding);
          final needed =
              tabs.length * (labelled ? _labelledExtent : _compactExtent) +
              (isOffline ? _leadingExtent : 0) +
              2 * _applePadding;
          return Align(
            alignment: AlignmentDirectional.centerStart,
            child: SizedBox(
              width: appleRailWidth,
              height: needed < available ? needed : available,
              child: OckerGlass(
                borderRadius: BorderRadius.circular(appleRailWidth / 2),
                scrimInset: 0,
                liquid: true,
                // A pane this narrow keeps the thin rim of the buttons'
                // bubble: the pane's own would bend most of what passes
                // under it.
                lensThickness: OckerLiquidGlass.bubbleThickness,
                lensStrength: OckerLiquidGlass.bubbleStrength,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: _applePadding),
                  child: MediaQuery.removePadding(
                    context: context,
                    removeLeft: true,
                    removeRight: true,
                    removeTop: true,
                    removeBottom: true,
                    child: NavigationRailTheme(
                      data: NavigationRailTheme.of(context).copyWith(
                        minWidth: appleRailWidth,
                        backgroundColor: Colors.transparent,
                        indicatorColor: tk.flat ? tk.ink(0.12) : tk.accent.withValues(alpha: tk.accentWash),
                        indicatorShape: const StadiumBorder(),
                        selectedIconTheme: IconThemeData(color: tk.accent, fill: 1),
                        unselectedIconTheme: IconThemeData(color: quiet),
                        selectedLabelTextStyle: labelStyle?.copyWith(color: tk.accent, fontWeight: FontWeight.w600),
                        unselectedLabelTextStyle: labelStyle?.copyWith(color: quiet),
                      ),
                      // One line per label, as on the bar: a word broken in
                      // two ("Mediathek-en") read as two places.
                      child: NavigationLabelScale(
                        labels: [for (final tab in tabs) tab.getLabel()],
                        // The rail keeps a few points either side of a
                        // label, and the chosen one is set heavier.
                        labelWidth: appleRailWidth - 24,
                        style: labelStyle ?? const TextStyle(fontSize: 12),
                        child: _buildRail(context),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Room above the first place and below the last inside Apple's capsule.
  static const double _applePadding = 12;

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
    // Apple's rail fills the glyph of the place one is at, as its tab bar does.
    final apple = ockerGlasTouch(context);
    Widget glyph(double fill) {
      Widget icon = AppIcon(tab.icon, fill: fill, weight: navIconWeight);
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
      selectedIcon: apple ? glyph(1) : null,
      label: Text(tab.getLabel()),
    );
  }
}
