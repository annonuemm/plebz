import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/models/catalog/catalog_item.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/tmdb/tmdb_fill_in_service.dart';
import 'package:plezy/services/tmdb/tmdb_client.dart';
import 'package:plezy/utils/external_ids.dart';

import '../../test_helpers/media_items.dart';
import '../../test_helpers/prefs.dart';

/// Counts what actually left the app, which is the whole point of the cache.
class _RecordingTmdb {
  int requests = 0;
  final List<Uri> urls = [];

  TmdbClient build(String credential) => TmdbClient(
    credential,
    httpClient: MockClient((request) async {
      requests++;
      urls.add(request.url);
      if (request.url.path.contains('/find/')) {
        return http.Response(jsonEncode({'movie_results': [], 'tv_results': []}), 200);
      }
      return http.Response(
        jsonEncode({
          'id': 1,
          'overview': 'Eine Beschreibung.',
          'images': {
            'logos': [
              {'file_path': '/logo.png', 'iso_639_1': 'en', 'vote_average': 5},
            ],
          },
        }),
        200,
      );
    }),
  );

  TmdbClient buildWithoutLogos(String credential) => TmdbClient(
    credential,
    httpClient: MockClient((request) async {
      requests++;
      urls.add(request.url);
      return http.Response(
        jsonEncode({
          'id': 1,
          'images': {'logos': []},
        }),
        200,
      );
    }),
  );
}

/// Serves external ids the way a media server would, and counts the asks.
class _FakeClient implements MediaServerClient {
  _FakeClient(this.idsById);

  final Map<String, ExternalIds> idsById;
  final List<String> externalIdCalls = [];

  @override
  ServerId get serverId => ServerId('server-1');

  @override
  String get serverName => 'Server';

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async {
    externalIdCalls.add(itemId);
    return idsById[itemId] ?? const ExternalIds();
  }

