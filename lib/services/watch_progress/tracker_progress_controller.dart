import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_server_client.dart';
import '../../utils/app_logger.dart';
import '../../utils/external_ids.dart';
import '../trackers/simkl/simkl_client.dart';
import 'external_id_index_client.dart';
import 'progress_routing.dart';
import 'simkl_watch_sync.dart';
import 'tracker_continue_watching.dart';
import 'tracker_watch_files.dart';
import 'tracker_watch_overlay.dart';
import 'tracker_watch_state.dart';

/// Keeps a tracker-led profile's watch state (fork addition): reads it from
/// disk, asks Simkl and the servers again, and hands [ProgressRouting] the
/// overlay to lay over every server item.
///
/// Bound by the app shell whenever the profile, its choice, its Simkl
/// session or the connected servers change ([bind]); a profile that keeps its
/// progress on the server hands everything back ([ProgressRouting] in server
/// mode) and costs nothing.
class TrackerProgressController extends ChangeNotifier {
  TrackerProgressController._();

  static final TrackerProgressController instance = TrackerProgressController._();

  /// Where each profile's files live; replaced in tests.
  @visibleForTesting
  Future<Directory> Function() rootDirectory = _defaultRoot;

  static Future<Directory> _defaultRoot() async =>
      Directory(p.join((await getApplicationSupportDirectory()).path, 'tracker_watch'));

  /// How long a change made here is kept at most. It gives way sooner to
  /// anything newer the tracker says about the same title (see
  /// [TrackerWatchOverlay]); this only clears what never got an answer.
  static const Duration patchLifetime = Duration(days: 30);

  /// How soon the tracker is asked again while changes made here wait for its
  /// echo.
  static const Duration patchEchoCheck = Duration(minutes: 3);

  /// How soon after a change made here the tracker is asked again.
  static const Duration echoDelay = Duration(seconds: 30);

  /// The same after a playback position. Playing leaves one every 30 s, and
  /// each one moves the echo on: longer than that gap, the tracker is asked
  /// once playback has stopped or paused, never while it runs.
  static const Duration positionEchoDelay = Duration(seconds: 90);

  /// How old a server's id index may grow before it is asked again. Kept on
  /// disk with the index, so a start within it asks the server nothing.
  static const Duration indexLifetime = Duration(hours: 1);

  /// How old the last whole read of a server's ids may grow; in between, the
  /// server is asked only for what was added since. A big library read whole
  /// took a minute of requests on every start. Titles gone from the server
  /// and matches corrected there wait for the next whole read.
  static const Duration wholeIndexLifetime = Duration(days: 7);

  /// How long a series' episode list is reused: the passes at start, the
  /// library tab and the series' page then share one request.
  static const Duration episodeListLifetime = Duration(minutes: 10);

  /// How long a server whose id index could not be read is left alone. Every
  /// refresh asked it again at once, and a listing that runs into the
  /// timeout cost minutes of download each time; the last index read stays
  /// in use meanwhile.
  static const Duration defaultIndexRetryDelay = Duration(minutes: 15);

  @visibleForTesting
  static Duration indexRetryDelay = defaultIndexRetryDelay;

  String? _profileId;
  SimklClient? _simkl;
  Map<String, ExternalIdIndexClient> _servers = const {};
  TrackerWatchFiles? _files;
  TrackerWatchState _state = TrackerWatchState.empty;
  final Map<String, Map<String, ExternalIds>> _indexes = {};
  final Map<String, DateTime> _indexedAt = {};
  final Map<String, DateTime> _indexWholeAt = {};
  final Map<String, int> _indexNewest = {};
  final Map<String, DateTime> _indexFailedAt = {};

  /// The servers whose index this profile has looked for on disk already.
  final Set<String> _indexesRead = {};
  final Map<String, ({DateTime at, Future<List<MediaItem>> episodes})> _episodeLists = {};
  final Map<String, ({int stamp, Future<List<MediaItem>> titles})> _recentTitles = {};
  final Map<String, LocalWatchPatch> _patches = {};
  Future<void>? _refreshing;
  Timer? _echoTimer;
  int _generation = 0;

  /// Whether a tracker keeps the active profile's watch state.
  bool get isActive => _simkl != null;

  TrackerWatchState get state => _state;

  /// The ids of [itemId] on [serverId], if its server has named them.
  ExternalIds? idsOf(String serverId, String itemId) => _indexes[serverId]?[itemId];

