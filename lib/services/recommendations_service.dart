import 'dart:async';

import '../media/ids.dart';
import '../media/media_backend.dart';
import '../media/library_query.dart';
import '../media/media_item.dart';
import '../media/media_item_types.dart';
import '../media/media_kind.dart';
import '../media/media_library.dart';
import '../media/media_server_client.dart';
import '../utils/app_logger.dart';
import 'multi_server_manager.dart';

/// Which servers the recommendation row is allowed to draw on.
///
/// Named by backend rather than by server: someone running Plex and Jellyfin
/// side by side usually wants one of the two shelves, not one of five servers,
/// and a backend that is not connected simply contributes nothing.
enum RecommendationsSource {
  all,
  plex,
  jellyfin,
  emby;

  /// Whether a library on [backend] may be used.
  bool allows(MediaBackend backend) => switch (this) {
    RecommendationsSource.all => true,
    RecommendationsSource.plex => backend == MediaBackend.plex,
    RecommendationsSource.jellyfin => backend == MediaBackend.jellyfin,
    RecommendationsSource.emby => backend == MediaBackend.emby,
  };
}

/// "Because you watched" for the home screen, built out of the user's own
/// libraries.
///
/// Two steps, both on machinery that already exists: a handful of titles the
/// viewer has watched or marked as a favourite become the seed, and each seed
/// is handed to its server's own "more like this" ([MediaServerClient.fetchRelatedHubs],
/// the same call behind the detail page's related row). What comes back is
/// merged, and anything the viewer has already dealt with is dropped.
///
/// Only titles that are actually on a server can appear — the related endpoints
/// answer out of the library, never out of a catalog. A row on the home screen
/// is a row of things to press play on; looking for what one does *not* own is
/// what the Explore tab is for.
class RecommendationsService {
  /// How many libraries are consulted for seeds. The whole row is a courtesy
  /// pass after the page is already up, so its request count is bounded rather
  /// than proportional to a big server's library list.
  static const maxSeedLibraries = 3;

  /// How many titles are asked "what is like this".
  static const maxSeeds = 5;

  /// How far down each library's recently-touched list to look for seeds.
  static const seedScanLimit = 20;

  final MultiServerManager _serverManager;

  RecommendationsService(this._serverManager);

  /// Recommendations across [libraries], best first, or empty when there is
  /// nothing to go on.
  ///
  /// [excludeKeys] are global keys the caller already shows elsewhere — the
  /// Continue Watching row, above all: recommending what is already one row up
  /// is not a recommendation.
  Future<List<MediaItem>> recommend({
    required List<MediaLibrary> libraries,
    Set<String> excludeKeys = const {},
    RecommendationsSource source = RecommendationsSource.all,
    int limit = 20,
    int rotation = 0,
  }) async {
    final seeds = await _seeds(libraries, source);
    if (seeds.isEmpty) return const [];

    final seedKeys = {for (final seed in seeds) seed.globalKey};
    final related = await Future.wait([for (final seed in seeds) _relatedTo(seed)]);

    // Round-robin rather than seed-by-seed: five films that all resemble one
    // favourite would otherwise fill the row before the second seed is heard.
    //
    // [rotation] moves the whole reading — which seed speaks first, and how
    // far down each one's list the round starts. Without it the row is a pure
    // function of what has been watched, so it stands still for days at a
    // time: the same twenty titles, drawn from the top of the same five lists,
    // until something is marked watched. Rotating reaches the rest of what the
    // servers already answered, at no extra request.
    final ordered = _rotated(related, rotation);
    final picked = <MediaItem>[];
    final seen = <String>{};
    for (var round = 0; picked.length < limit; round++) {
      var offered = false;
      for (final items in ordered) {
        if (items.isEmpty) continue;
        if (round >= items.length) continue;
        offered = true;
        // Each list is read from its own starting point and wraps, so a
        // rotation deep into a short list still offers that seed's titles
        // rather than skipping it.
        final item = items[(rotation + round) % items.length];
        final key = item.globalKey;
        if (!seen.add(key)) continue;
        if (seedKeys.contains(key) || excludeKeys.contains(key)) continue;
        // Watched already, or not something to play at all.
        if (item.isWatched || !(item.isMovie || item.isShow)) continue;
        picked.add(item);
        if (picked.length >= limit) break;
      }
      if (!offered) break;
    }

    appLogger.d('Recommendations: ${seeds.length} seeds → ${picked.length} titles (rotation $rotation)');
    return picked;
  }

