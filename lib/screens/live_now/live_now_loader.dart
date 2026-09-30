import 'package:clock/clock.dart';
import 'package:collection/collection.dart';

import '../../models/livetv_channel.dart';
import '../../models/livetv_program.dart';
import '../../providers/iptv_sources_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../services/sport/sport_models.dart';
import '../../services/sport/sport_repository.dart';
import '../../utils/app_logger.dart';
import '../../utils/live_tv_matching.dart';
import '../livetv/live_tv_server_iteration.dart';
import '../sport/sport_broadcast_finder.dart';

/// One tile of the home screen's "Jetzt live" row.
sealed class LiveNowEntry {
  const LiveNowEntry();

  /// Stable across refreshes, so a row keeps its place and its focus.
  String get id;
}

/// A game of the Sport leagues: on now, or still to come today.
final class LiveNowGame extends LiveNowEntry {
  const LiveNowGame({required this.match, required this.league});

  final SportMatch match;
  final SportLeague league;

  @override
  String get id => 'live_now:game:${league.shortcut}:${match.id}';
}

/// One of the viewer's favourite channels, with what is on it now.
final class LiveNowChannel extends LiveNowEntry {
  const LiveNowChannel({required this.channel, this.program});

  final LiveTvChannel channel;
  final LiveTvProgram? program;

  @override
  String get id => 'live_now:channel:${liveTvChannelScopeKey(channel)}';
}

/// What the row shows, and the channel list a tuned channel zaps through.
class LiveNowSnapshot {
  LiveNowSnapshot({this.entries = const [], this.channels = const []})
    : byId = {for (final entry in entries) entry.id: entry};

  final List<LiveNowEntry> entries;

  /// Every channel in the viewer's arrangement — the list the player gets.
  final List<LiveTvChannel> channels;

  /// [entries] by [LiveNowEntry.id], for the tiles to find theirs.
  final Map<String, LiveNowEntry> byId;

  static final empty = LiveNowSnapshot();

  bool get isEmpty => entries.isEmpty;
}

/// The games worth a tile, best first: those on now, then those still to come
/// today; within each, the higher league first ([SportLeague]'s own order is
/// the tier), then the earlier kickoff. Finished games and games of other
/// days are left out.
List<LiveNowGame> liveNowGames(Map<SportLeague, List<SportMatch>> byLeague, DateTime now) {
  final live = <LiveNowGame>[];
  final later = <LiveNowGame>[];
  final local = now.toLocal();
  bool today(DateTime at) {
    final day = at.toLocal();
    return day.year == local.year && day.month == local.month && day.day == local.day;
  }

  for (final league in SportLeague.values) {
    for (final match in byLeague[league] ?? const <SportMatch>[]) {
      if (match.isLive(now)) {
        live.add(LiveNowGame(match: match, league: league));
      } else if (!match.isFinished && match.kickoff.isAfter(now) && today(match.kickoff)) {
        later.add(LiveNowGame(match: match, league: league));
      }
    }
  }
  int byTierThenKickoff(LiveNowGame a, LiveNowGame b) {
    final tier = a.league.index.compareTo(b.league.index);
    return tier != 0 ? tier : a.match.kickoff.compareTo(b.match.kickoff);
  }

  return [...live..sort(byTierThenKickoff), ...later..sort(byTierThenKickoff)];
}

/// The favourites that are channels here, in the order the viewer keeps them,
/// each with what [programs] has on it at [now]. A favourite whose channel is
/// hidden or gone is left out. At most [limit].
List<LiveNowChannel> liveNowFavorites(
  List<LiveTvChannel> channels,
  List<FavoriteChannel> favorites,
  List<LiveTvProgram> programs,
  DateTime now, {
  int limit = 20,
}) {
  final byKey = {
    for (final channel in channels) favoriteChannelKey(channel.favoriteSource ?? '', channel.key): channel,
  };
  final seconds = now.millisecondsSinceEpoch ~/ 1000;
  final result = <LiveNowChannel>[];
  for (final favorite in favorites) {
    final channel = byKey[favorite.stableKey];
    if (channel == null) continue;
    final program = programs.firstWhereOrNull(
      (program) =>
          liveTvProgramMatchesChannel(program, channel) &&
          (program.beginsAt ?? seconds + 1) <= seconds &&
          seconds < (program.endsAt ?? 0),
    );
    result.add(LiveNowChannel(channel: channel, program: program));
    if (result.length == limit) break;
  }
  return result;
}

/// Gathers the "Jetzt live" row: the Sport games of today, then the viewer's
/// favourite channels with what is on them.
///
/// Every source answers from its own cache where it has one — the Sport
/// repository keeps a live matchday for a minute, the channel list is the one
/// Sport's guide search keeps — and the favourites and the guide are asked at
/// most every few minutes, or sooner once a programme on a tile has ended.
class LiveNowLoader {
  LiveNowLoader({
    required this.multiServer,
    required this.finder,
    this.iptv,
    SportRepository? sport,
    required this.sportEnabled,
  }) : sport = sport ?? SportRepository.instance;

