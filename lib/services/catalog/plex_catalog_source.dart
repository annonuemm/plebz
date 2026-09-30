import '../../media/media_rating.dart';
import '../../media/media_kind.dart';
import '../../models/catalog/catalog_cast_member.dart';
import '../../models/catalog/catalog_item.dart';
import '../../models/catalog/catalog_metadata.dart';
import '../../utils/external_ids.dart';
import '../../i18n/strings.g.dart';
import '../../utils/app_logger.dart';
import '../../utils/country_codes.dart';
import '../../utils/json_utils.dart';
import '../plex_discover_client.dart';
import '../plex_mappers.dart';
import 'catalog_source.dart';
import 'catalog_watchlist_machinery.dart';

/// A destination on a Discover shelf: a streaming service, a genre, an award.
///
/// Not a title, which is why it cannot travel as a [CatalogItem]: it has no
/// kind, no rating key and nothing to open a detail page with. What it does
/// have is a name and a section of its own, which is exactly a tile that
/// leads somewhere.
class PlexTile {
  const PlexTile({required this.id, required this.title, required this.sectionKey, this.imageUrl});

  /// Stable within a session and derived from what Discover names it by, so a
  /// tile keeps its identity across a refresh.
  final String id;
  final String title;

  /// The Discover section the tile opens.
  final String sectionKey;

  /// Absolute URL, or null where the shelf names its entries in words —
  /// genres and awards carry no artwork. A server-relative path is refused at
  /// parse time: the Explore rail draws these tiles without a server client,
  /// and a path it cannot resolve is a broken tile rather than a missing one.
  final String? imageUrl;
}

/// A shelf of such destinations, under Discover's own heading.
class PlexTileShelf {
  const PlexTileShelf({required this.id, required this.title, required this.tiles, required this.isPlatform});

  final String id;
  final String title;
  final List<PlexTile> tiles;

  /// True for the streaming services, which are drawn as their square logos
  /// and nothing else. Taken from Discover's own hub style, never from
  /// whether the tiles happen to carry pictures: genres arrive with artwork
  /// of their own, and one service without a logo would speak for the rest.
  final bool isPlatform;
}

/// [CatalogSource] backed by the active Plex profile's universal watchlist
/// and Discover's Home shelves (what Plex's own web client shows on its
/// Home ▸ Trending tab).
class PlexCatalogSource with CatalogWatchlistMachinery implements CatalogSource, CatalogHubSource {
  final PlexDiscoverClient _client;
  final bool includeImageVariants;
  final Map<String, String> _hubKeys = {};
  List<PlexTileShelf> _tileShelves = const [];

  /// Discover's shelves of destinations rather than titles — the streaming
  /// services, the genres, the awards — in the order they were sent. Empty
  /// until [fetchHubs] has run.
  List<PlexTileShelf> get tileShelves => _tileShelves;

  /// The language the shelf headings are asked for, or null where Discover's
  /// own wording already is the app's — its records are English by default.
  static String? get _uiLanguage {
    final language = LocaleSettings.currentLocale.languageCode;
    return language == 'en' ? null : language;
  }

  PlexCatalogSource(this._client, {this.includeImageVariants = false});

  @override
  CatalogSourceId get id => CatalogSourceId.plex;

  @override
  String get displayName => 'Plex';

  @override
  List<CatalogRowId> get supportedRows => const [CatalogRowId.watchlist];

  @override
  bool get supportsWatchlist => true;

  @override
  String get watchlistLogLabel => 'Plex: watchlist';

  // Discover validates X-Plex-Container-Size against a cap it drifts
  // without notice (#1715: 500 became invalid). 100 keeps the snapshot at
  // few requests while staying well under the observed cap, and the client
  // degrades to 25-item chunks if the cap ever drops below it; more pages
  // preserve the 5000-entry coverage.
  @override
  int get watchlistPageLimit => 100;

  @override
  int get watchlistMaxPages => 50;

