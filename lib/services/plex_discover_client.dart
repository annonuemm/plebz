import 'dart:async';

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../media/media_kind.dart';
import '../utils/app_logger.dart';
import '../utils/external_ids.dart';
import '../utils/json_utils.dart';

/// Credentials for Plex's cloud Discover provider. The access token is scoped
/// to the active Plex/Home profile; it must never be logged or persisted here.
class PlexDiscoverSession {
  final String accessToken;
  final String clientIdentifier;

  const PlexDiscoverSession({required this.accessToken, required this.clientIdentifier});

  bool get isUsable => accessToken.isNotEmpty && clientIdentifier.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is PlexDiscoverSession && other.accessToken == accessToken && other.clientIdentifier == clientIdentifier;

  @override
  int get hashCode => Object.hash(accessToken, clientIdentifier);
}

class PlexDiscoverPage {
  final List<Map<String, dynamic>> items;
  final bool hasMore;
  final int? totalResults;

  const PlexDiscoverPage({required this.items, this.hasMore = false, this.totalResults});
}

class PlexDiscoverSearchResult {
  final Map<String, dynamic> metadata;
  final double? score;

  const PlexDiscoverSearchResult({required this.metadata, this.score});
}

class PlexDiscoverHub {
  final String id;
  final String key;
  final String title;
  final String? type;
  final String? style;
  final PlexDiscoverPage page;

  const PlexDiscoverHub({
    required this.id,
    required this.key,
    required this.title,
    required this.page,
    this.type,
    this.style,
  });
}

class PlexDiscoverException implements Exception {
  final int statusCode;
  final String message;

  const PlexDiscoverException(this.statusCode, this.message);

  @override
  String toString() => 'PlexDiscoverException($statusCode): $message';
}

/// Minimal client for the Plex cloud catalog/watchlist API advertised by
/// `https://discover.provider.plex.tv/`.
class PlexDiscoverClient {
  static final Uri _baseUri = Uri.parse('https://discover.provider.plex.tv');

  /// Shelf types whose entries never become a catalog item. `clip` shelves
  /// list trailers, which have no detail page to open and nothing to play
  /// from here. `directory` shelves — genres, awards, streaming services —
  /// are no longer among them: their entries are destinations, and the
  /// catalog source turns them into tiles that open a section of their own.
  static const Set<String> _unrenderableHubTypes = {'clip'};

  final PlexDiscoverSession session;
  final http.Client _http;
  final Duration requestTimeout;

  PlexDiscoverClient(this.session, {http.Client? httpClient, this.requestTimeout = const Duration(seconds: 20)})
    : _http = httpClient ?? http.Client();

  // `Accept-Language`/`X-Plex-Language` are per-call, never global: asking
  // Discover for German returns records whose summary is *empty* rather than
  // falling back to the English one, so sending them everywhere emptied the
  // pages of descriptions. Only callers that can handle
  // an empty answer — by asking again unlocalized, or by laying the
  // localized words over the plain record ([withLocalizedText]) — may pass a
  // language.

  /// The longest description a Discover record carries: its `summary`, or a
  /// longer entry of its `Summary` list.
  static String? overviewOf(Map<String, dynamic> metadata) {
    var overview = _nonEmptyString(metadata['summary']);
    for (final summary in flexibleMapList(metadata['Summary'])) {
      final candidate = _nonEmptyString(summary['tag'] ?? summary['summary']);
      if (candidate != null && (overview == null || candidate.length > overview.length)) {
        overview = candidate;
      }
    }
    return overview;
  }