  /// The seeds' lists, with which one speaks first moved along by [rotation].
  ///
  /// The starting point inside each list is not enough on its own: the first
  /// seed's pick would still open the row every time, and that pick is the
  /// most-recently-watched title's nearest neighbour — the one the viewer is
  /// most likely to have seen already.
  static List<List<MediaItem>> _rotated(List<List<MediaItem>> lists, int rotation) {
    if (lists.length < 2) return lists;
    final offset = rotation % lists.length;
    if (offset == 0) return lists;
    return [...lists.sublist(offset), ...lists.sublist(0, offset)];
  }

  /// Which reading of the row this moment gets.
  ///
  /// Three hours: long enough that the row is not a slot machine — it must
  /// hold still while somebody walks along it, and through an evening's
  /// viewing — and short enough that a television switched on morning and
  /// night never shows the same twenty titles twice.
  static const rotationPeriod = Duration(hours: 3);

  static int rotationAt(DateTime now) => now.millisecondsSinceEpoch ~/ rotationPeriod.inMilliseconds;

  /// The titles to reason from: what the viewer marked, and what they watched.
  ///
  /// One request per library, sorted by when it was last touched, and the
  /// seeds are read out of that. A favourite ranks above a merely-watched
  /// title — it is the stronger statement of the two.
  Future<List<MediaItem>> _seeds(List<MediaLibrary> libraries, RecommendationsSource source) async {
    final candidates = libraries
        .where((library) => _holdsVideo(library) && source.allows(library.backend))
        .take(maxSeedLibraries)
        .toList();
    if (candidates.isEmpty) return const [];

    final pages = await Future.wait([for (final library in candidates) _recentlyTouched(library)]);

    final favourites = <MediaItem>[];
    final watched = <MediaItem>[];
    for (final page in pages) {
      for (final item in page) {
        if (!(item.isMovie || item.isShow)) continue;
        if (item.isFavorite == true) {
          favourites.add(item);
        } else if (item.isWatched || (item.viewCount ?? 0) > 0) {
          watched.add(item);
        }
      }
    }

    final seeds = <MediaItem>[];
    final seen = <String>{};
    for (final item in [...favourites, ...watched]) {
      if (!seen.add(item.globalKey)) continue;
      seeds.add(item);
      if (seeds.length >= maxSeeds) break;
    }
    return seeds;
  }

  Future<List<MediaItem>> _recentlyTouched(MediaLibrary library) async {
    final client = _clientFor(library);
    if (client == null) return const [];
    try {
      final page = await client.fetchLibraryPagedContent(
        library.id,
        query: const LibraryQuery(
          limit: seedScanLimit,
          sort: LibrarySort(field: 'lastViewedAt'),
        ),
        libraryKind: library.kind,
      );
      return page.items;
    } catch (error, stackTrace) {
      appLogger.d('Recommendations: seed scan failed on ${library.title}', error: error, stackTrace: stackTrace);
      return const [];
    }
  }

  Future<List<MediaItem>> _relatedTo(MediaItem seed) async {
    final serverId = serverIdOrNull(seed.serverId);
    final client = serverId == null ? null : _serverManager.getClient(serverId);
    if (client == null) return const [];
    try {
      final hubs = await client.fetchRelatedHubs(seed.id);
      return [for (final hub in hubs) ...hub.items];
    } catch (error, stackTrace) {
      appLogger.d('Recommendations: related lookup failed for ${seed.globalKey}', error: error, stackTrace: stackTrace);
      return const [];
    }
  }

  MediaServerClient? _clientFor(MediaLibrary library) {
    final serverId = serverIdOrNull(library.serverId);
    return serverId == null ? null : _serverManager.getClient(serverId);
  }

  /// Music and photo libraries have nothing to contribute to a row of things
  /// to watch.
  static bool _holdsVideo(MediaLibrary library) =>
      library.kind == MediaKind.movie || library.kind == MediaKind.show || library.kind == MediaKind.unknown;
}
