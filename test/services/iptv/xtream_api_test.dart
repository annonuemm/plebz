import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/models/livetv_channel.dart';
import 'package:plezy/services/iptv/iptv_source.dart';
import 'package:plezy/services/iptv/iptv_catchup.dart';
import 'package:plezy/services/iptv/xtream_api.dart';

const _api = XtreamApi(baseUrl: 'http://panel.example.com:8080', username: 'user', password: 'pass');

LiveTvChannel _channel({String? identifier = 'das-erste.de'}) =>
    LiveTvChannel(key: 'iptv:s:1', identifier: identifier, title: 'Das Erste', serverId: 's', serverName: 'Panel');

void main() {
  group('XtreamApi', () {
    test('carries the credentials on every call', () {
      for (final uri in [_api.userInfo(), _api.liveCategories(), _api.liveStreams(), _api.shortEpg('42')]) {
        expect(uri.queryParameters['username'], 'user', reason: '$uri');
        expect(uri.queryParameters['password'], 'pass', reason: '$uri');
        expect(uri.path, '/player_api.php');
      }
    });

    test('names the action the panel expects', () {
      expect(_api.liveCategories().queryParameters['action'], 'get_live_categories');
      expect(_api.liveStreams().queryParameters['action'], 'get_live_streams');
      expect(_api.shortEpg('42').queryParameters['action'], 'get_short_epg');
      expect(_api.shortEpg('42').queryParameters['stream_id'], '42');
      expect(_api.userInfo().queryParameters.containsKey('action'), isFalse);
    });

    test('builds the stream URL in the container the source asked for', () {
      // Panels serve both, but not all of them serve both well — which is why
      // this is a per-source choice and not a constant.
      expect(_api.liveStreamUrl('42').toString(), 'http://panel.example.com:8080/live/user/pass/42.ts');

      const hls = XtreamApi(
        baseUrl: 'http://panel.example.com:8080',
        username: 'user',
        password: 'pass',
        streamFormat: IptvStreamFormat.hls,
      );
      expect(hls.liveStreamUrl('42').toString(), 'http://panel.example.com:8080/live/user/pass/42.m3u8');
    });

    test('a base URL with trailing slashes still joins cleanly', () {
      const trailing = XtreamApi(baseUrl: 'http://panel.example.com:8080///', username: 'u', password: 'p');

      expect(trailing.liveStreamUrl('7').toString(), 'http://panel.example.com:8080/live/u/p/7.ts');
      expect(trailing.liveStreams().path, '/player_api.php');
    });
  });

  group('channelsFromXtream', () {
    test('maps a live stream row onto a channel', () {
      final channels = channelsFromXtream(
        [
          {
            'num': 1,
            'name': 'Das Erste HD',
            'stream_id': 1234,
            'stream_icon': 'http://logo/ard.png',
            'epg_channel_id': 'das-erste.de',
            'category_id': '5',
          },
        ],
        sourceId: 'source-1',
        sourceName: 'Panel',
        categoryNames: const {'5': 'Vollprogramm'},
      );

      final channel = channels.single;
      expect(channel.key, 'iptv:source-1:1234');
      expect(channel.title, 'Das Erste HD');
      expect(channel.number, '1');
      expect(channel.thumb, 'http://logo/ard.png');
      expect(channel.identifier, 'das-erste.de');
      expect(channel.lineup, 'Vollprogramm');
      expect(channel.serverName, 'Panel');
    });

    test('a numeric stream id sent as a string works the same', () {
      final channels = channelsFromXtream(
        [
          {'stream_id': '1234', 'name': 'A'},
        ],
        sourceId: 's',
        sourceName: 'S',
      );

      expect(channels.single.key, 'iptv:s:1234');
    });

    test('rows without a stream id are dropped', () {
      final channels = channelsFromXtream(
        [
          {'name': 'No id'},
          'garbage',
          {'stream_id': 7, 'name': 'Good'},
        ],
        sourceId: 's',
        sourceName: 'S',
      );

      expect(channels, hasLength(1));
      expect(channels.single.title, 'Good');
    });

    test('an unknown category leaves the group empty rather than showing its id', () {
      final channels = channelsFromXtream(
        [
          {'stream_id': 1, 'name': 'A', 'category_id': '99'},
        ],
        sourceId: 's',
        sourceName: 'S',
        categoryNames: const {'5': 'Sport'},
      );

      expect(channels.single.lineup, isNull);
    });
  });

  group('categoriesFromXtream', () {
    test('reduces the rows to id and name', () {
      expect(
        categoriesFromXtream([
          {'category_id': '1', 'category_name': 'Sport'},
          {'category_id': '2', 'category_name': 'News'},
          {'category_name': 'No id'},
        ]),
        {'1': 'Sport', '2': 'News'},
      );
    });
  });

  group('programsFromXtreamEpg', () {
    String b64(String value) => base64.encode(utf8.encode(value));

    test('decodes the base64 text and keeps the slot', () {
      final programs = programsFromXtreamEpg([
        {
          'title': b64('Tagesschau'),
          'description': b64('Nachrichten für Deutschland'),
          'start_timestamp': 1714852500,
          'stop_timestamp': 1714853400,
        },
      ], channel: _channel());

      final program = programs.single;
      expect(program.title, 'Tagesschau');
      expect(program.summary, 'Nachrichten für Deutschland');
      expect(program.beginsAt, 1714852500);
      expect(program.endsAt, 1714853400);
      expect(program.channelIdentifier, 'das-erste.de');
    });

    test('plain text that is not base64 survives untouched', () {
      final programs = programsFromXtreamEpg([
        {'title': 'Tagesschau', 'start_timestamp': 100, 'stop_timestamp': 200},
      ], channel: _channel());

      expect(programs.single.title, 'Tagesschau');
    });

    test('falls back to the formatted times when timestamps are missing', () {
      final programs = programsFromXtreamEpg([
        {'title': 'A', 'start': '2024-05-04 20:15:00', 'end': '2024-05-04 21:45:00'},
      ], channel: _channel());

      expect(programs.single.beginsAt, DateTime.parse('2024-05-04T20:15:00').millisecondsSinceEpoch ~/ 1000);
    });

    test('a row with no readable slot is dropped, since a guide cannot place it', () {
      final programs = programsFromXtreamEpg([
        {'title': 'No time'},
        {'title': 'Good', 'start_timestamp': 100, 'stop_timestamp': 200},
      ], channel: _channel());

      expect(programs, hasLength(1));
      expect(programs.single.title, 'Good');
    });

    test('programmes come back in chronological order', () {
      final programs = programsFromXtreamEpg([
        {'title': 'Later', 'start_timestamp': 500, 'stop_timestamp': 600},
        {'title': 'Earlier', 'start_timestamp': 100, 'stop_timestamp': 200},
      ], channel: _channel());

      expect(programs.map((p) => p.title), ['Earlier', 'Later']);
    });
  });

  group('archive rows', () {
    test('a reported window becomes the channel\'s', () {
      final channels = channelsFromXtream(
        [
          {'stream_id': 1, 'name': 'ARD', 'tv_archive': 1, 'tv_archive_duration': 7},
        ],
        sourceId: 's',
        sourceName: 'S',
      );

      expect(channels.single.catchupDays, 7);
    });

    test('the flag alone still says there is an archive', () {
      final channels = channelsFromXtream(
        [
          {'stream_id': 1, 'name': 'ARD', 'tv_archive': '1'},
        ],
        sourceId: 's',
        sourceName: 'S',
      );

      expect(channels.single.catchupDays, 1);
    });

    test('a channel without an archive has no window', () {
      final channels = channelsFromXtream(
        [
          {'stream_id': 1, 'name': 'ARD', 'tv_archive': 0},
        ],
        sourceId: 's',
        sourceName: 'S',
      );

      expect(channels.single.catchupDays, isNull);
    });

    test('off overrules a panel that reports one', () {
      final channels = channelsFromXtream(
        [
          {'stream_id': 1, 'name': 'ARD', 'tv_archive': 1, 'tv_archive_duration': 7},
        ],
        sourceId: 's',
        sourceName: 'S',
        catchupMode: IptvCatchupMode.off,
      );

      expect(channels.single.catchupDays, isNull);
    });
  });
}
