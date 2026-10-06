import '../../utils/app_logger.dart';
import '../trackers/simkl/simkl_client.dart';
import 'simkl_watch_state_parser.dart';
import 'tracker_watch_state.dart';

/// Brings a profile's [TrackerWatchState] up to date with its Simkl account
/// (fork addition), the way Simkl asks apps to sync:
///
/// - `/sync/activities` first. Nothing has changed when its `all` stamp is
///   the one kept, and that is the whole cost of a quiet check.
/// - Otherwise only what changed since that stamp, merged into the state.
/// - Everything again on the first sync, or when titles were taken off a
///   list: a change list cannot say what is gone.
/// - The paused sessions again whenever their stamp moved.
class SimklWatchSync {
  SimklWatchSync(this.client);

  final SimklClient client;

  static const _all = 'all';
  static const _removed = 'removed';
  static const _playback = 'playback';
  static const _kinds = ['movies', 'tv_shows', 'anime'];

  Future<TrackerWatchState> refresh(TrackerWatchState current) async {
    final marks = _marksOf(await client.getActivities());
    final kept = current.syncMarks;
    if (kept.isNotEmpty && kept[_all] == marks[_all]) return current;

    final everything = kept.isEmpty || kept[_removed] != marks[_removed];
    final playbackMoved = everything || kept[_playback] != marks[_playback];
    final playback = playbackMoved ? await client.getPlayback() : null;

    if (everything) {
      return parseSimklWatchState(
        allItems: await _withAnimeInTvdbNumbers(await client.getWatchedItems()),
        playback: playback ?? const [],
        syncMarks: marks,
      );
    }
    return mergeSimklChanges(
      current,
      changedItems: await _withAnimeInTvdbNumbers(
        await client.getWatchedItems(dateFrom: kept[_all]),
        dateFrom: kept[_all],
      ),
      playback: playback,
      syncMarks: marks,
    );
  }

  /// [items] with its anime asked again in TVDB's numbering, which a media
  /// server's anime library is ordered by: Simkl numbers anime its own way.
  /// Where that second answer cannot be had, [items] stays as it was.
  Future<Object?> _withAnimeInTvdbNumbers(Object? items, {String? dateFrom}) async {
    if (items is! Map || items['anime'] is! List || (items['anime'] as List).isEmpty) return items;
    try {
      final anime = await client.getWatchedItems(dateFrom: dateFrom, type: 'anime', extended: 'full_anime_seasons');
      if (anime is! Map || anime['anime'] is! List) return items;
      // Entry by entry, and only where the answer brought episodes: an anime
      // left without them here would read as never watched.
      final inTvdb = {
        for (final entry in anime['anime'] as List)
          if (_simklIdOf(entry) case final id? when _hasEpisodes(entry)) id: entry,
      };
      return {
        ...items,
        'anime': [for (final entry in items['anime'] as List) inTvdb[_simklIdOf(entry)] ?? entry],
      };
    } catch (error) {
      appLogger.d('Simkl: anime in TVDB numbering unavailable, keeping Simkl\'s own', error: error);
    }
    return items;
  }

  static Object? _simklIdOf(Object? entry) {
    final show = entry is Map ? entry['show'] : null;
    final ids = show is Map ? show['ids'] : null;
    return ids is Map ? ids['simkl'] : null;
  }

  static bool _hasEpisodes(Object? entry) =>
      entry is Map &&
      entry['seasons'] is List &&
      (entry['seasons'] as List).any(
        (season) => season is Map && season['episodes'] is List && (season['episodes'] as List).isNotEmpty,
      );

  static Map<String, String> _marksOf(Object? activities) {
    final map = activities is Map ? activities : const {};
    String stampsOf(String field) => [
      for (final kind in _kinds)
        if (map[kind] case final Map block) '${block[field] ?? ''}' else '',
    ].join('|');
    return {_all: '${map[_all] ?? ''}', _removed: stampsOf('removed_from_list'), _playback: stampsOf('playback')};
  }
}
