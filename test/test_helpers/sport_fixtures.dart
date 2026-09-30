import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/services/sport/openligadb_client.dart';
import 'package:plezy/services/sport/sport_repository.dart';

/// OpenLigaDB payloads in the shape the live API returns them — field names,
/// nesting and the quirks included (a table row names its club `teamInfoId`,
/// a fixture names it `teamId`; `location` may be null).

Map<String, Object?> openLigaTeam(int id, String name, {String? shortName, String? iconUrl}) => {
  'teamId': id,
  'teamName': name,
  'shortName': shortName ?? name,
  'teamIconUrl': iconUrl,
  'teamGroupName': null,
};

Map<String, Object?> openLigaGoal({
  required int home,
  required int away,
  int? minute,
  String? scorer,
  bool ownGoal = false,
  bool penalty = false,
}) => {
  'goalID': home * 10 + away,
  'scoreTeam1': home,
  'scoreTeam2': away,
  'matchMinute': minute,
  'goalGetterID': 1,
  'goalGetterName': scorer,
  'isPenalty': penalty,
  'isOwnGoal': ownGoal,
  'isOvertime': false,
  'comment': null,
};

Map<String, Object?> openLigaMatch({
  required int id,
  required int matchday,
  required DateTime kickoffUtc,
  required Map<String, Object?> home,
  required Map<String, Object?> away,
  int season = 2026,
  bool finished = false,
  (int, int)? halftime,
  (int, int)? result,
  List<Map<String, Object?>> goals = const [],
  String? stadium,
  String? city,
  int? spectators,
}) => {
  'matchID': id,
  'matchDateTime': kickoffUtc.add(const Duration(hours: 2)).toIso8601String().replaceFirst('Z', ''),
  'timeZoneID': 'W. Europe Standard Time',
  'leagueId': 5000,
  'leagueName': '1. Fußball-Bundesliga 2026/2027',
  'leagueSeason': season,
  'leagueShortcut': 'bl1',
  'matchDateTimeUTC': kickoffUtc.toUtc().toIso8601String(),
  'group': {'groupName': '$matchday. Spieltag', 'groupOrderID': matchday, 'groupID': 50000 + matchday},
  'team1': home,
  'team2': away,
  'lastUpdateDateTime': null,
  'matchIsFinished': finished,
  'matchResults': [
    if (halftime != null)
      {
        'resultID': 1,
        'resultName': 'Halbzeit',
        'pointsTeam1': halftime.$1,
        'pointsTeam2': halftime.$2,
        'resultOrderID': 1,
        'resultTypeID': 1,
        'resultDescription': 'Ergebnis zur Halbzeit',
      },
    if (result != null)
      {
        'resultID': 2,
        'resultName': 'Endergebnis',
        'pointsTeam1': result.$1,
        'pointsTeam2': result.$2,
        'resultOrderID': 2,
        'resultTypeID': 2,
        'resultDescription': 'Ergebnis nach Ende der offiziellen Spielzeit',
      },
  ],
  'goals': goals,
  'location': stadium == null && city == null
      ? null
      : {'locationID': 1, 'locationCity': city, 'locationStadium': stadium},
  'numberOfViewers': spectators,
};

Map<String, Object?> openLigaTableRow(
  int id,
  String name, {
  required int points,
  int matches = 4,
  int won = 0,
  int draw = 0,
  int lost = 0,
  int goals = 0,
  int opponentGoals = 0,
}) => {
  'teamInfoId': id,
  'teamName': name,
  'shortName': name,
  'teamIconUrl': null,
  'points': points,
  'opponentGoals': opponentGoals,
  'goals': goals,
  'matches': matches,
  'won': won,
  'lost': lost,
  'draw': draw,
  'goalDiff': goals - opponentGoals,
};

List<Map<String, Object?>> openLigaMatchdays(int count) => [
  for (var i = 1; i <= count; i++) {'groupName': '$i. Spieltag', 'groupOrderID': i, 'groupID': 50000 + i},
];

/// A stand-in for api.openligadb.de that answers from [routes], keyed by path
/// ("/getbltable/bl1/2026"), and records every path it was asked for.
///
/// A path with no route answers 404, which the client reads as "unknown".
class FakeOpenLigaDb {
  FakeOpenLigaDb(this.routes);

  final Map<String, Object?> routes;
  final List<String> requests = [];

  /// Paths that answer 500 instead of their route, for the failure paths.
  final Set<String> failing = {};

  late final http.Client client = MockClient((request) async {
    final path = request.url.path;
    requests.add(path);
    if (failing.contains(path)) return http.Response('boom', 500);
    if (!routes.containsKey(path)) return http.Response('not found', 404);
    // As bytes, the way the server sends them: UTF-8, so a club called
    // "München" arrives as the client will really see it.
    return http.Response.bytes(
      utf8.encode(jsonEncode(routes[path])),
      200,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
  });

  SportRepository repository() => SportRepository(client: OpenLigaDbClient(httpClient: client));

  int countOf(String path) => requests.where((p) => p == path).length;
}
