import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../media/media_item.dart';
import '../../redesign/ocker_skin.dart';
import '../../redesign/ocker_type.dart';
import '../../services/sport/sport_models.dart';
import '../../services/sport/sport_repository.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/app_logger.dart';
import '../sport/sport_broadcast_finder.dart';
import '../sport/sport_league_view.dart' show SportCrest;
import 'live_now_loader.dart';
import 'live_now_tile.dart';

/// The table around a game: both clubs with the club above and below each, in
/// table order. Clubs close together share their rows.
List<SportTableRow> liveNowTableExcerpt(List<SportTableRow> table, SportMatch match) {
  final wanted = <int>{};
  for (var i = 0; i < table.length; i++) {
    final id = table[i].team.id;
    if (id == match.home.id || id == match.away.id) wanted.addAll([i - 1, i, i + 1]);
  }
  return [
    for (var i = 0; i < table.length; i++)
      if (wanted.contains(i)) table[i],
  ];
}

/// Where a game is played, without the city twice: most stadiums in the
/// provider's data carry it in their name already.
String? liveNowGameVenue(SportMatch match) {
  final stadium = match.stadium?.trim();
  final city = match.city?.trim();
  if (stadium == null || stadium.isEmpty) return city == null || city.isEmpty ? null : city;
  if (city == null || city.isEmpty || stadium.contains(city)) return stadium;
  return '$stadium, $city';
}

/// A home screen stays open for hours; what is said about a game does not
/// stay right as long.
const _staleAfter = Duration(minutes: 5);

/// "Glas – v2" (Plebz): the line under a game's league in the spotlight: the
/// channel the guide has it on and where it is played. It always takes its
/// line, so the title above does not jump when the guide answers.
class LiveNowGameLine extends StatefulWidget {
  const LiveNowGameLine({super.key, required this.item, this.channelOf});

  final MediaItem? item;

  /// The channel a game is on; the viewer's guide when not given.
  final Future<String?> Function(LiveNowGame game)? channelOf;

  @visibleForTesting
  static void debugForget() => _LiveNowGameLineState._channels.clear();

  @override
  State<LiveNowGameLine> createState() => _LiveNowGameLineState();
}

class _LiveNowGameLineState extends State<LiveNowGameLine> {
  /// The guide is asked across every server and source; a slow one must not
  /// hold back what is already known.
  static const _guideWait = Duration(seconds: 3);

  /// Kept beyond this widget, which the spotlight rebuilds for every item.
  static final _channels = <int, ({DateTime at, String? channel})>{};
  static final _asking = <int>{};

  bool _needsAsking(LiveNowGame game) {
    if (_asking.contains(game.match.id)) return false;
    final known = _channels[game.match.id];
    return known == null || clock.now().difference(known.at) > _staleAfter;
  }

  Future<void> _load(LiveNowGame game) async {
    final id = game.match.id;
    _asking.add(id);
    final channel = await _channel(game);
    _asking.remove(id);
    _channels[id] = (at: clock.now(), channel: channel);
    if (mounted) setState(() {});
  }

  Future<String?> _channel(LiveNowGame game) async {
    try {
      final asked = widget.channelOf?.call(game) ?? _channelFromGuide(game);
      return await asked.timeout(_guideWait);
    } catch (error) {
      appLogger.d('Live now: no channel for a game', error: error);
      return null;
    }
  }

  Future<String?> _channelFromGuide(LiveNowGame game) async {
    final found = await SportBroadcastFinder.maybeOf(context)?.search(game.match, game.league);
    return found?.broadcasts.firstOrNull?.channel.displayName;
  }

  @override
  Widget build(BuildContext context) {
    final game = liveNowGameOf(context, widget.item);
    if (game == null) return const SizedBox.shrink();
    if (_needsAsking(game)) {
      // After the frame: the guide's providers are not read during a build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _needsAsking(game)) unawaited(_load(game));
      });
    }
    final parts = [_channels[game.match.id]?.channel, liveNowGameVenue(game.match)].nonNulls;
    return Padding(
      padding: EdgeInsets.only(top: 8 * ockerScale(context)),
      child: Text(
        parts.isEmpty ? ' ' : parts.join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: OckerType.of(context).spotlightSynopsis.copyWith(color: tokens(context).ink(0.78)),
      ),
    );
  }
}

