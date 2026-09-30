import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../focus/focusable_action_bar.dart';
import '../../i18n/strings.g.dart';
import '../../mixins/refreshable.dart';
import '../../mixins/tab_navigation_mixin.dart';
import '../../redesign/ocker_skin.dart';
import '../../redesign/ocker_submenu.dart';
import '../../services/sport/sport_models.dart';
import '../../services/sport/sport_repository.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/app_menu.dart';
import '../../widgets/desktop_app_bar.dart';
import '../../widgets/focusable_tab_chip.dart';
import '../main_screen.dart';
import 'sport_league_view.dart';
import 'sport_look.dart';

/// The Sport destination: 1. Bundesliga, 2. Bundesliga and 3. Liga.
///
/// The two themes choose a league in the way each chooses everything else
/// with a list behind it:
///
/// - **Standard** puts the three leagues in a row of chips across the top, the
///   way Downloads and the libraries lay out their sections. UP from the
///   content reaches them, LEFT reaches the side rail. The chips follow the
///   rule every chip row now has: walking moves the cursor, confirming opens.
/// - **The redesign** has no row of chips under its header — a row of words is
///   the only navigation it draws. "Sport" pressed a second time opens the
///   leagues as a submenu, exactly as "Mediatheken" lists the libraries, and
///   the league on show is named at the top of the page instead.
class SportScreen extends StatefulWidget {
  /// For tests; the app shares one.
  final SportRepository? repository;

  const SportScreen({super.key, this.repository});

  @override
  State<SportScreen> createState() => SportScreenState();
}

