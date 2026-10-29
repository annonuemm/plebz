import 'dart:async';
import 'dart:collection';

import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_server_client.dart';
import '../../utils/app_logger.dart';
import '../../utils/external_ids.dart';
import 'tracker_episode_list_client.dart';
import 'tracker_watch_state.dart';

/// A series' episodes on a server; see [TrackerContinueWatching.loadEpisodes].
typedef EpisodeLists = Future<List<MediaItem>> Function(MediaServerClient client, String showId);

/// Continue Watching for a tracker-led profile, from what its tracker says
/// (fork addition) — the server's own list belongs to whoever shares the
/// account.
///
/// Two kinds of entry, newest first:
/// - a film or an episode the tracker holds a paused session for;
/// - for each series watched lately, the next episode after the last one
///   seen, the way Plex's On Deck offers it.
///
/// Each is found on [client]'s server through its ids ([index]), and fetched
/// from there, so it carries the server's artwork and files and — through
/// the item mappers — the tracker's state.
///
/// Also the titles watched last ([recentlyWatched]), which the
/// recommendation row reasons from.
class TrackerContinueWatching {
  TrackerContinueWatching({required this.state, required this.index, EpisodeLists? episodesOf})
    : _episodesOf = episodesOf ?? loadEpisodes {
    for (final MapEntry(key: itemId, value: ids) in index.entries) {
      for (final key in _idKeys(ids)) {
        (_itemsById[key] ??= []).add(itemId);
      }
    }
  }

  final TrackerWatchState state;
  final Map<String, ExternalIds> index;
  final EpisodeLists _episodesOf;
  final Map<String, List<String>> _itemsById = {};

  /// How many series are looked at for a next episode: each costs a request.
  static const int seriesLimit = 20;

  /// How many requests run at once. One after another, twenty series' lists
  /// held the home page for a minute on a big server.
  static const int parallelLookups = 4;

  /// How many titles [recentlyWatched] names at most.
  static const int recentLimit = 30;

  static List<String> _idKeys(ExternalIds ids) => [
    if (ids.imdb case final imdb? when imdb.isNotEmpty) 'imdb:$imdb',
    if (ids.tmdb case final tmdb?) 'tmdb:$tmdb',
    if (ids.tvdb case final tvdb?) 'tvdb:$tvdb',
  ];

  /// The server's items known by [ids], most-named first.
  List<String> _itemsFor(ExternalIds ids) {
    final found = <String>[];
    for (final key in _idKeys(ids)) {
      for (final itemId in _itemsById[key] ?? const <String>[]) {
        if (!found.contains(itemId)) found.add(itemId);
      }
    }
    return found;
  }

  Future<List<MediaItem>> fetch(
    MediaServerClient client, {
    int? count,
    Set<String> excludedLibraryIds = const {},
  }) async {
    final limit = count ?? 20;
    final rows = <MediaItem>[];
    final seriesDone = <String>{};
    final gate = _Gate(parallelLookups);
    final episodesOf = <String, Future<List<MediaItem>>>{};
    Future<List<MediaItem>> episodes(String showId) =>
        episodesOf[showId] ??= gate.run(() => _episodesOf(client, showId));

    bool add(MediaItem? item, DateTime at) {
      if (item == null || rows.length >= limit) return false;
      if (item.libraryId != null && excludedLibraryIds.contains(item.libraryId)) return false;
      if (rows.any((row) => row.id == item.id)) return false;
      rows.add(item.copyWith(lastViewedAt: at.millisecondsSinceEpoch ~/ 1000));
      return true;
    }

    final paused = [...state.playback]..sort((a, b) => b.pausedAt.compareTo(a.pausedAt));
    final watching = state.shows.where((show) => show.lastWatchedAt != null && show.watched.isNotEmpty).toList()
      ..sort((a, b) => b.lastWatchedAt!.compareTo(a.lastWatchedAt!));

    // Every series looked at below is asked for up front, a few at a time,
    // at most one per row the list can take; each is awaited in turn below.
    final ahead = <String>{
      for (final session in paused)
        if (session.isEpisode) ?_itemsFor(session.ids).firstOrNull,
      for (final show in watching.take(seriesLimit)) ?_itemsFor(show.ids).firstOrNull,
    };
    for (final showId in ahead.take(limit)) {
      // A failure is met where the list is used.
      unawaited(episodes(showId).then<void>((_) {}, onError: (Object _) {}));
    }

    for (final session in paused) {
      if (rows.length >= limit) break;
      try {
        if (!session.isEpisode) {
          for (final itemId in _itemsFor(session.ids)) {
            final item = await client.fetchItem(itemId);
            if (item?.kind == MediaKind.movie && add(item, session.pausedAt)) break;
          }
          continue;
        }
        for (final showId in _itemsFor(session.ids)) {
          final episode = (await episodes(
            showId,
          )).where((e) => e.parentIndex == session.season && e.index == session.episode);
          if (episode.isEmpty) continue;
          seriesDone.add(showId);
          add(episode.first, session.pausedAt);
          break;
        }
      } catch (error) {
        appLogger.d('Tracker Continue Watching: a paused session could not be placed', error: error);
      }
    }

    for (final show in watching.take(seriesLimit)) {
      if (rows.length >= limit) break;
      try {
        for (final showId in _itemsFor(show.ids)) {
          if (seriesDone.contains(showId)) break;
          final list = await episodes(showId);
          if (list.isEmpty) continue;
          seriesDone.add(showId);
          add(_nextAfterLastSeen(list, show), show.lastWatchedAt!);
          break;
        }
      } catch (error) {
        appLogger.d('Tracker Continue Watching: the next episode could not be found', error: error);
      }
    }

    rows.sort((a, b) => b.recencySortKey.compareTo(a.recencySortKey));
    return rows;
  }

