import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/models/catalog/catalog_item.dart';
import 'package:plezy/screens/explore_screen.dart';
import 'package:plezy/services/catalog/catalog_source.dart';

/// Each title gets its own tmdb id: the identity a catalog item is keyed by,
/// and what the deduplication compares.
int _nextId = 1;

CatalogItem _title(String name, {String? backdropUrl}) => CatalogItem(
  source: CatalogSourceId.seerr,
  kind: MediaKind.movie,
  title: name,
  ids: CatalogItemIds(tmdb: _nextId++),
  posterUrl: 'https://image.tmdb.org/poster.jpg',
  backdropUrl: backdropUrl,
);

void main() {
  group('brandSpotlightTitleFrom', () {
    test('takes the first title that has wide artwork', () {
      final page = CatalogPage(
        items: [
          _title('No Backdrop'),
          _title('Wide One', backdropUrl: 'https://image.tmdb.org/wide.jpg'),
          _title('Wide Two', backdropUrl: 'https://image.tmdb.org/other.jpg'),
        ],
        hasMore: false,
      );

      expect(brandSpotlightTitleFrom(page)?.title, 'Wide One');
    });

    test('reads the backdrop where a catalog item actually keeps it', () {
      // The regression this exists for: a converted catalog item carries its
      // wide image in artPath and leaves the raw backdropPaths list null, so a
      // filter on that list matched nothing and the studio tile went on
      // showing its logo.
      final item = _title('Wide One', backdropUrl: 'https://image.tmdb.org/wide.jpg').toMediaItem();

      expect(item.backdropPaths, anyOf(isNull, isEmpty));
      expect(item.resolvedBackdropPaths, isNotEmpty);
    });

    test('skips a title another brand already shows', () {
      // Popularity order puts co-produced titles at the top of several brands,
      // and three tiles sharing one backdrop says nothing about any of them.
      final page = CatalogPage(
        items: [
          _title('Shared Hit', backdropUrl: 'https://image.tmdb.org/shared.jpg'),
          _title('Only Here', backdropUrl: 'https://image.tmdb.org/own.jpg'),
        ],
        hasMore: false,
      );
      final taken = {brandSpotlightTitleFrom(page)!.globalKey};

      expect(brandSpotlightTitleFrom(page)?.title, 'Shared Hit');
      expect(brandSpotlightTitleFrom(page, taken: taken)?.title, 'Only Here');
    });

    test('a brand with nothing left to itself yields nothing', () {
      final page = CatalogPage(
        items: [_title('Shared Hit', backdropUrl: 'https://image.tmdb.org/shared.jpg')],
        hasMore: false,
      );
      final taken = {brandSpotlightTitleFrom(page)!.globalKey};

      expect(brandSpotlightTitleFrom(page, taken: taken), isNull);
    });

    test('a page with no wide artwork at all yields nothing', () {
      final page = CatalogPage(items: [_title('One'), _title('Two')], hasMore: false);

      expect(brandSpotlightTitleFrom(page), isNull);
    });

    test('an empty page yields nothing', () {
      expect(brandSpotlightTitleFrom(const CatalogPage(items: [], hasMore: false)), isNull);
    });
  });
}
