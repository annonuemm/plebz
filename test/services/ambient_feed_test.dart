import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plezy/services/ambient/ambient_feed.dart';
import 'package:plezy/services/home_rows.dart';
import 'package:plezy/services/program_reminders.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 10, 27, 19, 30);
  late HomeRows rows;
  late List<ProgramReminder> reminders;

  AmbientFeed feed() => AmbientFeed(
    channel: const MethodChannel('test/ambient'),
    rows: rows,
    reminderChanges: ChangeNotifier(),
    reminderSource: () => reminders,
    supported: true,
    debounce: Duration.zero,
  );

  ({Map<String, dynamic> json, Map<String, String> sources, String snapshot}) build() {
    final payload = feed().buildPayload(now: now);
    return (
      json: jsonDecode(payload.snapshot) as Map<String, dynamic>,
      sources: payload.sources,
      snapshot: payload.snapshot,
    );
  }

  List<Map<String, dynamic>> scenesOf(Map<String, dynamic> json, String kind) => [
    for (final scene in json['scenes'] as List)
      if ((scene as Map<String, dynamic>)['kind'] == kind) scene,
  ];

  setUpAll(() => initializeDateFormatting());

  setUp(() {
    rows = HomeRows(channel: const MethodChannel('test/home_rows'), supported: true, debounce: Duration.zero);
    reminders = [];
  });

  test('Continue Watching becomes a scene with its picture by key, never by address', () {
    rows.publish(HomeRows.continueRow, 'Continue Watching', [
      const HomeRowTile(
        id: 'plezy_srv_1',
        kind: 'episode',
        title: 'Severance',
        open: 'plebz://play?content_id=plezy_srv_1',
        facts: ['S2 E4', '41 min'],
        progress: 0.58,
        ambientImage: 'http://10.0.0.2:32400/photo?X-Plex-Token=secret',
      ),
    ]);

    final (:json, :sources, :snapshot) = build();
    final scene = scenesOf(json, 'continue').single;
    expect(scene['title'], 'Severance');
    expect(scene['subtitle'], 'S2 E4 · 41 min');
    expect(scene['progress'], 0.58);
    expect(scene['open'], 'plebz://play?content_id=plezy_srv_1');
    expect(sources[scene['image']], 'http://10.0.0.2:32400/photo?X-Plex-Token=secret');
    expect(snapshot, isNot(contains('secret')), reason: 'credentials stay in the app');
  });

  test('library titles need a wide picture and show once, whatever row they are in', () {
    rows.publish(HomeRows.continueRow, 'Continue Watching', [
      const HomeRowTile(id: 'a', kind: 'movie', title: 'Dune', open: 'plebz://open?content_id=a', ambientImage: 'u/a'),
    ]);
    rows.publish('${HomeRows.libraryRowPrefix}srv|1|recent', 'Recently Added', [
      const HomeRowTile(id: 'a', kind: 'movie', title: 'Dune', open: 'plebz://open?content_id=a', ambientImage: 'u/a'),
      const HomeRowTile(id: 'b', kind: 'movie', title: 'Past Lives', open: 'plebz://open?content_id=b'),
      const HomeRowTile(
        id: 'c',
        kind: 'movie',
        title: 'Oppenheimer',
        open: 'plebz://open?content_id=c',
        ambientImage: 'u/c',
      ),
    ]);
    rows.publish(HomeRows.watchlistRow, 'Watchlist', [
      const HomeRowTile(
        id: 'd',
        kind: 'movie',
        title: 'Perfect Days',
        open: 'plebz://open?content_id=d',
        ambientImage: 'u/d',
      ),
    ]);

    final library = scenesOf(build().json, 'library');
    // The watchlist row stands before the library's; the screensaver shuffles them anyway.
    expect(library.map((scene) => scene['title']), ['Perfect Days', 'Oppenheimer']);
    expect(library.first['kicker'], 'On your watchlist');
    expect(library.last['kicker'], 'From your library');
  });

  test('"new since yesterday" counts films and the series with something new since yesterday began', () {
    rows.publish('${HomeRows.libraryRowPrefix}srv|1|recent', 'Recently Added', [
      HomeRowTile(id: 'm1', kind: 'movie', title: 'One', open: 'x', addedAt: now.subtract(const Duration(hours: 3))),
      HomeRowTile(id: 'm2', kind: 'movie', title: 'Two', open: 'x', addedAt: now.subtract(const Duration(hours: 30))),
      HomeRowTile(id: 'e1', kind: 'episode', title: 'Show', open: 'x', addedAt: now.subtract(const Duration(hours: 1))),
      HomeRowTile(id: 'e2', kind: 'episode', title: 'Show', open: 'x', addedAt: now.subtract(const Duration(hours: 2))),
      HomeRowTile(id: 'old', kind: 'movie', title: 'Old', open: 'x', addedAt: now.subtract(const Duration(hours: 44))),
      HomeRowTile(id: 't1', kind: 'track', title: 'Song', open: 'x', addedAt: now.subtract(const Duration(hours: 1))),
    ]);

    final (:json, sources: _, snapshot: _) = build();
    final scene = scenesOf(json, 'new').single;
    expect(scene['title'], '2 films, new from 1 series');
    expect(scene['subtitle'], 'One · Two · Show');
    expect(scene['validUntil'], now.add(AmbientFeed.newValidFor).millisecondsSinceEpoch);
    expect((json['ticker'] as List).single['text'], 'New since yesterday: 2 films, new from 1 series');
  });

  test('today\'s games carry both clubs, and the strip names the kickoff', () {
    rows.publish(HomeRows.liveNowRow, 'Live now', [
      HomeRowTile(
        id: 'game:1',
        kind: 'game',
        title: 'Dortmund – Bremen',
        open: 'plebz://now?id=game:1',
        startsAt: DateTime(2026, 10, 27, 20, 30),
        live: false,
        home: const HomeRowTeam(name: 'Borussia Dortmund', colour: Color(0xFFF5D20A)),
        away: const HomeRowTeam(name: 'Werder Bremen', colour: Color(0xFF1D9A5B)),
      ),
      HomeRowTile(
        id: 'game:2',
        kind: 'game',
        title: 'Yesterday – Game',
        open: 'x',
        startsAt: DateTime(2026, 10, 26, 20, 30),
      ),
    ]);

    final (:json, sources: _, snapshot: _) = build();
    final scene = scenesOf(json, 'sport').single;
    expect(scene['title'], 'Dortmund – Bremen');
    expect(scene['subtitle'], startsWith('20:30'));
    expect((scene['home'] as Map)['colour'], '#F5D20A');
    expect(scene['endsAt'], DateTime(2026, 10, 27, 20, 30).add(AmbientFeed.gameLength).millisecondsSinceEpoch);
    expect((json['ticker'] as List).single, containsPair('time', '20:30'));
  });

  test('a reminder set for today becomes a scene that tunes its channel', () {
    reminders = [
      ProgramReminder(
        channelScopeKey: 'iptv|a|7',
        channelTitle: 'arte',
        title: 'Der Pate',
        beginsAt: DateTime(2026, 10, 27, 20, 15).millisecondsSinceEpoch ~/ 1000,
      ),
      ProgramReminder(
        channelScopeKey: 'iptv|a|7',
        channelTitle: 'arte',
        title: 'Tomorrow',
        beginsAt: DateTime(2026, 10, 28, 20, 15).millisecondsSinceEpoch ~/ 1000,
      ),
    ];

    final (:json, sources: _, snapshot: _) = build();
    final scene = scenesOf(json, 'tv').single;
    expect(scene['title'], 'Der Pate');
    expect(scene['subtitle'], '20:15 · arte');
    expect(scene['kicker'], 'Reminder set');
    expect(scene['open'], 'plebz://reminder?key=${Uri.encodeQueryComponent(reminders.first.key)}');
    expect((json['ticker'] as List).single['text'], 'Der Pate · arte');
  });

  test('the feed follows the rows and writes a changed snapshot once', () async {
    final calls = <MethodCall>[];
    const channel = MethodChannel('test/ambient');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
    );

    final ambient = feed()..start();
    addTearDown(ambient.debugReset);
    rows.publish(HomeRows.watchlistRow, 'Watchlist', [
      const HomeRowTile(id: 'd', kind: 'movie', title: 'Perfect Days', open: 'x', ambientImage: 'u/d'),
    ]);
    await Future<void>.delayed(Duration.zero);
    await ambient.flush();

    final publishes = calls.where((call) => call.method == 'publish').toList();
    expect(publishes, hasLength(1));
    expect((publishes.single.arguments as Map)['snapshot'], contains('Perfect Days'));
  });

  test('the paused title goes over in memory, and OK plays on', () async {
    final calls = <MethodCall>[];
    const channel = MethodChannel('test/ambient');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    var resumed = 0;
    final ambient = feed();
    ambient.setPaused(
      const AmbientPause(title: 'Dune', remaining: '1 h 12 min left', image: 'http://srv/art?X-Plex-Token=t'),
      onResume: () async => resumed++,
    );
    await Future<void>.delayed(Duration.zero);
    final paused = calls.singleWhere((call) => call.method == 'setPaused').arguments as Map;
    expect(paused['title'], 'Dune');
    expect(paused['kicker'], 'Paused');
    expect(paused['hint'], 'OK resumes');

    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(const MethodCall('resume')),
      (_) {},
    );
    expect(resumed, 1);

    ambient.setPaused(null);
    await Future<void>.delayed(Duration.zero);
    expect(calls.last.arguments, isNull);
  });
}
