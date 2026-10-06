import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/database/app_database.dart';
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

    final index = await client.fetchExternalIdIndex();

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

    final index = await client.fetchExternalIdIndex();

    expect(index, hasLength(2));
    expect(index['film'], isA<ExternalIds>().having((ids) => ids.tmdb, 'tmdb', 110));
    expect(index['series']!.tvdb, 220);
    expect(asked.single.path, '/Items');
    expect(asked.single.queryParameters['IncludeItemTypes'], 'Movie,Series');
    expect(asked.single.queryParameters['Fields'], 'ProviderIds');
  });
}
