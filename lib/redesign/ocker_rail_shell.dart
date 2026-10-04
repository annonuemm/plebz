import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../media/ids.dart';
import '../providers/multi_server_provider.dart';
import '../services/plex_client.dart';
import '../services/settings_service.dart';
import '../widgets/settings_builder.dart';

import '../navigation/navigation_tabs.dart';
import '../theme/glass_backdrop.dart';
import '../theme/mono_tokens.dart';
import '../widgets/system_clock.dart';
import 'ocker_header_slot.dart';
import 'ocker_side_rail.dart';
import 'ocker_skin.dart';
import 'ocker_submenu.dart';
import 'ocker_type.dart';
import 'ultra_blur_backdrop.dart';

/// The frame every screen sits in under "Redesign – Glas": the rail down the
/// left, the screen beside it.
///
/// Focus is kept in two scopes, the same two the standard rail build uses, so
/// the screens' existing "go to the navigation" and "come back to the
/// content" calls keep working without knowing which chrome is on show. Under
/// everything lies the glass ground, and a screen puts its own chrome in the
/// slot this provides.
///
/// The screen is told it is exactly as wide as the room beside the rail. The
/// redesign's screens work their columns out from the width they are given —
/// the panel, the gutter, five posters — and a screen that believed it had the
/// whole width drew its right-hand column off the edge by the rail's strip.
class OckerRailShell extends StatefulWidget {
  /// The destinations whose ground follows the focused title, where that is
  /// switched on ([SettingsService.glasUltraBlur]).
  static const Set<NavigationTabId> ultraBlurDestinations = {NavigationTabId.discover, NavigationTabId.explore};

  /// The destinations, already filtered — see [OckerSideRail.tabs].
  final List<NavigationTab> tabs;

  final NavigationTabId selectedTab;
  final ValueChanged<NavigationTabId> onDestinationSelected;

  /// Hands focus back to the content beside the rail.
  final VoidCallback onNavigateToContent;

  /// See [OckerSideRail.onReselect].
  final bool Function(NavigationTabId)? onReselect;

  /// See [OckerSideRail.menuFor].
  final OckerRailMenu? Function(NavigationTabId)? menuFor;

  /// Whether the rail is open — the navigation holds focus.
  final bool expanded;

  /// Lets the host put focus on a destination from outside.
  final GlobalKey<OckerSideRailState> railKey;

  final FocusScopeNode railFocusScope;
  final FocusScopeNode contentFocusScope;

  final Widget content;

  const OckerRailShell({
    super.key,
    required this.tabs,
    required this.selectedTab,
    required this.onDestinationSelected,
    required this.onNavigateToContent,
    required this.expanded,
    this.onReselect,
    this.menuFor,
    required this.railKey,
    required this.railFocusScope,
    required this.contentFocusScope,
    required this.content,
  });

  /// The screen's chrome and the clock, top right, for tests.
  static const chromeKey = Key('ocker_rail_shell_chrome');

  @override
  State<OckerRailShell> createState() => _OckerRailShellState();
}

class _OckerRailShellState extends State<OckerRailShell> {
  /// What the screen on show wants beside the clock. See [OckerHeaderSlot].
  final _headerSlot = ValueNotifier<WidgetBuilder?>(null);

  /// The ground's colours under the focused Plex title, while that is
  /// switched on (see [UltraBlurAmbient]). Kept across destinations, so coming
  /// back to Home finds the colours it left.
  UltraBlurAmbient? _ultraBlur;

  UltraBlurAmbient? _ultraBlurFor(bool enabled) {
    if (!enabled) {
      // After the frame: the layer letting go of it is still listening now.
      final old = _ultraBlur;
      if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      return _ultraBlur = null;
    }
    return _ultraBlur ??= UltraBlurAmbient((
      owner: (serverId) {
        final client = context.read<MultiServerProvider?>()?.serverManager.getClient(ServerId(serverId));
        return client is PlexClient ? client : null;
      },
      any: () =>
          context.read<MultiServerProvider?>()?.serverManager.onlineClients.values.whereType<PlexClient>().firstOrNull,
    ));
  }