  @override
  Future<CatalogPage> fetchRow(CatalogRowId row, {int page = 1, int limit = 25}) async {
    if (row != CatalogRowId.watchlist) throw ArgumentError('Plex does not serve ${row.name}');
    final response = await _client.getWatchlist(page: page, limit: limit);
    final items = _fromMetadata(response.items);
    // The play state is what the watched filter runs on, and `includeUserState`
    // is undocumented enough to be worth one line: silence here is the first
    // thing to look at when the filter says nothing is watched.
    final answered = items.where((item) => item.isWatched != null).length;
    appLogger.d('Plex: watchlist page $page, $answered of ${items.length} entries carry play state');
    return CatalogPage(items: items, hasMore: response.hasMore, totalResults: response.totalResults);
  }

  @override
  Future<List<CatalogHub>> fetchHubs({int limit = 25}) async {
    final fetched = await _client.getHomeHubs(
      limit: limit,
      includeImageVariants: includeImageVariants,
      language: _uiLanguage,
    );
    final keys = <String, String>{};
    final result = <CatalogHub>[];
    final shelves = <PlexTileShelf>[];
    for (final hub in fetched) {
      final style = _hubStyleFor(hub.style);
      // Services, genres and awards are destinations, not titles: read as
      // metadata every entry drops out, and the shelf with it. They are kept
      // aside as tiles instead.
      final isPlatform = style == CatalogHubStyle.availabilityPlatforms;
      if (isPlatform || hub.type == 'directory') {
        // A service is its logo, so one without a logo is not a service: the
        // shelf ends in Plex's own "Preferred Services" entry, which picks
        // the services and can only be answered in their web client. A browse
        // shelf keeps every tile — those are named in words.
        final tiles = [
          for (final tile in _tilesFrom(hub.page.items))
            if (!isPlatform || tile.imageUrl != null) tile,
        ];
        if (tiles.isEmpty) continue;
        shelves.add(PlexTileShelf(id: hub.id, title: hub.title, tiles: tiles, isPlatform: isPlatform));
        continue;
      }
      final items = _fromMetadata(hub.page.items);
      if (items.isEmpty) continue;
      keys[hub.id] = hub.key;
      result.add(
        CatalogHub(
          id: hub.id,
          title: hub.title,
          style: style,
          page: CatalogPage(items: items, hasMore: hub.page.hasMore, totalResults: hub.page.totalResults),
        ),
      );
    }
    _hubKeys
      ..clear()
      ..addAll(keys);
    _tileShelves = List.unmodifiable(shelves);
    return result;
  }

  /// The tiles readable from one shelf of destinations, in Discover's order.
  ///
  /// A shelf that yields none is logged with the field names it did carry:
  /// the payload is undocumented, and the next shape it takes has to be
  /// readable from a single line rather than guessed at twice.
  static List<PlexTile> _tilesFrom(List<Map<String, dynamic>> metadata) {
    final tiles = <PlexTile>[];
    final seen = <String>{};
    for (final entry in metadata) {
      final tile = _toTile(entry);
      if (tile != null && seen.add(tile.id)) tiles.add(tile);
    }
    if (tiles.isEmpty && metadata.isNotEmpty) {
      appLogger.w('Plex Discover: no tile read from an entry carrying ${metadata.first.keys.join(', ')}');
    }
    return tiles;
  }

  static PlexTile? _toTile(Map<String, dynamic> metadata) {
    final title = _nonEmptyString(metadata['title']);
    final key = _nonEmptyString(metadata['hubKey'] ?? metadata['key']);
    // Both or nothing: a tile without a name says nothing and one without a
    // section opens nothing. The picture is optional — genres and awards are
    // named in words.
    if (title == null || key == null) return null;
    return PlexTile(id: _tileIdFor(metadata, title), title: title, sectionKey: key, imageUrl: _tileImage(metadata));
  }