  @override
  Future<List<MediaLibrary>> fetchLibraries() async => const [];

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaItem _catalogMovie({int? tmdb}) => CatalogItem(
  source: CatalogSourceId.simkl,
  kind: MediaKind.movie,
  title: 'Ein Film',
  ids: CatalogItemIds(tmdb: tmdb),
).toMediaItem();

MediaItem _episode({required String seriesId, required String episodeId}) => testMediaItem(
  id: episodeId,
  kind: MediaKind.episode,
  serverId: 'server-1',
  grandparentId: seriesId,
  grandparentTitle: 'Eine Serie',
);

Future<void> _enable({String key = 'test-key'}) async {
  final settings = await SettingsService.getInstance();
  await settings.write(SettingsService.tmdbLogosEnabled, true);
  await settings.write(SettingsService.tmdbApiKey, key);
}

void main() {
  late AppDatabase db;

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TmdbFillInService.resetForTesting();
    await SettingsService.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    TmdbFillInService.resetForTesting();
    await db.close();
  });

  test('stays silent while switched off or without a key', () async {
    final tmdb = _RecordingTmdb();
    TmdbFillInService.initialize(db, clientFactory: tmdb.build);
    final service = TmdbFillInService.instanceOrNull!;

    expect(service.isEnabled, isFalse);
    expect((await service.resolve(_catalogMovie(tmdb: 603))).logoUrl, isNull);

    // A key alone is not consent; the switch is what turns the feature on.
    await (await SettingsService.getInstance()).write(SettingsService.tmdbApiKey, 'test-key');
    expect(service.isEnabled, isFalse);
    expect((await service.resolve(_catalogMovie(tmdb: 603))).logoUrl, isNull);
    expect(tmdb.requests, 0);
  });

  test('resolves a logo once and answers the rest from cache', () async {
    await _enable();
    final tmdb = _RecordingTmdb();
    TmdbFillInService.initialize(db, clientFactory: tmdb.build);
    final service = TmdbFillInService.instanceOrNull!;

    final item = _catalogMovie(tmdb: 603);
    expect((await service.resolve(item)).logoUrl, endsWith('/logo.png'));
    expect(tmdb.requests, 1);

    expect((await service.resolve(item)).logoUrl, endsWith('/logo.png'));
    expect((await service.resolve(item)).logoUrl, endsWith('/logo.png'));
    expect(tmdb.requests, 1, reason: 'a resolved title must never be asked about twice');
  });

  test('one request brings back both the logo and the description', () async {
    await _enable();
    final tmdb = _RecordingTmdb();
    TmdbFillInService.initialize(db, clientFactory: tmdb.build);
    final service = TmdbFillInService.instanceOrNull!;

    final found = await service.resolve(_catalogMovie(tmdb: 603));

    expect(found.logoUrl, endsWith('/logo.png'));
    expect(found.summary, 'Eine Beschreibung.');
    expect(tmdb.requests, 1, reason: 'the description rides along with the logo, it does not cost a second ask');
  });

  test('the cache survives a restart', () async {
    await _enable();
    final first = _RecordingTmdb();
    TmdbFillInService.initialize(db, clientFactory: first.build);
    expect((await TmdbFillInService.instanceOrNull!.resolve(_catalogMovie(tmdb: 603))).logoUrl, endsWith('/logo.png'));
    expect(first.requests, 1);

    // Same database, fresh service: what a relaunch looks like.
    final second = _RecordingTmdb();
    TmdbFillInService.initialize(db, clientFactory: second.build);
    final restored = await TmdbFillInService.instanceOrNull!.resolve(_catalogMovie(tmdb: 603));
    expect(restored.logoUrl, endsWith('/logo.png'));
    expect(restored.summary, 'Eine Beschreibung.');
    expect(second.requests, 0, reason: 'the stored answer must outlive the process');
  });

  test('known() answers instantly once the lookup has run', () async {
    await _enable();
    final tmdb = _RecordingTmdb();
    TmdbFillInService.initialize(db, clientFactory: tmdb.build);
    final service = TmdbFillInService.instanceOrNull!;
    final item = _catalogMovie(tmdb: 603);

    expect(service.known(item), isNull, reason: 'nothing is known before the first lookup');

    await service.resolve(item);

    expect(service.known(item)?.logoUrl, endsWith('/logo.png'));
  });

  test('warming up makes stored answers available before the first frame', () async {
    await _enable();
    final first = _RecordingTmdb();
    TmdbFillInService.initialize(db, clientFactory: first.build);
    await TmdbFillInService.instanceOrNull!.resolve(_catalogMovie(tmdb: 603));

    // A relaunch: the answer is on disk but nothing is in memory yet, which is
    // what used to make every title flash its name once per launch.
    final second = _RecordingTmdb();
    TmdbFillInService.initialize(db, clientFactory: second.build);
    final service = TmdbFillInService.instanceOrNull!;
    expect(service.known(_catalogMovie(tmdb: 603)), isNull);

    await service.warmUp();

    expect(service.known(_catalogMovie(tmdb: 603))?.logoUrl, endsWith('/logo.png'));
    expect(second.requests, 0);
  });

  test('remembers that TMDB had no logo', () async {
    await _enable();
    final tmdb = _RecordingTmdb();
    TmdbFillInService.initialize(db, clientFactory: tmdb.buildWithoutLogos);
    final service = TmdbFillInService.instanceOrNull!;

    expect((await service.resolve(_catalogMovie(tmdb: 603))).logoUrl, isNull);
    expect((await service.resolve(_catalogMovie(tmdb: 603))).logoUrl, isNull);
    expect(tmdb.requests, 1, reason: 'a miss is an answer too, and must be cached like one');
  });

  test('caches unmatchable titles without asking TMDB at all', () async {
    await _enable();
    final tmdb = _RecordingTmdb();
    TmdbFillInService.initialize(db, clientFactory: tmdb.build);
    final service = TmdbFillInService.instanceOrNull!;

    // No ids anywhere: nothing to look up, and nothing to retry either.
    expect((await service.resolve(_catalogMovie())).logoUrl, isNull);
    expect((await service.resolve(_catalogMovie())).logoUrl, isNull);
    expect(tmdb.requests, 0);
  });

  test('episodes of one series share a single lookup', () async {
    await _enable();
    final tmdb = _RecordingTmdb();
    TmdbFillInService.initialize(db, clientFactory: tmdb.build);
    final service = TmdbFillInService.instanceOrNull!;
    final client = _FakeClient({'series-1': const ExternalIds(tmdb: 1396)});

    expect(
      (await service.resolve(
        _episode(seriesId: 'series-1', episodeId: 'ep-1'),
        client: client,
      )).logoUrl,
      endsWith('/logo.png'),
    );
    expect(
      (await service.resolve(
        _episode(seriesId: 'series-1', episodeId: 'ep-2'),
        client: client,
      )).logoUrl,
      endsWith('/logo.png'),
    );

    expect(tmdb.requests, 1);
    expect(client.externalIdCalls, ['series-1'], reason: 'ids belong to the series, and are asked for once');
    expect(tmdb.urls.single.path, '/3/tv/1396');
  });

  test('concurrent callers for one title share the in-flight lookup', () async {
    await _enable();
    final tmdb = _RecordingTmdb();
    TmdbFillInService.initialize(db, clientFactory: tmdb.build);
    final service = TmdbFillInService.instanceOrNull!;

    final item = _catalogMovie(tmdb: 603);
    final results = await Future.wait([service.resolve(item), service.resolve(item), service.resolve(item)]);

    expect(results.map((found) => found.logoUrl), everyElement(endsWith('/logo.png')));
    expect(tmdb.requests, 1);
  });

  test('a failed request is retried rather than remembered as a miss', () async {
    await _enable();
    var failing = true;
    var requests = 0;
    TmdbFillInService.initialize(
      db,
      clientFactory: (credential) => TmdbClient(
        credential,
        httpClient: MockClient((request) async {
          requests++;
          if (failing) return http.Response('boom', 500);
          return http.Response(
            jsonEncode({
              'id': 1,
              'images': {
                'logos': [
                  {'file_path': '/logo.png', 'iso_639_1': 'en', 'vote_average': 5},
                ],
              },
            }),
            200,
          );
        }),
      ),
    );
    final service = TmdbFillInService.instanceOrNull!;

    expect((await service.resolve(_catalogMovie(tmdb: 603))).logoUrl, isNull);
    expect(requests, 1);

    // A server that was briefly unreachable must not cost the title its logo
    // for the whole miss TTL.
    failing = false;
    expect((await service.resolve(_catalogMovie(tmdb: 603))).logoUrl, endsWith('/logo.png'));
    expect(requests, 2);
  });

  test('a library item without a server to ask is left for later', () async {
    await _enable();
    final tmdb = _RecordingTmdb();
    TmdbFillInService.initialize(db, clientFactory: tmdb.build);
    final service = TmdbFillInService.instanceOrNull!;
    final episode = _episode(seriesId: 'series-1', episodeId: 'ep-1');

    // No client: the external ids live on the server, so nothing was learned.
    expect((await service.resolve(episode)).logoUrl, isNull);
    expect(tmdb.requests, 0);

    final client = _FakeClient({'series-1': const ExternalIds(tmdb: 1396)});
    expect((await service.resolve(episode, client: client)).logoUrl, endsWith('/logo.png'));
  });

  test('clearing the cache makes the next lookup happen again', () async {
    await _enable();
    final tmdb = _RecordingTmdb();
    TmdbFillInService.initialize(db, clientFactory: tmdb.build);
    final service = TmdbFillInService.instanceOrNull!;

    await service.resolve(_catalogMovie(tmdb: 603));
    expect(tmdb.requests, 1);

    await service.clearCache();
    await service.resolve(_catalogMovie(tmdb: 603));
    expect(tmdb.requests, 2);
  });

  group('filmography', () {
    /// Answers the three calls one filmography takes: the title's cast, then
    /// the person's credits.
    TmdbClient buildFilmographyClient(String credential, {required List<Uri> seen}) => TmdbClient(
      credential,
      httpClient: MockClient((request) async {
        seen.add(request.url);
        if (request.url.path.endsWith('/credits') || request.url.path.endsWith('/aggregate_credits')) {
          return http.Response(
            jsonEncode({
              'cast': [
                {'id': 11, 'name': 'Ein Anderer'},
                {'id': 42, 'name': 'Gesuchte Person'},
              ],
            }),
            200,
          );
        }
        if (request.url.path.contains('/combined_credits')) {
          return http.Response(
            jsonEncode({
              'cast': [
                {'media_type': 'movie', 'id': 1, 'title': 'Neuer Film', 'release_date': '2024-01-01'},
                {'media_type': 'tv', 'id': 2, 'name': 'Alte Serie', 'first_air_date': '1999-05-05'},
                // The same title again for a second role, and an episode credit.
                {'media_type': 'movie', 'id': 1, 'title': 'Neuer Film', 'release_date': '2024-01-01'},
                {'media_type': 'episode', 'id': 3, 'name': 'Eine Folge'},
              ],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'id': 1,
            'images': {'logos': []},
          }),
          200,
        );
      }),
    );

    test('is read through the title the person was reached from', () async {
      await _enable();
      final seen = <Uri>[];
      TmdbFillInService.initialize(db, clientFactory: (c) => buildFilmographyClient(c, seen: seen));
      final service = TmdbFillInService.instanceOrNull!;

      final credits = await service.filmographyFor(
        sourceTitle: _catalogMovie(tmdb: 603),
        personName: 'Gesuchte Person',
      );

      expect(seen.first.path, '/3/movie/603/credits', reason: 'the title names the person, no name search');
      expect(seen.last.path, '/3/person/42/combined_credits');
      expect(credits.map((c) => c.title), ['Neuer Film', 'Alte Serie'], reason: 'newest first, each title once');
      expect(credits.first.isMovie, isTrue);
      expect(credits.last.year, 1999);
    });

    test('a person who is not in that title yields nothing rather than a guess', () async {
      await _enable();
      final seen = <Uri>[];
      TmdbFillInService.initialize(db, clientFactory: (c) => buildFilmographyClient(c, seen: seen));

      final credits = await TmdbFillInService.instanceOrNull!.filmographyFor(
        sourceTitle: _catalogMovie(tmdb: 603),
        personName: 'Steht Da Nicht',
      );

      expect(credits, isEmpty);
      expect(seen.every((uri) => !uri.path.contains('combined_credits')), isTrue);
    });

    test('nothing is fetched while the feature is off', () async {
      final seen = <Uri>[];
      TmdbFillInService.initialize(db, clientFactory: (c) => buildFilmographyClient(c, seen: seen));

      final credits = await TmdbFillInService.instanceOrNull!.filmographyFor(
        sourceTitle: _catalogMovie(tmdb: 603),
        personName: 'Gesuchte Person',
      );

      expect(credits, isEmpty);
      expect(seen, isEmpty);
    });

    test('a filmography is fetched once per person', () async {
      await _enable();
      final seen = <Uri>[];
      TmdbFillInService.initialize(db, clientFactory: (c) => buildFilmographyClient(c, seen: seen));
      final service = TmdbFillInService.instanceOrNull!;

      await service.filmographyFor(sourceTitle: _catalogMovie(tmdb: 603), personName: 'Gesuchte Person');
      final requests = seen.length;
      await service.filmographyFor(sourceTitle: _catalogMovie(tmdb: 603), personName: 'Gesuchte Person');

      expect(seen.length, requests);
    });
  });

  test('music is never looked up', () async {
    await _enable();
    final tmdb = _RecordingTmdb();
    TmdbFillInService.initialize(db, clientFactory: tmdb.build);
    final service = TmdbFillInService.instanceOrNull!;

    expect((await service.resolve(testMediaItem(kind: MediaKind.album, serverId: 'server-1'))).logoUrl, isNull);
    expect(tmdb.requests, 0);
  });
}
