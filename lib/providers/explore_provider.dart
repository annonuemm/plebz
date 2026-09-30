import 'dart:async';

import 'package:flutter/foundation.dart';

import '../i18n/strings.g.dart';
import '../media/media_backend.dart';
import '../media/media_hub.dart';
import '../media/year_filter.dart';
import '../services/settings_service.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../models/seerr/seerr_brand.dart';
import '../models/seerr/seerr_genre.dart';
import '../mixins/disposable_change_notifier_mixin.dart';
import '../services/catalog/catalog_source.dart';
import '../services/catalog/plex_catalog_source.dart';
import '../services/catalog/seerr_catalog_source.dart';
import '../services/trackers/future_coalescer.dart';
import '../utils/app_logger.dart';
import 'catalog_sources_provider.dart';

enum ExploreLoadState { initial, loading, loaded, error }

/// One rendered Explore shelf, backed by either a fixed catalog row or a
/// provider-defined hub.
class ExploreRowHub {
  final CatalogRowId? row;
  final String? providerHubId;
  final CatalogHubStyle? style;
  final int? totalResults;
  final MediaHub hub;

  const ExploreRowHub.catalogRow({required CatalogRowId this.row, required this.hub, this.totalResults})
    : providerHubId = null,
      style = null;

  const ExploreRowHub.providerHub({
    required String this.providerHubId,
    required this.hub,
    this.style,
    this.totalResults,
  }) : row = null;

  const ExploreRowHub._({this.row, this.providerHubId, this.style, this.totalResults, required this.hub});

  /// The same row with different contents — the year filter thins a row's
  /// items without changing what the row is or where it leads.
  ExploreRowHub copyWithHub(MediaHub hub) =>
      ExploreRowHub._(row: row, providerHubId: providerHubId, style: style, totalResults: totalResults, hub: hub);
}

/// Owns the Explore tab's fixed rows and provider-defined hubs, converted to
/// [MediaHub]s so the existing shelf stack renders them.
///
/// Lives inside the profile-keyed provider subtree. Listens to
/// [CatalogSourcesProvider] for the active source (connect/disconnect/switch)
/// and to the source's watchlist changes so the Watchlist row stays current
/// after mutations from anywhere in the app.
class ExploreProvider extends ChangeNotifier with DisposableChangeNotifierMixin {
  /// Rows reload when the tab is shown after this long.
  static const Duration staleAfter = Duration(minutes: 15);
  static const int rowLimit = 25;
  static const int viewAllPageLimit = 100;
  static const int viewAllMaxPages = 3;

  /// Watchlist mutations notify optimistically before the API call finishes;
  /// the row refetch waits out the burst so it reads settled server state.
  static const Duration _watchlistRefreshDelay = Duration(seconds: 1);

  ExploreProvider(this._catalogSources) {
    _catalogSources.addListener(_onSourcesChanged);
    _source = _catalogSources.activeSource;
    _source?.watchlistChanges.addListener(_onWatchlistChanged);
  }

  final CatalogSourcesProvider _catalogSources;
  CatalogSource? _source;

  Map<CatalogRowId, CatalogPage> _rows = {};
  List<CatalogHub> _providerHubs = const [];

  /// Seerr's genres, for the shelf of genre tiles. Empty for every other
  /// source: no one else serves them.
  List<SeerrGenre> _genres = const [];

  /// The same for series, used only to tell whether a genre tile can offer a
  /// series tab at all — the two lists do not hold the same genres.
  List<SeerrGenre> _tvGenres = const [];
  ExploreLoadState _state = ExploreLoadState.initial;
  String? _errorMessage;
  DateTime? _loadedAt;
  final FutureCoalescer<void> _loadCoalescer = FutureCoalescer();
  int _generation = 0;
  Timer? _watchlistRefreshTimer;

  // Watchlist-row freshness: every membership change bumps the mutation
  // epoch; a successful row refetch records which epoch it covered. A tab
  // re-shown with uncovered mutations refetches immediately — the debounced
  // timer alone can lose the race when the user navigates back quickly.
  int _watchlistMutationEpoch = 0;
  int _watchlistRowFetchedEpoch = 0;
  int _watchlistHubRetryEpoch = -1;
  final FutureCoalescer<void> _watchlistRefreshCoalescer = FutureCoalescer();