  /// [plain] with the title and description [localized] has in the app's
  /// language, where it has them (Plebz).
  ///
  /// The plain record stays the source of everything else, and a field
  /// Discover left empty for want of a translation keeps its English words —
  /// "Der Pate" where Discover knows it, "The Godfather" where it does not.
  /// A title that changes keeps the plain one as the original where the
  /// record names none: the library lookup tries the original first.
  static Map<String, dynamic> withLocalizedText(Map<String, dynamic> plain, Map<String, dynamic>? localized) {
    if (localized == null) return plain;
    final plainTitle = _nonEmptyString(plain['title']);
    final title = _nonEmptyString(localized['title']);
    final retitled = title != null && title != plainTitle;
    final overview = overviewOf(localized);
    if (!retitled && overview == null) return plain;
    return {
      ...plain,
      if (retitled) 'title': title,
      if (retitled && plainTitle != null && _nonEmptyString(plain['originalTitle']) == null)
        'originalTitle': plainTitle,
      if (overview != null) ...{'summary': overview, 'Summary': const <Object?>[]},
    };
  }

  /// [withLocalizedText] for a page of entries, matched by rating key. The
  /// log line is the only trace of how much Discover translated: it answers
  /// nothing without a token, so it can only be read off a device.
  static List<Map<String, dynamic>> withLocalizedTexts(
    List<Map<String, dynamic>> plain,
    List<Map<String, dynamic>>? localized, {
    required String language,
    required String label,
  }) {
    if (localized == null || localized.isEmpty || plain.isEmpty) return plain;
    final byKey = {for (final entry in localized) ?_nonEmptyString(entry['ratingKey']): entry};
    var retitled = 0;
    final result = [for (final entry in plain) withLocalizedText(entry, byKey[_nonEmptyString(entry['ratingKey'])])];
    for (var i = 0; i < plain.length; i++) {
      if (!identical(result[i], plain[i]) && result[i]['title'] != plain[i]['title']) retitled++;
    }
    appLogger.d('Plex Discover: $label, $retitled of ${plain.length} titles in $language');
    return result;
  }

  /// The entries of a localized copy of a request, or null when it fails:
  /// the localized answer only ever lends words, so losing it costs the
  /// translation and nothing else.
  Future<List<Map<String, dynamic>>?> _localizedEntries(
    String path, {
    Map<String, Object?>? query,
    required String language,
    required List<Map<String, dynamic>> Function(Map<String, dynamic> container) entries,
  }) async {
    try {
      final data = await _request('GET', path, query: query, allowNotFound: true, language: language);
      return data == null ? null : entries(_mediaContainer(data));
    } catch (error) {
      appLogger.d('Plex Discover: localized $path failed', error: error);
      return null;
    }
  }

  /// Largest container size field-proven against Discover's request
  /// validation: the Explore row fetch uses it on every load. Oversized
  /// pages refetch as chunks of it, so the cap can drift below a caller's
  /// page size without breaking that caller's offset math (#1715: 500
  /// became "Invalid value provided for x-plex-container-size!").
  static const int _watchlistChunkSize = 25;

  /// [language] lays the entries' localized titles and descriptions over
  /// them ([withLocalizedTexts]); the membership snapshot needs none.
  Future<PlexDiscoverPage> getWatchlist({int page = 1, int limit = 25, String? language}) async {
    final safePage = page < 1 ? 1 : page;
    final safeLimit = limit.clamp(1, 500);
    final offset = (safePage - 1) * safeLimit;
    try {
      return await _watchlistRange(offset, safeLimit, language: language);
    } on PlexDiscoverException catch (error) {
      if (safeLimit <= _watchlistChunkSize || !_isContainerSizeRejection(error)) rethrow;
      appLogger.w('Plex Discover: container size $safeLimit rejected, refetching in chunks of $_watchlistChunkSize');
      final items = <Map<String, dynamic>>[];
      PlexDiscoverPage chunk;
      do {
        final remaining = safeLimit - items.length;
        chunk = await _watchlistRange(
          offset + items.length,
          remaining > _watchlistChunkSize ? _watchlistChunkSize : remaining,
          language: language,
        );
        items.addAll(chunk.items);
      } while (items.length < safeLimit && chunk.hasMore && chunk.items.isNotEmpty);
      return PlexDiscoverPage(items: items, hasMore: chunk.hasMore, totalResults: chunk.totalResults);
    }
  }

