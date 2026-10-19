import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/services/sport/sport_league_names.dart';
import 'package:plezy/services/sport/sport_models.dart';

import '../../test_helpers/sport_fixtures.dart';

void main() {
  group('SportLeagueLayout', () {
    test('by default the German leagues are on show and the cups wait to be switched on', () {
      final layout = SportLeagueLayout.decode('');
      expect(layout.order, SportLeague.values);
      expect(layout.visible, [SportLeague.bundesliga1, SportLeague.bundesliga2, SportLeague.liga3]);
      expect(layout.isHidden(SportLeague.championsLeague), isTrue);
      expect(layout.isHidden(SportLeague.dfbPokal), isTrue);
    });

    test('keeps the viewer\'s order and choice through a round trip', () {
      final layout = SportLeagueLayout.decode('')
          .withOrder([
            SportLeague.championsLeague,
            SportLeague.bundesliga1,
            SportLeague.dfbPokal,
            SportLeague.bundesliga2,
            SportLeague.liga3,
            SportLeague.europaLeague,
          ])
          .withHidden(SportLeague.championsLeague, false)
          .withHidden(SportLeague.liga3, true);
      final again = SportLeagueLayout.decode(layout.encode());
      expect(again.visible, [SportLeague.championsLeague, SportLeague.bundesliga1, SportLeague.bundesliga2]);
      expect(again.order, layout.order);
    });

    test('a competition the stored order does not know goes to the end, by its default', () {
      final layout = SportLeagueLayout.decode('bl2,-bl1,unknown,bl3');
      expect(layout.order.take(3), [SportLeague.bundesliga2, SportLeague.bundesliga1, SportLeague.liga3]);
      expect(layout.order.skip(3), [SportLeague.championsLeague, SportLeague.europaLeague, SportLeague.dfbPokal]);
      expect(layout.visible, [SportLeague.bundesliga2, SportLeague.liga3]);
    });

    test('the last competition on show cannot be hidden', () {
      var layout = SportLeagueLayout.decode('bl1,-bl2,-bl3');
      expect(layout.visible, [SportLeague.bundesliga1]);
      layout = layout.withHidden(SportLeague.bundesliga1, true);
      expect(layout.visible, [SportLeague.bundesliga1]);
      expect(SportLeagueLayout.decode('-bl1,-bl2,-bl3').visible, [SportLeague.bundesliga1]);
    });
  });

  group('sportMatchdayLabel', () {
    test('a league counts its matchdays', () {
      expect(sportMatchdayLabel(SportLeague.bundesliga1, 4, name: '4. Spieltag'), t.sport.matchday(n: 4));
    });

    test('a European cup\'s league phase is counted too, however the provider spaces it', () {
      expect(sportMatchdayLabel(SportLeague.championsLeague, 3, name: '3.Spieltag'), t.sport.matchday(n: 3));
    });

    test('a knock-out round goes by its own name', () {
      expect(
        sportMatchdayLabel(SportLeague.championsLeague, 10, name: 'Achtelfinale Hinspiele'),
        'Achtelfinale Hinspiele',
      );
      expect(sportMatchdayLabel(SportLeague.dfbPokal, 2, name: '2. Runde'), '2. Runde');
    });
  });

  group('a cup tie\'s result', () {
    final home = openLigaTeam(1, 'Eintracht Frankfurt');
    final away = openLigaTeam(2, 'Borussia Dortmund');

    test('after extra time is the score shown, and says so', () {
      final match = SportMatch.fromJson(
        openLigaMatch(
          id: 1,
          matchday: 2,
          groupName: '2. Runde',
          kickoffUtc: DateTime.utc(2025, 10, 28, 17),
          home: home,
          away: away,
          finished: true,
          result: (2, 2),
          extraTime: (2, 4),
        ),
      )!;
      expect(match.result, const SportScore(2, 4));
      expect(match.afterExtraTime, isTrue);
      expect(match.penalties, isNull);
    });

    test('a shoot-out is kept beside the score after extra time', () {
      final match = SportMatch.fromJson(
        openLigaMatch(
          id: 2,
          matchday: 2,
          groupName: '2. Runde',
          kickoffUtc: DateTime.utc(2025, 10, 28, 17),
          home: home,
          away: away,
          finished: true,
          result: (1, 1),
          extraTime: (1, 1),
          penalties: (3, 5),
        ),
      )!;
      expect(match.result, const SportScore(1, 1));
      expect(match.penalties, const SportScore(3, 5));
      expect(match.matchday.name, '2. Runde');
    });

    test('a league match has neither', () {
      final match = SportMatch.fromJson(
        openLigaMatch(
          id: 3,
          matchday: 4,
          kickoffUtc: DateTime.utc(2026, 9, 19, 13, 30),
          home: home,
          away: away,
          finished: true,
          result: (2, 1),
        ),
      )!;
      expect(match.afterExtraTime, isFalse);
      expect(match.penalties, isNull);
    });
  });
}