  List<ExploreRowHub>? _hubsCache;
  (int, String)? _hubsCacheKey;
  int _rowsEpoch = 0;

  CatalogSource? get activeSource => _source;

  ExploreLoadState get state => _state;

  bool get isLoading => _state == ExploreLoadState.initial || _state == ExploreLoadState.loading;

  /// Raw load failure (unlocalized); the screen wraps it for display.
  String? get errorMessage => _errorMessage;

  /// Non-empty rows of the active source in display order. Memoized on row
  /// content (and one localized string, so a locale change busts the cache).
  List<ExploreRowHub> get rowHubs {
    final source = _source;
    if (source == null) return const [];
    final key = (_rowsEpoch, rowTitle(CatalogRowId.watchlist));
    if (_hubsCache != null && key == _hubsCacheKey) return _hubsCache!;
    final hubs = <ExploreRowHub>[
      for (final row in source.supportedRows)
        if (_rows[row] case final CatalogPage page)
          if (page.items.isNotEmpty)
            ExploreRowHub.catalogRow(
              row: row,
              totalResults: page.totalResults,
              hub: MediaHub(
                id: 'explore:${source.id.name}:${row.name}',
                identifier: 'explore.${row.name}',
                title: rowTitle(row),
                type: 'mixed',
                items: [for (final item in page.items) item.toMediaItem()],
                size: page.totalResults ?? page.items.length,
                more: page.hasMore,
              ),
            ),
      if (_genres.isNotEmpty)
        ExploreRowHub.providerHub(
          providerHubId: genreHubId,
          hub: MediaHub(
            id: 'explore:${source.id.name}:genres',
            identifier: 'explore.genres',
            title: t.explore.rows.genres,
            // The rail reads this to know the tiles are not titles.
            type: 'genre',
            items: genreItems(_genres),
            size: _genres.length,
            more: false,
          ),
        ),
      if (_showsBrandShelves) ...[
        ExploreRowHub.providerHub(
          providerHubId: studioHubId,
          hub: MediaHub(
            id: 'explore:${source.id.name}:studios',
            identifier: 'explore.studios',
            title: t.explore.rows.studios,
            type: 'studio',
            items: [for (final studio in kSeerrStudios) brandItem(studio, studioIdPrefix)],
            size: kSeerrStudios.length,
            more: false,
          ),
        ),
        ExploreRowHub.providerHub(
          providerHubId: networkHubId,
          hub: MediaHub(
            id: 'explore:${source.id.name}:networks',
            identifier: 'explore.networks',
            title: t.explore.rows.networks,
            type: 'network',
            items: [for (final network in kSeerrNetworks) brandItem(network, networkIdPrefix)],
            size: kSeerrNetworks.length,
            more: false,
          ),
        ),
      ],
      for (final providerHub in _providerHubs)
        if (_rendersProviderHub(providerHub) && providerHub.page.items.isNotEmpty)
          ExploreRowHub.providerHub(
            providerHubId: providerHub.id,
            style: providerHub.style,
            totalResults: providerHub.page.totalResults,
            hub: MediaHub(
              id: 'explore:${source.id.name}:hub:${providerHub.id}',
              identifier: 'explore.hub.${providerHub.id}',
              title: providerHub.title,
              type: 'mixed',
              items: [for (final item in providerHub.page.items) item.toMediaItem()],
              size: providerHub.page.totalResults ?? providerHub.page.items.length,
              more: providerHub.page.hasMore,
            ),
          ),
    ];
    final ordered = _withYearFilter(spreadTileShelves(liftNetworksUnderPopularShows(hubs), _tileShelves(source)));
    _hubsCache = ordered;
    _hubsCacheKey = key;
    return ordered;
  }

  /// Plex's own shelves of destinations — the streaming services, the genres,
  /// the awards — which Discover hands out as hubs of "titles" that are not
  /// titles. The source keeps them aside as tiles; this is where they become
  /// rows.
  List<ExploreRowHub> _tileShelves(CatalogSource source) {
    if (source is! PlexCatalogSource) return const [];
    return [
      for (final shelf in source.tileShelves)
        ExploreRowHub.providerHub(
          providerHubId: '$tileShelfIdPrefix${shelf.id}',
          hub: MediaHub(
            id: 'explore:${source.id.name}:tiles:${shelf.id}',
            identifier: 'explore.tiles.${shelf.id}',
            // Discover's own heading, which it now answers in the app's
            // language; a service shelf keeps ours, which names it better.
            title: shelf.isPlatform ? t.explore.rows.platforms : shelf.title,
            // What the rail lays the tiles out by: service logos are square
            // artwork, a genre, an award or a decade is a word on a pill.
            type: shelf.isPlatform ? 'platform' : 'chip',
            items: [for (final tile in shelf.tiles) tileItem(tile)],
            size: shelf.tiles.length,
            more: false,
          ),
        ),
    ];
  }

