import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/models/catalog/catalog_item.dart';
import 'package:plezy/models/catalog/catalog_metadata.dart';
import 'package:plezy/services/catalog/catalog_source.dart';
import 'package:plezy/services/catalog/seerr_catalog_source.dart';
import 'package:plezy/services/catalog/seerr_shelves.dart';

/// Records the discover calls the shelves make and answers with whatever the
/// test staged, so the assertions are about the query rather than the network.
class _RecordingSource implements SeerrCatalogSource {
  final movieCalls = <Map<String, Object?>>[];
  final tvCalls = <Map<String, Object?>>[];

  /// Answer per page number; anything unlisted comes back empty.
  Map<int, CatalogPage> pages = const {};

  @override
  Future<CatalogPage> discoverMoviesPage({
    int page = 1,
    int? studio,
    int? genre,
    String? sortBy,
    String? releaseDateGte,
    String? releaseDateLte,
    int? voteCountGte,
    int? watchProviders,
    String? watchRegion,
  }) async {
    movieCalls.add({
      'page': page,
      'studio': studio,
      'genre': genre,
      'sortBy': sortBy,
      'gte': releaseDateGte,
      'lte': releaseDateLte,
      'votes': voteCountGte,
      'watchProviders': watchProviders,
      'watchRegion': watchRegion,
    });
    return pages[page] ?? const CatalogPage(items: [], hasMore: false);
  }

