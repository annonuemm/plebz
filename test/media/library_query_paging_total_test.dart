import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/library_query.dart';

/// A Plex hub it has not walked to the end answers with a sentinel total —
/// `offset + returned + 1` — which means "there is more" and nothing else. The
/// grid clamps its next request against the total it was given, so the
/// sentinel had it ask for a single title, and a View All crawled one at a
/// time after its first page.
void main() {
  group('pagingTotalFor', () {
    test('a full page claims room for another full one', () {
      // What Plex really said after page one of a long hub: 0 + 50 + 1.
      expect(pagingTotalFor(start: 0, returned: 50, requested: 50, reportedTotal: 51), 100);
    });

    test('and again on the page after that', () {
      expect(pagingTotalFor(start: 50, returned: 50, requested: 50, reportedTotal: 101), 150);
    });

    test('a short page is the end, exactly', () {
      expect(pagingTotalFor(start: 100, returned: 12, requested: 50, reportedTotal: 113), 112);
    });

    test('an honest total is kept where it is larger', () {
      // Jellyfin counts properly; nothing here may shrink that.
      expect(pagingTotalFor(start: 0, returned: 50, requested: 50, reportedTotal: 450), 450);
    });

    test('an empty page ends it without claiming a title that is not there', () {
      expect(pagingTotalFor(start: 150, returned: 0, requested: 50, reportedTotal: 151), 150);
    });
  });
}
