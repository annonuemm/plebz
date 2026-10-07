import 'package:flutter/foundation.dart';

import '../../utils/external_ids.dart';

/// A film as the profile's tracker knows it (fork addition).
@immutable
class TrackedMovie {
  const TrackedMovie({required this.key, required this.ids, this.watchedAt});

  /// The tracker's own id, unique among its films.
  final String key;
  final ExternalIds ids;

  /// When it was last watched; null for a film the tracker only lists.
  final DateTime? watchedAt;

  bool get isWatched => watchedAt != null;

  Map<String, Object?> toJson() => {'key': key, 'ids': ids.toJson(), 'watchedAt': watchedAt?.toIso8601String()};

  static TrackedMovie? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final key = raw['key'];
    final ids = raw['ids'];
    if (key is! String || ids is! Map) return null;
    return TrackedMovie(
      key: key,
      ids: ExternalIds.fromJson(ids.cast<String, Object?>()),
      watchedAt: _date(raw['watchedAt']),
    );
  }
}

/// A series as the profile's tracker knows it: which episodes are watched,
/// season by season, in the tracker's numbering (fork addition).
@immutable
class TrackedShow {
  const TrackedShow({required this.key, required this.ids, this.watched = const {}, this.lastWatchedAt});

  final String key;
  final ExternalIds ids;

  /// Watched episode numbers by season number.
  final Map<int, Set<int>> watched;
  final DateTime? lastWatchedAt;

  bool hasWatched(int season, int episode) => watched[season]?.contains(episode) ?? false;

  int watchedIn(int season) => watched[season]?.length ?? 0;

  int get watchedCount => watched.values.fold(0, (sum, episodes) => sum + episodes.length);

  Map<String, Object?> toJson() => {
    'key': key,
    'ids': ids.toJson(),
    'watched': {for (final MapEntry(:key, :value) in watched.entries) '$key': (value.toList()..sort())},
    'lastWatchedAt': lastWatchedAt?.toIso8601String(),
  };

  static TrackedShow? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final key = raw['key'];
    final ids = raw['ids'];
    if (key is! String || ids is! Map) return null;
    final watched = <int, Set<int>>{};
    if (raw['watched'] case final Map seasons) {
      for (final MapEntry(:key, :value) in seasons.entries) {
        final season = int.tryParse('$key');
        if (season == null || value is! List) continue;
        watched[season] = {for (final episode in value) ?(episode is num ? episode.toInt() : null)};
      }
    }
    return TrackedShow(
      key: key,
      ids: ExternalIds.fromJson(ids.cast<String, Object?>()),
      watched: watched,
      lastWatchedAt: _date(raw['lastWatchedAt']),
    );
  }
}

/// Where playback of a film or an episode was left, as the tracker keeps it
/// (fork addition). A share of the runtime, not a time: the tracker does not
/// know which file was played, so the item's own duration places it.
@immutable
class TrackedPlayback {
  const TrackedPlayback({
    required this.key,
    required this.ids,
    required this.progress,
    required this.pausedAt,
    this.season,
    this.episode,
  });

  /// The tracker's id for this paused session, to forget it by.
  final String key;

  /// The film's ids, or the series' for an episode.
  final ExternalIds ids;

  /// 0–100.
  final double progress;
  final DateTime pausedAt;
  final int? season;
  final int? episode;

  bool get isEpisode => season != null && episode != null;

  /// The resume position in [duration].
  Duration positionIn(Duration duration) =>
      Duration(milliseconds: (duration.inMilliseconds * progress.clamp(0, 100) / 100).round());

  Map<String, Object?> toJson() => {
    'key': key,
    'ids': ids.toJson(),
    'progress': progress,
    'pausedAt': pausedAt.toIso8601String(),
    'season': season,
    'episode': episode,
  };

  static TrackedPlayback? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final key = raw['key'];
    final ids = raw['ids'];
    final progress = raw['progress'];
    final pausedAt = _date(raw['pausedAt']);
    if (key is! String || ids is! Map || progress is! num || pausedAt == null) return null;
    return TrackedPlayback(
      key: key,
      ids: ExternalIds.fromJson(ids.cast<String, Object?>()),
      progress: progress.toDouble(),
      pausedAt: pausedAt,
      season: (raw['season'] as num?)?.toInt(),
      episode: (raw['episode'] as num?)?.toInt(),
    );
  }
}