  /// Continue Watching on [client]'s server for a tracker-led profile; null
  /// while the server keeps the profile's progress, so its own list is used.
  Future<List<MediaItem>>? continueWatchingFor(
    MediaServerClient client, {
    int? count,
    Set<String> excludedLibraryIds = const {},
  }) {
    if (!isActive) return null;
    // Home and every library page ask in turn; one answer serves them all
    // for a minute, as long as nothing was watched or marked since.
    final key = '${client.serverId}|$count|${(excludedLibraryIds.toList()..sort()).join(',')}';
    final kept = _continueWatching[key];
    if (kept != null && kept.stamp == _changeStamp && clock.now().difference(kept.at) < continueWatchingLifetime) {
      return kept.rows;
    }
    final rows = TrackerContinueWatching(
      state: _state,
      index: _indexes[client.serverId] ?? const {},
      episodesOf: _episodesOf,
    ).fetch(client, count: count, excludedLibraryIds: excludedLibraryIds);
    _continueWatching[key] = (stamp: _changeStamp, at: clock.now(), rows: rows);
    rows.catchError((Object _) {
      if (identical(_continueWatching[key]?.rows, rows)) _continueWatching.remove(key);
      return const <MediaItem>[];
    });
    return rows;
  }

  /// How long a Continue Watching answer is reused.
  static const Duration continueWatchingLifetime = Duration(minutes: 1);

  final Map<String, ({int stamp, DateTime at, Future<List<MediaItem>> rows})> _continueWatching = {};

  /// Counts every change to what this profile watched — the tracker's or one
  /// made here.
  int _changeStamp = 0;

  /// The episode a series' page offers next for a tracker-led profile, in
  /// place of the account's own; [item] other than a series has none.
  Future<MediaItem?> onDeckFor(MediaServerClient client, MediaItem? item) async {
    if (item == null || item.kind != MediaKind.show) return null;
    try {
      await _ensureIdsOf(client, item.id);
      return await TrackerContinueWatching(
        state: _state,
        index: _indexes[client.serverId] ?? const {},
        episodesOf: _episodesOf,
      ).nextEpisodeOf(client, item.id);
    } catch (error) {
      appLogger.d('Tracker progress: next episode of ${item.id} unknown', error: error);
      return null;
    }
  }

  /// [showId]'s episodes on [client]'s server, read at most once per
  /// [episodeListLifetime] and laid over with this profile's state anew each
  /// time, so what was watched since shows.
  Future<List<MediaItem>> _episodesOf(MediaServerClient client, String showId) {
    final key = '${client.serverId}|$showId';
    final kept = _episodeLists[key];
    final Future<List<MediaItem>> list;
    if (kept != null && clock.now().difference(kept.at) < episodeListLifetime) {
      list = kept.episodes;
    } else {
      list = TrackerContinueWatching.loadEpisodes(client, showId);
      _episodeLists[key] = (at: clock.now(), episodes: list);
      list.then<void>(
        (_) {},
        onError: (Object _) {
          // A failed read is not kept; the next pass asks again.
          if (identical(_episodeLists[key]?.episodes, list)) _episodeLists.remove(key);
        },
      );
    }
    return list.then((episodes) => [for (final episode in episodes) ProgressRouting.overlay(episode)]);
  }

  /// The films and series this profile watched last on [client]'s server,
  /// newest first — what the recommendation row reasons from — or null while
  /// the server keeps the profile's progress. One answer per change.
  Future<List<MediaItem>>? recentlyWatchedOn(MediaServerClient client) {
    if (!isActive) return null;
    final key = client.serverId;
    final kept = _recentTitles[key];
    if (kept != null && kept.stamp == _changeStamp) return kept.titles;
    final titles = TrackerContinueWatching(
      state: _state,
      index: _indexes[client.serverId] ?? const {},
    ).recentlyWatched(client);
    _recentTitles[key] = (stamp: _changeStamp, titles: titles);
    titles.then<void>(
      (_) {},
      onError: (Object _) {
        if (identical(_recentTitles[key]?.titles, titles)) _recentTitles.remove(key);
      },
    );
    return titles;
  }