  /// Spread [shelves] through [hubs] rather than stacking them at one end.
  ///
  /// Plex's own page alternates them with the rows of titles, and for good
  /// reason: three shelves of tiles in a row read as a settings page, and all
  /// of them at the bottom is where nobody scrolls. The first goes second —
  /// the row before anything else should be titles a viewer can start — and
  /// the rest follow every few rows.
  @visibleForTesting
  static List<ExploreRowHub> spreadTileShelves(List<ExploreRowHub> hubs, List<ExploreRowHub> shelves) {
    if (shelves.isEmpty) return hubs;
    final spread = List<ExploreRowHub>.of(hubs);
    var at = 1;
    for (final shelf in shelves) {
      spread.insert(at.clamp(0, spread.length), shelf);
      at += 4;
    }
    return spread;
  }

  /// Marks a tile shelf among the provider hubs.
  static const String tileShelfIdPrefix = 'plex:tiles:';

  static const String sectionKeyPrefix = 'plex:section:';

  /// A destination as a shelf entry: its name, its picture where it has one,
  /// and an id carrying the section a tap opens.
  static MediaItem tileItem(PlexTile tile) => MediaItem(
    id: '$sectionKeyPrefix${tile.sectionKey}',
    backend: MediaBackend.plex,
    kind: MediaKind.unknown,
    title: tile.title,
    artPath: tile.imageUrl,
  );

  /// The Discover section [item] opens, or null when it is an ordinary title.
  static String? sectionKeyOf(MediaItem item) =>
      item.id.startsWith(sectionKeyPrefix) ? item.id.substring(sectionKeyPrefix.length) : null;

  /// The rows with the year ranges applied, where the setting reaches beyond
  /// the libraries. Tile shelves are left alone: a genre or a service is not
  /// a title and has no year to judge.
  List<ExploreRowHub> _withYearFilter(List<ExploreRowHub> rows) {
    final settings = SettingsService.instanceOrNull;
    if (settings == null) return rows;
    final movies = settings.movieYearRangeBeyondLibraries;
    final shows = settings.showYearRangeBeyondLibraries;
    if (movies.isEmpty && shows.isEmpty) return rows;
    return [
      for (final row in rows)
        if (applyYearFilterToHub(row.hub, movies: movies, shows: shows) case final hub when hub.items.isNotEmpty)
          row.hub == hub ? row : row.copyWithHub(hub),
    ];
  }

  /// Put the streaming-service shelf directly under "Popular series".
  ///
  /// It is built with the other tile shelves at the end, which is where the
  /// genres and studios belong — but a viewer looking for something to watch
  /// reaches for a service far more often than for a genre, and a shelf four
  /// rows down is a shelf nobody sees. Leaves the list alone when either row
  /// is missing.
  @visibleForTesting
  static List<ExploreRowHub> liftNetworksUnderPopularShows(List<ExploreRowHub> hubs) {
    final networkIndex = hubs.indexWhere((entry) => entry.providerHubId == networkHubId);
    final popularIndex = hubs.indexWhere((entry) => entry.row == CatalogRowId.popularShows);
    if (networkIndex < 0 || popularIndex < 0 || networkIndex == popularIndex + 1) return hubs;

    final reordered = List<ExploreRowHub>.of(hubs);
    final networks = reordered.removeAt(networkIndex);
    final target = reordered.indexWhere((entry) => entry.row == CatalogRowId.popularShows) + 1;
    reordered.insert(target, networks);
    return reordered;
  }

  /// Identifies the genre shelf among the provider hubs.
  static const String genreHubId = 'seerr:genres';

  /// Identifies the studio and network shelves among the provider hubs.
  static const String studioHubId = 'seerr:studios';
  static const String networkHubId = 'seerr:networks';

