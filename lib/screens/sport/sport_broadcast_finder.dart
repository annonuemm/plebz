import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../models/live_tv_channel_layout.dart';
import '../../models/livetv_channel.dart';
import '../../models/livetv_program.dart';
import '../../providers/iptv_sources_provider.dart';
import '../../providers/live_tv_channel_layout_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../services/sport/sport_broadcast_matching.dart';
import '../../services/sport/sport_models.dart';
import '../../utils/app_logger.dart';
import '../livetv/live_tv_server_iteration.dart';

/// What the guide says about where a fixture can be watched.
class SportBroadcastSearch {
  /// Programmes that name the game, then Konferenzen of its league.
  final List<SportBroadcast> broadcasts;

  /// The viewer's own channels for the league, for when [broadcasts] is
  /// empty. Empty whenever [broadcasts] is not.
  final List<SportBroadcast> leagueChannels;

  /// Every channel, in the viewer's arrangement: the list the player zaps
  /// through once one of them is tuned.
  final List<LiveTvChannel> channels;

  const SportBroadcastSearch({required this.broadcasts, required this.leagueChannels, required this.channels});

  bool get isEmpty => broadcasts.isEmpty && leagueChannels.isEmpty;
}

/// Looks a fixture up in the viewer's own guide: every media server with
/// Live TV and every IPTV source, the channels as Live TV shows them — the
/// DVR's switched-off channels and the ones hidden under "Sender verwalten"
/// left out, in the viewer's order.
///
/// Asks for a few hours around kickoff only, and keeps the channel list for
/// a few minutes, so opening one game after another does not reload the
/// playlist each time.
class SportBroadcastFinder {
  SportBroadcastFinder({required this.multiServer, this.iptv, this.layout});

  /// The providers under [context], or null where there is no Live TV to
  /// ask at all — no server list in scope (a test host).
  static SportBroadcastFinder? maybeOf(BuildContext context) {
    final multiServer = context.read<MultiServerProvider?>();
    if (multiServer == null) return null;
    return SportBroadcastFinder(
      multiServer: multiServer,
      iptv: context.read<IptvSourcesProvider?>(),
      layout: context.read<LiveTvChannelLayoutProvider?>(),
    );
  }

  final MultiServerProvider multiServer;
  final IptvSourcesProvider? iptv;
  final LiveTvChannelLayoutProvider? layout;

  /// How far from now a game is still looked for: a week back is as deep as
  /// an archive usually reaches, a week ahead as far as a guide does.
  static const searchReach = Duration(days: 7);

  static const _channelsTtl = Duration(minutes: 5);
  static const _leagueChannelLead = Duration(hours: 2);
  static const _leagueChannelTail = Duration(hours: 2, minutes: 15);

  List<LiveTvChannel>? _channels;
  DateTime? _channelsAt;

  /// Whether the guide can have anything to say about [match] — false for a
  /// game further off than [searchReach], where it cannot. Such a game is not
  /// looked up, and [search] answers for it that nothing was found.
  static bool worthSearching(SportMatch match, {DateTime? now}) {
    final at = now ?? clock.now();
    return match.kickoff.isAfter(at.subtract(searchReach)) && match.kickoff.isBefore(at.add(searchReach));
  }

