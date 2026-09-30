import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/services/tmdb/tmdb_client.dart';
import 'package:plezy/utils/external_ids.dart';

/// A JWT-shaped credential; only the three-segment shape matters.
const _readAccessToken = 'eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiJwbGV6eSJ9.c2lnbmF0dXJl';

http.Response _json(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

Map<String, Object?> _details(List<Map<String, Object?>> logos, {String? overview}) => {
  'id': 1,
  'overview': ?overview,
  'images': {'logos': logos},
};

Map<String, Object?> _logo(String path, {String? language, double vote = 0}) => {
  'file_path': path,
  'iso_639_1': language,
  'vote_average': vote,
};

void main() {
  group('fetchFillIn', () {
    test('prefers the first requested language over a better-rated later one', () async {
      final client = TmdbClient(
        'key',
        httpClient: MockClient(
          (_) async => _json(
            _details([_logo('/english.png', language: 'en', vote: 9), _logo('/german.png', language: 'de', vote: 1)]),
          ),
        ),
      );

      expect(
        (await client.fetchFillIn(isMovie: true, tmdbId: 1, languages: ['de', 'en'])).fillIn?.logoUrl,
        '${TmdbClient.imageBase}/${TmdbClient.logoSize}/german.png',
      );
    });

    test('falls back to the next language, then to language-neutral artwork', () async {
      final englishOnly = TmdbClient(
        'key',
        httpClient: MockClient((_) async => _json(_details([_logo('/english.png', language: 'en')]))),
      );
      expect(
        (await englishOnly.fetchFillIn(isMovie: false, tmdbId: 1, languages: ['de', 'en'])).fillIn?.logoUrl,
        endsWith('/english.png'),
      );

      final neutralOnly = TmdbClient(
        'key',
        httpClient: MockClient((_) async => _json(_details([_logo('/neutral.png')]))),
      );
      expect(
        (await neutralOnly.fetchFillIn(isMovie: false, tmdbId: 1, languages: ['de', 'en'])).fillIn?.logoUrl,
        endsWith('/neutral.png'),
      );
    });

    test('picks the highest-rated logo within a language', () async {
      final client = TmdbClient(
        'key',
        httpClient: MockClient(
          (_) async => _json(
            _details([
              _logo('/meh.png', language: 'de', vote: 2),
              _logo('/best.png', language: 'de', vote: 7.5),
              _logo('/good.png', language: 'de', vote: 5),
            ]),
          ),
        ),
      );

      expect(
        (await client.fetchFillIn(isMovie: true, tmdbId: 1, languages: ['de'])).fillIn?.logoUrl,
        endsWith('/best.png'),
      );
    });

    test('separates "TMDB has none" from "the request failed"', () async {
      final empty = TmdbClient('key', httpClient: MockClient((_) async => _json(_details([]))));
      final none = await empty.fetchFillIn(isMovie: true, tmdbId: 1, languages: ['en']);
      expect(none.fillIn?.isEmpty, isTrue);
      expect(none.conclusive, isTrue);

      // A caller may cache the first answer forever and must not cache this
      // one at all, so the two can never collapse into a bare null.
      final failing = TmdbClient('key', httpClient: MockClient((_) async => http.Response('nope', 401)));
      final failed = await failing.fetchFillIn(isMovie: true, tmdbId: 1, languages: ['en']);
      expect(failed.fillIn, isNull);
      expect(failed.conclusive, isFalse);
    });

    test('gets the overview and the logos in one request', () async {
      final seen = <Uri>[];
      final client = TmdbClient(
        'key',
        httpClient: MockClient((request) async {
          seen.add(request.url);
          return _json(_details([_logo('/logo.png', language: 'de')], overview: 'Eine Beschreibung.'));
        }),
      );

      final result = await client.fetchFillIn(isMovie: false, tmdbId: 42, languages: ['de', 'en']);

      expect(seen.single.path, '/3/tv/42');
      expect(seen.single.queryParameters['language'], 'de');
      expect(seen.single.queryParameters['append_to_response'], 'images');
      expect(seen.single.queryParameters['include_image_language'], 'de,en,null');
      expect(result.fillIn?.summary, 'Eine Beschreibung.');
      expect(result.fillIn?.logoUrl, endsWith('/logo.png'));
    });

    test('retries the overview in English when the title is untranslated', () async {
      final seen = <Uri>[];
      final client = TmdbClient(
        'key',
        httpClient: MockClient((request) async {
          seen.add(request.url);
          // TMDB answers with an empty overview rather than falling back itself.
          final isRetry = request.url.queryParameters['language'] == 'en';
          return _json(_details([], overview: isRetry ? 'An English description.' : ''));
        }),
      );

      final result = await client.fetchFillIn(isMovie: true, tmdbId: 42, languages: ['de', 'en']);

      expect(seen, hasLength(2));
      expect(seen.last.queryParameters['language'], 'en');
      expect(result.fillIn?.summary, 'An English description.');
    });

    test('does not ask twice when the first language already answered', () async {
      var requests = 0;
      final client = TmdbClient(
        'key',
        httpClient: MockClient((_) async {
          requests++;
          return _json(_details([], overview: 'Eine Beschreibung.'));
        }),
      );

      await client.fetchFillIn(isMovie: true, tmdbId: 42, languages: ['de', 'en']);

      expect(requests, 1);
    });
  });

  group('credentials', () {
    test('a v3 key travels as a query parameter', () async {
      late http.Request seen;
      final client = TmdbClient(
        'abc123',
        httpClient: MockClient((request) async {
          seen = request;
          return _json(_details([]));
        }),
      );

      await client.fetchFillIn(isMovie: true, tmdbId: 1, languages: ['en']);

      expect(seen.url.queryParameters['api_key'], 'abc123');
      expect(seen.headers.containsKey('Authorization'), isFalse);
    });

    test('a v4 read access token travels as a bearer header', () async {
      late http.Request seen;
      final client = TmdbClient(
        _readAccessToken,
        httpClient: MockClient((request) async {
          seen = request;
          return _json(_details([]));
        }),
      );

      await client.fetchFillIn(isMovie: true, tmdbId: 1, languages: ['en']);

      expect(seen.url.queryParameters.containsKey('api_key'), isFalse);
      expect(seen.headers['Authorization'], 'Bearer $_readAccessToken');
    });

    test('verifyCredential reports what TMDB answered', () async {
      final accepted = TmdbClient('key', httpClient: MockClient((_) async => _json({'images': {}})));
      expect(await accepted.verifyCredential(), isTrue);

      final rejected = TmdbClient('key', httpClient: MockClient((_) async => http.Response('{}', 401)));
      expect(await rejected.verifyCredential(), isFalse);

      final missing = TmdbClient('', httpClient: MockClient((_) async => fail('must not be asked')));
      expect(await missing.verifyCredential(), isFalse);
    });
  });

  group('resolveId', () {
    test('uses a TMDB id without asking anyone', () async {
      final client = TmdbClient('key', httpClient: MockClient((_) async => fail('must not be asked')));
      expect((await client.resolveId(isMovie: true, ids: const ExternalIds(tmdb: 603))).id, 603);
    });

    test('finds a movie by its IMDb id', () async {
      late Uri seen;
      final client = TmdbClient(
        'key',
        httpClient: MockClient((request) async {
          seen = request.url;
          return _json({
            'movie_results': [
              {'id': 603},
            ],
            'tv_results': [],
          });
        }),
      );

      expect((await client.resolveId(isMovie: true, ids: const ExternalIds(imdb: 'tt0133093'))).id, 603);
      expect(seen.path, '/3/find/tt0133093');
      expect(seen.queryParameters['external_source'], 'imdb_id');
    });

    test('finds a show by its TVDB id, but never a movie', () async {
      var calls = 0;
      http.Client build() => MockClient((request) async {
        calls++;
        return _json({
          'movie_results': [],
          'tv_results': [
            {'id': 1396},
          ],
        });
      });

      expect(
        (await TmdbClient(
          'key',
          httpClient: build(),
        ).resolveId(isMovie: false, ids: const ExternalIds(tvdb: 81189))).id,
        1396,
      );
      expect(calls, 1);

      expect(
        (await TmdbClient('key', httpClient: build()).resolveId(isMovie: true, ids: const ExternalIds(tvdb: 81189))).id,
        isNull,
      );
      expect(calls, 1, reason: 'a TVDB id names a series, so a movie lookup must not be attempted');
    });

    test('a failed find is never mistaken for an unknown title', () async {
      final client = TmdbClient('key', httpClient: MockClient((_) async => http.Response('boom', 500)));
      final result = await client.resolveId(isMovie: true, ids: const ExternalIds(imdb: 'tt0133093'));
      expect(result.id, isNull);
      expect(result.conclusive, isFalse);
    });

    test('returns null without any usable id', () async {
      final client = TmdbClient('key', httpClient: MockClient((_) async => fail('must not be asked')));
      expect((await client.resolveId(isMovie: true, ids: const ExternalIds())).id, isNull);
    });
  });
}
