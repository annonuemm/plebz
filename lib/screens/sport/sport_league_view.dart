import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image_ce/cached_network_image.dart' show HttpExceptionWithStatus;
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../redesign/ocker_skin.dart';
import '../../focus/focusable_wrapper.dart';
import '../../i18n/app_locale_utils.dart';
import '../../i18n/strings.g.dart';
import '../../models/livetv_channel.dart';
import '../../providers/multi_server_provider.dart';
import '../../services/settings_service.dart';
import '../../services/sport/club_colours.dart';
import '../../services/sport/sport_broadcast_matching.dart';
import '../../services/sport/sport_crest_fallback.dart';
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

  const SportLeagueView({
    super.key,
    required this.league,
    required this.isActive,
    required this.onExitUp,
    this.onExitLeft,
    this.repository,
    this.broadcastFinder,
    this.onWatch,
  });

  @override
  State<SportLeagueView> createState() => SportLeagueViewState();
}

class SportLeagueViewState extends State<SportLeagueView> with AutomaticKeepAliveClientMixin {
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

  Timer? _liveTimer;
  final _matchdayNode = FocusNode(debugLabel: 'sport_matchday');
  final _previousNode = FocusNode(debugLabel: 'sport_matchday_previous');
  final _nextNode = FocusNode(debugLabel: 'sport_matchday_next');
  final _matchdayKey = GlobalKey();
  final Map<int, FocusNode> _matchNodes = {};
  final _retryNode = FocusNode(debugLabel: 'sport_retry');
  final _stageNode = FocusNode(debugLabel: 'sport_favourite_stage');

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
  void dispose() {
    _liveTimer?.cancel();
    _matchdayNode.dispose();
    _previousNode.dispose();
    _nextNode.dispose();
    for (final node in _matchNodes.values) {
      node.dispose();
    }
    _retryNode.dispose();
    _stageNode.dispose();
    super.dispose();
  }

  FocusNode _matchNode(int id) => _matchNodes.putIfAbsent(id, () => FocusNode(debugLabel: 'sport_match_$id'));

  /// The favourite club's game of the matchday on show (Plebz), which stands
  /// on a stage over the rest; null without a favourite, or where it does not
  /// play.
  SportMatch? get _stage {
    final club = SettingsService.instanceOrNull?.read(PlebzPrefs.sportFavouriteClub) ?? 0;
    if (club == 0) return null;
    return _matches.where((match) => match.home.id == club || match.away.id == club).firstOrNull;
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
          // the table goes under the fixtures instead of crushing both into
          // columns too narrow for a club's name. Plebz: a handheld needs the
          // height for it too — a phone on its side squeezed the table's rows
          // to slivers beside the fixtures.
          final wide =
              constraints.maxWidth >= 720 &&
              (look.ocker || !PlatformDetector.isMobile(context) || constraints.maxHeight >= 480);
          if (!wide) {
            final bar = _buildMatchdayBar(look, compact: _isCompactBar(look, constraints.maxWidth));
            return Column(
              children: [
                bar,
                SizedBox(height: look.gap),
                Expanded(
                  child: ListView(
                    padding: _listPadding(context),
                    children: [
                      if (_dayLoading || _matches.isEmpty)
                        SizedBox(height: look.matchRowHeight * 3, child: _buildFixturesPlaceholder(look))
                      else
                        ..._matchItems(look, compact: _isCompact(look, constraints.maxWidth)),
                      SizedBox(height: look.gap * 2),
                      _SportTable(rows: _table, look: look, highlight: _highlightedTeams, league: widget.league),
                    ],
                  ),
                ),
              ],
            );
          }
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
                child: _SportTable(
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
            label: previous == null ? null : t.sport.matchday(n: previous),
            onNavigateLeft: widget.onExitLeft ?? () {},
            onNavigateRight: _matchdayNode.requestFocus,
          ),
          Expanded(child: Center(child: _buildMatchdayButton(look))),
          _buildArrow(
            look,
            node: _nextNode,
            icon: Symbols.chevron_right_rounded,
            target: next,
            label: next == null ? null : t.sport.matchday(n: next),
            onNavigateLeft: _matchdayNode.requestFocus,
            onNavigateRight: () {},
          ),
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
            label: previous == null ? null : t.sport.matchday(n: previous),
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
            label: next == null ? null : t.sport.matchday(n: next),
            onNavigateLeft: _previousNode.requestFocus,
            onNavigateRight: () {},
          ),
        ],
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
    final label = selected == null ? '' : t.sport.matchday(n: selected);
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
            label: t.sport.matchday(n: day.order),
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
    if (_stage != null) return _stageNode.requestFocus();
    _matchNode(_matches.first.id).requestFocus();
  }

  void _focusMatchdayButton() => _matchdayNode.requestFocus();

  // -------------------------------------------------------------- fixtures

  /// Whether a fixtures column this wide gets the clubs' short names —
  /// "Dortmund", "HSV" — the way a results app on a phone sets them. Full
  /// names there leave "Borussia …" and "TSG Hoffe…".
  bool _isCompact(SportLook look, double width) => width / look.scale < 640;

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
    final homeWon = score != null && match.isFinished && score.home > score.away;
    final awayWon = score != null && match.isFinished && score.away > score.home;
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
                              ? _ScoreBoard(score: score, live: live, look: look)
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
                ? t.sport.finalScore
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
class _ScoreBoard extends StatelessWidget {
  const _ScoreBoard({required this.score, required this.live, required this.look});

