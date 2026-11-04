import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image_ce/cached_network_image.dart' show HttpExceptionWithStatus;
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../redesign/ocker_skin.dart';
import '../../focus/focus_theme.dart';
import '../../redesign/ocker_type.dart';
import '../../focus/focusable_wrapper.dart';
import '../../utils/layout_constants.dart';
import '../../redesign/ocker_play_ground.dart';
import '../../redesign/ocker_frost.dart';
import '../../redesign/ocker_glide_edge.dart';
import '../../services/device_performance.dart';
import '../../focus/focusable_action_bar.dart';
import '../../i18n/app_locale_utils.dart';
import '../../i18n/strings.g.dart';
import '../../models/livetv_channel.dart';
import '../../providers/multi_server_provider.dart';
import '../../services/settings_service.dart';
import '../../services/sport/club_colours.dart';
import '../../services/sport/sport_board.dart';
import '../../services/sport/sport_broadcast_matching.dart';
import '../../services/sport/sport_crest_fallback.dart';
import '../../services/sport/sport_league_names.dart';
import '../../services/sport/sport_models.dart';
import '../../services/sport/sport_repository.dart';
import '../../theme/mono_tokens.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/app_menu.dart';
import '../../widgets/optimized_media_image.dart';
import '../../widgets/settings_builder.dart';
import '../../utils/live_tv_matching.dart';
import '../../utils/live_tv_player_navigation.dart';
import '../../utils/platform_detector.dart';
import 'club_colour_ground.dart';
import 'sport_board_widgets.dart';
import 'sport_broadcast_finder.dart';
import 'sport_look.dart';
import 'sport_match_sheet.dart';

/// One league: which matchday is on show, its fixtures, and the table beside
/// them.
///
/// Opens on the matchday the provider calls current. Above the fixtures sits
/// one bar, the way the kicker app has it: the matchday and its dates in the
/// middle, an arrow either side to the one before and the one after. The
/// middle opens the whole season as a list, the current matchday marked, for
/// the jump that would take twenty presses of an arrow. A row of thirty-four
/// numbers was tried first: it ran off the edge of the screen and said less
/// than the one word does.
///
/// The same bar serves a remote and a finger — LEFT and RIGHT walk its three
/// parts, OK presses the one under the cursor, and each part is a tap target
/// of its own on a phone.
///
/// Theme-neutral in structure: the same bar, list and table in both themes,
/// drawn through [SportLook]. What the two themes need differently at the
/// *edges* — where UP and LEFT lead out of this view — is handed in.
class SportLeagueView extends StatefulWidget {
  final SportLeague league;

  /// Whether this league is the one on screen. A hidden one does not poll.
  final bool isActive;

  /// UP out of the matchday bar: the league chips in the standard theme, the
  /// navigation in the redesign.
  final VoidCallback onExitUp;

  /// LEFT off the first column: the side rail. Null where there is nothing
  /// over there.
  final VoidCallback? onExitLeft;

  /// For tests; the app shares one.
  final SportRepository? repository;

  /// For tests; the app's is built from the Live TV providers in scope.
  final SportBroadcastFinder? broadcastFinder;

  /// For tests; the app opens the player through [navigateToLiveTv].
  final SportWatchCallback? onWatch;

  /// Where the television's board hands its stage's clubs, for the ground
  /// the screen draws behind it (Plebz); null for a league not on show.
  final ValueNotifier<SportStageGround?>? stageGround;

  const SportLeagueView({
    super.key,
    required this.league,
    required this.isActive,
    required this.onExitUp,
    this.onExitLeft,
    this.repository,
    this.broadcastFinder,
    this.onWatch,
    this.stageGround,
  });

  @override
  State<SportLeagueView> createState() => SportLeagueViewState();
}

