import 'package:flutter/foundation.dart';

import '../../media/media_kind.dart';
import '../../models/catalog/catalog_cast_member.dart';
import '../../models/catalog/catalog_metadata.dart';
import '../../models/catalog/catalog_item.dart';
import '../../models/seerr/seerr_details.dart';
import '../../models/seerr/seerr_genre.dart';
import '../../models/seerr/seerr_media.dart';
import '../../models/seerr/seerr_page.dart';
import '../../models/seerr/seerr_request.dart';
import '../../utils/app_logger.dart';
import '../../utils/country_codes.dart';
import '../../utils/external_ids.dart';
import '../../utils/trailer_urls.dart';
import '../seerr/seerr_client.dart';
import '../settings_service.dart';
import '../seerr/seerr_constants.dart';
import 'catalog_source.dart';

/// How many shows on one page may be looked up. A page is 20 items, so this
/// is a ceiling rather than a limit in practice — it exists so a shelf that
/// ever grows cannot turn into an unbounded burst against the instance.
const int _episodeFactsPerPageLimit = 20;

/// How long a looked-up episode count and air date stay good. Episode counts
/// barely move; the next air date does, which is what sets the hour.
const Duration _showFactsTtl = Duration(hours: 6);

/// Entries kept before the cache is dropped whole. Scrolling several shelves
/// touches a few hundred titles; clearing beats evicting one by one for
/// something this small.
const int _showFactsCacheLimit = 500;

final Map<int, _SeerrShowFacts> _showFactsCache = {};

/// What a Seerr detail body contributes to a poster badge.
///
/// An instance that answers "nothing to say" is cached as an empty one: the
/// second look at a finished show should not cost a second request.
class _SeerrShowFacts {
  final int? episodeCount;
  final CatalogNextEpisode? nextEpisode;
  final DateTime? fetchedAt;

  const _SeerrShowFacts({this.episodeCount, this.nextEpisode, this.fetchedAt});

  bool get isEmpty => episodeCount == null && nextEpisode == null;

  bool isFresh(DateTime now) => fetchedAt != null && now.difference(fetchedAt!) < _showFactsTtl;

  _SeerrShowFacts stampedAt(DateTime now) =>
      _SeerrShowFacts(episodeCount: episodeCount, nextEpisode: nextEpisode, fetchedAt: now);
}

/// [CatalogSource] backed by a Seerr instance's TMDB-based discover API.
///
/// Wraps the catalog [SeerrClient] owned by `SeerrAccountProvider` (not owned
/// here — never disposed by this class). Seerr has no watchlist; its
/// contribution besides discovery rows is the request flow, which the
/// request surfaces reach through [client] directly.
class SeerrCatalogSource implements CatalogSource {
  final SeerrClient client;
  final WatchlistChangeNotifier _watchlistChanges = WatchlistChangeNotifier();

  SeerrCatalogSource(this.client);

  @override
  CatalogSourceId get id => CatalogSourceId.seerr;

  @override
  String get displayName => 'Seerr';

  @override
  List<CatalogRowId> get supportedRows => const [
    CatalogRowId.recentlyAdded,
    CatalogRowId.trending,
    CatalogRowId.popularMovies,
    CatalogRowId.popularShows,
    CatalogRowId.upcomingMovies,
    CatalogRowId.upcomingShows,
  ];

  @override
  bool get supportsWatchlist => false;

  /// Whether the signed-in user may request titles of [kind] — gates the
  /// detail-screen Request action.
  ///
  /// An empty bitfield means the instance reported no permissions at all,
  /// which is not the same as reporting that the user has none: a user who
  /// truly may do nothing could not sign in to a purpose. Treated as unknown
  /// and answered yes, so the instance itself gets to refuse — with a reason
  /// the request sheet shows — rather than the action silently not existing.
  bool canRequest(MediaKind kind) {
    // A zero mask means no permission, full stop. It used to mean "this
    // instance told us nothing", because POST /auth/local answers with the
    // entity default rather than the stored mask (#2213) — the sign-in now
    // reads GET /auth/me for the real one, so the guess is no longer needed
    // and would only hide a genuine revocation.
    return seerrHasPermission(client.session.permissions, [
      SeerrPermission.request,
      kind == MediaKind.movie ? SeerrPermission.requestMovie : SeerrPermission.requestTv,
    ]);
  }

