import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/database/app_database.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/services/jellyfin_api_cache.dart';
import 'package:plezy/services/jellyfin_mappers.dart';
import 'package:plezy/services/plex_api_cache.dart';
import 'package:plezy/services/plex_mappers.dart';
import 'package:plezy/services/watch_progress/progress_routing.dart';

import '../../test_helpers/backend_client_fixtures.dart';
import '../../test_helpers/media_items.dart';

/// Says every item is half watched, the way a tracker's state would.
class _HalfWatched implements WatchStateOverlay {
  int calls = 0;

  @override
  MediaItem apply(MediaItem item) {
    calls++;
    return item.copyWith(viewOffsetMs: 1000);
  }
}

/// Breaks the overlay contract by handing back another kind of item.
class _WrongType implements WatchStateOverlay {
  @override
  MediaItem apply(MediaItem item) => testMediaItem(id: 'other', backend: MediaBackend.jellyfin);
}

PlexMediaItem _plexMovie() => PlexMappers.mediaItem(
  PlexMetadataDto.fromJsonWithImages(const {
    'ratingKey': '42',
    'type': 'movie',
    'title': 'Film',
    'viewOffset': 0,
  }).copyWith(serverId: ServerId('plex')),
);

MediaItem? _jellyfinMovie() => JellyfinMappers.mediaItem(
  const {'Id': 'film-1', 'Name': 'Film', 'Type': 'Movie'},
  serverId: ServerId('jellyfin'),
  absolutizer: null,
);

void main() {
  final routing = ProgressRouting.instance;
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    JellyfinApiCache.initialize(db);
  });

  tearDown(() async {
    routing.debugReset();
    await db.close();
  });

  group('with the server keeping the watch state (the default)', () {
    test('the server is in charge, and items pass through untouched', () {
      expect(routing.source, ProgressSourceKind.server);
      expect(routing.serverKeepsWatchState, isTrue);
      final item = testMediaItem(id: 'x');
      expect(identical(ProgressRouting.overlay(item), item), isTrue);
    });

    test('an overlay handed to the server is not used', () {
      final overlay = _HalfWatched();
      routing.activate(ProgressSourceKind.server, overlay: overlay);
      expect(_plexMovie().viewOffsetMs, 0);
      expect(overlay.calls, 0);
    });

    test('watched marks still reach Plex and Jellyfin', () async {
      final plexPaths = <String>[];
      final plex = testPlexClient(
        handler: (request) async {
          plexPaths.add(request.url.path);
          return http.Response('', 200);
        },
      );
      addTearDown(plex.close);
      final jellyfinPaths = <String>[];
      final jellyfin = testJellyfinClient(
        handler: (request) async {
          jellyfinPaths.add(request.url.path);
          return http.Response('{}', 200, headers: const {'content-type': 'application/json'});
        },
      );
      addTearDown(jellyfin.close);

      final plexItem = testMediaItem(id: '42', backend: MediaBackend.plex, kind: MediaKind.movie);
      await plex.markWatched(plexItem);
      await plex.markUnwatched(plexItem);
      expect(plexPaths, ['/:/scrobble', '/:/unscrobble']);

      final jellyfinItem = testMediaItem(id: 'film-1', backend: MediaBackend.jellyfin, kind: MediaKind.movie);
      await jellyfin.markWatched(jellyfinItem);
      await jellyfin.markUnwatched(jellyfinItem);
      expect(jellyfinPaths, hasLength(2));
    });
  });

  group('with a tracker keeping the watch state', () {
    test('every backend\'s items carry the tracker\'s state', () {
      final overlay = _HalfWatched();
      routing.activate(ProgressSourceKind.tracker, overlay: overlay);
      expect(routing.serverKeepsWatchState, isFalse);

      final plex = _plexMovie();
      expect(plex, isA<PlexMediaItem>());
      expect(plex.viewOffsetMs, 1000);
      expect(_jellyfinMovie()!.viewOffsetMs, 1000);
      expect(overlay.calls, 2);
    });

    test('an overlay that changes the kind of item is not trusted', () {
      routing.activate(ProgressSourceKind.tracker, overlay: _WrongType());
      final plex = _plexMovie();
      expect(plex.id, '42');
    });

    test('watched marks do not reach the shared server account', () async {
      routing.activate(ProgressSourceKind.tracker, overlay: _HalfWatched());
      var requests = 0;
      final plex = testPlexClient(
        handler: (_) async {
          requests++;
          return http.Response('', 200);
        },
      );
      addTearDown(plex.close);
      final jellyfin = testJellyfinClient(
        handler: (_) async {
          requests++;
          return http.Response('{}', 200);
        },
      );
      addTearDown(jellyfin.close);

      final item = testMediaItem(id: '42', backend: MediaBackend.plex, kind: MediaKind.movie);
      await plex.markWatched(item);
      await plex.markUnwatched(item);
      await jellyfin.markWatched(item);
      await jellyfin.markUnwatched(item);
      expect(requests, 0);
    });

    test('handing back to the server ends the overlay', () {
      routing.activate(ProgressSourceKind.tracker, overlay: _HalfWatched());
      routing.activate(ProgressSourceKind.server);
      expect(_plexMovie().viewOffsetMs, 0);
      expect(routing.serverKeepsWatchState, isTrue);
    });
  });
}
