import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/media/ultra_blur_colors.dart';
import 'package:plezy/models/livetv_channel.dart';
import 'package:plezy/models/livetv_program.dart';
import 'package:plezy/screens/live_now/live_now_loader.dart';
import 'package:plezy/services/home_rows.dart';
import 'package:plezy/services/settings_service.dart' show EpisodePosterMode;
import 'package:plezy/services/sport/sport_models.dart';

import '../test_helpers/media_items.dart';
import '../test_helpers/sport_fixtures.dart';

class _Client implements MediaServerClient {
  @override
  String thumbnailUrl(String? path, {int? width, int? height, bool cover = true}) =>
      'https://server.example/photo?url=$path&X-Plex-Token=secret';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/home_rows');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  HomeRows rows() => HomeRows(channel: channel, supported: true, debounce: Duration.zero);

  HomeRowTile tile(String id, {String? image}) =>
      HomeRowTile(id: id, kind: 'movie', title: id, image: image, open: 'plebz://watchlist');

  group('snapshot', () {
    test('rows stand in their fixed order, whatever order they arrive in', () {
      final home = rows()
        ..publish(HomeRows.recommendationsRow, 'Empfehlungen', [tile('r')])
        ..publish(HomeRows.liveNowRow, 'Jetzt live', [tile('l')])
        ..publish(HomeRows.continueRow, 'Weiterschauen', [tile('c')]);
      final snapshot = jsonDecode(home.buildPayload().snapshot) as Map<String, dynamic>;
      expect([for (final row in snapshot['rows'] as List) row['id']], ['live_now', 'continue', 'recommendations']);
      expect(snapshot['schema'], 1);
    });

    test('artwork goes over as a key; the address with its token stays behind', () {
      final home = rows()
        ..publish(HomeRows.continueRow, 'Weiterschauen', [
          tile('c', image: 'https://server.example/a.jpg?X-Plex-Token=secret'),
        ]);
      final payload = home.buildPayload();
      expect(payload.snapshot, isNot(contains('secret')));
      final image = ((jsonDecode(payload.snapshot)['rows'] as List).single['items'] as List).single['image'] as String;
      expect(image, startsWith('content://app.plebz.homerows/art/'));
      final key = image.split('/').last;
      expect(key, matches(RegExp(r'^[a-f0-9]{40}$')));
      expect(payload.sources[key], 'https://server.example/a.jpg?X-Plex-Token=secret');
    });

    test('library rows follow the fixed ones in the order they were given', () {
      final home = rows()
        ..publish('library:b', 'Neu in Serien', [tile('s')], order: 1)
        ..publish('library:a', 'Neu in Filmen', [tile('f')], order: 2)
        ..publish(HomeRows.continueRow, 'Weiterschauen', [tile('c')]);
      final snapshot = jsonDecode(home.buildPayload().snapshot) as Map<String, dynamic>;
      expect([for (final row in snapshot['rows'] as List) row['id']], ['continue', 'library:b', 'library:a']);
      expect(home.libraryRowIds, unorderedEquals(['library:a', 'library:b']));
    });

    test('an empty row is taken away', () {
      final home = rows()
        ..publish(HomeRows.watchlistRow, 'Merkliste', [tile('w')])
        ..publish(HomeRows.watchlistRow, 'Merkliste', const []);
      expect(jsonDecode(home.buildPayload().snapshot)['rows'], isEmpty);
    });

    test('the theme names the design and its colours', () {
      final home = rows()
        ..setTheme(const HomeRowsTheme(variant: 'glas', accent: Color(0xFF7FB2FF), background: Color(0xFF1A1A1C)));
      expect(jsonDecode(home.buildPayload().snapshot)['theme'], {
        'variant': 'glas',
        'accent': '#7FB2FF',
        'background': '#1A1A1C',
      });
    });

    test('the theme carries the ink when the app gives it', () {
      final home = rows()
        ..setTheme(
          const HomeRowsTheme(
            variant: 'flach',
            accent: Color(0xFFA866EE),
            background: Color(0xFF08070C),
            text: Color(0xFFF9FAFB),
            fullCards: true,
          ),
        );
      final theme = jsonDecode(home.buildPayload().snapshot)['theme'];
      expect(theme['text'], '#F9FAFB');
      expect(theme['fullCards'], isTrue);
    });
  });

