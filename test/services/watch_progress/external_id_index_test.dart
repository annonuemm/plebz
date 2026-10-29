import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/database/app_database.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/services/jellyfin_api_cache.dart';
import 'package:plezy/services/plex_api_cache.dart';
import 'package:plezy/utils/external_ids.dart';

import '../../test_helpers/backend_client_fixtures.dart';

http.Response _json(Object body) =>
    http.Response(jsonEncode(body), 200, headers: const {'content-type': 'application/json'});

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    JellyfinApiCache.initialize(db);
  });

  tearDown(() => db.close());

  test('Plex names every film and series by its ids, one listing per library', () async {
    final asked = <Uri>[];
    final client = testPlexClient(
      handler: (request) async {
        asked.add(request.url);
        return switch (request.url.path) {
          '/library/sections' => _json({
            'MediaContainer': {
              'Directory': [
                {'key': '1', 'type': 'movie', 'title': 'Filme'},
                {'key': '2', 'type': 'show', 'title': 'Serien'},
                {'key': '3', 'type': 'artist', 'title': 'Musik'},
              ],
            },
          }),
          '/library/sections/1/all' => _json({
            'MediaContainer': {
              'Metadata': [
                {
                  'ratingKey': '10',
                  'Guid': [
                    {'id': 'imdb://tt010'},
                    {'id': 'tmdb://110'},
                  ],
                },
                {'ratingKey': '11', 'guid': 'com.plexapp.agents.imdb://tt011?lang=de'},
                {'ratingKey': '12', 'guid': 'local://12'},
              ],
            },
          }),
          '/library/sections/2/all' => _json({
            'MediaContainer': {
              'Metadata': [
                {
                  'ratingKey': '20',
                  'Guid': [
                    {'id': 'tvdb://220'},
                  ],
                },
              ],
            },
          }),
          _ => http.Response('{}', 404),
        };
      },
    );
    addTearDown(client.close);

    final read = await client.fetchExternalIdIndex();
    final index = read.ids;

    expect(read.complete, isTrue);
    expect(index.keys, unorderedEquals(['10', '11', '20']));
    expect(index['10']!.tmdb, 110);
    expect(index['11']!.imdb, 'tt011');
    expect(index['20']!.tvdb, 220);
    final listings = [
      for (final uri in asked)
        if (uri.path.endsWith('/all')) '${uri.path}?type=${uri.queryParameters['type']}',
    ];
    expect(listings, ['/library/sections/1/all?type=1', '/library/sections/2/all?type=2']);
    expect(
      asked.where((uri) => uri.path.endsWith('/all')).every((uri) => uri.queryParameters['includeGuids'] == '1'),
      isTrue,
    );
  });

  test('Plex reads a large library in pages, not in one listing', () async {
    final pages = <String>[];
    final client = testPlexClient(
      handler: (request) async {
        final query = request.url.queryParameters;
        if (request.url.path == '/library/sections') {
          return _json({
            'MediaContainer': {
              'Directory': [
                {'key': '1', 'type': 'movie', 'title': 'Filme'},
              ],
            },
          });
        }
        final start = int.parse(query['X-Plex-Container-Start']!);
        final size = int.parse(query['X-Plex-Container-Size']!);
        pages.add('$start+$size');
        const total = 1203;
        final end = start + size > total ? total : start + size;
        return _json({
          'MediaContainer': {
            'totalSize': total,
            'Metadata': [
              for (var i = start; i < end; i++)
                {
                  'ratingKey': '$i',
                  'Guid': [
                    {'id': 'tmdb://${1000 + i}'},
                  ],
                },
            ],
          },
        });
      },
    );
    addTearDown(client.close);

    final index = (await client.fetchExternalIdIndex()).ids;

    expect(index, hasLength(1203));
    expect(index['1202']!.tmdb, 2202);
    expect(pages, ['0+500', '500+500', '1000+500']);
  });

  test('Plex stops at once when a server answers the whole library despite the paging', () async {
    var listings = 0;
    final client = testPlexClient(
      handler: (request) async {
        if (request.url.path == '/library/sections') {
          return _json({
            'MediaContainer': {
              'Directory': [
                {'key': '1', 'type': 'movie', 'title': 'Filme'},
              ],
            },
          });
        }
        listings++;
        return _json({
          'MediaContainer': {
            'Metadata': [
              for (var i = 0; i < 700; i++)
                {
                  'ratingKey': '$i',
                  'Guid': [
                    {'id': 'tmdb://${1000 + i}'},
                  ],
                },
            ],
          },
        });
      },
    );
    addTearDown(client.close);

    final index = (await client.fetchExternalIdIndex()).ids;

    expect(index, hasLength(700));
    expect(listings, 1);
  });

  http.Response sections() => _json({
    'MediaContainer': {
      'Directory': [
        {'key': '1', 'type': 'movie', 'title': 'Filme'},
      ],
    },
  });

  Map<String, Object> row(String key, int addedAt) => {
    'ratingKey': key,
    'addedAt': addedAt,
    'Guid': [
      {'id': 'tmdb://1$key'},
    ],
  };

  test('Plex is asked only for what was added since the last read', () async {
    final asked = <Uri>[];
    final client = testPlexClient(
      handler: (request) async {
        asked.add(request.url);
        if (request.url.path == '/library/sections') return sections();
        return _json({
          'MediaContainer': {
            'Metadata': [row('30', 2000)],
          },
        });
      },
    );
    addTearDown(client.close);

    final read = await client.fetchExternalIdIndex(addedSince: 1000);

    expect(read.complete, isFalse);
    expect(read.ids.keys, ['30']);
    expect(read.newest, 2000);
    final listing = asked.singleWhere((uri) => uri.path.endsWith('/all'));
    expect(listing.queryParameters['includeGuids'], '1');
    expect(
      int.parse(listing.queryParameters['addedAt>>']!),
      lessThan(1000),
      reason: 'a little before the last read, so nothing added in the same second is missed',
    );
  });

  test('Plex is read whole where the server ignores what was added since', () async {
    final asked = <Uri>[];
    final client = testPlexClient(
      handler: (request) async {
        asked.add(request.url);
        if (request.url.path == '/library/sections') return sections();
        return _json({
          'MediaContainer': {
            'Metadata': [row('1', 10), row('30', 2000)],
          },
        });
      },
    );
    addTearDown(client.close);

    final read = await client.fetchExternalIdIndex(addedSince: 1000);

    expect(read.complete, isTrue);
    expect(read.ids.keys, unorderedEquals(['1', '30']));
    expect(read.newest, 2000);
    final listings = asked.where((uri) => uri.path.endsWith('/all')).toList();
    expect(listings, hasLength(2), reason: 'the listing since, then the whole one');
    expect(listings.last.queryParameters.containsKey('addedAt>>'), isFalse);
  });

  test('Plex is read whole where the server refuses what was added since', () async {
    final client = testPlexClient(
      handler: (request) async {
        if (request.url.path == '/library/sections') return sections();
        if (request.url.queryParameters.containsKey('addedAt>>')) return http.Response('', 400);
        return _json({
          'MediaContainer': {
            'Metadata': [row('1', 10)],
          },
        });
      },
    );
    addTearDown(client.close);

    final read = await client.fetchExternalIdIndex(addedSince: 1000);

    expect(read.complete, isTrue);
    expect(read.ids.keys, ['1']);
  });

  test('Plex lists a series\' episodes without their audio and subtitle tracks', () async {
    final asked = <Uri>[];
    final client = testPlexClient(
      handler: (request) async {
        asked.add(request.url);
        return _json({
          'MediaContainer': {
            'librarySectionID': 2,
            'Metadata': [
              for (var number = 1; number <= 2; number++)
                {
                  'ratingKey': 'e$number',
                  'type': 'episode',
                  'title': 'Folge $number',
                  'grandparentRatingKey': '77',
                  'parentIndex': 1,
                  'index': number,
                },
            ],
          },
        });
      },
    );
    addTearDown(client.close);

    final episodes = await client.fetchEpisodesWithoutStreams('77');

    expect(episodes.map((episode) => episode.id), ['e1', 'e2']);
    expect(episodes.first.kind, MediaKind.episode);
    expect(episodes.first.libraryId, '2');
    expect(asked.single.path, '/library/metadata/77/grandchildren');
    expect(asked.single.queryParameters.containsKey('includeStreams'), isFalse);
    expect(asked.single.queryParameters['X-Plex-Container-Size'], '2000');
  });

  test('Jellyfin names every film and series by its provider ids in one request', () async {
    final asked = <Uri>[];
    final client = testJellyfinClient(
      handler: (request) async {
        asked.add(request.url);
        return _json({
          'Items': [
            {
              'Id': 'film',
              'ProviderIds': {'Tmdb': '110', 'Imdb': 'tt010'},
            },
            {
              'Id': 'series',
              'ProviderIds': {'Tvdb': '220'},
            },
            {'Id': 'bare', 'ProviderIds': <String, Object>{}},
          ],
        });
      },
    );
    addTearDown(client.close);

    final index = (await client.fetchExternalIdIndex()).ids;

    expect(index, hasLength(2));
    expect(index['film'], isA<ExternalIds>().having((ids) => ids.tmdb, 'tmdb', 110));
    expect(index['series']!.tvdb, 220);
    expect(asked.single.path, '/Items');
    expect(asked.single.queryParameters['IncludeItemTypes'], 'Movie,Series');
    expect(asked.single.queryParameters['Fields'], 'ProviderIds');
  });
}
