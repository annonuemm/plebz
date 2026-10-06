import '../../media/library_query.dart';
import '../../media/media_filter.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_server_client.dart';
import '../../utils/media_server_http_client.dart' show AbortController;
import 'progress_routing.dart';
import 'tracker_progress_controller.dart';

/// Library browsing that answers "unwatched" and "last watched" from a
/// tracker-led profile's own state (fork addition).
///
/// The server evaluates those against the account, which a tracker-led
/// profile shares. So for such a query the library is read whole once —
/// with every other filter, the search and the letter jump still asked of
/// the server — and filtered, sorted and paged here. The whole read is kept
/// until the tracker's state changes; the profile's own marks since are laid
/// over it again at every page.
extension TrackerLibraryQuery on MediaServerClient {
  Future<LibraryPage<MediaItem>> fetchLibraryPageForProfile(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) {
    if (!TrackerProgressController.instance.isActive || !TrackerLibraryPages.needsProfileState(query)) {
      return fetchLibraryPagedContent(libraryId, query: query, libraryKind: libraryKind, abort: abort);
    }
    return TrackerLibraryPages.instance.page(this, libraryId, query: query, libraryKind: libraryKind, abort: abort);
  }
}

class TrackerLibraryPages {
  TrackerLibraryPages._();

  static final TrackerLibraryPages instance = TrackerLibraryPages._();

  /// How much of a library is read at most, and in pages of what size.
  static const int readLimit = 20000;
  static const int readPageSize = 500;

  static const _watchSorts = {'lastViewedAt', 'viewCount'};

  final Map<String, ({int revision, Future<List<MediaItem>> items})> _reads = {};

  static bool needsProfileState(LibraryQuery query) =>
      query.filters.any((clause) => clause.field == MediaFilterField.unwatched) ||
      _watchSorts.contains(query.sort?.field);

  Future<LibraryPage<MediaItem>> page(
    MediaServerClient client,
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async {
    final serverQuery = query.copyWith(
      offset: 0,
      limit: readPageSize,
      filters: [
        for (final clause in query.filters)
          if (clause.field != MediaFilterField.unwatched) clause,
      ],
      sort: _watchSorts.contains(query.sort?.field) ? null : query.sort,
    );
    final revision = TrackerProgressController.instance.revision.value;
    // Reads from before the tracker's state last changed are of no more use.
    _reads.removeWhere((_, read) => read.revision != revision);
    final key = '${client.serverId}|$libraryId|$libraryKind|$serverQuery';
    final kept = _reads[key];
    final read = kept != null && kept.revision == revision
        ? kept.items
        : (_reads[key] = (
            revision: revision,
            items: _readAll(client, libraryId, serverQuery, libraryKind, abort),
          )).items;
    final List<MediaItem> all;
    try {
      all = await read;
    } catch (_) {
      // A failed or cancelled read is not kept; the next page asks again.
      if (identical(_reads[key]?.items, read)) _reads.remove(key);
      rethrow;
    }

    var items = [for (final item in all) ProgressRouting.overlay(item)];
    for (final clause in query.filters) {
      if (clause.field != MediaFilterField.unwatched) continue;
      final wantUnwatched = clause.values.contains('1') != clause.op.isNegated;
      items = [
        for (final item in items)
          if (!item.isWatched == wantUnwatched) item,
      ];
    }
    final sort = query.sort;
    if (sort != null && _watchSorts.contains(sort.field)) {
      int valueOf(MediaItem item) => sort.field == 'viewCount' ? (item.viewCount ?? 0) : (item.lastViewedAt ?? 0);
      final ascending = sort.direction == LibrarySortDirection.ascending;
      items.sort((a, b) => ascending ? valueOf(a).compareTo(valueOf(b)) : valueOf(b).compareTo(valueOf(a)));
    }
    final start = query.offset.clamp(0, items.length);
    final end = (start + query.limit).clamp(start, items.length);
    return LibraryPage(items: items.sublist(start, end), totalCount: items.length, offset: query.offset);
  }

  static Future<List<MediaItem>> _readAll(
    MediaServerClient client,
    String libraryId,
    LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  ) async {
    final items = <MediaItem>[];
    while (items.length < readLimit) {
      final page = await client.fetchLibraryPagedContent(
        libraryId,
        query: query.copyWith(offset: items.length),
        libraryKind: libraryKind,
        abort: abort,
      );
      items.addAll(page.items);
      if (page.items.isEmpty || items.length >= page.totalCount) break;
    }
    return items;
  }

  void clear() => _reads.clear();
}