  @override
  Listenable get watchlistChanges => _watchlistChanges;

  /// Seerr pages are a fixed 20 items; [limit] cannot be honored, so callers
  /// get pages of 20 with [CatalogPage.hasMore] from `totalPages`.
  /// The genres this instance offers, for the Explore genre shelf.
  ///
  /// Seerr-specific, so not part of [CatalogSource]: no other provider serves
  /// genres, and inventing a row id for something only one source has would
  /// force every other source to reject it.
  Future<List<SeerrGenre>> genres(MediaKind kind) => client.getGenres(_mediaTypeFor(kind));

  /// One page of titles in a genre.
  Future<CatalogPage> genrePage(MediaKind kind, int genreId, {int page = 1}) async =>
      _toPage(await client.getByGenre(_mediaTypeFor(kind), genreId, page: page));

  /// One page of `/discover/movies` with filters — the row loaders of a
  /// studio or genre page build on this.
  Future<CatalogPage> discoverMoviesPage({
    int page = 1,
    int? studio,
    int? genre,
    String? sortBy,
    String? releaseDateGte,
    String? releaseDateLte,
    int? voteCountGte,
    int? watchProviders,
    String? watchRegion,
  }) async => _toPage(
    await client.discoverMovies(
      page: page,
      studio: studio,
      genre: genre,
      sortBy: sortBy,
      releaseDateGte: releaseDateGte,
      releaseDateLte: releaseDateLte,
      voteCountGte: voteCountGte,
      watchProviders: watchProviders,
      watchRegion: watchRegion,
    ),
  );

  /// One page of `/discover/tv` with filters.
  Future<CatalogPage> discoverTvPage({
    int page = 1,
    int? network,
    int? genre,
    String? sortBy,
    String? firstAirDateGte,
    String? firstAirDateLte,
    int? voteCountGte,
    int? watchProviders,
    String? watchRegion,
  }) async => _toPage(
    await client.discoverTv(
      page: page,
      network: network,
      genre: genre,
      sortBy: sortBy,
      firstAirDateGte: firstAirDateGte,
      firstAirDateLte: firstAirDateLte,
      voteCountGte: voteCountGte,
      watchProviders: watchProviders,
      watchRegion: watchRegion,
    ),
  );

  /// The streaming service ids this instance can filter by, for [region].
  ///
  /// Cached per source and region: the list is stable, and a brand page would
  /// otherwise fetch it again on every open.
  Future<List<({int id, String name})>> watchProviders(String mediaType, {required String region}) async {
    final key = '$mediaType/$region';
    if (_watchProviders[key] case final cached?) return cached;
    try {
      return _watchProviders[key] = await client.getWatchProviders(mediaType, region: region);
    } catch (error) {
      appLogger.d('Seerr: watch provider list failed for $key', error: error);
      return const [];
    }
  }

  final Map<String, List<({int id, String name})>> _watchProviders = {};

  /// One page of a studio's films.
  Future<CatalogPage> studioPage(int studioId, {int page = 1}) async =>
      _toPage(await client.getByStudio(studioId, page: page));

  /// One page of a network's series.
  Future<CatalogPage> networkPage(int networkId, {int page = 1}) async =>
      _toPage(await client.getByNetwork(networkId, page: page));

  static String _mediaTypeFor(MediaKind kind) => kind == MediaKind.movie ? 'movie' : 'tv';