  group('writing', () {
    test('writes once, and not again while nothing changed', () async {
      final home = rows()..publish(HomeRows.continueRow, 'Weiterschauen', [tile('c')]);
      await home.flush();
      await home.flush();
      expect(calls.where((call) => call.method == 'publish'), hasLength(1));
    });

    test('clear empties the snapshot on the Android side', () async {
      final home = rows()..publish(HomeRows.continueRow, 'Weiterschauen', [tile('c')]);
      await home.clear();
      expect(calls.map((call) => call.method), ['clear']);
      expect(jsonDecode(home.buildPayload().snapshot)['rows'], isEmpty);
    });

    test('off Android nothing is sent', () async {
      final home = HomeRows(channel: channel, supported: false, debounce: Duration.zero)
        ..publish(HomeRows.continueRow, 'Weiterschauen', [tile('c')]);
      await home.flush();
      await home.clear();
      expect(calls, isEmpty);
    });
  });

  group('library titles', () {
    test('Continue Watching plays on, with how far it has been watched', () {
      final item = testMediaItem(
        id: '42',
        kind: MediaKind.episode,
        title: 'Pilot',
        grandparentTitle: 'Severance',
        parentIndex: 1,
        index: 1,
        serverId: 'srv',
        thumbPath: '/library/metadata/42/thumb',
        durationMs: 1000,
        viewOffsetMs: 250,
      );
      final tile = homeRowTileForItem(item, client: _Client(), resume: true)!;
      expect(tile.open, 'plebz://play?content_id=plezy_srv_42');
      expect(
        homeRowTileForItem(item, client: _Client(), resume: true, openDetails: true)!.open,
        'plebz://open?content_id=plezy_srv_42',
        reason: 'the start page opens the title\'s page first',
      );
      expect(tile.title, 'Severance');
      expect(tile.subtitle, 'S1 E1 · Pilot');
      expect(tile.progress, 0.25);
      expect(tile.imageShape, HomeRowImageShape.landscape);
    });

    test('Continue Watching carries what the spotlight writes over it', () {
      final item = testMediaItem(
        id: '42',
        kind: MediaKind.episode,
        title: 'Pilot',
        grandparentTitle: 'Severance',
        parentIndex: 1,
        index: 1,
        serverId: 'srv',
        summary: '  Mark leads a team.  ',
        contentRating: 'de/16',
        rating: 7.6,
        thumbPath: '/library/metadata/42/thumb',
        grandparentThumbPath: '/library/metadata/1/thumb',
        grandparentArtPath: '/library/metadata/1/art',
        durationMs: 2460000,
        viewOffsetMs: 250,
      );
      final home = rows();
      final tile = homeRowTileForItem(
        item,
        client: _Client(),
        resume: true,
        posterMode: EpisodePosterMode.seriesPoster,
      )!;
      expect(tile.imageShape, HomeRowImageShape.poster, reason: 'the start page shows the series poster');
      expect(tile.image, contains('/library/metadata/1/thumb'));
      expect(tile.backdrop, contains('/library/metadata/1/art'));
      expect(tile.summary, 'Mark leads a team.');
      expect(tile.facts.first, 'S1 E1');
      expect(tile.facts.last, '★ 7.6');
      expect(tile.badge, isNotNull);

      home.publish(HomeRows.continueRow, 'Weiterschauen', [tile]);
      final payload = home.buildPayload();
      final json = (jsonDecode(payload.snapshot)['rows'] as List).single['items'].single as Map;
      expect(json['backdrop'], startsWith('content://app.plebz.homerows/art/'));
      expect(payload.sources.values, contains(contains('/library/metadata/1/art')));
      expect(json['facts'], tile.facts);
      expect(json['summary'], 'Mark leads a team.');
    });

    test('an unwatched episode keeps its story to itself when spoilers are hidden', () {
      final item = testMediaItem(
        id: '43',
        kind: MediaKind.episode,
        title: 'Half Loop',
        grandparentTitle: 'Severance',
        serverId: 'srv',
        summary: 'Everything happens.',
        thumbPath: '/library/metadata/43/thumb',
        artPath: '/library/metadata/43/art',
        grandparentArtPath: '/library/metadata/1/art',
        backdropPaths: const ['/library/metadata/43/still'],
        durationMs: 1000,
        viewOffsetMs: 100,
      );
      final tile = homeRowTileForItem(item, client: _Client(), resume: true, hideSpoilers: true)!;
      expect(tile.summary, isNull);
      expect(tile.backdrop, contains('/library/metadata/1/art'));
      expect(tile.image, contains('/library/metadata/1/art'), reason: 'the still would show the scene');
    });

    test('a poster tile carries no spotlight', () {
      final tile = homeRowTileForItem(
        testMediaItem(id: '7', title: 'Dune', serverId: 'srv', thumbPath: '/t', summary: 'Sand.'),
        client: _Client(),
      )!;
      expect(tile.backdrop, isNull);
      expect(tile.summary, isNull);
      expect(tile.facts, isEmpty);
    });

    test('a recommendation opens its page; a watchlist title no server has opens the watchlist', () {
      final library = testMediaItem(id: '7', title: 'Dune', serverId: 'srv', thumbPath: '/t');
      expect(homeRowTileForItem(library, client: _Client())!.open, 'plebz://open?content_id=plezy_srv_7');

      final catalog = testMediaItem(id: 'tmdb://1', title: 'Dune', thumbPath: 'https://images.example/dune.jpg');
      final tile = homeRowTileForItem(catalog, client: null)!;
      expect(tile.open, 'plebz://watchlist');
      expect(tile.image, 'https://images.example/dune.jpg');
      expect(homeRowTileForItem(catalog, client: null, resume: true), isNull, reason: 'nothing to play on');
    });
  });