  /// The tile's picture, where it has one. Discover carries it both as an
  /// `Image` element and as a plain `thumb`, so both are read.
  static String? _tileImage(Map<String, dynamic> metadata) {
    final byType = <String, String>{};
    for (final image in flexibleMapList(metadata['Image'])) {
      final type = _nonEmptyString(image['type']);
      final url = _nonEmptyString(image['url']);
      if (type != null && url != null) byType.putIfAbsent(type, () => url);
    }
    for (final type in const ['clearLogoWide', 'clearLogo', 'coverArt', 'banner', 'coverPoster']) {
      if (_absoluteUrl(byType[type]) case final url?) return url;
    }
    for (final field in const ['thumb', 'art', 'logo', 'image']) {
      if (_absoluteUrl(_nonEmptyString(metadata[field])) case final url?) return url;
    }
    return null;
  }

  static String? _absoluteUrl(String? value) =>
      value != null && (value.startsWith('http://') || value.startsWith('https://')) ? value : null;

  /// A slug, because the id ends up in a hub id and a tile id.
  static String _tileIdFor(Map<String, dynamic> metadata, String title) {
    final raw = _nonEmptyString(metadata['id']) ?? _nonEmptyString(metadata['ratingKey']) ?? title;
    final slug = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? title : slug;
  }

  /// The shelves behind one tile — "Recently added on Prime Video",
  /// "Recommended for you" — each with its first titles.
  ///
  /// Plex's own client shows a service or a genre this way, and a whole
  /// catalogue flattened into one grid is a list nobody reads to the end of.
  /// Every shelf's key is registered, so a row's View All can be followed
  /// like any other hub.
  Future<List<CatalogHub>> fetchSectionHubs(String sectionKey, {int limit = 25}) async {
    final fetched = await _client.getSectionHubs(
      sectionKey,
      limit: limit,
      includeImageVariants: includeImageVariants,
      language: _uiLanguage,
    );
    final result = <CatalogHub>[];
    for (final hub in fetched) {
      final items = _fromMetadata(hub.page.items);
      if (items.isEmpty) continue;
      _hubKeys[hub.id] = hub.key;
      result.add(
        CatalogHub(
          id: hub.id,
          title: hub.title,
          style: _hubStyleFor(hub.style),
          page: CatalogPage(items: items, hasMore: hub.page.hasMore, totalResults: hub.page.totalResults),
        ),
      );
    }
    return result;
  }

  /// Discover serves a hub in one shot — it ignores container offsets — so
  /// View All has nothing to page into beyond the first request.
  @override
  Future<CatalogPage> fetchHub(String id, {int page = 1, int limit = 25}) async {
    final key = _hubKeys[id];
    if (key == null || page > 1) return const CatalogPage(items: []);
    final response = await _client.getHub(key, limit: limit, includeImageVariants: includeImageVariants);
    return CatalogPage(items: _fromMetadata(response.items), hasMore: false, totalResults: response.totalResults);
  }

  @override
  Future<List<CatalogItem>> search(String query, {int limit = 30}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    return _fromSearchResults(await _client.search(trimmed, limit: limit));
  }

  @override
  Future<CatalogItemIds?> resolveItemIds(MediaKind kind, ExternalIds external, {String? title}) async {
    // Plex Discover matches on imdb/tmdb/tvdb only; an AniDB-only item has
    // nothing to send it.
    if (!external.hasCatalogIds) return null;
    // Two indexes, and they disagree: titles Discover's search plainly has
    // can be absent from its id match. The search is the fallback, its hit
    // verified against the same ids before it counts.
    final metadata =
        await _client.match(external, kind: kind) ??
        (title == null ? null : await _client.matchByTitle(title, external));
    final matchedKind = metadata == null ? null : _kindFor(metadata['type']);
    if (metadata == null || matchedKind != kind) return null;
    final ids = _idsFor(metadata);
    if (ids.plex == null) return null;
    return CatalogItemIds(
      plex: ids.plex,
      imdb: ids.imdb ?? external.imdb,
      tmdb: ids.tmdb ?? external.tmdb,
      tvdb: ids.tvdb ?? external.tvdb,
    );
  }