  @override
  Future<CatalogPage> fetchRow(CatalogRowId row, {int page = 1, int limit = 25}) async {
    if (row == CatalogRowId.recentlyAdded) return _recentlyAddedPage(limit, page: page);
    final res = await switch (row) {
      CatalogRowId.trending => client.getTrending(page: page),
      CatalogRowId.popularMovies => client.getPopularMovies(page: page),
      CatalogRowId.popularShows => client.getPopularTv(page: page),
      CatalogRowId.upcomingMovies => client.getUpcomingMovies(page: page),
      CatalogRowId.upcomingShows => client.getUpcomingTv(page: page),
      CatalogRowId.recentlyAdded ||
      CatalogRowId.watchlist ||
      CatalogRowId.recommendedMovies ||
      CatalogRowId.recommendedShows ||
      CatalogRowId.trendingMovies ||
      CatalogRowId.trendingShows ||
      CatalogRowId.trendingAnime ||
      CatalogRowId.suggestedAnime ||
      CatalogRowId.airingAnime ||
      CatalogRowId.popularAnime => throw ArgumentError('Seerr does not serve ${row.name}'),
    };
    return _toPage(res);
  }

  @override
  Future<List<CatalogItem>> search(String query, {int limit = 30}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final page = await client.search(trimmed);
    return (await _toPage(page)).items;
  }

  @override
  Future<CatalogDetail> fetchDetail(CatalogItem item, {int castLimit = 20, int relatedLimit = 20}) async {
    final tmdbId = item.ids.tmdb;
    if (tmdbId == null) return CatalogDetail(item: item);

    // Start both retained calls before awaiting either. Each helper isolates
    // its own failure so detail metadata and recommendations degrade
    // independently.
    final detailsFuture = _fetchDetails(item.kind, tmdbId);
    final relatedFuture = _fetchRecommendations(item.kind, tmdbId, relatedLimit);
    final details = await detailsFuture;
    final related = await relatedFuture;

    return CatalogDetail(
      item: details == null ? item : item.enrichedWith(_toDetailCatalogItem(details, item.kind)),
      cast: details == null ? const [] : _toCast(details, castLimit),
      related: related,
    );
  }

  /// Seerr requests key on TMDB ids, so any library item carrying one is in
  /// scope; the watchlist action stays hidden regardless
  /// ([supportsWatchlist] is false).
  @override
  Future<CatalogItemIds?> resolveItemIds(MediaKind kind, ExternalIds external, {String? title}) async =>
      external.tmdb == null ? null : CatalogItemIds(tmdb: external.tmdb, imdb: external.imdb, tvdb: external.tvdb);

  // Seerr has no watchlist: membership is always unknown and mutations are
  // programming errors (the action is hidden when supportsWatchlist is false).

  @override
  Future<void> ensureWatchlistLoaded() => Future.value();

  @override
  bool? isOnWatchlist(MediaKind kind, CatalogItemIds ids) => null;

  @override
  Future<void> addToWatchlist(MediaKind kind, CatalogItemIds ids, {String? title}) =>
      throw UnsupportedError('Seerr has no watchlist');

  @override
  Future<void> removeFromWatchlist(MediaKind kind, CatalogItemIds ids, {String? title}) =>
      throw UnsupportedError('Seerr has no watchlist');

  Future<CatalogPage> _toPage(SeerrPage<SeerrMedia> page) async {
    final items = [
      for (final m in page.items)
        if (m.displayTitle.isNotEmpty) _toCatalogItem(m),
    ];
    return CatalogPage(items: await _withEpisodeFacts(items), hasMore: page.hasMore, totalResults: page.totalResults);
  }

