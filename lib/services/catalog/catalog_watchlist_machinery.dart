import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../media/media_kind.dart';
import '../../models/catalog/catalog_item.dart';
import '../../utils/app_logger.dart';
import '../trackers/future_coalescer.dart';
import 'catalog_source.dart';

/// One snapshot page of watchlist membership: each group holds every key
/// form of a single watchlist entry.
typedef WatchlistKeyPage = ({List<List<String>> groups, bool hasMore});

/// Shared watchlist snapshot + optimistic-mutation machinery behind the
/// watchlist half of [CatalogSource] (Trakt, MAL). Implementations supply
/// key derivation, the snapshot page fetch, and the actual mutation call.
///
/// The snapshot maps every key form of an entry to the entry's full key
/// group, so a mutation carrying only a subset of the entry's id forms (a
/// media-detail remove works from server-resolved external ids, which lack
/// Trakt's trakt/slug forms) still drops the WHOLE entry. With a flat key
/// set, the sibling keys survived a remove and any-match membership stayed
/// true for the rest of the session.
mixin CatalogWatchlistMachinery {
  final WatchlistChangeNotifier _watchlistChanges = WatchlistChangeNotifier();
  // Coalesces the membership-snapshot load; distinct from Simkl's own all-items coalescer (`_simklAllItemsLoad`).
  final FutureCoalescer<void> _watchlistLoad = FutureCoalescer();
  Map<String, Set<String>>? _watchlistKeyGroups;

  // ---------- Contract ----------

  /// Log prefix naming the source and its list, e.g. `Trakt: watchlist`.
  String get watchlistLogLabel;

  /// Full-snapshot paging bounds.
  int get watchlistPageLimit;
  int get watchlistMaxPages;

  /// Every membership key form of [ids], namespaced by [kind]. Sources with
  /// different identity rules (MAL and AniList) override this.
  List<String> membershipKeysFor(MediaKind kind, CatalogItemIds ids) => [
    for (final key in ids.allKeys) '${kind.id}/$key',
  ];

  /// One page of the snapshot as key groups (one group per entry).
  Future<WatchlistKeyPage> fetchWatchlistKeyPage(int page, int limit);

  /// Resolve [ids] to the concrete forms the mutation call needs (MAL maps
  /// external ids to a MAL id via Fribb). Throw when the item cannot exist
  /// in this source's domain. Default: pass-through.
  Future<CatalogItemIds> resolveWatchlistMutationIds(MediaKind kind, CatalogItemIds ids, {String? title}) async => ids;

  /// The actual API mutation for the resolved [ids].
  ///
  /// The snapshot is loaded once per session, so a removal must not trust it:
  /// where the service's delete takes more than the watchlist entry with it
  /// (MAL, AniList and Simkl drop the whole list entry), re-read the entry's
  /// current state first and leave anything no longer on the watchlist alone,
  /// calling [reloadWatchlistSnapshot] since the snapshot has proven stale.
  Future<void> performWatchlistMutation(MediaKind kind, CatalogItemIds ids, {required bool add});

  // ---------- CatalogSource watchlist surface ----------

  Listenable get watchlistChanges => _watchlistChanges;

  /// Load failures are logged and swallowed: membership stays unknown
  /// (null) and the next call retries — every UI call site fires this
  /// unawaited, so a flaky request must not become an uncaught error.
  Future<void> ensureWatchlistLoaded() {
    if (_watchlistKeyGroups != null) return Future.value();
    return _watchlistLoad.run(_loadWatchlistSnapshot);
  }

  Future<void> _loadWatchlistSnapshot() async {
    try {
      final map = <String, Set<String>>{};
      var page = 1;
      while (true) {
        final res = await fetchWatchlistKeyPage(page, watchlistPageLimit);
        for (final group in res.groups) {
          final shared = group.toSet();
          for (final key in shared) {
            map[key] = shared;
          }
        }
        if (!res.hasMore) break;
        if (page >= watchlistMaxPages) {
          appLogger.w('$watchlistLogLabel snapshot truncated at ${map.length} keys ($page pages)');
          break;
        }
        page++;
      }
      _watchlistKeyGroups = map;
      // A fresh list settles what it agrees with, and what has waited long
      // enough. What it contradicts within the window is kept: a provider that
      // takes a while to show an addition (Plex does) would otherwise take the
      // mark away again until it caught up.
      final now = watchlistClock();
      _localMembership.removeWhere(
        (key, mine) => map.containsKey(key) == mine.value || now.difference(mine.at) >= localMembershipWindow,
      );
      _watchlistChanges.notify();
    } catch (e) {
      appLogger.w('$watchlistLogLabel snapshot load failed', error: e);
    }
  }

  /// What this session did to the list, whatever the snapshot says — or fails
  /// to say.
  ///
  /// The snapshot is a whole-list read and can be refused for its own reasons
  /// (Plex Discover answers 504 often enough to be ordinary). Without this a
  /// title the user just added came back unknown: no mark on it, and the next
  /// press offered to add it again. What we did ourselves is known even when
  /// the list is not.
  final Map<String, ({bool value, DateTime at})> _localMembership = {};

  /// How long our own record outranks a list that contradicts it.
  ///
  /// Long enough to cover a provider that takes its time showing an addition —
  /// Plex does — and short enough that a record which is simply wrong (the
  /// title removed on another device) cannot outlive the wait. After this the
  /// provider has the last word.
  static const Duration localMembershipWindow = Duration(minutes: 10);

  /// Overridable so a test can age a record without waiting for the clock.
  @visibleForTesting
  DateTime Function() watchlistClock = DateTime.now;

  /// Drop the snapshot and load it afresh; for a source that found the service
  /// disagreeing with it. Membership reads as unknown until the reload lands.
  @protected
  void reloadWatchlistSnapshot() {
    _watchlistKeyGroups = null;
    unawaited(ensureWatchlistLoaded());
  }

  bool? isOnWatchlist(MediaKind kind, CatalogItemIds ids) {
    final keys = membershipKeysFor(kind, ids);
    final now = watchlistClock();
    for (final key in keys) {
      if (_localMembership[key] case final mine?) {
        if (now.difference(mine.at) < localMembershipWindow) return mine.value;
        _localMembership.remove(key);
      }
    }
    final map = _watchlistKeyGroups;
    if (map == null) return null;
    return keys.any(map.containsKey);
  }

  Future<void> addToWatchlist(MediaKind kind, CatalogItemIds ids, {String? title}) =>
      _mutateWatchlist(kind, ids, add: true, title: title);

  Future<void> removeFromWatchlist(MediaKind kind, CatalogItemIds ids, {String? title}) =>
      _mutateWatchlist(kind, ids, add: false, title: title);

  Future<void> _mutateWatchlist(MediaKind kind, CatalogItemIds ids, {required bool add, String? title}) async {
    final resolved = await resolveWatchlistMutationIds(kind, ids, title: title);
    final keys = membershipKeysFor(kind, resolved);

    // Remembered whether or not there is a snapshot to flip: this is the only
    // record when the whole-list read failed, and it is what puts the mark on
    // the title the user just acted on.
    final previousLocal = {for (final key in keys) key: _localMembership[key]};
    final stampedAt = watchlistClock();
    for (final key in keys) {
      _localMembership[key] = (value: add, at: stampedAt);
    }

    // Optimistic: flip the snapshot first so UI toggles instantly; revert on
    // failure. Callers surface the rethrown error.
    final map = _watchlistKeyGroups;
    Set<String>? addedGroup;
    List<Set<String>>? removedGroups;
    var changed = false;
    if (map != null && keys.isNotEmpty) {
      if (add) {
        addedGroup = keys.toSet();
        for (final key in addedGroup) {
          map[key] = addedGroup;
        }
        changed = true;
      } else {
        removedGroups = _takeGroups(map, keys);
        changed = removedGroups.isNotEmpty;
      }
    }
    // One notification for the one change, whether it landed in the snapshot,
    // in our own record, or in both.
    if (changed || keys.isNotEmpty) _watchlistChanges.notify();

    try {
      await performWatchlistMutation(kind, resolved, add: add);
    } catch (_) {
      previousLocal.forEach((key, was) {
        if (was == null) {
          _localMembership.remove(key);
        } else {
          _localMembership[key] = was;
        }
      });
      var reverted = keys.isNotEmpty;

      // Revert only if the snapshot wasn't replaced by a reload meanwhile.
      if (changed && identical(map, _watchlistKeyGroups)) {
        if (addedGroup != null) {
          for (final key in addedGroup) {
            if (identical(map![key], addedGroup)) map.remove(key);
          }
        }
        for (final group in removedGroups ?? const <Set<String>>[]) {
          for (final key in group) {
            map![key] = group;
          }
        }
        reverted = true;
      }
      if (reverted) _watchlistChanges.notify();
      rethrow;
    }
    // The optimistic notify above (if any — none without a loaded snapshot,
    // or for an entry the snapshot already agreed on) reached listeners before
    // the service had the change. Listeners that read the service itself, like
    // the Watchlist row, need to hear once it has.
    _watchlistChanges.notify();
  }

  /// Remove every entry group hit by [keys] from [map], returning them for
  /// a potential revert.
  static List<Set<String>> _takeGroups(Map<String, Set<String>> map, Iterable<String> keys) {
    final groups = <Set<String>>[];
    for (final key in keys) {
      final group = map[key];
      if (group != null && !groups.any((existing) => identical(existing, group))) {
        groups.add(group);
      }
    }
    for (final group in groups) {
      group.forEach(map.remove);
    }
    return groups;
  }

  /// Call from the source's [CatalogSource.dispose].
  void disposeWatchlistMachinery() {
    _watchlistChanges.dispose();
  }
}
