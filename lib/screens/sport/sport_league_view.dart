import 'dart:async';

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
import '../../services/sport/sport_broadcast_matching.dart';
import '../../services/sport/sport_models.dart';
import '../../services/sport/sport_repository.dart';
import '../../theme/mono_tokens.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/app_menu.dart';
import '../../widgets/optimized_media_image.dart';
import '../../utils/live_tv_matching.dart';
import '../../utils/live_tv_player_navigation.dart';
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
    super.dispose();
  }

  FocusNode _matchNode(int id) => _matchNodes.putIfAbsent(id, () => FocusNode(debugLabel: 'sport_match_$id'));

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

  /// A running match changes by the minute; nothing else here does.
  Future<void> _refreshIfLive() async {
    if (!mounted || !widget.isActive) return;
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final bar = _buildMatchdayBar(look);
        // Side by side wherever there is a table's width to spare; on a phone
        // the table goes under the fixtures instead of crushing both into
        // columns too narrow for a club's name.
        final wide = constraints.maxWidth >= 720;
        if (!wide) {
          return Column(
            children: [
              bar,
              SizedBox(height: look.gap),
              Expanded(
                child: ListView(
                  children: [
                    if (_dayLoading || _matches.isEmpty)
                      SizedBox(height: look.matchRowHeight * 3, child: _buildFixturesPlaceholder(look))
                    else
                      ..._matchItems(look, compact: _isCompact(look, constraints.maxWidth)),
                    SizedBox(height: look.gap * 2),
                    _SportTable(rows: _table, look: look, highlight: _highlightedTeams),
                  ],
                ),
              ),
            ],
          );
        }
        final tableWidth = ((look.ocker ? 600 : 380) * look.scale).clamp(0.0, constraints.maxWidth * 0.46);
        final fixturesWidth = constraints.maxWidth - tableWidth - look.gap * 2;
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
                        : ListView(children: _matchItems(look, compact: _isCompact(look, fixturesWidth))),
                  ),
                ],
              ),
            ),
            SizedBox(width: look.gap * 2),
            SizedBox(
              width: tableWidth,
              child: _SportTable(rows: _table, look: look, highlight: _highlightedTeams, fitHeight: true),
            ),
          ],
        );
      },
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

  Widget _buildMatchdayBar(SportLook look) {
    final (previous, next) = _neighbours;
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

  /// One of the two arrows. At either end of the season the arrow stays where
  /// it is, dimmed and doing nothing, so the cursor never loses its footing
  /// and the bar keeps its shape.
  Widget _buildArrow(
    SportLook look, {
    required FocusNode node,
    required IconData icon,
    required int? target,
    required String? label,
    required VoidCallback onNavigateLeft,
    required VoidCallback onNavigateRight,
  }) {
    final size = (look.ocker ? 64 : 48) * look.scale;
    void step() {
      if (target != null) unawaited(_selectMatchday(target));
    }

    return FocusableWrapper(
      focusNode: node,
      borderRadius: look.tk.radiusSm,
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
        child: SizedBox.square(
          dimension: size,
          child: Center(
            child: AppIcon(icon, size: size * 0.6, color: look.ink(target == null ? 0.2 : 0.85)),
          ),
        ),
      ),
    );
  }

  /// "Spieltag 5 ⌄" over the dates it is played on. The chevron is the one
  /// the header draws beside a destination that opens a list.
  Widget _buildMatchdayButton(SportLook look) {
    final selected = _selected;
    final label = selected == null ? '' : t.sport.matchday(n: selected);
    final style = look.matchdayChip(current: true).copyWith(color: look.ink(1));
    final dates = _dateRange(LocaleSettings.currentLocale.intlLocaleName);
    final isCurrent = selected != null && selected == _currentMatchday;
    final detail = look.time.copyWith(color: look.ink(0.6));
    return FocusableWrapper(
      key: _matchdayKey,
      focusNode: _matchdayNode,
      borderRadius: look.tk.radiusSm,
      useBackgroundFocus: true,
      glassFocus: true,
      semanticLabel: label,
      onSelect: () => unawaited(_chooseMatchday()),
      onNavigateUp: widget.onExitUp,
      onNavigateLeft: _previousNode.requestFocus,
      onNavigateRight: _nextNode.requestFocus,
      onNavigateDown: _focusFirstMatch,
      child: SportTap(
        onTap: () => unawaited(_chooseMatchday()),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16 * look.scale, vertical: 4 * look.scale),
          child: Column(
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
          ),
        ),
      ),
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
    for (var i = 0; i < _matches.length; i++) {
      final match = _matches[i];
      final matchDay = DateUtils.dateOnly(match.kickoff);
      if (matchDay != day) {
        day = matchDay;
        items.add(
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : look.gap, bottom: look.gap / 2, left: 4 * look.scale),
            child: Text(_dayLabel(matchDay, locale).toUpperCase(), style: look.heading.copyWith(color: look.ink(0.55))),
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
    final homeWon = score != null && match.isFinished && score.home > score.away;
    final awayWon = score != null && match.isFinished && score.away > score.home;

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
          if (focused && _focusedMatch?.id != match.id) setState(() => _focusedMatch = match);
        },
        onSelect: () => _openMatch(match),
        onNavigateUp: index == 0 ? _focusMatchdayButton : () => _matchNode(_matches[index - 1].id).requestFocus(),
        onNavigateDown: index == _matches.length - 1 ? () {} : () => _matchNode(_matches[index + 1].id).requestFocus(),
        onNavigateLeft: widget.onExitLeft ?? () {},
        // Nothing to the right takes focus: the table is read, not walked.
        onNavigateRight: () {},
        onBack: _focusMatchdayButton,
        child: SportTap(
          onTap: () => _openMatch(match),
          child: Container(
            height: look.matchRowHeight,
            // Room inside the row, so the time does not stand on the edge of
            // the plate that marks the row holding focus — wherever that plate
            // is glass, a phone wearing the look included.
            padding: EdgeInsets.symmetric(horizontal: ockerGlass(context) ? 16 * look.scale : 0),
            child: Row(
              children: [
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
                    child: Text(
                      score == null ? '–:–' : '${score.home} : ${score.away}',
                      style: look
                          .score(strong: score != null)
                          .copyWith(color: live ? look.live : look.ink(score == null ? 0.4 : 1)),
                    ),
                  ),
                ),
                Expanded(
                  child: _TeamCell(team: match.away, look: look, alignEnd: false, strong: awayWon, short: compact),
                ),
              ],
            ),
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
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 6 * look.scale, vertical: 3 * look.scale),
        decoration: BoxDecoration(color: look.live, borderRadius: BorderRadius.circular(look.tk.radiusXs)),
        child: Text(t.sport.live, style: look.badge.copyWith(color: Colors.white)),
      ),
    );
  }
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
class SportCrest extends StatelessWidget {
  final SportTeam team;
  final double size;

