import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../focus/dpad_navigator.dart';
import '../../focus/focusable_wrapper.dart';
import '../../i18n/app_locale_utils.dart';
import '../../i18n/strings.g.dart';
import '../../models/livetv_channel.dart';
import '../../services/sport/sport_broadcast_matching.dart';
import '../../services/sport/sport_models.dart';
import '../../utils/live_tv_matching.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/overlay_sheet.dart';
import '../../widgets/live_tv_channel_logo.dart';
import 'sport_broadcast_finder.dart';
import 'sport_league_view.dart' show SportCrest, SportTap;
import 'sport_look.dart';

/// Starts [broadcast] — live, or from the archive at [startAtEpoch] — with
/// [channels] as the list the player zaps through.
typedef SportWatchCallback = void Function(SportBroadcast broadcast, List<LiveTvChannel> channels, {int? startAtEpoch});

/// The window a fixture opens: who, when, how it stands, where to watch it,
/// and who scored.
///
/// [broadcasts] is the guide search, already running; null where there is
/// nothing to search (no Live TV in scope). The window closes itself before
/// [onWatch] runs, so the player opens over the page and BACK from it lands
/// there.
Future<void> showSportMatchSheet(
  BuildContext context, {
  required SportMatch match,
  required SportLeague league,
  required List<SportTableRow> table,
  Future<SportBroadcastSearch?>? broadcasts,
  SportWatchCallback? onWatch,
}) {
  final size = MediaQuery.sizeOf(context);
  final look = SportLook.of(context);
  return OverlaySheetController.showAdaptive<void>(
    context,
    alignment: Alignment.center,
    constraints: BoxConstraints(maxWidth: (size.width * 0.62).clamp(320.0, 1100.0), maxHeight: size.height * 0.86),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.symmetric(horizontal: 36 * look.scale, vertical: 30 * look.scale),
      child: SportMatchDetail(
        match: match,
        league: league,
        table: table,
        broadcasts: broadcasts,
        onWatch: onWatch == null
            ? null
            : (broadcast, channels, {startAtEpoch}) {
                OverlaySheetController.closeAdaptive(sheetContext);
                onWatch(broadcast, channels, startAtEpoch: startAtEpoch);
              },
      ),
    ),
  );
}

class SportMatchDetail extends StatefulWidget {
  final SportMatch match;
  final SportLeague league;
  final List<SportTableRow> table;
  final Future<SportBroadcastSearch?>? broadcasts;
  final SportWatchCallback? onWatch;

  const SportMatchDetail({
    super.key,
    required this.match,
    required this.league,
    required this.table,
    this.broadcasts,
    this.onWatch,
  });

  @override
  State<SportMatchDetail> createState() => _SportMatchDetailState();
}

/// What a broadcast row offers to do.
enum _Watch { live, tune, restart, archive }

class _SportMatchDetailState extends State<SportMatchDetail> {
  final _scroll = ScrollController();
  final _sheetNode = FocusNode(debugLabel: 'sport_match_sheet');

  /// The buttons of the broadcast rows, a row per list.
  final List<List<FocusNode>> _rowNodes = [];

  SportBroadcastSearch? _search;
  bool _searching = false;

  /// The ways to watch, decided once when the search answers: a window is
  /// open for a minute, and a button that changed under the cursor would be
  /// worse than one a minute out of date.
  List<({SportBroadcast broadcast, List<_Watch> actions})> _rows = const [];

  /// Whether any of [_rows] is the game itself, not a guess at it.
  bool _foundGame = false;

