import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/sport/sport_models.dart';

import '../../test_helpers/sport_fixtures.dart';

void main() {
  final bayern = openLigaTeam(
    40,
    'FC Bayern München',
    shortName: 'Bayern',
    iconUrl: 'https://upload.wikimedia.org/b.svg',
  );
  final bremen = openLigaTeam(134, 'Werder Bremen', shortName: 'Bremen');

  group('SportMatch.fromJson', () {
    test('reads a finished fixture with its results, goals and ground', () {
      final match = SportMatch.fromJson(
        openLigaMatch(
          id: 77001,
          matchday: 4,
          kickoffUtc: DateTime.utc(2026, 9, 19, 13, 30),
          home: bayern,
          away: bremen,
          finished: true,
          halftime: (1, 0),
          result: (2, 1),
          goals: [
            // Out of order on purpose: the provider does not promise any.
            openLigaGoal(home: 2, away: 1, minute: 88, scorer: 'Kane', penalty: true),
            openLigaGoal(home: 1, away: 0, minute: 12, scorer: 'Musiala'),
            openLigaGoal(home: 1, away: 1, minute: 61, scorer: 'Upamecano', ownGoal: true),
          ],
          stadium: 'Allianz Arena',
          city: 'München',
          spectators: 75000,
        ),
      )!;

      expect(match.id, 77001);
      expect(match.season, 2026);
      expect(match.matchday.order, 4);
      expect(match.home.shortName, 'Bayern');
      expect(match.home.iconUrl, isNotNull);
      expect(match.away.iconUrl, isNull);
      expect(match.isFinished, isTrue);
      expect(match.halftime, const SportScore(1, 0));
      expect(match.result, const SportScore(2, 1));
      expect(match.goals.map((g) => g.minute), [12, 61, 88], reason: 'in the order the score grew');
      expect(match.goals.last.isPenalty, isTrue);
      expect(match.goals[1].isOwnGoal, isTrue);
      expect(match.stadium, 'Allianz Arena');
      expect(match.city, 'München');
      expect(match.spectators, 75000);
    });

    test('takes the kickoff from the UTC field, not from Germany\'s clock', () {
      final kickoff = DateTime.utc(2026, 9, 19, 13, 30);
      final match = SportMatch.fromJson(
        openLigaMatch(id: 1, matchday: 4, kickoffUtc: kickoff, home: bayern, away: bremen),
      )!;

      expect(match.kickoff.isUtc, isFalse);
      expect(match.kickoff.toUtc(), kickoff);
    });

    test('drops a fixture it cannot place rather than inventing one', () {
      final broken = openLigaMatch(id: 1, matchday: 4, kickoffUtc: DateTime.utc(2026), home: bayern, away: bremen)
        ..['team2'] = null;
      expect(SportMatch.fromJson(broken), isNull);
    });

    test('no ground and no crowd read as unknown, not as zero', () {
      final match = SportMatch.fromJson(
        openLigaMatch(id: 1, matchday: 4, kickoffUtc: DateTime.utc(2026), home: bayern, away: bremen, spectators: 0),
      )!;
      expect(match.stadium, isNull);
      expect(match.city, isNull);
      expect(match.spectators, isNull);
    });
  });

  group('SportMatch state', () {
    SportMatch fixture({bool finished = false, List<Map<String, Object?>> goals = const [], (int, int)? result}) =>
        SportMatch.fromJson(
          openLigaMatch(
            id: 1,
            matchday: 4,
            kickoffUtc: DateTime.utc(2026, 9, 19, 13, 30),
            home: bayern,
            away: bremen,
            finished: finished,
            goals: goals,
            result: result,
          ),
        )!;

    final kickoff = DateTime.utc(2026, 9, 19, 13, 30).toLocal();

    test('is live from the whistle until the provider says it is over', () {
      final match = fixture();
      expect(match.isLive(kickoff.subtract(const Duration(minutes: 1))), isFalse);
      expect(match.isLive(kickoff), isTrue);
      expect(match.isLive(kickoff.add(const Duration(minutes: 95))), isTrue);
      expect(fixture(finished: true).isLive(kickoff.add(const Duration(minutes: 95))), isFalse);
    });

    test('a provider that stopped updating does not keep a match live all night', () {
      expect(fixture().isLive(kickoff.add(const Duration(hours: 3))), isFalse);
    });

    test('has no score before kickoff and 0:0 once it is under way', () {
      final match = fixture();
      expect(match.scoreAt(kickoff.subtract(const Duration(hours: 1))), isNull);
      expect(match.scoreAt(kickoff.add(const Duration(minutes: 5))), const SportScore(0, 0));
    });

    test('adds a running score up from the goals, and prefers the official one', () {
      final running = fixture(goals: [openLigaGoal(home: 0, away: 1, minute: 30)]);
      expect(running.scoreAt(kickoff.add(const Duration(minutes: 40))), const SportScore(0, 1));

      final official = fixture(finished: true, result: (0, 2), goals: [openLigaGoal(home: 0, away: 1, minute: 30)]);
      expect(official.scoreAt(kickoff.add(const Duration(hours: 5))), const SportScore(0, 2));
    });
  });

  test('a goal belongs to the side whose score it changed, own goals included', () {
    // Bremen's defender turns it in: the goal is Bayern's, and the scorer's
    // club would have said Bremen.
    final ownGoal = SportGoal.fromJson(openLigaGoal(home: 1, away: 0, scorer: 'Friedl', ownGoal: true))!;
    expect(ownGoal.scoredByHome(const SportScore(0, 0)), isTrue);

    final away = SportGoal.fromJson(openLigaGoal(home: 1, away: 1))!;
    expect(away.scoredByHome(const SportScore(1, 0)), isFalse);
  });

  group('crestUrl', () {
    test('turns an SVG original into a PNG thumbnail at a width Wikimedia serves', () {
      expect(
        crestUrl('https://upload.wikimedia.org/wikipedia/commons/9/9e/Logo_Mainz_05.svg'),
        'https://upload.wikimedia.org/wikipedia/commons/thumb/9/9e/Logo_Mainz_05.svg/${crestThumbnailWidth}px-Logo_Mainz_05.svg.png',
      );
    });

    test('keeps a language wiki and encodes each name exactly once', () {
      expect(
        crestUrl('https://upload.wikimedia.org/wikipedia/de/f/ff/1._FC_Saarbr%C3%BCcken.svg'),
        'https://upload.wikimedia.org/wikipedia/de/thumb/f/ff/1._FC_Saarbr%C3%BCcken.svg/'
        '${crestThumbnailWidth}px-1._FC_Saarbr%C3%BCcken.svg.png',
      );
      // The provider sends some names raw; they come out encoded the same way.
      expect(
        crestUrl('https://upload.wikimedia.org/wikipedia/commons/f/fa/1._FC_Nürnberg_logo.svg'),
        contains('/1._FC_N%C3%BCrnberg_logo.svg/${crestThumbnailWidth}px-1._FC_N%C3%BCrnberg_logo.svg.png'),
      );
    });

    test('a raster original becomes a thumbnail of the same format', () {
      expect(
        crestUrl('https://upload.wikimedia.org/wikipedia/commons/9/97/FC_Schalke_04_Logo.png'),
        'https://upload.wikimedia.org/wikipedia/commons/thumb/9/97/FC_Schalke_04_Logo.png/${crestThumbnailWidth}px-FC_Schalke_04_Logo.png',
      );
    });

    test('an existing thumbnail is moved to the standard width, its tracking query dropped', () {
      expect(
        crestUrl(
          'https://upload.wikimedia.org/wikipedia/commons/thumb/8/8f/F.C._Hansa_Rostock_Logo.svg/960px-F.C._Hansa_Rostock_Logo.svg.png'
          '?utm_source=de.wikipedia.org&utm_campaign=parser',
        ),
        'https://upload.wikimedia.org/wikipedia/commons/thumb/8/8f/F.C._Hansa_Rostock_Logo.svg/${crestThumbnailWidth}px-F.C._Hansa_Rostock_Logo.svg.png',
      );
    });

    test('leaves every other host alone', () {
      for (final url in [
        'https://i.imgur.com/r3mvi0h.png',
        'https://assets.dfb.de/uploads/000/018/232/small_union-Berlin.jpg',
      ]) {
        expect(crestUrl(url), url);
      }
    });

    test('a club parsed from the provider carries the rewritten crest', () {
      final team = SportTeam.fromJson(
        openLigaTeam(40, 'FC Bayern München', iconUrl: 'https://upload.wikimedia.org/wikipedia/commons/1/1f/Logo.svg'),
      )!;
      expect(team.iconUrl, endsWith('/thumb/1/1f/Logo.svg/${crestThumbnailWidth}px-Logo.svg.png'));
    });
  });

  group('SportTableRow.listFromJson', () {
    test('numbers the rows in the order they arrive and reads the club off teamInfoId', () {
      final rows = SportTableRow.listFromJson([
        openLigaTableRow(40, 'Bayern', points: 12, goals: 14, opponentGoals: 3),
        openLigaTableRow(134, 'Bremen', points: 7, goals: 5, opponentGoals: 9),
      ]);

      expect(rows.map((r) => r.position), [1, 2]);
      expect(rows.first.team.id, 40);
      expect(rows.first.goalDifference, 11);
      expect(rows.last.goalDifference, -4);
      expect(rows.last.points, 7);
    });

    test('anything but a list is an empty table', () {
      expect(SportTableRow.listFromJson({'error': 'nope'}), isEmpty);
    });
  });
}
