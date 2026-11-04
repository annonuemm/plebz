import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/sport/club_colours.dart';
import 'package:plezy/services/sport/sport_board.dart';
import 'package:plezy/services/sport/sport_models.dart';

/// The Sport page's stage and rows (Plebz): who stands on the stage, and how
/// a matchday breaks into rows.
void main() {
  final now = DateTime(2026, 11, 24, 20, 0);
  const day = SportMatchday(order: 5, name: '5. Spieltag');
  const bayern = SportTeam(id: 40, name: 'FC Bayern München', shortName: 'Bayern');
  const paris = SportTeam(id: 9001, name: 'Paris Saint-Germain', shortName: 'Paris');
  const hsv = SportTeam(id: 100, name: 'Hamburger SV', shortName: 'HSV');
  const gladbach = SportTeam(id: 87, name: 'Borussia Mönchengladbach', shortName: 'Gladbach');
  const madrid = SportTeam(id: 9002, name: 'Real Madrid', shortName: 'Madrid');
  const juventus = SportTeam(id: 9003, name: 'Juventus', shortName: 'Juventus');
  const liverpool = SportTeam(id: 9004, name: 'FC Liverpool', shortName: 'Liverpool');
  const psv = SportTeam(id: 9005, name: 'PSV Eindhoven', shortName: 'PSV');

  var nextId = 1;
  SportMatch game(SportTeam home, SportTeam away, DateTime kickoff, {bool finished = false}) => SportMatch(
    id: nextId++,
    season: 2026,
    matchday: day,
    kickoff: kickoff,
    home: home,
    away: away,
    isFinished: finished,
    result: finished ? const SportScore(2, 1) : null,
  );

  group('the stage', () {
    test('a game on now comes first, the favourite\'s before any other', () {
      final running = game(madrid, juventus, now.subtract(const Duration(minutes: 30)));
      final favourite = game(hsv, gladbach, now.subtract(const Duration(minutes: 10)));
      final later = game(bayern, paris, now.add(const Duration(hours: 1)));
      final games = [running, favourite, later];

      final plain = sportStageFor(games, league: .bundesliga1, favouriteClub: 0, now: now)!;
      expect(plain.match, running);
      expect(plain.reason, SportStageReason.live);

      final own = sportStageFor(games, league: .bundesliga1, favouriteClub: hsv.id, now: now)!;
      expect(own.match, favourite);
      expect(own.reason, SportStageReason.live);
    });

    test('of the games on now in a European cup, a German club\'s (Plebz)', () {
      final first = game(madrid, juventus, now.subtract(const Duration(minutes: 30)));
      final german = game(paris, bayern, now.subtract(const Duration(minutes: 30)));
      final pick = sportStageFor([first, german], league: .championsLeague, favouriteClub: 0, now: now)!;
      expect(pick.match, german);
      expect(pick.reason, SportStageReason.live);
    });

    test('with nothing on, the favourite\'s game, before kickoff and after the whistle', () {
      final played = game(hsv, gladbach, now.subtract(const Duration(days: 1)), finished: true);
      final next = game(bayern, paris, now.add(const Duration(hours: 1)));

      final pick = sportStageFor([played, next], league: .bundesliga1, favouriteClub: gladbach.id, now: now)!;
      expect(pick.match, played);
      expect(pick.reason, SportStageReason.favourite);
    });

    test('a European cup puts a German club\'s game before the next one', () {
      final first = game(madrid, juventus, now.add(const Duration(minutes: 45)));
      final german = game(bayern, paris, now.add(const Duration(hours: 1)));

      final cup = sportStageFor([first, german], league: .championsLeague, favouriteClub: 0, now: now)!;
      expect(cup.match, german);
      expect(cup.reason, SportStageReason.germanClub);

      final league = sportStageFor([first, german], league: .bundesliga1, favouriteClub: 0, now: now)!;
      expect(league.match, first, reason: 'a German league has only German clubs');
      expect(league.reason, SportStageReason.next);
    });

    test('with every game over, the first; with none, nothing', () {
      final played = game(madrid, juventus, now.subtract(const Duration(days: 1)), finished: true);
      final pick = sportStageFor([played], league: .championsLeague, favouriteClub: 0, now: now)!;
      expect(pick.match, played);
      expect(pick.reason, SportStageReason.finished);
      expect(sportStageFor(const [], league: .bundesliga1, favouriteClub: 0, now: now), isNull);
    });
  });

  group('the rows', () {
    test('a league\'s by day, whatever the kickoffs', () {
      final saturday = DateTime(2026, 11, 7);
      final games = [
        game(bayern, hsv, saturday.add(const Duration(hours: 15, minutes: 30))),
        game(gladbach, paris, saturday.add(const Duration(hours: 18, minutes: 30))),
        game(madrid, juventus, saturday.add(const Duration(days: 1, hours: 15, minutes: 30))),
      ];
      final rows = sportBoardRows(games, league: .bundesliga1);
      expect(rows.map((row) => row.kind), [SportBoardRowKind.day, SportBoardRowKind.day]);
      expect(rows.first.matches, hasLength(2));
    });

    test('a European cup\'s German clubs first, then each kickoff of a day', () {
      final tuesday = DateTime(2026, 11, 24);
      final early = game(madrid, juventus, tuesday.add(const Duration(hours: 18, minutes: 45)));
      final german = game(bayern, paris, tuesday.add(const Duration(hours: 21)));
      final late = game(liverpool, psv, tuesday.add(const Duration(hours: 21)));
      final rows = sportBoardRows([early, german, late], league: .championsLeague);

      expect(rows.map((row) => row.kind), [
        SportBoardRowKind.germanClubs,
        SportBoardRowKind.kickoff,
        SportBoardRowKind.kickoff,
      ]);
      expect(rows[0].matches, [german]);
      expect(rows[1].matches, [early]);
      expect(rows[2].matches, [german, late]);
      expect(rows[2].sameDayAs(rows[1]), isTrue, reason: 'the second kickoff of a day leaves its date out');
      expect(rows[1].sameDayAs(rows[0]), isFalse, reason: 'after the German clubs\' row the date stands again');
    });

    test('a cup day with one kickoff is one row', () {
      final evening = DateTime(2026, 12, 1, 20, 45);
      final rows = sportBoardRows([game(hsv, gladbach, evening), game(bayern, paris, evening)], league: .dfbPokal);
      expect(rows.map((row) => row.kind), [SportBoardRowKind.day]);
    });
  });

  group('the European clubs\' colours (Plebz)', () {
    SportTeam team(String name, String short) => SportTeam(id: 99000 + name.length, name: name, shortName: short);

    test('found by name, in German as the provider writes them', () {
      expect(clubColourFor(team('Inter Mailand', 'Inter')), isNotNull);
      expect(clubColourFor(team('Galatasaray Istanbul', 'Galatasaray')), isNotNull);
      expect(clubColourFor(team('Atlético Madrid', 'Atlético')), clubColourFor(team('Atletico Madrid', 'Atletico')));
    });

    test('Villarreal is not Aston Villa, and black and white stays plain', () {
      expect(clubColourFor(team('Villarreal CF', 'Villarreal')), isNot(clubColourFor(team('Aston Villa', 'Villa'))));
      expect(clubColourFor(team('Real Madrid', 'Madrid')), isNull);
      expect(clubColourFor(team('Juventus Turin', 'Juventus')), isNull);
    });

    test('a German club is known by its id, and only that makes it German', () {
      expect(isGermanClub(team('Inter Mailand', 'Inter')), isFalse);
      expect(isGermanClub(const SportTeam(id: 40, name: 'FC Bayern München', shortName: 'Bayern')), isTrue);
    });
  });
}