  /// `studio:2` / `network:213` for a brand tile, null for an ordinary title.
  ///
  /// Names the tile a spotlight has to stand in for: a logo on a flat card is
  /// no backdrop, so those tiles borrow one from a title of their own.
  static String? brandKeyOf(MediaItem item) {
    if (studioIdOf(item) case final id?) return 'studio:$id';
    if (networkIdOf(item) case final id?) return 'network:$id';
    return null;
  }

  static const String studioIdPrefix = 'seerr:studio:';
  static const String networkIdPrefix = 'seerr:network:';

  /// The two fixed shelves ride along with a loaded Seerr page: they need no
  /// request of their own, but on their own — beside nothing else — they would
  /// suggest the page had loaded when it had not.
  bool get _showsBrandShelves => _source is SeerrCatalogSource && _rows.isNotEmpty;

  /// A studio or network as a shelf entry, its id carrying what a tap needs.
  ///
  /// [idPrefix] also says which of the two it is, and so which endpoint the
  /// tap asks: [studioIdPrefix] films, [networkIdPrefix] series.
  static MediaItem brandItem(SeerrBrand brand, String idPrefix) => MediaItem(
    id: '$idPrefix${brand.id}',
    backend: MediaBackend.plex,
    kind: MediaKind.unknown,
    title: brand.name,
    artPath: brand.logoUrl(),
  );

  /// The studio id in [item], or null when it is not a studio tile.
  static int? studioIdOf(MediaItem item) => _idAfter(item, studioIdPrefix);

  /// The network id in [item], or null when it is not a network tile.
  static int? networkIdOf(MediaItem item) => _idAfter(item, networkIdPrefix);

  static int? _idAfter(MediaItem item, String prefix) =>
      item.id.startsWith(prefix) ? int.tryParse(item.id.substring(prefix.length)) : null;

  /// The genre shelf, each tile behind a different picture.
  ///
  /// Films carry several genres, so the same title is offered as artwork for
  /// several of them and a plain "take the first" leaves the row showing one
  /// picture two or three times. Each tile takes the first of its own
  /// backdrops that no earlier tile took; a genre whose every candidate is
  /// spoken for keeps its first, which still beats no picture at all.
  List<MediaItem> genreItems(List<SeerrGenre> genres) {
    final used = <String>{};
    return [
      for (final genre in genres)
        genreItem(
          genre,
          genre.backdrops.firstWhere((path) => used.add(path), orElse: () => genre.backdrops.firstOrNull ?? ''),
        ),
    ];
  }

  /// A genre as a shelf entry.
  ///
  /// The id carries what a tap needs — the film genre, and the series genre
  /// where one exists — because the shelf speaks in [MediaItem]s and a genre
  /// is not one. Everything else on the tile comes from the name and the
  /// backdrop the shelf picked for it.
  MediaItem genreItem(SeerrGenre genre, String backdrop) {
    final tvId = tvGenreIdFor(genre.id);
    return MediaItem(
      id: '$genreIdPrefix${genre.id}${tvId == null ? '' : ':$tvId'}',
      backend: MediaBackend.plex,
      kind: MediaKind.unknown,
      title: genre.name,
      artPath: backdrop.isEmpty ? null : SeerrCatalogSource.tmdbImageUrl(backdrop, 'w780'),
    );
  }

  static const String genreIdPrefix = 'seerr:genre:movie:';

  /// The film genre id in [item], or null when it is an ordinary title.
  static int? genreIdOf(MediaItem item) {
    if (!item.id.startsWith(genreIdPrefix)) return null;
    return int.tryParse(item.id.substring(genreIdPrefix.length).split(':').first);
  }

  /// The series genre id in [item], or null when this genre has no series
  /// counterpart — then the page shows films alone.
  static int? tvGenreIdOf(MediaItem item) {
    if (!item.id.startsWith(genreIdPrefix)) return null;
    final parts = item.id.substring(genreIdPrefix.length).split(':');
    return parts.length < 2 ? null : int.tryParse(parts[1]);
  }

  /// Series genres that carry a film genre's content under a different id.
  ///
  /// Most genres share their id across the two lists; these few do not,
  /// because the series list merges them. Matching on ids rather than on
  /// names keeps this working whatever language Seerr answers in.
  static const Map<int, int> _tvGenreForMovieGenre = {
    28: 10759, // Action -> Action & Adventure
    12: 10759, // Adventure -> Action & Adventure
    878: 10765, // Science Fiction -> Sci-Fi & Fantasy
    14: 10765, // Fantasy -> Sci-Fi & Fantasy
    10752: 10768, // War -> War & Politics
  };