  @override
  Future<CatalogPage> discoverTvPage({
    int page = 1,
    int? network,
    int? genre,
    String? sortBy,
    String? firstAirDateGte,
    String? firstAirDateLte,
    int? voteCountGte,
    int? watchProviders,
    String? watchRegion,
  }) async {
    tvCalls.add({
      'page': page,
      'network': network,
      'genre': genre,
      'sortBy': sortBy,
      'gte': firstAirDateGte,
      'lte': firstAirDateLte,
      'votes': voteCountGte,
      'watchProviders': watchProviders,
      'watchRegion': watchRegion,
    });
    return pages[page] ?? const CatalogPage(items: [], hasMore: false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CatalogItem _item(String title, {CatalogAvailability? availability}) => CatalogItem(
  source: CatalogSourceId.seerr,
  ids: CatalogItemIds(slug: title),
  kind: MediaKind.movie,
  title: title,
  serverState: availability == null ? null : CatalogServerState(availability: availability),
);

void main() {
  setUp(() => LocaleSettings.setLocaleSync(AppLocale.en));

  final today = DateTime(2026, 8, 30);

  List<SeerrShelf> shelvesFor(_RecordingSource source, {int? studioId, int? networkId, int rotation = 0}) =>
      seerrShelvesFor(source: source, now: today, studioId: studioId, networkId: networkId, rotation: rotation);

  test('the two availability rows are told apart by name', () {
    // A genre page carries both; identical titles would make them one row
    // repeated.
    final source = _RecordingSource();
    final titles = seerrShelvesFor(
      source: source,
      now: today,
      movieGenreId: 28,
      tvGenreId: 10759,
    ).where((shelf) => shelf.id.endsWith(':available')).map((shelf) => shelf.title).toList();

    expect(titles, hasLength(2));
    expect(titles.toSet(), hasLength(2));
    expect(titles.first, endsWith('Films'));
    expect(titles.last, endsWith('Series'));
  });

  test('the whole list leads the page, with a tab per kind', () {
    final source = _RecordingSource();

    // The shelves under it each answer one question; this is where to go when
    // none of them asked the right one.
    final genre = seerrShelvesFor(source: source, now: today, movieGenreId: 28, tvGenreId: 10759);
    expect(genre.first.id, 'all');
    expect(genre.first.tabs?.map((tab) => tab.kind), [MediaKind.movie, MediaKind.show]);

    final studio = shelvesFor(source, studioId: 2);
    expect(studio.first.tabs?.map((tab) => tab.kind), [MediaKind.movie], reason: 'one kind, one tab');
  });

  test('films and series alternate rather than following one another', () {
    final source = _RecordingSource();

    final ids = seerrShelvesFor(
      source: source,
      now: today,
      movieGenreId: 28,
      tvGenreId: 10759,
    ).skip(1).map((shelf) => shelf.id).toList();

    expect(ids.take(4), ['movie:popular', 'tv:popular', 'movie:recent', 'tv:recent']);
  });

  group('watch providers', () {
    const providers = [
      (id: 8, name: 'Netflix'),
      (id: 337, name: 'Disney Plus'),
      (id: 119, name: 'Amazon Prime Video'),
      (id: 350, name: 'Apple TV Plus'),
    ];

    test('matches a tile to a service across the punctuation both spell differently', () {
      expect(matchWatchProvider('Netflix', providers), 8);
      expect(matchWatchProvider('Disney+', providers), 337, reason: 'the plus is written out on one side');
      expect(matchWatchProvider('Prime Video', providers), 119, reason: 'and the company name is on the other');
      expect(matchWatchProvider('Apple TV+', providers), 350);
    });

    test('a service the instance does not offer stays unmatched', () {
      // A near miss would fill the row with somebody else's catalog.
      expect(matchWatchProvider('ARD', providers), isNull);
      expect(matchWatchProvider('', providers), isNull);
    });

    test("a network's film rows go through the availability filter, its series rows do not", () async {
      final source = _RecordingSource();
      final shelves = seerrShelvesFor(
        source: source,
        now: today,
        networkId: 213,
        movieWatchProviderId: 8,
        watchRegion: 'DE',
      );

      for (final shelf in shelves.skip(1)) {
        await shelf.load(1);
      }

      expect(source.movieCalls, isNotEmpty, reason: 'a network has films too, reached another way');
      expect(source.movieCalls.every((call) => call['watchProviders'] == 8 && call['watchRegion'] == 'DE'), isTrue);
      // Series stay on the network filter, which is the precise one for them.
      expect(source.tvCalls.every((call) => call['network'] == 213 && call['watchProviders'] == null), isTrue);
    });

    test('without a match a network keeps its series rows alone', () {
      final source = _RecordingSource();

      final kinds = seerrShelvesFor(source: source, now: today, networkId: 213).map((shelf) => shelf.kind).toSet();

      expect(kinds, {MediaKind.show});
    });
  });

  test('a studio gets film rows and a network series rows', () {
    final source = _RecordingSource();

    expect(shelvesFor(source, studioId: 2).map((shelf) => shelf.kind).toSet(), {
      MediaKind.movie,
    }, reason: 'a studio is a film concept');
    expect(shelvesFor(source, networkId: 213).map((shelf) => shelf.kind).toSet(), {MediaKind.show});
  });

  test('every row asks a different question of the same studio', () async {
    final source = _RecordingSource();

    for (final shelf in shelvesFor(source, studioId: 2)) {
      await shelf.load(1);
    }

    // The studio never changes; the sort and the date window are what differ.
    expect(source.movieCalls.every((call) => call['studio'] == 2), isTrue);
    final sorts = source.movieCalls.map((call) => call['sortBy']).toSet();
    expect(sorts, containsAll(['popularity.desc', 'primary_release_date.desc', 'primary_release_date.asc']));
  });

  test('new films are ones already out, upcoming ones are not', () async {
    final source = _RecordingSource();
    final shelves = {for (final shelf in shelvesFor(source, studioId: 2)) shelf.id: shelf};

    await shelves['movie:recent']!.load(1);
    await shelves['movie:upcoming']!.load(1);

    expect(source.movieCalls[0]['lte'], '2026-08-30', reason: 'released, not merely announced');
    expect(source.movieCalls[0]['gte'], isNull);
    expect(source.movieCalls[1]['gte'], '2026-08-30');
    expect(source.movieCalls[1]['lte'], isNull);
  });

  test('the best-rated row keeps out single-vote wonders', () async {
    final source = _RecordingSource();
    final shelves = {for (final shelf in shelvesFor(source, networkId: 213)) shelf.id: shelf};

    await shelves['tv:top']!.load(1);

    expect(source.tvCalls.single['votes'], seerrTopRatedVoteFloor);
    expect(source.tvCalls.single['sortBy'], 'vote_average.desc');
  });

  group('immer mal was Neues', () {
    test('keeps only what is on a server', () async {
      final source = _RecordingSource()
        ..pages = {
          1: CatalogPage(
            items: [
              _item('have-it', availability: CatalogAvailability.available),
              _item('part-of-it', availability: CatalogAvailability.partiallyAvailable),
              _item('not-mine'),
              _item('requested', availability: CatalogAvailability.unavailable),
            ],
            hasMore: true,
          ),
        };
      final shelves = {for (final shelf in shelvesFor(source, studioId: 2)) shelf.id: shelf};

      final page = await shelves['movie:available']!.load(1);

      expect(page.items.map((item) => item.title), ['have-it', 'part-of-it']);
    });

    test('reads further along the catalog on a later start', () async {
      final source = _RecordingSource();
      final shelves = {for (final shelf in shelvesFor(source, studioId: 2, rotation: 4)) shelf.id: shelf};

      await shelves['movie:available']!.load(1);

      expect(source.movieCalls.first['page'], 5, reason: 'the row starts somewhere else each time');
    });

    test('looks a few pages further when the first has nothing, then gives up', () async {
      final source = _RecordingSource()
        ..pages = {
          for (var page = 1; page <= 10; page++) page: CatalogPage(items: [_item('none')], hasMore: true),
        };
      final shelves = {for (final shelf in shelvesFor(source, studioId: 2)) shelf.id: shelf};

      final page = await shelves['movie:available']!.load(1);

      expect(page.items, isEmpty);
      expect(source.movieCalls, hasLength(seerrAvailableScanPages), reason: 'a courtesy row, not a search');
    });

    test('stops early when the catalog runs out', () async {
      final source = _RecordingSource()..pages = {1: const CatalogPage(items: [], hasMore: false)};
      final shelves = {for (final shelf in shelvesFor(source, studioId: 2)) shelf.id: shelf};

      await shelves['movie:available']!.load(1);

      expect(source.movieCalls, hasLength(1));
    });
  });
}
