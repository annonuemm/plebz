import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/utils/media_server_http_client.dart';
import 'package:plezy/services/recommendations_service.dart';

import '../test_helpers/media_items.dart';

/// A server that answers a library scan with [shelf] and "more like this" with
/// whatever [relatedById] holds for the seed.
class _FakeClient implements MediaServerClient {
  _FakeClient({String id = 'srv', this.shelf = const [], this.relatedById = const {}}) : serverId = ServerId(id);

  @override
  final ServerId serverId;

  final List<MediaItem> shelf;
  final Map<String, List<MediaItem>> relatedById;

  final scannedLibraries = <String>[];
  final relatedCalls = <String>[];

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async {
    scannedLibraries.add(libraryId);
    return LibraryPage(items: shelf, totalCount: shelf.length);
  }

  @override
  Future<List<MediaHub>> fetchRelatedHubs(String id, {int count = 10}) async {
    relatedCalls.add(id);
    final items = relatedById[id] ?? const <MediaItem>[];
    return [MediaHub(id: 'related-$id', title: 'More like this', type: 'movie', items: items, size: items.length)];
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaItem _item(
  String id, {
  String serverId = 'srv',
  MediaKind kind = MediaKind.movie,
  bool favorite = false,
  int? viewCount,
}) => testMediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: kind,
  title: id,
  serverId: serverId,
  isFavorite: favorite,
  viewCount: viewCount,
);

MediaLibrary _library(
  String id, {
  String serverId = 'srv',
  MediaKind kind = MediaKind.movie,
  MediaBackend backend = MediaBackend.plex,
}) => MediaLibrary(id: id, backend: backend, title: 'Library $id', kind: kind, serverId: serverId);

void main() {
  ({MultiServerManager manager, RecommendationsService service}) withClient(_FakeClient client) {
    final manager = MultiServerManager()..debugRegisterClientForTesting(client);
    addTearDown(manager.dispose);
    return (manager: manager, service: RecommendationsService(manager));
  }

  group('rotation', () {
    _FakeClient twoSeedsDeep() => _FakeClient(
      shelf: [_item('liked', favorite: true), _item('seen', viewCount: 1)],
      relatedById: {
        'liked': [_item('a1'), _item('a2'), _item('a3')],
        'seen': [_item('b1'), _item('b2'), _item('b3')],
      },
    );

    test('stands still within one period', () async {
      final s = withClient(twoSeedsDeep());

      final first = await s.service.recommend(libraries: [_library('1')], rotation: 7);
      final again = await s.service.recommend(libraries: [_library('1')], rotation: 7);

      expect(again.map((item) => item.id), first.map((item) => item.id));
    });

    test('opens on a different title in the next one', () async {
      final s = withClient(twoSeedsDeep());

      final now = await s.service.recommend(libraries: [_library('1')], rotation: 0);
      final later = await s.service.recommend(libraries: [_library('1')], rotation: 1);

      // The row a viewer sees first is the thing that must change; the set
      // behind it is the same handful either way, since that is all the
      // servers offered.
      expect(later.first.id, isNot(now.first.id));
    });

    test('a rotation past the end of a list wraps rather than skipping the seed', () async {
      final s = withClient(twoSeedsDeep());

      // Both lists hold three; a rotation of five is past the end of both.
      final result = await s.service.recommend(libraries: [_library('1')], rotation: 5);

      expect(result.length, 6, reason: 'every title is still offered');
      expect(result.map((item) => item.id).toSet(), {'a1', 'a2', 'a3', 'b1', 'b2', 'b3'});
    });

    test('the period is the one the home screen schedules against', () {
      final start = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      expect(RecommendationsService.rotationAt(start), 0);
      expect(RecommendationsService.rotationAt(start.add(const Duration(hours: 2, minutes: 59))), 0);
      expect(RecommendationsService.rotationAt(start.add(const Duration(hours: 3))), 1);
      expect(RecommendationsService.rotationAt(start.add(const Duration(hours: 9))), 3);
    });
  });

  test('recommends what resembles a favourite', () async {
    final client = _FakeClient(
      shelf: [_item('liked', favorite: true)],
      relatedById: {
        'liked': [_item('suggestion')],
      },
    );
    final s = withClient(client);

    final result = await s.service.recommend(libraries: [_library('1')]);

    expect(result.map((item) => item.id), ['suggestion']);
    expect(client.relatedCalls, ['liked'], reason: 'the favourite is what gets asked about');
  });

  test('a watched title is a seed too, and a favourite outranks it', () async {
    final client = _FakeClient(
      shelf: [_item('seen', viewCount: 1), _item('liked', favorite: true)],
      relatedById: {
        'liked': [_item('from-favourite')],
        'seen': [_item('from-watched')],
      },
    );
    final s = withClient(client);

    await s.service.recommend(libraries: [_library('1')]);

    expect(client.relatedCalls, ['liked', 'seen'], reason: 'a marked title is the stronger statement');
  });

  test('nothing watched and nothing marked means no row at all', () async {
    final client = _FakeClient(shelf: [_item('untouched')]);
    final s = withClient(client);

    expect(await s.service.recommend(libraries: [_library('1')]), isEmpty);
    expect(client.relatedCalls, isEmpty, reason: 'no seed, no requests');
  });

  test('what the viewer already saw or is already being shown is dropped', () async {
    final client = _FakeClient(
      shelf: [_item('liked', favorite: true)],
      relatedById: {
        'liked': [_item('already-seen', viewCount: 2), _item('in-continue-watching'), _item('fresh')],
      },
    );
    final s = withClient(client);

    final result = await s.service.recommend(libraries: [_library('1')], excludeKeys: {'srv:in-continue-watching'});

    expect(result.map((item) => item.id), ['fresh']);
  });

  test('a seed never recommends itself', () async {
    final client = _FakeClient(
      shelf: [_item('liked', favorite: true)],
      relatedById: {
        'liked': [_item('liked', favorite: true), _item('other')],
      },
    );
    final s = withClient(client);

    expect((await s.service.recommend(libraries: [_library('1')])).map((item) => item.id), ['other']);
  });

  test('the same title from two seeds appears once', () async {
    final client = _FakeClient(
      shelf: [_item('liked', favorite: true), _item('seen', viewCount: 1)],
      relatedById: {
        'liked': [_item('shared')],
        'seen': [_item('shared')],
      },
    );
    final s = withClient(client);

    expect((await s.service.recommend(libraries: [_library('1')])).map((item) => item.id), ['shared']);
  });

  test('the seeds take turns, so one favourite cannot fill the row', () async {
    final client = _FakeClient(
      shelf: [_item('a', favorite: true), _item('b', favorite: true)],
      relatedById: {
        'a': [_item('a1'), _item('a2')],
        'b': [_item('b1'), _item('b2')],
      },
    );
    final s = withClient(client);

    expect((await s.service.recommend(libraries: [_library('1')])).map((item) => item.id), ['a1', 'b1', 'a2', 'b2']);
  });

  test('music and photo libraries are not scanned', () async {
    final client = _FakeClient(shelf: [_item('liked', favorite: true)]);
    final s = withClient(client);

    await s.service.recommend(
      libraries: [
        _library('music', kind: MediaKind.artist),
        _library('films'),
      ],
    );

    expect(client.scannedLibraries, ['films']);
  });

  test('the number of libraries consulted is bounded', () async {
    final client = _FakeClient(shelf: [_item('liked', favorite: true)]);
    final s = withClient(client);

    await s.service.recommend(libraries: [for (var i = 0; i < 10; i++) _library('lib-$i')]);

    expect(client.scannedLibraries, hasLength(RecommendationsService.maxSeedLibraries));
  });

  test('episodes are neither seeds nor suggestions', () async {
    // The row is about what to start next, and an episode is the middle of
    // something already started.
    final client = _FakeClient(
      shelf: [
        _item('episode', kind: MediaKind.episode, viewCount: 1),
        _item('liked', favorite: true),
      ],
      relatedById: {
        'liked': [_item('an-episode', kind: MediaKind.episode), _item('a-show', kind: MediaKind.show)],
      },
    );
    final s = withClient(client);

    final result = await s.service.recommend(libraries: [_library('1')]);

    expect(client.relatedCalls, ['liked']);
    expect(result.map((item) => item.id), ['a-show']);
  });

  test('a server that fails its scan costs the row nothing', () async {
    final client = _ThrowingClient(id: 'srv');
    final manager = MultiServerManager()..debugRegisterClientForTesting(client);
    addTearDown(manager.dispose);

    expect(await RecommendationsService(manager).recommend(libraries: [_library('1')]), isEmpty);
  });
  group('source scope', () {
    test('only the chosen backend is scanned', () async {
      final plex = _FakeClient(
        id: 'plex-1',
        shelf: [_item('liked', serverId: 'plex-1', favorite: true)],
      );
      final jellyfin = _FakeClient(
        id: 'jf-1',
        shelf: [_item('also-liked', serverId: 'jf-1', favorite: true)],
      );
      final manager = MultiServerManager()
        ..debugRegisterClientForTesting(plex)
        ..debugRegisterClientForTesting(jellyfin);
      addTearDown(manager.dispose);

      await RecommendationsService(manager).recommend(
        libraries: [
          _library('p', serverId: 'plex-1'),
          _library('j', serverId: 'jf-1', backend: MediaBackend.jellyfin),
        ],
        source: RecommendationsSource.plex,
      );

      expect(plex.scannedLibraries, ['p']);
      expect(jellyfin.scannedLibraries, isEmpty, reason: 'the other backend is out of scope');
    });

    test('all means all', () async {
      final plex = _FakeClient(
        id: 'plex-1',
        shelf: [_item('liked', serverId: 'plex-1', favorite: true)],
      );
      final jellyfin = _FakeClient(
        id: 'jf-1',
        shelf: [_item('also-liked', serverId: 'jf-1', favorite: true)],
      );
      final manager = MultiServerManager()
        ..debugRegisterClientForTesting(plex)
        ..debugRegisterClientForTesting(jellyfin);
      addTearDown(manager.dispose);

      await RecommendationsService(manager).recommend(
        libraries: [
          _library('p', serverId: 'plex-1'),
          _library('j', serverId: 'jf-1', backend: MediaBackend.jellyfin),
        ],
      );

      expect(plex.scannedLibraries, ['p']);
      expect(jellyfin.scannedLibraries, ['j']);
    });

    test('a scope with nothing connected yields no row rather than falling back', () async {
      final plex = _FakeClient(
        id: 'plex-1',
        shelf: [_item('liked', serverId: 'plex-1', favorite: true)],
      );
      final manager = MultiServerManager()..debugRegisterClientForTesting(plex);
      addTearDown(manager.dispose);

      final result = await RecommendationsService(manager).recommend(
        libraries: [_library('p', serverId: 'plex-1')],
        source: RecommendationsSource.emby,
      );

      expect(result, isEmpty);
      expect(plex.scannedLibraries, isEmpty);
    });
  });
}

class _ThrowingClient extends _FakeClient {
  _ThrowingClient({super.id});

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async => throw StateError('server gone');
}
