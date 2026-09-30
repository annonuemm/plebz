import 'dart:async';

import '../media/ids.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_server_client.dart';
import '../utils/app_logger.dart';
import '../utils/watch_state_notifier.dart';
import 'data_aggregation_service.dart';
import 'multi_server_manager.dart';
import 'settings_service.dart';

/// Carries a watched mark over to every other copy of the same movie.
///
/// Someone with Plex and Jellyfin side by side owns the same film twice, and
/// watching it on one leaves the other claiming it is unseen. This listens to
/// the app's single watched/unwatched event and writes the same state to every
/// other copy it can identify — other libraries on the same server included,
/// since a 4K and an HD section hold the film under two rating keys.
///
/// Copies are found by external id (IMDb / TMDB / TVDB), the same lookup the
/// detail page's "other copies" section uses. The title is only ever a search
/// term: a candidate that does not match on an id is discarded, so a mark
/// never lands on a film that merely shares a name.
///
/// Films, whole series and single seasons — not individual episodes. A series
/// costs no more than a film: both backends mark a series or season's episodes
/// themselves, so one write covers the lot. A season is found through its show
/// and its own number, because neither backend can be searched by an external
/// id at all (Plex's `guid=` filter only matches its own `plex://` id, and
/// Jellyfin dropped `anyProviderIdEquals`) and a season title is worthless as
/// a search term. An episode would need the whole episode list of every copy,
/// one round per episode, which is the reason it stops here.
class CrossServerWatchedMirror {
  /// How long a copy this service wrote stays exempt from its own listener.
  ///
  /// Writing a copy emits the same event the write came in on, which would
  /// otherwise start the round again. The entry is normally consumed by that
  /// event within a frame; the window only bounds the leak for a write whose
  /// event never arrives (an item with no server id emits nothing).
  static const selfWriteWindow = Duration(minutes: 1);

  final MultiServerManager _serverManager;
  final DataAggregationService _aggregation;
  final DateTime Function() _now;

  StreamSubscription<WatchStateEvent>? _subscription;

  /// Copies this service marked, and when. Keyed by global key.
  final Map<String, DateTime> _selfWritten = {};