  /// Null when the viewer has no Live TV at all — nothing to search, and
  /// nothing to say about it either. A game beyond [searchReach] is not in
  /// any guide, so it finds nothing without asking one.
  Future<SportBroadcastSearch?> search(SportMatch match, SportLeague league) async {
    await iptv?.ensureLoaded();
    final sources = iptv?.liveTvSources ?? const [];
    if (multiServer.liveTvServers.isEmpty && sources.isEmpty) return null;
    if (!worthSearching(match)) {
      return const SportBroadcastSearch(broadcasts: [], leagueChannels: [], channels: []);
    }

    final channels = await _loadChannels();
    if (channels.isEmpty) return null;

    final kickoff = match.kickoff.toUtc();
    final from = kickoff.subtract(const Duration(minutes: 30));
    final to = kickoff.add(const Duration(hours: 3));
    final programs = <LiveTvProgram>[];
    await forEachLiveTvServer(
      multiServer,
      resolveClient: multiServer.getClientForServer,
      body: (client, _) async => programs.addAll(await client.liveTv.fetchSchedule(from: from, to: to)),
      onError: (_, serverInfo, error, _) =>
          appLogger.d('Sport: no guide from server ${serverInfo.serverId}', error: error),
    );
    for (final source in sources) {
      try {
        programs.addAll(await source.fetchSchedule(from: from, to: to));
      } catch (error) {
        appLogger.d('Sport: no guide from an IPTV source', error: error);
      }
    }

    final broadcasts = findSportBroadcasts(match: match, league: league, channels: channels, programs: programs);
    // The league's channels are a guess at where the game is, worth making
    // only while it is on or about to be; for a game long over or days away
    // they would just be a list of channels.
    final now = clock.now();
    final guessWorthMaking =
        now.isAfter(match.kickoff.subtract(_leagueChannelLead)) && now.isBefore(match.kickoff.add(_leagueChannelTail));
    final leagueChannels = broadcasts.isNotEmpty || !guessWorthMaking
        ? const <SportBroadcast>[]
        : sportLeagueChannels(match: match, league: league, channels: channels, programs: programs);
    appLogger.d(
      'Sport: ${match.home.shortName}–${match.away.shortName}: ${programs.length} programmes around kickoff, '
      '${broadcasts.length} broadcasts, ${leagueChannels.length} league channels',
    );
    return SportBroadcastSearch(broadcasts: broadcasts, leagueChannels: leagueChannels, channels: channels);
  }

  /// The channels as the Live TV screen assembles them.
  Future<List<LiveTvChannel>> _loadChannels() async {
    final kept = _channels;
    final keptAt = _channelsAt;
    if (kept != null && keptAt != null && clock.now().difference(keptAt) < _channelsTtl) return kept;

    await layout?.ensureLoaded();
    final all = <LiveTvChannel>[];
    final seen = <String>{};
    await forEachLiveTvServer(
      multiServer,
      resolveClient: multiServer.getClientForServer,
      // One entry per DVR, and each has its own lineup.
      dedupeByServerId: false,
      body: (client, serverInfo) async {
        final enabled = liveTvEnabledChannelKeys(serverInfo);
        final source = await client.liveTv.buildFavoriteChannelSource(lineup: serverInfo.lineup);
        for (final channel in await client.liveTv.fetchChannels(lineup: serverInfo.lineup)) {
          if (enabled != null && !enabled.contains(channel.key)) continue;
          // Scoped to its DVR the way Live TV scopes it: the player finds the
          // server to tune on through it, the guide matches on it.
          final scoped = channel.copyWith(liveDvrKey: serverInfo.dvrKey, favoriteSource: source);
          if (seen.add(liveTvChannelScopeKey(scoped))) all.add(scoped);
        }
      },
      onError: (_, serverInfo, error, _) =>
          appLogger.d('Sport: no channels from server ${serverInfo.serverId}', error: error),
    );
    for (final source in iptv?.liveTvSources ?? const []) {
      try {
        for (final channel in await source.fetchChannels()) {
          if (seen.add(liveTvChannelScopeKey(channel))) all.add(channel);
        }
      } catch (error) {
        appLogger.d('Sport: no channels from an IPTV source', error: error);
      }
    }
    all.sort((a, b) {
      final aNumber = double.tryParse(a.number ?? '') ?? 999999;
      final bNumber = double.tryParse(b.number ?? '') ?? 999999;
      return aNumber.compareTo(bNumber);
    });
    final arranged = applyLiveTvChannelLayout(all, layout?.layout ?? LiveTvChannelLayout.empty);
    _channels = arranged;
    _channelsAt = clock.now();
    return arranged;
  }
}