  /// The series genre matching [movieGenreId], or null when there is none.
  ///
  /// A candidate only counts when Seerr actually lists it, so a wrong guess
  /// costs a missing tab rather than a page of the wrong genre.
  int? tvGenreIdFor(int movieGenreId) {
    if (_tvGenres.isEmpty) return null;
    final ids = {for (final genre in _tvGenres) genre.id};
    if (ids.contains(movieGenreId)) return movieGenreId;
    final mapped = _tvGenreForMovieGenre[movieGenreId];
    return mapped != null && ids.contains(mapped) ? mapped : null;
  }

  static bool _rendersProviderHub(CatalogHub hub) {
    // Plex's availabilityPlatforms entries are streaming services, not
    // titles, and never belong in a row of posters. The source now keeps them
    // aside as tiles and _platformShelf gives them a row of their own; this
    // stays as the guard for a hub that reaches here all the same.
    return hub.style != CatalogHubStyle.availabilityPlatforms;
  }

  static String rowTitle(CatalogRowId row) => switch (row) {
    CatalogRowId.recentlyAdded => t.discover.recentlyAdded,
    CatalogRowId.watchlist => t.explore.rows.watchlist,
    CatalogRowId.recommendedMovies => t.explore.rows.recommendedMovies,
    CatalogRowId.recommendedShows => t.explore.rows.recommendedShows,
    CatalogRowId.trendingMovies => t.explore.rows.trendingMovies,
    CatalogRowId.trendingShows => t.explore.rows.trendingShows,
    CatalogRowId.popularMovies => t.explore.rows.popularMovies,
    CatalogRowId.popularShows => t.explore.rows.popularShows,
    CatalogRowId.trendingAnime => t.explore.rows.trendingAnime,
    CatalogRowId.suggestedAnime => t.explore.rows.suggestedAnime,
    CatalogRowId.airingAnime => t.explore.rows.airingAnime,
    CatalogRowId.popularAnime => t.explore.rows.popularAnime,
    CatalogRowId.trending => t.explore.rows.trending,
    CatalogRowId.upcomingMovies => t.explore.rows.upcomingMovies,
    CatalogRowId.upcomingShows => t.explore.rows.upcomingShows,
  };

  /// Load if never loaded, after an error, or when the content has gone
  /// stale. Called on first build and every time the tab is shown.
  void ensureFresh() {
    if (_source == null) return;
    if (_state == ExploreLoadState.initial || _state == ExploreLoadState.error) {
      unawaited(load());
      return;
    }
    final loadedAt = _loadedAt;
    if (loadedAt != null && DateTime.now().difference(loadedAt) > staleAfter) {
      unawaited(load());
      return;
    }
    if (_watchlistRowFetchedEpoch < _watchlistMutationEpoch) {
      unawaited(_refreshWatchlistRow());
    }
  }

  /// Full reload of every supported row (one request per row). Concurrent
  /// calls coalesce into the in-flight pass; a source switch resets the
  /// coalescer (see [_onSourcesChanged]) so the new source's load starts
  /// instead of joining the doomed one.
  Future<void> load() => _loadCoalescer.run(_loadOnce);