  /// Fills in episode count and next air date for the shows on a page, so the
  /// poster badges have something to say.
  ///
  /// Seerr's discover response carries neither — unlike Plex, whose hubs ship
  /// `leafCount` and `duration` inline — so each show costs its own detail
  /// request. That is why this is behind
  /// [SettingsService.seerrCardEpisodeFacts] and why movies are skipped: no
  /// badge on this ladder applies to them.
  ///
  /// A title whose request fails keeps its plain row entry. One instance that
  /// cannot describe a show must not cost the whole shelf.
  Future<List<CatalogItem>> _withEpisodeFacts(List<CatalogItem> items) async {
    if (SettingsService.instanceOrNull?.read(SettingsService.seerrCardEpisodeFacts) != true) return items;

    final wanted = <int>{
      for (final item in items)
        if (item.kind == MediaKind.show && item.episodeCount == null)
          if (item.ids.tmdb case final int tmdbId) tmdbId,
    };
    if (wanted.isEmpty) return items;

    final now = DateTime.now();
    final missing = wanted.where((id) => _showFactsCache[id]?.isFresh(now) != true).toList();
    await Future.wait([
      for (final tmdbId in missing.take(_episodeFactsPerPageLimit))
        _fetchDetails(MediaKind.show, tmdbId).then((details) {
          _rememberShowFacts(tmdbId, details == null ? null : _showFactsFrom(details), now);
        }),
    ]);

    return [for (final item in items) _withCachedFacts(item, now)];
  }

  CatalogItem _withCachedFacts(CatalogItem item, DateTime now) {
    if (item.kind != MediaKind.show) return item;
    if (item.ids.tmdb case final int tmdbId) {
      final facts = _showFactsCache[tmdbId];
      if (facts == null || !facts.isFresh(now) || facts.isEmpty) return item;
      // A detail item carrying nothing else: enrichedWith takes `detail ?? row`
      // per field, so an otherwise empty one touches only these two.
      return item.enrichedWith(
        CatalogItem(
          source: CatalogSourceId.seerr,
          kind: MediaKind.show,
          title: '',
          ids: const CatalogItemIds(),
          episodeCount: facts.episodeCount,
          nextEpisode: facts.nextEpisode,
        ),
      );
    }
    return item;
  }

  static _SeerrShowFacts _showFactsFrom(SeerrDetails details) =>
      _SeerrShowFacts(episodeCount: _episodeCount(details), nextEpisode: _nextEpisode(details));

  static void _rememberShowFacts(int tmdbId, _SeerrShowFacts? facts, DateTime now) {
    if (_showFactsCache.length >= _showFactsCacheLimit) _showFactsCache.clear();
    _showFactsCache[tmdbId] = (facts ?? const _SeerrShowFacts()).stampedAt(now);
  }

  /// Clears the session cache of episode counts and air dates.
  @visibleForTesting
  static void resetShowFactsCache() => _showFactsCache.clear();

  static CatalogNextEpisode? _nextEpisode(SeerrDetails details) {
    final next = details.nextEpisodeToAir;
    final airsAt = _date(next?.airDate);
    if (airsAt == null) return null;
    return CatalogNextEpisode(airsAt: airsAt, episode: _positive(next?.episodeNumber));
  }

  CatalogItem _toCatalogItem(SeerrMedia m) => CatalogItem(
    source: CatalogSourceId.seerr,
    kind: m.isMovie ? MediaKind.movie : MediaKind.show,
    title: m.displayTitle,
    year: m.year,
    overview: _nonEmpty(m.overview),
    rating: m.voteAverage,
    votes: m.voteCount,
    ids: CatalogItemIds(tmdb: m.id),
    posterUrl: tmdbImageUrl(m.posterPath, 'w600_and_h900_bestv2'),
    backdropUrl: tmdbImageUrl(m.backdropPath, 'w1920_and_h800_multi_faces'),
    posterVariants: tmdbPosterVariants(m.posterPath),
    backdropVariants: tmdbBackdropVariants(m.backdropPath),
    serverState: _serverState(m.mediaInfo),
    releaseDate: _date(m.date),
    originalTitle: _originalTitle(m.displayOriginalTitle, m.displayTitle),
    languages: _languageList(m.originalLanguage),
    countries: _countryCodes(m.originCountry),
    isAdult: m.isMovie ? m.adult : null,
  );

