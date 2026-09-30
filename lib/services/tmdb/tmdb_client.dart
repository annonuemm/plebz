import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../utils/abortable_http_request.dart';
import '../../utils/app_logger.dart';
import '../../utils/external_ids.dart';
import '../../utils/platform_http_client_stub.dart'
    if (dart.library.io) '../../utils/platform_http_client_io.dart'
    as platform;

/// Read-only TMDB v3 client, used to fill in artwork the media server does not
/// have. It never writes to the user's TMDB account and never sends anything
/// but an id and a language preference.
///
/// Accepts either credential TMDB hands out on the same settings page: a v3 API
/// key travels as a query parameter, a v4 read access token (a JWT) as a bearer
/// header. Users copy whichever field they land on, so guessing from the shape
/// is friendlier than making them find the right one.
class TmdbClient {
  static const String apiBase = 'https://api.themoviedb.org/3';
  static const String imageBase = 'https://image.tmdb.org/t/p';

  /// Clear logos are drawn over artwork at roughly a third of the screen
  /// width; w500 covers that on a 4K panel and keeps the transparent PNGs
  /// small enough for a low-end TV's image cache.
  static const String logoSize = 'w500';

  /// Filmography posters are grid cards, not full-bleed art.
  static const String posterSize = 'w342';

  static const Duration _timeout = Duration(seconds: 15);

  final String credential;
  final http.Client _http;
  final bool _ownsClient;

  TmdbClient(this.credential, {http.Client? httpClient})
    : _http = httpClient ?? platform.createPlatformClient(),
      _ownsClient = httpClient == null;

  void dispose() {
    if (_ownsClient) _http.close();
  }

  /// A v4 read access token is a JWT; a v3 key is 32 hex characters.
  bool get _isBearerToken => credential.startsWith('ey') && credential.split('.').length == 3;

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    if (_isBearerToken) 'Authorization': 'Bearer $credential',
  };

  Uri _uri(String path, [Map<String, String> query = const {}]) =>
      Uri.parse('$apiBase$path').replace(queryParameters: {if (!_isBearerToken) 'api_key': credential, ...query});

  /// Whether the stored credential is accepted by TMDB. `/configuration` is the
  /// cheapest authenticated endpoint and answers 401 for a bad key.
  Future<bool> verifyCredential() async {
    if (credential.isEmpty) return false;
    final response = await _get(_uri('/configuration'), operation: 'TMDB verify');
    return response?.statusCode == 200;
  }

  /// The TMDB id for an item, resolved from whatever id the server knows.
  ///
  /// Never guesses from title and year: that would happily return the wrong
  /// film, and a wrong logo is worse than none.
  ///
  /// `conclusive` says whether TMDB actually answered. A failed request is not
  /// the same as "no such title", and callers cache only the latter.
  Future<({int? id, bool conclusive})> resolveId({required bool isMovie, required ExternalIds ids}) async {
    if (ids.tmdb != null) return (id: ids.tmdb, conclusive: true);

    final imdb = ids.imdb;
    if (imdb != null && imdb.isNotEmpty) {
      final found = await _find(imdb, source: 'imdb_id', isMovie: isMovie);
      if (found.id != null || !found.conclusive) return found;
    }

    // TVDB ids only ever name a series, so a movie lookup would be a category
    // error even when the id is present.
    final tvdb = ids.tvdb;
    if (!isMovie && tvdb != null) {
      return _find('$tvdb', source: 'tvdb_id', isMovie: isMovie);
    }
    return (id: null, conclusive: true);
  }

  Future<({int? id, bool conclusive})> _find(String externalId, {required String source, required bool isMovie}) async {
    final response = await _get(_uri('/find/$externalId', {'external_source': source}), operation: 'TMDB find $source');
    final body = _decode(response);
    if (body == null) return (id: null, conclusive: false);
    final results = body[isMovie ? 'movie_results' : 'tv_results'];
    if (results is! List || results.isEmpty) return (id: null, conclusive: true);
    final first = results.first;
    return (id: first is Map && first['id'] is int ? first['id'] as int : null, conclusive: true);
  }

  /// Everything this client fills in for one title, in a single request.
  ///
  /// `conclusive` is false when the request itself failed — a caller may cache
  /// "TMDB has nothing" forever and must never cache "I could not ask".
  ///
  /// [languages] is a preference order of ISO-639-1 codes. Logos add
  /// language-neutral artwork (TMDB's `null` language, typically a wordless
  /// mark) as a last resort; the overview is fetched in the first language and
  /// retried in English when TMDB has no translation for it.
  ///
  /// `append_to_response` is what makes this one request rather than two: the
  /// details payload carries the overview, and the appended images block
  /// carries the logos.
  Future<({TmdbFillIn? fillIn, bool conclusive})> fetchFillIn({
    required bool isMovie,
    required int tmdbId,
    required List<String> languages,
  }) async {
    final path = '/${isMovie ? 'movie' : 'tv'}/$tmdbId';
    final primary = languages.isEmpty ? 'en' : languages.first;
    final response = await _get(
      _uri(path, {
        'language': primary,
        'append_to_response': 'images',
        'include_image_language': [...languages, 'null'].join(','),
      }),
      operation: 'TMDB details',
    );
    final body = _decode(response);
    if (body == null) return (fillIn: null, conclusive: false);

    final logos = (body['images'] as Map?)?['logos'];
    final logoPath = logos is List ? _bestLogoPath(logos.whereType<Map>(), languages) : null;

    var overview = _nonEmpty(body['overview']);
    if (overview == null && primary != 'en') {
      // TMDB returns an empty overview rather than falling back, so an untranslated
      // title needs a second ask. Best-effort: a failure here still leaves a usable
      // logo, so it does not make the whole answer inconclusive.
      final english = _decode(await _get(_uri(path, {'language': 'en'}), operation: 'TMDB overview (en)'));
      overview = _nonEmpty(english?['overview']);
    }

    return (
      fillIn: TmdbFillIn(logoUrl: logoPath == null ? null : '$imageBase/$logoSize$logoPath', summary: overview),
      conclusive: true,
    );
  }

  static String? _nonEmpty(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// The TMDB id of the person credited as [name] on a title.
  ///
  /// Resolved through the title rather than by searching for the name: two
  /// actors share a name often enough that a search would sometimes open the
  /// wrong filmography, and the title the viewer just came from names exactly
  /// one of them.
  Future<int?> personIdInCast({required bool isMovie, required int tmdbId, required String name}) async {
    final path = isMovie ? '/movie/$tmdbId/credits' : '/tv/$tmdbId/aggregate_credits';
    final body = _decode(await _get(_uri(path), operation: 'TMDB cast'));
    final cast = body?['cast'];
    if (cast is! List) return null;

    final wanted = _normalizedName(name);
    for (final member in cast.whereType<Map>()) {
      if (_normalizedName(member['name']?.toString() ?? '') != wanted) continue;
      final id = member['id'];
      if (id is int) return id;
    }
    return null;
  }

  /// Every film and series a person is credited in, newest first.
  ///
  /// Asked for in the app's language so the titles line up with what a German
  /// library calls the same films — the caller matches them by title.
  Future<List<TmdbCredit>> personCredits({required int personId, required List<String> languages}) async {
    final body = _decode(
      await _get(
        _uri('/person/$personId/combined_credits', {'language': languages.isEmpty ? 'en' : languages.first}),
        operation: 'TMDB filmography',
      ),
    );
    final cast = body?['cast'];
    if (cast is! List) return const [];

    final credits = <TmdbCredit>[];
    final seen = <String>{};
    for (final entry in cast.whereType<Map>()) {
      final credit = TmdbCredit.fromJson(entry);
      // The same title appears once per role played in it.
      if (credit == null || !seen.add('${credit.isMovie}:${credit.tmdbId}')) continue;
      credits.add(credit);
    }
    credits.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
    return credits;
  }

  static String _normalizedName(String name) => name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Highest-rated logo in the earliest language that has one. Language beats
  /// rating deliberately: a mediocre German logo still reads as the title the
  /// user sees everywhere else in the app, an excellent Japanese one does not.
  static String? _bestLogoPath(Iterable<Map> logos, List<String> languages) {
    for (final language in [...languages, null]) {
      Map? best;
      for (final logo in logos) {
        if (logo['iso_639_1'] != language) continue;
        final path = logo['file_path'];
        if (path is! String || path.isEmpty) continue;
        if (best == null || _score(logo) > _score(best)) best = logo;
      }
      if (best != null) return best['file_path'] as String;
    }
    return null;
  }

  static double _score(Map logo) {
    final vote = logo['vote_average'];
    return vote is num ? vote.toDouble() : 0;
  }

  Future<http.Response?> _get(Uri uri, {required String operation}) async {
    try {
      final response = await sendAbortableHttpRequest(
        _http,
        'GET',
        uri,
        headers: _headers,
        timeout: _timeout,
        operation: operation,
      );
      if (response.statusCode != 200) {
        appLogger.d('$operation -> ${response.statusCode}');
      }
      return response;
    } catch (e) {
      // Artwork is decoration: a failed lookup logs and leaves the title text
      // in place, it never surfaces as an error to the user.
      appLogger.d('$operation failed', error: e);
      return null;
    }
  }

  static Map<String, dynamic>? _decode(http.Response? response) {
    if (response == null || response.statusCode != 200) return null;
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      appLogger.d('TMDB response was not JSON', error: e);
      return null;
    }
  }
}