  const SportCrest({super.key, required this.team, required this.size});

  @override
  Widget build(BuildContext context) {
    // The image's own stand-ins are a filled plate with a 40px glyph — made
    // for a poster, and at a crest's size the glyph spills over the club's
    // name. A crest that is loading shows nothing; one that cannot be had
    // shows a quiet shield of its own size.
    Widget shield(BuildContext context) => Center(
      child: Icon(Symbols.shield_rounded, size: size * 0.8, color: tokens(context).ink(0.3)),
    );
    return SizedBox.square(
      dimension: size,
      child: team.iconUrl == null
          ? shield(context)
          : OptimizedMediaImage.thumb(
              imagePath: team.iconUrl,
              width: size,
              height: size,
              fit: BoxFit.contain,
              placeholder: (_, _) => const SizedBox.shrink(),
              errorWidget: (context, _, _) => shield(context),
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

  const _SportTable({required this.rows, required this.look, required this.highlight, this.fitHeight = false});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final heading = Padding(
      padding: EdgeInsets.only(bottom: look.gap / 2, left: 4 * look.scale),
      child: Text(t.sport.table.toUpperCase(), style: look.heading.copyWith(color: look.ink(0.55))),
    );
    if (!fitHeight) {
      return Column(
        crossAxisAlignment: .start,
        children: [heading, _headerRow(), for (final row in rows) _row(row, (look.ocker ? 40 : 30) * look.scale)],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final headingHeight = look.heading.fontSize! * 1.4 + look.gap / 2;
        final available = constraints.maxHeight - headingHeight;
        final rowHeight = (available / (rows.length + 1)).clamp(18.0 * look.scale, (look.ocker ? 44 : 34) * look.scale);
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Column(
            crossAxisAlignment: .start,
            children: [
              heading,
              _headerRow(height: rowHeight),
              for (final row in rows) _row(row, rowHeight),
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
    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: 4 * look.scale),
      decoration: BoxDecoration(
        color: lit ? look.ink(0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(look.tk.radiusXs),
      ),
      child: Row(
        children: [
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
