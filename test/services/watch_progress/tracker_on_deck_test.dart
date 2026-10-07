import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/services/trackers/simkl/simkl_client.dart';
import 'package:plezy/services/trackers/tracker_session.dart';
import 'package:plezy/services/watch_progress/external_id_index_client.dart';
import 'package:plezy/services/watch_progress/progress_routing.dart';
import 'package:plezy/services/watch_progress/tracker_progress_controller.dart';
import 'package:plezy/utils/external_ids.dart';

import '../../test_helpers/media_items.dart';

/// A server whose library listing named one copy of a series ("4k-show") but
/// not the copy in another library ("hd-show"), as a copy added since would be.
class _Server implements MediaServerClient, ExternalIdIndexClient {
  final asked = <String>[];

  @override
  ServerId get serverId => ServerId('plex');

  @override
  Future<Map<String, ExternalIds>> fetchExternalIdIndex() async => {'4k-show': const ExternalIds(tvdb: 900)};

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async {
    asked.add(itemId);
    return itemId == 'hd-show' ? const ExternalIds(tvdb: 900) : const ExternalIds();
  }

  @override
  Future<LibraryPage<MediaItem>> fetchPlayableDescendantsPage(
    String parentId, {
    int? start,
    int? size,
    Object? abort,
  }) async {
    final items = [
      for (var number = 1; number <= 5; number++)
        testMediaItem(
          id: '$parentId-e$number',
          serverId: 'plex',
          kind: MediaKind.episode,
          grandparentId: parentId,
          parentIndex: 1,
          index: number,
        ),
    ];
    return LibraryPage(items: items, totalCount: items.length);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

/// Simkl: the series watched up to S1E2.
SimklClient _simkl() => SimklClient(
  const TrackerSession(accessToken: 't', refreshToken: '', expiresAt: 0, createdAt: 0),
  onSessionInvalidated: () {},
  httpClient: MockClient((request) async {
    final body = switch (request.url.path) {
      '/sync/activities' => {'all': 'a1'},
      '/sync/playback' => const [],
      _ => {
        'shows': [
          {
            'show': {
              'ids': {'simkl': 10, 'tvdb': 900},
            },
            'last_watched_at': '2026-10-06T20:00:00Z',
            'seasons': [
              {
                'number': 1,
                'episodes': [
                  {'number': 1},
                  {'number': 2},
                ],
              },
            ],
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
    root = await Directory.systemTemp.createTemp('tracker_on_deck_test');
    controller.rootDirectory = () async => root;
  });

  tearDown(() async {
    await controller.debugFlush();
    controller.debugReset();
    ProgressRouting.instance.debugReset();
    await root.delete(recursive: true);
  });

  test('a copy of a series its library listing did not name still goes on where Simkl says', () async {
    final server = _Server();
    final simkl = _simkl();
    addTearDown(simkl.dispose);
    await controller.bind(profileId: 'anna', trackerLed: true, simkl: simkl, servers: {'plex': server});

    final hdShow = testMediaItem(id: 'hd-show', serverId: 'plex', kind: MediaKind.show);
    final next = await controller.onDeckFor(server, hdShow);

    expect(server.asked, ['hd-show'], reason: 'its ids asked for once, on the spot');
    expect(next?.id, 'hd-show-e3');

    // The page's episodes, fetched after this, carry Simkl's marks too.
    final episode = testMediaItem(
      id: 'hd-show-e2',
      serverId: 'plex',
      kind: MediaKind.episode,
      grandparentId: 'hd-show',
      parentIndex: 1,
      index: 2,
    );
    expect(ProgressRouting.overlay(episode).isWatched, isTrue);

    await controller.onDeckFor(server, hdShow);
    expect(server.asked, ['hd-show'], reason: 'known now, not asked again');
  });
}