  /// Makes sure the ids of [itemId] on [client]'s server are known, asking
  /// the server for this one title when its library listing did not name it —
  /// a copy added since, a library on a server that came online later. Without
  /// them a series' page knows nothing the tracker says about it: every episode
  /// reads unwatched and play starts at the first.
  ///
  /// Called before the page fetches its episodes, so they come in with the
  /// tracker's state already.
  Future<void> _ensureIdsOf(MediaServerClient client, String itemId) async {
    final serverId = client.serverId;
    if (_indexes[serverId]?.containsKey(itemId) ?? false) return;
    final generation = _generation;
    final ids = await client.fetchExternalIds(itemId);
    if (generation != _generation || !ids.hasCatalogIds) {
      if (!ids.hasCatalogIds) appLogger.i('Tracker progress: $serverId/$itemId names no ids, cannot be matched');
      return;
    }
    final index = Map.of(_indexes[serverId] ?? const <String, ExternalIds>{})..[itemId] = ids;
    _indexes[serverId] = index;
    unawaited(_files?.writeIndex(serverId, index));
    _publish();
  }

  /// Counts up whenever what the tracker or the servers said changed — not
  /// for changes made here, which their own events already show. Screens
  /// listing many titles fetch again on it.
  final ValueNotifier<int> revision = ValueNotifier(0);

  Future<void> bind({
    required String? profileId,
    required bool trackerLed,
    required SimklClient? simkl,
    required Map<String, ExternalIdIndexClient> servers,
  }) async {
    if (!trackerLed || simkl == null || profileId == null) {
      _deactivate();
      return;
    }
    _simkl = simkl;
    _servers = Map.of(servers);
    if (profileId != _profileId) {
      final generation = ++_generation;
      _profileId = profileId;
      _state = TrackerWatchState.empty;
      _retryTimer?.cancel();
      _lastSyncAt = null;
      _syncFailed = false;
      _failedSyncs = 0;
      _clearIndexes();
      _patches.clear();
      final files = TrackerWatchFiles(Directory(p.join((await rootDirectory()).path, _safe(profileId))));
      if (generation != _generation) return;
      _files = files;
      ProgressRouting.instance.onLocalChange = _noteLocalChange;
      _publish();
      final state = await files.readState();
      final patches = await files.readPatches();
      if (generation != _generation) return;
      _state = state;
      _patches.addAll(patches);
      await _readKeptIndexes();
      if (generation != _generation) return;
      _publish(contentChanged: true);
    } else if (await _readKeptIndexes()) {
      _publish(contentChanged: true);
    }
    await refresh();
  }

  /// Reads the id index kept on disk for each server this profile has not
  /// looked for one yet — at a profile's first bind, and for a server that
  /// came online since, which would otherwise be read whole at every start.
  /// True when one was found. One read after another; a refresh waits for
  /// them, so a server is not read whole while its kept index is on its way.
  Future<bool> _readKeptIndexes() => _keptIndexReads = _keptIndexReads.then((_) => _readKeptIndexesNow());

  Future<bool> _keptIndexReads = Future.value(false);

  Future<bool> _readKeptIndexesNow() async {
    final files = _files;
    if (files == null) return false;
    final generation = _generation;
    final fresh = [
      for (final serverId in _servers.keys)
        if (_indexesRead.add(serverId)) serverId,
    ];
    final Map<String, ({Map<String, ExternalIds> ids, IndexReadMarks? marks})> kept;
    try {
      kept = {
        for (final serverId in fresh)
          serverId: (ids: await files.readIndex(serverId), marks: await files.readIndexMarks(serverId)),
      };
    } catch (error) {
      // Only a head start: without it the servers are read as before.
      appLogger.w('Tracker progress: kept id indexes unreadable', error: error);
      return false;
    }
    if (generation != _generation) return false;
    var found = false;
    for (final MapEntry(key: serverId, value: (:ids, :marks)) in kept.entries) {
      if (ids.isEmpty || _indexes.containsKey(serverId)) continue;
      _indexes[serverId] = ids;
      found = true;
      // An index kept without its read times (an older version wrote it) is
      // read whole once more.
      if (marks == null) continue;
      _indexedAt[serverId] = marks.readAt;
      _indexWholeAt[serverId] = marks.wholeAt;
      if (marks.newest case final newest?) _indexNewest[serverId] = newest;
    }
    return found;
  }

  void _clearIndexes() {
    _indexes.clear();
    _indexedAt.clear();
    _indexWholeAt.clear();
    _indexNewest.clear();
    _indexFailedAt.clear();
    _indexesRead.clear();
    _episodeLists.clear();
    _recentTitles.clear();
  }