  @override
  void dispose() {
    _headerSlot.dispose();
    _ultraBlur?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final railWidth = OckerSideRail.collapsedWidth(context);

    return SettingValueBuilder<bool>(
      pref: SettingsService.glasUltraBlur,
      builder: (context, ultraBlurOn, _) {
        // Home and Explore only (the user's call): every other destination
        // keeps the theme's own ground, and its posters report to nothing.
        final ultraBlur =
            _ultraBlurFor(ultraBlurOn) == null || !OckerRailShell.ultraBlurDestinations.contains(widget.selectedTab)
            ? null
            : _ultraBlur;
        return UltraBlurScope(
          ambient: ultraBlur,
          child: OckerHeaderSlot(
            slot: _headerSlot,
            child: GlassBackdrop(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // A slot of its own either way: the shell beside it keeps its
                  // place, and with it the screens and focus, when switched.
                  if (ultraBlur != null)
                    IgnorePointer(child: UltraBlurLayer(colors: ultraBlur))
                  else
                    const SizedBox.shrink(),
                  _buildShell(context, media, railWidth),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildShell(BuildContext context, MediaQueryData media, double railWidth) {
    // A Material of its own, clear: the rail's names and the chrome in the
    // corner stand outside any screen's Scaffold, and text with no Material
    // above it is drawn in the framework's error style.
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = (constraints.maxWidth - railWidth).clamp(0.0, double.infinity).toDouble();
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                left: railWidth,
                top: 0,
                bottom: 0,
                width: contentWidth,
                child: MediaQuery(
                  // The rail takes the leading inset along with the strip,
                  // so the screen must not indent for it a second time.
                  data: media.copyWith(size: Size(contentWidth, media.size.height)).removePadding(removeLeft: true),
                  // No autofocus, exactly as in the other two shells: focus
                  // is moved deliberately, or a rebuild steals it back.
                  child: FocusScope(
                    node: widget.contentFocusScope,
                    child: Stack(
                      fit: StackFit.expand,
                      // Unclipped: a screen's backdrop reaches back under
                      // the strip the shut rail keeps, as it does beside
                      // the standard rail (see SideNavigationBleedBuilder).
                      clipBehavior: Clip.none,
                      children: [
                        widget.content,
                        // Inside the content's scope: with no band overhead
                        // these are the top of the screen they belong to,
                        // reached by UP out of it, not part of the navigation.
                        ValueListenableBuilder<WidgetBuilder?>(
                          valueListenable: _headerSlot,
                          // Home's alone, as the standard theme's toolbar
                          // is: the home screen stays mounted behind the
                          // others, and its chrome, published once, stood
                          // in the corner of every page — over the
                          // watchlist's band.
                          builder: (context, screenChrome, _) =>
                              screenChrome == null || widget.selectedTab != NavigationTabId.discover
                              ? const SizedBox.shrink()
                              : _Chrome(builder: screenChrome),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: FocusScope(
                  node: widget.railFocusScope,
                  child: OckerSideRail(
                    key: widget.railKey,
                    tabs: widget.tabs,
                    selectedTab: widget.selectedTab,
                    expanded: widget.expanded,
                    onDestinationSelected: widget.onDestinationSelected,
                    onNavigateToContent: widget.onNavigateToContent,
                    onReselect: widget.onReselect,
                    menuFor: widget.menuFor,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A screen's own chrome with the clock after it, in the top right corner —
/// where the band used to carry them, and where the standard theme's home
/// screen keeps its toolbar.
class _Chrome extends StatelessWidget {
  const _Chrome({required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final scale = ockerScale(context);
    return Positioned(
      top: MediaQuery.paddingOf(context).top + OckerLayout.headerTop / 2 * scale,
      right: OckerLayout.safeMargin * scale,
      child: Row(
        key: OckerRailShell.chromeKey,
        mainAxisSize: .min,
        children: [
          builder(context),
          SizedBox(width: 18 * scale),
          SystemClock(style: OckerType.of(context).clock.copyWith(color: tk.ink(0.72))),
        ],
      ),
    );
  }
}