  Future<PlexDiscoverPage> _watchlistRange(int offset, int size, {String? language}) async {
    const path = '/library/sections/watchlist/all';
    // Asked alongside the plain page, not after it: a request more, no wait.
    final localized = language == null
        ? null
        : _localizedEntries(
            path,
            query: {'X-Plex-Container-Start': offset, 'X-Plex-Container-Size': size},
            language: language,
            entries: (container) => flexibleMapList(container['Metadata']),
          );
    final data = await _request(
      'GET',
      path,
      query: {
        'X-Plex-Container-Start': offset,
        'X-Plex-Container-Size': size,
        'includeGuids': 1,
        'includeMeta': 1,
        // What the account has already watched, so the watchlist can be
        // filtered by it. Discover knows: play state syncs there from every
        // server the account uses.
        'includeUserState': 1,
      },
    );
    final container = _mediaContainer(data!);
    final items = flexibleMapList(container['Metadata']);
    final reportedTotal = flexibleInt(container['totalSize']);
    final total = reportedTotal ?? flexibleInt(container['size']) ?? items.length;
    return PlexDiscoverPage(
      items: localized == null
          ? items
          : withLocalizedTexts(items, await localized, language: language!, label: 'watchlist'),
      hasMore: offset + items.length < total,
      totalResults: reportedTotal,
    );
  }

  static bool _isContainerSizeRejection(PlexDiscoverException error) =>
      error.statusCode == 400 && error.message.toLowerCase().contains('container-size');

  /// Discover's Home shelves — the rows Plex's own web client renders on its
  /// Home ▸ Trending tab, which reads
  /// `provider://tv.plex.provider.discover/hubs/sections/home`.
  ///
  /// The section listing is placeholders only: every hub comes back with
  /// `placeholder: true`, `size: 0` and no `Metadata`, so each rendered shelf
  /// costs one further request against its own key. Shelves that can never
  /// produce a catalog item are dropped before spending that request:
  /// `directory` shelves list browse categories (genre/decade/award) and
  /// `clip` shelves list trailers.
  /// What a shelf of destinations is asked for, whatever the caller wanted.
  ///
  /// Well under the cap Discover validates container sizes against — a cap it
  /// has moved without notice before (#1715: 500 stopped being accepted), and
  /// which answers the watchlist's 100.
  static const int _destinationShelfLimit = 60;

  Future<List<PlexDiscoverHub>> getHomeHubs({
    int limit = 25,
    int concurrency = 6,
    bool includeImageVariants = false,
    String? language,
  }) => getSectionHubs(
    '/hubs/sections/home',
    limit: limit,
    concurrency: concurrency,
    includeImageVariants: includeImageVariants,
    language: language,
  );

