import 'package:flutter/material.dart' hide ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/screens/live_now/live_now_game_facts.dart';
import 'package:plezy/screens/live_now/live_now_loader.dart';
import 'package:plezy/screens/live_now/live_now_tile.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/sport/sport_models.dart';
import 'package:plezy/services/sport/sport_repository.dart';
import 'package:plezy/theme/mono_theme.dart';

SportTeam _team(int id) => SportTeam(id: id, name: 'Club $id', shortName: 'C$id');

SportMatch _match({int home = 4, int away = 12, String? stadium, String? city}) => SportMatch(
  id: 1,
  season: 2026,
  matchday: const SportMatchday(order: 7, name: '7. Spieltag'),
  kickoff: DateTime(2026, 10, 3, 15, 30),
  home: _team(home),
  away: _team(away),
  isFinished: false,
  stadium: stadium,
  city: city,
);

final _table = [
  for (var position = 1; position <= 18; position++)
    SportTableRow(
      position: position,
      team: _team(position),
      played: 7,
      won: 3,
      drawn: 1,
      lost: 3,
      goalsFor: 10,
      goalsAgainst: 10,
      points: 40 - position,
    ),
];

class _Repository extends SportRepository {
  @override
  Future<List<SportTableRow>?> table(SportLeague league, int season) async => _table;
}

void main() {
  List<int> positions(SportMatch match) => [for (final row in liveNowTableExcerpt(_table, match)) row.position];

  group('the table around a game', () {
    test('each club with its neighbours, in table order', () {
      expect(positions(_match(home: 12, away: 4)), [3, 4, 5, 11, 12, 13]);
    });

    test('clubs close together share their rows', () {
      expect(positions(_match(home: 4, away: 6)), [3, 4, 5, 6, 7]);
    });

    test('the top and the bottom of the table have one neighbour', () {
      expect(positions(_match(home: 1, away: 18)), [1, 2, 17, 18]);
    });

    test('a club the table does not know leaves the other', () {
      expect(positions(_match(home: 99)), [11, 12, 13]);
    });
  });

  group('the ground behind a game', () {
    const plain = Color(0xFF101010);

    test('each club on its side of the screen, top and bottom alike', () {
      final ground = liveNowGameGround(_match(home: 65, away: 81), plain)!;
      expect(ground.topLeft, ground.bottomLeft);
      expect(ground.topRight, ground.bottomRight);
      expect(ground.topLeft, isNot(plain));
    });

    test('a club without a colour leaves the plain ground on its side', () {
      final ground = liveNowGameGround(_match(home: 65, away: 2), plain)!;
      expect(ground.topRight, plain);
      expect(ground.topLeft, isNot(plain));
    });

    test('no colours at all, no ground of their own', () {
      expect(liveNowGameGround(_match(home: 1, away: 2), plain), isNull);
    });
  });

  group('where a game is played', () {
    test('stadium and city, the city only once', () {
      expect(liveNowGameVenue(_match(stadium: 'Waldstadion', city: 'Frankfurt')), 'Waldstadion, Frankfurt');
      expect(liveNowGameVenue(_match(stadium: 'Stadion Frankfurt', city: 'Frankfurt')), 'Stadion Frankfurt');
    });

    test('whatever is known, or nothing', () {
      expect(liveNowGameVenue(_match(city: 'Frankfurt')), 'Frankfurt');
      expect(liveNowGameVenue(_match(stadium: ' ', city: '')), isNull);
    });
  });

  group('the spotlight', () {
    final game = LiveNowGame(
      match: _match(stadium: 'Waldstadion', city: 'Frankfurt'),
      league: SportLeague.bundesliga1,
    );

    Future<void> pump(WidgetTester tester, {required String itemId}) async {
      final item = MediaItem(id: itemId, backend: MediaBackend.plex, kind: MediaKind.unknown);
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(MonoPalette.dark, variant: AppThemeVariant.glasV2),
          home: Scaffold(
            body: LiveNowScope(
              snapshot: LiveNowSnapshot(entries: [game]),
              child: Column(
                children: [
                  LiveNowGameLine(item: item, channelOf: (_) async => 'Sky Bundesliga 3'),
                  SizedBox(
                    width: 520,
                    child: LiveNowSpotlightFacts(item: item, repository: _Repository()),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    setUp(LiveNowGameLine.debugForget);

    testWidgets('a game names its channel and place on a line, the table beside it', (tester) async {
      await pump(tester, itemId: game.id);

      expect(find.text('Sky Bundesliga 3 · Waldstadion, Frankfurt'), findsOneWidget);
      expect(find.text('Club 4'), findsOneWidget);
      expect(find.text('Club 13'), findsOneWidget);
      expect(find.text('Club 8'), findsNothing);
    });

    testWidgets('anything else leaves the side empty', (tester) async {
      await pump(tester, itemId: 'live_now:channel:other');

      expect(find.textContaining('Waldstadion'), findsNothing);
      expect(find.text('Club 4'), findsNothing);
    });
  });
}