class SportLeagueViewState extends State<SportLeagueView>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  SportRepository get _repo => widget.repository ?? SportRepository.instance;

  int? _season;
  int? _currentMatchday;
  int? _selected;
  List<SportMatchday> _matchdays = const [];
  List<SportMatch> _matches = const [];
  List<SportTableRow> _table = const [];
  bool _loading = true;
  bool _failed = false;

  /// A matchday other than the one on screen has been asked for and has not
  /// arrived. The fixtures column shows that rather than keeping the old
  /// matchday's games under the new matchday's number.
  bool _dayLoading = false;

  /// The fixture under the cursor, whose two clubs the table lights up.
  SportMatch? _focusedMatch;

  /// Bumped by every load, so a slow answer for a matchday the viewer has
  /// already left cannot overwrite the one they moved to.
  int _generation = 0;

  /// A European cup's 36 clubs need the page's width (Plebz): its table is a
  /// view of its own, two columns side by side, which the bar switches to.
  /// On a phone a German league's too, rather than under its fixtures.
  bool _showTable = false;

  /// Whether the table is a view the bar switches to, for the layout last
  /// built: a European cup's off the television, a league's on a phone.
  /// The television puts it at the foot of the page ([_buildBoard]).
  bool _tableIsView = false;

  /// The table beside the fixtures — a German league's, with room for both.
  bool get _tableBeside => widget.league.hasTable && widget.league.isDomestic;

  Timer? _liveTimer;
  final _viewToggleNode = FocusNode(debugLabel: 'sport_view_toggle');
  final _matchdayNode = FocusNode(debugLabel: 'sport_matchday');
  final _previousNode = FocusNode(debugLabel: 'sport_matchday_previous');
  final _nextNode = FocusNode(debugLabel: 'sport_matchday_next');
  final _matchdayKey = GlobalKey();
  final Map<int, FocusNode> _matchNodes = {};
  final _retryNode = FocusNode(debugLabel: 'sport_retry');
  final _stageNode = FocusNode(debugLabel: 'sport_favourite_stage');

  // The television's board (Plebz): the stage's button, the tiles by row
  // and place — a game can stand in two rows, a European cup's German clubs'
  // and its kickoff's — the table at the foot, or the cup's rounds.
  bool _boardShown = false;
  List<SportBoardRow> _boardRows = const [];
  final _boardStageNode = FocusNode(debugLabel: 'sport_board_stage');
  final _stagePreviousNode = FocusNode(debugLabel: 'sport_stage_previous');
  final _stageNextNode = FocusNode(debugLabel: 'sport_stage_next');

  /// The game the viewer stepped the stage to with its arrows (Plebz); null
  /// for the one [sportStageFor] picks. A new matchday starts from the pick.
  int? _stageMatchId;
  final _boardTableNode = FocusNode(debugLabel: 'sport_board_table');
  final Map<String, FocusNode> _tileNodes = {};
  final Map<int, FocusNode> _roundNodes = {};
  final Map<int, ScrollController> _rowScrolls = {};
  final Map<int, GlobalKey> _rowKeys = {};
  late final _boardScroll = ScrollController()..addListener(_publishStageGround);

  /// The soft top edge the board glides under, as the start page's rows do
  /// ([OckerGlideEdge]): eased in as a glide starts and out once it has
  /// settled; [_boardGlideTarget] is where the glide ends, so the edge clears
  /// over its last stretch and the row arriving on top is whole.
  late final _boardEdgeIn = AnimationController(vsync: this, duration: const Duration(milliseconds: 90));
  double? _boardGlideTarget;

  /// The stage's clubs, last handed to [SportLeagueView.stageGround].
  SportMatch? _groundMatch;

  /// The row the cursor last stood in. The page scrolls up or down only when
  /// it changes rows: walking along one, the page stays where it is.
  int? _boardFocusRow;

  /// The clubs the table at the foot lights: the favourite's alone (Plebz,
  /// the user's call — a tile says its clubs' places itself).
  final _boardHighlight = ValueNotifier<Set<int>>(const {});
  final Map<int, FocusNode> _tablePanelNodes = {};
  final _tableScroll = ScrollController();
  final _tableBlockKey = GlobalKey();

  /// The table's panel at [index]: its first is [_boardTableNode], where the
  /// cursor comes down to.
  FocusNode _tablePanelNode(int index) => index == 0
      ? _boardTableNode
      : _tablePanelNodes.putIfAbsent(index, () => FocusNode(debugLabel: 'sport_table_panel_$index'));

  /// While a match is being played, how often its score is asked for again.
  static const _livePoll = Duration(seconds: 60);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _liveTimer = Timer.periodic(_livePoll, (_) => _refreshIfLive());
  }

  @override
  void didUpdateWidget(covariant SportLeagueView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Back on show (Plebz): the screen's ground takes this league's stage.
    if (widget.stageGround != oldWidget.stageGround) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _publishStageGround());
    }
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _viewToggleNode.dispose();
    _matchdayNode.dispose();
    _previousNode.dispose();
    _nextNode.dispose();
    for (final node in _matchNodes.values) {
      node.dispose();
    }
    _retryNode.dispose();
    _stageNode.dispose();
    _boardStageNode.dispose();
    _stagePreviousNode.dispose();
    _stageNextNode.dispose();
    _boardTableNode.dispose();
    for (final node in [..._tileNodes.values, ..._roundNodes.values]) {
      node.dispose();
    }
    for (final controller in [..._rowScrolls.values, _boardScroll]) {
      controller.dispose();
    }
    _boardEdgeIn.dispose();
    _boardHighlight.dispose();
    for (final node in _tablePanelNodes.values) {
      node.dispose();
    }
    _tableScroll.dispose();
    super.dispose();
  }

  FocusNode _matchNode(int id) => _matchNodes.putIfAbsent(id, () => FocusNode(debugLabel: 'sport_match_$id'));

  /// The game of the matchday on show that stands on a stage over the rest,
  /// and why ([sportStageFor], Plebz): a game on now, the favourite club's,
  /// a German club's in a European cup, the next one.
  ({SportMatch match, SportStageReason reason})? get _stagePick => sportStageFor(
    _matches,
    league: widget.league,
    favouriteClub: SettingsService.instanceOrNull?.read(PlebzPrefs.sportFavouriteClub) ?? 0,
    now: clock.now(),
  );

  SportMatch? get _stage => _stagePick?.match;

  /// What the television's stage shows: the game stepped to, else the pick.
  ({SportMatch match, SportStageReason reason})? get _boardStage {
    final chosen = _stageMatchId;
    if (chosen != null) {
      final match = _matches.where((match) => match.id == chosen).firstOrNull;
      if (match != null) return (match: match, reason: SportStageReason.next);
    }
    return _stagePick;
  }

  /// The stage one game on or back, in kickoff order. The arrow at an end
  /// gives way: focus moves to the button beside it.
  void _stepStage(SportMatch from, int by) {
    final index = _matches.indexWhere((match) => match.id == from.id);
    final target = index + by;
    if (index < 0 || target < 0 || target >= _matches.length) return;
    setState(() => _stageMatchId = _matches[target].id);
    final atEnd = target == 0 || target == _matches.length - 1;
    if (atEnd) WidgetsBinding.instance.addPostFrameCallback((_) => _boardStageNode.requestFocus());
  }

  /// The matchday's games in the list: all but the one on the stage.
  List<SportMatch> get _listed {
    final stage = _stage;
    return stage == null
        ? _matches
        : [
            for (final match in _matches)
              if (match.id != stage.id) match,
          ];
  }

  /// Where the cursor goes when this league is entered: the matchday itself,
  /// in the middle of the bar.
  void focusEntry() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_failed) {
        _retryNode.requestFocus();
        return;
      }
      if (_matchdayNode.context != null) _matchdayNode.requestFocus();
    });
  }

  /// Where the focus stood when [focusFirstMatch] was asked for while the
  /// matchday was still loading. Once it arrives the top match takes focus —
  /// but only if the focus has not moved on in the meantime.
  FocusNode? _firstMatchFrom;
  bool _firstMatchPending = false;

  /// Entering the destination from the navigation: the top match of the
  /// matchday on show, which is what one comes here to look at. Still loading,
  /// it is taken as soon as the matchday is there.
  void focusFirstMatch() {
    // A frame of its own, or the cursor waits for the next key press.
    WidgetsBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_failed) {
        _retryNode.requestFocus();
        return;
      }
      if (_loading || _dayLoading || _matches.isEmpty) {
        _firstMatchPending = true;
        _firstMatchFrom = FocusManager.instance.primaryFocus;
        return;
      }
      _firstMatchPending = false;
      _focusFirstMatch();
    });
  }

  /// Hands over a pending [focusFirstMatch] once the matches are built.
  void _settlePendingFirstMatch() {
    if (!_firstMatchPending || _matches.isEmpty) return;
    _firstMatchPending = false;
    final from = _firstMatchFrom;
    _firstMatchFrom = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final now = FocusManager.instance.primaryFocus;
      // Still in Sport — this league or the one just left, where a closing
      // menu hands focus back — counts as not having moved on. Only a cursor
      // that has left Sport altogether is left where it is.
      final stillInSport = now?.context?.findAncestorWidgetOfExactType<SportLeagueView>() != null;
      if (now != null && now != from && now != _matchdayNode && !stillInSport) return;
      _focusFirstMatch();
    });
  }

  /// Fresh data for this league, keeping the matchday on show.
  Future<void> reload() async {
    _repo.invalidate(widget.league);
    await _load(quiet: _matches.isNotEmpty);
  }

  Future<void> _load({bool quiet = false}) async {
    final generation = ++_generation;
    if (!quiet) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }

    final now = await _repo.current(widget.league);
    if (!mounted || generation != _generation) return;
    if (now == null) {
      setState(() {
        _loading = false;
        _failed = _matches.isEmpty;
      });
      return;
    }

    final selected = _selected ?? now.matchday;
    final results = await Future.wait<Object?>([
      _repo.matchdays(widget.league, now.season),
      _repo.table(widget.league, now.season),
      if (selected != now.matchday) _repo.matchday(widget.league, now.season, selected),
    ]);
    if (!mounted || generation != _generation) return;

    setState(() {
      _season = now.season;
      _currentMatchday = now.matchday;
      _selected = selected;
      _matchdays = (results[0] as List<SportMatchday>?) ?? _matchdays;
      _table = (results[1] as List<SportTableRow>?) ?? _table;
      _matches = selected == now.matchday ? now.matches : (results[2] as List<SportMatch>?) ?? _matches;
      _loading = false;
      _failed = false;
      _dayLoading = false;
    });
    _settlePendingFirstMatch();
  }

  Future<void> _selectMatchday(int order) async {
    final season = _season;
    if (season == null || order == _selected) return;
    final generation = ++_generation;
    setState(() {
      _selected = order;
      _focusedMatch = null;
      _dayLoading = true;
      _stageMatchId = null;
    });
    final matches = await _repo.matchday(widget.league, season, order);
    if (!mounted || generation != _generation) return;
    setState(() {
      _matches = matches ?? const [];
      _dayLoading = false;
    });
    _settlePendingFirstMatch();
  }

  /// Whether anyone can see the scores: another destination in front keeps
  /// this one mounted with its tickers off, and an app in the background is
  /// seen by nobody. Not inactive — a desktop window that lost focus still is.
  bool get _onScreen {
    if (!TickerMode.getValuesNotifier(context).value.enabled) return false;
    final state = WidgetsBinding.instance.lifecycleState;
    return state != AppLifecycleState.hidden && state != AppLifecycleState.paused;
  }

  /// A running match changes by the minute; nothing else here does.
  Future<void> _refreshIfLive() async {
    if (!mounted || !widget.isActive || !_onScreen) return;
    final now = clock.now();
    if (!_matches.any((match) => match.isLive(now))) return;
    final season = _season;
    final selected = _selected;
    if (season == null || selected == null) return;
    final results = await Future.wait<Object?>([
      _repo.matchday(widget.league, season, selected),
      _repo.table(widget.league, season),
    ]);
    if (!mounted || _selected != selected) return;
    setState(() {
      _matches = (results[0] as List<SportMatch>?) ?? _matches;
      _table = (results[1] as List<SportTableRow>?) ?? _table;
    });
  }

  /// Built on first use and kept, so its channel list is loaded once for a
  /// run of games rather than once per game.
  SportBroadcastFinder? _finder;

  void _openMatch(SportMatch match) {
    final finder = _finder ??= widget.broadcastFinder ?? SportBroadcastFinder.maybeOf(context);
    // A game that is over is not looked for: its window shows the result,
    // not where it was on.
    final now = clock.now();
    final over = match.isFinished || (now.isAfter(match.kickoff) && !match.isLive(now));
    final broadcasts = over ? null : finder?.search(match, widget.league);
    unawaited(
      showSportMatchSheet(
        context,
        match: match,
        league: widget.league,
        table: _table,
        broadcasts: broadcasts,
        onWatch: widget.onWatch ?? _watch,
      ),
    );
  }

  /// Into the player, the way the guide goes there: [channels] to zap
  /// through, confined to the channel's own group — the Bundesliga channels,
  /// for a game on one of them.
  void _watch(SportBroadcast broadcast, List<LiveTvChannel> channels, {int? startAtEpoch}) {
    final multiServer = context.read<MultiServerProvider?>();
    if (multiServer == null) return;
    unawaited(
      navigateToLiveTv(
        context,
        multiServer: multiServer,
        channel: broadcast.channel,
        channels: channels,
        startAtEpoch: startAtEpoch,
        group: liveTvNonEmpty(broadcast.channel.lineup),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final look = SportLook.of(context);

    if (_loading && _matches.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_failed) return _buildFailure(look);

    // A favourite club chosen in the settings takes the stage at once.
    return SettingValueBuilder<int>(
      pref: PlebzPrefs.sportFavouriteClub,
      builder: (context, _, _) => LayoutBuilder(
        builder: (context, constraints) {
          // Side by side wherever there is a table's width to spare; on a phone
          // the table is a view of its own instead of crushing both into
          // columns too narrow for a club's name. Plebz: a handheld needs the
          // height for it too — a phone on its side squeezed the table's rows
          // to slivers beside the fixtures.
          final wide =
              constraints.maxWidth >= 720 &&
              (look.ocker || !PlatformDetector.isMobile(context) || constraints.maxHeight >= 480);
          // The television (Plebz): the stage, the games as rows of tiles and
          // the table at the foot, the way the start page is laid out.
          // A phone or a tablet under the redesigns (Plebz): the same board
          // for touch. A Mac keeps its list and the table beside it.
          final touch = look.flat && PlatformDetector.isMobile(context);
          _boardShown = look.ocker || touch;
          if (look.ocker) {
            _tableIsView = false;
            return _buildBoard(look, constraints);
          }
          if (touch) {
            _tableIsView = false;
            return _buildTouchBoard(look, constraints);
          }
          // Off it, a table that is not beside the fixtures is a view of its
          // own (Plebz): a European cup's, and on a phone a league's.
          _tableIsView = widget.league.hasTable && (!widget.league.isDomestic || !wide);
          // A cup (Plebz): its fixtures take the page's width — a European
          // cup's table is a view of its own, the DFB-Pokal has none.
          if (!_tableBeside || !wide) return _buildCupPage(look, constraints, wide: wide);
          final tableWidth = ((look.ocker ? 600 : 380) * look.scale).clamp(0.0, constraints.maxWidth * 0.46);
          // Under the redesign the table stands as far from the fixtures as
          // from the screen's edge — the page's own margin, both sides alike.
          final columnGap = look.ocker ? OckerLayout.safeMargin * look.scale : look.gap * 2;
          final fixturesWidth = constraints.maxWidth - tableWidth - columnGap;
          final bar = _buildMatchdayBar(look, compact: _isCompactBar(look, fixturesWidth));
          // The bar belongs to the fixtures — it says which ones these are — so
          // it stands over their column, centred on it, and the table beside
          // them keeps the full height.
          return Row(
            crossAxisAlignment: .start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    bar,
                    SizedBox(height: look.gap),
                    Expanded(
                      child: _dayLoading || _matches.isEmpty
                          ? _buildFixturesPlaceholder(look)
                          : ListView(
                              padding: _listPadding(context),
                              children: _matchItems(look, compact: _isCompact(look, fixturesWidth)),
                            ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: columnGap),
              Container(
                width: tableWidth,
                // Plebz: clear of a tablet's navigation bar, which cut the
                // zones' key off the panel's foot.
                padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
                // Plebz: on a tablet the panel is as tall as its table and no
                // taller; run to the page's foot it stood half empty on an
                // upright one.
                child: PlatformDetector.isMobile(context)
                    ? SingleChildScrollView(
                        child: _SportTable(
                          rows: _table,
                          look: look,
                          highlight: _highlightedTeams,
                          league: widget.league,
                        ),
                      )
                    : _SportTable(
                        rows: _table,
                        look: look,
                        highlight: _highlightedTeams,
                        league: widget.league,
                        fitHeight: true,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// A phone's or a tablet's Sport page under the redesigns (Plebz): the
  /// television's board for touch — the bar, the stage and the games as
  /// tiles by day (a cup's evening by kickoff, a European cup's German clubs
  /// first). Narrow, the tiles stand under one another and a switch under
  /// the stage turns the page to the table; with room for two columns they
  /// pair up; a tablet held across keeps the table beside them.
  Widget _buildTouchBoard(SportLook look, BoxConstraints constraints) {
    final locale = LocaleSettings.currentLocale.intlLocaleName;
    final pick = _dayLoading || _matches.isEmpty ? null : _boardStage;
    if (_groundMatch?.id != pick?.match.id) {
      _groundMatch = pick?.match;
      // After the frame: the ground is built above this page.
      WidgetsBinding.instance.addPostFrameCallback((_) => _publishStageGround());
    }
    final bar = _buildTouchBar(look);
    if (_dayLoading || _matches.isEmpty) {
      return Column(
        children: [
          bar,
          Expanded(child: _buildFixturesPlaceholder(look)),
        ],
      );
    }
    const gap = 12.0;
    const tableWidth = 360.0;
    final hasTable = widget.league.hasTable && _table.isNotEmpty;
    final beside = hasTable && constraints.maxWidth >= 1000;
    final width = beside ? constraints.maxWidth - tableWidth - 2 * gap : constraints.maxWidth;
    final columns = width >= 640 ? 2 : 1;
    final tileWidth = (width - gap * (columns - 1)) / columns;
    final rows = sportBoardRows(_matches, league: widget.league);
    _boardRows = rows;
    final places = {for (final row in _table) row.team.id: row.position};
    final children = <Widget>[
      if (pick != null)
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: _buildTouchStage(look, pick, locale, wide: width >= 640),
        ),
      if (hasTable && !beside) _buildViewSwitch(look),
      if (hasTable && !beside && _showTable)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: _SportTable(
            rows: _table,
            look: look,
            highlight: const {},
            league: widget.league,
            splitAt: width >= 760 ? (_table.length + 1) ~/ 2 : null,
            // The switch over it already says what it is.
            showTitle: false,
          ),
        )
      else
        for (var i = 0; i < rows.length; i++) ...[
          Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 8, left: 2),
            child: _touchRowHeading(_boardRowLabel(rows, i, locale)),
          ),
          for (var start = 0; start < rows[i].matches.length; start += columns)
            Padding(
              padding: const EdgeInsets.only(bottom: gap),
              child: Row(
                children: [
                  for (var c = 0; c < columns; c++) ...[
                    if (c > 0) const SizedBox(width: gap),
                    if (start + c < rows[i].matches.length)
                      _buildTouchTile(
                        look,
                        rows[i].matches[start + c],
                        tileWidth,
                        places: places,
                        // The German clubs' row runs over the days.
                        date: rows[i].kind == SportBoardRowKind.germanClubs
                            ? DateFormat.MMMEd(locale).format(rows[i].matches[start + c].kickoff.toLocal())
                            : null,
                      )
                    else
                      SizedBox(width: tileWidth),
                  ],
                ],
              ),
            ),
        ],
    ];
    final page = Column(
      children: [
        bar,
        Expanded(
          child: ListView(
            controller: _boardScroll,
            padding: _listPadding(context).add(const EdgeInsets.only(bottom: 24)),
            children: children,
          ),
        ),
      ],
    );
    if (!beside) return page;
    return Row(
      crossAxisAlignment: .start,
      children: [
        Expanded(child: page),
        const SizedBox(width: 2 * gap),
        Container(
          width: tableWidth,
          // Clear of a tablet's navigation bar, as the panel beside the list,
          // and the panel as tall as the page: its rows close up to fit, the
          // key under them included — run on past the foot, the table was cut
          // off at the screen's edge.
          padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 16),
          child: _SportTable(rows: _table, look: look, highlight: const {}, league: widget.league, fitHeight: true),
        ),
      ],
    );
  }

  /// A touch board row's name as the start page names its rows on this
  /// device ([HubSection], Plebz): Glas's bold sentence case, Flach's mono
  /// label in capitals.
  Widget _touchRowHeading(String label) {
    final type = OckerType.of(context);
    final base = Theme.of(context).textTheme.titleLarge;
    if (type.glasHeadings) {
      return Text(
        label,
        maxLines: 1,
        overflow: .ellipsis,
        style: type.sectionHeading.copyWith(color: base?.color),
      );
    }
    return Text(
      label.toUpperCase(),
      maxLines: 1,
      overflow: .ellipsis,
      style: base?.copyWith(
        fontFamily: tokens(context).monoFontFamily,
        fontSize: (base.fontSize ?? 22) * 0.62,
        fontWeight: FontWeight.w400,
        letterSpacing: 1.8,
      ),
    );
  }

  /// The touch board's bar: the matchday between its two arrows, as on the
  /// television; the middle opens the whole season.
  Widget _buildTouchBar(SportLook look) {
    final (previous, next) = _neighbours;
    const height = 48.0;
    return SizedBox(
      height: height,
      child: Row(
        children: [
          _buildArrow(
            look,
            compact: true,
            node: _previousNode,
            icon: Symbols.chevron_left_rounded,
            target: previous,
            label: previous == null ? null : _label(previous),
            onNavigateLeft: widget.onExitLeft ?? () {},
            onNavigateRight: _matchdayNode.requestFocus,
          ),
          Expanded(
            child: FocusableWrapper(
              focusNode: _matchdayNode,
              borderRadius: height / 2,
              useBackgroundFocus: true,
              glassFocus: true,
              onSelect: () => unawaited(_chooseMatchday()),
              onNavigateLeft: _previousNode.requestFocus,
              onNavigateRight: _nextNode.requestFocus,
              onNavigateUp: widget.onExitUp,
              onNavigateDown: _focusFirstMatch,
              child: Center(
                child: FittedBox(fit: BoxFit.scaleDown, child: _boardMatchdayWord(look, height, 15)),
              ),
            ),
          ),
          _buildArrow(
            look,
            compact: true,
            node: _nextNode,
            icon: Symbols.chevron_right_rounded,
            target: next,
            label: next == null ? null : _label(next),
            onNavigateLeft: _matchdayNode.requestFocus,
            onNavigateRight: () {},
          ),
        ],
      ),
    );
  }

  /// The touch board's stage: a swipe steps through the games, as the arrows
  /// do on a tablet (and on the television); a phone shows where it stands
  /// with dots under "Zum Spiel".
  Widget _buildTouchStage(
    SportLook look,
    ({SportMatch match, SportStageReason reason}) pick,
    String locale, {
    required bool wide,
  }) {
    final match = pick.match;
    final index = _matches.indexWhere((game) => game.id == match.id);
    final count = _matches.length;
    void step(int by) => _stepStage(match, by);
    final v2 = ockerGlasV2(context);
    const height = 44.0;
    const shape = StadiumBorder();
    final button = OckerPlayGround(
      v2: v2,
      focused: false,
      shape: shape,
      radius: height / 2,
      child: FilledButton(
        onPressed: () => _openMatch(match),
        style: ButtonStyle(
          backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
          foregroundColor: WidgetStatePropertyAll(OckerPlayGround.foreground(context, v2: v2)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 22)),
          minimumSize: const WidgetStatePropertyAll(Size(0, height)),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: const WidgetStatePropertyAll(shape),
        ),
        child: Text(t.sport.toMatch, style: const TextStyle(fontSize: 15, fontWeight: .w700)),
      ),
    );
    Widget arrow(IconData icon, int by, String tooltip) {
      final enabled = index + by >= 0 && index + by < count;
      return IconButton(
        tooltip: tooltip,
        onPressed: enabled ? () => step(by) : null,
        icon: AppIcon(icon, size: 24, color: look.ink(enabled ? 0.85 : 0.2)),
      );
    }

    final Widget action;
    if (wide) {
      action = Row(
        mainAxisSize: .min,
        children: [
          button,
          const SizedBox(width: 8),
          arrow(Symbols.chevron_left_rounded, -1, t.sport.previousMatch),
          arrow(Symbols.chevron_right_rounded, 1, t.sport.nextOnStage),
        ],
      );
    } else {
      action = Column(
        mainAxisSize: .min,
        children: [
          button,
          // As many dots as games, while they fit on a line.
          if (count > 1 && count <= 12) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisSize: .min,
              children: [
                for (var i = 0; i < count; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: i == index ? 14 : 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: look.ink(i == index ? 0.95 : 0.35),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ],
        ],
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity.abs() < 200) return;
        step(velocity < 0 ? 1 : -1);
      },
      child: SportTouchStage(
        match: match,
        reason: pick.reason,
        look: look,
        locale: locale,
        wide: wide,
        position: _stageMatchId == null || index < 0 ? null : t.sport.stagePosition(n: index + 1, total: count),
        action: action,
      ),
    );
  }

  /// "Spiele | Tabelle" under a phone's stage (Plebz): the two views of the
  /// page, the one on show in the chosen wash.
  Widget _buildViewSwitch(SportLook look) {
    const height = 36.0;
    Widget part(String label, bool chosen, bool table) => Expanded(
      child: SportTap(
        onTap: () => setState(() => _showTable = table),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: chosen ? look.tk.accent.withValues(alpha: ockerV2ChosenWash) : null,
            borderRadius: BorderRadius.circular(height / 2),
          ),
          child: Text(
            label,
            style: look.time.copyWith(
              fontSize: 15,
              fontWeight: chosen ? .w600 : .w500,
              color: look.ink(chosen ? 1 : 0.62),
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: look.ink(0.08), borderRadius: BorderRadius.circular(height / 2 + 3)),
        child: Row(children: [part(t.sport.fixtures, !_showTable, false), part(t.sport.table, _showTable, true)]),
      ),
    );
  }

  /// One game of the touch board: a tap opens it, as a line of the list did.
  Widget _buildTouchTile(
    SportLook look,
    SportMatch match,
    double width, {
    required Map<int, int> places,
    String? date,
  }) {
    final score = match.scoreAt(clock.now());
    return FocusableWrapper(
      focusNode: _matchNode(match.id),
      borderRadius: artworkRadius(context),
      disableScale: true,
      semanticLabel: [match.home.name, match.away.name, if (score != null) score.toString()].join(', '),
      onSelect: () => _openMatch(match),
      child: SportTap(
        onTap: () => _openMatch(match),
        child: SportGameTile(
          match: match,
          width: width,
          touchHeight: 104,
          look: look,
          homePlace: places[match.home.id],
          awayPlace: places[match.away.id],
          date: date,
        ),
      ),
    );
  }

  /// A cup's page (Plebz): the bar, and under it the round's fixtures or —
  /// for a European cup, switched in the bar — its table in two columns.
  Widget _buildCupPage(SportLook look, BoxConstraints constraints, {required bool wide}) {
    final bar = _buildMatchdayBar(look, compact: _isCompactBar(look, constraints.maxWidth));
    final Widget body;
    if (_showTable && _tableIsView) {
      final twoColumns = constraints.maxWidth >= 760 * (look.ocker ? look.scale : 1);
      final table = _SportTable(
        rows: _table,
        look: look,
        highlight: const {},
        league: widget.league,
        fitHeight: wide,
        splitAt: twoColumns ? (_table.length + 1) ~/ 2 : null,
      );
      body = wide ? table : SingleChildScrollView(padding: _listPadding(context), child: table);
    } else {
      body = _dayLoading || _matches.isEmpty
          ? _buildFixturesPlaceholder(look)
          : ListView(
              padding: _listPadding(context),
              children: _matchItems(look, compact: _isCompact(look, constraints.maxWidth)),
            );
    }
    return Column(
      children: [
        bar,
        SizedBox(height: look.gap),
        Expanded(child: body),
      ],
    );
  }

  Set<int> get _highlightedTeams {
    final match = _focusedMatch;
    return match == null ? const {} : {match.home.id, match.away.id};
  }

  Widget _buildFailure(SportLook look) {
    return Center(
      child: Column(
        mainAxisSize: .min,
        children: [
          Text(t.sport.loadFailed, style: look.body.copyWith(color: look.ink(0.72))),
          SizedBox(height: look.gap),
          FocusableWrapper(
            focusNode: _retryNode,
            autofocus: widget.isActive,
            useBackgroundFocus: true,
            glassFocus: true,
            onSelect: () => unawaited(_load()),
            onNavigateUp: widget.onExitUp,
            onNavigateLeft: widget.onExitLeft,
            child: SportTap(
              onTap: () => unawaited(_load()),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 20 * look.scale, vertical: 10 * look.scale),
                child: Text(t.common.retry, style: look.matchdayChip(current: true).copyWith(color: look.ink(1))),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFixturesPlaceholder(SportLook look) => Center(
    child: _dayLoading
        ? const CircularProgressIndicator()
        : Text(t.sport.noMatches, style: look.body.copyWith(color: look.ink(0.6))),
  );

  // ---------------------------------------------------------------- board

  FocusNode _tileNode(int row, int match) =>
      _tileNodes.putIfAbsent('$row:$match', () => FocusNode(debugLabel: 'sport_tile_${row}_$match'));

  FocusNode _roundNode(int order) => _roundNodes.putIfAbsent(order, () => FocusNode(debugLabel: 'sport_round_$order'));

  ScrollController _rowScroll(int row) => _rowScrolls.putIfAbsent(row, ScrollController.new);

  int get _favouriteClub => SettingsService.instanceOrNull?.read(PlebzPrefs.sportFavouriteClub) ?? 0;

  /// What stands under the rows: the table, or the DFB-Pokal's rounds.
  bool get _boardHasFoot => widget.league.hasTable ? _table.isNotEmpty : _matchdays.isNotEmpty;

  void _focusBoardEntry() {
    if (_stage != null) return _boardStageNode.requestFocus();
    _focusTile(0, 0);
  }

  /// One tile's width with the gap after it, from the board's last build.
  double _boardStride = 1;

  /// Focus on the tile at [column] of [row]. A row only builds the tiles in
  /// view, so one scrolled out of it is brought in first and focused once it
  /// is there — asked for before, the request went nowhere and the cursor
  /// stayed where it was.
  void _focusTile(int row, int column) {
    if (row < 0 || row >= _boardRows.length) return;
    final games = _boardRows[row].matches;
    if (games.isEmpty) return;
    final place = column.clamp(0, games.length - 1);
    final node = _tileNode(row, games[place].id);
    if (node.context != null) return node.requestFocus();
    final controller = _rowScroll(row);
    if (controller.hasClients) {
      final position = controller.position;
      controller.jumpTo((place * _boardStride).clamp(position.minScrollExtent, position.maxScrollExtent));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && node.context != null) node.requestFocus();
    });
  }

  /// UP or DOWN from the tile at [column] of [from]: the tile of [to] that
  /// stands under it on the screen — the rows are scrolled each its own way,
  /// so the same place in the row can be far off to one side.
  void _focusRow(int from, int column, int to) {
    if (to < 0 || to >= _boardRows.length) return;
    double offset(int row) => _rowScroll(row).hasClients ? _rowScroll(row).offset : 0;
    final x = column * _boardStride - offset(from);
    final place = ((x + offset(to)) / _boardStride).round();
    _focusTile(to, place.clamp(0, _boardRows[to].matches.length - 1));
  }

  /// The table's panel the cursor last stood on, to come back down to.
  int _tablePanel = 0;

  /// The table's panels' width with the gap after, from the board's last
  /// build.
  double _tableStride = 1;

  /// DOWN from the last row: the table's panel last stood on — brought into
  /// view first where the row of panels has scrolled it away, as a tile is
  /// ([_focusTile]) — or the DFB-Pokal's round on show.
  void _focusBoardFoot() {
    if (!_boardHasFoot) return;
    if (widget.league.hasTable) {
      final node = _tablePanelNode(_tablePanel);
      if (node.context != null) return node.requestFocus();
      if (_tableScroll.hasClients) {
        final position = _tableScroll.position;
        _tableScroll.jumpTo((_tablePanel * _tableStride).clamp(position.minScrollExtent, position.maxScrollExtent));
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && node.context != null) node.requestFocus();
      });
      return;
    }
    final order = _selected ?? _matchdays.first.order;
    _roundNode(_matchdays.any((day) => day.order == order) ? order : _matchdays.first.order).requestFocus();
  }

  /// Keeps the tile at [column] of [row] in view as the cursor walks the row:
  /// the row scrolls only as far as it has to.
  ///
  /// The row runs from one edge of the screen to the other: a tile stops at
  /// the page's margins — [start] on the left, [end] on the right — and
  /// whatever lies past them is cut by the screen's edge, not the page's.
  void _revealTile(int row, int column, double tileWidth, double gap, {required double start, required double end}) {
    final controller = _rowScroll(row);
    if (!controller.hasClients) return;
    final position = controller.position;
    // Where the tile stands in the row, its first tile at [start].
    final left = start + column * (tileWidth + gap);
    final right = left + tileWidth;
    var target = position.pixels;
    if (left - target < start) target = left - start;
    if (right - target > position.viewportDimension - end) target = right - (position.viewportDimension - end);
    target = target.clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < 1) return;
    unawaited(
      controller.animateTo(target, duration: FocusTheme.navigationScrollDuration(), curve: Curves.easeOutCubic),
    );
  }

  /// Hands the stage's clubs to the screen's ground, fading as the page
  /// scrolls down past the stage.
  void _publishStageGround() {
    final target = widget.stageGround;
    if (target == null || !mounted) return;
    final match = _boardShown ? _groundMatch : null;
    final offset = _boardScroll.hasClients ? _boardScroll.offset : 0.0;
    final fade = (1 - offset / (360 * ockerScale(context))).clamp(0.0, 1.0);
    final next = match == null
        ? null
        : SportStageGround(home: clubColourFor(match.home), away: clubColourFor(match.away), opacity: fade);
    if (target.value != next) target.value = next;
  }

  /// The matchday's name, its dates and "aktuell", as the one word of the
  /// board's bar between its arrows.
  Widget _boardMatchdayWord(SportLook look, double height, double size) {
    final selected = _selected;
    final label = selected == null ? '' : _label(selected);
    final dates = _dateRange(LocaleSettings.currentLocale.intlLocaleName);
    final isCurrent = selected != null && selected == _currentMatchday;
    final base = OckerType.of(context).spotlightFacts.copyWith(fontSize: size, height: 1);
    return KeyedSubtree(
      key: _matchdayKey,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => unawaited(_chooseMatchday()),
        child: SizedBox(
          height: height,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: height * 0.38),
            child: Center(
              widthFactor: 1,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: label,
                      style: TextStyle(color: look.ink(1), fontWeight: .w700),
                    ),
                    if (dates != null) TextSpan(text: ' · $dates'),
                    if (isCurrent) const TextSpan(text: ' · '),
                    if (isCurrent)
                      TextSpan(
                        text: t.sport.current,
                        style: TextStyle(color: look.live, fontWeight: .w600),
                      ),
                  ],
                ),
                maxLines: 1,
                style: base.copyWith(color: look.ink(0.7)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A row of the board's buttons on one band of glass, as a detail page's
  /// are: focus the band's capsule gliding along them; Flach's discs and
  /// capsules mark their own.
  Widget _boardBand(FocusableActionBar bar) => ockerGlass(context) && !ockerFlat(context)
      ? OckerGlassBand(overhang: EdgeInsets.all(ockerBandMargin(context)), liquidBubble: true, child: bar)
      : bar;

  /// The board's bar: the league's name, and beside it the matchday between
  /// its two arrows on one band (Plebz), in the size of a detail page's
  /// buttons. The middle opens the whole season.
  Widget _buildBoardBar(SportLook look) {
    final tvScale = TvLayoutConstants.scaleOf(context);
    final size = 46 * tvScale;
    final (previous, next) = _neighbours;
    final glass = ockerGlass(context) && !ockerFlat(context);
    return Row(
      children: [
        Text(
          sportLeagueName(widget.league),
          style: OckerType.of(context).spotlightFacts.copyWith(fontSize: 17 * tvScale, color: look.ink(0.62)),
        ),
        SizedBox(width: 20 * tvScale),
        _boardBand(
          FocusableActionBar(
            glyphDiameter: size,
            spacing: glass ? 4 * tvScale : 10 * tvScale,
            wrapBuiltAction: glass
                ? (context, state, child) =>
                      OckerWordFocus(focused: state.showFocus, outset: EdgeInsets.zero, child: child)
                : null,
            onNavigateUp: widget.onExitUp,
            onNavigateDown: _focusFirstMatch,
            onNavigateLeft: widget.onExitLeft,
            actions: [
              FocusableAction(
                debugLabel: 'sport_matchday_previous',
                focusNode: _previousNode,
                icon: Symbols.chevron_left_rounded,
                tooltip: previous == null ? null : _label(previous),
                onPressed: previous == null ? null : () => unawaited(_selectMatchday(previous)),
              ),
              FocusableAction(
                debugLabel: 'sport_matchday',
                focusNode: _matchdayNode,
                onPressed: () => unawaited(_chooseMatchday()),
                builder: (context, state) => _boardMatchdayWord(look, size, 17 * tvScale),
              ),
              FocusableAction(
                debugLabel: 'sport_matchday_next',
                focusNode: _nextNode,
                icon: Symbols.chevron_right_rounded,
                tooltip: next == null ? null : _label(next),
                onPressed: next == null ? null : () => unawaited(_selectMatchday(next)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The stage's buttons: "Zum Spiel" — a detail page's play button, on the
  /// same ground ([OckerPlayGround]) at the same size — and beside it two
  /// arrows that step the stage through the matchday's games (Plebz).
  Widget _buildStageAction(SportLook look, SportMatch match) {
    final index = _matches.indexWhere((game) => game.id == match.id);
    final tvScale = TvLayoutConstants.scaleOf(context);
    final size = 46 * tvScale;
    final v2 = ockerGlasV2(context);
    final glass = ockerGlass(context) && !ockerFlat(context);
    final foreground = OckerPlayGround.foreground(context, v2: v2);
    const shape = StadiumBorder();
    void open() => _openMatch(match);
    return _boardBand(
      FocusableActionBar(
        wrapBuiltAction: glass
            ? (context, state, child) => OckerWordFocus(focused: state.showFocus, outset: EdgeInsets.zero, child: child)
            : null,
        glyphDiameter: size,
        spacing: glass ? 16 * tvScale : 10 * tvScale,
        onNavigateUp: _focusMatchdayButton,
        onNavigateDown: () => _focusTile(0, 0),
        onNavigateLeft: widget.onExitLeft,
        onFocusChange: (focused) {
          if (!focused) return;
          _boardFocusRow = null;
          _boardToTop();
        },
        actions: [
          FocusableAction(
            debugLabel: 'sport_board_stage',
            focusNode: _boardStageNode,
            onPressed: open,
            staysLit: v2 && ockerFrost(context),
            builder: (context, state) => SizedBox(
              height: size,
              child: OckerPlayGround(
                v2: v2,
                focused: state.showFocus,
                shape: shape,
                radius: size / 2,
                child: FilledButton(
                  onPressed: open,
                  style: ButtonStyle(
                    backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
                    foregroundColor: WidgetStatePropertyAll(foreground),
                    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
                    padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 22 * tvScale)),
                    minimumSize: WidgetStatePropertyAll(Size(0, size)),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: const WidgetStatePropertyAll(shape),
                  ),
                  child: Text(
                    t.sport.toMatch,
                    style: TextStyle(fontSize: 17 * tvScale, fontWeight: .w700),
                  ),
                ),
              ),
            ),
          ),
          FocusableAction(
            debugLabel: 'sport_stage_previous',
            focusNode: _stagePreviousNode,
            icon: Symbols.chevron_left_rounded,
            tooltip: t.sport.previousMatch,
            onPressed: index > 0 ? () => _stepStage(match, -1) : null,
          ),
          FocusableAction(
            debugLabel: 'sport_stage_next',
            focusNode: _stageNextNode,
            icon: Symbols.chevron_right_rounded,
            tooltip: t.sport.nextOnStage,
            onPressed: index >= 0 && index < _matches.length - 1 ? () => _stepStage(match, 1) : null,
          ),
        ],
      ),
    );
  }

  /// The television's Sport page (Plebz): the bar, the stage with the game
  /// that matters most just now, the games as rows of tiles — by day, or for
  /// a cup by kickoff, a European cup's German clubs first — and at the foot
  /// the table in two columns, or the DFB-Pokal's way to the final. The sizes
  /// are the start page's: a 28 heading over each row, tiles 520 wide.
  Widget _buildBoard(SportLook look, BoxConstraints constraints) {
    final bar = _buildBoardBar(look);
    final locale = LocaleSettings.currentLocale.intlLocaleName;
    final pick = _dayLoading || _matches.isEmpty ? null : _boardStage;
    if (_groundMatch?.id != pick?.match.id) {
      _groundMatch = pick?.match;
      // After the frame: the ground is built above this page.
      WidgetsBinding.instance.addPostFrameCallback((_) => _publishStageGround());
    }
    final s = look.scale;
    // The page runs from one edge of the screen to the other (Plebz): a row's
    // tiles come in from the right edge and leave at the left one, as on the
    // start page, and a ring of focus is never cut by the page. What is not a
    // row keeps to the margins inside.
    final start = ockerFlushLeftInset(context);
    final margin = OckerLayout.safeMargin * s;
    Widget inside(Widget child) => Padding(
      padding: EdgeInsets.only(left: start, right: margin),
      child: child,
    );
    if (_dayLoading || _matches.isEmpty) {
      return Column(
        crossAxisAlignment: .start,
        children: [
          inside(bar),
          Expanded(child: inside(_buildFixturesPlaceholder(look))),
        ],
      );
    }
    final rows = sportBoardRows(_matches, league: widget.league);
    _boardRows = rows;
    final favourite = _favouriteClub;
    _boardHighlight.value = favourite == 0 ? const {} : {favourite};
    final places = {for (final row in _table) row.team.id: row.position};

    final gap = 24 * s;
    final tileWidth = 520 * s;
    _boardStride = tileWidth + gap;
    // Room round a tile for its ring and its growth, inside the row.
    final lead = 14 * s;
    final rowHeading = OckerType.of(context).sectionHeading;

    final children = <Widget>[
      if (pick != null)
        inside(
          Padding(
            padding: EdgeInsets.only(top: 72 * s, bottom: 16 * s),
            child: SportStageHero(
              match: pick.match,
              reason: pick.reason,
              look: look,
              locale: locale,
              position: _stageMatchId == null
                  ? null
                  : t.sport.stagePosition(n: _matches.indexOf(pick.match) + 1, total: _matches.length),
              action: _buildStageAction(look, pick.match),
            ),
          ),
        ),
      for (var i = 0; i < rows.length; i++)
        _buildBoardRow(
          look,
          rows,
          i,
          locale,
          tileWidth: tileWidth,
          gap: gap,
          lead: lead,
          start: start,
          endRoom: margin,
          heading: rowHeading,
          hasStage: pick != null,
          places: places,
        ),
      if (_boardHasFoot && widget.league.hasTable)
        Padding(
          padding: EdgeInsets.only(top: 48 * s),
          child: _buildBoardTable(look, rowHeading, start: start, margin: margin, width: constraints.maxWidth),
        )
      else if (_boardHasFoot)
        inside(
          Padding(
            padding: EdgeInsets.only(top: 48 * s),
            child: _buildRounds(look, rowHeading),
          ),
        ),
    ];
    return Column(
      crossAxisAlignment: .start,
      children: [
        inside(bar),
        Expanded(
          // As the start page's rows (Plebz): what glides up under the bar
          // dissolves into it while it moves, and at rest a row stands whole
          // at the top with nothing drawn offscreen; a weak box keeps the
          // plain clip.
          child: OckerGlideEdge(
            listenable: Listenable.merge([_boardScroll, _boardEdgeIn]),
            strength: _boardEdgeStrength,
            fadeHeight: 72 * s,
            child: SingleChildScrollView(
              controller: _boardScroll,
              padding: _listPadding(context).add(EdgeInsets.only(bottom: 48 * s)),
              child: Column(crossAxisAlignment: .start, children: children),
            ),
          ),
        ),
      ],
    );
  }

  /// Brings [row] up once the cursor has moved into it, at its tile for
  /// [match]: the first row back to the top, where the stage is; another to
  /// the top of the page, under the bar, as the start page brings its row
  /// up (Plebz).
  void _revealRow(int row, int match) {
    if (row == 0) return _boardToTop();
    // The whole row, its heading over the tiles: brought up from the table
    // with the tiles alone, the heading stayed cut under the bar.
    _revealBox(() => _rowKeys[row]?.currentContext ?? _tileNode(row, match).context);
  }

  /// Glides the page until the box at [of] stands at its top, under the bar,
  /// [room] below it: in this frame where the box is laid out, as the start
  /// page starts its glide, after it where it has only just been built.
  ///
  /// A row brings its own room above its heading, so it stands at the very
  /// top as the start page's row does — any lower, and the bottom of the row
  /// above showed as a strip under the bar.
  void _revealBox(BuildContext? Function() of, {double room = 0}) {
    if (_glideToBox(of, room)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _glideToBox(of, room));
  }

  bool _glideToBox(BuildContext? Function() of, double room) {
    final context = of();
    if (!mounted || !_boardScroll.hasClients || context == null || !context.mounted) return false;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    final viewport = _boardScroll.position.context.notificationContext?.findRenderObject() as RenderBox?;
    if (viewport == null) return false;
    final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
    final position = _boardScroll.position;
    _boardGlide(position.pixels + top - room);
    return true;
  }

  /// Back to the top of the page, where the stage is: the first row and the
  /// stage share the first screen.
  void _boardToTop() {
    if (!_boardScroll.hasClients || _boardScroll.offset <= 0) return;
    _boardGlide(0);
  }

  /// The page's one way of moving up and down: at the start page's pace
  /// ([FocusTheme.navigationScrollDuration] — the quick step on a weak box),
  /// the top edge soft only while it glides.
  void _boardGlide(double to) {
    final position = _boardScroll.position;
    final target = to.clamp(position.minScrollExtent, position.maxScrollExtent).toDouble();
    if ((target - position.pixels).abs() < 1) return;
    _boardGlideTarget = target;
    if (!DevicePerformance.isReduced) unawaited(_boardEdgeIn.forward());
    unawaited(
      _boardScroll
          .animateTo(target, duration: FocusTheme.navigationScrollDuration(), curve: Curves.easeOutCubic)
          .whenComplete(() {
            // A newer glide has taken over and keeps the edge.
            if (!mounted || _boardGlideTarget != target) return;
            _boardGlideTarget = null;
            unawaited(_boardEdgeIn.reverse());
          }),
    );
  }

  /// How soft the top edge is just now: eased in, and cleared over a glide's
  /// last stretch.
  double _boardEdgeStrength() {
    var strength = _boardEdgeIn.value;
    final target = _boardGlideTarget;
    if (target != null && _boardScroll.hasClients) {
      final remaining = (_boardScroll.offset - target).abs();
      strength = math.min(strength, (remaining / (140 * ockerScale(context))).clamp(0.0, 1.0));
    }
    return strength;
  }

  String _boardRowLabel(List<SportBoardRow> rows, int index, String locale) {
    final row = rows[index];
    final previous = index > 0 ? rows[index - 1] : null;
    return switch (row.kind) {
      SportBoardRowKind.germanClubs => t.sport.withGermanClubs,
      SportBoardRowKind.day => _dayLabel(row.day, locale),
      SportBoardRowKind.kickoff =>
        '${row.sameDayAs(previous) ? DateFormat.EEEE(locale).format(row.day) : _dayLabel(row.day, locale)}'
            ' · ${DateFormat.Hm(locale).format(row.kickoff!)}',
    };
  }

  Widget _buildBoardRow(
    SportLook look,
    List<SportBoardRow> rows,
    int index,
    String locale, {
    required double tileWidth,
    required double gap,
    required double lead,
    required double start,
    required double endRoom,
    required TextStyle heading,
    required bool hasStage,
    required Map<int, int> places,
  }) {
    final s = look.scale;
    final row = rows[index];
    final games = row.matches;
    final tileHeight = tileWidth / sportTileAspect;
    final last = index == rows.length - 1;
    return Padding(
      key: _rowKeys.putIfAbsent(index, GlobalKey.new),
      padding: EdgeInsets.only(top: 40 * s),
      child: Column(
        crossAxisAlignment: .start,
        children: [
          Padding(
            padding: EdgeInsets.only(left: start),
            child: Text(
              look.headingCase(_boardRowLabel(rows, index, locale)),
              style: heading.copyWith(color: look.ink(1)),
            ),
          ),
          SizedBox(height: 6 * s),
          SizedBox(
            height: tileHeight + 2 * lead,
            child: ListView.separated(
              controller: _rowScroll(index),
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              // The next tile peeks past the page's margin, as on the start
              // page, rather than stopping at a cut.
              clipBehavior: Clip.none,
              // The last tile can come in as far as the page's margin.
              padding: EdgeInsets.fromLTRB(start, lead, endRoom, lead),
              itemCount: games.length,
              separatorBuilder: (_, _) => SizedBox(width: gap),
              itemBuilder: (context, column) {
                final match = games[column];
                return FocusableWrapper(
                  focusNode: _tileNode(index, match.id),
                  borderRadius: artworkRadius(context),
                  focusScale: FocusTheme.focusScaleFor(context, 1.04),
                  // The page's scrolling is the board's own ([_revealRow]): the
                  // wrapper's, and going back to the top for the first row, took
                  // turns and the row bobbed up and down along a walk.
                  autoScroll: false,
                  semanticLabel: [
                    match.home.name,
                    match.away.name,
                    if (match.scoreAt(clock.now()) case final score?)
                      score.toString()
                    else
                      DateFormat.Hm(locale).format(match.kickoff.toLocal()),
                  ].join(', '),
                  onFocusChange: (focused) {
                    if (!focused) return;
                    _revealTile(index, column, tileWidth, gap, start: start, end: endRoom);
                    if (index != _boardFocusRow) {
                      _boardFocusRow = index;
                      _revealRow(index, match.id);
                    }
                  },
                  onSelect: () => _openMatch(match),
                  onNavigateLeft: column > 0 ? () => _focusTile(index, column - 1) : (widget.onExitLeft ?? () {}),
                  onNavigateRight: column < games.length - 1 ? () => _focusTile(index, column + 1) : () {},
                  onNavigateUp: index > 0
                      ? () => _focusRow(index, column, index - 1)
                      : hasStage
                      ? _boardStageNode.requestFocus
                      : _focusMatchdayButton,
                  onNavigateDown: last
                      ? (_boardHasFoot ? _focusBoardFoot : () {})
                      : () => _focusRow(index, column, index + 1),
                  // BACK walks to the row's start first, as on the start page.
                  onBack: column > 0 ? () => _focusTile(index, 0) : _focusMatchdayButton,
                  child: SportTap(
                    onTap: () => _openMatch(match),
                    child: SportGameTile(
                      match: match,
                      width: tileWidth,
                      look: look,
                      homePlace: places[match.home.id],
                      awayPlace: places[match.away.id],
                      // The German clubs' row runs over the days (Plebz).
                      date: row.kind == SportBoardRowKind.germanClubs
                          ? DateFormat.MMMEd(locale).format(match.kickoff.toLocal())
                          : null,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// The table at the foot of the page (Plebz): its two halves on two flat
  /// panels side by side, under a row's heading. Read, not walked: one stop
  /// for the cursor, so a remote can get down to it — both panels ringed
  /// while it holds focus, neither grown.
  Widget _buildBoardTable(
    SportLook look,
    TextStyle heading, {
    required double start,
    required double margin,
    required double width,
  }) {
    final s = look.scale;
    final played = _table.fold<int>(0, (most, row) => math.max(most, row.played));
    final panels = sportTablePanels(_table);
    final gap = 48 * s;
    // Two panels side by side between the page's margins; more come in from
    // the right as the cursor walks on.
    final panelWidth = ((width - start - margin - gap) / 2).clamp(320 * s, double.infinity).toDouble();
    final panelHeight = sportTablePanelHeight(panels.first.length) * s;
    _tableStride = panelWidth + gap;
    if (_tablePanel >= panels.length) _tablePanel = 0;
    // UP from a panel: the tile standing over it in the last row.
    void up(int index) {
      final last = _boardRows.length - 1;
      if (last < 0) return;
      final x = index * _tableStride - (_tableScroll.hasClients ? _tableScroll.offset : 0);
      final rowOffset = _rowScroll(last).hasClients ? _rowScroll(last).offset : 0;
      _focusTile(last, ((x + rowOffset) / _boardStride).round());
    }

    void reveal(int index) {
      if (!_tableScroll.hasClients) return;
      final position = _tableScroll.position;
      final left = start + index * (panelWidth + gap);
      final right = left + panelWidth;
      var target = position.pixels;
      if (left - target < start) target = left - start;
      if (right - target > position.viewportDimension - margin) target = right - (position.viewportDimension - margin);
      target = target.clamp(position.minScrollExtent, position.maxScrollExtent);
      if ((target - position.pixels).abs() < 1) return;
      unawaited(
        _tableScroll.animateTo(target, duration: FocusTheme.navigationScrollDuration(), curve: Curves.easeOutCubic),
      );
    }

    return Column(
      key: _tableBlockKey,
      crossAxisAlignment: .start,
      children: [
        // Named as a row of tiles is, with how far the season has come beside
        // it.
        Padding(
          padding: EdgeInsets.only(left: start, right: margin),
          child: Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: look.headingCase(t.sport.table)),
                      if (played > 0)
                        TextSpan(
                          text: '   ${t.sport.tableAfter(n: played)}',
                          style: OckerType.of(
                            context,
                          ).spotlightFacts.copyWith(color: look.ink(0.55), fontSize: heading.fontSize! * 0.66),
                        ),
                    ],
                  ),
                  style: heading.copyWith(color: look.ink(1)),
                ),
              ),
              // More panels than the screen holds (Plebz): arrows say which
              // way the table goes on.
              if (panels.length > 2)
                ListenableBuilder(
                  listenable: _tableScroll,
                  builder: (context, _) {
                    final position = _tableScroll.hasClients ? _tableScroll.position : null;
                    final back = position != null && position.pixels > position.minScrollExtent + 1;
                    final on = position == null || position.pixels < position.maxScrollExtent - 1;
                    final size = heading.fontSize! * 1.1;
                    return Row(
                      mainAxisSize: .min,
                      children: [
                        AppIcon(Symbols.chevron_left_rounded, size: size, color: look.ink(back ? 0.7 : 0.18)),
                        SizedBox(width: 8 * s),
                        AppIcon(Symbols.chevron_right_rounded, size: size, color: look.ink(on ? 0.7 : 0.18)),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
        SizedBox(height: 20 * s),
        SizedBox(
          height: panelHeight,
          child: ListView.separated(
            controller: _tableScroll,
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            clipBehavior: Clip.none,
            padding: EdgeInsets.only(left: start, right: margin),
            itemCount: panels.length,
            separatorBuilder: (_, _) => SizedBox(width: gap),
            itemBuilder: (context, index) => FocusableWrapper(
              focusNode: _tablePanelNode(index),
              // The ring round the one panel under the cursor, and no growth
              // (the user's calls): it would push past the screen's margins.
              borderRadius: 28 * s,
              disableScale: true,
              autoScroll: false,
              semanticLabel: t.sport.table,
              onFocusChange: (focused) {
                if (!focused) return;
                _tablePanel = index;
                reveal(index);
                if (_boardFocusRow != -1) {
                  _boardFocusRow = -1;
                  // The table's title as high as a row's heading.
                  _revealBox(() => _tableBlockKey.currentContext, room: 40 * s);
                }
              },
              onNavigateUp: () => up(index),
              onNavigateDown: () {},
              onNavigateLeft: index > 0 ? _tablePanelNode(index - 1).requestFocus : (widget.onExitLeft ?? () {}),
              onNavigateRight: index < panels.length - 1 ? _tablePanelNode(index + 1).requestFocus : () {},
              onBack: index > 0 ? _boardTableNode.requestFocus : _focusMatchdayButton,
              child: SizedBox(
                width: panelWidth,
                child: SportTablePanel(
                  rows: panels[index],
                  count: _table.length,
                  league: widget.league,
                  highlight: _boardHighlight.value,
                  look: look,
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(left: start, right: margin, top: 20 * s),
          child: SportTableLegend(rows: _table, league: widget.league, look: look),
        ),
      ],
    );
  }

  /// The DFB-Pokal's rounds, the one being played marked (Plebz): "Der Weg
  /// nach Berlin". OK on one shows it.
  Widget _buildRounds(SportLook look, TextStyle heading) {
    final s = look.scale;
    final days = _matchdays;
    return Column(
      crossAxisAlignment: .start,
      children: [
        Text(look.headingCase(t.sport.roadToFinal), style: heading.copyWith(color: look.ink(1))),
        SizedBox(height: 18 * s),
        Row(
          children: [
            for (var i = 0; i < days.length; i++) ...[
              if (i > 0) SizedBox(width: 16 * s),
              Expanded(
                child: SportRoundPane(
                  name: sportMatchdayLabel(widget.league, days[i].order, name: days[i].name),
                  note: days[i].order == _currentMatchday
                      ? t.sport.current
                      : (_currentMatchday != null && days[i].order < _currentMatchday!)
                      ? t.sport.roundPlayed
                      : null,
                  onShow: days[i].order == _selected,
                  isCurrent: days[i].order == _currentMatchday,
                  look: look,
                  focusNode: _roundNode(days[i].order),
                  onSelect: () => unawaited(_selectMatchday(days[i].order)),
                  onNavigateLeft: i > 0 ? _roundNode(days[i - 1].order).requestFocus : (widget.onExitLeft ?? () {}),
                  onNavigateRight: i < days.length - 1 ? _roundNode(days[i + 1].order).requestFocus : () {},
                  onNavigateUp: () => _focusTile(_boardRows.length - 1, 0),
                  onBack: _focusMatchdayButton,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  // --------------------------------------------------------------- matchday

  /// The matchday before and after the one on show, or null at either end of
  /// the season.
  (int?, int?) get _neighbours {
    final index = _matchdays.indexWhere((day) => day.order == _selected);
    if (index < 0) return (null, null);
    return (
      index > 0 ? _matchdays[index - 1].order : null,
      index < _matchdays.length - 1 ? _matchdays[index + 1].order : null,
    );
  }

  /// What matchday [order] is called: "Spieltag 4", or a cup round's own name
  /// ("Achtelfinale Hinspiele").
  String _label(int order) {
    final name =
        _matchdays.where((day) => day.order == order).firstOrNull?.name ??
        _matches.where((match) => match.matchday.order == order).firstOrNull?.matchday.name;
    return sportMatchdayLabel(widget.league, order, name: name);
  }

  /// "Fr., 9. Okt. – So., 11. Okt." — the days the matchday on show is played
  /// on, read off its fixtures. Null while they are loading.
  String? _dateRange(String locale) {
    if (_dayLoading || _matches.isEmpty) return null;
    final first = DateUtils.dateOnly(_matches.first.kickoff);
    final last = DateUtils.dateOnly(_matches.last.kickoff);
    final format = DateFormat.MMMEd(locale);
    return first == last ? format.format(first) : '${format.format(first)} – ${format.format(last)}';
  }

  /// Plebz: a list left to pad itself takes the status bar's height again at
  /// its top — the page above it has already stepped below it — and on a
  /// phone that gap showed the rows scrolling through it between the bar and
  /// the first day. Only the navigation bar at the foot is kept clear.
  EdgeInsets _listPadding(BuildContext context) => EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom);

  /// Whether the bar over the fixtures is a phone's (Plebz): the title smaller,
  /// its dates on a line under it, the arrows smaller — at the television's
  /// size the three were wider than a phone and ran off its edge.
  bool _isCompactBar(SportLook look, double width) => !look.ocker && width < 600;

  Widget _buildMatchdayBar(SportLook look, {bool compact = false}) {
    final (previous, next) = _neighbours;
    if (look.flat) return _buildFlatMatchdayBar(look, previous, next, compact: compact);
    final bar = SizedBox(
      height: (look.ocker ? 76 : 60) * look.scale,
      child: Row(
        children: [
          _buildArrow(
            look,
            node: _previousNode,
            icon: Symbols.chevron_left_rounded,
            target: previous,
            label: previous == null ? null : _label(previous),
            onNavigateLeft: widget.onExitLeft ?? () {},
            onNavigateRight: _matchdayNode.requestFocus,
          ),
          Expanded(child: Center(child: _buildMatchdayButton(look))),
          _buildArrow(
            look,
            node: _nextNode,
            icon: Symbols.chevron_right_rounded,
            target: next,
            label: next == null ? null : _label(next),
            onNavigateLeft: _matchdayNode.requestFocus,
            onNavigateRight: _tableIsView ? _viewToggleNode.requestFocus : () {},
          ),
          if (_tableIsView) ...[SizedBox(width: 8 * look.scale), _buildViewToggle(look, compact: compact)],
        ],
      ),
    );
    // The standard theme sets it on a plate, as it does every bar; the
    // redesign draws no plates, and a hairline under it is enough to make one
    // line of the three parts.
    return DecoratedBox(
      decoration: look.ocker
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: look.ink(0.14), width: 1)),
            )
          : BoxDecoration(color: look.ink(0.06), borderRadius: BorderRadius.circular(look.tk.radiusMd)),
      child: bar,
    );
  }

  /// "Flach" (Plebz): the matchday as the page's title on the left — its
  /// dates and "aktuell" quietly beside it — and the two arrows as round
  /// buttons at the right of the fixtures. Pressing the title still opens the
  /// season.
  Widget _buildFlatMatchdayBar(SportLook look, int? previous, int? next, {required bool compact}) {
    return ConstrainedBox(
      // Grows with the viewer's text size where the title takes two lines.
      constraints: compact
          ? BoxConstraints(minHeight: 64 * look.scale)
          : BoxConstraints.tightFor(height: 64 * look.scale),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _buildMatchdayButton(look, compact: compact),
            ),
          ),
          _buildArrow(
            look,
            compact: compact,
            node: _previousNode,
            icon: Symbols.chevron_left_rounded,
            target: previous,
            label: previous == null ? null : _label(previous),
            onNavigateLeft: _matchdayNode.requestFocus,
            onNavigateRight: _nextNode.requestFocus,
          ),
          SizedBox(width: (compact ? 8 : 10) * look.scale),
          _buildArrow(
            look,
            compact: compact,
            node: _nextNode,
            icon: Symbols.chevron_right_rounded,
            target: next,
            label: next == null ? null : _label(next),
            onNavigateLeft: _previousNode.requestFocus,
            onNavigateRight: _tableIsView ? _viewToggleNode.requestFocus : () {},
          ),
          if (_tableIsView) ...[
            SizedBox(width: (compact ? 8 : 10) * look.scale),
            _buildViewToggle(look, compact: compact),
          ],
        ],
      ),
    );
  }

  /// "Tabelle" over the fixtures, "Spiele" over the table (Plebz): a European
  /// cup's two views — and on a phone a league's — at the bar's right end.
  /// Shaped like the arrows beside it — a plain plate in the standard look and
  /// Glas, a round-ended button on Flach. A phone's bar has room for its
  /// symbol alone.
  Widget _buildViewToggle(SportLook look, {bool compact = false}) {
    final height = (compact ? 44 : (look.flat ? 54 : (look.ocker ? 64 : 48))) * look.scale;
    final label = _showTable ? t.sport.fixtures : t.sport.table;
    void toggle() => setState(() => _showTable = !_showTable);
    return FocusableWrapper(
      focusNode: _viewToggleNode,
      borderRadius: look.flat ? height / 2 : look.tk.radiusSm,
      useBackgroundFocus: true,
      glassFocus: true,
      semanticLabel: label,
      onSelect: toggle,
      onNavigateLeft: _nextNode.requestFocus,
      onNavigateRight: () {},
      onNavigateUp: widget.onExitUp,
      onNavigateDown: _showTable ? () {} : _focusFirstMatch,
      child: SportTap(
        onTap: toggle,
        child: Container(
          height: height,
          width: compact ? height : null,
          padding: compact ? null : EdgeInsets.symmetric(horizontal: 20 * look.scale),
          decoration: BoxDecoration(
            color: look.flat ? look.ink(0.06) : null,
            borderRadius: BorderRadius.circular(look.flat ? height / 2 : look.tk.radiusSm),
          ),
          child: Row(
            mainAxisSize: .min,
            mainAxisAlignment: .center,
            children: [
              AppIcon(
                _showTable ? Symbols.sports_soccer_rounded : Symbols.table_rows_rounded,
                size: height * (look.flat ? 0.4 : 0.42),
                color: look.ink(0.85),
              ),
              if (!compact) ...[
                SizedBox(width: 8 * look.scale),
                Text(
                  label,
                  style: look.time.copyWith(color: look.ink(0.9), fontWeight: .w600),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// One of the two arrows. At either end of the season the arrow stays where
  /// it is, dimmed and doing nothing, so the cursor never loses its footing
  /// and the bar keeps its shape.
  Widget _buildArrow(
    SportLook look, {
    bool compact = false,
    required FocusNode node,
    required IconData icon,
    required int? target,
    required String? label,
    required VoidCallback onNavigateLeft,
    required VoidCallback onNavigateRight,
  }) {
    final size = (compact ? 44 : (look.flat ? 54 : (look.ocker ? 64 : 48))) * look.scale;
    void step() {
      if (target != null) unawaited(_selectMatchday(target));
    }

    return FocusableWrapper(
      focusNode: node,
      borderRadius: look.flat ? size / 2 : look.tk.radiusSm,
      useBackgroundFocus: true,
      glassFocus: true,
      semanticLabel: label,
      onSelect: step,
      onNavigateLeft: onNavigateLeft,
      onNavigateRight: onNavigateRight,
      onNavigateUp: widget.onExitUp,
      onNavigateDown: _focusFirstMatch,
      child: SportTap(
        onTap: step,
        child: DecoratedBox(
          // Flat: a round button of its own, as on the other pages.
          decoration: look.flat ? BoxDecoration(color: look.ink(0.06), shape: BoxShape.circle) : const BoxDecoration(),
          child: SizedBox.square(
            dimension: size,
            child: Center(
              child: AppIcon(icon, size: size * (look.flat ? 0.5 : 0.6), color: look.ink(target == null ? 0.2 : 0.85)),
            ),
          ),
        ),
      ),
    );
  }

  /// "Spieltag 5 ⌄" over the dates it is played on. The chevron is the one
  /// the header draws beside a destination that opens a list.
  Widget _buildMatchdayButton(SportLook look, {bool compact = false}) {
    final selected = _selected;
    final label = selected == null ? '' : _label(selected);
    final style = look.matchdayChip(current: true).copyWith(color: look.ink(1));
    final dates = _dateRange(LocaleSettings.currentLocale.intlLocaleName);
    final isCurrent = selected != null && selected == _currentMatchday;
    final detail = look.time.copyWith(color: look.ink(0.6));
    final Widget face;
    if (look.flat && compact) {
      // A phone's (Plebz): the title, and under it the dates and "aktuell" in
      // one quiet line that gives way before the arrows do.
      final quiet = look.leagueLabel.copyWith(color: look.ink(0.55), fontSize: 14 * look.scale, height: 1.2);
      face = Padding(
        padding: EdgeInsets.symmetric(horizontal: 4 * look.scale, vertical: 6 * look.scale),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: look.matchdayTitle.copyWith(color: look.ink(1), fontSize: 26 * look.scale),
            ),
            if (dates != null || isCurrent) ...[
              SizedBox(height: 4 * look.scale),
              Builder(
                builder: (context) => Text.rich(
                  TextSpan(
                    children: [
                      if (dates != null) TextSpan(text: dates),
                      if (dates != null && isCurrent) const TextSpan(text: ' · '),
                      if (isCurrent)
                        TextSpan(
                          text: t.sport.current,
                          style: TextStyle(
                            color: OckerFlatFocusInk.invertingAt(context) ? look.ink(1) : look.live,
                            fontWeight: .w600,
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: quiet,
                ),
              ),
            ],
          ],
        ),
      );
    } else if (look.flat) {
      final quiet = look.leagueLabel.copyWith(color: look.ink(0.55));
      face = Padding(
        padding: EdgeInsets.symmetric(horizontal: 12 * look.scale, vertical: 8 * look.scale),
        child: Row(
          mainAxisSize: .min,
          crossAxisAlignment: .baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(label, style: look.matchdayTitle.copyWith(color: look.ink(1))),
            if (dates != null) ...[
              SizedBox(width: 14 * look.scale),
              Flexible(
                child: Text(dates, maxLines: 1, overflow: TextOverflow.ellipsis, style: quiet),
              ),
            ],
            if (isCurrent) ...[
              SizedBox(width: 14 * look.scale),
              // In ink on the white focus fill, which turns it dark: the
              // accent, inverted with the title, came out as its complement.
              Builder(
                builder: (context) => Text(
                  t.sport.current,
                  style: quiet.copyWith(
                    color: OckerFlatFocusInk.invertingAt(context) ? look.ink(1) : look.live,
                    fontSize: 15 * look.scale,
                    fontWeight: .w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    } else {
      face = Padding(
        padding: EdgeInsets.symmetric(horizontal: 16 * look.scale, vertical: 4 * look.scale),
        child: _matchdayFace(look, label: label, style: style, dates: dates, isCurrent: isCurrent, detail: detail),
      );
    }
    return FocusableWrapper(
      key: _matchdayKey,
      focusNode: _matchdayNode,
      borderRadius: look.tk.radiusSm,
      useBackgroundFocus: true,
      glassFocus: true,
      semanticLabel: label,
      onSelect: () => unawaited(_chooseMatchday()),
      onNavigateUp: widget.onExitUp,
      // Flat: the title leads the bar and both arrows follow it.
      onNavigateLeft: look.flat ? (widget.onExitLeft ?? () {}) : _previousNode.requestFocus,
      onNavigateRight: look.flat ? _previousNode.requestFocus : _nextNode.requestFocus,
      onNavigateDown: _focusFirstMatch,
      child: SportTap(onTap: () => unawaited(_chooseMatchday()), child: face),
    );
  }

  /// "Spieltag 5 ⌄" over its dates, in the bar's middle.
  Widget _matchdayFace(
    SportLook look, {
    required String label,
    required TextStyle style,
    required String? dates,
    required bool isCurrent,
    required TextStyle detail,
  }) {
    return Column(
      mainAxisSize: .min,
      children: [
        Row(
          mainAxisSize: .min,
          children: [
            Text(label, style: style),
            SizedBox(width: 4 * look.scale),
            AppIcon(Symbols.keyboard_arrow_down_rounded, size: style.fontSize! * 1.1, color: look.ink(0.72)),
          ],
        ),
        // The redesign sets both lines at a line height of 1, so
        // without a gap the dates would touch the label.
        if (dates != null || isCurrent) SizedBox(height: (look.ocker ? 7 : 3) * look.scale),
        if (dates != null || isCurrent)
          Text.rich(
            TextSpan(
              children: [
                if (dates != null) TextSpan(text: dates),
                if (dates != null && isCurrent) const TextSpan(text: ' · '),
                if (isCurrent)
                  TextSpan(
                    text: t.sport.current,
                    style: TextStyle(color: look.live),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: detail,
          ),
      ],
    );
  }

  /// Every matchday of the season as a menu, opening on the one on show.
  ///
  /// The current matchday says so, which is the way back to "now" after
  /// wandering off to the end of the season.
  Future<void> _chooseMatchday() async {
    if (_matchdays.isEmpty) return;
    final box = _matchdayKey.currentContext?.findRenderObject() as RenderBox?;
    final anchor = box == null || !box.hasSize ? null : box.localToGlobal(Offset.zero) & box.size;
    final chosen = await showAdaptiveAppMenu<int>(
      context,
      title: t.sport.chooseMatchday,
      anchorRect: anchor,
      anchorAlignment: AppMenuAnchorAlignment.center,
      focusFirstItem: true,
      isScrollControlled: true,
      entries: [
        for (final day in _matchdays)
          AppMenuItem<int>(
            value: day.order,
            label: sportMatchdayLabel(widget.league, day.order, name: day.name),
            subtitle: day.order == _currentMatchday ? t.sport.current : null,
            selected: day.order == _selected,
          ),
      ],
    );
    if (!mounted) return;
    _matchdayNode.requestFocus();
    if (chosen != null) unawaited(_selectMatchday(chosen));
  }

  void _focusFirstMatch() {
    if (_dayLoading || _matches.isEmpty) return;
    if (_boardShown) return _focusBoardEntry();
    if (_stage != null) return _stageNode.requestFocus();
    _matchNode(_matches.first.id).requestFocus();
  }

  void _focusMatchdayButton() => _matchdayNode.requestFocus();

  // -------------------------------------------------------------- fixtures

  /// Whether a fixtures column this wide gets the clubs' short names —
  /// "Dortmund", "HSV" — the way a results app on a phone sets them. Full
  /// names there leave "Borussia …" and "TSG Hoffe…".
  /// Plebz: the redesigns' scoreboard line holds a pairing on one line down
  /// to 560 — an upright tablet's column beside the table stacked the two
  /// clubs with room to spare.
  bool _isCompact(SportLook look, double width) => width / look.scale < (look.flat ? 560 : 640);

  List<Widget> _matchItems(SportLook look, {required bool compact}) {
    final items = <Widget>[];
    final locale = LocaleSettings.currentLocale.intlLocaleName;
    DateTime? day;
    final listed = _listed;
    final stage = _stage;
    if (stage != null) items.add(_buildStage(look, stage, locale));
    for (var i = 0; i < listed.length; i++) {
      final match = listed[i];
      final matchDay = DateUtils.dateOnly(match.kickoff);
      if (matchDay != day) {
        day = matchDay;
        items.add(
          Padding(
            padding: EdgeInsets.only(
              top: i == 0 && stage == null ? 0 : look.gap,
              bottom: look.gap / 2,
              left: 4 * look.scale,
            ),
            child: Text(
              look.headingCase(_dayLabel(matchDay, locale)),
              style: look.dayHeading.copyWith(color: look.ink(0.55)),
            ),
          ),
        );
      }
      items.add(_matchRow(look, match, i, locale, compact: compact));
    }
    return items;
  }

  String _dayLabel(DateTime day, String locale) {
    final today = DateUtils.dateOnly(clock.now());
    final difference = day.difference(today).inDays;
    final date = DateFormat.MMMMEEEEd(locale).format(day);
    return switch (difference) {
      0 => '${t.sport.today} · $date',
      1 => '${t.sport.tomorrow} · $date',
      -1 => '${t.sport.yesterday} · $date',
      _ => date,
    };
  }

  Widget _matchRow(SportLook look, SportMatch match, int index, String locale, {required bool compact}) {
    final now = clock.now();
    final score = match.scoreAt(now);
    final live = match.isLive(now);
    final listed = _listed;
    // Both redesigns (Plebz): the line as a scoreboard — the clubs' colours at
    // its two ends, the score on a board of its own, a game on now lit up.
    final board = look.flat;
    // A tie level after extra time is decided by its shoot-out.
    final decider = match.penalties ?? score;
    final homeWon = decider != null && match.isFinished && decider.home > decider.away;
    final awayWon = decider != null && match.isFinished && decider.away > decider.home;
    final note = sportScoreNote(match);
    // A phone's line under the redesigns (Plebz, the viewer's pick): the two
    // clubs one above the other, each with its colour, crest, full name and
    // goals — side by side a phone left their names a few letters each.
    final stacked = board && compact;

    return Padding(
      padding: EdgeInsets.only(bottom: 4 * look.scale),
      child: FocusableWrapper(
        focusNode: _matchNode(match.id),
        borderRadius: look.tk.radiusSm,
        useBackgroundFocus: true,
        glassFocus: true,
        // A row as wide as the page, grown from its centre, pushes its time
        // out past the list's left edge, where it is clipped. The plate
        // behind it already says which one is under the cursor.
        disableScale: true,
        semanticLabel: [
          match.home.name,
          match.away.name,
          if (score != null) score.toString() else DateFormat.Hm(locale).format(match.kickoff),
        ].join(', '),
        onFocusChange: (focused) {
          if (focused && _focusedMatch?.id != match.id) {
            setState(() => _focusedMatch = match);
          } else if (!focused && board && live) {
            // ignore: no-empty-block - the lit plate comes back with the rebuild
            setState(() {});
          }
        },
        onSelect: () => _openMatch(match),
        onNavigateUp: index > 0
            ? () => _matchNode(listed[index - 1].id).requestFocus()
            : _stage != null
            ? _stageNode.requestFocus
            : _focusMatchdayButton,
        onNavigateDown: index == listed.length - 1 ? () {} : () => _matchNode(listed[index + 1].id).requestFocus(),
        onNavigateLeft: widget.onExitLeft ?? () {},
        // Nothing to the right takes focus: the table is read, not walked.
        onNavigateRight: () {},
        onBack: _focusMatchdayButton,
        child: SportTap(
          onTap: () => _openMatch(match),
          child: Container(
            height: stacked ? null : look.matchRowHeight,
            // Two lines grow with the viewer's text size.
            constraints: stacked ? BoxConstraints(minHeight: look.matchRowHeight) : null,
            // Room inside the row, so the time does not stand on the edge of
            // the plate that marks the row holding focus — wherever that plate
            // is glass, a phone wearing the look included.
            padding: EdgeInsets.symmetric(
              horizontal: ockerGlass(context) ? (stacked ? 12 : 16) * look.scale : 0,
              vertical: stacked ? 8 * look.scale : 0,
            ),
            decoration: board && live && !_matchNode(match.id).hasFocus
                ? BoxDecoration(
                    color: look.live.withValues(alpha: 0.1),
                    border: Border.all(color: look.live.withValues(alpha: 0.45)),
                    borderRadius: BorderRadius.circular(look.tk.radiusSm),
                  )
                : null,
            child: stacked
                ? _StackedMatchLines(
                    match: match,
                    score: score,
                    live: live,
                    homeWon: homeWon,
                    awayWon: awayWon,
                    look: look,
                    locale: locale,
                  )
                : Row(
                    children: [
                      if (board) ...[_ClubEdge(team: match.home, look: look), SizedBox(width: 12 * look.scale)],
                      SizedBox(
                        width: (look.ocker ? 88 : (compact ? 50 : 64)) * look.scale,
                        child: live
                            ? _LiveBadge(look: look)
                            : Text(
                                DateFormat.Hm(locale).format(match.kickoff),
                                style: look.time.copyWith(color: look.ink(match.isFinished ? 0.45 : 0.7)),
                              ),
                      ),
                      Expanded(
                        child: _TeamCell(team: match.home, look: look, alignEnd: true, strong: homeWon, short: compact),
                      ),
                      SizedBox(
                        width: (look.ocker ? 104 : (compact ? 58 : 76)) * look.scale,
                        child: Center(
                          // On Flach's white focus fill what stands on it is
                          // inverted, and the accent came out as its complement. In
                          // ink there, the score turns dark like the names beside it.
                          child: board
                              ? _ScoreBoard(score: score, live: live, look: look, note: note)
                              : note != null
                              ? FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Column(
                                    mainAxisSize: .min,
                                    children: [
                                      Text(
                                        '${score!.home} : ${score.away}',
                                        style: look.score(strong: true).copyWith(color: look.ink(1)),
                                      ),
                                      Text(
                                        note,
                                        style: look.time.copyWith(
                                          color: look.ink(0.55),
                                          fontSize: look.time.fontSize! * 0.8,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : Builder(
                                  builder: (context) => Text(
                                    score == null ? '–:–' : '${score.home} : ${score.away}',
                                    style: look
                                        .score(strong: score != null)
                                        .copyWith(
                                          color: live && !OckerFlatFocusInk.invertingAt(context)
                                              ? look.live
                                              : look.ink(score == null ? 0.4 : 1),
                                        ),
                                  ),
                                ),
                        ),
                      ),
                      Expanded(
                        child: _TeamCell(
                          team: match.away,
                          look: look,
                          alignEnd: false,
                          strong: awayWon,
                          short: compact,
                        ),
                      ),
                      if (board) ...[SizedBox(width: 12 * look.scale), _ClubEdge(team: match.away, look: look)],
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  /// The favourite club's game, on a stage of its clubs' colours over the
  /// rest of the matchday (Plebz). OK opens it as a line of the list does.
  Widget _buildStage(SportLook look, SportMatch match, String locale) {
    final listed = _listed;
    final radius = (look.flat ? 20 : 12) * look.scale;
    final score = match.scoreAt(clock.now());
    return Padding(
      padding: EdgeInsets.only(bottom: look.gap / 2),
      child: FocusableWrapper(
        focusNode: _stageNode,
        borderRadius: radius,
        disableScale: true,
        semanticLabel: [match.home.name, match.away.name, if (score != null) score.toString()].join(', '),
        onFocusChange: (focused) {
          if (focused && _focusedMatch?.id != match.id) setState(() => _focusedMatch = match);
        },
        onSelect: () => _openMatch(match),
        onNavigateUp: _focusMatchdayButton,
        onNavigateDown: listed.isEmpty ? () {} : () => _matchNode(listed.first.id).requestFocus(),
        onNavigateLeft: widget.onExitLeft ?? () {},
        onNavigateRight: () {},
        onBack: _focusMatchdayButton,
        child: SportTap(
          onTap: () => _openMatch(match),
          child: _FavouriteStage(match: match, look: look, locale: locale, radius: radius),
        ),
      ),
    );
  }
}

/// The favourite club's game, large (Plebz): both crests and the score — or
/// the pairing, before it starts — on the clubs' colours, the state of the
/// game over them and the clubs' names under them.
class _FavouriteStage extends StatelessWidget {
  const _FavouriteStage({required this.match, required this.look, required this.locale, required this.radius});

  final SportMatch match;
  final SportLook look;
  final String locale;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final now = clock.now();
    final live = match.isLive(now);
    final score = match.scoreAt(now);
    final home = clubColourFor(match.home);
    final away = clubColourFor(match.away);
    final ink = home != null || away != null ? Colors.white : look.ink(1);
    final s = look.scale;
    final kickoff = match.kickoff.toLocal();
    final status = live
        ? _LiveBadge(look: look)
        : Text(
            match.isFinished
                ? (sportScoreNote(match) ?? t.sport.finalScore)
                : '${DateFormat.EEEE(locale).format(kickoff)}, ${DateFormat.Hm(locale).format(kickoff)}',
            style: look.time.copyWith(color: ink.withValues(alpha: 0.78)),
          );
    return SizedBox(
      height: (look.ocker ? 220 : 160) * s,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: ClubColourGround(
          home: home,
          away: away,
          borderRadius: BorderRadius.circular(radius),
          child: Padding(
            padding: EdgeInsets.fromLTRB(20 * s, 16 * s, 20 * s, 16 * s),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(height: 26 * s, child: status),
                ),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: .min,
                      children: [
                        SportCrest(team: match.home, size: look.crest * 2.6),
                        SizedBox(width: 40 * s),
                        if (score != null)
                          Text(
                            '${score.home} : ${score.away}',
                            style: look.score().copyWith(fontSize: 64 * s, color: ink),
                          )
                        else
                          Text(t.sport.versus, style: look.teamName().copyWith(color: ink.withValues(alpha: 0.6))),
                        SizedBox(width: 40 * s),
                        SportCrest(team: match.away, size: look.crest * 2.6),
                      ],
                    ),
                  ),
                ),
                Text(
                  '${match.home.name} – ${match.away.name}',
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: look.teamName().copyWith(color: ink.withValues(alpha: 0.9)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A fixture as a phone shows it under the redesigns (Plebz): the kickoff, or
/// LIVE, at the left; beside it the two clubs one above the other, each with
/// its colour, crest, full name and goals. The winner's line in full ink, the
/// loser's goals faint, a running game's goals in the live colour.
class _StackedMatchLines extends StatelessWidget {
  const _StackedMatchLines({
    required this.match,
    required this.score,
    required this.live,
    required this.homeWon,
    required this.awayWon,
    required this.look,
    required this.locale,
  });

  final SportMatch match;
  final SportScore? score;
  final bool live;
  final bool homeWon;
  final bool awayWon;
  final SportLook look;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final score = this.score;
    return Row(
      children: [
        SizedBox(
          width: 52 * look.scale,
          child: live
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: _LiveBadge(look: look),
                )
              : Text(
                  DateFormat.Hm(locale).format(match.kickoff),
                  style: look.time.copyWith(color: look.ink(match.isFinished ? 0.45 : 0.7)),
                ),
        ),
        Expanded(
          child: Column(
            mainAxisSize: .min,
            children: [
              _StackedTeamLine(
                team: match.home,
                goals: score?.home,
                won: homeWon,
                lost: awayWon,
                live: live,
                look: look,
              ),
              SizedBox(height: 6 * look.scale),
              _StackedTeamLine(
                team: match.away,
                goals: score?.away,
                won: awayWon,
                lost: homeWon,
                live: live,
                look: look,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StackedTeamLine extends StatelessWidget {
  const _StackedTeamLine({
    required this.team,
    required this.goals,
    required this.won,
    required this.lost,
    required this.live,
    required this.look,
  });

  final SportTeam team;
  final int? goals;
  final bool won;
  final bool lost;
  final bool live;
  final SportLook look;

  @override
  Widget build(BuildContext context) {
    final goals = this.goals;
    final s = look.scale;
    return Row(
      children: [
        _ClubEdge(team: team, look: look, height: 18 * s),
        SizedBox(width: 10 * s),
        SportCrest(team: team, size: 22 * s),
        SizedBox(width: 10 * s),
        Expanded(
          child: Text(
            team.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: look.teamName(strong: won).copyWith(color: look.ink(won ? 1 : 0.88)),
          ),
        ),
        if (goals != null) ...[
          SizedBox(width: 12 * s),
          // In ink on Flach's white focus fill, which turns it dark: the live
          // colour, inverted with the row, came out as its complement.
          Text(
            '$goals',
            style: look
                .score(strong: !lost)
                .copyWith(
                  fontSize: 18 * s,
                  color: live && !OckerFlatFocusInk.invertingAt(context) ? look.live : look.ink(lost ? 0.5 : 1),
                ),
          ),
        ],
      ],
    );
  }
}

/// A club's colour as an edge of its line (Plebz): the clubs of a game told
/// apart before their names are read. Grey for a club in black and white.
class _ClubEdge extends StatelessWidget {
  const _ClubEdge({required this.team, required this.look, this.height});

  final SportTeam team;
  final SportLook look;

  /// The line's own height by default; a phone's two lines take one each.
  final double? height;

  @override
  Widget build(BuildContext context) {
    final colour = clubColourFor(team);
    // In their own colours on Flach's white focus fill too.
    return OckerKeepColours(
      child: Container(
        width: (height == null ? 4 : 3) * look.scale,
        height: height ?? look.matchRowHeight * 0.56,
        decoration: BoxDecoration(
          color: colour == null ? Colors.white.withValues(alpha: 0.22) : clubMarkColour(colour),
          borderRadius: BorderRadius.circular(2 * look.scale),
        ),
      ),
    );
  }
}

/// The score on a board of its own, as a stadium shows it (Plebz): white on
/// black, in the live colour while the game is on, faint before it starts.
/// Its own colours on Flach's white focus fill as well — a scoreboard stays
/// one.
/// How a cup tie was decided, under its score (Plebz): "n. V." after extra
/// time, "4:3 i. E." after a shoot-out; null for anything else.
String? sportScoreNote(SportMatch match) {
  final penalties = match.penalties;
  if (penalties != null) return t.sport.onPenalties(score: '${penalties.home}:${penalties.away}');
  if (match.afterExtraTime && match.isFinished) return t.sport.afterExtraTime;
  return null;
}

class _ScoreBoard extends StatelessWidget {
  const _ScoreBoard({required this.score, required this.live, required this.look, this.note});

  final SportScore? score;
  final bool live;
  final SportLook look;

  /// How a cup tie was decided ([sportScoreNote]).
  final String? note;

  @override
  Widget build(BuildContext context) {
    final score = this.score;
    return OckerKeepColours(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: (look.ocker ? 12 : 8) * look.scale, vertical: 6 * look.scale),
          decoration: BoxDecoration(
            color: const Color(0xF2050505),
            border: Border.all(color: live ? look.live : Colors.white.withValues(alpha: 0.14)),
            borderRadius: BorderRadius.circular(8 * look.scale),
          ),
          child: Column(
            mainAxisSize: .min,
            children: [
              Text(
                score == null ? '–:–' : '${score.home} : ${score.away}',
                style: look
                    .score(strong: score != null)
                    .copyWith(color: live ? look.live : Colors.white.withValues(alpha: score == null ? 0.4 : 1)),
              ),
              if (note != null)
                Text(
                  note!,
                  style: look.time.copyWith(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: look.time.fontSize! * 0.75,
                    height: 1.1,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tap or a click on something the remote reaches through its
/// [FocusableWrapper] — which answers keys, not pointers. On a phone and under
/// a mouse this is what makes the same parts work.
class SportTap extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;

  const SportTap({super.key, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) => GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: child);
}

class _LiveBadge extends StatelessWidget {
  final SportLook look;

  const _LiveBadge({required this.look});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      // A signal in its own colours, on Flach's white focus fill too: inverted
      // with the row, the accent badge came out in its complement.
      child: OckerKeepColours(child: _badge()),
    );
  }

  Widget _badge() => Container(
    padding: EdgeInsets.symmetric(horizontal: (look.flat ? 9 : 6) * look.scale, vertical: 3 * look.scale),
    decoration: ShapeDecoration(
      color: look.live,
      shape: look.flat
          ? const StadiumBorder()
          : RoundedRectangleBorder(borderRadius: BorderRadius.circular(look.tk.radiusXs)),
    ),
    // White or the ground, whichever reads on the colour: a picked yellow
    // accent takes the dark.
    child: Text(
      t.sport.live,
      style: look.badge.copyWith(
        color: ThemeData.estimateBrightnessForColor(look.live) == Brightness.dark ? Colors.white : look.tk.bg,
      ),
    ),
  );
}

/// A club in a fixture line: its crest on the side nearest the score, its
/// name on the far side of that.
class _TeamCell extends StatelessWidget {
  final SportTeam team;
  final SportLook look;
  final bool alignEnd;
  final bool strong;

  /// The club's short name, for a narrow column.
  final bool short;

  const _TeamCell({
    required this.team,
    required this.look,
    required this.alignEnd,
    required this.strong,
    required this.short,
  });

  @override
  Widget build(BuildContext context) {
    final name = Flexible(
      child: Text(
        short ? team.shortName : team.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: alignEnd ? TextAlign.end : TextAlign.start,
        style: look.teamName(strong: strong).copyWith(color: look.ink(strong ? 1 : 0.88)),
      ),
    );
    final crest = SportCrest(team: team, size: look.crest);
    final space = SizedBox(width: look.gap * 0.7);
    return Row(
      mainAxisAlignment: alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: alignEnd ? [name, space, crest] : [crest, space, name],
    );
  }
}

/// A club's crest, or a plain shield where the provider has none.
///
/// Wikimedia, where most crests live, throttles a burst of image requests
/// (429), and a whole matchday's crests are one such burst: the crests that
/// lost out came back on their own, a little later, one by one. A crest whose
/// link is dead (404) — or that keeps failing — is taken from the club's
/// Wikipedia article instead ([SportCrestFallback]).
class SportCrest extends StatefulWidget {
  final SportTeam team;
  final double size;

  const SportCrest({super.key, required this.team, required this.size});

  /// How long a throttled crest waits before it asks again: growing, with a
  /// little spread so a matchday's crests do not all come back at once.
  @visibleForTesting
  static Duration retryDelay(int attempt, {int spreadMs = 0}) =>
      Duration(milliseconds: 800 * (1 << attempt.clamp(0, 4)) + spreadMs);

  /// Throttled or a passing fault: ask again, a few times. A link that is not
  /// there (404, 410) goes to the fallback at once.
  @visibleForTesting
  static bool shouldRetry(int? statusCode, int attempt) =>
      attempt < _maxRetries && statusCode != 404 && statusCode != 410;

  static const int _maxRetries = 4;

  @override
  State<SportCrest> createState() => _SportCrestState();
}

class _SportCrestState extends State<SportCrest> {
  static final math.Random _spread = math.Random();

  String? _url;
  int _attempt = 0;
  int? _failedAttempt;
  Timer? _retry;
  bool _askedFallback = false;

  @override
  void initState() {
    super.initState();
    _url = widget.team.iconUrl;
    if (_url == null) unawaited(_takeFallback());
  }

  @override
  void didUpdateWidget(covariant SportCrest oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.team.id == widget.team.id && oldWidget.team.iconUrl == widget.team.iconUrl) return;
    _retry?.cancel();
    _retry = null;
    _url = widget.team.iconUrl;
    _attempt = 0;
    _failedAttempt = null;
    _askedFallback = false;
    if (_url == null) unawaited(_takeFallback());
  }

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  void _onFailed(Object error) {
    if (!mounted || _failedAttempt == _attempt) return;
    _failedAttempt = _attempt;
    final status = error is HttpExceptionWithStatus ? error.statusCode : null;
    if (SportCrest.shouldRetry(status, _attempt)) {
      _retry = Timer(SportCrest.retryDelay(_attempt, spreadMs: _spread.nextInt(600)), () {
        _retry = null;
        if (mounted) setState(() => _attempt++);
      });
    } else {
      unawaited(_takeFallback());
    }
  }

  Future<void> _takeFallback() async {
    if (_askedFallback) return;
    _askedFallback = true;
    final url = await SportCrestFallback.instance.crestFor(widget.team);
    if (!mounted || url == null || url == _url) return;
    setState(() {
      _url = url;
      _attempt = 0;
      _failedAttempt = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    // The image's own stand-ins are a filled plate with a 40px glyph — made
    // for a poster, and at a crest's size the glyph spills over the club's
    // name. A crest that is loading shows nothing; one that cannot be had
    // shows a quiet shield of its own size.
    Widget shield(BuildContext context) => Center(
      child: AppIcon(Symbols.shield_rounded, size: size * 0.8, color: tokens(context).ink(0.3)),
    );
    final url = _url;
    return SizedBox.square(
      dimension: size,
      child: url == null
          ? shield(context)
          : OptimizedMediaImage.thumb(
              // A new attempt is a new image, so the failed load is asked again.
              key: ValueKey('$url#$_attempt'),
              imagePath: url,
              width: size,
              height: size,
              fit: BoxFit.contain,
              placeholder: (_, _) => const SizedBox.shrink(),
              errorWidget: (context, _, error) {
                WidgetsBinding.instance.addPostFrameCallback((_) => _onFailed(error));
                return shield(context);
              },
            ),
    );
  }
}

// ------------------------------------------------------------------ table

/// Where a place in the table stands for something — the places that go
/// up, or into the Champions League (0), the next ones, Europe or the
/// promotion play-off (1), and the foot, the ones that go down (2) — as a
/// stroke at its left under the redesigns, in the zone's colour, with a key
/// under the table. Null for the places between. [count] is the table's
/// length.
int? sportTableZone(SportLeague league, int position, int count) {
  final (top, next, bottom) = switch (league) {
    // Champions League, then the Europa places; the play-off and the drop.
    SportLeague.bundesliga1 => (4, 6, 3),
    // Promotion, the play-off; the play-off and the drop.
    SportLeague.bundesliga2 => (2, 3, 3),
    // Promotion, the play-off; the drop.
    SportLeague.liga3 => (2, 3, 4),
    // The league phase (Plebz): the round of sixteen, the knock-out
    // play-offs, out.
    SportLeague.championsLeague || SportLeague.europaLeague => (8, 24, count - 24),
    // Knock-out only; it has no table.
    SportLeague.dfbPokal => (0, 0, 0),
  };
  if (position <= top) return 0;
  if (position <= next) return 1;
  if (position > count - bottom) return 2;
  return null;
}

Color sportZoneColour(SportLeague league, int zone) => switch (zone) {
  0 => league == SportLeague.bundesliga1 ? const Color(0xFF3D7BE0) : const Color(0xFF2FAE5B),
  1 => const Color(0xFFE8912D),
  _ => const Color(0xFFD9534F),
};

String sportZoneLabel(SportLeague league, int zone) => switch ((league, zone)) {
  (SportLeague.championsLeague || SportLeague.europaLeague, 0) => t.sport.zoneRoundOf16,
  (SportLeague.championsLeague || SportLeague.europaLeague, 1) => t.sport.zoneKnockoutPlayoff,
  (SportLeague.championsLeague || SportLeague.europaLeague, _) => t.sport.zoneEliminated,
  (SportLeague.bundesliga1, 0) => t.sport.zoneChampionsLeague,
  (SportLeague.bundesliga1, 1) => t.sport.zoneEurope,
  (_, 0) => t.sport.zonePromotion,
  (_, 1) => t.sport.zonePlayoff,
  _ => t.sport.zoneRelegation,
};

class _SportTable extends StatelessWidget {
  final List<SportTableRow> rows;
  final SportLook look;

  /// The two clubs of the fixture under the cursor.
  final Set<int> highlight;

  /// Share the height it is given between its rows, rather than taking its
  /// natural height. Side by side with the fixtures the whole table has to be
  /// on screen: it is read, not walked, so a part below the edge could never
  /// be scrolled to with a remote.
  final bool fitHeight;

  /// Which league, for where its table's zones fall.
  final SportLeague league;

  /// Where a long table breaks into a second column beside the first
  /// (Plebz: a European cup's 36 clubs on a page of their own); null for one.
  final int? splitAt;

  /// "Tabelle" over the rows; left out where something over the panel says
  /// it already (Plebz, a phone's switch).
  final bool showTitle;

  const _SportTable({
    required this.rows,
    required this.look,
    required this.highlight,
    required this.league,
    this.fitHeight = false,
    this.splitAt,
    this.showTitle = true,
  });

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    // "Flach" (Plebz): the table stands on a panel of its own, as the detail
    // panel does on the other pages, under a title rather than a label.
    // Glas: the same panel as a card of glass, as its detail panel is.
    if (look.flat) {
      final pad = 16 * look.scale;
      final padding = EdgeInsets.fromLTRB(pad, pad + 4 * look.scale, pad, pad);
      final radius = BorderRadius.circular(24 * look.scale);
      final panel = ockerFlat(context)
          ? Container(
              padding: padding,
              decoration: BoxDecoration(
                color: look.ink(0.045),
                border: Border.all(color: look.ink(0.08)),
                borderRadius: radius,
              ),
              child: _buildTable(context),
            )
          : OckerGlass(
              borderRadius: radius,
              scrimInset: 0,
              child: Padding(padding: padding, child: _buildTable(context)),
            );
      // Beside the fixtures the panel runs to the foot of the page.
      return fitHeight ? SizedBox.expand(child: panel) : panel;
    }
    return _buildTable(context);
  }

  int? _zone(int position) => sportTableZone(league, position, rows.length);

  Color _zoneColour(int zone) => sportZoneColour(league, zone);

  String _zoneLabel(int zone) => sportZoneLabel(league, zone);

  TextStyle get _legendStyle {
    final cell = look.tableCell();
    return cell.copyWith(fontSize: cell.fontSize! * 0.72, color: look.ink(0.55));
  }

  /// What the strokes stand for, under the table.
  Widget _legend() {
    final s = look.scale;
    return Padding(
      padding: EdgeInsets.only(top: look.gap * 0.6, left: 4 * s),
      child: Wrap(
        spacing: 14 * s,
        runSpacing: 4 * s,
        children: [
          for (final zone in const [0, 1, 2])
            Row(
              mainAxisSize: .min,
              children: [
                Container(
                  width: 3 * s,
                  height: 12 * s,
                  decoration: BoxDecoration(color: _zoneColour(zone), borderRadius: BorderRadius.circular(2 * s)),
                ),
                SizedBox(width: 6 * s),
                Text(_zoneLabel(zone), style: _legendStyle),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildTable(BuildContext context) {
    final heading = Padding(
      padding: EdgeInsets.only(bottom: look.gap / 2, left: 4 * look.scale),
      child: Text(
        look.headingCase(t.sport.table),
        style: look.flat
            ? look.matchdayTitle.copyWith(fontSize: 24 * look.scale, color: look.ink(1))
            : look.heading.copyWith(color: look.ink(0.55)),
      ),
    );
    if (!fitHeight) {
      return Column(
        crossAxisAlignment: .start,
        children: [
          if (showTitle) heading,
          _columns((look.ocker ? 40 : 30) * look.scale, natural: true),
          if (look.flat) _legend(),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // What the heading and the key take, as drawn (Plebz): the redesigns'
        // title is the larger one, and the key's line its stroke or its words,
        // whichever is taller — measured short, the key fell off the foot.
        final titleSize = look.flat ? 24 * look.scale : look.heading.fontSize!;
        final headingHeight = showTitle ? titleSize * 1.4 + look.gap / 2 : 0.0;
        final legendLine = math.max(_legendStyle.fontSize! * 1.5, 12 * look.scale);
        final legendHeight = look.flat ? legendLine + look.gap * 0.6 + 4 * look.scale : 0.0;
        final available = constraints.maxHeight - headingHeight - legendHeight;
        final perColumn = splitAt == null ? rows.length : splitAt!.clamp(0, rows.length);
        final rowHeight = (available / (perColumn + 1)).clamp(18.0 * look.scale, (look.ocker ? 44 : 34) * look.scale);
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Column(
            crossAxisAlignment: .start,
            children: [if (showTitle) heading, _columns(rowHeight), if (look.flat) _legend()],
          ),
        );
      },
    );
  }

  /// The header and the rows: one column, or two side by side from
  /// [splitAt] on, each under a header of its own.
  Widget _columns(double rowHeight, {bool natural = false}) {
    Widget column(List<SportTableRow> part) => Column(
      crossAxisAlignment: .start,
      children: [
        _headerRow(height: natural ? null : rowHeight),
        for (final row in part) _row(row, rowHeight),
      ],
    );
    final split = splitAt;
    if (split == null || split >= rows.length) return column(rows);
    return Row(
      crossAxisAlignment: .start,
      children: [
        Expanded(child: column(rows.sublist(0, split))),
        SizedBox(width: look.gap * 2),
        Expanded(child: column(rows.sublist(split))),
      ],
    );
  }

  double get _positionWidth => (look.ocker ? 40 : 30) * look.scale;
  double get _numberWidth => (look.ocker ? 52 : 38) * look.scale;

  Widget _headerRow({double? height}) {
    final style = look.tableCell().copyWith(color: look.ink(0.45));
    return SizedBox(
      height: height ?? (look.ocker ? 34 : 26) * look.scale,
      child: Row(
        children: [
          // In line with the rows' places, past their zone strokes.
          if (look.flat) SizedBox(width: 11 * look.scale),
          SizedBox(
            width: _positionWidth,
            child: Text(t.sport.position, style: style),
          ),
          SizedBox(width: look.crest * 0.8 + look.gap * 0.6),
          Expanded(child: Text(t.sport.club, style: style)),
          _number(t.sport.played, style),
          _number(t.sport.difference, style),
          _number(t.sport.points, style),
        ],
      ),
    );
  }

  Widget _row(SportTableRow row, double height) {
    final lit = highlight.contains(row.team.id);
    final style = look.tableCell(strong: lit).copyWith(color: look.ink(lit ? 1 : 0.82));
    final difference = row.goalDifference > 0 ? '+${row.goalDifference}' : '${row.goalDifference}';
    final zone = look.flat ? _zone(row.position) : null;
    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: 4 * look.scale),
      decoration: BoxDecoration(
        color: lit ? look.ink(look.flat ? 0.08 : 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(look.flat ? 12 * look.scale : look.tk.radiusXs),
      ),
      child: Row(
        children: [
          if (look.flat)
            Container(
              width: 3 * look.scale,
              height: (height * 0.5).clamp(0.0, 24 * look.scale),
              margin: EdgeInsets.only(right: 8 * look.scale),
              decoration: BoxDecoration(
                color: zone == null ? Colors.transparent : _zoneColour(zone),
                borderRadius: BorderRadius.circular(2 * look.scale),
              ),
            ),
          SizedBox(
            width: _positionWidth - 4 * look.scale,
            child: Text('${row.position}', style: style),
          ),
          SportCrest(team: row.team, size: (look.crest * 0.8).clamp(0.0, height * 0.8)),
          SizedBox(width: look.gap * 0.6),
          Expanded(
            child: Text(row.team.shortName, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
          ),
          _number('${row.played}', style),
          _number(difference, style),
          _number('${row.points}', style.copyWith(fontWeight: .w700)),
        ],
      ),
    );
  }

  Widget _number(String text, TextStyle style) => SizedBox(
    width: _numberWidth,
    child: Text(text, textAlign: TextAlign.end, style: style),
  );
}