  CrossServerWatchedMirror({required this._serverManager, required this._aggregation, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  void start() {
    _subscription ??= WatchStateNotifier().stream.listen((event) => unawaited(handleEvent(event)));
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _selfWritten.clear();
  }

  /// The one pass, exposed so a test can await it instead of racing the stream.
  Future<void> handleEvent(WatchStateEvent event) async {
    final watched = switch (event.changeType) {
      WatchStateChangeType.watched => true,
      WatchStateChangeType.unwatched => false,
      _ => null,
    };
    if (watched == null) return;
    if (_consumeSelfWrite(event.globalKey)) return;
    if (!(SettingsService.instanceOrNull?.read(SettingsService.mirrorWatchedAcrossServers) ?? false)) return;

    final source = _serverManager.getClient(event.serverId);
    if (source == null) return;

    try {
      // A null item means the server no longer knows it — nothing to match on.
      final item = await source.fetchItem(event.itemId);
      switch (item?.kind) {
        case MediaKind.movie || MediaKind.show:
          await _mirrorTitle(source, item!, watched: watched, origin: event.globalKey);
        case MediaKind.season:
          await _mirrorSeason(source, item!, watched: watched, origin: event.globalKey);
        // Episodes and everything else (tracks, photos) stay out of it.
        case _:
          return;
      }
    } catch (error, stackTrace) {
      // A mirror that cannot run changes nothing the viewer asked for, so it
      // stays a log line rather than an error in their face.
      appLogger.w('Cross-server watched mirror failed for ${event.globalKey}', error: error, stackTrace: stackTrace);
    }
  }

  /// A film or a whole series: found directly, marked in one write per copy.
  Future<void> _mirrorTitle(
    MediaServerClient source,
    MediaItem item, {
    required bool watched,
    required String origin,
  }) async {
    final copies = await _findCopiesOf(source, item);
    for (final copy in copies) {
      await _mirrorTo(copy, watched: watched, origin: origin);
    }
  }

  /// A single season: its show is what can be found, the season number is what
  /// picks it out of the copy. Costs one extra listing per show copy and still
  /// nothing per episode.
  Future<void> _mirrorSeason(
    MediaServerClient source,
    MediaItem season, {
    required bool watched,
    required String origin,
  }) async {
    // Plex hangs a season off the show through parentId; Jellyfin fills both
    // that and grandparentId with the series.
    final showId = season.parentId ?? season.grandparentId;
    final number = season.index;
    if (showId == null || number == null) return;

    final show = await source.fetchItem(showId);
    if (show == null) return;

    for (final showCopy in await _findCopiesOf(source, show)) {
      // The show this very season hangs off: the only season under it with
      // this number is the one that was just marked.
      if (showCopy.globalKey == show.globalKey) continue;

      final target = _clientFor(showCopy);
      if (target == null) continue;
      for (final child in await target.fetchChildren(showCopy.id)) {
        if (child.kind != MediaKind.season || child.index != number) continue;
        await _mirrorTo(child, watched: watched, origin: origin);
      }
    }
  }

  /// Every library copy of [item] — other libraries on its own server included,
  /// since a 4K and an HD section hold it twice.
  ///
  /// Two search terms, because neither backend can filter by external id: the
  /// title as this server spells it, and the original one. Libraries in
  /// different languages hold the same title under different names, and the
  /// second term is only spent when the first verified nothing.
  Future<List<MediaItem>> _findCopiesOf(MediaServerClient source, MediaItem item) async {
    final ids = await source.fetchExternalIds(item.id);
    // Without an id there is only the title, and a title alone is never enough
    // to declare two entries the same thing.
    if (!ids.hasCatalogIds) return const [];

    // Every connected server: mirroring is about the copies elsewhere.
    final lookup = await _aggregation.findByExternalIdsAcrossServers(
      ids,
      kind: item.kind,
      serverIds: _serverManager.serverIds.toSet(),
      titles: {?item.title, ?item.originalTitle}.toList(),
      year: item.year,
      plexGuid: item.guid,
    );
    return lookup.items;
  }

  Future<void> _mirrorTo(MediaItem copy, {required bool watched, required String origin}) async {
    if (copy.globalKey == origin) return;
    // Already right — a copy watched on both servers, or a second pass over
    // work the first one did. Skipping keeps the round self-limiting even if
    // the self-write guard ever misses.
    if (copy.isWatched == watched) return;

    final target = _clientFor(copy);
    if (target == null) return;

    _selfWritten[copy.globalKey] = _now();
    try {
      if (watched) {
        await target.markWatched(copy);
      } else {
        await target.markUnwatched(copy);
      }
      // The copy is on a screen the viewer may already be looking at, so the
      // app learns about it the same way it learns about any other mark.
      WatchStateNotifier().notifyWatched(
        item: copy,
        isNowWatched: watched,
        cacheServerId: target.cacheServerId,
        serverAcknowledged: true,
      );
      appLogger.d('Mirrored watched=$watched to ${copy.globalKey}');
    } catch (error, stackTrace) {
      _selfWritten.remove(copy.globalKey);
      appLogger.w('Could not mirror watched state to ${copy.globalKey}', error: error, stackTrace: stackTrace);
    }
  }

  MediaServerClient? _clientFor(MediaItem item) {
    final serverId = serverIdOrNull(item.serverId);
    return serverId == null ? null : _serverManager.getClient(serverId);
  }

  /// True when this event is the echo of our own write.
  bool _consumeSelfWrite(String globalKey) {
    final at = _selfWritten.remove(globalKey);
    if (at == null) return false;
    _dropExpiredSelfWrites();
    return _now().difference(at) < selfWriteWindow;
  }

  void _dropExpiredSelfWrites() {
    final now = _now();
    _selfWritten.removeWhere((_, at) => now.difference(at) >= selfWriteWindow);
  }
}
