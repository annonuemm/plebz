import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../utils/external_ids.dart';
import 'progress_routing.dart';
import 'tracker_watch_state.dart';

/// The ids a server's film or series is known by elsewhere; null when the
/// server named none, or has not been asked yet.
typedef ServerItemIds = ExternalIds? Function(String serverId, String itemId);

/// A change made in this app that the tracker has not confirmed yet: marked
/// watched or unwatched, or left at [offsetMs] (fork addition).
class LocalWatchPatch {
  const LocalWatchPatch({this.watched, this.offsetMs, required this.at});

  /// True or false for a mark; null for a playback position.
  final bool? watched;
  final int? offsetMs;
  final DateTime at;

  static String keyOf(String serverId, String itemId) => '$serverId|$itemId';

  Map<String, Object?> toJson() => {'watched': watched, 'offsetMs': offsetMs, 'at': at.toIso8601String()};

  static LocalWatchPatch? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final at = raw['at'] is String ? DateTime.tryParse(raw['at'] as String) : null;
    if (at == null) return null;
    return LocalWatchPatch(watched: raw['watched'] as bool?, offsetMs: (raw['offsetMs'] as num?)?.toInt(), at: at);
  }
}

/// Lays a tracker's watch state over what a server says (fork addition).
///
/// What the server said about watching is set aside whole — on a shared
/// account it is someone else's — and replaced by the tracker's: watched or
/// not, where playback was left, how many episodes of a series or season are
/// seen. A title the tracker does not know is unwatched. Films and series are
/// found by their ids ([idsOf]); a season or an episode by its series' ids and
/// its own season and episode numbers. Anything else — music, photos, clips —
/// passes untouched.
///
/// [patches] are this app's own changes the tracker has not echoed yet. They
/// win over its state, the newest first, and a mark on a series or a season
/// reaches its episodes.
class TrackerWatchOverlay implements WatchStateOverlay {
  TrackerWatchOverlay({required this.state, required this.idsOf, this.patches = const {}});

  final TrackerWatchState state;
  final ServerItemIds idsOf;
  final Map<String, LocalWatchPatch> patches;

  @override
  MediaItem apply(MediaItem item) {
    final serverId = item.serverId;
    if (serverId == null) return item;
    ExternalIds? ids(String? itemId) => itemId == null || itemId.isEmpty ? null : idsOf(serverId, itemId);

    // This device's own change stands until the tracker says something newer
    // about the same title: a mark or position made here never echoed (a
    // scrobble refused, a sync missed) is not lost after a few minutes.
    if (_patchFor(item, serverId) case final patch? when !_trackerNewer(item, serverId, patch.at)) {
      return _patched(item, patch);
    }

    switch (item.kind) {
      case MediaKind.movie:
        final movieIds = ids(item.id);
        final movie = movieIds == null ? null : state.movie(movieIds);
        final paused = movieIds == null || movie?.isWatched == true ? null : state.moviePlayback(movieIds);
        return _leaf(item, watchedAt: movie?.watchedAt, paused: paused);
      case MediaKind.episode:
        final showIds = ids(item.grandparentId);
        final season = item.parentIndex;
        final number = item.index;
        if (showIds == null || season == null || number == null) return _leaf(item);
        final show = state.show(showIds);
        final watched = show?.hasWatched(season, number) ?? false;
        return _leaf(
          item,
          watchedAt: watched ? (show?.lastWatchedAt ?? DateTime.utc(1970)) : null,
          paused: watched ? null : state.episodePlayback(showIds, season, number),
        );
      case MediaKind.show:
        final show = _show(ids(item.id));
        return _container(item, seen: show?.watchedCount ?? 0, lastWatchedAt: show?.lastWatchedAt);
      case MediaKind.season:
        final show = _show(ids(item.parentId));
        final season = item.index ?? item.parentIndex;
        return _container(
          item,
          seen: season == null ? 0 : (show?.watchedIn(season) ?? 0),
          lastWatchedAt: show?.lastWatchedAt,
        );
      default:
        return item;
    }
  }

  TrackedShow? _show(ExternalIds? ids) => ids == null ? null : state.show(ids);