/// Everything a profile's tracker says about what it watched (fork addition).
///
/// Tracker-neutral: Simkl fills it today, and another tracker would fill the
/// same shape. Looked up by the ids a media server knows a title by — IMDb,
/// TMDB, TVDB — since the tracker never sees the server's own ids.
class TrackerWatchState {
  TrackerWatchState({
    List<TrackedMovie> movies = const [],
    List<TrackedShow> shows = const [],
    List<TrackedPlayback> playback = const [],
    Map<String, String> syncMarks = const {},
  }) : syncMarks = Map.unmodifiable(syncMarks),
       movies = List.unmodifiable(movies),
       shows = List.unmodifiable(shows),
       playback = List.unmodifiable(playback) {
    for (final movie in movies) {
      for (final id in _idKeys(movie.ids)) {
        _movieById[id] ??= movie;
      }
    }
    for (final show in shows) {
      for (final id in _idKeys(show.ids)) {
        _showById[id] ??= show;
      }
    }
    for (final entry in playback) {
      for (final id in _idKeys(entry.ids)) {
        final slot = entry.isEpisode ? '$id|${entry.season}|${entry.episode}' : id;
        final kept = _playbackById[slot];
        // The latest pause wins when a session was left twice.
        if (kept == null || entry.pausedAt.isAfter(kept.pausedAt)) _playbackById[slot] = entry;
      }
    }
  }

  static final TrackerWatchState empty = TrackerWatchState();

  final List<TrackedMovie> movies;
  final List<TrackedShow> shows;
  final List<TrackedPlayback> playback;

  /// The tracker's own markers of the state this reflects — when what last
  /// changed, per kind — to ask for what changed since; empty before the
  /// first sync.
  final Map<String, String> syncMarks;

  final Map<String, TrackedMovie> _movieById = {};
  final Map<String, TrackedShow> _showById = {};
  final Map<String, TrackedPlayback> _playbackById = {};

  static List<String> _idKeys(ExternalIds ids) => [
    if (ids.imdb case final imdb? when imdb.isNotEmpty) 'imdb:$imdb',
    if (ids.tmdb case final tmdb? when tmdb > 0) 'tmdb:$tmdb',
    if (ids.tvdb case final tvdb? when tvdb > 0) 'tvdb:$tvdb',
  ];

  static T? _first<T>(Map<String, T> index, List<String> keys) {
    for (final key in keys) {
      if (index[key] case final found?) return found;
    }
    return null;
  }

  TrackedMovie? movie(ExternalIds ids) => _first(_movieById, _idKeys(ids));

  TrackedShow? show(ExternalIds ids) => _first(_showById, _idKeys(ids));

  TrackedPlayback? moviePlayback(ExternalIds ids) => _first(_playbackById, _idKeys(ids));

  TrackedPlayback? episodePlayback(ExternalIds showIds, int season, int episode) =>
      _first(_playbackById, [for (final id in _idKeys(showIds)) '$id|$season|$episode']);

  /// The same state, but asked for whole at the next sync: without the marks
  /// a tracker answers everything rather than what changed since.
  TrackerWatchState withoutSyncMarks() => TrackerWatchState(movies: movies, shows: shows, playback: playback);

  Map<String, Object?> toJson() => {
    'syncMarks': syncMarks,
    'movies': [for (final movie in movies) movie.toJson()],
    'shows': [for (final show in shows) show.toJson()],
    'playback': [for (final entry in playback) entry.toJson()],
  };

  factory TrackerWatchState.fromJson(Map<String, Object?> json) => TrackerWatchState(
    syncMarks: {
      if (json['syncMarks'] case final Map marks)
        for (final MapEntry(:key, :value) in marks.entries)
          if (key is String && value is String) key: value,
    },
    movies: [for (final raw in _list(json['movies'])) ?TrackedMovie.fromJson(raw)],
    shows: [for (final raw in _list(json['shows'])) ?TrackedShow.fromJson(raw)],
    playback: [for (final raw in _list(json['playback'])) ?TrackedPlayback.fromJson(raw)],
  );

  static List<Object?> _list(Object? value) => value is List ? value : const [];
}

DateTime? _date(Object? value) => value is String ? DateTime.tryParse(value) : null;