  /// What the servers most recently gained, as full titles.
  ///
  /// Seerr answers with bare ids, so each one costs a detail request. They go
  /// out together and a failure drops its entry rather than the row: one
  /// title the instance cannot describe is not worth an empty shelf. The row
  /// is a single snapshot — [page] beyond the first is empty rather than
  /// wrong, since Seerr's parameter here is a count, not a page.
  Future<CatalogPage> _recentlyAddedPage(int limit, {int page = 1}) async {
    if (page > 1) return const CatalogPage(items: [], hasMore: false);
    final refs = await client.getRecentlyAdded(take: limit);
    final resolved = await Future.wait([
      for (final ref in refs)
        _fetchDetails(ref.isMovie ? MediaKind.movie : MediaKind.show, ref.tmdbId).then(
          (details) =>
              details == null ? null : _toDetailCatalogItem(details, ref.isMovie ? MediaKind.movie : MediaKind.show),
        ),
    ]);
    final items = [for (final item in resolved) ?item];
    return CatalogPage(items: items, hasMore: false, totalResults: items.length);
  }

  Future<SeerrDetails?> _fetchDetails(MediaKind kind, int tmdbId) async {
    try {
      return kind == MediaKind.movie ? await client.getMovie(tmdbId) : await client.getTv(tmdbId);
    } catch (error) {
      appLogger.w('Seerr: detail load failed for tmdb:$tmdbId', error: error);
      return null;
    }
  }

  Future<List<CatalogItem>> _fetchRecommendations(MediaKind kind, int tmdbId, int limit) async {
    try {
      final page = kind == MediaKind.movie
          ? await client.getMovieRecommendations(tmdbId)
          : await client.getTvRecommendations(tmdbId);
      return (await _toPage(page)).items.take(limit).toList();
    } catch (error) {
      appLogger.w('Seerr: recommendations load failed for tmdb:$tmdbId', error: error);
      return const [];
    }
  }

  CatalogItem _toDetailCatalogItem(SeerrDetails details, MediaKind kind) => CatalogItem(
    source: CatalogSourceId.seerr,
    kind: kind,
    title: details.displayTitle,
    year: _year(details.date),
    overview: _nonEmpty(details.overview),
    runtimeMinutes: _positive(details.runtime) ?? _firstPositive(details.episodeRunTime),
    rating: details.voteAverage,
    votes: details.voteCount,
    genres: _names(details.genres),
    certification: _certification(details, kind),
    trailerUrl: kind == MediaKind.movie ? _trailerUrl(details.relatedVideos) : null,
    airStatus: _airStatus(details.status, kind),
    episodeCount: kind == MediaKind.show ? _episodeCount(details) : null,
    // Free here, unlike on a row: the detail body is already in hand, so this
    // needs no setting and no extra request.
    nextEpisode: kind == MediaKind.show ? _nextEpisode(details) : null,
    network: kind == MediaKind.show ? _firstName(details.networks) : null,
    ids: CatalogItemIds(
      tmdb: _positive(details.id),
      imdb: _nonEmpty(details.imdbId) ?? _nonEmpty(details.externalIds?.imdbId),
      tvdb: _positive(details.externalIds?.tvdbId),
    ),
    posterUrl: tmdbImageUrl(details.posterPath, 'w600_and_h900_bestv2'),
    backdropUrl: tmdbImageUrl(details.backdropPath, 'w1920_and_h800_multi_faces'),
    posterVariants: tmdbPosterVariants(details.posterPath),
    backdropVariants: tmdbBackdropVariants(details.backdropPath),
    serverState: _serverState(details.mediaInfo),
    releaseDate: _date(details.date),
    originalTitle: _originalTitle(details.displayOriginalTitle, details.displayTitle),
    tagline: _nonEmpty(details.tagline),
    endDate: _endDate(details, kind),
    studios: _names(details.productionCompanies),
    countries: _detailCountries(details),
    languages: _detailLanguages(details),
    credits: _credits(details),
    tags: _tags(details.keywords),
    budget: _positive(details.budget),
    revenue: _positive(details.revenue),
    isAdult: kind == MediaKind.movie ? details.adult : null,
  );

