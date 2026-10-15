import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../theme/liquid_glass.dart';
import '../widgets/app_icon.dart';
import '../widgets/side_navigation_rail.dart' show SideNavigationRailState;

import '../media/ids.dart';
import '../media/ultra_blur_colors.dart';
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
  /// switched on ([PlebzPrefs.ultraBlurFor]).
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
    final railWidth = OckerSideRail.reservedWidth(context);

    return SettingValueBuilder<bool>(
      pref: PlebzPrefs.ultraBlurFor(flat: tokens(context).flat),
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
              // The route under the shell lays the same ground already.
              reuseRouteGround: true,
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
          // Plebz: Glas on the Apple TV hides the shut rail (OckerSideRail), so
          // the page has the whole width, dims while the rail is open over it,
          // and a capsule at its top left says where one is — Apple's TV app.
          final apple = ockerGlasHiddenRail(context);
          final contentLeft = railWidth;
          final contentWidth = (constraints.maxWidth - contentLeft).clamp(0.0, double.infinity).toDouble();
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                left: contentLeft,
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
              if (apple) ...[
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: widget.expanded ? 1 : 0,
                      duration: SideNavigationRailState.expandDuration,
                      child: ColoredBox(color: tokens(context).bg.withValues(alpha: 0.55)),
                    ),
                  ),
                ),
                if (widget.tabs.firstWhereOrNull((tab) => tab.id == widget.selectedTab) case final tab?)
                  _ApplePlace(tab: tab, visible: !widget.expanded),
              ],
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
          SystemClock(
            style: OckerType.of(
              context,
            ).clock.copyWith(color: tk.ink(tk.flat ? 0.62 : 0.72), fontWeight: tk.flat ? FontWeight.w500 : null),
          ),
        ],
      ),
    );
  }
}

/// Where one is, while Glas's rail is hidden on the Apple TV (Plebz): a small
/// capsule of glass at the page's top left with the destination's symbol and
/// name, a chevron before it saying the rail lies that way — as Apple's TV
/// app shows its section ("‹ Apple TV"). Not a control: LEFT or BACK opens
/// the rail as they always did.
class _ApplePlace extends StatelessWidget {
  const _ApplePlace({required this.tab, required this.visible});

