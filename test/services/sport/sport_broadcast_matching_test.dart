import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/models/livetv_channel.dart';
import 'package:plezy/models/livetv_program.dart';
import 'package:plezy/services/sport/sport_broadcast_matching.dart';
import 'package:plezy/services/sport/sport_models.dart';

void main() {
  final kickoff = DateTime.utc(2026, 10, 10, 13, 30);
  int epoch(DateTime at) => at.millisecondsSinceEpoch ~/ 1000;

  const dortmund = SportTeam(id: 7, name: 'Borussia Dortmund', shortName: 'Dortmund');
  const bremen = SportTeam(id: 134, name: 'SV Werder Bremen', shortName: 'Bremen');
  const gladbach = SportTeam(id: 87, name: 'Borussia Mönchengladbach', shortName: 'Gladbach');
  const koeln = SportTeam(id: 65, name: '1. FC Köln', shortName: 'Köln');

  SportMatch game(SportTeam home, SportTeam away) => SportMatch(
    id: 1,
    season: 2026,
    matchday: const SportMatchday(order: 7, name: '7. Spieltag'),
    kickoff: kickoff,
    home: home,
    away: away,
    isFinished: false,
  );

  LiveTvChannel channel(String key, {String? title, String? group, String? identifier, String? number}) =>
      LiveTvChannel(
        key: key,
        title: title ?? key,
        identifier: identifier,
        lineup: group,
        number: number,
        serverId: 'iptv',
      );

  LiveTvProgram program(
    String channelId,
    String title, {
    String? subtitle,
    String? summary,
    List<String>? genres,
    Duration from = const Duration(minutes: -30),
    Duration length = const Duration(hours: 2, minutes: 30),
  }) => LiveTvProgram(
    title: title,
    subtitle: subtitle,
    summary: summary,
    genres: genres,
    beginsAt: epoch(kickoff.add(from)),
    endsAt: epoch(kickoff.add(from).add(length)),
    channelIdentifier: channelId,
    serverId: 'iptv',
  );

  List<SportBroadcast> find(
    SportMatch match,
    List<LiveTvChannel> channels,
    List<LiveTvProgram> programs, {
    SportLeague league = SportLeague.bundesliga1,
  }) => findSportBroadcasts(match: match, league: league, channels: channels, programs: programs);

  group('sportFold', () {
    test('meets every way of writing an umlaut', () {
      expect(sportFold('Köln'), sportFold('Koeln'));
      expect(sportFold('Köln'), sportFold('Koln'));
      expect(sportFold('Borussia Mönchengladbach'), sportFold('BORUSSIA MOENCHENGLADBACH'));
      expect(sportFold('Fürth'), sportFold('Fuerth'));
    });

    test('turns punctuation into single spaces', () {
      expect(sportFold('Bundesliga: Dortmund – Bremen (7. Spieltag)'), 'bundesliga dortmund bremen 7 spieltag');
    });
  });

  test('a club answers to its names, its words and a known abbreviation, not to a shared word', () {
    final tokens = sportTeamTokens(dortmund);
    expect(tokens, containsAll(['borussia dortmund', 'dortmund', 'bvb']));
    expect(tokens, isNot(contains('borussia')), reason: 'Dortmund and Gladbach both answer to it');
  });

  group('findSportBroadcasts', () {
    final sky = channel('sky-bl1', title: 'Sky Sport Bundesliga 1');

    test('finds the pairing in the title', () {
      final found = find(game(dortmund, bremen), [sky], [program('sky-bl1', 'Borussia Dortmund - Werder Bremen')]);
      expect(found.single.channel.key, 'sky-bl1');
      expect(found.single.kind, SportBroadcastKind.match);
    });

    test('finds it in the sub-title under a title that only names the competition', () {
      final found = find(game(dortmund, bremen), [sky], [program('sky-bl1', 'Bundesliga', subtitle: 'BVB – Werder')]);
      expect(found.single.kind, SportBroadcastKind.match);
    });

    test('meets a guide that writes the umlaut out', () {
      final found = find(game(gladbach, koeln), [sky], [program('sky-bl1', 'Moenchengladbach - Koeln')]);
      expect(found, hasLength(1));
    });

    test('takes neither the build-up that ends at kickoff nor the analysis after', () {
      final found = find(
        game(dortmund, bremen),
        [sky],
        [
          program(
            'sky-bl1',
            'Dortmund – Bremen: Vorbericht',
            from: const Duration(hours: -1),
            length: const Duration(hours: 1),
          ),
          program(
            'sky-bl1',
            'Dortmund – Bremen: Analyse',
            from: const Duration(hours: 2),
            length: const Duration(hours: 1),
          ),
        ],
      );
      expect(found, isEmpty);
    });

    test('does not take another game at the same time', () {
      final found = find(game(dortmund, bremen), [sky], [program('sky-bl1', 'Borussia Mönchengladbach - 1. FC Köln')]);
      expect(found, isEmpty);
    });

    test('reads the description only of a programme that is football', () {
      final match = game(dortmund, bremen);
      final football = find(
        match,
        [sky],
        [
          program('sky-bl1', 'Live', summary: 'Borussia Dortmund empfängt Werder Bremen.', genres: ['Fußball']),
        ],
      );
      expect(football, hasLength(1));

      final news = find(
        match,
        [channel('news', title: 'Nachrichten 24')],
        [program('news', 'Am Nachmittag', summary: 'Heute: Dortmund gegen Bremen und das Wetter.')],
      );
      expect(news, isEmpty);
    });

    test('a Konferenz of the league counts, after the game itself', () {
      final other = channel('sky-conf', title: 'Sky Sport Bundesliga');
      final found = find(
        game(dortmund, bremen),
        [sky, other],
        [program('sky-conf', 'Bundesliga: Die Konferenz'), program('sky-bl1', 'Borussia Dortmund - Werder Bremen')],
      );
      expect(found.map((b) => b.kind), [SportBroadcastKind.match, SportBroadcastKind.conference]);
    });

    test('a Konferenz of another league does not', () {
      final conference = [program('sky-bl1', '2. Bundesliga: Die Konferenz')];
      expect(find(game(dortmund, bremen), [sky], conference), isEmpty);
      expect(find(game(dortmund, bremen), [sky], conference, league: SportLeague.bundesliga2), hasLength(1));
    });

    test('a Konferenz that names no league takes the channel\'s', () {
      final found = find(game(dortmund, bremen), [sky], [program('sky-bl1', 'Die Konferenz')]);
      expect(found.single.kind, SportBroadcastKind.conference);
      expect(
        find(game(dortmund, bremen), [sky], [program('sky-bl1', 'Die Konferenz')], league: SportLeague.liga3),
        isEmpty,
      );
    });

    test('a station in several qualities is offered once, in the viewer\'s first copy', () {
      final copies = [
        channel('raw', title: 'Sky Bundesliga 1 RAW', identifier: 'sky.bl1'),
        channel('fhd', title: 'Sky Bundesliga 1 FHD', identifier: 'sky.bl1'),
        channel('hd', title: 'Sky Bundesliga 1 HD', identifier: 'sky.bl1'),
      ];
      final found = find(game(dortmund, bremen), copies, [program('sky.bl1', 'Borussia Dortmund - Werder Bremen')]);
      expect(found.single.channel.key, 'raw');
    });
  });

  group('sportLeagueChannels', () {
    test('a Bundesliga group serves both Bundesligen but not the 3. Liga', () {
      final channels = [
        channel('news', title: 'Nachrichten', group: 'DE • News'),
        channel('b1', title: 'Sky Bundesliga 1', group: 'DE • Sport • Bundesliga'),
        channel('m1', title: 'Magenta Sport 1', group: 'DE • 3. Liga'),
      ];
      List<String> keys(SportLeague league) => sportLeagueChannels(
        match: game(dortmund, bremen),
        league: league,
        channels: channels,
        programs: const [],
      ).map((b) => b.channel.key).toList();

      expect(keys(SportLeague.bundesliga1), ['b1']);
      expect(keys(SportLeague.bundesliga2), ['b1']);
      expect(keys(SportLeague.liga3), ['m1']);
    });

    test('knows the broadcasters by name, whatever the playlist puts around it', () {
      Set<SportLeague> leagues(String name) => sportBroadcasterLeagues(name);
      const bundesligen = {SportLeague.bundesliga1, SportLeague.bundesliga2};

      expect(leagues('Sky Sport Top Event'), bundesligen);
      expect(leagues('DE: SKY SPORT MIX FHD'), bundesligen);
      expect(leagues('Sky Sport Bundesliga 4 HD'), bundesligen);
      expect(leagues('Sky Bundesliga 1'), bundesligen, reason: 'the name Sky used before 2021');
      expect(leagues('DAZN 1 HD'), {SportLeague.bundesliga1});
      expect(leagues('DE: DAZN2'), {SportLeague.bundesliga1});
      expect(leagues('MagentaSport 2'), {SportLeague.liga3});
      expect(leagues('Magenta Sport 3. Liga 1 FHD'), {SportLeague.liga3});
    });

    test('but not their channels for news, other sports or other countries', () {
      for (final name in [
        'Sky Sport News HD',
        'Sky Sport Tennis',
        'Sky Sport Austria 1',
        'UK: Sky Sports Mix',
        'MagentaSport Eishockey',
        'MagentaSport Frauen-Bundesliga',
        'DAZN LaLiga',
        'Sky Cinema Action',
        'Skyline TV',
      ]) {
        expect(sportBroadcasterLeagues(name), isEmpty, reason: name);
      }
    });

    test('offers the broadcasters after the group and the named channels, each for its own league', () {
      final channels = [
        channel('dazn', title: 'DAZN 1 HD', group: 'DE • Sport'),
        channel('magenta', title: 'MagentaSport 2', group: 'DE • Sport'),
        channel('event', title: 'Sky Sport Top Event', group: 'DE • Sport'),
        channel('named', title: 'Sky Sport Bundesliga 3', group: 'DE • Sport'),
        channel('b1', title: 'Sky Bundesliga 1', group: 'Sport • Bundesliga'),
        channel('news', title: 'Sky Sport News', group: 'DE • Sport'),
      ];
      List<String> keys(SportLeague league) => sportLeagueChannels(
        match: game(dortmund, bremen),
        league: league,
        channels: channels,
        programs: const [],
      ).map((b) => b.channel.key).toList();

      expect(keys(SportLeague.bundesliga1), ['b1', 'named', 'dazn', 'event']);
      expect(keys(SportLeague.bundesliga2), ['b1', 'named', 'event'], reason: 'DAZN has no 2. Bundesliga');
      expect(keys(SportLeague.liga3), ['magenta']);
    });

    test('the group first, then channels whose own name says it, each with what is on at the game', () {
      final channels = [
        channel('solo', title: 'Sky Sport Bundesliga 3', group: 'DE • Sport'),
        channel('b1', title: 'Sky Bundesliga 1', group: 'Sport • Bundesliga'),
      ];
      final found = sportLeagueChannels(
        match: game(dortmund, bremen),
        league: SportLeague.bundesliga1,
        channels: channels,
        programs: [program('b1', 'Fußball live')],
      );
      expect(found.map((b) => b.channel.key), ['b1', 'solo']);
      expect(found.first.program?.title, 'Fußball live');
      expect(found.last.program, isNull);
      expect(found.every((b) => b.kind == SportBroadcastKind.leagueChannel), isTrue);
    });
  });
}
