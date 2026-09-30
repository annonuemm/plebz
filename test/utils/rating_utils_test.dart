import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_rating.dart';
import 'package:plezy/utils/rating_utils.dart';

void main() {
  setUpAll(() => LocaleSettings.setLocaleRaw('en'));

  group('ratingInfoForSource - Rotten Tomatoes', () {
    test('critic at or above the 60% tomatometer is fresh', () {
      final info = ratingInfoForSource('rottenTomatoesCritic', 6.0);
      expect(info!.assetPath, 'assets/rating_icons/rt_fresh.svg');
      expect(info.formattedValue, '60%');
    });

    test('critic below the tomatometer is rotten', () {
      final info = ratingInfoForSource('rottenTomatoesCritic', 5.9);
      expect(info!.assetPath, 'assets/rating_icons/rt_rotten.svg');
      expect(info.formattedValue, '59%');
    });

    test('audience uses the popcorn pair on the same threshold', () {
      expect(ratingInfoForSource('rottenTomatoesAudience', 6.0)!.assetPath, 'assets/rating_icons/rt_upright.svg');
      expect(ratingInfoForSource('rottenTomatoesAudience', 5.9)!.assetPath, 'assets/rating_icons/rt_spilled.svg');
    });

    test('the unsplit key follows the critic pair', () {
      expect(ratingInfoForSource('rottenTomatoes', 9.2)!.assetPath, 'assets/rating_icons/rt_fresh.svg');
    });

    test('percent rounds to a whole number', () {
      expect(ratingInfoForSource('rottenTomatoesCritic', 7.57)!.formattedValue, '76%');
    });
  });

  group('ratingInfoForSource - branded scales', () {
    test('IMDb keeps its 0-10 decimal', () {
      final info = ratingInfoForSource('imdb', 7.5);
      expect(info!.assetPath, 'assets/rating_icons/imdb.svg');
      expect(info.formattedValue, '7.5');
    });

    test('TMDB renders as a percentage', () {
      final info = ratingInfoForSource('tmdb', 6.8);
      expect(info!.assetPath, 'assets/rating_icons/tmdb.svg');
      expect(info.formattedValue, '68%');
    });
  });

  group('ratingInfoForSource - unbranded sources', () {
    test('sources without a logo get no badge so they stay label-only', () {
      for (final source in ['critic', 'audience', 'simkl', 'mal', 'anilist', 'trakt']) {
        expect(ratingInfoForSource(source, 8.0), isNull, reason: source);
      }
    });

    test('an unknown key gets no badge', () {
      expect(ratingInfoForSource('letterboxd', 8.0), isNull);
      expect(ratingInfoForSource('', 8.0), isNull);
    });
  });

  group('ratingSourceLabel', () {
    test('names every source the mappers can emit', () {
      const sources = [
        'critic',
        'audience',
        'imdb',
        'tmdb',
        'rottenTomatoes',
        'rottenTomatoesCritic',
        'rottenTomatoesAudience',
        'simkl',
        'mal',
        'anilist',
        'trakt',
      ];
      for (final source in sources) {
        expect(ratingSourceLabel(source), isNotEmpty, reason: source);
      }
    });

    test('keeps the Rotten Tomatoes panels distinguishable', () {
      expect(ratingSourceLabel('rottenTomatoesCritic'), isNot(ratingSourceLabel('rottenTomatoesAudience')));
    });

    test('returns null for an unknown key so it can be dropped rather than shown raw', () {
      expect(ratingSourceLabel('letterboxd'), isNull);
      expect(ratingSourceLabel(''), isNull);
    });

    test('the synthetic average is labelled, so it is announced like any source', () {
      expect(ratingSourceLabel(averageRatingSource), isNotEmpty);
    });
  });

  group('averagedRatings', () {
    test('collapses several scores to their mean on the shared 0-10 scale', () {
      // The four badges from a Plex movie: TMDB 79%, IMDb 7.4, RT 95%, RT
      // audience 96% — all stored as 0-10.
      final averaged = averagedRatings(const [
        MediaRatingSource(source: 'tmdb', value: 7.9),
        MediaRatingSource(source: 'imdb', value: 7.4),
        MediaRatingSource(source: 'rottenTomatoesCritic', value: 9.5),
        MediaRatingSource(source: 'rottenTomatoesAudience', value: 9.6),
      ]);

      expect(averaged, hasLength(1));
      expect(averaged.single.source, averageRatingSource);
      expect(averaged.single.value, closeTo(8.6, 0.001));
    });

    test('a single score is left exactly as it is', () {
      const only = [MediaRatingSource(source: 'imdb', value: 7.4)];

      expect(averagedRatings(only), same(only));
    });

    test('an empty list stays empty', () {
      expect(averagedRatings(const []), isEmpty);
    });

    test('drops vote counts rather than implying the mean carries them', () {
      final averaged = averagedRatings(const [
        MediaRatingSource(source: 'imdb', value: 8, votes: 1000),
        MediaRatingSource(source: 'tmdb', value: 6, votes: 50),
      ]);

      expect(averaged.single.value, 7);
      expect(averaged.single.votes, isNull);
    });

    test('the average carries no brand badge, so it renders with the neutral star', () {
      expect(ratingInfoForSource(averageRatingSource, 8.6), isNull);
    });
  });
}