  @override
  void initState() {
    super.initState();
    final pending = widget.broadcasts;
    if (pending != null) {
      _searching = true;
      unawaited(
        pending
            .then((search) {
              if (!mounted) return;
              final now = clock.now();
              final rows = <({SportBroadcast broadcast, List<_Watch> actions})>[];
              for (final broadcast in [...?search?.broadcasts, ...?search?.leagueChannels]) {
                final actions = _actionsFor(broadcast, now);
                if (actions.isNotEmpty) rows.add((broadcast: broadcast, actions: actions));
              }
              setState(() {
                _search = search;
                _searching = false;
                _rows = rows;
                _foundGame = rows.any((row) => row.broadcast.kind != SportBroadcastKind.leagueChannel);
                _rowNodes.addAll([
                  for (var i = 0; i < rows.length; i++)
                    [for (var j = 0; j < rows[i].actions.length; j++) FocusNode(debugLabel: 'sport_watch_${i}_$j')],
                ]);
              });
              // Standing where the window opened, the cursor moves to the
              // first way to watch: that is what a game is opened for. Once
              // the viewer has scrolled away, it stays where they put it.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted || !_sheetNode.hasPrimaryFocus) return;
                if (_scroll.hasClients && _scroll.offset > 0) return;
                if (_rowNodes.isNotEmpty) _rowNodes.first.first.requestFocus();
              });
            })
            .catchError((Object _) {
              if (mounted) setState(() => _searching = false);
            }),
      );
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _sheetNode.dispose();
    _disposeRowNodes();
    super.dispose();
  }

  void _disposeRowNodes() {
    for (final row in _rowNodes) {
      for (final node in row) {
        node.dispose();
      }
    }
    _rowNodes.clear();
  }

  void _scrollBy(double delta) {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      (_scroll.offset + delta).clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
    );
  }

  /// UP and DOWN scroll the window while the cursor is on the window itself.
  /// UP at the top goes back to the last way to watch.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!node.hasPrimaryFocus || !event.isActionable || !_scroll.hasClients) return KeyEventResult.ignored;
    final step = 120 * SportLook.of(context).scale;
    if (event.logicalKey.isDownKey) {
      _scrollBy(step);
      return KeyEventResult.handled;
    }
    if (event.logicalKey.isUpKey) {
      if (_scroll.offset <= 0 && _rowNodes.isNotEmpty) {
        _rowNodes.last.first.requestFocus();
      } else {
        _scrollBy(-step);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  SportTableRow? _rowFor(SportTeam team) {
    for (final row in widget.table) {
      if (row.team.id == team.id) return row;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final look = SportLook.of(context);
    final match = widget.match;
    final now = clock.now();
    final score = match.scoreAt(now);
    final live = match.isLive(now);
    final locale = LocaleSettings.currentLocale.intlLocaleName;

    final eyebrow = [
      t.sport.matchday(n: match.matchday.order),
      DateFormat.MMMMEEEEd(locale).format(match.kickoff),
      DateFormat.Hm(locale).format(match.kickoff),
    ].join(' · ');

    return Focus(
      focusNode: _sheetNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: SingleChildScrollView(
        controller: _scroll,
        child: Column(
          crossAxisAlignment: .stretch,
          mainAxisSize: .min,
          children: [
            Text(eyebrow.toUpperCase(), style: look.heading.copyWith(color: look.ink(0.55))),
            SizedBox(height: look.gap * 1.5),
            LayoutBuilder(
              builder: (context, constraints) {
                // A phone's window has no room for two full names and the
                // score between them; the clubs go by their short names.
                final compact = constraints.maxWidth < 520 * look.scale;
                return Row(
                  crossAxisAlignment: .start,
                  children: [
                    Expanded(child: _club(look, match.home, short: compact)),
                    SizedBox(
                      width: (look.ocker ? 220 : (compact ? 110 : 160)) * look.scale,
                      child: Column(
                        children: [
                          Text(
                            score == null ? '–:–' : '${score.home} : ${score.away}',
                            style: look.score().copyWith(
                              fontSize: look.score().fontSize! * 2.1,
                              color: live ? look.live : look.ink(1),
                            ),
                          ),
                          SizedBox(height: look.gap / 2),
                          Text(
                            _state(match, now),
                            textAlign: TextAlign.center,
                            style: look.time.copyWith(color: live ? look.live : look.ink(0.6)),
                          ),
                        ],
                      ),
                    ),
                    Expanded(child: _club(look, match.away, short: compact)),
                  ],
                );
              },
            ),
            ..._broadcastSection(look, locale),
            if (score != null) ...[
              SizedBox(height: look.gap * 2),
              Text(t.sport.goals.toUpperCase(), style: look.heading.copyWith(color: look.ink(0.55))),
              SizedBox(height: look.gap / 2),
              if (match.goals.isEmpty)
                Text(t.sport.noGoals, style: look.body.copyWith(color: look.ink(0.6)))
              else
                ..._goals(look, match),
            ],
            if (_venue(match) case final String venue) ...[
              SizedBox(height: look.gap * 2),
              Text(venue, style: look.body.copyWith(color: look.ink(0.6))),
            ],
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ broadcasts

  List<Widget> _broadcastSection(SportLook look, String locale) {
    if (widget.broadcasts == null) return const [];
    final heading = [
      SizedBox(height: look.gap * 2),
      Text(t.sport.broadcast.toUpperCase(), style: look.heading.copyWith(color: look.ink(0.55))),
      SizedBox(height: look.gap / 2),
    ];
    final note = look.body.copyWith(color: look.ink(0.6));

    if (_searching) {
      return [
        ...heading,
        Row(
          children: [
            SizedBox.square(dimension: 16 * look.scale, child: const CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: look.gap * 0.7),
            Flexible(child: Text(t.sport.searchingGuide, style: note)),
          ],
        ),
      ];
    }

    final search = _search;
    // No Live TV at all: nothing to say, so nothing said.
    if (search == null) return const [];

    final rows = _rows;
    return [
      ...heading,
      if (!_foundGame) Text(t.sport.notInGuide, style: note),
      if (!_foundGame && rows.isNotEmpty) ...[
        SizedBox(height: look.gap / 2),
        Text(t.sport.leagueChannels(league: _leagueName(widget.league)), style: note),
      ],
      SizedBox(height: look.gap / 2),
      _broadcastRows(look, search, locale),
    ];
  }

  static String _leagueName(SportLeague league) => switch (league) {
    SportLeague.bundesliga1 => t.sport.bundesliga1,
    SportLeague.bundesliga2 => t.sport.bundesliga2,
    SportLeague.liga3 => t.sport.liga3,
  };

  /// What can be done with [broadcast] now: a programme on air is watched
  /// live and, where the archive has it, from its start; one still to come
  /// is a channel to tune to; one that is over only from the archive, and
  /// not at all where the archive does not reach.
  List<_Watch> _actionsFor(SportBroadcast broadcast, DateTime now) {
    final program = broadcast.program;
    final begins = program?.beginsAt;
    final ends = program?.endsAt;
    if (program == null || begins == null || ends == null) return const [_Watch.live];
    final nowEpoch = now.millisecondsSinceEpoch ~/ 1000;
    final archived = liveTvProgramIsArchived(broadcast.channel, program, now: now);
    if (ends <= nowEpoch) return archived ? const [_Watch.archive] : const [];
    if (begins > nowEpoch) return const [_Watch.tune];
    final worthRestarting = nowEpoch - begins > liveTvRestartThreshold.inSeconds;
    return [_Watch.live, if (archived && worthRestarting) _Watch.restart];
  }

  /// The ways to watch, one line each: the channel and its programme, then
  /// the buttons. Side by side they are a table, so the first button of every
  /// line stands in one column; on a phone the buttons go under the channel.
  Widget _broadcastRows(SportLook look, SportBroadcastSearch search, String locale) {
    final rows = _rows;
    List<Widget> buttonsOf(int i) => [
      for (var j = 0; j < rows[i].actions.length; j++)
        _watchButton(look, rows[i].broadcast, rows[i].actions[j], i, j, rows[i].actions.length, search),
    ];
    final spacing = look.gap * 0.8;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560 * look.scale) {
          return Column(
            crossAxisAlignment: .stretch,
            children: [
              for (var i = 0; i < rows.length; i++)
                Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : spacing),
                  child: Column(
                    crossAxisAlignment: .start,
                    children: [
                      _broadcastInfo(look, rows[i].broadcast, locale),
                      SizedBox(height: look.gap / 2),
                      Wrap(spacing: look.gap / 2, runSpacing: look.gap / 2, children: buttonsOf(i)),
                    ],
                  ),
                ),
            ],
          );
        }
        final columns = rows.fold<int>(0, (most, row) => row.actions.length > most ? row.actions.length : most);
        return Table(
          columnWidths: {
            0: const FlexColumnWidth(),
            for (var j = 1; j <= columns; j++) j: const IntrinsicColumnWidth(),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            for (var i = 0; i < rows.length; i++)
              TableRow(
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : spacing, right: look.gap),
                    child: _broadcastInfo(look, rows[i].broadcast, locale),
                  ),
                  for (var j = 0; j < columns; j++)
                    Padding(
                      padding: EdgeInsets.only(top: i == 0 ? 0 : spacing, left: j == 0 ? 0 : look.gap / 2),
                      child: j < rows[i].actions.length ? buttonsOf(i)[j] : const SizedBox.shrink(),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }

  Widget _broadcastInfo(SportLook look, SportBroadcast broadcast, String locale) {
    final channel = broadcast.channel;
    final program = broadcast.program;
    final logo = channel.thumb ?? channel.guideLogo;
    final title = program == null ? null : [program.title, ?liveTvNonEmpty(program.subtitle)].join(' – ');
    final start = program?.startTime;
    final end = program?.endTime;
    final times = start == null || end == null
        ? null
        : '${DateFormat.Hm(locale).format(start)}–${DateFormat.Hm(locale).format(end)}';

    return Row(
      children: [
        if (logo != null && (logo.startsWith('http://') || logo.startsWith('https://'))) ...[
          SizedBox(
            width: 64 * look.scale,
            height: 36 * look.scale,
            child: LiveTvChannelLogo(
              channel: channel,
              client: null,
              width: 64 * look.scale,
              height: 36 * look.scale,
              fallback: (_) => const SizedBox.shrink(),
            ),
          ),
          SizedBox(width: look.gap * 0.8),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: .start,
            mainAxisSize: .min,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: channel.displayName),
                    if (broadcast.kind == SportBroadcastKind.conference)
                      TextSpan(
                        text: '  ${t.sport.conference.toUpperCase()}',
                        style: look.badge.copyWith(color: look.live),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: look.teamName(strong: true).copyWith(color: look.ink(1)),
              ),
              if (title != null)
                Text(
                  [?times, title].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: look.time.copyWith(color: look.ink(0.6)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _watchButton(
    SportLook look,
    SportBroadcast broadcast,
    _Watch action,
    int row,
    int column,
    int columns,
    SportBroadcastSearch search,
  ) {
    final (label, icon) = switch (action) {
      _Watch.live => (t.common.play, Symbols.play_arrow_rounded),
      _Watch.tune => (t.liveTv.watchChannel, Symbols.live_tv_rounded),
      _Watch.restart => (t.liveTv.restartFromArchive, Symbols.replay_rounded),
      _Watch.archive => (t.liveTv.watchFromArchive, Symbols.replay_rounded),
    };
    final startAt = action == _Watch.restart || action == _Watch.archive ? broadcast.program?.beginsAt : null;
    void watch() => widget.onWatch?.call(broadcast, search.channels, startAtEpoch: startAt);

    FocusNode? rowNode(int r) =>
        r < 0 || r >= _rowNodes.length ? null : _rowNodes[r][column.clamp(0, _rowNodes[r].length - 1)];
    final style = look.matchdayChip(current: true).copyWith(color: look.ink(1));
    return FocusableWrapper(
      focusNode: _rowNodes[row][column],
      borderRadius: look.tk.radiusSm,
      useBackgroundFocus: true,
      glassFocus: true,
      semanticLabel: '$label, ${broadcast.channel.displayName}',
      onSelect: watch,
      onNavigateLeft: column > 0 ? _rowNodes[row][column - 1].requestFocus : () {},
      onNavigateRight: column < columns - 1 ? _rowNodes[row][column + 1].requestFocus : () {},
      onNavigateUp: () => rowNode(row - 1)?.requestFocus(),
      onNavigateDown: () {
        final next = rowNode(row + 1);
        if (next != null) {
          next.requestFocus();
        } else {
          // Below the last way to watch there are only things to read.
          _sheetNode.requestFocus();
          _scrollBy(120 * look.scale);
        }
      },
      child: SportTap(
        onTap: watch,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 14 * look.scale, vertical: 8 * look.scale),
          decoration: BoxDecoration(
            color: look.ink(column == 0 ? 0.12 : 0.06),
            borderRadius: BorderRadius.circular(look.tk.radiusSm),
          ),
          child: Row(
            mainAxisSize: .min,
            children: [
              AppIcon(icon, size: style.fontSize! * 1.2, color: look.ink(0.9)),
              SizedBox(width: 6 * look.scale),
              Flexible(
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ the game

  /// A line under the score saying where the match stands.
  String _state(SportMatch match, DateTime now) {
    if (match.isLive(now)) {
      final halftime = match.halftime;
      return halftime == null ? t.sport.live : '${t.sport.live} · ${t.sport.halftime} $halftime';
    }
    if (match.isFinished) {
      final halftime = match.halftime;
      return halftime == null ? t.sport.finalScore : '${t.sport.finalScore} · ${t.sport.halftime} $halftime';
    }
    return t.sport.notStarted;
  }

  Widget _club(SportLook look, SportTeam team, {bool short = false}) {
    final row = _rowFor(team);
    return Column(
      children: [
        SportCrest(team: team, size: look.crest * 2.4),
        SizedBox(height: look.gap * 0.7),
        Text(
          short ? team.shortName : team.name,
          textAlign: TextAlign.center,
          maxLines: 2,
          style: look.teamName(strong: true).copyWith(color: look.ink(1)),
        ),
        if (row != null) ...[
          SizedBox(height: look.gap / 3),
          Text(
            '${t.sport.place(n: row.position)} · ${row.points} ${t.sport.points}',
            textAlign: TextAlign.center,
            style: look.time.copyWith(color: look.ink(0.6)),
          ),
        ],
      ],
    );
  }

  /// One line per goal, on the side of the club it counted for, with the score
  /// it made between the two sides — the way a results page has always set it.
  List<Widget> _goals(SportLook look, SportMatch match) {
    final lines = <Widget>[];
    var before = const SportScore(0, 0);
    for (final goal in match.goals) {
      final home = goal.scoredByHome(before);
      before = goal.score;
      final minute = goal.minute == null ? '' : "${goal.minute}'";
      final notes = [if (goal.isOwnGoal) t.sport.ownGoal, if (goal.isPenalty) t.sport.penalty];
      final who = [
        goal.scorer ?? '',
        if (notes.isNotEmpty) '(${notes.join(', ')})',
      ].where((part) => part.isNotEmpty).join(' ');
      final text = home ? '$who  $minute' : '$minute  $who';
      final style = look.body.copyWith(color: look.ink(0.9));
      lines.add(
        Padding(
          padding: EdgeInsets.symmetric(vertical: 3 * look.scale),
          child: Row(
            children: [
              Expanded(
                child: home ? Text(text.trim(), textAlign: TextAlign.end, style: style) : const SizedBox.shrink(),
              ),
              SizedBox(
                width: (look.ocker ? 120 : 88) * look.scale,
                child: Text(
                  '${goal.score.home} : ${goal.score.away}',
                  textAlign: TextAlign.center,
                  style: look.score(strong: false).copyWith(color: look.ink(0.72)),
                ),
              ),
              Expanded(child: home ? const SizedBox.shrink() : Text(text.trim(), style: style)),
            ],
          ),
        ),
      );
    }
    return lines;
  }

  String? _venue(SportMatch match) {
    final parts = [
      ?match.stadium,
      ?match.city,
      if (match.spectators case final int spectators)
        t.sport.spectators(
          n: NumberFormat.decimalPattern(LocaleSettings.currentLocale.intlLocaleName).format(spectators),
        ),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}