  Future<void> _loadOnce() async {
    // Yield so a load() kicked off during build can't notify mid-build.
    await null;
    if (isDisposed) return;
    final source = _source;
    if (source == null) return;
    final generation = _generation;
    final mutationEpochAtStart = _watchlistMutationEpoch;

    _state = ExploreLoadState.loading;
    _errorMessage = null;
    safeNotifyListeners();

    final fetched = <CatalogRowId, CatalogPage>{};
    List<CatalogHub>? fetchedProviderHubs;
    Object? firstError;
    final CatalogHubSource? hubSource = source is CatalogHubSource ? source as CatalogHubSource : null;
    final seerr = source is SeerrCatalogSource ? source : null;
    List<SeerrGenre>? fetchedGenres;
    List<SeerrGenre>? fetchedTvGenres;
    await Future.wait<void>([
      if (seerr != null)
        () async {
          try {
            // One shelf, built from the film genres: the two lists overlap
            // heavily, and two nearly identical shelves read worse than one.
            // The series list comes along all the same — it decides which
            // tiles can offer a series tab.
            final both = await Future.wait([seerr.genres(MediaKind.movie), seerr.genres(MediaKind.show)]);
            fetchedGenres = both[0];
            fetchedTvGenres = both[1];
          } catch (e) {
            // A missing genre shelf is not worth failing the page for.
            appLogger.w('Explore: seerr genres failed', error: e);
          }
        }(),
      for (final row in source.supportedRows)
        () async {
          try {
            fetched[row] = await source.fetchRow(row, limit: rowLimit);
          } catch (e) {
            appLogger.w('Explore: ${source.id.name} row ${row.name} failed', error: e);
            firstError ??= e;
          }
        }(),
      if (hubSource != null)
        () async {
          try {
            fetchedProviderHubs = await hubSource.fetchHubs(limit: rowLimit);
          } catch (e) {
            appLogger.w('Explore: ${source.id.name} provider hubs failed', error: e);
            firstError ??= e;
          }
        }(),
    ]);
    if (isDisposed || generation != _generation) return;

    // A debounced watchlist refresh that landed while this load was in
    // flight covered later mutations than both the watchlist page and the
    // provider hubs that track it — keep the fresher versions.
    if (_watchlistRowFetchedEpoch > mutationEpochAtStart) {
      fetched.remove(CatalogRowId.watchlist);
      fetchedProviderHubs = null;
    }

    if (fetched.isEmpty && (fetchedProviderHubs == null || (fetchedProviderHubs!.isEmpty && firstError != null))) {
      // Nothing succeeded: keep stale rows if any (they beat an error flash),
      // otherwise surface the failure. A null message falls back to the
      // localized empty-state text in the screen.
      if (_rows.isEmpty && _providerHubs.isEmpty) {
        _state = ExploreLoadState.error;
        _errorMessage = firstError?.toString();
      } else {
        _state = ExploreLoadState.loaded;
      }
    } else {
      // Failed rows and hubs keep their previous content.
      _rows = {..._rows, ...fetched};
      if (fetchedProviderHubs case final hubs?) _providerHubs = hubs;
      if (fetchedGenres case final genres?) _genres = genres;
      if (fetchedTvGenres case final genres?) _tvGenres = genres;
      _state = ExploreLoadState.loaded;
      _loadedAt = DateTime.now();
      _rowsEpoch++;
      if (fetched.containsKey(CatalogRowId.watchlist) && mutationEpochAtStart > _watchlistRowFetchedEpoch) {
        _watchlistRowFetchedEpoch = mutationEpochAtStart;
      }
    }
    // Mutations that landed while the load was in flight aren't reflected in
    // the page we just stored — schedule the debounced catch-up ourselves
    // (the mutation-time notification skips rows that aren't loaded yet).
    if (_rows.containsKey(CatalogRowId.watchlist) && _watchlistRowFetchedEpoch < _watchlistMutationEpoch) {
      _scheduleWatchlistRefresh();
    }
    safeNotifyListeners();
  }

  /// Full item list for a fixed row's View All grid.
  Future<List<MediaItem>> loadAllForRow(CatalogRowId row) async {
    final source = _source;
    if (source == null) return const [];
    return _loadAllPages(row.name, (page) => source.fetchRow(row, page: page, limit: viewAllPageLimit));
  }

  /// Full item list for either a fixed row or a provider-defined hub.
  Future<List<MediaItem>> loadAllForHub(ExploreRowHub rowHub) async {
    if (rowHub.row case final row?) return loadAllForRow(row);
    final source = _source;
    final hubId = rowHub.providerHubId;
    if (source is! CatalogHubSource || hubId == null) return rowHub.hub.items;
    final hubSource = source as CatalogHubSource;
    return _loadAllPages(hubId, (page) => hubSource.fetchHub(hubId, page: page, limit: viewAllPageLimit));
  }

  Future<List<MediaItem>> _loadAllPages(String label, Future<CatalogPage> Function(int page) fetchPage) async {
    final items = <MediaItem>[];
    var page = 1;
    while (true) {
      final result = await fetchPage(page);
      items.addAll([for (final item in result.items) item.toMediaItem()]);
      if (!result.hasMore) break;
      if (page >= viewAllMaxPages) {
        appLogger.w('Explore: $label View All truncated at ${items.length} items ($page pages)');
        break;
      }
      page++;
    }
    return items;
  }

