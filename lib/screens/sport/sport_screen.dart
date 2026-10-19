import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../focus/focusable_action_bar.dart';
import '../../i18n/strings.g.dart';
import '../../mixins/refreshable.dart';
import '../../mixins/tab_navigation_mixin.dart';
import '../../redesign/ocker_skin.dart';
import '../../redesign/ocker_submenu.dart';
import '../../services/settings_service.dart';
import '../../services/sport/sport_league_names.dart';
import '../../services/sport/sport_models.dart';
import '../../services/sport/sport_repository.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/app_menu.dart';
import '../../widgets/desktop_app_bar.dart';
import '../../widgets/focusable_tab_chip.dart';
import '../main_screen.dart';
import 'sport_league_management_sheet.dart';
import 'sport_league_view.dart';
import 'sport_look.dart';
import '../../redesign/ocker_glas_look.dart';

/// The Sport destination: the German leagues, and the cups the viewer adds
/// under "Ligen verwalten" (Plebz) — which ones and in which order is theirs
/// ([SportLeagueLayout]).
///
/// The two themes choose a league in the way each chooses everything else
/// with a list behind it:
///
/// - **Standard** puts the leagues in a row of chips across the top, the
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
  /// The competitions on show, in the viewer's order.
  List<SportLeague> _leagues = visibleSportLeagues();
  String _storedLayout = '';
  ValueListenable<String>? _layoutListenable;

  final Map<SportLeague, FocusNode> _chipNodeOf = {};
  final Map<SportLeague, GlobalKey<SportLeagueViewState>> _keyOf = {};
  final _actionBarKey = GlobalKey<FocusableActionBarState>();

  FocusNode _chipNode(SportLeague league) =>
      _chipNodeOf[league] ??= FocusNode(debugLabel: 'sport_league_${league.shortcut}');

  GlobalKey<SportLeagueViewState> _keyFor(SportLeague league) => _keyOf[league] ??= GlobalKey<SportLeagueViewState>();

  @override
  List<FocusNode> get tabChipFocusNodes => [for (final league in _leagues) _chipNode(league)];

  @override
  void initState() {
    super.initState();
    initTabNavigation();
    _layoutListenable = SettingsService.instanceOrNull?.listenable(PlebzPrefs.sportLeagueLayout);
    _storedLayout = _layoutListenable?.value ?? '';
    _layoutListenable?.addListener(_onLayoutChanged);
  }

  @override
  void dispose() {
    _layoutListenable?.removeListener(_onLayoutChanged);
    for (final node in _chipNodeOf.values) {
      node.dispose();
    }
    disposeTabNavigation();
    super.dispose();
  }

  /// "Ligen verwalten" changed which leagues are on show or their order: the
  /// tabs follow, and the league on show stays on show where it still is.
  void _onLayoutChanged() {
    final stored = _layoutListenable?.value ?? '';
    if (!mounted || stored == _storedLayout) return;
    _storedLayout = stored;
    final next = SportLeagueLayout.decode(stored).visible;
    if (listEquals(next, _leagues)) return;
    final showing = _leagues[tabController.index];
    final index = next.indexOf(showing);
    setState(() {
      _leagues = next;
      tabController
        ..removeListener(onTabChanged)
        ..dispose();
      tabController = TabController(length: next.length, vsync: this, initialIndex: index < 0 ? 0 : index);
      tabController.addListener(onTabChanged);
    });
  }

  void _openLeagueManagement() => unawaited(showSportLeagueManagementSheet(context));

  @override
  void onTabChanged() {
    if (!tabController.indexIsChanging) {
      super.onTabChanged();
      // Which league polls for live scores follows which one is on show.
      if (mounted) setState(() {});
    }
  }

  static String _labelOf(SportLeague league) => sportLeagueName(league);

  SportLeagueViewState? get _activeLeague => _keyOf[_leagues[tabController.index]]?.currentState;

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
    AppMenuItem<int>(value: -2, icon: Symbols.tune_rounded, label: t.sport.manageLeagues),
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
    if (chosen == -2) {
      _openLeagueManagement();
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
      final league = _keyOf[_leagues[index]]?.currentState;
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
            key: _keyFor(_leagues[i]),
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
            look.headingCase(_labelOf(_leagues[tabController.index])),
            style: (look.flat ? look.leagueLabel : look.heading).copyWith(color: tk.ink(look.flat ? 0.6 : 0.72)),
          ),
          SizedBox(height: (look.flat ? 8 : 16) * scale),
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
            backgroundColor: pageBarColor(context),
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
                    icon: Symbols.tune_rounded,
                    tooltip: t.sport.manageLeagues,
                    debugLabel: 'sport_manage_leagues',
                    onPressed: _openLeagueManagement,
                  ),
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
            child: OckerClearOfRail(
              // Plebz: clear of Glas's floating rail in landscape on Apple's handhelds.
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
          ),
        ],
      ),
    );
  }
}
