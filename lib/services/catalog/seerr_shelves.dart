import '../../i18n/strings.g.dart';
import '../../media/media_kind.dart';
import '../../models/catalog/catalog_item.dart';
import '../../models/catalog/catalog_metadata.dart';
import 'catalog_source.dart';
import 'seerr_catalog_source.dart';

/// One row of a Seerr studio, network or genre page.
///
/// The rows exist because Seerr's dedicated `/discover/movies/studio/{id}` and
/// `/discover/tv/network/{id}` routes take nothing but a page number: every
/// shelf built on them would be the same list in the same order. The parent
/// discover routes carry the studio or network as a *filter*, which leaves
/// `sortBy` and the date window free — and those are what tell one row from
/// the next.
class SeerrShelf {
  /// Stable within a page, so the grid behind a row keeps its own cache.
  final String id;
  final String title;
  final MediaKind kind;

  /// One page of this row, 1-based the way Seerr counts.
  final Future<CatalogPage> Function(int page) load;

  /// Set on the "everything" row only: one entry per kind this studio,
  /// network or genre has. Its "view all" opens them as a tabbed page rather
  /// than a single grid — the row stands for the whole list, and the whole
  /// list has two halves.
  final List<SeerrShelf>? tabs;

  const SeerrShelf({required this.id, required this.title, required this.kind, required this.load, this.tabs});
}

/// Match a brand tile to one of the streaming services the instance offers.
///
/// By name rather than by a hardcoded id: the ids are TMDB's and differ per
/// region, so they are asked for. The names differ in punctuation and in the
/// company's full title — "Disney+" against "Disney Plus", "Prime Video"
/// against "Amazon Prime Video" — so both sides are stripped to letters and
/// digits before they are compared, and a name that contains the other counts.
///
/// Returns null rather than a near miss: a wrong provider fills the row with
/// somebody else's catalog, which is worse than an absent row.
int? matchWatchProvider(String brand, List<({int id, String name})> providers) {
  final wanted = _normalizeProviderName(brand);
  if (wanted.isEmpty) return null;

  for (final provider in providers) {
    if (_normalizeProviderName(provider.name) == wanted) return provider.id;
  }
  for (final provider in providers) {
    final name = _normalizeProviderName(provider.name);
    if (name.contains(wanted) || wanted.contains(name)) return provider.id;
  }
  return null;
}

String _normalizeProviderName(String name) =>
    name.toLowerCase().replaceAll('+', 'plus').replaceAll('&', 'and').replaceAll(RegExp(r'[^a-z0-9]'), '');

/// What one Seerr discover page holds. Fixed by the server, not a preference.
const int seerrPageSize = 20;

/// Vote floor for the best-rated row.
///
/// Without it the row is a parade of titles with a single ten-point vote:
/// TMDB's average is unweighted, so one enthusiast outranks a classic.
const seerrTopRatedVoteFloor = 200;

/// How many pages the "something you already have" row will look through
/// before giving up. Availability is sparse in a catalog of thousands, and
/// this row is a courtesy, not a search.
const seerrAvailableScanPages = 3;

