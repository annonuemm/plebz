import 'dart:async';
import 'dart:math';

import '../media/media_filter.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_library.dart';
import '../media/media_server_client.dart';
import '../media/trailer_stage_selection.dart';
import '../screens/media_detail/trailer_extras.dart';
import '../utils/app_logger.dart';
import '../media/ids.dart';

/// One library the stage may draw from.
///
/// [genres] maps genre display name to this library's own filter value, since
/// a Plex genre id belongs to the section that issued it. An empty map means
/// "genres unknown here" — the selection then drops its genre clause for this
/// library rather than inventing a value.
typedef TrailerStageLibrary = ({
  MediaServerClient client,
  String libraryId,
  MediaKind kind,
  Map<String, String> genres,
});

/// A title whose trailer is ready to play.
class TrailerStageEntry {
  const TrailerStageEntry({required this.item, required this.trailer, required this.url});

  /// The film or series the trailer belongs to — what the facts line names.
  final MediaItem item;

  /// The extra that is the trailer.
  final MediaItem trailer;

  /// Self-contained stream URL, token in the query string. Resolved through
  /// [MediaServerClient.resolveExternalPlaybackUrl] on purpose: a trailer
  /// needs no transcode session and must not report progress, so the stage
  /// never appears in the server's dashboard or on a tracker.
  final String url;
}

/// Feeds the trailer stage one playable trailer after another.
///
/// The hard part is not the order but the sifting. A library query answers
/// with titles, and whether a title has a trailer is a separate request per
/// title ([MediaServerClient.fetchExtras]). So the queue keeps two buffers: a
/// pool of candidates drawn in random order, and a short run of resolved
/// entries kept ahead of what is playing. Titles without a trailer are
/// skipped silently — the viewer asked for trailers, not for apologies.
///
/// [examined] and [found] are the honest report of that sifting, which is also
/// the answer to "does my library even have trailers".
class TrailerStageQueue {
  TrailerStageQueue({
    required this.libraries,
    required this.selection,
    Random? random,
    this.pageSize = 30,
    this.lookAhead = 2,
  }) : _random = random ?? Random(),
       _sources = [
         for (final library in libraries)
           if (selection.kind.accepts(library.kind) && selection.canBeServedBy(library.genres)) _Source(library),
       ];

  final List<TrailerStageLibrary> libraries;
  final TrailerStageSelection selection;

  /// How many titles one library query asks for at a time.
  final int pageSize;

  /// How many resolved entries to keep beyond the one in hand. Two is enough
  /// to cover a switch without holding a long tail of stale URLs.
  final int lookAhead;

  final Random _random;
  final List<_Source> _sources;

  final List<MediaItem> _candidates = [];
  final List<TrailerStageEntry> _ready = [];
  final Set<String> _seen = {};

  int _examined = 0;
  int _found = 0;
  bool _disposed = false;
  Future<void>? _filling;

  /// Titles whose extras have been looked at.
  int get examined => _examined;

  /// How many of those had a trailer.
  int get found => _found;

  /// True once every library has been walked to its end and nothing is left.
  bool get isExhausted => _ready.isEmpty && _candidates.isEmpty && _sources.every((s) => s.drained);

  /// Whether the stage has any library to draw from at all. False when the
  /// selection names a kind no library holds, or genres none of them know.
  bool get hasSources => _sources.isNotEmpty;

  /// The next trailer, or null when there are no more.
  ///
  /// Returns from the look-ahead buffer when it can, and only waits when the
  /// buffer is empty — which is the first call and, after that, only when the
  /// sifting could not keep up.
  Future<TrailerStageEntry?> next() async {
    while (_ready.isEmpty) {
      if (_disposed) return null;
      final filled = await _fill();
      if (!filled) return null;
    }
    final entry = _ready.removeAt(0);
    // Deliberately not awaited: the picture should start now, and the next
    // title can be sifted while it plays.
    unawaited(_fill());
    return entry;
  }

  /// Resolve entries until the look-ahead is full. Returns false when nothing
  /// more can be resolved, ever.
  Future<bool> _fill() {
    final running = _filling;
    if (running != null) return running.then((_) => _ready.isNotEmpty);
    final work = _fillOnce();
    _filling = work;
    return work.then((_) {
      _filling = null;
      return _ready.isNotEmpty;
    });
  }

  Future<void> _fillOnce() async {
    while (!_disposed && _ready.length <= lookAhead) {
      if (_candidates.isEmpty && !await _loadCandidates()) return;
      if (_candidates.isEmpty) return;
      final item = _candidates.removeAt(0);
      final entry = await _resolve(item);
      if (entry != null) _ready.add(entry);
    }
  }

  /// One title: does it have a trailer, and where does it stream from.
  Future<TrailerStageEntry?> _resolve(MediaItem item) async {
    final source = _sourceFor(item);
    if (source == null) return null;
    try {
      final extras = await source.fetchExtras(item.id);
      _examined++;
      final trailer = primaryTrailerFor(item, extras);
      if (trailer == null) return null;
      final url = (await source.resolveExternalPlayback(trailer))?.url;
      if (url == null) return null;
      _found++;
      return TrailerStageEntry(item: item, trailer: trailer, url: url);
    } catch (e) {
      // One unreachable title must not end the evening. It counts as examined
      // so the report stays honest about how much was looked at.
      _examined++;
      appLogger.d('Trailer stage: ${item.title} could not be resolved', error: e);
      return null;
    }
  }

