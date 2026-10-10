import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/sport/sport_models.dart';

import '../../test_helpers/sport_fixtures.dart';

void main() {
  final kickoff = DateTime.utc(2026, 9, 19, 13, 30);
  final home = openLigaTeam(40, 'FC Bayern München');
  final away = openLigaTeam(134, 'Werder Bremen');

  Map<String, Object?> finishedMatch(int id, int day) => openLigaMatch(
    id: id,
    matchday: day,
    kickoffUtc: kickoff.subtract(Duration(days: 7 * (4 - day))),
    home: home,
    away: away,
    finished: true,
    result: (1, 0),
  );

  FakeOpenLigaDb provider() => FakeOpenLigaDb({
    '/getmatchdata/bl1': [openLigaMatch(id: 4, matchday: 4, kickoffUtc: kickoff, home: home, away: away)],
    '/getmatchdata/bl1/2026/3': [finishedMatch(3, 3)],
    '/getavailablegroups/bl1/2026': openLigaMatchdays(34),
    '/getbltable/bl1/2026': [openLigaTableRow(40, 'Bayern', points: 9)],
  });

  // A clock the test moves by hand, well before the fixture's kickoff so the
  // current matchday reads as upcoming.
  var now = DateTime.utc(2026, 9, 18, 12);
  setUp(() => now = DateTime.utc(2026, 9, 18, 12));
  T atNow<T>(T Function() body) => withClock(Clock(() => now), body);

  test('reads the season and the current matchday off the current fixtures', () async {
    final repo = provider().repository();
    final current = await atNow(() => repo.current(SportLeague.bundesliga1));

    expect(current!.season, 2026);
    expect(current.matchday, 4);
    expect(current.matches.single.id, 4);
  });

  test("takes the scores from the numbered matchday, not the provider's stale current answer", () async {
    // The provider kept its "current" answer for hours (seen on a Saturday
    // evening): a game long over still read as just begun there, while the
    // matchday asked for by number had the result.
    final api = FakeOpenLigaDb({
      '/getmatchdata/bl1': [openLigaMatch(id: 4, matchday: 4, kickoffUtc: kickoff, home: home, away: away)],
      '/getmatchdata/bl1/2026/4': [
        openLigaMatch(id: 4, matchday: 4, kickoffUtc: kickoff, home: home, away: away, finished: true, result: (2, 3)),
      ],
    });
    now = kickoff.add(const Duration(hours: 4));
    final current = await atNow(() => api.repository().current(SportLeague.bundesliga1));

    expect(current!.matchday, 4);
    expect(current.matches.single.isFinished, isTrue);
  });

  test('asks the provider once for as long as an answer is fresh', () async {
    final api = provider();
    final repo = api.repository();

    await atNow(() => repo.table(SportLeague.bundesliga1, 2026));
    await atNow(() => repo.table(SportLeague.bundesliga1, 2026));
    expect(api.countOf('/getbltable/bl1/2026'), 1);

    now = now.add(const Duration(minutes: 3));
    await atNow(() => repo.table(SportLeague.bundesliga1, 2026));
    expect(api.countOf('/getbltable/bl1/2026'), 2, reason: 'a table is kept two minutes');
  });

  test('keeps a finished matchday far longer than the table', () async {
    final api = provider();
    final repo = api.repository();

    await atNow(() => repo.matchday(SportLeague.bundesliga1, 2026, 3));
    now = now.add(const Duration(hours: 1));
    await atNow(() => repo.matchday(SportLeague.bundesliga1, 2026, 3));

    expect(api.countOf('/getmatchdata/bl1/2026/3'), 1);
  });

  test('two asks at once share one request', () async {
    final api = provider();
    final repo = api.repository();

    await atNow(
      () => Future.wait([repo.matchdays(SportLeague.bundesliga1, 2026), repo.matchdays(SportLeague.bundesliga1, 2026)]),
    );

    expect(api.countOf('/getavailablegroups/bl1/2026'), 1);
  });

  test('a failed fetch hands back what was kept, however old', () async {
    final api = provider();
    final repo = api.repository();

    final first = await atNow(() => repo.table(SportLeague.bundesliga1, 2026));
    api.failing.add('/getbltable/bl1/2026');
    now = now.add(const Duration(hours: 5));
    final second = await atNow(() => repo.table(SportLeague.bundesliga1, 2026));

    expect(api.countOf('/getbltable/bl1/2026'), 2, reason: 'it did try');
    expect(second, same(first));
  });

  test('answers null only when there was never anything', () async {
    final api = provider()..failing.add('/getbltable/bl1/2026');
    final repo = api.repository();

    expect(await atNow(() => repo.table(SportLeague.bundesliga1, 2026)), isNull);
  });

  test('invalidate sends the next ask to the network, for that league only', () async {
    final api = provider()..routes['/getbltable/bl2/2026'] = [openLigaTableRow(1, 'Hertha', points: 8)];
    final repo = api.repository();

    await atNow(() => repo.table(SportLeague.bundesliga1, 2026));
    await atNow(() => repo.table(SportLeague.bundesliga2, 2026));
    repo.invalidate(SportLeague.bundesliga1);
    await atNow(() => repo.table(SportLeague.bundesliga1, 2026));
    await atNow(() => repo.table(SportLeague.bundesliga2, 2026));

    expect(api.countOf('/getbltable/bl1/2026'), 2);
    expect(api.countOf('/getbltable/bl2/2026'), 1);
  });

  test('sends nothing about the viewer: league, season and matchday are the whole request', () async {
    final api = provider();
    final repo = api.repository();

    await atNow(() => repo.current(SportLeague.bundesliga1));
    await atNow(() => repo.matchday(SportLeague.bundesliga1, 2026, 3));

    for (final path in api.requests) {
      expect(path, matches(RegExp(r'^/(getmatchdata|getbltable|getavailablegroups)/bl[123](/\d{4}(/\d+)?)?$')));
    }
  });

  group('which matchday is current', () {
    // Matchday 4 is played on Saturday 19 and Sunday 20 September 2026, in
    // local time wherever the test runs; the Tuesday after is the 22nd.
    DateTime local(int day, [int hour = 0, int minute = 0]) => DateTime(2026, 9, day, hour, minute);

    Map<String, Object?> game(int id, DateTime kickoff, {bool finished = true}) => openLigaMatch(
      id: id,
      matchday: 4,
      kickoffUtc: kickoff.toUtc(),
      home: home,
      away: away,
      finished: finished,
      result: finished ? (1, 1) : null,
    );

    FakeOpenLigaDb weekend({bool sundayFinished = true, DateTime? rescheduled}) => FakeOpenLigaDb({
      '/getmatchdata/bl1': [
        game(41, local(19, 15, 30)),
        game(42, local(20, 17, 30), finished: sundayFinished),
        if (rescheduled != null) game(43, rescheduled, finished: false),
      ],
      '/getmatchdata/bl1/2026/5': [
        openLigaMatch(id: 51, matchday: 5, kickoffUtc: local(25, 20, 30).toUtc(), home: away, away: home),
      ],
      '/getavailablegroups/bl1/2026': openLigaMatchdays(34),
    });

    Future<int?> currentAt(FakeOpenLigaDb api, DateTime at) async {
      now = at;
      final current = await atNow(() => api.repository().current(SportLeague.bundesliga1));
      return current?.matchday;
    }

    test('a finished matchday stays current over Sunday and Monday', () async {
      expect(await currentAt(weekend(), local(20, 22)), 4);
      expect(await currentAt(weekend(), local(21, 23, 59)), 4);
    });

    test('from Tuesday the next matchday is current, with its own fixtures', () async {
      final api = weekend();
      now = local(22);
      final current = await atNow(() => api.repository().current(SportLeague.bundesliga1));

      expect(current!.matchday, 5);
      expect(current.matches.single.id, 51);
    });

    test('a matchday with a game still to come does not move on', () async {
      final api = weekend(sundayFinished: false);
      // Sunday's game kicks off in the future from here: nothing to move on from.
      expect(await currentAt(api, local(20, 12)), 4);
      expect(api.requests, isNot(contains('/getmatchdata/bl1/2026/5')));
    });

    test('a game made up after the next matchday has begun does not hold it', () async {
      final api = weekend(rescheduled: DateTime(2026, 11, 11, 18, 30));
      expect(await currentAt(api, local(22)), 5);
    });

    test('a late game before the next matchday holds it until it is played', () async {
      // The 3. Liga in September 2026: nine games at the weekend, the tenth
      // the Friday after, and the next matchday a fortnight off.
      final api = weekend(rescheduled: local(25, 19))
        ..routes['/getmatchdata/bl1/2026/5'] = [
          openLigaMatch(id: 51, matchday: 5, kickoffUtc: DateTime(2026, 10, 10, 14).toUtc(), home: away, away: home),
        ];
      expect(await currentAt(api, local(23)), 4, reason: 'Friday’s game is the next one there is');
      expect(await currentAt(api, DateTime(2026, 9, 28, 12)), 4, reason: 'over Sunday and Monday after it');
      expect(await currentAt(api, local(29)), 5, reason: 'and from the Tuesday after it, the next');
    });

    test('past the last matchday of the season the last one stays current', () async {
      final api = weekend()..routes.remove('/getmatchdata/bl1/2026/5');
      expect(await currentAt(api, local(23)), 4);
    });
  });
}