  List<CatalogCastMember> _toCast(SeerrDetails details, int limit) => [
    for (final member in (details.credits?.cast ?? const <SeerrCastMember>[]).take(limit))
      if (_nonEmpty(member.name) case final String name)
        CatalogCastMember(
          name: name,
          secondary: _nonEmpty(member.character),
          imageUrl: tmdbImageUrl(member.profilePath, 'w300'),
        ),
  ];

  CatalogServerState? _serverState(SeerrMediaInfo? info) {
    if (info == null) return null;
    // Read the product at call time: getPublicSettings refreshes it on the
    // live session, upgrading legacy sessions mid-lifetime.
    final product = client.session.product;

    int? availableSeasons;
    int? totalSeasons;
    final seasons = info.seasons;
    if (seasons != null && seasons.isNotEmpty) {
      var available = 0;
      var total = 0;
      for (final season in seasons) {
        if (season.seasonNumber <= 0) continue;
        total++;
        if (season.status(product) == SeerrMediaStatus.available) available++;
      }
      if (total > 0) {
        availableSeasons = available;
        totalSeasons = total;
      }
    }

    final status = info.status(product);
    final status4k = info.status4k(product);
    final state = CatalogServerState(
      availability: _availability(status),
      availability4k: _availability(status4k),
      request: _requestState(info, is4k: false, mediaStatus: status),
      request4k: _requestState(info, is4k: true, mediaStatus: status4k),
      availableSeasons: availableSeasons,
      totalSeasons: totalSeasons,
    );
    return state.isEmpty ? null : state;
  }

  static CatalogAvailability? _availability(SeerrMediaStatus status) => switch (status) {
    SeerrMediaStatus.available => CatalogAvailability.available,
    SeerrMediaStatus.partiallyAvailable => CatalogAvailability.partiallyAvailable,
    SeerrMediaStatus.pending ||
    SeerrMediaStatus.processing ||
    SeerrMediaStatus.blocklisted ||
    SeerrMediaStatus.deleted => CatalogAvailability.unavailable,
    SeerrMediaStatus.unknown => null,
  };

  static CatalogRequestState? _requestState(
    SeerrMediaInfo info, {
    required bool is4k,
    required SeerrMediaStatus mediaStatus,
  }) {
    var pendingApproval = false;
    var approved = false;
    var declined = false;
    var failed = false;
    for (final request in info.requests ?? const <SeerrRequest>[]) {
      if ((request.is4k ?? false) != is4k) continue;
      switch (request.status) {
        case SeerrRequestStatus.pending:
          pendingApproval = true;
        case SeerrRequestStatus.approved:
          approved = true;
        case SeerrRequestStatus.declined:
          declined = true;
        case SeerrRequestStatus.failed:
          failed = true;
        case SeerrRequestStatus.completed:
          // Settled: the media status already reflects availability, so a
          // completed request contributes no active request state.
          break;
      }
    }

    // These two `pending` values are unrelated. Request.pending means waiting
    // for approval; MediaInfo.pending means an approved request is queued in
    // the acquisition pipeline. Keep that distinction and precedence explicit.
    if (pendingApproval) return CatalogRequestState.pending;
    // Seerr marks a request Failed on arr-push failure but can leave the
    // media status Processing/Pending behind. With no live pending/approved
    // request backing that status it is stale, so the failed request wins and
    // re-requesting stays open; any live request keeps the pipeline outcome.
    if (failed && !approved) return CatalogRequestState.failed;
    if (mediaStatus == SeerrMediaStatus.processing) return CatalogRequestState.processing;
    if (approved || mediaStatus == SeerrMediaStatus.pending) return CatalogRequestState.approved;
    if (declined) return CatalogRequestState.declined;
    return null;
  }