  /// The episode a series' page offers to play next: the one left paused,
  /// else the next after the last one seen; null for a series not started or
  /// seen to its end.
  Future<MediaItem?> nextEpisodeOf(MediaServerClient client, String showId) async {
    final ids = index[showId];
    if (ids == null) return null;
    final paused = state.playback.where((session) => session.isEpisode && session.ids.intersects(ids)).toList()
      ..sort((a, b) => b.pausedAt.compareTo(a.pausedAt));
    final show = state.show(ids);
    if (paused.isEmpty && show == null) return null;
    final list = await _episodesOf(client, showId);
    for (final session in paused) {
      for (final episode in list) {
        if (episode.parentIndex == session.season && episode.index == session.episode) return episode;
      }
    }
    return show == null ? null : _nextAfterLastSeen(list, show);
  }

  /// The first episode on the server after the last one seen that is not
  /// seen itself; null for a series seen to its end. Specials (season 0)
  /// are never offered as next.
  static MediaItem? _nextAfterLastSeen(List<MediaItem> episodes, TrackedShow show) {
    (int, int)? last;
    for (final MapEntry(key: season, value: numbers) in show.watched.entries) {
      if (season <= 0) continue;
      for (final number in numbers) {
        if (last == null || season > last.$1 || (season == last.$1 && number > last.$2)) last = (season, number);
      }
    }
    if (last == null) return null;
    final ordered = episodes.where((e) => (e.parentIndex ?? 0) > 0 && e.index != null).toList()
      ..sort(
        (a, b) =>
            a.parentIndex != b.parentIndex ? a.parentIndex!.compareTo(b.parentIndex!) : a.index!.compareTo(b.index!),
      );
    for (final episode in ordered) {
      final season = episode.parentIndex!;
      final number = episode.index!;
      final after = season > last.$1 || (season == last.$1 && number > last.$2);
      if (after && !show.hasWatched(season, number)) return episode;
    }
    return null;
  }

  /// The films and series this profile watched or left paused last that
  /// [client]'s server holds, newest first, at most [limit] — found through
  /// the tracker's dates and the server's ids, so no library has to be read
  /// whole and sorted to know them.
  Future<List<MediaItem>> recentlyWatched(MediaServerClient client, {int limit = recentLimit}) async {
    final dated = <({DateTime at, ExternalIds ids, MediaKind kind})>[
      for (final movie in state.movies)
        if (movie.watchedAt case final at?) (at: at, ids: movie.ids, kind: MediaKind.movie),
      for (final show in state.shows)
        if (show.lastWatchedAt case final at?) (at: at, ids: show.ids, kind: MediaKind.show),
      // A paused episode names its series.
      for (final session in state.playback)
        (at: session.pausedAt, ids: session.ids, kind: session.isEpisode ? MediaKind.show : MediaKind.movie),
    ]..sort((a, b) => b.at.compareTo(a.at));

    // A film and a series may share a TMDB number: each item is kept only
    // when it turns out to be what the tracker named.
    final wanted = <String, MediaKind>{};
    for (final title in dated) {
      if (wanted.length >= limit) break;
      for (final itemId in _itemsFor(title.ids)) {
        wanted.putIfAbsent(itemId, () => title.kind);
      }
    }

    final gate = _Gate(parallelLookups);
    final fetched = await Future.wait([
      for (final MapEntry(key: itemId, value: kind) in wanted.entries.take(limit))
        gate.run(() async {
          try {
            final item = await client.fetchItem(itemId);
            return item?.kind == kind ? item : null;
          } catch (error) {
            appLogger.d('Tracker recent titles: $itemId could not be fetched', error: error);
            return null;
          }
        }),
    ]);
    return [for (final item in fetched) ?item];
  }

  /// A series' episodes, as lightly as [client] can list them.
  static Future<List<MediaItem>> loadEpisodes(MediaServerClient client, String showId) async {
    final items = client is TrackerEpisodeListClient
        ? await (client as TrackerEpisodeListClient).fetchEpisodesWithoutStreams(showId)
        : (await client.fetchPlayableDescendantsPage(showId, start: 0, size: 2000)).items;
    return [
      for (final item in items)
        if (item.kind == MediaKind.episode) item,
    ];
  }
}

/// Lets at most [width] tasks run at once; the rest wait their turn in the
/// order they came.
class _Gate {
  _Gate(this.width);

  final int width;
  int _running = 0;
  final Queue<Completer<void>> _waiting = Queue();

  Future<T> run<T>(Future<T> Function() task) async {
    if (_running < width) {
      _running++;
    } else {
      final turn = Completer<void>();
      _waiting.add(turn);
      // The slot of a task that ends is handed straight on.
      await turn.future;
    }
    try {
      return await task();
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      } else {
        _running--;
      }
    }
  }
}