  /// Whether the tracker holds anything about [item] from after [at]: a watch
  /// or a paused session of its own, or a later watch anywhere in its series.
  bool _trackerNewer(MediaItem item, String serverId, DateTime at) {
    bool after(DateTime? moment) => moment != null && moment.isAfter(at);
    ExternalIds? ids(String? itemId) => itemId == null || itemId.isEmpty ? null : idsOf(serverId, itemId);
    switch (item.kind) {
      case MediaKind.movie:
        final movieIds = ids(item.id);
        if (movieIds == null) return false;
        return after(state.movie(movieIds)?.watchedAt) || after(state.moviePlayback(movieIds)?.pausedAt);
      case MediaKind.episode:
        final showIds = ids(item.grandparentId);
        if (showIds == null) return false;
        final season = item.parentIndex;
        final number = item.index;
        final paused = season == null || number == null ? null : state.episodePlayback(showIds, season, number);
        return after(state.show(showIds)?.lastWatchedAt) || after(paused?.pausedAt);
      case MediaKind.show:
        return after(_show(ids(item.id))?.lastWatchedAt);
      case MediaKind.season:
        return after(_show(ids(item.parentId))?.lastWatchedAt);
      default:
        return false;
    }
  }

  /// The newest patch on [item] itself, or a mark on the season or series it
  /// belongs to.
  LocalWatchPatch? _patchFor(MediaItem item, String serverId) {
    if (patches.isEmpty) return null;
    final ancestors = switch (item.kind) {
      MediaKind.episode => [item.parentId, item.grandparentId],
      MediaKind.season => [item.parentId],
      MediaKind.movie || MediaKind.show => const <String?>[],
      _ => null,
    };
    if (ancestors == null) return null;
    LocalWatchPatch? newest = patches[LocalWatchPatch.keyOf(serverId, item.id)];
    for (final id in ancestors) {
      if (id == null || id.isEmpty) continue;
      final patch = patches[LocalWatchPatch.keyOf(serverId, id)];
      if (patch == null || patch.watched == null) continue;
      if (newest == null || patch.at.isAfter(newest.at)) newest = patch;
    }
    return newest;
  }

  static MediaItem _patched(MediaItem item, LocalWatchPatch patch) {
    final at = patch.at.millisecondsSinceEpoch ~/ 1000;
    if (item.kind.usesLeafWatchCounts) {
      final watched = patch.watched ?? false;
      final total = item.leafWatchTotal;
      return item.copyWith(
        viewedLeafCount: watched ? (total ?? item.viewedLeafCount) : 0,
        viewCount: watched ? 1 : 0,
        viewOffsetMs: null,
        lastViewedAt: watched ? at : null,
      );
    }
    final offset = patch.offsetMs;
    return item.copyWith(
      viewCount: patch.watched == true ? 1 : 0,
      viewOffsetMs: patch.watched == null && offset != null && offset > 0 ? offset : null,
      lastViewedAt: patch.watched == false ? null : at,
    );
  }

  /// A film or an episode: watched when [watchedAt] is set, else resumable
  /// where [paused] left it — placed in the item's own duration.
  static MediaItem _leaf(MediaItem item, {DateTime? watchedAt, TrackedPlayback? paused}) {
    final duration = item.durationMs;
    final offset = paused != null && duration != null && duration > 0
        ? paused.positionIn(Duration(milliseconds: duration)).inMilliseconds
        : null;
    final at = watchedAt ?? paused?.pausedAt;
    return item.copyWith(
      viewCount: watchedAt != null ? 1 : 0,
      viewOffsetMs: offset != null && offset > 0 ? offset : null,
      lastViewedAt: at == null ? null : at.millisecondsSinceEpoch ~/ 1000,
    );
  }

  /// A series or a season: [seen] episodes watched, capped at what the server
  /// holds — the tracker counts episodes this server may not have.
  static MediaItem _container(MediaItem item, {required int seen, DateTime? lastWatchedAt}) {
    final total = item.leafWatchTotal;
    final viewed = total == null ? seen : (seen > total ? total : seen);
    return item.copyWith(
      viewedLeafCount: viewed,
      viewCount: total != null && viewed >= total ? 1 : 0,
      viewOffsetMs: null,
      lastViewedAt: viewed > 0 && lastWatchedAt != null ? lastWatchedAt.millisecondsSinceEpoch ~/ 1000 : null,
    );
  }
}