  static String? _certification(SeerrDetails details, MediaKind kind) {
    if (kind == MediaKind.movie) {
      return _preferredCountryValue(
        details.releases?.results,
        (entry) => entry.countryCode,
        (entry) =>
            _nonEmpty(entry.rating) ??
            entry.releaseDates?.map((date) => _nonEmpty(date.certification)).nonNulls.firstOrNull,
      );
    }
    return _preferredCountryValue(
      details.contentRatings?.results,
      (entry) => entry.countryCode,
      (entry) => _nonEmpty(entry.rating),
    );
  }

  static String? _preferredCountryValue<T>(
    List<T>? entries,
    String? Function(T entry) country,
    String? Function(T entry) value,
  ) {
    if (entries == null) return null;
    for (final entry in entries) {
      if (country(entry)?.toUpperCase() != 'US') continue;
      if (value(entry) case final String result) return result;
    }
    for (final entry in entries) {
      if (value(entry) case final String result) return result;
    }
    return null;
  }

  static String? _trailerUrl(List<SeerrRelatedVideo>? videos) {
    if (videos == null) return null;
    for (final video in videos) {
      if (video.type?.toLowerCase() != 'trailer') continue;
      if (_nonEmpty(video.url) case final String url) return url;
      if (_nonEmpty(video.key) case final String key when video.site?.toLowerCase() == 'youtube') {
        return youTubeTrailerUrl(key);
      }
    }
    return null;
  }

  static CatalogAirStatus? _airStatus(String? raw, MediaKind kind) {
    return switch (raw?.trim().toLowerCase()) {
      'returning series' || 'airing' => CatalogAirStatus.airing,
      'ended' => CatalogAirStatus.ended,
      'canceled' || 'cancelled' => CatalogAirStatus.canceled,
      'planned' || 'pilot' || 'rumored' || 'in production' || 'post production' => CatalogAirStatus.upcoming,
      'released' when kind == MediaKind.show => CatalogAirStatus.ended,
      _ => null,
    };
  }

  static DateTime? _endDate(SeerrDetails details, MediaKind kind) {
    if (kind != MediaKind.show) return null;
    final status = _airStatus(details.status, kind);
    return status == CatalogAirStatus.ended || status == CatalogAirStatus.canceled ? _date(details.lastAirDate) : null;
  }

  static int? _episodeCount(SeerrDetails details) {
    if (_positive(details.numberOfEpisodes) case final int count) return count;
    var total = 0;
    var found = false;
    for (final season in details.seasons ?? const <SeerrSeason>[]) {
      if (_positive(season.episodeCount) case final int count) {
        total += count;
        found = true;
      }
    }
    return found ? total : null;
  }

