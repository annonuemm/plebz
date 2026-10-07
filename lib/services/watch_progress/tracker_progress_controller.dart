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

  /// How old a server's id index may grow before it is asked again.
  static const Duration indexLifetime = Duration(hours: 1);

  String? _profileId;
  SimklClient? _simkl;
  Map<String, ExternalIdIndexClient> _servers = const {};
  TrackerWatchFiles? _files;
  TrackerWatchState _state = TrackerWatchState.empty;
  final Map<String, Map<String, ExternalIds>> _indexes = {};
  final Map<String, DateTime> _indexedAt = {};
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
      ).nextEpisodeOf(client, item.id);
    } catch (error) {
      appLogger.d('Tracker progress: next episode of ${item.id} unknown', error: error);
      return null;
    }
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
      _indexes.clear();
      _indexedAt.clear();
      _patches.clear();
      final files = TrackerWatchFiles(Directory(p.join((await rootDirectory()).path, _safe(profileId))));
      if (generation != _generation) return;
      _files = files;
      ProgressRouting.instance.onLocalChange = _noteLocalChange;
      _publish();
      final state = await files.readState();
      final indexes = {for (final serverId in _servers.keys) serverId: await files.readIndex(serverId)};
      final patches = await files.readPatches();
      if (generation != _generation) return;
      _state = state;
      _indexes.addAll(indexes);
      _patches.addAll(patches);
      _publish(contentChanged: true);
    }
    await refresh();
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
    for (final MapEntry(key: serverId, value: client) in _servers.entries) {
      final at = _indexedAt[serverId];
      if (!full && at != null && clock.now().difference(at) < indexLifetime) continue;
      try {
        final index = await client.fetchExternalIdIndex();
        if (generation != _generation) return;
        _indexes[serverId] = index;
        _indexedAt[serverId] = clock.now();
        changed = true;
        unawaited(files.writeIndex(serverId, index));
      } catch (error) {
        appLogger.w('Tracker progress: ids of $serverId could not be read', error: error);
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
    _echoAfter(echoDelay);
  }

  void _echoAfter(Duration delay) {
    _echoTimer?.cancel();
    _echoTimer = Timer(delay, () => unawaited(refresh()));
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
    _indexes.clear();
    _indexedAt.clear();
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