class SportScreenState extends State<SportScreen>
    with TickerProviderStateMixin, TabNavigationMixin, FocusableTab, OckerSubmenuHost, ManualRefreshable {
  static const _leagues = SportLeague.values;

  final List<FocusNode> _chipNodes = [
    for (final league in _leagues) FocusNode(debugLabel: 'sport_league_${league.shortcut}'),
  ];
  final List<GlobalKey<SportLeagueViewState>> _leagueKeys = [
    for (final _ in _leagues) GlobalKey<SportLeagueViewState>(),
  ];
  final _actionBarKey = GlobalKey<FocusableActionBarState>();

  @override
  List<FocusNode> get tabChipFocusNodes => _chipNodes;

  @override
  void initState() {
    super.initState();
    initTabNavigation();
  }

  @override
  void dispose() {
    for (final node in _chipNodes) {
      node.dispose();
    }
    disposeTabNavigation();
    super.dispose();
  }

  @override
  void onTabChanged() {
    if (!tabController.indexIsChanging) {
      super.onTabChanged();
      // Which league polls for live scores follows which one is on show.
      if (mounted) setState(() {});
    }
  }

  static String _labelOf(SportLeague league) => switch (league) {
    SportLeague.bundesliga1 => t.sport.bundesliga1,
    SportLeague.bundesliga2 => t.sport.bundesliga2,
    SportLeague.liga3 => t.sport.liga3,
  };

  SportLeagueViewState? get _activeLeague => _leagueKeys[tabController.index].currentState;

  /// Entering the destination: the league chip in the standard theme — where
  /// every tabbed screen puts the cursor first — and in the redesign, which
  /// has no chips to land on, the top match of the matchday on show.
  @override
  void focusActiveTabIfReady() {
    if (isOckerLayout(context)) {
      _activeLeague?.focusFirstMatch();
      return;
    }
    suppressAutoFocus = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      getTabChipFocusNode(tabController.index).requestFocus();
    });
  }

  void _focusCurrentLeague() {
    setState(() => suppressAutoFocus = false);
    _activeLeague?.focusEntry();
  }

  void _exitToNavigation() => MainScreenFocusScope.focusSidebarOf(context);

  @override
  void manualRefresh() => unawaited(_activeLeague?.reload());

  // ------------------------------------------------------------ redesign

  /// The leagues and what else the page has, as rows under "Sport" in the
  /// side rail.
  @override
  OckerRailMenu? get ockerRailMenu => OckerRailMenu.fromEntries(_ockerMenuEntries(), _onOckerMenuChosen);

  List<AppMenuEntry<int>> _ockerMenuEntries() => [
    for (var i = 0; i < _leagues.length; i++)
      AppMenuItem<int>(value: i, label: _labelOf(_leagues[i]), selected: i == tabController.index),
    const AppMenuDivider<int>(),
    // Refresh lives here for the same reason it does under "Erkunden":
    // the redesign draws no toolbar for this page, and a second place to
    // look for one row's worth of things would be one too many.
    AppMenuItem<int>(value: -1, icon: Symbols.refresh_rounded, label: t.common.refresh),
  ];

  void _onOckerMenuChosen(int chosen) {
    if (chosen == -1) {
      manualRefresh();
      return;
    }
    setState(() => tabController.index = chosen);
    _focusLeagueOnceBuilt(chosen);
  }

  /// Focus [index]'s top match once its page exists.
  ///
  /// The page is not built when the league is chosen — the views slide across
  /// to it over several frames — and a request made before then went nowhere,
  /// leaving focus in the league left behind. So this waits for the page, a
  /// frame at a time, and then puts focus where entering Sport puts it.
  void _focusLeagueOnceBuilt(int index, {int framesLeft = 40}) {
    WidgetsBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || tabController.index != index) return;
      final league = _leagueKeys[index].currentState;
      if (league != null) {
        league.focusFirstMatch();
      } else if (framesLeft > 0) {
        _focusLeagueOnceBuilt(index, framesLeft: framesLeft - 1);
      }
    });
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final ocker = isOckerLayout(context);
    final views = TabBarView(
      controller: tabController,
      // A swipe between leagues is a phone's gesture. On a television, and in
      // the redesign where the leagues are chosen from a menu, the only way
      // from one to the next is the way that was asked for.
      physics: ocker || PlatformDetector.isTV() ? const NeverScrollableScrollPhysics() : null,
      children: [
        for (var i = 0; i < _leagues.length; i++)
          SportLeagueView(
            key: _leagueKeys[i],
            league: _leagues[i],
            isActive: tabController.index == i,
            onExitUp: ocker ? _exitToNavigation : focusTabBar,
            onExitLeft: _exitToNavigation,
            repository: widget.repository,
          ),
      ],
    );
    return ocker ? _buildOcker(context, views) : _buildStandard(context, views);
  }

  Widget _buildOcker(BuildContext context, Widget views) {
    final tk = tokens(context);
    final scale = ockerScale(context);
    final look = SportLook.of(context);
    // No fill of its own: the page sits on the shell's glass ground, which a
    // flat fill here covered everywhere but under the side rail.
    return Padding(
      padding: EdgeInsets.fromLTRB(
        ockerFlushLeftInset(context),
        ockerContentTop(context),
        OckerLayout.safeMargin * scale,
        32 * scale,
      ),
      child: Column(
        crossAxisAlignment: .start,
        children: [
          // Which league this is, said where the chips would have said it.
          Text(
            _labelOf(_leagues[tabController.index]).toUpperCase(),
            style: look.heading.copyWith(color: tk.ink(0.72)),
          ),
          SizedBox(height: 16 * scale),
          Expanded(child: views),
        ],
      ),
    );
  }

  Widget _buildChip(int index) => buildTabChip(
    _labelOf(_leagues[index]),
    index,
    onSelectWhenActive: _focusCurrentLeague,
    onNavigateDown: _focusCurrentLeague,
    onNavigateToActions: () => _actionBarKey.currentState?.requestFocusOnFirst(),
  );

  List<Widget> _chips() => [
    for (var i = 0; i < _leagues.length; i++) ...[if (i > 0) const SizedBox(width: 8), _buildChip(i)],
  ];

  Widget _buildStandard(BuildContext context, Widget views) {
    final sideNav = PlatformDetector.shouldUseSideNavigation(context);
    return Scaffold(
      body: CustomScrollView(
        primary: false,
        slivers: [
          DesktopSliverAppBar(
            title: sideNav ? TabChipStrip(children: _chips()) : Text(t.navigation.sport),
            floating: true,
            pinned: true,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            scrolledUnderElevation: 0,
            actions: [
              FocusableActionBar(
                key: _actionBarKey,
                onNavigateLeft: () => getTabChipFocusNode(tabCount - 1).requestFocus(),
                onNavigateDown: _focusCurrentLeague,
                actions: [
                  FocusableAction(
                    icon: Symbols.refresh_rounded,
                    tooltip: t.common.refresh,
                    debugLabel: 'sport_refresh',
                    onPressed: manualRefresh,
                  ),
                ],
              ),
            ],
          ),
          SliverFillRemaining(
            child: Column(
              children: [
                if (!sideNav)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    alignment: .centerLeft,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: _chips()),
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(sideNav ? 24 : 16, 8, sideNav ? 32 : 16, 16),
                    child: views,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
