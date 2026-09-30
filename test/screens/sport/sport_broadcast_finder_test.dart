import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/providers/iptv_sources_provider.dart';
import 'package:plezy/screens/sport/sport_broadcast_finder.dart';
import 'package:plezy/services/iptv/iptv_live_tv_source.dart';
import 'package:plezy/services/iptv/iptv_source.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/sport/sport_broadcast_matching.dart';
import 'package:plezy/services/sport/sport_models.dart';

import '../../test_helpers/multi_server_fixtures.dart';
import '../../test_helpers/prefs.dart';

/// From a playlist and an XMLTV guide, the way an IPTV provider serves them,
/// to the button in the match window.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(resetSharedPreferencesForTest);

  const playlist = '''
#EXTM3U
#EXTINF:-1 tvg-id="sky.bl1" group-title="DE • Sport • Bundesliga",Sky Bundesliga 1 HD
http://provider/stream/bl1
#EXTINF:-1 tvg-id="sky.bl2" group-title="DE • Sport • Bundesliga",Sky Bundesliga 2 HD
http://provider/stream/bl2
#EXTINF:-1 tvg-id="ard" group-title="DE • Vollprogramm",Das Erste HD
http://provider/stream/ard
''';

  // Half an hour from now, on the minute: the game is about to start.
  final now = DateTime.now().toUtc();
  final kickoff = DateTime.utc(now.year, now.month, now.day, now.hour, now.minute).add(const Duration(minutes: 30));

  String stamp(DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${at.year}${two(at.month)}${two(at.day)}${two(at.hour)}${two(at.minute)}00 +0000';
  }

  String guide({required bool withGame}) {
    final from = stamp(kickoff.subtract(const Duration(minutes: 30)));
    final to = stamp(kickoff.add(const Duration(hours: 2)));
    return '''
<tv>
  ${withGame ? '<programme start="$from" stop="$to" channel="sky.bl1"><title>Bundesliga</title><sub-title>Borussia Dortmund - Werder Bremen</sub-title></programme>' : ''}
  <programme start="$from" stop="$to" channel="sky.bl2"><title>Golf</title></programme>
  <programme start="$from" stop="$to" channel="ard"><title>Sportschau live</title><desc>Dortmund gegen Bremen, dazu das Wetter</desc></programme>
</tv>
''';
  }

  const dortmund = SportTeam(id: 7, name: 'Borussia Dortmund', shortName: 'Dortmund');
  const bremen = SportTeam(id: 134, name: 'SV Werder Bremen', shortName: 'Bremen');
  final match = SportMatch(
    id: 1,
    season: 2026,
    matchday: const SportMatchday(order: 7, name: '7. Spieltag'),
    kickoff: kickoff,
    home: dortmund,
    away: bremen,
    isFinished: false,
  );

  Future<SportBroadcastFinder> finderWith(String guideXml, {List<Uri>? requests}) async {
    final manager = MultiServerManager();
    final multiServer = testMultiServerProvider(manager);
    addTearDown(multiServer.dispose);
    final iptv = IptvSourcesProvider(
      profileId: 'profile-1',
      buildSource: (source) => IptvLiveTvSource(
        source,
        // Bytes, as a provider sends them: the playlist carries "•".
        httpClient: MockClient((request) async {
          requests?.add(request.url);
          return http.Response.bytes(utf8.encode(request.url.path.endsWith('.m3u') ? playlist : guideXml), 200);
        }),
      ),
    );
    addTearDown(iptv.dispose);
    await iptv.save(
      const IptvSource(
        id: 'src',
        name: 'Mein IPTV',
        kind: IptvSourceKind.m3u,
        playlistUrl: 'http://provider/list.m3u',
        epgUrls: ['http://provider/guide.xml'],
      ),
    );
    return SportBroadcastFinder(multiServer: multiServer, iptv: iptv);
  }

  test('finds the game named in a sub-title, on the channel that carries it', () async {
    final finder = await finderWith(guide(withGame: true));
    final search = (await finder.search(match, SportLeague.bundesliga1))!;

    expect(search.broadcasts, hasLength(1), reason: 'not the news programme that only mentions the pairing');
    final found = search.broadcasts.single;
    expect(found.kind, SportBroadcastKind.match);
    expect(found.channel.displayName, 'Sky Bundesliga 1 HD');
    expect(found.program?.subtitle, 'Borussia Dortmund - Werder Bremen');
    expect(search.leagueChannels, isEmpty);
    expect(search.channels, hasLength(3), reason: 'the whole list, for zapping in the player');
  });

  test('where the guide names nothing, offers the channels of the Bundesliga group', () async {
    final finder = await finderWith(guide(withGame: false));
    final search = (await finder.search(match, SportLeague.bundesliga1))!;

    expect(search.broadcasts, isEmpty);
    expect(search.leagueChannels.map((b) => b.channel.displayName), ['Sky Bundesliga 1 HD', 'Sky Bundesliga 2 HD']);
    expect(search.leagueChannels.last.program?.title, 'Golf', reason: 'with what is on there at the game');
  });

  test('without Live TV there is nothing to search', () async {
    final manager = MultiServerManager();
    final multiServer = testMultiServerProvider(manager);
    addTearDown(multiServer.dispose);
    final finder = SportBroadcastFinder(multiServer: multiServer);

    expect(await finder.search(match, SportLeague.bundesliga1), isNull);
  });

  test('a game weeks away finds nothing, without asking the provider', () async {
    final requests = <Uri>[];
    final finder = await finderWith(guide(withGame: true), requests: requests);
    final later = SportMatch(
      id: 2,
      season: 2026,
      matchday: const SportMatchday(order: 9, name: '9. Spieltag'),
      kickoff: kickoff.add(const Duration(days: 17)),
      home: dortmund,
      away: bremen,
      isFinished: false,
    );
    final before = requests.length;
    final search = await finder.search(later, SportLeague.bundesliga1);

    expect(search, isNotNull, reason: 'the window still says the game is not in the guide');
    expect(search!.isEmpty, isTrue);
    expect(requests, hasLength(before), reason: 'neither playlist nor guide is loaded for it');
  });

  test('only games within a week are worth searching', () {
    final at = DateTime.utc(2026, 10, 1);
    SportMatch at_(DateTime kickoff) => SportMatch(
      id: 1,
      season: 2026,
      matchday: const SportMatchday(order: 7, name: ''),
      kickoff: kickoff,
      home: dortmund,
      away: bremen,
      isFinished: false,
    );
    expect(SportBroadcastFinder.worthSearching(at_(at.add(const Duration(days: 2))), now: at), isTrue);
    expect(SportBroadcastFinder.worthSearching(at_(at.subtract(const Duration(days: 3))), now: at), isTrue);
    expect(SportBroadcastFinder.worthSearching(at_(at.add(const Duration(days: 20))), now: at), isFalse);
    expect(SportBroadcastFinder.worthSearching(at_(at.subtract(const Duration(days: 20))), now: at), isFalse);
  });
}