  /// The shelves of any Discover section, hydrated.
  ///
  /// Home is one such section; a streaming service's page
  /// (`/library/platforms/<service>`) is another, and both answer the same
  /// way — placeholders that each cost a request of their own.
  /// [language] localizes the shelf headings on the listing request, which
  /// carries no summaries to be emptied. The shelves of titles are hydrated
  /// plainly, with their localized titles and descriptions laid over them
  /// ([getHub]), so what the note above warns of cannot happen here either.
  Future<List<PlexDiscoverHub>> getSectionHubs(
    String path, {
    int limit = 25,
    int concurrency = 6,
    bool includeImageVariants = false,
    String? language,
  }) async {
    final safeLimit = limit.clamp(1, 100);
    final data = await _request('GET', path, query: {'includeMeta': 1}, language: language);
    final container = _mediaContainer(data!);
    final candidates = <({String id, String key, String title, String? type, String? style})>[];
    final seen = <String>{};
    for (final hub in flexibleMapList(container['Hub'])) {
      final type = _nonEmptyString(hub['type']);
      final style = _nonEmptyString(hub['style']);
      if (_unrenderableHubTypes.contains(type) && style != 'availabilityPlatforms') continue;
      final key = _nonEmptyString(hub['key'] ?? hub['hubKey']);
      final id = _nonEmptyString(hub['hubIdentifier']) ?? key;
      final title = _nonEmptyString(hub['title']);
      if (key == null || id == null || title == null || !seen.add(id)) continue;
      candidates.add((id: id, key: key, title: title, type: type, style: style));
    }
    if (candidates.isEmpty && language != null) {
      // A localized answer that named nothing. Discover leaves fields empty
      // where it has no translation rather than falling back, and a section
      // without headings is a section without rows — so ask again plainly.
      appLogger.d('Plex Discover: $path named no shelf in $language, retrying unlocalized');
      return getSectionHubs(path, limit: limit, concurrency: concurrency, includeImageVariants: includeImageVariants);
    }
    if (candidates.isEmpty) return const [];

    // One shelf failing (a hub retired between listing and hydration, a
    // transient 5xx) must not sink the whole tab, but a pass where every
    // shelf failed is a real failure and keeps the caller's error surface.
    final pages = List<PlexDiscoverPage?>.filled(candidates.length, null);
    // How many entries each shelf is asked for. A shelf of *titles* shows a
    // handful and offers "View All" for the rest, so the caller's size is
    // right. A shelf of *destinations* — genres, awards, the services — has no
    // "View All" anywhere in the app: whatever the container size cuts is
    // simply gone. At the caller's 25 Plex's genre list was cut part way
    // through, which is why "History" never appeared in it.
    final limits = [
      for (final candidate in candidates)
        candidate.type == 'directory' || candidate.style == 'availabilityPlatforms'
            ? _destinationShelfLimit
            : safeLimit,
    ];
    Object? firstError;
    StackTrace? firstStackTrace;
    var cursor = 0;
    Future<void> hydrate() async {
      while (true) {
        final index = cursor++;
        if (index >= candidates.length) return;
        final candidate = candidates[index];
        try {
          // One over the shelf size is what tells View All there is more.
          pages[index] = await getHub(
            candidate.key,
            limit: limits[index] + 1,
            includeImageVariants: includeImageVariants,
            // Destinations are named in the listing's words already.
            language: candidate.type == 'directory' || candidate.style == 'availabilityPlatforms' ? null : language,
          );
        } catch (error, stackTrace) {
          firstError ??= error;
          firstStackTrace ??= stackTrace;
          appLogger.w('Plex Discover: hub ${candidate.id} of $path failed', error: error, stackTrace: stackTrace);
        }
      }
    }

    await Future.wait([for (var i = concurrency.clamp(1, candidates.length); i > 0; i--) hydrate()]);
    if (firstError case final error? when pages.every((page) => page == null)) {
      Error.throwWithStackTrace(error, firstStackTrace!);
    }

    return [
      for (var i = 0; i < candidates.length; i++)
        if (pages[i] case final page? when page.items.isNotEmpty)
          PlexDiscoverHub(
            id: candidates[i].id,
            key: candidates[i].key,
            title: candidates[i].title,
            type: candidates[i].type,
            style: candidates[i].style,
            page: PlexDiscoverPage(
              items: page.items.take(limits[i]).toList(),
              hasMore: page.items.length > limits[i] || (page.totalResults != null && page.totalResults! > limits[i]),
              totalResults: page.totalResults,
            ),
          ),
    ];
  }

  /// One Discover hub in full. The provider ignores container offsets on hub
  /// keys and truncates with `limit` instead, so a hub is always a single
  /// page and [PlexDiscoverPage.hasMore] never reports one.
  /// How many placeholder shelves one page is followed into. A service's page
  /// runs to a dozen rows and each is a request of its own; the first few
  /// already fill a grid.
  static const int _shelfHydrationLimit = 8;