  void _onSourcesChanged() {
    final next = _catalogSources.activeSource;
    if (identical(next, _source)) return;
    _source?.watchlistChanges.removeListener(_onWatchlistChanged);
    _source = next;
    _source?.watchlistChanges.addListener(_onWatchlistChanged);
    _generation++;
    _watchlistRefreshTimer?.cancel();
    // Detach any in-flight passes for the old source: their generation guard
    // already discards their results, but the new source's load must not
    // coalesce into them (that left the tab stuck on the loading state).
    _loadCoalescer.reset();
    _watchlistRefreshCoalescer.reset();
    _watchlistMutationEpoch = 0;
    _watchlistRowFetchedEpoch = 0;
    _watchlistHubRetryEpoch = -1;
    _rows = {};
    _providerHubs = const [];
    _genres = const [];
    _tvGenres = const [];
    _loadedAt = null;
    _errorMessage = null;
    _state = ExploreLoadState.initial;
    _rowsEpoch++;
    safeNotifyListeners();
    if (next != null) unawaited(load());
  }

  void _onWatchlistChanged() {
    // Always bump: a mutation during the initial full load has no row to
    // patch yet, but the load's completion checks this epoch to catch up.
    _watchlistMutationEpoch++;
    if (!_rows.containsKey(CatalogRowId.watchlist)) return;
    _scheduleWatchlistRefresh();
  }

  void _scheduleWatchlistRefresh() {
    _watchlistRefreshTimer?.cancel();
    _watchlistRefreshTimer = Timer(_watchlistRefreshDelay, () => unawaited(_refreshWatchlistRow()));
  }

  Future<void> _refreshWatchlistRow() => _watchlistRefreshCoalescer.run(_refreshWatchlistRowOnce);

  Future<void> _refreshWatchlistRowOnce() async {
    final source = _source;
    if (source == null || isDisposed) return;
    final generation = _generation;
    final coveredEpoch = _watchlistMutationEpoch;
    CatalogPage? fetchedPage;
    List<CatalogHub>? fetchedProviderHubs;
    final CatalogHubSource? hubSource = source is CatalogHubSource ? source as CatalogHubSource : null;
    var providerHubRefreshFailed = false;
    await Future.wait<void>([
      () async {
        try {
          fetchedPage = await source.fetchRow(CatalogRowId.watchlist, limit: rowLimit);
        } catch (e) {
          appLogger.w('Explore: watchlist row refresh failed', error: e);
        }
      }(),
      if (hubSource != null)
        () async {
          try {
            fetchedProviderHubs = await hubSource.fetchHubs(limit: rowLimit);
          } catch (e) {
            appLogger.w('Explore: ${source.id.name} provider hub refresh failed', error: e);
          }
        }(),
    ]);
    providerHubRefreshFailed = hubSource != null && fetchedProviderHubs == null;
    if (isDisposed || generation != _generation) return;
    if (fetchedPage == null && fetchedProviderHubs == null) return;

    if (fetchedPage case final page?) {
      _rows = {..._rows, CatalogRowId.watchlist: page};
      if (!providerHubRefreshFailed) {
        _watchlistRowFetchedEpoch = coveredEpoch;
        _watchlistHubRetryEpoch = -1;
      }
    }
    if (fetchedProviderHubs case final hubs?) _providerHubs = hubs;
    _rowsEpoch++;
    safeNotifyListeners();

    if (fetchedPage == null) return;
    if (providerHubRefreshFailed) {
      // One automatic retry per mutation epoch avoids leaving derived hubs
      // stale without hammering an unavailable endpoint indefinitely.
      if (_watchlistHubRetryEpoch != coveredEpoch) {
        _watchlistHubRetryEpoch = coveredEpoch;
        _scheduleWatchlistRefresh();
      }
    } else if (_watchlistMutationEpoch > coveredEpoch) {
      // Mutations that arrived during this pass need one more refresh.
      _scheduleWatchlistRefresh();
    } else {
      // Fully caught up: a still-pending debounce would only refetch the same
      // state.
      _watchlistRefreshTimer?.cancel();
    }
  }

  @override
  void dispose() {
    _catalogSources.removeListener(_onSourcesChanged);
    _source?.watchlistChanges.removeListener(_onWatchlistChanged);
    _watchlistRefreshTimer?.cancel();
    super.dispose();
  }
}