  final MultiServerProvider multiServer;
  final SportBroadcastFinder finder;
  final IptvSourcesProvider? iptv;
  final SportRepository sport;

  /// Whether the Sport tab is switched on; asked on every load, so switching
  /// it off takes the games out at the next refresh.
  final bool Function() sportEnabled;

  static const _favoritesTtl = Duration(minutes: 5);
  static const _guideTtl = Duration(minutes: 5);

  List<FavoriteChannel>? _favorites;
  DateTime? _favoritesAt;
  List<LiveTvProgram>? _programs;
  DateTime? _programsAt;
  DateTime? _programsStaleAt;

  Future<LiveNowSnapshot> load() async {
    final now = clock.now();
    final games = sportEnabled() ? liveNowGames(await _games(), now) : const <LiveNowGame>[];

    await iptv?.ensureLoaded();
    final hasLiveTv = multiServer.liveTvServers.isNotEmpty || (iptv?.liveTvSources.isNotEmpty ?? false);
    if (!hasLiveTv) return LiveNowSnapshot(entries: games);

    final channels = await finder.channels();
    final favorites = await _loadFavorites(now);
    final programs = favorites.isEmpty ? const <LiveTvProgram>[] : await _loadPrograms(now);
    return LiveNowSnapshot(
      entries: [...games, ...liveNowFavorites(channels, favorites, programs, now)],
      channels: channels,
    );
  }

  Future<Map<SportLeague, List<SportMatch>>> _games() async {
    final byLeague = <SportLeague, List<SportMatch>>{};
    for (final league in SportLeague.values) {
      try {
        final current = await sport.current(league);
        if (current != null) byLeague[league] = current.matches;
      } catch (error) {
        appLogger.d('Live now: no games for ${league.shortcut}', error: error);
      }
    }
    return byLeague;
  }

  Future<List<FavoriteChannel>> _loadFavorites(DateTime now) async {
    final kept = _favorites;
    final keptAt = _favoritesAt;
    if (kept != null && keptAt != null && now.difference(keptAt) < _favoritesTtl) return kept;

    final merged = <FavoriteChannel>[];
    final seen = <String>{};
    final stores = <String>{};
    await forEachLiveTvServer(
      multiServer,
      resolveClient: multiServer.getClientForServer,
      dedupeByServerId: false,
      body: (client, _) async {
        final liveTv = client.liveTv;
        if (!stores.add(liveTv.favoriteStoreKey)) return;
        for (final favorite in await liveTv.fetchFavoriteChannels()) {
          if (seen.add(favorite.stableKey)) merged.add(favorite);
        }
      },
      onError: (_, serverInfo, error, _) =>
          appLogger.d('Live now: no favourites from server ${serverInfo.serverId}', error: error),
    );
    for (final source in iptv?.liveTvSources ?? const []) {
      try {
        for (final favorite in await source.fetchFavoriteChannels()) {
          if (seen.add(favorite.stableKey)) merged.add(favorite);
        }
      } catch (error) {
        appLogger.d('Live now: no favourites from an IPTV source', error: error);
      }
    }
    _favorites = merged;
    _favoritesAt = now;
    return merged;
  }

  /// What is on now, across every guide. Asked again after [_guideTtl], or as
  /// soon as the first programme it found has ended.
  Future<List<LiveTvProgram>> _loadPrograms(DateTime now) async {
    final kept = _programs;
    final keptAt = _programsAt;
    final staleAt = _programsStaleAt;
    if (kept != null &&
        keptAt != null &&
        now.difference(keptAt) < _guideTtl &&
        (staleAt == null || now.isBefore(staleAt))) {
      return kept;
    }

    final from = now.subtract(const Duration(minutes: 1));
    final to = now.add(const Duration(minutes: 1));
    final programs = <LiveTvProgram>[];
    await forEachLiveTvServer(
      multiServer,
      resolveClient: multiServer.getClientForServer,
      body: (client, _) async => programs.addAll(await client.liveTv.fetchSchedule(from: from, to: to)),
      onError: (_, serverInfo, error, _) =>
          appLogger.d('Live now: no guide from server ${serverInfo.serverId}', error: error),
    );
    for (final source in iptv?.liveTvSources ?? const []) {
      try {
        programs.addAll(await source.fetchSchedule(from: from, to: to));
      } catch (error) {
        appLogger.d('Live now: no guide from an IPTV source', error: error);
      }
    }
    final ends = [
      for (final program in programs)
        if (program.endsAt case final end? when end * 1000 > now.millisecondsSinceEpoch) end,
    ];
    _programs = programs;
    _programsAt = now;
    _programsStaleAt = ends.isEmpty ? null : DateTime.fromMillisecondsSinceEpoch(ends.min * 1000);
    return programs;
  }
}
