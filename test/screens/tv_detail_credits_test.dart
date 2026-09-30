import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/screens/media_detail/tv_detail_credits.dart';

List<TvDetailCredit> credits({List<String>? directors, String? studio, List<String>? cast}) => tvDetailCredits(
  directorLabel: 'Director',
  directorsLabel: 'Directors',
  studioLabel: 'Studio',
  castLabel: 'Cast',
  directors: directors,
  studio: studio,
  cast: cast,
);

void main() {
  group('what the corner says', () {
    test('direction, studio and cast, in that order', () {
      final lines = credits(
        directors: ['Guy Ritchie'],
        studio: 'Netflix',
        cast: ['Theo James', 'Kaya Scodelario', 'Daniel Ings'],
      );

      expect(lines.map((line) => line.label), ['Director', 'Studio', 'Cast']);
      expect(lines.last.value, 'Theo James, Kaya Scodelario, Daniel Ings');
    });

    test('three names of the cast, however long the list', () {
      final lines = credits(cast: ['A', 'B', 'C', 'D', 'E']);

      expect(lines.single.value, 'A, B, C');
    });

    test('the label follows the count', () {
      expect(credits(directors: ['One']).single.label, 'Director');
      expect(credits(directors: ['One', 'Two']).single.label, 'Directors');
      // A third name would push the line onto two rows for no gain — the crew
      // list is a screen of its own.
      expect(credits(directors: ['One', 'Two', 'Three']).single.value, 'One, Two');
    });

    test('a field with nothing to say is left out, not printed empty', () {
      final lines = credits(directors: const [], studio: '   ', cast: ['Only Actor']);

      expect(lines.map((line) => line.label), ['Cast']);
    });

    test('nothing known at all draws nothing', () {
      expect(credits(), isEmpty);
    });

    test('a person credited twice is named once', () {
      // Both backends can list the same person under two credits, and a corner
      // that reads "Ritchie, Ritchie" looks broken.
      expect(credits(cast: ['Guy Ritchie', 'guy ritchie', 'Theo James']).single.value, 'Guy Ritchie, Theo James');
    });

    test('blank entries do not use up one of the three places', () {
      expect(credits(cast: ['', '  ', 'A', 'B', 'C']).single.value, 'A, B, C');
    });
  });
}
