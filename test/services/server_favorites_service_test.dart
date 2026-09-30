import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/media_filter.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/media/server_capabilities.dart';
import 'package:plezy/services/server_favorites_service.dart';

import '../test_helpers/media_items.dart';

class _FakeClient implements MediaServerClient {
  _FakeClient({required this.capabilities, this.total = 2, this.fails = false});

  @override
  final ServerCapabilities capabilities;

  final int total;
  final bool fails;
  final queries = <LibraryQuery>[];

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    Object? abort,
  }) async {
    queries.add(query);
    if (fails) throw Exception('library unreachable');
    final start = query.offset;
    final end = start + query.limit > total ? total : start + query.limit;
    return LibraryPage<MediaItem>(
      items: [
        for (var i = start; i < end; i++)
          testMediaItem(id: '$libraryId-$i', kind: MediaKind.movie, title: 'Fav $i', serverId: 'server-1'),
      ],
      totalCount: total,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaLibrary _library(String id, {String serverId = 'server-1'}) =>
    MediaLibrary(id: id, backend: MediaBackend.jellyfin, title: 'Library $id', serverId: serverId);

void main() {
  const service = ServerFavoritesService();

  test('collects favorites from every library that supports them', () async {
    final client = _FakeClient(capabilities: ServerCapabilities.jellyfin);

    final favorites = await service.fetchFavorites(libraries: [_library('a'), _library('b')], clientFor: (_) => client);

    expect(favorites.map((item) => item.id), ['a-0', 'a-1', 'b-0', 'b-1']);
    // `favoritesOnly` was a named flag until upstream 2.21 folded it into the
    // clause list.
    expect(
      client.queries.every((query) => query.filters.any((clause) => clause.field == MediaFilterField.favorite)),
      isTrue,
    );
  });

  test('skips Plex libraries entirely rather than dumping them', () async {
    // Plex ignores favoritesOnly, so an unguarded request would return the
    // whole library as "favorites".
    final plex = _FakeClient(capabilities: ServerCapabilities.plex, total: 500);

    final favorites = await service.fetchFavorites(libraries: [_library('a')], clientFor: (_) => plex);

    expect(favorites, isEmpty);
    expect(plex.queries, isEmpty, reason: 'no request should even be made');
  });

  test('one unreachable library does not empty the tab', () async {
    final ok = _FakeClient(capabilities: ServerCapabilities.jellyfin);
    final broken = _FakeClient(capabilities: ServerCapabilities.jellyfin, fails: true);

    final favorites = await service.fetchFavorites(
      libraries: [
        _library('a', serverId: 'broken'),
        _library('b', serverId: 'ok'),
      ],
      clientFor: (serverId) => serverId == 'ok' ? ok : broken,
    );

    expect(favorites.map((item) => item.id), ['b-0', 'b-1']);
  });

  test('a library whose server is not connected is skipped', () async {
    final favorites = await service.fetchFavorites(libraries: [_library('a')], clientFor: (_) => null);

    expect(favorites, isEmpty);
  });

  group('hasFavoritesCapableLibrary', () {
    test('is true when a connected server has favorites', () {
      expect(
        ServerFavoritesService.hasFavoritesCapableLibrary(
          libraries: [_library('a')],
          clientFor: (_) => _FakeClient(capabilities: ServerCapabilities.jellyfin),
        ),
        isTrue,
      );
    });

    test('is false for a Plex-only setup, so the tab is never offered', () {
      expect(
        ServerFavoritesService.hasFavoritesCapableLibrary(
          libraries: [_library('a')],
          clientFor: (_) => _FakeClient(capabilities: ServerCapabilities.plex),
        ),
        isFalse,
      );
    });

    test('is false without libraries', () {
      expect(ServerFavoritesService.hasFavoritesCapableLibrary(libraries: const [], clientFor: (_) => null), isFalse);
    });
  });
}
