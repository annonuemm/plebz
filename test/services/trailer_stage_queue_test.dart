import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/media/trailer_stage_selection.dart';
import 'package:plezy/services/playback_initialization_types.dart';
import 'package:plezy/services/trailer_stage_queue.dart';

/// A film, and whether the server holds a trailer for it.
typedef _Title = ({String id, bool hasTrailer});

MediaItem _movie(String id, String serverId) =>
    PlexMediaItem(id: id, kind: MediaKind.movie, title: 'Film $id', serverId: serverId);

MediaItem _trailerExtra(String id, String serverId) =>
    PlexMediaItem(id: '$id-trailer', kind: MediaKind.clip, title: 'Trailer', subtype: 'trailer', serverId: serverId);

/// Only the three calls the queue makes. Counts them, so a test can pin how
/// much sifting one trailer costs.
class _FakeClient implements MediaServerClient {
  _FakeClient({required String serverId, required this.titles, this.failExtrasFor = const {}})
    : serverId = ServerId(serverId);

  @override
  final ServerId serverId;
  @override
  final String serverName = 'Server';

  final List<_Title> titles;

  /// Ids whose extras request throws, standing in for an unreachable title.
  final Set<String> failExtrasFor;

  int pageCalls = 0;
  int extrasCalls = 0;
  final List<LibraryQuery> queries = [];

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    Object? abort,
  }) async {
    pageCalls++;
    queries.add(query);
    final page = titles.skip(query.offset).take(query.limit).map((title) => _movie(title.id, serverId)).toList();
    return LibraryPage(items: page, totalCount: titles.length, offset: query.offset);
  }

  @override
  Future<List<MediaItem>> fetchExtras(String id) async {
    extrasCalls++;
    if (failExtrasFor.contains(id)) throw StateError('unreachable');
    final title = titles.firstWhere((t) => t.id == id);
    return title.hasTrailer ? [_trailerExtra(id, serverId)] : const [];
  }

  @override
  Future<ExternalPlaybackTarget?> resolveExternalPlayback(
    MediaItem item, {
    int mediaIndex = 0,
    String? mediaSourceId,
  }) async => ExternalPlaybackTarget(url: 'https://server/${item.id}?X-Plex-Token=abc');

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TrailerStageLibrary _library(_FakeClient client, {MediaKind kind = MediaKind.movie, Map<String, String>? genres}) =>
    (client: client, libraryId: 'lib-1', kind: kind, genres: genres ?? const <String, String>{});

void main() {
  group('TrailerStageQueue', () {
    test('skips the titles with no trailer and plays the ones that have one', () async {
      final client = _FakeClient(
        serverId: 's1',
        titles: const [(id: 'a', hasTrailer: false), (id: 'b', hasTrailer: true), (id: 'c', hasTrailer: false)],
      );
      final queue = TrailerStageQueue(
        libraries: [_library(client)],
        selection: const TrailerStageSelection(),
        random: Random(1),
        pageSize: 10,
      );

      final entry = await queue.next();

      expect(entry, isNotNull);
      expect(entry!.item.id, 'b');
      expect(entry.trailer.id, 'b-trailer');
      expect(entry.url, contains('b-trailer'));
      // Every title was looked at, and the report says how many carried one.
      expect(queue.examined, 3);
      expect(queue.found, 1);
    });

    test('ends the evening when nothing is left', () async {
      final client = _FakeClient(serverId: 's1', titles: const [(id: 'a', hasTrailer: false)]);
      final queue = TrailerStageQueue(
        libraries: [_library(client)],
        selection: const TrailerStageSelection(),
        pageSize: 10,
      );

      expect(await queue.next(), isNull);
      expect(queue.isExhausted, isTrue);
      expect(queue.examined, 1);
      expect(queue.found, 0);
    });

    test('a title that cannot be reached costs one entry, not the evening', () async {
      final client = _FakeClient(
        serverId: 's1',
        titles: const [(id: 'a', hasTrailer: true), (id: 'b', hasTrailer: true)],
        failExtrasFor: {'a'},
      );
      final queue = TrailerStageQueue(
        libraries: [_library(client)],
        selection: const TrailerStageSelection(),
        random: Random(3),
        pageSize: 10,
      );

      final first = await queue.next();

      expect(first?.item.id, 'b');
      expect(queue.examined, 2);
      expect(queue.found, 1);
    });

    test('the look-ahead means the second trailer needs no new page', () async {
      final client = _FakeClient(
        serverId: 's1',
        titles: const [
          (id: 'a', hasTrailer: true),
          (id: 'b', hasTrailer: true),
          (id: 'c', hasTrailer: true),
          (id: 'd', hasTrailer: true),
        ],
      );
      final queue = TrailerStageQueue(
        libraries: [_library(client)],
        selection: const TrailerStageSelection(),
        pageSize: 10,
      );

      await queue.next();
      final pagesAfterFirst = client.pageCalls;
      final second = await queue.next();

      expect(second, isNotNull);
      expect(client.pageCalls, pagesAfterFirst);
    });

    test('a library of the wrong kind is never asked', () async {
      final client = _FakeClient(serverId: 's1', titles: const [(id: 'a', hasTrailer: true)]);
      final queue = TrailerStageQueue(
        libraries: [_library(client, kind: MediaKind.show)],
        selection: const TrailerStageSelection(kind: TrailerStageKind.movie),
      );

      expect(queue.hasSources, isFalse);
      expect(await queue.next(), isNull);
      expect(client.pageCalls, 0);
    });

    test('a library that knows none of the chosen genres is left out', () async {
      final knows = _FakeClient(serverId: 's1', titles: const [(id: 'a', hasTrailer: true)]);
      final knowsNot = _FakeClient(serverId: 's2', titles: const [(id: 'b', hasTrailer: true)]);
      final queue = TrailerStageQueue(
        libraries: [
          _library(knows, genres: const {'Drama': '7'}),
          _library(knowsNot, genres: const {'Comedy': '9'}),
        ],
        selection: const TrailerStageSelection(genres: {'Drama'}),
        pageSize: 10,
      );

      await queue.next();

      expect(knows.pageCalls, 1);
      expect(knowsNot.pageCalls, 0);
      // The library that does know the genre asks for it by its own value.
      expect(knows.queries.single.filters.single.values, ['7']);
    });

    test('draws from every eligible library', () async {
      final one = _FakeClient(serverId: 's1', titles: const [(id: 'a', hasTrailer: true)]);
      final two = _FakeClient(serverId: 's2', titles: const [(id: 'b', hasTrailer: true)]);
      final queue = TrailerStageQueue(
        libraries: [_library(one), _library(two)],
        selection: const TrailerStageSelection(),
        random: Random(5),
        pageSize: 10,
      );

      final seen = <String>{};
      for (var i = 0; i < 2; i++) {
        final entry = await queue.next();
        if (entry != null) seen.add(entry.item.id);
      }

      expect(seen, {'a', 'b'});
    });

    test('a disposed queue hands out nothing more', () async {
      final client = _FakeClient(serverId: 's1', titles: const [(id: 'a', hasTrailer: true)]);
      final queue = TrailerStageQueue(
        libraries: [_library(client)],
        selection: const TrailerStageSelection(),
        pageSize: 10,
      );

      queue.dispose();

      expect(await queue.next(), isNull);
    });
  });
}