  ///
  /// [language] lays the entries' localized titles and descriptions over the
  /// plain ones ([withLocalizedTexts]).
  Future<PlexDiscoverPage> getHub(
    String key, {
    int limit = 100,
    bool includeImageVariants = false,
    bool hydrateShelves = true,
    String? language,
  }) async {
    final safeLimit = limit.clamp(1, 500);
    // Asked alongside the plain hub, not after it: a request more, no wait.
    // A page of placeholders wastes it; its shelves ask for their own.
    final localized = language == null
        ? null
        : _localizedEntries(
            key,
            query: {'limit': safeLimit, 'excludeElements': 'Media,Image'},
            language: language,
            entries: _hubEntries,
          );
    final data = await _request(
      'GET',
      key,
      query: {
        'limit': safeLimit,
        'includeGuids': 1,
        'includeMeta': 1,
        'includeUserState': 1,
        // Allowing Image on the measured 26-item hub grew 27,287 -> 55,925
        // bytes (+104.95%). Discover is uncached and Home hydrates up to six
        // hubs concurrently, so spotlight/logo consumers must opt in per
        // request and ordinary shelves stay narrow.
        'excludeElements': includeImageVariants ? 'Media' : 'Media,Image',
      },
    );
    final container = _mediaContainer(data!);
    final hubs = flexibleMapList(container['Hub']);
    final items = _hubEntries(container);
    if (items.isNotEmpty || !hydrateShelves) {
      final page = items.take(safeLimit).toList();
      return PlexDiscoverPage(
        items: localized == null ? page : withLocalizedTexts(page, await localized, language: language!, label: key),
        totalResults: flexibleInt(container['totalSize']),
      );
    }

    // Nothing here, but shelves that say where it is. Discover answers a
    // section with placeholders — `size: 0` and no entries — and expects each
    // shelf to be fetched by its own key; that is what Home does, and a
    // streaming service's page is built the same way.
    return PlexDiscoverPage(
      items: await _hydrateShelves(
        hubs,
        limit: safeLimit,
        includeImageVariants: includeImageVariants,
        language: language,
      ),
    );
  }

  /// A hub answer's entries. Every shelf the answer carries counts: usually
  /// one — the hub that was asked for — but a streaming service's own key
  /// answers with its whole page, and then the titles are spread over
  /// several. Four places to look, because Discover files a shelf's entries
  /// wherever suits it: titles as Metadata, destinations — a streaming
  /// service, say — as Directory, either on the container or in the shelves
  /// it wraps. The first that holds anything wins; appending would list a
  /// hub's entries twice where the container repeats them.
  static List<Map<String, dynamic>> _hubEntries(Map<String, dynamic> container) {
    final hubs = flexibleMapList(container['Hub']);
    List<Map<String, dynamic>> fromHubs(String field) => [for (final hub in hubs) ...flexibleMapList(hub[field])];
    return [
      flexibleMapList(container['Metadata']),
      fromHubs('Metadata'),
      flexibleMapList(container['Directory']),
      fromHubs('Directory'),
    ].firstWhere((found) => found.isNotEmpty, orElse: () => const []);
  }

  /// The entries of [hubs], fetched one key at a time and merged in order.
  ///
  /// One shelf failing costs that shelf: a page half full beats an empty one,
  /// and the caller has no way to retry a single row.
  Future<List<Map<String, dynamic>>> _hydrateShelves(
    List<Map<String, dynamic>> hubs, {
    required int limit,
    required bool includeImageVariants,
    String? language,
  }) async {
    final keys = [
      for (final hub in hubs) ?_nonEmptyString(hub['key'] ?? hub['hubKey']),
    ].take(_shelfHydrationLimit).toList();
    if (keys.isEmpty) return const [];

    final pages = await Future.wait([
      for (final key in keys)
        getHub(
          key,
          limit: limit,
          includeImageVariants: includeImageVariants,
          hydrateShelves: false,
          language: language,
        ).then<PlexDiscoverPage?>(
          (page) => page,
          onError: (Object error) {
            appLogger.w('Plex Discover: shelf $key of a followed hub failed', error: error);
            return null;
          },
        ),
    ]);
    return [for (final page in pages) ...?page?.items].take(limit).toList();
  }