  group('library shelves', () {
    MediaHub hub(String id, {String server = 'srv', String? library, int items = 1}) => MediaHub(
      id: id,
      title: 'Hub $id',
      type: 'movie',
      items: [for (var i = 0; i < items; i++) testMediaItem(id: '$id$i', title: 'T$i', serverId: server)],
      libraryId: library,
      serverId: server,
      serverName: 'Server $server',
    );

    test('every shelf but Continue Watching and empty ones, under an id that names where it comes from', () {
      final shelves = homeRowsLibraryShelves([
        hub('continueWatching'),
        hub('/hubs/sections/1/recentlyAdded', library: '1'),
        hub('/hubs/empty', items: 0),
      ]);
      expect([for (final shelf in shelves) shelf.id], ['library:srv|1|/hubs/sections/1/recentlyAdded']);
      expect(shelves.single.title, 'Hub /hubs/sections/1/recentlyAdded');
      expect(shelves.single.subtitle, isNull, reason: 'one server needs no name');
    });

    test('shelves from several servers name theirs', () {
      final shelves = homeRowsLibraryShelves([hub('a'), hub('b', server: 'other')]);
      expect([for (final shelf in shelves) shelf.subtitle], ['Server srv', 'Server other']);
    });
  });

  group('Jetzt live', () {
    test('a game carries both crests and opens what its tile opens', () {
      final now = DateTime.utc(2026, 10, 16, 18, 45);
      final match = SportMatch.fromJson(
        openLigaMatch(
          id: 9,
          matchday: 7,
          kickoffUtc: DateTime.utc(2026, 10, 16, 18, 30),
          home: openLigaTeam(1, 'FC Bayern München', shortName: 'Bayern', iconUrl: 'https://crests.example/fcb.png'),
          away: openLigaTeam(2, 'Borussia Dortmund', shortName: 'Dortmund', iconUrl: 'https://crests.example/bvb.png'),
        ),
      )!;
      final entry = LiveNowGame(match: match, league: SportLeague.bundesliga1);
      final tile = homeRowTileForLiveNow(entry, clientFor: (_) => null, now: now);
      expect(tile.kind, 'game');
      expect(tile.title, 'Bayern – Dortmund');
      expect(tile.home!.image, 'https://crests.example/fcb.png');
      expect(tile.live, isTrue);
      expect(tile.open, 'plebz://now?id=${Uri.encodeQueryComponent(entry.id)}');
    });

    test("a game carries the clubs' colours for the tile's ground", () {
      final match = SportMatch.fromJson(
        openLigaMatch(
          id: 10,
          matchday: 7,
          kickoffUtc: DateTime.utc(2026, 10, 16, 18, 30),
          home: openLigaTeam(40, 'FC Bayern München', shortName: 'Bayern'),
          away: openLigaTeam(999999, 'Unbekannt FC', shortName: 'Unbekannt'),
        ),
      )!;
      final tile = homeRowTileForLiveNow(
        LiveNowGame(match: match, league: SportLeague.bundesliga1),
        clientFor: (_) => null,
        now: DateTime.utc(2026, 10, 16, 12),
      );
      final json = tile.toJson((address) => address);
      expect((json['home'] as Map)['colour'], '#DC052D');
      expect((json['away'] as Map).containsKey('colour'), isFalse, reason: 'a club not listed keeps the plain ground');
    });

    test("a title carries Plex's corner colours when the app has them", () {
      final tile = homeRowTileForItem(
        testMediaItem(id: '7', title: 'Dune', serverId: 'srv', thumbPath: '/t'),
        client: _Client(),
        colours: const UltraBlurColors(
          topLeft: Color(0xFF112233),
          topRight: Color(0xFF445566),
          bottomRight: Color(0xFF778899),
          bottomLeft: Color(0xFFAABBCC),
        ),
      )!;
      expect(tile.toJson((address) => address)['colours'], ['#112233', '#445566', '#778899', '#AABBCC']);
    });

    test("a league's matchday: kickoff and date ahead, the score once it is over", () async {
      await initializeDateFormatting();
      final upcoming = SportMatch.fromJson(
        openLigaMatch(
          id: 20,
          matchday: 8,
          kickoffUtc: DateTime.utc(2026, 10, 25, 13, 30),
          home: openLigaTeam(40, 'FC Bayern München', shortName: 'Bayern'),
          away: openLigaTeam(87, 'Borussia Mönchengladbach', shortName: 'Gladbach'),
        ),
      )!;
      final tile = homeRowTileForMatch(upcoming, now: DateTime.utc(2026, 10, 20));
      expect(tile.kind, 'game');
      expect(tile.title, 'Bayern – Gladbach');
      expect(tile.score, isNull);
      expect(tile.subtitle, contains('25.10.'));
      expect(tile.open, 'plebz://sport');
      expect(tile.toJson((address) => address)['home']['colour'], '#DC052D');

      final line = homeRowsMatchdayLine(8, [upcoming]);
      expect(line, contains('8'));
      expect(line, contains('25'));
    });

    test('a row can say a word about itself and be the one to open on', () {
      final home = rows()
        ..publish(
          HomeRows.sportRow(SportLeague.bundesliga2),
          '2. Bundesliga',
          [tile('m')],
          subtitle: 'Spieltag 10',
          selected: true,
        )
        ..publish(HomeRows.sportRow(SportLeague.bundesliga1), '1. Bundesliga', [tile('n')], subtitle: 'Spieltag 8');
      final json = jsonDecode(home.buildPayload().snapshot)['rows'] as List;
      expect([for (final row in json) row['id']], ['sport:bl1', 'sport:bl2']);
      expect(json.last['subtitle'], 'Spieltag 10');
      expect(json.last['selected'], isTrue);
      expect((json.first as Map).containsKey('selected'), isFalse);
    });

    test('a channel shows what is on and how far it is', () {
      final now = DateTime.fromMillisecondsSinceEpoch(1500 * 1000);
      final entry = LiveNowChannel(
        channel: LiveTvChannel(key: 'ard', title: 'Das Erste', thumb: 'https://logos.example/ard.png'),
        program: LiveTvProgram(title: 'Tagesschau', beginsAt: 1000, endsAt: 2000),
      );
      final tile = homeRowTileForLiveNow(entry, clientFor: (_) => null, now: now);
      expect(tile.title, 'Tagesschau');
      expect(tile.subtitle, 'Das Erste');
      expect(tile.image, 'https://logos.example/ard.png');
      expect(tile.progress, 0.5);
    });
  });
}
