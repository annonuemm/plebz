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
  _FakeClient({String id = 'srv', this.shelf = const [], this.relatedById = const {}, this.shelfByLibrary = const {}})
    : serverId = ServerId(id);

  @override
  final ServerId serverId;

  final List<MediaItem> shelf;
  final Map<String, List<MediaItem>> relatedById;

  /// A library's own shelf, where one differs from [shelf].
  final Map<String, List<MediaItem>> shelfByLibrary;

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
    final items = shelfByLibrary[libraryId] ?? shelf;
    return LibraryPage(items: items, totalCount: items.length);
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
  String? title,
  int? year,
  MediaBackend backend = MediaBackend.plex,
  double? userRating,
  int? lastViewedAt,
  int? durationMs,
  int? viewOffsetMs,
  int? leafCount,
  int? viewedLeafCount,
}) => testMediaItem(
  id: id,
  backend: backend,
  kind: kind,
  title: title ?? id,
  year: year,
  serverId: serverId,
  isFavorite: favorite,
  viewCount: viewCount,
  userRating: userRating,
  lastViewedAt: lastViewedAt,
  durationMs: durationMs,
  viewOffsetMs: viewOffsetMs,
  leafCount: leafCount,
  viewedLeafCount: viewedLeafCount,
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

  test('every seed is heard, so one favourite cannot fill the row', () async {
    final client = _FakeClient(
      shelf: [_item('a', favorite: true), _item('b', favorite: true)],
      relatedById: {
        'a': [_item('a1'), _item('a2')],
        'b': [_item('b1'), _item('b2')],
      },
    );
    final s = withClient(client);

    expect((await s.service.recommend(libraries: [_library('1')])).map((item) => item.id).toSet(), {
      'a1',
      'b1',
      'a2',
      'b2',
    });
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

  group('one title, wherever it is', () {
    ({_FakeClient plex, _FakeClient jellyfin, RecommendationsService service}) twoServers({
      List<MediaItem> plexShelf = const [],
      List<MediaItem> jellyfinShelf = const [],
      Map<String, List<MediaItem>> plexRelated = const {},
      Map<String, List<MediaItem>> jellyfinRelated = const {},
    }) {
      final plex = _FakeClient(id: 'plex', shelf: plexShelf, relatedById: plexRelated);
      final jellyfin = _FakeClient(id: 'jf', shelf: jellyfinShelf, relatedById: jellyfinRelated);
      final manager = MultiServerManager()
        ..debugRegisterClientForTesting(plex)
        ..debugRegisterClientForTesting(jellyfin);
      addTearDown(manager.dispose);
      return (plex: plex, jellyfin: jellyfin, service: RecommendationsService(manager));
    }

    final libraries = [_library('p', serverId: 'plex'), _library('j', serverId: 'jf', backend: MediaBackend.jellyfin)];

    test('a film on Plex and on Jellyfin is one entry', () async {
      final s = twoServers(
        plexShelf: [_item('liked-p', serverId: 'plex', favorite: true)],
        jellyfinShelf: [_item('liked-j', serverId: 'jf', favorite: true, backend: MediaBackend.jellyfin)],
        plexRelated: {
          'liked-p': [_item('dune-p', serverId: 'plex', title: 'Dune', year: 2021)],
        },
        jellyfinRelated: {
          'liked-j': [_item('dune-j', serverId: 'jf', title: 'Dune', year: 2021, backend: MediaBackend.jellyfin)],
        },
      );

      final result = await s.service.recommend(libraries: libraries);

      expect(result.where((item) => item.title == 'Dune'), hasLength(1));
    });

    test('watched on one server is watched on the other', () async {
      final s = twoServers(
        plexShelf: [_item('liked', serverId: 'plex', favorite: true)],
        jellyfinShelf: [
          _item('seen-j', serverId: 'jf', title: 'Arrival', year: 2016, viewCount: 1, backend: MediaBackend.jellyfin),
        ],
        plexRelated: {
          'liked': [
            _item('arrival-p', serverId: 'plex', title: 'Arrival', year: 2016),
            _item('other', serverId: 'plex'),
          ],
        },
      );

      final result = await s.service.recommend(libraries: libraries);

      expect(result.map((item) => item.id), ['other']);
    });

    test('a title watched on both counts as one seed', () async {
      final s = twoServers(
        plexShelf: [_item('seen-p', serverId: 'plex', title: 'Heat', year: 1995, viewCount: 1)],
        jellyfinShelf: [
          _item('seen-j', serverId: 'jf', title: 'Heat', year: 1995, viewCount: 1, backend: MediaBackend.jellyfin),
        ],
      );

      await s.service.recommend(libraries: libraries);

      expect([...s.plex.relatedCalls, ...s.jellyfin.relatedCalls], hasLength(1));
    });
  });

  group('what is under way', () {
    test('an episode in Continue Watching makes its series a seed', () async {
      // A profile that has finished nothing yet had nothing to go on.
      final client = _FakeClient(
        relatedById: {
          'show-1': [_item('alike', kind: MediaKind.show)],
        },
      );
      final s = withClient(client);
      final episode = testMediaItem(
        id: 'ep-1',
        kind: MediaKind.episode,
        title: 'Pilot',
        serverId: 'srv',
        grandparentId: 'show-1',
        grandparentTitle: 'The Show',
      );

      final result = await s.service.recommend(libraries: [_library('1')], underWay: [episode]);

      expect(client.relatedCalls, ['show-1']);
      expect(result.map((item) => item.id), ['alike']);
    });

    test('a series under way is never suggested back', () async {
      final client = _FakeClient(
        shelf: [_item('liked', favorite: true)],
        relatedById: {
          'liked': [_item('show-1', kind: MediaKind.show), _item('other')],
        },
      );
      final s = withClient(client);
      final episode = testMediaItem(
        id: 'ep-1',
        kind: MediaKind.episode,
        title: 'Pilot',
        serverId: 'srv',
        grandparentId: 'show-1',
        grandparentTitle: 'The Show',
      );

      final result = await s.service.recommend(
        libraries: [_library('1')],
        underWay: [episode],
        excludeItems: [episode],
      );

      expect(result.map((item) => item.id), ['other']);
    });

    test('the libraries the viewer is watching in are read first', () async {
      final client = _FakeClient();
      final s = withClient(client);
      final film = testMediaItem(id: 'half', title: 'Half', serverId: 'srv', libraryId: 'lib-9');

      await s.service.recommend(libraries: [for (var i = 0; i < 10; i++) _library('lib-$i')], underWay: [film]);

      expect(client.scannedLibraries.first, 'lib-9');
      expect(client.scannedLibraries, hasLength(RecommendationsService.maxSeedLibraries));
    });
  });

  test('a title several seeds point at goes first more often, but not always', () async {
    final client = _FakeClient(
      shelf: [_item('a', favorite: true), _item('b', favorite: true), _item('c', favorite: true)],
      relatedById: {
        'a': [_item('only-a'), _item('shared')],
        'b': [_item('only-b'), _item('shared')],
        'c': [_item('only-c')],
      },
    );
    final s = withClient(client);

    final firsts = <String, int>{};
    for (var rotation = 0; rotation < 120; rotation++) {
      final result = await s.service.recommend(libraries: [_library('1')], rotation: rotation);
      expect(result.map((item) => item.id).toSet(), {'shared', 'only-a', 'only-b', 'only-c'});
      firsts.update(result.first.id, (count) => count + 1, ifAbsent: () => 1);
    }

    // The better guess has the better chance; a fixed seat at the front
    // would pin it there for as long as the seeds stay.
    final shared = firsts['shared'] ?? 0;
    for (final other in ['only-a', 'only-b', 'only-c']) {
      expect(shared, greaterThan(firsts[other] ?? 0), reason: '$firsts');
    }
    expect(shared, lessThan(120), reason: 'others get the front too: $firsts');
  });

  group('Mehr davon, Weniger davon', () {
    test('a title asked for more of is a seed, and what is like it is favoured', () async {
      final client = _FakeClient(
        shelf: [_item('seen', viewCount: 1)],
        relatedById: {
          'seen': [_item('x1'), _item('x2'), _item('x3')],
          'loved': [_item('y1'), _item('y2'), _item('y3')],
        },
      );
      final s = withClient(client);
      var fromLoved = 0;
      for (var rotation = 0; rotation < 60; rotation++) {
        final result = await s.service.recommend(
          libraries: [_library('1')],
          liked: [_item('loved')],
          rotation: rotation,
        );
        if (result.first.id.startsWith('y')) fromLoved++;
      }
      expect(client.relatedCalls, contains('loved'));
      expect(fromLoved, greaterThan(30), reason: 'doubled weight, more often first');
    });

    test('a disliked title stays out, and what is like it is held back', () async {
      final client = _FakeClient(
        shelf: [_item('liked', favorite: true)],
        relatedById: {
          'liked': [_item('hated'), _item('alike'), _item('fine')],
        },
      );
      final s = withClient(client);
      var alikeFirst = 0;
      for (var rotation = 0; rotation < 80; rotation++) {
        final result = await s.service.recommend(
          libraries: [_library('1')],
          disliked: {RecommendationsService.copyKeyOf(_item('hated'))},
          heldBack: {RecommendationsService.copyKeyOf(_item('alike'))},
          rotation: rotation,
        );
        expect(result.map((item) => item.id), isNot(contains('hated')));
        expect(result.map((item) => item.id), contains('alike'), reason: 'held back, not hidden');
        if (result.first.id == 'alike') alikeFirst++;
      }
      expect(alikeFirst, lessThan(40), reason: 'a quarter of the chance');
    });

    test('the liked pool takes turns as seeds across periods', () async {
      final client = _FakeClient();
      final s = withClient(client);
      final liked = [for (var i = 0; i < 9; i++) _item('fav-$i')];
      final heard = <String>{};
      for (var rotation = 0; rotation < 12; rotation++) {
        client.relatedCalls.clear();
        await s.service.recommend(libraries: [_library('1')], liked: liked, rotation: rotation);
        heard.addAll(client.relatedCalls);
      }
      expect(heard, containsAll([for (final item in liked) item.id]), reason: 'every liked title gets its turn');
    });
  });

  test('seeds come from every library, not the first three', () async {
    final client = _FakeClient(
      shelfByLibrary: {
        'lib-5': [_item('liked', favorite: true)],
      },
      relatedById: {
        'liked': [_item('suggested')],
      },
    );
    final s = withClient(client);

    final result = await s.service.recommend(libraries: [for (var i = 0; i < 6; i++) _library('lib-$i')]);

    expect(result.map((item) => item.id), ['suggested']);
  });

  test('a title rated highly is a seed, and favourites and ratings leave room for what was watched last', () async {
    final client = _FakeClient(
      shelf: [
        for (var i = 0; i < 6; i++) _item('fav-$i', favorite: true),
        for (var i = 0; i < 6; i++) _item('rated-$i', userRating: 9),
        for (var i = 0; i < 6; i++) _item('seen-$i', viewCount: 1, lastViewedAt: 1000 - i),
        _item('rated-low', userRating: 5),
      ],
    );
    final s = withClient(client);

    await s.service.recommend(libraries: [_library('1')]);

    final asked = client.relatedCalls;
    expect(asked, hasLength(RecommendationsService.maxSeeds));
    expect(asked.where((id) => id.startsWith('fav-')), hasLength(RecommendationsService.maxFavouriteSeeds));
    expect(asked.where((id) => id.startsWith('rated-')), hasLength(RecommendationsService.maxRatedSeeds));
    expect(asked.where((id) => id.startsWith('seen-')), ['seen-0', 'seen-1', 'seen-2', 'seen-3']);
    expect(asked, isNot(contains('rated-low')));
  });

  test('a film with a resume point or a series under way is not suggested', () async {
    final client = _FakeClient(
      shelf: [_item('liked', favorite: true)],
      relatedById: {
        'liked': [
          _item('resumable', durationMs: 6000000, viewOffsetMs: 1200000),
          _item('half-seen', kind: MediaKind.show, leafCount: 10, viewedLeafCount: 4),
          _item('fresh'),
        ],
      },
    );
    final s = withClient(client);

    final result = await s.service.recommend(libraries: [_library('1')]);

    expect(result.map((item) => item.id), ['fresh']);
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
