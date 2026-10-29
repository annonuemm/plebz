import 'dart:async';

import '../exceptions/media_server_exceptions.dart';
import '../media/ids.dart';
import '../media/library_query.dart';
import '../media/media_hub.dart';
import '../media/media_filter.dart' show libraryFilterValueId;
import '../media/media_item.dart';
import '../media/media_item_merge.dart' show compareLibraryCopies;
import '../media/media_item_types.dart';
import '../media/media_kind.dart';
import '../media/media_library.dart';
import '../media/media_server_client.dart';
import '../utils/app_logger.dart';
import 'multi_server_manager.dart';
import 'plex_client.dart';
import 'plex_constants.dart';
import 'recommendations_service.dart';
import 'settings_service.dart';
import 'streaming_brands.dart';
import 'studio_browse_client.dart';

/// The id every brand row's hub goes by: this, then the brand's shortcut.
const brandRowHubPrefix = 'plebz:brand:';

bool isBrandRowHub(MediaHub hub) => hub.id.startsWith(brandRowHubPrefix);

/// The brand a brand row's hub stands for, or null for any other hub.
StreamingBrand? brandOfHub(MediaHub hub) =>
    isBrandRowHub(hub) ? StreamingBrand.fromShortcut(hub.id.substring(brandRowHubPrefix.length)) : null;

/// [row] as a home-screen hub: the brand's name over its titles, films and
/// series together, with "Alle" when there is more.
MediaHub brandRowHub(BrandRow row) => MediaHub(
  id: '$brandRowHubPrefix${row.brand.shortcut}',
  title: row.brand.displayName,
  type: 'mixed',
  items: row.items,
  size: row.items.length,
  more: row.more,
);

/// The viewer's arrangement of the brand rows.
BrandRowsLayout brandRowsLayout() =>
    BrandRowsLayout.decode(SettingsService.instanceOrNull?.read(PlebzPrefs.brandRowsLayout) ?? '');

/// One brand's row on the home screen: what it shows, and whether "Alle" has
/// more behind it.
typedef BrandRow = ({StreamingBrand brand, List<MediaItem> items, bool more});

/// The home screen's brand rows (Plebz): per streaming service, the titles of
/// the viewer's own libraries that name it as their network or studio.
///
/// Two steps per library: which of its studios and networks stand for which
/// brand (listed once and kept for [tagLifetime]), then, per brand, a handful
/// of its titles in the server's random order. The servers do the filtering,
/// so a brand costs one request per library that has it — none where it has
/// nothing.
class BrandRowsService {
  BrandRowsService(this._serverManager);

  final MultiServerManager _serverManager;

  /// Titles a row shows.
  static const rowLimit = 20;

  /// Titles asked of each library per brand: the row's worth, plus room for
  /// the copies another server holds of the same title.
  static const sampleSize = 30;

  /// Libraries consulted at most. The rows are a courtesy pass after the page
  /// is up; their cost is bounded, not proportional to a big server's list.
  static const maxLibraries = 12;

  /// Requests in flight at once — a weak TV box shares its connection with
  /// the artwork of the page it is filling.
  static const concurrency = 4;

  /// "Alle": the page size it reads in, and where it stops.
  static const allPageSize = 100;
  static const allLimit = 1000;

  /// A library's studio listing is read again after this long: a studio
  /// appears when a title naming it is added, which is rare.
  static const tagLifetime = Duration(hours: 6);

  final Map<String, ({DateTime at, Map<StreamingBrand, List<_BrandFilter>> filters})> _filters = {};

