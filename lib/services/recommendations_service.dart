import 'dart:async';

import '../media/ids.dart';
import '../media/media_backend.dart';
import '../media/library_query.dart';
import '../media/media_item.dart';
import '../media/media_item_types.dart';
import '../media/media_kind.dart';
import '../media/media_library.dart';
import '../media/media_item_merge.dart' show compareLibraryCopies;
import '../media/media_search_grouping.dart' show mediaSearchTitleKey;
import '../media/media_server_client.dart';
import '../utils/app_logger.dart';
import 'multi_server_manager.dart';
import 'plex_client.dart';
import 'plex_constants.dart';

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
  /// than proportional to a big server's library list — but wide enough that
  /// a viewer with Plex and Jellyfin side by side is read on both.
  static const maxSeedLibraries = 8;

  /// How many titles are asked "what is like this".
  static const maxSeeds = 10;

  /// Of [maxSeeds], at most this many favourites and this many titles the
  /// viewer rated highly — the rest are what was watched last, so the row
  /// still follows what the viewer is into now.
  static const maxFavouriteSeeds = 3;
  static const maxRatedSeeds = 3;

  /// Of [maxSeeds], at most this many come from what is under way — the
  /// series of an episode in Continue Watching, a film half seen. For a
  /// profile that has finished nothing yet, they are all there is to go on.
  static const maxUnderWaySeeds = 3;

  /// A personal rating at or above this (of 10) makes a title a seed.
  static const ratedSeedThreshold = 8.0;

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
    List<MediaItem> excludeItems = const [],
    List<MediaItem> underWay = const [],
    RecommendationsSource source = RecommendationsSource.all,
    int limit = 20,
    int rotation = 0,
  }) async {
    final scan = await _scan(libraries, source, underWay);
    final seeds = scan.seeds;
    if (seeds.isEmpty) return const [];
    final seedKeys = {for (final seed in seeds) seed.globalKey};

    // One title is one title, whichever server holds it: a film on Plex and
    // on Jellyfin is a single entry, and a film watched on one of them is
    // watched. Identity is the copy key — kind, title and year — and an item
    // that cannot give one only ever stands for itself.
    final excluded = <String>{
      for (final seed in seeds) _copyKey(seed),
      for (final item in excludeItems) _copyKey(item),
      ...scan.dealtWith,
    };

    final related = await Future.wait([for (final seed in seeds) _relatedTo(seed)]);

    // Round-robin rather than seed-by-seed: five films that all resemble one
    // favourite would otherwise fill the row before the second seed is heard.
    //
    // [rotation] moves the whole reading — which seed speaks first, and how
    // far down each one's list the round starts. Without it the row is a pure
    // function of what has been watched, so it stands still for days at a
    // time: the same twenty titles, drawn from the top of the same lists,
    // until something is marked watched. Rotating reaches the rest of what the
    // servers already answered, at no extra request.
    final ordered = _rotated(related, rotation);
    final order = <String>[];
    final copies = <String, List<MediaItem>>{};
    final votes = <String, Set<int>>{};
    final longest = ordered.fold<int>(0, (most, items) => items.length > most ? items.length : most);
    for (var round = 0; round < longest; round++) {
      for (var list = 0; list < ordered.length; list++) {
        final items = ordered[list];
        if (round >= items.length) continue;
        // Each list is read from its own starting point and wraps, so a
        // rotation deep into a short list still offers that seed's titles
        // rather than skipping it.
        final item = items[(rotation + round) % items.length];
        if (excludeKeys.contains(item.globalKey) || seedKeys.contains(item.globalKey)) continue;
        // Watched already, started already, or not something to play at all.
        if (!(item.isMovie || item.isShow) || _dealtWith(item)) continue;
        final key = _copyKey(item);
        if (excluded.contains(key)) continue;
        (votes[key] ??= <int>{}).add(list);
        final known = copies[key];
        if (known == null) {
          order.add(key);
          copies[key] = [item];
        } else if (!known.any((copy) => copy.globalKey == item.globalKey)) {
          known.add(item);
        }
      }
    }

    // A title several of the viewer's titles point at is the better guess, so
    // it goes first; among equals the round-robin order stands, and with it
    // the rotation. The best copy is the one the row opens.
    // List.sort is not stable, so the round-robin position breaks ties.
    final position = {for (final (index, key) in order.indexed) key: index};
    final ranked = [...order]
      ..sort((a, b) {
        final byVotes = votes[b]!.length.compareTo(votes[a]!.length);
        return byVotes != 0 ? byVotes : position[a]!.compareTo(position[b]!);
      });
    final picked = [for (final key in ranked.take(limit)) (copies[key]!..sort(compareLibraryCopies)).first];

    appLogger.d('Recommendations: ${seeds.length} seeds → ${picked.length} titles (rotation $rotation)');
    return picked;
  }

  /// Watched, or under way: a film with a resume point, a series some of whose
  /// episodes are behind the viewer. Either is the middle of something, which
  /// "Continue Watching" is for, not a suggestion.
  static bool _dealtWith(MediaItem item) => item.isWatched || item.hasActiveProgress || item.isPartiallyWatched;

  static String _copyKey(MediaItem item) => mediaSearchTitleKey(item) ?? 'self:${item.globalKey}';

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

  /// The titles to reason from, and every title the scan showed to be watched
  /// or under way (by copy key, so a copy on another server counts too).
  ///
  /// One request per library, sorted by when it was last touched. The seeds
  /// are up to [maxFavouriteSeeds] favourites — the strongest statement there
  /// is — up to [maxRatedSeeds] titles the viewer rated [ratedSeedThreshold]
  /// or better, and the rest what was watched most recently, across every
  /// library rather than the first one's.
  Future<({List<MediaItem> seeds, Set<String> dealtWith})> _scan(
    List<MediaLibrary> libraries,
    RecommendationsSource source,
    List<MediaItem> underWay,
  ) async {
    // What is under way, as titles: an episode or a season stands for its
    // series. Only the backends in scope.
    final underWaySeeds = <MediaItem>[];
    for (final item in underWay) {
      if (!source.allows(item.backend)) continue;
      final seriesId = switch (item.kind) {
        MediaKind.episode => item.grandparentId,
        MediaKind.season => item.grandparentId ?? item.parentId,
        _ => null,
      };
      if (seriesId != null) {
        underWaySeeds.add(
          MediaItem(
            id: seriesId,
            backend: item.backend,
            kind: MediaKind.show,
            title: item.grandparentTitle ?? item.parentTitle ?? '',
            serverId: item.serverId,
          ),
        );
      } else if (item.isMovie || item.isShow) {
        underWaySeeds.add(item);
      }
    }

    // The libraries those titles are in come first: that is where the viewer
    // is watching, and a server with twenty libraries would otherwise be read
    // in its own order, up to the limit, possibly past all of them.
    final busy = {for (final item in underWay) ?item.libraryGlobalKey};
    final eligible = libraries.where((library) => _holdsVideo(library) && source.allows(library.backend)).toList();
    final candidates = [
      ...eligible.where((library) => busy.contains(library.globalKey)),
      ...eligible.where((library) => !busy.contains(library.globalKey)),
    ].take(maxSeedLibraries).toList();
    if (candidates.isEmpty && underWaySeeds.isEmpty) {
      return (seeds: const <MediaItem>[], dealtWith: const <String>{});
    }

    final pages = await Future.wait([for (final library in candidates) _recentlyTouched(library)]);

    final favourites = <MediaItem>[];
    final rated = <MediaItem>[];
    final watched = <MediaItem>[];
    final dealtWith = <String>{};
    for (final page in pages) {
      for (final item in page) {
        if (!(item.isMovie || item.isShow)) continue;
        if (_dealtWith(item)) dealtWith.add(_copyKey(item));
        if (item.isFavorite == true) {
          favourites.add(item);
        } else if ((item.userRating ?? 0) >= ratedSeedThreshold) {
          rated.add(item);
        } else if (item.isWatched || (item.viewCount ?? 0) > 0 || item.isPartiallyWatched) {
          watched.add(item);
        }
      }
    }
    // Most recent first across the libraries, not library by library.
    int byRecency(MediaItem a, MediaItem b) => b.recencySortKey.compareTo(a.recencySortKey);
    favourites.sort(byRecency);
    rated.sort((a, b) => (b.userRating ?? 0).compareTo(a.userRating ?? 0));
    watched.sort(byRecency);

    final seeds = <MediaItem>[];
    final seen = <String>{};
    void take(List<MediaItem> from, int most) {
      var taken = 0;
      for (final item in from) {
        if (seeds.length >= maxSeeds || taken >= most) return;
        if (!seen.add(_copyKey(item))) continue;
        seeds.add(item);
        taken++;
      }
    }

    take(favourites, maxFavouriteSeeds);
    take(underWaySeeds, maxUnderWaySeeds);
    take(rated, maxRatedSeeds);
    take(watched, maxSeeds);
    // Room left over goes to the others beyond their share.
    take(favourites, maxSeeds);
    take(underWaySeeds, maxSeeds);
    take(rated, maxSeeds);
    if (seeds.isEmpty) {
      appLogger.d(
        'Recommendations: no seeds in ${candidates.length} libraries '
        '(${pages.fold<int>(0, (sum, page) => sum + page.length)} titles scanned, ${underWay.length} under way)',
      );
    }
    return (seeds: seeds, dealtWith: dealtWith);
  }

  Future<List<MediaItem>> _recentlyTouched(MediaLibrary library) async {
    final client = _clientFor(library);
    if (client == null) return const [];
    try {
      if (client is PlexClient) {
        // Plex is asked without collections. The browse path asks for them,
        // and a library set to hide the items of a collection behind it then
        // answers "most recently watched" with collections — which are
        // neither films nor series, so a viewer with plenty of history got
        // no seed at all. The type keeps the answer to the library's titles.
        final type = PlexMetadataType.forKind(library.kind);
        final page = await client.fetchLibraryPage(
          library.id,
          start: 0,
          size: seedScanLimit,
          filters: {'sort': 'lastViewedAt:desc', 'includeCollections': '0', 'type': ?type?.toString()},
        );
        return page.items;
      }
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
