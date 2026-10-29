import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/database/app_database.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/services/brand_rows_service.dart';
import 'package:plezy/services/jellyfin_api_cache.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/plex_api_cache.dart';
import 'package:plezy/services/streaming_brands.dart';

import '../test_helpers/backend_client_fixtures.dart';

http.Response _json(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status, headers: const {'content-type': 'application/json'});

Map<String, Object> _plexItems(List<Map<String, Object>> items, {int? total, int section = 2}) => {
  'MediaContainer': {
    'size': items.length,
    'totalSize': total ?? items.length,
    'librarySectionID': section,
    'Metadata': items,
  },
};

Map<String, Object> _plexValues(Map<String, String> titlesByKey) => {
  'MediaContainer': {
    'size': titlesByKey.length,
    'Directory': [
      for (final MapEntry(:key, :value) in titlesByKey.entries) {'key': key, 'title': value},
    ],
  },
};

MediaLibrary _plexLibrary(String id, MediaKind kind) =>
    MediaLibrary(id: id, backend: MediaBackend.plex, title: 'Plex $id', kind: kind, serverId: 'plex-1');

MediaLibrary _jellyfinLibrary(String id, MediaKind kind) =>
    MediaLibrary(id: id, backend: MediaBackend.jellyfin, title: 'Jellyfin $id', kind: kind, serverId: 'srv-1');