  static List<String>? _countryCodes(Iterable<String?>? values) {
    if (values == null) return null;
    final result = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final trimmed = _nonEmpty(value);
      if (trimmed == null) continue;
      final normalized = CountryCodes.normalizeCode(trimmed);
      if (normalized.isNotEmpty && seen.add(normalized)) result.add(normalized);
    }
    return result.isEmpty ? null : result;
  }

  static List<String>? _detailCountries(SeerrDetails details) => _countryCodes([
    ...?details.originCountry,
    for (final value in details.productionCountries ?? const <SeerrProductionCountry>[])
      value.countryCode ?? value.name,
  ]);

  static List<String>? _detailLanguages(SeerrDetails details) => _languageCodes([
    details.originalLanguage,
    ...?details.languages,
    for (final language in details.spokenLanguages ?? const <SeerrSpokenLanguage>[]) language.languageCode,
  ]);

  static List<String>? _languageCodes(Iterable<String?> values) {
    final result = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final normalized = _nonEmpty(value)?.toLowerCase();
      if (normalized != null && seen.add(normalized)) result.add(normalized);
    }
    return result.isEmpty ? null : result;
  }

  static List<CatalogCredit>? _credits(SeerrDetails details) {
    final result = <CatalogCredit>[];
    final seen = <String>{};

    void add(String? rawName, CatalogCreditRole? role) {
      final name = _nonEmpty(rawName);
      if (name == null || role == null || !seen.add('${role.name}\u0000$name')) return;
      result.add(CatalogCredit(name: name, role: role));
    }

    for (final creator in details.createdBy ?? const <SeerrNamedValue>[]) {
      add(creator.name, CatalogCreditRole.creator);
    }
    for (final member in details.credits?.crew ?? const <SeerrCrewMember>[]) {
      add(member.name, _creditRole(member.job, member.department));
    }
    return result.isEmpty ? null : result;
  }

  static CatalogCreditRole? _creditRole(String? job, String? department) {
    return switch (job?.trim().toLowerCase()) {
      'director' => CatalogCreditRole.director,
      'writer' || 'screenplay' || 'story' || 'teleplay' => CatalogCreditRole.writer,
      'producer' || 'executive producer' || 'co-producer' => CatalogCreditRole.producer,
      'composer' || 'original music composer' => CatalogCreditRole.composer,
      _ when department?.trim().toLowerCase() == 'writing' => CatalogCreditRole.writer,
      _ => null,
    };
  }

  static List<CatalogTag>? _tags(List<SeerrNamedValue>? keywords) {
    final names = _names(keywords);
    return names == null ? null : [for (final name in names) CatalogTag(name: name)];
  }

  static List<String>? _names(List<SeerrNamedValue>? values) {
    if (values == null) return null;
    final names = [
      for (final value in values)
        if (_nonEmpty(value.name) case final String name) name,
    ];
    return names.isEmpty ? null : names;
  }

  static String? _firstName(List<SeerrNamedValue>? values) {
    if (values == null) return null;
    for (final value in values) {
      if (_nonEmpty(value.name) case final String name) return name;
    }
    return null;
  }

  static List<String>? _languageList(String? language) => _languageCodes([language]);

  static String? _originalTitle(String? original, String displayed) {
    final value = _nonEmpty(original);
    return value == null || value == displayed ? null : value;
  }

  static DateTime? _date(String? raw) => raw == null ? null : DateTime.tryParse(raw);

  static int? _year(String? raw) {
    if (raw == null || raw.length < 4) return null;
    return int.tryParse(raw.substring(0, 4));
  }

  static int? _positive(int? value) => value != null && value > 0 ? value : null;

  static int? _firstPositive(List<int>? values) {
    if (values == null) return null;
    for (final value in values) {
      if (value > 0) return value;
    }
    return null;
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static Map<int, String>? tmdbPosterVariants(String? path) {
    if (path == null || path.isEmpty) return null;
    return {
      92: tmdbImageUrl(path, 'w92')!,
      154: tmdbImageUrl(path, 'w154')!,
      185: tmdbImageUrl(path, 'w185')!,
      342: tmdbImageUrl(path, 'w342')!,
      500: tmdbImageUrl(path, 'w500')!,
      600: tmdbImageUrl(path, 'w600_and_h900_bestv2')!,
      780: tmdbImageUrl(path, 'w780')!,
    };
  }

  static Map<int, String>? tmdbBackdropVariants(String? path) {
    if (path == null || path.isEmpty) return null;
    return {
      300: tmdbImageUrl(path, 'w300')!,
      780: tmdbImageUrl(path, 'w780')!,
      1280: tmdbImageUrl(path, 'w1280')!,
      1920: tmdbImageUrl(path, 'w1920_and_h800_multi_faces')!,
    };
  }

  /// Seerr serves TMDB relative paths (`/abc.jpg`); images come straight off
  /// the TMDB CDN at the same sizes the Seerr web UI uses.
  static String? tmdbImageUrl(String? path, String size) =>
      path == null || path.isEmpty ? null : 'https://image.tmdb.org/t/p/$size$path';

  @override
  void dispose() {
    _watchlistChanges.dispose();
  }
}