  /// The rows for [brands], in that order; a brand with nothing on any server
  /// is left out.
  Future<List<BrandRow>> rows({
    required List<MediaLibrary> libraries,
    required List<StreamingBrand> brands,
    DateTime Function() now = DateTime.now,
  }) async {
    final eligible = libraries.where(_holdsVideo).take(maxLibraries).toList();
    if (eligible.isEmpty || brands.isEmpty) return const [];

    final filters = await _bounded([for (final library in eligible) () => _filtersFor(library, now())]);

    // One request per brand, library and field that matched.
    final requests = <({StreamingBrand brand, MediaLibrary library, _BrandFilter filter})>[
      for (final brand in brands)
        for (final (index, library) in eligible.indexed)
          for (final filter in filters[index][brand] ?? const <_BrandFilter>[])
            (brand: brand, library: library, filter: filter),
    ];
    final samples = await _bounded([
      for (final request in requests)
        () => _page(request.library, request.filter, offset: 0, limit: sampleSize, random: true),
    ]);

    final rows = <BrandRow>[];
    for (final brand in brands) {
      final pages = [
        for (final (index, request) in requests.indexed)
          if (request.brand == brand) samples[index],
      ];
      final merged = _merged([for (final page in pages) page.items]);
      if (merged.isEmpty) continue;
      final more = merged.length > rowLimit || pages.any((page) => page.totalCount > page.items.length);
      rows.add((brand: brand, items: merged.take(rowLimit).toList(), more: more));
    }
    final counts = [for (final row in rows) '${row.brand.shortcut}=${row.items.length}${row.more ? '+' : ''}'];
    appLogger.d(
      'Brand rows: ${eligible.length} libraries, ${requests.length} requests → ${counts.isEmpty ? 'nothing' : counts.join(' ')}',
    );
    return rows;
  }

