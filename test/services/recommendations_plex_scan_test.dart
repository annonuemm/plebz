import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/database/app_database.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/plex_api_cache.dart';
import 'package:plezy/services/recommendations_service.dart';

import '../test_helpers/backend_client_fixtures.dart';

/// A Plex library set to hide the films of a collection behind it answers
/// "most recently watched" with collections when they are asked for — and a
/// viewer with plenty of history got no seed at all.
void main() {
  late AppDatabase db;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
  });
  tearDown(() => db.close());

  test('the seed scan asks Plex for the titles themselves, without collections', () async {
    final scans = <Uri>[];
    final relatedAsked = <String>[];
    final client = testPlexClient(
      serverId: ServerId('plex-1'),
      handler: (request) async {
        final path = request.url.path;
        if (path.contains('/library/sections/7/all')) {
          scans.add(request.url);
          return http.Response(
            jsonEncode({
              'MediaContainer': {
                'size': 1,
                'totalSize': 1,
                'librarySectionID': 7,
                'Metadata': [
                  {'ratingKey': '42', 'type': 'movie', 'title': 'Heat', 'year': 1995, 'viewCount': 2},
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (path.contains('related')) relatedAsked.add(path);
        return http.Response(
          jsonEncode({
            'MediaContainer': {'size': 0},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      },
    );
    final manager = MultiServerManager()..debugRegisterClientForTesting(client);
    addTearDown(manager.dispose);

    await RecommendationsService(manager).recommend(
      libraries: [
        MediaLibrary(id: '7', backend: MediaBackend.plex, title: 'Filme', kind: MediaKind.movie, serverId: 'plex-1'),
      ],
    );

    expect(scans, hasLength(1));
    final query = scans.single.queryParameters;
    expect(query['includeCollections'], '0');
    expect(query['type'], '1');
    expect(query['sort'], 'lastViewedAt:desc');
    expect(relatedAsked.single, contains('42'), reason: 'the watched film is a seed');
  });
}