/// What TMDB knows about a title that the media server did not supply.
///
/// Both fields are independently optional: plenty of titles have a logo and no
/// German overview, or the other way round.
class TmdbFillIn {
  const TmdbFillIn({this.logoUrl, this.summary});

  final String? logoUrl;
  final String? summary;

  bool get isEmpty => logoUrl == null && summary == null;
}

/// One title in a person's filmography.
class TmdbCredit {
  const TmdbCredit({required this.tmdbId, required this.isMovie, required this.title, this.year, this.posterUrl});

  /// Null for an entry with no id, no title, or a media type this app does not
  /// show (a person is also credited on episodes and collections).
  static TmdbCredit? fromJson(Map<dynamic, dynamic> json) {
    final mediaType = json['media_type'];
    if (mediaType != 'movie' && mediaType != 'tv') return null;
    final id = json['id'];
    if (id is! int) return null;
    final isMovie = mediaType == 'movie';
    final title = (isMovie ? json['title'] : json['name'])?.toString().trim();
    if (title == null || title.isEmpty) return null;
    final date = (isMovie ? json['release_date'] : json['first_air_date'])?.toString();
    final poster = json['poster_path'];
    return TmdbCredit(
      tmdbId: id,
      isMovie: isMovie,
      title: title,
      year: date == null || date.length < 4 ? null : int.tryParse(date.substring(0, 4)),
      posterUrl: poster is String && poster.isNotEmpty
          ? '${TmdbClient.imageBase}/${TmdbClient.posterSize}$poster'
          : null,
    );
  }

  final int tmdbId;
  final bool isMovie;
  final String title;
  final int? year;
  final String? posterUrl;
}