  Future<List<PlexDiscoverSearchResult>> search(String query, {int limit = 30}) async {
    final data = await _request(
      'GET',
      '/library/search',
      query: {
        'query': query,
        'limit': limit.clamp(1, 100),
        'searchTypes': 'movies,tv',
        'searchProviders': 'discover',
        'includeGuids': 1,
        'includeMetadata': 1,
        'filterPeople': 1,
      },
    );
    final container = _mediaContainer(data!);
    return [
      for (final group in flexibleMapList(container['SearchResults']))
        for (final result in flexibleMapList(group['SearchResult']))
          if (firstFlexibleMap(result['Metadata']) case final Map<String, dynamic> metadata)
            PlexDiscoverSearchResult(metadata: metadata, score: flexibleDouble(result['score'])),
    ];
  }

  /// Discover's entry for the item carrying any of [ids].
  ///
  /// Every id form is tried, not just the first one present: the match
  /// endpoint indexes a title under whichever ids Plex's own agent recorded
  /// for it, and a library whose agent supplied a different set would
  /// otherwise miss a title Discover plainly has.
  ///
  /// The lookup only answers when the guid is paired with the numeric
  /// metadata `type` (1 movie, 2 show) — a bare guid returns an empty
  /// container for every item (#1873).
  Future<Map<String, dynamic>?> match(ExternalIds ids, {required MediaKind kind}) async {
    final type = switch (kind) {
      MediaKind.movie => 1,
      MediaKind.show => 2,
      _ => null,
    };
    if (type == null) return null;
    for (final guid in [
      if (ids.imdb != null) 'imdb://${ids.imdb}',
      if (ids.tmdb != null) 'tmdb://${ids.tmdb}',
      if (ids.tvdb != null) 'tvdb://${ids.tvdb}',
    ]) {
      final data = await _request(
        'GET',
        '/library/metadata/matches',
        query: {'type': type, 'guid': guid, 'includeGuids': 1},
        allowNotFound: true,
      );
      final metadata = data == null ? null : firstFlexibleMap(_mediaContainer(data)['Metadata']);
      if (metadata != null) return metadata;
    }
    return null;
  }

  /// The Discover entry for [title] whose own ids overlap [ids].
  ///
  /// The fallback for a title the id match does not answer for although
  /// Discover's search finds it — two different indexes, and only the search
  /// one is guaranteed to cover what the app's own Discover pages show. The
  /// result still has to carry one of the ids: a title-only hit could be any
  /// remake, and a wrong entry on a watchlist is worse than none.
  Future<Map<String, dynamic>?> matchByTitle(String title, ExternalIds ids) async {
    if (title.trim().isEmpty || !ids.hasCatalogIds) return null;
    final results = await search(title, limit: 20);

    // Search rows do not reliably carry their `Guid` array even when asked
    // for it, so the ones that cannot be verified in place are confirmed
    // with a metadata read. Bounded: a handful of extra requests is a fair
    // price for one watchlist press, a search page of them is not.
    const maxMetadataProbes = 3;
    final unverified = <String>[];
    for (final result in results) {
      final guids = result.metadata['Guid'];
      if (guids is List && guids.isNotEmpty) {
        if (ExternalIds.fromGuids(guids).intersects(ids)) return result.metadata;
        continue;
      }
      final ratingKey = result.metadata['ratingKey']?.toString();
      if (ratingKey != null && ratingKey.isNotEmpty && unverified.length < maxMetadataProbes) {
        unverified.add(ratingKey);
      }
    }

    for (final ratingKey in unverified) {
      final metadata = await getMetadata(ratingKey);
      final guids = metadata?['Guid'];
      if (guids is List && ExternalIds.fromGuids(guids).intersects(ids)) return metadata;
    }
    return null;
  }