  final NavigationTab tab;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final scale = ockerScale(context);
    final word = OckerType.of(context).navWord(active: true).copyWith(color: tk.ink(1));
    final height = 56 * scale;
    return Positioned(
      top: MediaQuery.paddingOf(context).top + OckerLayout.headerTop / 2 * scale,
      left: ockerFlushLeftInset(context),
      child: IgnorePointer(
        child: ValueListenableBuilder<int>(
          valueListenable: OckerHidesPlace.hiding,
          builder: (context, hiding, child) =>
              _PlaceVisibility(railShut: visible, columnShut: hiding == 0, child: child!),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(Symbols.arrow_back_ios_new_rounded, size: 26 * scale, weight: 500, color: tk.ink(0.72)),
              SizedBox(width: 10 * scale),
              SizedBox(
                height: height,
                child: _PlaceLight(
                  ambient: UltraBlurScope.of(context),
                  builder: (context, light) => OckerGlass(
                    borderRadius: BorderRadius.circular(height / 2),
                    scrimInset: 0,
                    liquid: true,
                    lensThickness: OckerLiquidGlass.bubbleThickness,
                    lensStrength: OckerLiquidGlass.bubbleStrength,
                    lightTint: light,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 22 * scale),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppIcon(tab.icon, size: 30 * scale, weight: 500, color: tk.ink(1)),
                          SizedBox(width: 12 * scale),
                          Text(tab.getLabel(), maxLines: 1, style: word),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// When the place capsule shows (Plebz, the user's calls 2026-10-14). It lies
/// above every page and under the rail:
///
/// - The rail opening slides over it. Under Liquid Glass it is never faded
///   (a fade puts its lens in a layer of its own, where it sees nothing behind
///   it and turned dark mid-fade): it goes once the rail has covered it and
///   is back as the rail starts to close. Elsewhere it fades with the rail.
/// - A column taking the top left (OckerHidesPlace) slides in over where it
///   stands, and the capsule would show over it: it goes at once, and comes
///   back as the column leaves.
class _PlaceVisibility extends StatefulWidget {
  const _PlaceVisibility({required this.railShut, required this.columnShut, required this.child});

  final bool railShut;
  final bool columnShut;
  final Widget child;

  @override
  State<_PlaceVisibility> createState() => _PlaceVisibilityState();
}

class _PlaceVisibilityState extends State<_PlaceVisibility> {
  late bool _shown = widget.railShut && widget.columnShut;
  Duration _fade = Duration.zero;
  Timer? _timer;

  void _show(bool shown, {Duration after = Duration.zero, Duration fade = Duration.zero}) {
    _timer?.cancel();
    void apply() {
      _shown = shown;
      _fade = fade;
    }

    if (after == Duration.zero) {
      apply();
    } else {
      _timer = Timer(after, () {
        if (mounted) setState(apply);
      });
    }
  }

  @override
  void didUpdateWidget(_PlaceVisibility oldWidget) {
    super.didUpdateWidget(oldWidget);
    final want = widget.railShut && widget.columnShut;
    if (want == (oldWidget.railShut && oldWidget.columnShut)) return;
    final glide = SideNavigationRailState.expandDuration;
    final liquid = OckerLiquidGlass.active;
    if (!widget.columnShut) {
      _show(false);
    } else if (!oldWidget.columnShut) {
      // The column is leaving: back at once. Waiting for it to have gone
      // read worse than the moment over it (the user's call, 2026-10-14).
      _show(true, fade: liquid ? Duration.zero : glide);
    } else if (!widget.railShut) {
      _show(false, after: liquid ? glide : Duration.zero, fade: liquid ? Duration.zero : glide);
    } else {
      _show(true, fade: liquid ? Duration.zero : glide);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(opacity: _shown ? 1 : 0, duration: _fade, child: widget.child);
}

/// The light the place capsule takes up (Plebz, the user's call
/// 2026-10-14): the top left of the focused Plex title's colours, while
/// "Hintergrund in Posterfarben" shows them — so its glass seems to catch the
/// light of the picture behind it. Eased over as the ground crossfades;
/// transparent while there are none.
class _PlaceLight extends StatefulWidget {
  const _PlaceLight({required this.ambient, required this.builder});

  final UltraBlurAmbient? ambient;
  final Widget Function(BuildContext context, Color? light) builder;

  @override
  State<_PlaceLight> createState() => _PlaceLightState();
}

class _PlaceLightState extends State<_PlaceLight> {
  /// The last colour shown, which fades out in its own hue rather than
  /// through black.
  Color _last = const Color(0x00000000);

  Color _target(UltraBlurColors? colours) {
    final corner = colours?.topLeft;
    if (corner != null) return _last = corner.withValues(alpha: 1);
    return _last.withValues(alpha: 0);
  }

  @override
  Widget build(BuildContext context) {
    final ambient = widget.ambient;
    if (ambient == null) return widget.builder(context, null);
    return ValueListenableBuilder<UltraBlurColors?>(
      valueListenable: ambient,
      builder: (context, colours, _) => TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: _target(colours)),
        duration: UltraBlurLayer.crossfade,
        curve: Curves.easeInOut,
        builder: (context, light, _) => widget.builder(context, light),
      ),
    );
  }
}

/// While [hide] holds, the place capsule on the Apple TV ([_ApplePlace])
/// stands aside (Plebz): for a page or a column that shows its own heading at
/// the top left — the settings' topic column, the libraries' column, the
/// guide's group column — which the capsule would otherwise cover.
class OckerHidesPlace extends StatefulWidget {
  const OckerHidesPlace({super.key, required this.hide, required this.child});

  final bool hide;
  final Widget child;

  /// How many are hiding it now.
  static final ValueNotifier<int> hiding = ValueNotifier(0);

  @override
  State<OckerHidesPlace> createState() => _OckerHidesPlaceState();
}

class _OckerHidesPlaceState extends State<OckerHidesPlace> {
  bool _counted = false;

  /// Whether this page is the one on show. MainScreen keeps the tabs it has
  /// opened alive behind the current one, their tickers muted
  /// ([TickerMode]); one of those hides nothing — else the capsule stayed
  /// hidden on every page once the settings had been opened.
  bool _onShow = true;

  void _sync(bool hide) {
    if (hide == _counted) return;
    _counted = hide;
    // After the frame: a count changed mid-build would mark the capsule dirty
    // while its own ancestor is building.
    WidgetsBinding.instance.addPostFrameCallback((_) => OckerHidesPlace.hiding.value += hide ? 1 : -1);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _onShow = TickerMode.valuesOf(context).enabled;
    _sync(widget.hide && _onShow);
  }

  @override
  void didUpdateWidget(OckerHidesPlace oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync(widget.hide && _onShow);
  }

  @override
  void dispose() {
    _sync(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