  @override
  Future<CatalogItemIds> resolveWatchlistMutationIds(MediaKind kind, CatalogItemIds ids, {String? title}) async {
    if (ids.plex != null && ids.plex!.isNotEmpty) return ids;
    // With the title, so a title Discover's id match does not know can still
    // be found through its search — which is where a Seerr item usually ends
    // up, carrying a TMDB id and nothing Plex indexed it under.
    final resolved = await resolveItemIds(kind, ids.toExternalIds(), title: title);
    if (resolved?.plex == null || resolved!.plex!.isEmpty) {
      throw StateError('Plex: no rating key for ${ids.canonicalKey ?? 'item'}');
    }
    return resolved;
  }

  @override
  Future<CatalogDetail> fetchDetail(CatalogItem item, {int castLimit = 20, int relatedLimit = 20}) async {
    final ratingKey = item.ids.plex;
    if (ratingKey == null || ratingKey.isEmpty) return CatalogDetail(item: item);

    // All three run together: the localized summary does not depend on the
    // plain record, so asking for it costs a request but no waiting.
    final metadataFuture = _loadDetailMetadata(ratingKey);
    final relatedFuture = _loadRelatedMetadata(ratingKey);
    final localizedOverviewFuture = _localizedOverview(ratingKey);
    final metadata = await metadataFuture;
    final relatedMetadata = await relatedFuture;
    final localizedOverview = await localizedOverviewFuture;
    final localized = metadata == null || localizedOverview == null
        ? metadata
        : {...metadata, 'summary': localizedOverview, 'Summary': const <Object?>[]};
    final detailItem = localized == null ? null : _toCatalogItem(localized);
    final safeCastLimit = castLimit < 0 ? 0 : castLimit;
    final safeRelatedLimit = relatedLimit < 0 ? 0 : relatedLimit;

    return CatalogDetail(
      item: detailItem == null ? item : item.enrichedWith(detailItem),
      cast: metadata == null
          ? const []
          : [
              for (final role in flexibleMapList(metadata['Role']).take(safeCastLimit))
                if (_nonEmptyString(role['tag'] ?? role['name']) case final String name)
                  CatalogCastMember(
                    name: name,
                    secondary: _nonEmptyString(role['role']),
                    imageUrl: _nonEmptyString(role['thumb']),
                  ),
            ],
      related: _fromMetadata(relatedMetadata).take(safeRelatedLimit).toList(),
    );
  }

  Future<Map<String, dynamic>?> _loadDetailMetadata(String ratingKey) async {
    try {
      return await _client.getMetadata(ratingKey);
    } catch (error, stackTrace) {
      appLogger.w('Plex: detail metadata failed', error: error, stackTrace: stackTrace);
      return null;
    }
  }