  MediaServerClient? _sourceFor(MediaItem item) =>
      _sources.firstWhereOrNullBy((s) => s.library.client.serverId == item.serverId)?.library.client;

  /// Draw one more page from every library that still has one, shuffled
  /// together.
  ///
  /// The servers already answer in random order; shuffling the merge keeps two
  /// libraries from arriving in alternating blocks.
  Future<bool> _loadCandidates() async {
    final live = _sources.where((s) => !s.drained).toList();
    if (live.isEmpty) return false;
    final pages = await Future.wait([for (final source in live) _loadPage(source)]);
    final drawn = <MediaItem>[];
    for (final page in pages) {
      for (final item in page) {
        if (_seen.add(item.globalKey)) drawn.add(item);
      }
    }
    drawn.shuffle(_random);
    _candidates.addAll(drawn);
    return drawn.isNotEmpty || _sources.any((s) => !s.drained);
  }

  Future<List<MediaItem>> _loadPage(_Source source) async {
    try {
      final page = await source.library.client.fetchLibraryPagedContent(
        source.library.libraryId,
        query: selection.queryFor(
          source.library.kind,
          libraryGenres: source.library.genres,
          offset: source.offset,
          limit: pageSize,
        ),
        libraryKind: source.library.kind,
      );
      source.offset += page.items.length;
      // A short page is the end of this library. The total is not trusted for
      // that: a random sort makes some backends report a total they then do
      // not deliver.
      if (page.items.length < pageSize) source.drained = true;
      return page.items;
    } catch (e) {
      appLogger.w('Trailer stage: library ${source.library.libraryId} page failed', error: e);
      source.drained = true;
      return const [];
    }
  }

  void dispose() {
    _disposed = true;
    _candidates.clear();
    _ready.clear();
  }
}

/// Loads the values of one filter category for one library. The app's
/// implementation reaches for the Plex-only `getFilterValues`; a backend that
/// already answered with its values (Jellyfin) never needs it.
typedef FilterValuesLoader = Future<List<MediaFilterValue>> Function(MediaServerClient client, MediaFilter filter);

/// The libraries the stage may draw from, with no genres resolved yet.
///
/// Costs nothing: the libraries come from the provider and the clients from
/// the manager, so the selection screen can be on the television before a
/// single request goes out.
///
/// Only film and series libraries are considered — a music or photo library
/// has no trailers, and asking it would spend a request to learn that. Hidden
/// libraries stay hidden here too: a library the viewer took off the home
/// screen has no business supplying an evening's programme.
List<TrailerStageLibrary> trailerStageLibrariesFrom({
  required List<MediaLibrary> libraries,
  required MediaServerClient? Function(ServerId serverId) clientFor,
}) {
  final sources = <TrailerStageLibrary>[];
  for (final library in libraries) {
    if (library.hidden) continue;
    if (library.kind != MediaKind.movie && library.kind != MediaKind.show) continue;
    final serverId = library.serverId;
    if (serverId == null) continue;
    final client = clientFor(ServerId(serverId));
    if (client == null) continue;
    sources.add((client: client, libraryId: library.id, kind: library.kind, genres: const <String, String>{}));
  }
  return sources;
}

/// The same libraries with each one's genre catalog filled in.
///
/// Two requests per library on Plex — the categories, then the genre values —
/// so every library is asked at once rather than in turn, and the caller runs
/// this behind the screen it has already drawn.
Future<List<TrailerStageLibrary>> withTrailerStageGenres(
  List<TrailerStageLibrary> libraries, {
  FilterValuesLoader? loadFilterValues,
}) async {
  final catalogs = await Future.wait([for (final library in libraries) _genresFor(library, loadFilterValues)]);
  return [
    for (final (index, library) in libraries.indexed)
      (client: library.client, libraryId: library.libraryId, kind: library.kind, genres: catalogs[index]),
  ];
}

/// Genre display name → this library's own filter value.
///
/// Returns an empty map when the library offers no genre category or the
/// values cannot be loaded. The selection then drops its genre clause for
/// this library, which shows too much rather than nothing — a stage that
/// silently skipped a whole library would look like missing trailers.
Future<Map<String, String>> _genresFor(TrailerStageLibrary library, FilterValuesLoader? loadFilterValues) async {
  try {
    final result = await library.client.fetchLibraryFiltersWithValues(library.libraryId, libraryKind: library.kind);
    final genre = result.filters.firstWhereOrNullBy((f) {
      final name = f.filter.toLowerCase();
      return name == 'genre' || name == 'genres';
    });
    if (genre == null) return const {};
    final values = result.cachedValues[genre.filter] ?? result.cachedValues[genre.key] ?? const <MediaFilterValue>[];
    final resolved = values.isNotEmpty ? values : await loadFilterValues?.call(library.client, genre) ?? const [];
    return {
      for (final value in resolved)
        if (value.title.isNotEmpty) value.title: libraryFilterValueId(value.key, genre.filter),
    };
  } catch (e) {
    appLogger.d('Trailer stage: genres for library ${library.libraryId} unavailable', error: e);
    return const {};
  }
}

class _Source {
  _Source(this.library);

  final TrailerStageLibrary library;
  int offset = 0;
  bool drained = false;
}

extension _FirstWhereOrNull<E> on Iterable<E> {
  E? firstWhereOrNullBy(bool Function(E element) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
