import '../../utils/external_ids.dart';
import 'tracker_watch_state.dart';

/// Reads Simkl's sync answers into a [TrackerWatchState] (fork addition).
///
/// [allItems] is `GET /sync/all-items` with `extended=full`,
/// `episode_watched_at=yes` and `include_all_episodes=yes`; [playback] is
/// `GET /sync/playback`. Anime counts as series: Simkl lists it apart, but a
/// media server keeps it among its shows.
TrackerWatchState parseSimklWatchState({
  required Object? allItems,
  required Object? playback,
  Map<String, String> syncMarks = const {},
}) {
  final items = allItems is Map ? allItems : const {};
  return TrackerWatchState(
    syncMarks: syncMarks,
    movies: [for (final entry in _list(items['movies'])) ?_movie(entry)],
    shows: [
      for (final entry in _list(items['shows'])) ?_show(entry),
      for (final entry in _list(items['anime'])) ?_show(entry),
    ],
    playback: [for (final entry in _list(playback)) ?_playback(entry)],
  );
}

/// [previous] with what changed since its [TrackerWatchState.syncMarks]:
/// every title in [changedItems] replaces its earlier entry whole, as Simkl
/// sends changed titles whole. [playback], when given, replaces the paused
/// sessions; they are few, and fetched whole every time.
TrackerWatchState mergeSimklChanges(
  TrackerWatchState previous, {
  required Object? changedItems,
  Object? playback,
  Map<String, String>? syncMarks,
}) {
  final changes = parseSimklWatchState(allItems: changedItems, playback: playback ?? const []);
  final movies = {for (final movie in previous.movies) movie.key: movie};
  for (final movie in changes.movies) {
    movies[movie.key] = movie;
  }
  final shows = {for (final show in previous.shows) show.key: show};
  for (final show in changes.shows) {
    shows[show.key] = show;
  }
  return TrackerWatchState(
    syncMarks: syncMarks ?? previous.syncMarks,
    movies: movies.values.toList(),
    shows: shows.values.toList(),
    playback: playback == null ? previous.playback : changes.playback,
  );
}

TrackedMovie? _movie(Object? entry) {
  if (entry is! Map) return null;
  final movie = entry['movie'];
  if (movie is! Map) return null;
  final ids = _ids(movie['ids']);
  final key = _key(movie['ids'], ids);
  if (key == null) return null;
  final status = entry['status'];
  final watchedAt = _date(entry['last_watched_at']) ?? _date(entry['watched_at']);
  // A film on the watchlist or dropped is listed, not watched.
  final watched = status == 'completed' || (status == null && watchedAt != null);
  return TrackedMovie(key: key, ids: ids, watchedAt: watched ? (watchedAt ?? DateTime.utc(1970)) : null);
}

TrackedShow? _show(Object? entry) {
  if (entry is! Map) return null;
  final show = entry['show'];
  if (show is! Map) return null;
  final ids = _ids(show['ids']);
  final key = _key(show['ids'], ids);
  if (key == null) return null;
  final watched = <int, Set<int>>{};
  for (final season in _list(entry['seasons'])) {
    if (season is! Map) continue;
    final number = _int(season['number']);
    if (number == null) continue;
    for (final episode in _list(season['episodes'])) {
      if (episode is! Map) continue;
      // Anime asked for in TVDB's numbering carries it per episode; that is
      // the numbering a media server orders its anime by.
      final (inSeason, episodeNumber) = _tvdbNumbers(episode) ?? (number, _int(episode['number']));
      if (episodeNumber != null) (watched[inSeason] ??= {}).add(episodeNumber);
    }
  }
  return TrackedShow(
    key: key,
    ids: ids,
    watched: watched,
    lastWatchedAt: _date(entry['last_watched_at']) ?? _date(entry['last_watched']),
  );
}

TrackedPlayback? _playback(Object? entry) {
  if (entry is! Map) return null;
  final id = entry['id'];
  final progress = entry['progress'];
  final pausedAt = _date(entry['paused_at']);
  if (id == null || progress is! num || pausedAt == null) return null;
  if (entry['type'] == 'movie') {
    final movie = entry['movie'];
    if (movie is! Map) return null;
    return TrackedPlayback(key: '$id', ids: _ids(movie['ids']), progress: progress.toDouble(), pausedAt: pausedAt);
  }
  final show = entry['show'] ?? entry['anime'];
  final episode = entry['episode'];
  if (show is! Map || episode is! Map) return null;
  final (season, number) =
      _tvdbNumbers(episode) ?? (_int(episode['season']) ?? 1, _int(episode['number'] ?? episode['episode']));
  if (number == null) return null;
  return TrackedPlayback(
    key: '$id',
    ids: _ids(show['ids']),
    progress: progress.toDouble(),
    pausedAt: pausedAt,
    season: season,
    episode: number,
  );
}

/// An anime episode's TVDB season and number, when Simkl gave them.
(int, int)? _tvdbNumbers(Map episode) {
  final tvdb = episode['tvdb'];
  if (tvdb is! Map) return null;
  final season = _int(tvdb['season']);
  final number = _int(tvdb['episode'] ?? tvdb['number']);
  return season == null || number == null ? null : (season, number);
}

ExternalIds _ids(Object? raw) {
  if (raw is! Map) return const ExternalIds();
  final imdb = raw['imdb'];
  return ExternalIds(
    imdb: imdb is String && imdb.isNotEmpty ? imdb : null,
    tmdb: _positive(raw['tmdb']),
    tvdb: _positive(raw['tvdb']),
  );
}

/// Simkl's own id, else the external ones: a title Simkl names no way at all
/// cannot be looked up and is left out.
String? _key(Object? raw, ExternalIds ids) {
  final simkl = raw is Map ? _positive(raw['simkl'] ?? raw['simkl_id']) : null;
  if (simkl != null) return 'simkl:$simkl';
  if (!ids.hasCatalogIds) return null;
  return 'ids:${ids.imdb}|${ids.tmdb}|${ids.tvdb}';
}

int? _int(Object? value) => switch (value) {
  final num number => number.toInt(),
  final String text => int.tryParse(text),
  _ => null,
};

int? _positive(Object? value) {
  final number = _int(value);
  return number != null && number > 0 ? number : null;
}

DateTime? _date(Object? value) => value is String ? DateTime.tryParse(value) : null;

List<Object?> _list(Object? value) => value is List ? value : const [];