  /// Ask Simkl what changed, and each server for its ids where they have
  /// grown old; one pass at a time.
  Future<void> refresh() => _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  /// "Jetzt abgleichen": everything asked again — Simkl whole rather than what
  /// changed, every server's ids anew. Waits for a pass already under way
  /// first. True when Simkl answered.
  Future<bool> syncNow() async {
    await _refreshing;
    if (!isActive) return false;
    _episodeLists.clear();
    await (_refreshing = _refresh(full: true).whenComplete(() => _refreshing = null));
    return isActive && !_syncFailed;
  }

  /// After a failed sync, when to try again: sooner first, then less often.
  static const List<Duration> defaultRetryDelays = [Duration(minutes: 1), Duration(minutes: 5), Duration(minutes: 15)];

  @visibleForTesting
  static List<Duration> retryDelays = defaultRetryDelays;

  DateTime? _lastSyncAt;
  bool _syncFailed = false;
  bool _syncing = false;
  int _failedSyncs = 0;
  Timer? _retryTimer;

  /// When Simkl last answered a sync; null before the first.
  DateTime? get lastSyncAt => _lastSyncAt;

  /// Whether the last sync failed — a retry is then on its way.
  bool get syncFailed => _syncFailed;

  /// Whether a sync is under way.
  bool get syncing => _syncing;

  void _scheduleRetry() {
    _retryTimer?.cancel();
    final delay = retryDelays[(_failedSyncs - 1).clamp(0, retryDelays.length - 1)];
    _retryTimer = Timer(delay, () => unawaited(refresh()));
  }

  Future<void> _refresh({bool full = false}) async {
    final generation = _generation;
    final simkl = _simkl;
    final files = _files;
    if (simkl == null || files == null) return;
    _syncing = true;
    notifyListeners();
    try {
      await _refreshWith(simkl, files, generation, full: full);
    } finally {
      if (generation == _generation) {
        _syncing = false;
        notifyListeners();
      }
    }
  }

  Future<void> _refreshWith(SimklClient simkl, TrackerWatchFiles files, int generation, {required bool full}) async {
    var changed = false;
    try {
      final next = await SimklWatchSync(simkl).refresh(full ? _state.withoutSyncMarks() : _state);
      if (generation != _generation) return;
      _lastSyncAt = clock.now();
      _syncFailed = false;
      _failedSyncs = 0;
      _retryTimer?.cancel();
      if (!identical(next, _state)) {
        _state = next;
        changed = true;
        unawaited(files.writeState(next));
      }
    } catch (error) {
      if (generation != _generation) return;
      // Not left until the next resume or profile switch: a first sync that
      // failed kept the profile blank until the viewer reconnected Simkl.
      _syncFailed = true;
      _failedSyncs++;
      _scheduleRetry();
      appLogger.w('Tracker progress: Simkl sync failed (attempt $_failedSyncs), trying again later', error: error);
    }
    await _keptIndexReads;
    if (generation != _generation) return;
    for (final MapEntry(key: serverId, value: client) in _servers.entries) {
      final at = _indexedAt[serverId];
      if (!full && at != null && clock.now().difference(at) < indexLifetime) continue;
      final failedAt = _indexFailedAt[serverId];
      if (!full && failedAt != null && clock.now().difference(failedAt) < indexRetryDelay) continue;
      try {
        final known = _indexes[serverId];
        final wholeAt = _indexWholeAt[serverId];
        final addedSince =
            full || known == null || wholeAt == null || clock.now().difference(wholeAt) >= wholeIndexLifetime
            ? null
            : _indexNewest[serverId];
        final read = await client.fetchExternalIdIndex(addedSince: addedSince);
        if (generation != _generation) return;
        final now = clock.now();
        _indexedAt[serverId] = now;
        _indexFailedAt.remove(serverId);
        if (read.complete) {
          _indexWholeAt[serverId] = now;
          _indexNewest.remove(serverId);
        }
        final newest = read.newest;
        if (newest != null && newest > (_indexNewest[serverId] ?? 0)) _indexNewest[serverId] = newest;
        final index = read.complete ? read.ids : {...?known, ...read.ids};
        if (!read.complete) {
          appLogger.d('Tracker progress: ${read.ids.length} titles added on $serverId since the last read');
        }
        // The same ids again change nothing on screen: no reason to have
        // every page fetch anew.
        if (!_sameIndex(known, index)) {
          _indexes[serverId] = index;
          changed = true;
          unawaited(files.writeIndex(serverId, index));
        }
        unawaited(
          files.writeIndexMarks(
            serverId,
            IndexReadMarks(readAt: now, wholeAt: _indexWholeAt[serverId] ?? now, newest: _indexNewest[serverId]),
          ),
        );
      } catch (error) {
        if (generation != _generation) return;
        _indexFailedAt[serverId] = clock.now();
        appLogger.w(
          'Tracker progress: ids of $serverId could not be read, next try in ${indexRetryDelay.inMinutes} min',
          error: error,
        );
      }
    }
    final stale = clock.now().subtract(patchLifetime);
    final before = _patches.length;
    _patches.removeWhere((_, patch) => patch.at.isBefore(stale));
    if (_patches.length != before) unawaited(files.writePatches(Map.of(_patches)));
    if (changed || _patches.length != before) _publish(contentChanged: changed);
    appLogger.i(
      'Tracker progress: ${_state.movies.length} films, ${_state.shows.length} series, '
      '${_state.playback.length} paused, ${_patches.length} own changes waiting',
    );
    if (_patches.isNotEmpty) _echoAfter(patchEchoCheck);
  }