  /// Full metadata for one Discover item.
  ///
  /// [language] asks for a localized record; see the note on the headers
  /// above. A caller that passes one must be prepared for an empty summary and
  /// ask again without it.
  Future<Map<String, dynamic>?> getMetadata(String ratingKey, {String? language}) async {
    final data = await _request(
      'GET',
      '/library/metadata/${Uri.encodeComponent(ratingKey)}',
      query: {'includeGuids': 1},
      allowNotFound: true,
      language: language,
    );
    if (data == null) return null;
    return firstFlexibleMap(_mediaContainer(data)['Metadata']);
  }

  /// [language] behaves as in [getHub].
  Future<List<Map<String, dynamic>>> getRelated(String ratingKey, {String? language}) async {
    final path = '/library/metadata/${Uri.encodeComponent(ratingKey)}/related';
    final localized = language == null ? null : _localizedEntries(path, language: language, entries: _relatedEntries);
    final data = await _request('GET', path, allowNotFound: true);
    if (data == null) return const [];
    final entries = _relatedEntries(_mediaContainer(data));
    return localized == null
        ? entries
        : withLocalizedTexts(entries, await localized, language: language!, label: 'related');
  }

  static List<Map<String, dynamic>> _relatedEntries(Map<String, dynamic> container) => [
    for (final hub in flexibleMapList(container['Hub'])) ...flexibleMapList(hub['Metadata']),
    if (container['Hub'] == null) ...flexibleMapList(container['Metadata']),
  ];

  /// People whose name matches [name], best match first: the `Directory` rows
  /// of a people search, each carrying `metadataId`, `title` and `thumb`.
  Future<List<Map<String, dynamic>>> searchPeople(String name, {int limit = 5}) async {
    final data = await _request(
      'GET',
      '/library/search',
      query: {'query': name, 'limit': limit.clamp(1, 20), 'searchTypes': 'people', 'searchProviders': 'discover'},
    );
    final container = _mediaContainer(data!);
    return [
      for (final group in flexibleMapList(container['SearchResults']))
        for (final result in flexibleMapList(group['SearchResult']))
          if (firstFlexibleMap(result['Directory']) case final Map<String, dynamic> person)
            if (person['type'] == null || person['type'] == 'person') person,
    ];
  }

  /// One person's record — `summary`, `bornAt`, `diedAt`, `birthPlace`,
  /// `thumb` — or null when Discover does not know [personId].
  ///
  /// [personId] is the hex id a cast entry carries (`Role.id`), never a
  /// server's numeric tag id. [language] behaves as in [getMetadata].
  Future<Map<String, dynamic>?> getPerson(String personId, {String? language}) async {
    final data = await _request(
      'GET',
      '/library/people/${Uri.encodeComponent(personId)}',
      allowNotFound: true,
      language: language,
    );
    if (data == null) return null;
    final container = _mediaContainer(data);
    return firstFlexibleMap(container['Metadata']) ?? firstFlexibleMap(container['Directory']);
  }

  /// A person's filmography as Discover groups it — "Actor", "Producer",
  /// "Appearances" — each group `{type, title, Credit: [{role, Metadata}]}`
  /// with one Discover item per credit. An unknown person answers an empty
  /// list; a body without groups throws, since that is not an empty career.
  ///
  /// [language] lays each credit's localized title and description over it,
  /// as [getHub] does.
  Future<List<Map<String, dynamic>>> getPersonCredits(String personId, {String? language}) async {
    final path = '/library/people/${Uri.encodeComponent(personId)}/credits';
    final localized = language == null
        ? null
        : _localizedEntries(
            path,
            language: language,
            entries: (container) => _creditEntries(flexibleMapList(container['CreditGroup'])),
          );
    final data = await _request('GET', path, allowNotFound: true);
    if (data == null) return const [];
    final container = _mediaContainer(data);
    final groups = container['CreditGroup'];
    if (groups == null) {
      if (flexibleInt(container['size']) == 0 || flexibleInt(container['totalSize']) == 0) return const [];
      throw const PlexDiscoverException(200, 'Person credits carried no CreditGroup');
    }
    final plainGroups = flexibleMapList(groups);
    if (localized == null) return plainGroups;
    final overlaid = withLocalizedTexts(
      _creditEntries(plainGroups),
      await localized,
      language: language!,
      label: 'person credits',
    );
    // Back into the groups in the order they were read out.
    var next = 0;
    return [
      for (final group in plainGroups)
        {
          ...group,
          'Credit': [
            for (final credit in flexibleMapList(group['Credit']))
              if (firstFlexibleMap(credit['Metadata']) != null) {...credit, 'Metadata': overlaid[next++]} else credit,
          ],
        },
    ];
  }