  /// Everything [brand] has across [libraries], by title — what "Alle" opens.
  Future<List<MediaItem>> all({
    required StreamingBrand brand,
    required List<MediaLibrary> libraries,
    DateTime Function() now = DateTime.now,
  }) async {
    final eligible = libraries.where(_holdsVideo).take(maxLibraries).toList();
    final filters = await _bounded([for (final library in eligible) () => _filtersFor(library, now())]);
    final lists = await _bounded([
      for (final (index, library) in eligible.indexed)
        for (final filter in filters[index][brand] ?? const <_BrandFilter>[]) () => _everything(library, filter),
    ]);
    final merged = _merged(lists);
    merged.sort((a, b) => a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase()));
    return merged;
  }

  /// One title per copy key, the best copy of it, read across [lists] in turn
  /// so one big library does not fill a row before the next is heard.
  static List<MediaItem> _merged(List<List<MediaItem>> lists) {
    final order = <String>[];
    final copies = <String, List<MediaItem>>{};
    final longest = lists.fold<int>(0, (most, items) => items.length > most ? items.length : most);
    for (var round = 0; round < longest; round++) {
      for (final items in lists) {
        if (round >= items.length) continue;
        final item = items[round];
        if (!(item.isMovie || item.isShow)) continue;
        final key = RecommendationsService.copyKeyOf(item);
        final known = copies[key];
        if (known == null) {
          order.add(key);
          copies[key] = [item];
        } else if (!known.any((copy) => copy.globalKey == item.globalKey)) {
          known.add(item);
        }
      }
    }
    return [for (final key in order) (copies[key]!..sort(compareLibraryCopies)).first];
  }

  /// Which of [library]'s studios and networks stand for which brand.
  Future<Map<StreamingBrand, List<_BrandFilter>>> _filtersFor(MediaLibrary library, DateTime now) async {
    final cached = _filters[library.globalKey];
    if (cached != null && now.difference(cached.at) < tagLifetime) return cached.filters;
    final client = _clientFor(library);
    if (client == null) return const {};
    final found = <StreamingBrand, List<_BrandFilter>>{};
    var failed = false;
    if (client is PlexClient) {
      // A series names its network in `network` and often in `studio` too, a
      // film only in `studio`. Each field is listed and filtered on its own.
      final fields = library.kind == MediaKind.show ? const ['network', 'studio'] : const ['studio'];
      final type = PlexMetadataType.forKind(library.kind);
      for (final field in fields) {
        try {
          final values = await client.getFilterValues(
            '/library/sections/${library.id}/$field${type == null ? '' : '?type=$type'}',
          );
          final ids = <StreamingBrand, List<String>>{};
          for (final value in values) {
            final brand = StreamingBrand.matching(value.title);
            if (brand != null) (ids[brand] ??= []).add(libraryFilterValueId(value.key, field));
          }
          for (final MapEntry(key: brand, value: values) in ids.entries) {
            (found[brand] ??= []).add(_BrandFilter(field, values));
          }
        } on MediaServerHttpException catch (error) {
          // A section without the field answers 404, which is an answer; any
          // other failure is tried again on the next pass rather than
          // remembered as "none".
          if (error.statusCode == 404) continue;
          appLogger.d('Brand rows: no $field listing in ${library.title}', error: error);
          failed = true;
        } catch (error) {
          appLogger.d('Brand rows: no $field listing in ${library.title}', error: error);
          failed = true;
        }
      }
    } else if (client case final StudioBrowseClient studioClient) {
      try {
        final studios = await studioClient.fetchLibraryStudios(library.id);
        final ids = <StreamingBrand, List<String>>{};
        for (final studio in studios) {
          final brand = StreamingBrand.matching(studio.name);
          if (brand != null) (ids[brand] ??= []).add(studio.id);
        }
        for (final MapEntry(key: brand, value: values) in ids.entries) {
          found[brand] = [_BrandFilter(_BrandFilter.studioIds, values)];
        }
      } catch (error) {
        appLogger.d('Brand rows: no studio listing in ${library.title}', error: error);
        failed = true;
      }
    }
    if (!failed || found.isNotEmpty) _filters[library.globalKey] = (at: now, filters: found);
    return found;
  }

  Future<LibraryPage<MediaItem>> _page(
    MediaLibrary library,
    _BrandFilter filter, {
    required int offset,
    required int limit,
    required bool random,
  }) async {
    final client = _clientFor(library);
    try {
      if (client is PlexClient) {
        final type = PlexMetadataType.forKind(library.kind);
        // Without collections, as the recommendation scan asks: a library
        // set to show a collection in place of its members would otherwise
        // answer with the collection.
        final page = await client.fetchLibraryPage(
          library.id,
          start: offset,
          size: limit,
          filters: {
            filter.field: filter.values.join(','),
            'includeCollections': '0',
            'type': ?type?.toString(),
            'sort': random ? 'random:asc' : 'titleSort:asc',
          },
        );
        return LibraryPage(items: page.items, totalCount: page.totalSize, offset: offset);
      }
      if (client case final StudioBrowseClient studioClient) {
        return await studioClient.fetchStudioTitles(
          library.id,
          studioIds: filter.values,
          kinds: switch (library.kind) {
            MediaKind.movie => const [MediaKind.movie],
            MediaKind.show => const [MediaKind.show],
            _ => const [MediaKind.movie, MediaKind.show],
          },
          offset: offset,
          limit: limit,
          random: random,
        );
      }
    } catch (error) {
      appLogger.d('Brand rows: ${filter.field} query failed in ${library.title}', error: error);
    }
    return LibraryPage(items: const [], totalCount: 0, offset: offset);
  }

  Future<List<MediaItem>> _everything(MediaLibrary library, _BrandFilter filter) async {
    final items = <MediaItem>[];
    while (items.length < allLimit) {
      final page = await _page(library, filter, offset: items.length, limit: allPageSize, random: false);
      items.addAll(page.items);
      if (page.items.length < allPageSize || items.length >= page.totalCount) break;
    }
    return items;
  }

  /// [tasks] run [concurrency] at a time; the results in [tasks]' order.
  static Future<List<T>> _bounded<T>(List<Future<T> Function()> tasks) async {
    final results = List<T?>.filled(tasks.length, null);
    var next = 0;
    Future<void> worker() async {
      while (next < tasks.length) {
        final index = next++;
        results[index] = await tasks[index]();
      }
    }

    await Future.wait([for (var i = concurrency.clamp(1, tasks.isEmpty ? 1 : tasks.length); i > 0; i--) worker()]);
    return results.cast<T>();
  }

  MediaServerClient? _clientFor(MediaLibrary library) {
    final serverId = serverIdOrNull(library.serverId);
    return serverId == null ? null : _serverManager.getClient(serverId);
  }

  /// Films and series. A Plex section always has a type; a Jellyfin library
  /// of mixed content does not, and is asked for both.
  static bool _holdsVideo(MediaLibrary library) =>
      library.kind == MediaKind.movie || library.kind == MediaKind.show || library.kind == MediaKind.unknown;
}

/// One field of one library to filter on, with the values that stand for a
/// brand there: Plex's `network` or `studio` with their value ids, or a
/// Jellyfin library's studio ids.
class _BrandFilter {
  const _BrandFilter(this.field, this.values);

  static const studioIds = 'studioIds';

  final String field;
  final List<String> values;
}