  void _noteLocalChange(MediaItem item, {bool? watched, int? offsetMs}) {
    final serverId = item.serverId;
    if (!isActive || serverId == null) return;
    _patches[LocalWatchPatch.keyOf(serverId, item.id)] = LocalWatchPatch(
      watched: watched,
      offsetMs: offsetMs,
      at: clock.now(),
    );
    // Kept on disk: a position left here must survive the app being closed
    // before the tracker has it.
    unawaited(_files?.writePatches(Map.of(_patches)));
    _publish();
    _echoAfter(watched == null ? positionEchoDelay : echoDelay);
  }

  void _echoAfter(Duration delay) {
    _echoTimer?.cancel();
    _echoDelay = delay;
    _echoTimer = Timer(delay, () {
      _echoDelay = null;
      unawaited(refresh());
    });
  }

  Duration? _echoDelay;

  /// What the echo now waiting was set to wait; null when none waits.
  @visibleForTesting
  Duration? get debugEchoDelay => (_echoTimer?.isActive ?? false) ? _echoDelay : null;

  static bool _sameIndex(Map<String, ExternalIds>? before, Map<String, ExternalIds> after) {
    if (before == null || before.length != after.length) return false;
    for (final MapEntry(key: itemId, value: ids) in after.entries) {
      final was = before[itemId];
      if (was == null ||
          was.imdb != ids.imdb ||
          was.tmdb != ids.tmdb ||
          was.tvdb != ids.tvdb ||
          was.anidb != ids.anidb) {
        return false;
      }
    }
    return true;
  }

  void _publish({bool contentChanged = false}) {
    _changeStamp++;
    ProgressRouting.instance.activate(
      ProgressSourceKind.tracker,
      overlay: TrackerWatchOverlay(state: _state, idsOf: idsOf, patches: Map.of(_patches)),
    );
    if (contentChanged) revision.value++;
    notifyListeners();
  }

  void _deactivate() {
    if (_profileId == null && _simkl == null) return;
    _generation++;
    _echoTimer?.cancel();
    _retryTimer?.cancel();
    _lastSyncAt = null;
    _syncFailed = false;
    _syncing = false;
    _failedSyncs = 0;
    _profileId = null;
    _simkl = null;
    _servers = const {};
    _files = null;
    _state = TrackerWatchState.empty;
    _clearIndexes();
    _continueWatching.clear();
    _patches.clear();
    ProgressRouting.instance
      ..onLocalChange = null
      ..activate(ProgressSourceKind.server);
    revision.value++;
    notifyListeners();
  }

  static String _safe(String name) => name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  /// Done once what was learnt so far is on disk.
  @visibleForTesting
  Future<void> debugFlush() async => _files?.idle;

  @visibleForTesting
  void debugReset() {
    _deactivate();
    rootDirectory = _defaultRoot;
    retryDelays = defaultRetryDelays;
    indexRetryDelay = defaultIndexRetryDelay;
  }
}

/// A series' page asks for its next episode through here (fork addition).
extension TrackerOnDeckLookup on MediaServerClient {
  /// [fetchItemWithOnDeck], with a tracker-led profile's next episode in
  /// place of the shared account's.
  Future<({MediaItem? item, MediaItem? onDeckEpisode})> fetchItemWithProfileOnDeck(
    String id, {
    void Function(MediaItem item)? onItemReady,
  }) async {
    final result = await fetchItemWithOnDeck(id, onItemReady: onItemReady);
    final controller = TrackerProgressController.instance;
    if (!controller.isActive) return result;
    return (item: result.item, onDeckEpisode: await controller.onDeckFor(this, result.item));
  }
}