  static List<Map<String, dynamic>> _creditEntries(List<Map<String, dynamic>> groups) => [
    for (final group in groups)
      for (final credit in flexibleMapList(group['Credit'])) ?firstFlexibleMap(credit['Metadata']),
  ];

  Future<void> setWatchlisted(String ratingKey, {required bool add}) async {
    await _request(
      'PUT',
      add ? '/actions/addToWatchlist' : '/actions/removeFromWatchlist',
      query: {'ratingKey': ratingKey},
    );
  }

  Future<Map<String, dynamic>?> _request(
    String method,
    String path, {
    Map<String, Object?>? query,
    bool allowNotFound = false,
    String? language,
  }) async {
    var relative = Uri.parse(path);
    // A key Discover wrote itself may carry the host it is already on. That
    // is the same address, so it is accepted and reduced to its path; any
    // other host still stops here.
    if (relative.host == _baseUri.host && (relative.scheme.isEmpty || relative.scheme == _baseUri.scheme)) {
      relative = relative.replace(scheme: '', host: '');
    }
    if (relative.hasScheme || relative.host.isNotEmpty || !relative.path.startsWith('/')) {
      throw ArgumentError.value(path, 'path', 'Plex Discover paths must stay on the provider host');
    }
    final uri = _baseUri.replace(
      path: relative.path,
      queryParameters: {
        ...relative.queryParameters,
        for (final entry in query?.entries ?? const <MapEntry<String, Object?>>[])
          if (entry.value != null) entry.key: entry.value.toString(),
      },
    );
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'X-Plex-Token': session.accessToken,
      'X-Plex-Client-Identifier': session.clientIdentifier,
      'X-Plex-Product': 'Plezy',
      'X-Plex-Version': '2',
      if (language != null) ...{'Accept-Language': language, 'X-Plex-Language': language},
    };
    final request = switch (method) {
      'GET' => _http.get(uri, headers: headers),
      'PUT' => _http.put(uri, headers: headers),
      _ => throw ArgumentError.value(method, 'method', 'Unsupported Plex Discover method'),
    };
    final stopwatch = Stopwatch()..start();
    final response = await request.timeout(requestTimeout);
    // The other API surfaces log every request; without this line Discover
    // drift is invisible in reporter logs (#1715 shipped blind).
    appLogger.d('Discover $method ${relative.path} → ${response.statusCode} (${stopwatch.elapsedMilliseconds}ms)');
    if (allowNotFound && response.statusCode == 404) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PlexDiscoverException(response.statusCode, _errorMessage(response.body));
    }
    if (response.body.isEmpty) return const <String, dynamic>{};
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic> ? decoded : const <String, dynamic>{};
  }

  static Map<String, dynamic> _mediaContainer(Map<String, dynamic> data) =>
      firstFlexibleMap(data['MediaContainer']) ?? const <String, dynamic>{};

  static String? _nonEmptyString(Object? value) {
    final string = value?.toString().trim();
    return string == null || string.isEmpty ? null : string;
  }

  static String _errorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      final error = decoded is Map<String, dynamic> ? firstFlexibleMap(decoded['Error']) : null;
      return error?['message']?.toString() ?? error?['error']?.toString() ?? 'Request failed';
    } catch (_) {
      return 'Request failed';
    }
  }

  void dispose() => _http.close();
}