  /// The description in the app's language, or null to keep the one the
  /// unlocalized record carried.
  ///
  /// A second request rather than one localized fetch for everything: Discover
  /// answers a localized request with an *empty* summary when it has no
  /// translation instead of falling back, and there is no telling what else
  /// thins out with it. So the plain record stays the source of truth and this
  /// only ever adds a description on top — German where it exists, the English
  /// one where it does not.
  Future<String?> _localizedOverview(String ratingKey) async {
    final language = LocaleSettings.currentLocale.languageCode;
    if (language == 'en') return null;
    try {
      final localized = await _client.getMetadata(ratingKey, language: language);
      return localized == null ? null : _overviewFor(localized);
    } catch (error) {
      appLogger.d('Plex: localized summary failed', error: error);
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _loadRelatedMetadata(String ratingKey) async {
    try {
      return await _client.getRelated(ratingKey);
    } catch (error, stackTrace) {
      appLogger.w('Plex: related metadata failed', error: error, stackTrace: stackTrace);
      return const [];
    }
  }

  @override
  Future<WatchlistKeyPage> fetchWatchlistKeyPage(int page, int limit) async {
    final response = await _client.getWatchlist(page: page, limit: limit);
    final groups = <List<String>>[];
    final seen = <String>{};
    for (final metadata in response.items) {
      final kind = _kindFor(metadata['type']);
      final title = _nonEmptyString(metadata['title']);
      final ids = _idsFor(metadata);
      if (kind == null || title == null || ids.plex == null) continue;
      if (seen.add(ids.identityKeyFor(kind))) groups.add(membershipKeysFor(kind, ids));
    }
    return (groups: groups, hasMore: response.hasMore);
  }

  @override
  Future<void> performWatchlistMutation(MediaKind kind, CatalogItemIds ids, {required bool add}) async {
    final ratingKey = ids.plex;
    if (ratingKey == null || ratingKey.isEmpty) {
      throw ArgumentError('Plex watchlist mutations require a Plex rating key');
    }
    await _client.setWatchlisted(ratingKey, add: add);
  }

  List<CatalogItem> _fromMetadata(List<Map<String, dynamic>> metadata) {
    final items = <CatalogItem>[];
    final seen = <String>{};
    for (final value in metadata) {
      final item = _toCatalogItem(value);
      if (item != null && seen.add(item.identityKey)) items.add(item);
    }
    return items;
  }

  List<CatalogItem> _fromSearchResults(List<PlexDiscoverSearchResult> results) {
    final items = <CatalogItem>[];
    final seen = <String>{};
    for (final result in results) {
      final item = _toCatalogItem(result.metadata);
      if (item != null && seen.add(item.identityKey)) items.add(item);
    }
    return items;
  }

  /// The account's play state for one Discover entry, or null when the
  /// response carries none.
  ///
  /// `includeUserState=1` is answered in more than one shape — the counters
  /// sit on the entry itself on some endpoints and under a `UserState` object
  /// on others — so both are read rather than guessed at. A show is watched
  /// when every episode Plex counts is: a bare `viewCount` on a series says
  /// how often *something* in it played, which is not the same thing.
  static bool? _watchedFrom(Map<String, dynamic> metadata) {
    final nested = metadata['UserState'] ?? metadata['userState'];
    if (nested is Map) {
      final fromNested = _watchedFrom(nested.cast<String, dynamic>());
      if (fromNested != null) return fromNested;
    }
    final leafCount = flexibleInt(metadata['leafCount']);
    final viewedLeafCount = flexibleInt(metadata['viewedLeafCount']);
    if (leafCount != null && leafCount > 0 && viewedLeafCount != null) return viewedLeafCount >= leafCount;
    final viewCount = flexibleInt(metadata['viewCount']);
    if (viewCount != null) return viewCount > 0;
    if (viewedLeafCount != null) return viewedLeafCount > 0;
    return null;
  }

  CatalogItem? _toCatalogItem(Map<String, dynamic> metadata) {
    final kind = _kindFor(metadata['type']);
    final title = _nonEmptyString(metadata['title']);
    final ids = _idsFor(metadata);
    if (kind == null || title == null || ids.plex == null) return null;

    final genres = _tagsFor(metadata['Genre']);
    final studios = _tagsFor(metadata['Studio']);
    final countries = _countriesFor(metadata['Country']);
    final credits = _creditsFor(metadata);
    final ratings = _ratingsFor(metadata);
    final durationMs = flexibleInt(metadata['duration']);
    final continuing = flexibleBoolNullable(metadata['isContinuingSeries']);
    final nextAirDate = kind == MediaKind.show
        ? _date(metadata['nextEpisodeOriginallyAvailableAt']) ?? _date(metadata['nextSeasonOriginallyAvailableAt'])
        : null;

    String? coverPoster;
    String? coverArt;
    String? background;
    String? clearLogo;
    String? clearLogoWide;
    String? imageBanner;
    for (final image in flexibleMapList(metadata['Image'])) {
      final type = _nonEmptyString(image['type']);
      final url = _nonEmptyString(image['url']);
      if (type == null || url == null) continue;
      switch (type) {
        case 'coverPoster':
          coverPoster ??= url;
        case 'coverArt':
          coverArt ??= url;
        case 'background':
          background ??= url;
        case 'clearLogo':
          clearLogo ??= url;
        case 'clearLogoWide':
          clearLogoWide ??= url;
        case 'banner':
          imageBanner ??= url;
      }
    }

    final headlineRating = normalizedPlexRating(metadata['rating']);
    final isWatched = _watchedFrom(metadata);
    final audienceRating = normalizedPlexRating(metadata['audienceRating']);
    return CatalogItem(
      source: CatalogSourceId.plex,
      kind: kind,
      isWatched: isWatched,
      title: title,
      year: flexibleInt(metadata['year']),
      overview: _overviewFor(metadata),
      runtimeMinutes: durationMs == null ? null : Duration(milliseconds: durationMs).inMinutes,
      rating: headlineRating ?? audienceRating,
      genres: genres,
      certification: _nonEmptyString(metadata['contentRating']),
      airStatus: kind == MediaKind.show && continuing != null
          ? continuing
                ? CatalogAirStatus.airing
                : CatalogAirStatus.ended
          : null,
      episodeCount: kind == MediaKind.show ? flexibleInt(metadata['leafCount']) : null,
      network: _nonEmptyString(metadata['studio'] ?? metadata['network']),
      ids: ids,
      posterUrl: _nonEmptyString(metadata['thumb']) ?? coverPoster ?? coverArt,
      backdropUrl: _nonEmptyString(metadata['art']) ?? background,
      logoUrl: clearLogoWide ?? clearLogo,
      bannerUrl: _nonEmptyString(metadata['banner']) ?? imageBanner,
      ratings: ratings,
      nextEpisode: nextAirDate == null ? null : CatalogNextEpisode(airsAt: nextAirDate),
      releaseDate: _date(metadata['originallyAvailableAt']),
      endDate: kind == MediaKind.show && continuing == false
          ? _date(metadata['lastEpisodeOriginallyAvailableAt']) ?? _date(metadata['lastSeasonOriginallyAvailableAt'])
          : null,
      originalTitle: _nonEmptyString(metadata['originalTitle']),
      tagline: _nonEmptyString(metadata['tagline']),
      studios: studios,
      countries: countries,
      credits: credits,
      contentAdvisory: _contentAdvisoryFor(metadata),
      budget: flexibleInt(metadata['budget']),
      revenue: flexibleInt(metadata['revenue']),
    );
  }

  static List<String>? _tagsFor(Object? value) {
    final tags = <String>[];
    final seen = <String>{};
    for (final entry in flexibleMapList(value)) {
      final tag = _nonEmptyString(entry['tag'] ?? entry['name']);
      if (tag != null && seen.add(tag)) tags.add(tag);
    }
    return tags.isEmpty ? null : tags;
  }

  static List<String>? _countriesFor(Object? value) {
    final countries = <String>[];
    final seen = <String>{};
    for (final entry in flexibleMapList(value)) {
      final tag = _nonEmptyString(entry['tag'] ?? entry['name']);
      if (tag == null) continue;
      final country = CountryCodes.normalizeCode(tag);
      if (country.isNotEmpty && seen.add(country)) countries.add(country);
    }
    return countries.isEmpty ? null : countries;
  }

  static List<CatalogCredit>? _creditsFor(Map<String, dynamic> metadata) {
    final credits = <CatalogCredit>[];
    final seen = <String>{};

    void addCredits(Object? value, CatalogCreditRole role) {
      for (final entry in flexibleMapList(value)) {
        final name = _nonEmptyString(entry['tag'] ?? entry['name'] ?? entry['role']);
        if (name != null && seen.add('${role.name}\u0000$name')) {
          credits.add(CatalogCredit(name: name, role: role));
        }
      }
    }

    addCredits(metadata['Director'], CatalogCreditRole.director);
    addCredits(metadata['Writer'], CatalogCreditRole.writer);
    addCredits(metadata['Producer'], CatalogCreditRole.producer);
    return credits.isEmpty ? null : credits;
  }

  static List<MediaRatingSource>? _ratingsFor(Map<String, dynamic> metadata) => plexRatingSources(
    rating: metadata['rating'],
    ratingImage: metadata['ratingImage'],
    audienceRating: metadata['audienceRating'],
    audienceRatingImage: metadata['audienceRatingImage'],
    ratingSources: [
      for (final rating in flexibleMapList(metadata['Rating']))
        (image: rating['image'], type: rating['type'], value: rating['value']),
    ],
    imdbVotes: flexibleInt(metadata['imdbRatingCount']),
  );

  static String? _overviewFor(Map<String, dynamic> metadata) {
    var overview = _nonEmptyString(metadata['summary']);
    for (final summary in flexibleMapList(metadata['Summary'])) {
      final candidate = _nonEmptyString(summary['tag'] ?? summary['summary']);
      if (candidate != null && (overview == null || candidate.length > overview.length)) {
        overview = candidate;
      }
    }
    return overview;
  }

  static String? _contentAdvisoryFor(Map<String, dynamic> metadata) {
    final advisories = <String>[];
    final seen = <String>{};
    for (final commonSense in flexibleMapList(metadata['CommonSenseMedia'])) {
      final oneLiner = _nonEmptyString(commonSense['oneLiner']);
      int? age;
      for (final rating in flexibleMapList(commonSense['AgeRating'])) {
        age ??= flexibleInt(rating['age']);
      }
      final advisory = [if (age != null) '$age+', ?oneLiner].join(' · ');
      if (advisory.isNotEmpty && seen.add(advisory)) advisories.add(advisory);
    }
    return advisories.isEmpty ? null : advisories.join('\n');
  }

  static DateTime? _date(Object? value) => value is String ? DateTime.tryParse(value) : null;

  static MediaKind? _kindFor(Object? type) => switch (type) {
    'movie' => MediaKind.movie,
    'show' => MediaKind.show,
    _ => null,
  };

  static CatalogHubStyle? _hubStyleFor(Object? style) => switch (style) {
    'shelf' => CatalogHubStyle.shelf,
    'availabilityPlatforms' => CatalogHubStyle.availabilityPlatforms,
    _ => null,
  };

  static CatalogItemIds _idsFor(Map<String, dynamic> metadata) {
    String? imdb;
    int? tmdb;
    int? tvdb;

    void consumeGuid(Object? value) {
      final guid = _nonEmptyString(value);
      if (guid == null) return;
      final separator = guid.indexOf('://');
      if (separator <= 0) return;
      final provider = guid.substring(0, separator).toLowerCase();
      final id = guid.substring(separator + 3);
      switch (provider) {
        case 'imdb':
          imdb ??= id;
        case 'tmdb':
          tmdb ??= int.tryParse(id);
        case 'tvdb':
          tvdb ??= int.tryParse(id);
      }
    }

    consumeGuid(metadata['guid']);
    for (final guid in flexibleMapList(metadata['Guid'])) {
      consumeGuid(guid['id']);
    }

    return CatalogItemIds(plex: _nonEmptyString(metadata['ratingKey']), imdb: imdb, tmdb: tmdb, tvdb: tvdb);
  }

  static String? _nonEmptyString(Object? value) {
    final string = value?.toString().trim();
    return string == null || string.isEmpty ? null : string;
  }

  @override
  void dispose() {
    disposeWatchlistMachinery();
    _client.dispose();
  }
}