  final SportScore? score;
  final bool live;
  final SportLook look;

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
          child: Text(
            score == null ? '–:–' : '${score.home} : ${score.away}',
            style: look
                .score(strong: score != null)
                .copyWith(color: live ? look.live : Colors.white.withValues(alpha: score == null ? 0.4 : 1)),
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
      child: Icon(Symbols.shield_rounded, size: size * 0.8, color: tokens(context).ink(0.3)),
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

  const _SportTable({
    required this.rows,
    required this.look,
    required this.highlight,
    required this.league,
    this.fitHeight = false,
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

  /// Where a place in the table stands for something — the places that go
  /// up, or into the Champions League (0), the next ones, Europe or the
  /// promotion play-off (1), and the foot, the ones that go down (2) — as a
  /// stroke at its left under the redesigns, in the zone's colour, with a key
  /// under the table. Null for the places between.
  int? _zone(int position) {
    final count = rows.length;
    final (top, next, bottom) = switch (league) {
      // Champions League, then the Europa places; the play-off and the drop.
      SportLeague.bundesliga1 => (4, 6, 3),
      // Promotion, the play-off; the play-off and the drop.
      SportLeague.bundesliga2 => (2, 3, 3),
      // Promotion, the play-off; the drop.
      SportLeague.liga3 => (2, 3, 4),
    };
    if (position <= top) return 0;
    if (position <= next) return 1;
    if (position > count - bottom) return 2;
    return null;
  }

  Color _zoneColour(int zone) => switch (zone) {
    0 => league == SportLeague.bundesliga1 ? const Color(0xFF3D7BE0) : const Color(0xFF2FAE5B),
    1 => const Color(0xFFE8912D),
    _ => const Color(0xFFD9534F),
  };

  String _zoneLabel(int zone) => switch (zone) {
    0 => league == SportLeague.bundesliga1 ? t.sport.zoneChampionsLeague : t.sport.zonePromotion,
    1 => league == SportLeague.bundesliga1 ? t.sport.zoneEurope : t.sport.zonePlayoff,
    _ => t.sport.zoneRelegation,
  };

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
          heading,
          _headerRow(),
          for (final row in rows) _row(row, (look.ocker ? 40 : 30) * look.scale),
          if (look.flat) _legend(),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final headingHeight = look.heading.fontSize! * 1.4 + look.gap / 2;
        final legendHeight = look.flat ? _legendStyle.fontSize! * 1.4 + look.gap * 0.6 : 0.0;
        final available = constraints.maxHeight - headingHeight - legendHeight;
        final rowHeight = (available / (rows.length + 1)).clamp(18.0 * look.scale, (look.ocker ? 44 : 34) * look.scale);
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Column(
            crossAxisAlignment: .start,
            children: [
              heading,
              _headerRow(height: rowHeight),
              for (final row in rows) _row(row, rowHeight),
              if (look.flat) _legend(),
            ],
          ),
        );
      },
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