/// The game [item] stands for in the "Jetzt live" row, if it does.
LiveNowGame? liveNowGameOf(BuildContext context, MediaItem? item) {
  final entry = item == null ? null : LiveNowScope.entryOf(context, item.id);
  return entry is LiveNowGame ? entry : null;
}

/// "Glas – v2" (Plebz): what the spotlight's empty side says about a game,
/// which has no backdrop: the table around both clubs. Everything else — a
/// channel, a film, a cup tie — leaves it empty.
class LiveNowSpotlightFacts extends StatefulWidget {
  const LiveNowSpotlightFacts({super.key, required this.item, this.repository});

  final MediaItem? item;
  final SportRepository? repository;

  @override
  State<LiveNowSpotlightFacts> createState() => _LiveNowSpotlightFactsState();
}

class _LiveNowSpotlightFactsState extends State<LiveNowSpotlightFacts> {
  final _known = <int, ({DateTime at, List<SportTableRow> rows})>{};
  final _asking = <int>{};

  bool _needsAsking(LiveNowGame game) {
    if (!game.league.hasTable || _asking.contains(game.match.id)) return false;
    final known = _known[game.match.id];
    return known == null || clock.now().difference(known.at) > _staleAfter;
  }

  Future<void> _load(LiveNowGame game) async {
    final id = game.match.id;
    _asking.add(id);
    final rows = await _tableRows(game);
    _asking.remove(id);
    if (!mounted) return;
    setState(() => _known[id] = (at: clock.now(), rows: rows));
  }

  Future<List<SportTableRow>> _tableRows(LiveNowGame game) async {
    try {
      final repository = widget.repository ?? SportRepository.instance;
      final table = await repository.table(game.league, game.match.season);
      return table == null ? const [] : liveNowTableExcerpt(table, game.match);
    } catch (error) {
      appLogger.d('Live now: no table for a game', error: error);
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = liveNowGameOf(context, widget.item);
    if (game != null && _needsAsking(game)) unawaited(_load(game));
    final rows = game == null ? null : _known[game.match.id]?.rows;
    return AnimatedSwitcher(
      duration: ockerGlassMotion(const Duration(milliseconds: 220)),
      layoutBuilder: (current, previous) => Stack(alignment: Alignment.bottomRight, children: [...previous, ?current]),
      child: game == null || rows == null || rows.isEmpty
          ? const SizedBox.shrink(key: ValueKey('none'))
          : _GameTable(key: ValueKey(game.match.id), match: game.match, rows: rows),
    );
  }
}

class _GameTable extends StatelessWidget {
  const _GameTable({super.key, required this.match, required this.rows});

  final SportMatch match;
  final List<SportTableRow> rows;

  @override
  Widget build(BuildContext context) {
    final scale = ockerScale(context);
    return OckerGlass(
      borderRadius: BorderRadius.circular(artworkRadius(context)),
      scrimInset: 0,
      groundOpacity: ockerBandGroundOpacity,
      child: Padding(
        padding: EdgeInsets.all(16 * scale),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, row) in rows.indexed) ...[
              if (index > 0 && row.position != rows[index - 1].position + 1) const _Hairline(),
              _TableLine(row: row, playing: row.team.id == match.home.id || row.team.id == match.away.id),
            ],
          ],
        ),
      ),
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: 8 * ockerScale(context)),
    child: SizedBox(height: 1, child: ColoredBox(color: tokens(context).ink(0.10))),
  );
}

class _TableLine extends StatelessWidget {
  const _TableLine({required this.row, required this.playing});

  final SportTableRow row;

  /// One of the two clubs of the game, among their neighbours.
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final scale = ockerScale(context);
    final style = OckerType.of(context).body.copyWith(
      color: tk.ink(playing ? 1 : 0.62),
      fontWeight: playing ? FontWeight.w600 : FontWeight.w400,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: playing ? tk.accent.withValues(alpha: ockerV2ChosenWash) : null,
        borderRadius: BorderRadius.circular(tk.radiusSm),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 7 * scale),
        child: Row(
          children: [
            SizedBox(
              width: 38 * scale,
              child: Text('${row.position}', style: style),
            ),
            SportCrest(team: row.team, size: 28 * scale),
            SizedBox(width: 12 * scale),
            Expanded(
              child: Text(row.team.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
            ),
            SizedBox(width: 12 * scale),
            Text('${row.points}', style: style),
          ],
        ),
      ),
    );
  }
}