void main() {
  late AppDatabase db;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    JellyfinApiCache.initialize(db);
  });
  tearDown(() => db.close());

  group('Plex', () {
    test('a series library is filtered by network and studio, a film library by studio', () async {
      final asked = <Uri>[];
      final client = testPlexClient(
        serverId: ServerId('plex-1'),
        handler: (request) async {
          final url = request.url;
          if (url.path == '/library/sections/2/network') {
            return _json(_plexValues({'101': 'Netflix', '102': 'ZDF', '103': 'HBO'}));
          }
          if (url.path == '/library/sections/2/studio') return _json(_plexValues({'Lucasfilm': 'Lucasfilm'}));
          if (url.path == '/library/sections/1/studio') {
            return _json(_plexValues({'Netflix': 'Netflix', 'Amazon%20MGM%20Studios': 'Amazon MGM Studios'}));
          }
          if (url.path == '/library/sections/2/all') {
            asked.add(url);
            final network = url.queryParameters['network'];
            return _json(
              _plexItems([
                if (network == '101') {'ratingKey': '20', 'type': 'show', 'title': 'Dark', 'year': 2017},
                if (network == '103') {'ratingKey': '21', 'type': 'show', 'title': 'The Wire', 'year': 2002},
              ]),
            );
          }
          if (url.path == '/library/sections/1/all') {
            asked.add(url);
            final studio = url.queryParameters['studio'];
            return _json(
              _plexItems(section: 1, [
                if (studio == 'Netflix') {'ratingKey': '10', 'type': 'movie', 'title': 'Roma', 'year': 2018},
                if (studio == 'Amazon MGM Studios')
                  {'ratingKey': '11', 'type': 'movie', 'title': 'Saltburn', 'year': 2023},
              ]),
            );
          }
          return _json({
            'MediaContainer': {'size': 0},
          }, status: 404);
        },
      );
      final manager = MultiServerManager()..debugRegisterClientForTesting(client);
      addTearDown(manager.dispose);

      final rows = await BrandRowsService(manager).rows(
        libraries: [_plexLibrary('1', MediaKind.movie), _plexLibrary('2', MediaKind.show)],
        brands: [StreamingBrand.netflix, StreamingBrand.prime, StreamingBrand.hbo, StreamingBrand.disney],
      );

      expect(rows.map((row) => row.brand), [StreamingBrand.netflix, StreamingBrand.prime, StreamingBrand.hbo]);
      expect(rows.first.items.map((item) => item.title), ['Roma', 'Dark'], reason: 'films and series in turn');
      expect(rows[1].items.single.title, 'Saltburn', reason: 'an encoded studio key is decoded once');
      for (final url in asked) {
        expect(url.queryParameters['includeCollections'], '0');
        expect(url.queryParameters['sort'], 'random:asc');
      }
      expect(asked.where((url) => url.queryParameters['type'] == '2'), hasLength(2));
      expect(asked, hasLength(4), reason: 'one request per brand and field that matched — none for Disney+');
    });

    test('a section without a network field is asked only for studios', () async {
      final client = testPlexClient(
        serverId: ServerId('plex-1'),
        handler: (request) async {
          final path = request.url.path;
          if (path == '/library/sections/2/network') return _json({'errors': []}, status: 404);
          if (path == '/library/sections/2/studio') return _json(_plexValues({'Netflix': 'Netflix'}));
          if (path == '/library/sections/2/all') {
            return _json(
              _plexItems([
                {'ratingKey': '20', 'type': 'show', 'title': 'Dark', 'year': 2017},
              ]),
            );
          }
          return _json({
            'MediaContainer': {'size': 0},
          });
        },
      );
      final manager = MultiServerManager()..debugRegisterClientForTesting(client);
      addTearDown(manager.dispose);

      final rows = await BrandRowsService(
        manager,
      ).rows(libraries: [_plexLibrary('2', MediaKind.show)], brands: [StreamingBrand.netflix]);

      expect(rows.single.items.single.title, 'Dark');
    });

    test('"Alle" reads every page, by title', () async {
      final starts = <String?>[];
      final client = testPlexClient(
        serverId: ServerId('plex-1'),
        handler: (request) async {
          final url = request.url;
          if (url.path == '/library/sections/2/network') return _json(_plexValues({'101': 'Netflix'}));
          if (url.path == '/library/sections/2/studio') return _json(_plexValues({}));
          if (url.path == '/library/sections/2/all') {
            final start = int.parse(url.queryParameters['X-Plex-Container-Start'] ?? '0');
            starts.add(url.queryParameters['X-Plex-Container-Start']);
            expect(url.queryParameters['sort'], 'titleSort:asc');
            final page = [
              for (var i = start; i < start + BrandRowsService.allPageSize && i < 150; i++)
                {'ratingKey': '$i', 'type': 'show', 'title': 'Show ${i.toString().padLeft(3, '0')}', 'year': 2000},
            ];
            return _json(_plexItems(page, total: 150));
          }
          return _json({
            'MediaContainer': {'size': 0},
          });
        },
      );
      final manager = MultiServerManager()..debugRegisterClientForTesting(client);
      addTearDown(manager.dispose);

      final all = await BrandRowsService(
        manager,
      ).all(brand: StreamingBrand.netflix, libraries: [_plexLibrary('2', MediaKind.show)]);

      expect(all, hasLength(150));
      expect(starts, ['0', '100']);
      expect(all.first.title, 'Show 000');
    });
  });

  group('Jellyfin', () {
    test('studios are listed once, then the titles asked for by studio id', () async {
      final studioCalls = <Uri>[];
      final itemCalls = <Uri>[];
      final client = testJellyfinClient(
        handler: (request) async {
          final url = request.url;
          if (url.path == '/Studios') {
            studioCalls.add(url);
            return _json({
              'Items': [
                {'Id': 's1', 'Name': 'Netflix'},
                {'Id': 's2', 'Name': 'Disney Channel'},
                {'Id': 's3', 'Name': 'Apple TV+'},
              ],
            });
          }
          if (url.path == '/Items') {
            itemCalls.add(url);
            final ids = url.queryParameters['StudioIds'];
            return _json({
              'Items': [
                if (ids == 's1') {'Id': 'a', 'Type': 'Series', 'Name': 'Wednesday', 'ProductionYear': 2022},
                if (ids == 's3') {'Id': 'b', 'Type': 'Series', 'Name': 'Severance', 'ProductionYear': 2022},
              ],
              'TotalRecordCount': 1,
            });
          }
          return _json({});
        },
      );
      final manager = MultiServerManager()..debugRegisterClientForTesting(client);
      addTearDown(manager.dispose);
      final service = BrandRowsService(manager);
      final libraries = [_jellyfinLibrary('lib-tv', MediaKind.show)];
      final brands = [StreamingBrand.netflix, StreamingBrand.disney, StreamingBrand.apple];

      final rows = await service.rows(libraries: libraries, brands: brands);
      await service.rows(libraries: libraries, brands: brands);

      expect(rows.map((row) => row.brand), [StreamingBrand.netflix, StreamingBrand.apple]);
      expect(rows.first.items.single.title, 'Wednesday');
      expect(studioCalls, hasLength(1), reason: 'the listing is kept');
      expect(studioCalls.single.queryParameters['ParentId'], 'lib-tv');
      expect(itemCalls.first.queryParameters['SortBy'], 'Random');
      expect(itemCalls.first.queryParameters['IncludeItemTypes'], 'Series');
      expect(itemCalls.first.queryParameters['ParentId'], 'lib-tv');
    });
  });

  test('one title on two servers is one entry', () async {
    final plex = testPlexClient(
      serverId: ServerId('plex-1'),
      handler: (request) async {
        final path = request.url.path;
        if (path == '/library/sections/2/network') return _json(_plexValues({'101': 'Netflix'}));
        if (path == '/library/sections/2/studio') return _json(_plexValues({}));
        if (path == '/library/sections/2/all') {
          return _json(
            _plexItems([
              {'ratingKey': '20', 'type': 'show', 'title': 'Dark', 'year': 2017},
            ]),
          );
        }
        return _json({
          'MediaContainer': {'size': 0},
        });
      },
    );
    final jellyfin = testJellyfinClient(
      handler: (request) async {
        if (request.url.path == '/Studios') {
          return _json({
            'Items': [
              {'Id': 's1', 'Name': 'Netflix'},
            ],
          });
        }
        if (request.url.path == '/Items') {
          return _json({
            'Items': [
              {'Id': 'x', 'Type': 'Series', 'Name': 'Dark', 'ProductionYear': 2017},
              {'Id': 'y', 'Type': 'Series', 'Name': 'Ozark', 'ProductionYear': 2017},
            ],
            'TotalRecordCount': 2,
          });
        }
        return _json({});
      },
    );
    final manager = MultiServerManager()
      ..debugRegisterClientForTesting(plex)
      ..debugRegisterClientForTesting(jellyfin);
    addTearDown(manager.dispose);

    final rows = await BrandRowsService(manager).rows(
      libraries: [_plexLibrary('2', MediaKind.show), _jellyfinLibrary('lib-tv', MediaKind.show)],
      brands: [StreamingBrand.netflix],
    );

    expect(rows.single.items.map((item) => item.title), ['Dark', 'Ozark']);
  });

  test('music and photo libraries are not asked', () async {
    var requests = 0;
    final client = testPlexClient(
      serverId: ServerId('plex-1'),
      handler: (request) async {
        requests++;
        return _json({
          'MediaContainer': {'size': 0},
        });
      },
    );
    final manager = MultiServerManager()..debugRegisterClientForTesting(client);
    addTearDown(manager.dispose);

    final rows = await BrandRowsService(
      manager,
    ).rows(libraries: [_plexLibrary('9', MediaKind.artist)], brands: [StreamingBrand.netflix]);

    expect(rows, isEmpty);
    expect(requests, 0);
  });
}