/// The rows for a studio (films), a network (series) or a genre (both).
///
/// [now] fixes the date window, so the same call on the same day builds the
/// same rows — and a test can ask for a specific day.
List<SeerrShelf> seerrShelvesFor({
  required SeerrCatalogSource source,
  required DateTime now,
  int? studioId,
  int? networkId,
  int? movieGenreId,
  int? tvGenreId,

  /// A network's films: Seerr filters films by studio and series by network,
  /// and a streaming service is a network. TMDB's "available at" filter is the
  /// one that spans both, so a network's film rows go through it.
  int? movieWatchProviderId,
  String? watchRegion,
  int rotation = 0,
}) {
  final today = _isoDate(now);
  final shelves = <SeerrShelf>[];

  void addMovieShelves({int? studio, int? genre, int? watchProvider}) {
    Future<CatalogPage> movies(int page, {String? sortBy, String? gte, String? lte, int? votes}) =>
        source.discoverMoviesPage(
          page: page,
          studio: studio,
          genre: genre,
          sortBy: sortBy,
          releaseDateGte: gte,
          releaseDateLte: lte,
          voteCountGte: votes,
          watchProviders: watchProvider,
          watchRegion: watchProvider == null ? null : watchRegion,
        );

    shelves.addAll([
      SeerrShelf(
        id: 'movie:popular',
        title: t.seerr.shelfPopularMovies,
        kind: MediaKind.movie,
        load: (page) => movies(page, sortBy: 'popularity.desc'),
      ),
      SeerrShelf(
        id: 'movie:recent',
        title: t.seerr.shelfRecentMovies,
        kind: MediaKind.movie,
        // Released, not merely dated: without the cap the row fills with
        // announcements years out, sorted newest first.
        load: (page) => movies(page, sortBy: 'primary_release_date.desc', lte: today),
      ),
      SeerrShelf(
        id: 'movie:upcoming',
        title: t.seerr.shelfUpcomingMovies,
        kind: MediaKind.movie,
        load: (page) => movies(page, sortBy: 'primary_release_date.asc', gte: today),
      ),
      SeerrShelf(
        id: 'movie:top',
        title: t.seerr.shelfTopRatedMovies,
        kind: MediaKind.movie,
        load: (page) => movies(page, sortBy: 'vote_average.desc', votes: seerrTopRatedVoteFloor),
      ),
      SeerrShelf(
        id: 'movie:available',
        // Named per kind: a genre page carries both, and two rows with the
        // same name are two rows nobody can tell apart.
        title: t.seerr.shelfAvailableMovies,
        kind: MediaKind.movie,
        load: (page) => _availablePage(
          (p) => movies(p, sortBy: 'popularity.desc'),
          page: page,
          rotation: rotation,
        ),
      ),
    ]);
  }

  void addTvShelves({int? network, int? genre}) {
    Future<CatalogPage> shows(int page, {String? sortBy, String? gte, String? lte, int? votes}) =>
        source.discoverTvPage(
          page: page,
          network: network,
          genre: genre,
          sortBy: sortBy,
          firstAirDateGte: gte,
          firstAirDateLte: lte,
          voteCountGte: votes,
        );

    shelves.addAll([
      SeerrShelf(
        id: 'tv:popular',
        title: t.seerr.shelfPopularShows,
        kind: MediaKind.show,
        load: (page) => shows(page, sortBy: 'popularity.desc'),
      ),
      SeerrShelf(
        id: 'tv:recent',
        title: t.seerr.shelfRecentShows,
        kind: MediaKind.show,
        load: (page) => shows(page, sortBy: 'first_air_date.desc', lte: today),
      ),
      SeerrShelf(
        id: 'tv:upcoming',
        title: t.seerr.shelfUpcomingShows,
        kind: MediaKind.show,
        load: (page) => shows(page, sortBy: 'first_air_date.asc', gte: today),
      ),
      SeerrShelf(
        id: 'tv:top',
        title: t.seerr.shelfTopRatedShows,
        kind: MediaKind.show,
        load: (page) => shows(page, sortBy: 'vote_average.desc', votes: seerrTopRatedVoteFloor),
      ),
      SeerrShelf(
        id: 'tv:available',
        title: t.seerr.shelfAvailableShows,
        kind: MediaKind.show,
        load: (page) => _availablePage(
          (p) => shows(p, sortBy: 'popularity.desc'),
          page: page,
          rotation: rotation,
        ),
      ),
    ]);
  }

  // A studio is a film concept and a network a series one; a genre has both.
  if (studioId != null) addMovieShelves(studio: studioId);
  if (movieGenreId != null) addMovieShelves(genre: movieGenreId);
  if (networkId != null && movieWatchProviderId != null) addMovieShelves(watchProvider: movieWatchProviderId);
  if (networkId != null) addTvShelves(network: networkId);
  if (tvGenreId != null) addTvShelves(genre: tvGenreId);

  final rows = _interleaved(shelves);
  final everything = _everythingShelf(rows);
  return [?everything, ...rows];
}

/// The row that stands for the whole list, built from the popular rows that
/// were already defined — one tab per kind, in the order they appear.
///
/// It leads the page because it is the fallback: the shelves under it each
/// answer one question, and this is where to go when none of them asked the
/// right one.
SeerrShelf? _everythingShelf(List<SeerrShelf> rows) {
  final popular = [
    for (final row in rows)
      if (row.id.endsWith(':popular')) row,
  ];
  if (popular.isEmpty) return null;
  return SeerrShelf(
    id: 'all',
    title: t.seerr.shelfEverything,
    kind: popular.first.kind,
    load: popular.first.load,
    tabs: popular,
  );
}

/// Films and series alternating, in the order the rows were built: popular
/// films, popular series, new films, new series, and so on.
///
/// Built kind by kind above because the two ask different questions of Seerr,
/// but read row by row: a page that lists every film row before the first
/// series row makes the second half invisible without a long scroll.
List<SeerrShelf> _interleaved(List<SeerrShelf> shelves) {
  final movies = [
    for (final shelf in shelves)
      if (shelf.kind == MediaKind.movie) shelf,
  ];
  final shows = [
    for (final shelf in shelves)
      if (shelf.kind != MediaKind.movie) shelf,
  ];
  if (movies.isEmpty || shows.isEmpty) return shelves;

  final out = <SeerrShelf>[];
  for (var i = 0; i < movies.length || i < shows.length; i++) {
    if (i < movies.length) out.add(movies[i]);
    if (i < shows.length) out.add(shows[i]);
  }
  return out;
}

/// "immer mal was Neues": titles of this studio, network or genre that are
/// already on one of the user's servers.
///
/// Availability comes from Seerr's own answer, so this costs no per-title
/// lookup. [rotation] shifts which stretch of the catalog is read, so the row
/// shows a different handful each time the app is started rather than the same
/// twenty forever — a shelf of what one already owns is only interesting if it
/// changes.
Future<CatalogPage> _availablePage(
  Future<CatalogPage> Function(int page) fetch, {
  required int page,
  required int rotation,
}) async {
  final found = <CatalogItem>[];
  var hasMore = false;

  for (var offset = 0; offset < seerrAvailableScanPages; offset++) {
    final result = await fetch(page + rotation + offset);
    hasMore = result.hasMore;
    found.addAll(result.items.where(_isAvailable));
    if (found.isNotEmpty || !result.hasMore) break;
  }

  return CatalogPage(items: found, hasMore: hasMore);
}

bool _isAvailable(CatalogItem item) {
  final availability = item.serverState?.availability;
  return availability == CatalogAvailability.available || availability == CatalogAvailability.partiallyAvailable;
}

String _isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
