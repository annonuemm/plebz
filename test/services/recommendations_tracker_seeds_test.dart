import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/recommendations_service.dart';
import 'package:plezy/services/trackers/simkl/simkl_client.dart';
import 'package:plezy/services/trackers/tracker_session.dart';
import 'package:plezy/services/watch_progress/external_id_index_client.dart';
import 'package:plezy/services/watch_progress/progress_routing.dart';
import 'package:plezy/services/watch_progress/tracker_progress_controller.dart';
import 'package:plezy/utils/external_ids.dart';
import 'package:plezy/utils/media_server_http_client.dart';

import '../test_helpers/media_items.dart';

/// A server with a film watched last in library 1 and one in library 9, and
/// films like the first.
class _Server implements MediaServerClient, ExternalIdIndexClient {
  @override
  final ServerId serverId = ServerId('srv');

  final scannedLibraries = <String>[];
  final relatedCalls = <String>[];

  @override
  Future<ExternalIdIndexRead> fetchExternalIdIndex({int? addedSince}) async =>
      const ExternalIdIndexRead({'film': ExternalIds(tmdb: 101), 'elsewhere': ExternalIds(tmdb: 102)}, complete: true);

  // Through the overlay, as the backends' item mappers hand every item.
  @override
  Future<MediaItem?> fetchItem(String id) async => switch (id) {
    'film' => ProgressRouting.overlay(testMediaItem(id: 'film', title: 'Film', serverId: 'srv', libraryId: '1')),
    'elsewhere' => ProgressRouting.overlay(
      testMediaItem(id: 'elsewhere', title: 'Elsewhere', serverId: 'srv', libraryId: '9'),
    ),
    _ => null,
  };

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async {
    scannedLibraries.add(libraryId);
    return const LibraryPage(items: [], totalCount: 0);
  }

  @override
  Future<List<MediaHub>> fetchRelatedHubs(String id, {int count = 10}) async {
    relatedCalls.add(id);
    final items = [testMediaItem(id: 'like-$id', title: 'Like $id', serverId: 'srv', libraryId: '1')];
    return [MediaHub(id: 'related-$id', title: 'More like this', type: 'movie', items: items, size: items.length)];
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

/// Simkl: both films watched, the one in library 9 last.
SimklClient _simkl() => SimklClient(
  const TrackerSession(accessToken: 't', refreshToken: '', expiresAt: 0, createdAt: 0),
  onSessionInvalidated: () {},
  httpClient: MockClient((request) async {
    final body = switch (request.url.path) {
      '/sync/activities' => {'all': 'a1'},
      '/sync/playback' => const [],
      _ => {
        'movies': [
          {
            'movie': {
              'ids': {'simkl': 1, 'tmdb': 101},
            },
            'status': 'completed',
            'last_watched_at': '2026-10-01T20:00:00Z',
          },
          {
            'movie': {
              'ids': {'simkl': 2, 'tmdb': 102},
            },
            'status': 'completed',
            'last_watched_at': '2026-10-02T20:00:00Z',
          },
        ],
      },
    };
    return http.Response(jsonEncode(body), 200, headers: const {'content-type': 'application/json'});
  }),
);

void main() {
  final controller = TrackerProgressController.instance;
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('recommendations_tracker_seeds_test');
    controller.rootDirectory = () async => root;
  });

  tearDown(() async {
    await controller.debugFlush();
    controller.debugReset();
    ProgressRouting.instance.debugReset();
    await root.delete(recursive: true);
  });

  test('a tracker-led profile\'s seeds are the titles its tracker names, without reading a library', () async {
    final server = _Server();
    final manager = MultiServerManager()..debugRegisterClientForTesting(server);
    addTearDown(manager.dispose);
    final simkl = _simkl();
    addTearDown(simkl.dispose);
    await controller.bind(profileId: 'anna', trackerLed: true, simkl: simkl, servers: {'srv': server});

    final picked = await RecommendationsService(manager).recommend(
      libraries: [
        MediaLibrary(id: '1', backend: MediaBackend.plex, title: 'Filme', kind: MediaKind.movie, serverId: 'srv'),
      ],
    );

    expect(picked.map((item) => item.id), ['like-film']);
    expect(server.relatedCalls, ['film'], reason: 'the film in library 9 is out of scope');
    expect(server.scannedLibraries, isEmpty);
  });
}
