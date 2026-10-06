import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/media_filter.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/services/watch_progress/progress_routing.dart';
import 'package:plezy/services/watch_progress/tracker_library_query.dart';

import '../../test_helpers/media_items.dart';

/// A library of five films, a to e, read in pages of two.
class _Library implements MediaServerClient {
  final queries = <LibraryQuery>[];

  @override
  ServerId get serverId => ServerId('plex');

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    Object? abort,
  }) async {
    queries.add(query);
    const ids = ['a', 'b', 'c', 'd', 'e'];
    final slice = ids.skip(query.offset).take(2);
    return LibraryPage(
      // The shared account has watched everything.
      items: [for (final id in slice) ProgressRouting.overlay(testMediaItem(id: id, serverId: 'plex', viewCount: 1))],
      totalCount: ids.length,
      offset: query.offset,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

/// The profile's tracker: b and d watched, d the more recently.
class _Tracker implements WatchStateOverlay {
  @override
  MediaItem apply(MediaItem item) => switch (item.id) {
    'b' => item.copyWith(viewCount: 1, lastViewedAt: 100),
    'd' => item.copyWith(viewCount: 1, lastViewedAt: 200),
    _ => item.copyWith(viewCount: 0, lastViewedAt: null),
  };
}

void main() {
  const unwatched = LibraryQuery(
    limit: 2,
    filters: [
      LibraryFilter(field: MediaFilterField.unwatched, values: ['1']),
    ],
  );

  setUp(() {
    TrackerLibraryPages.instance.clear();
    ProgressRouting.instance.activate(ProgressSourceKind.tracker, overlay: _Tracker());
  });

  tearDown(ProgressRouting.instance.debugReset);

  test('only queries about watching are answered here', () {
    expect(TrackerLibraryPages.needsProfileState(unwatched), isTrue);
    expect(TrackerLibraryPages.needsProfileState(const LibraryQuery(sort: LibrarySort(field: 'lastViewedAt'))), isTrue);
    expect(TrackerLibraryPages.needsProfileState(const LibraryQuery(sort: LibrarySort(field: 'title'))), isFalse);
  });

  test('"unwatched" pages through the profile\'s unwatched films, the library read once', () async {
    final library = _Library();
    final pages = TrackerLibraryPages.instance;

    final first = await pages.page(library, 'movies', query: unwatched);
    final second = await pages.page(library, 'movies', query: unwatched.copyWith(offset: 2));

    expect(first.items.map((item) => item.id), ['a', 'c']);
    expect(first.totalCount, 3);
    expect(second.items.map((item) => item.id), ['e']);
    expect(library.queries, hasLength(3), reason: 'five films in pages of two, once');
    expect(library.queries.every((query) => query.filters.isEmpty), isTrue, reason: 'the server is not asked');
  });

  test('"watched" is the other half', () async {
    final page = await TrackerLibraryPages.instance.page(
      _Library(),
      'movies',
      query: const LibraryQuery(
        limit: 10,
        filters: [
          LibraryFilter(field: MediaFilterField.unwatched, op: LibraryFilterOperator.isNot, values: ['1']),
        ],
      ),
    );
    expect(page.items.map((item) => item.id), ['b', 'd']);
  });

  test('"last watched" sorts by the profile\'s own viewing', () async {
    final library = _Library();
    final page = await TrackerLibraryPages.instance.page(
      library,
      'movies',
      query: const LibraryQuery(limit: 2, sort: LibrarySort(field: 'lastViewedAt')),
    );
    expect(page.items.map((item) => item.id), ['d', 'b']);
    expect(library.queries.first.sort, isNull);
  });
}
