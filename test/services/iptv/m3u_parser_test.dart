import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/iptv/iptv_catchup.dart';
import 'package:plezy/services/iptv/m3u_parser.dart';

void main() {
  group('parseM3u', () {
    test('reads the attributes and the display name of an entry', () {
      final entries = parseM3u('''
#EXTM3U
#EXTINF:-1 tvg-id="das-erste.de" tvg-name="Das Erste HD" tvg-logo="http://logo/ard.png" group-title="Vollprogramm",Das Erste HD
http://provider/stream/1
''');

      expect(entries, hasLength(1));
      final entry = entries.single;
      expect(entry.url, 'http://provider/stream/1');
      expect(entry.name, 'Das Erste HD');
      expect(entry.tvgId, 'das-erste.de');
      expect(entry.tvgName, 'Das Erste HD');
      expect(entry.logo, 'http://logo/ard.png');
      expect(entry.group, 'Vollprogramm');
    });

    test('a comma inside the title does not truncate the name', () {
      final entries = parseM3u('''
#EXTINF:-1 tvg-id="sport1",Sport, Live und mehr
http://provider/stream/2
''');

      expect(entries.single.name, 'Sport, Live und mehr');
    });

    test('directives between the entry and its URL are stepped over', () {
      // Providers routinely emit per-entry player options.
      final entries = parseM3u('''
#EXTINF:-1 tvg-id="a",Channel A
#EXTVLCOPT:http-user-agent=Mozilla
#EXTGRP:News
http://provider/stream/a
''');

      expect(entries.single.url, 'http://provider/stream/a');
      expect(entries.single.group, 'News', reason: '#EXTGRP applies to the entry that follows it');
    });

    test('an explicit group-title beats the older #EXTGRP directive', () {
      final entries = parseM3u('''
#EXTINF:-1 group-title="Sport",Channel A
#EXTGRP:News
http://provider/stream/a
''');

      expect(entries.single.group, 'Sport');
    });

    test('attribute casing varies between providers', () {
      final entries = parseM3u('''
#EXTINF:-1 TVG-ID="a" TVG-LOGO="http://logo/a.png",Channel A
http://provider/stream/a
''');

      expect(entries.single.tvgId, 'a');
      expect(entries.single.logo, 'http://logo/a.png');
    });

    test('an entry without a URL is dropped rather than half-read', () {
      final entries = parseM3u('''
#EXTINF:-1 tvg-id="a",Channel A
#EXTINF:-1 tvg-id="b",Channel B
http://provider/stream/b
''');

      expect(entries, hasLength(1));
      expect(entries.single.tvgId, 'b', reason: 'the dangling entry must not steal the next URL');
    });

    test('a URL with no entry line before it is ignored', () {
      expect(parseM3u('#EXTM3U\nhttp://provider/orphan\n'), isEmpty);
    });

    test('an entry with no attributes still yields its name and URL', () {
      final entries = parseM3u('#EXTINF:-1,Plain Channel\nhttp://provider/plain\n');

      expect(entries.single.name, 'Plain Channel');
      expect(entries.single.tvgId, isNull);
    });

    test('falls back to tvg-name, then the URL, when the title is empty', () {
      expect(parseM3u('#EXTINF:-1 tvg-name="From Attr",\nhttp://p/1\n').single.name, 'From Attr');
      expect(parseM3u('#EXTINF:-1,\nhttp://p/2\n').single.name, 'http://p/2');
    });

    test('blank lines and carriage returns are tolerated', () {
      final entries = parseM3u('#EXTM3U\r\n\r\n#EXTINF:-1,Channel A\r\nhttp://p/a\r\n');

      expect(entries.single.url, 'http://p/a');
      expect(entries.single.name, 'Channel A');
    });

    test('a user agent and referer the provider insists on are carried along', () {
      final entries = parseM3u('''
#EXTINF:-1 tvg-id="a",Channel A
#EXTVLCOPT:http-user-agent=Mozilla/5.0 (SmartTV)
#EXTVLCOPT:http-referrer=http://provider/
#EXTVLCOPT:network-caching=1000
http://provider/stream/a
''');

      expect(entries.single.headers, {'User-Agent': 'Mozilla/5.0 (SmartTV)', 'Referer': 'http://provider/'});
    });

    test('headers do not leak from one entry to the next', () {
      final entries = parseM3u('''
#EXTINF:-1,Channel A
#EXTVLCOPT:http-user-agent=Mozilla
http://provider/stream/a
#EXTINF:-1,Channel B
http://provider/stream/b
''');

      expect(entries[0].headers, {'User-Agent': 'Mozilla'});
      expect(entries[1].headers, isEmpty);
    });

    test('headers appended to the URL are split off it', () {
      final entries = parseM3u('''
#EXTINF:-1,Channel A
http://provider/stream/a|User-Agent=VLC%2F3.0&Referer=http://provider/
''');

      expect(entries.single.url, 'http://provider/stream/a');
      expect(entries.single.headers, {'User-Agent': 'VLC/3.0', 'Referer': 'http://provider/'});
    });

    test('a URL header wins over the entry directive', () {
      final entries = parseM3u('''
#EXTINF:-1,Channel A
#EXTVLCOPT:http-user-agent=Mozilla
http://provider/stream/a|User-Agent=VLC
''');

      expect(entries.single.headers['User-Agent'], 'VLC');
    });

    test('an empty playlist is empty, not an error', () {
      expect(parseM3u(''), isEmpty);
      expect(parseM3u('#EXTM3U\n'), isEmpty);
    });
  });

  group('channelsFromM3u', () {
    List<M3uEntry> entries(int count) => [
      for (var i = 0; i < count; i++) M3uEntry(url: 'http://p/$i', name: 'Channel $i', tvgId: 'id-$i'),
    ];

    test('carries name, logo, group and origin onto the channel', () {
      final channels = channelsFromM3u(
        const [
          M3uEntry(
            url: 'http://p/1',
            name: 'Das Erste HD',
            tvgId: 'das-erste.de',
            logo: 'http://logo/ard.png',
            group: 'Vollprogramm',
            number: '1',
          ),
        ],
        sourceId: 'source-1',
        sourceName: 'Mein IPTV',
      );

      final channel = channels.single;
      expect(channel.title, 'Das Erste HD');
      expect(channel.identifier, 'das-erste.de', reason: 'this is what an XMLTV guide keys on');
      expect(channel.thumb, 'http://logo/ard.png');
      expect(channel.number, '1');
      expect(channel.lineup, 'Vollprogramm');
      expect(channel.serverId, 'source-1');
      expect(channel.serverName, 'Mein IPTV');
      expect(
        channel.favoriteSource,
        'iptv://source-1',
        reason: 'the favorites store is keyed by the source URI the Live TV screen registers',
      );
      expect(channel.favoriteStoreKey, 'iptv:source-1');
    });

    test('numbers channels by position when the provider does not', () {
      final channels = channelsFromM3u(entries(3), sourceId: 's', sourceName: 'S');

      expect(channels.map((c) => c.number), ['1', '2', '3']);
    });

    test('channel keys are unique, even for a duplicated stream', () {
      final channels = channelsFromM3u(
        const [
          M3uEntry(url: 'http://p/1', name: 'A', tvgId: 'same'),
          M3uEntry(url: 'http://p/1', name: 'A again', tvgId: 'same'),
        ],
        sourceId: 's',
        sourceName: 'S',
      );

      expect(channels.map((c) => c.key).toSet(), hasLength(2));
    });

    test('two sources holding the same stream stay apart', () {
      final first = channelsFromM3u(entries(1), sourceId: 'source-a', sourceName: 'A').single;
      final second = channelsFromM3u(entries(1), sourceId: 'source-b', sourceName: 'B').single;

      expect(first.key, isNot(second.key));
    });
  });

  group('catch-up attributes', () {
    test('the archive form, its template and its depth are read', () {
      final entry = parseM3u(
        '#EXTM3U\n'
        '#EXTINF:-1 tvg-id="ard" catchup="shift" catchup-source="?utc={utc}" catchup-days="5",Das Erste\n'
        'http://p/ard\n',
      ).single;

      expect(entry.catchup.declaredMode, 'shift');
      expect(entry.catchup.source, '?utc={utc}');
      expect(entry.catchup.days, 5);
    });

    test('the older spellings mean the same thing', () {
      final entry = parseM3u('#EXTM3U\n#EXTINF:-1 catchup-type="flussonic" tvg-rec="3",ZDF\nhttp://p/zdf\n').single;

      expect(entry.catchup.declaredMode, 'flussonic');
      expect(entry.catchup.days, 3);
    });

    test('a seconds-shaped window is read as the days it is', () {
      // `catchup-time` is seconds in some generators; 604800 is a week, not
      // 604800 days.
      final entry = parseM3u('#EXTM3U\n#EXTINF:-1 catchup="default" catchup-time="604800",A\nhttp://p/a\n').single;

      expect(entry.catchup.days, 7);
    });

    test('an entry that says nothing carries nothing', () {
      final entry = parseM3u('#EXTM3U\n#EXTINF:-1,Plain\nhttp://p/plain\n').single;

      expect(entry.catchup.isEmpty, isTrue);
    });

    test('the window reaches the channel, and only for entries that have one', () {
      final channels = channelsFromM3u(
        const [
          M3uEntry(
            url: 'http://p/1',
            name: 'With',
            catchup: IptvCatchupInfo(declaredMode: 'shift', days: 4),
          ),
          M3uEntry(url: 'http://p/2', name: 'Without'),
        ],
        sourceId: 's',
        sourceName: 'S',
      );

      expect(channels.map((c) => c.catchupDays), [4, null]);
    });

    test('an explicit mode gives every channel the source-wide window', () {
      final channels = channelsFromM3u(
        const [M3uEntry(url: 'http://p/1', name: 'Silent')],
        sourceId: 's',
        sourceName: 'S',
        catchupMode: IptvCatchupMode.query,
        sourceCatchupDays: 2,
      );

      expect(channels.single.catchupDays, 2);
    });
  });

  group('choosing groups', () {
    const playlist = '''
#EXTM3U
#EXTINF:-1 group-title="DE • Sport",Sport 1
http://p/1.ts
#EXTINF:-1 group-title="UK • News",News
http://p/2.ts
#EXTINF:-1 group-title="DE • Sport",Sport 2
http://p/3.ts
#EXTINF:-1,Loose
#EXTGRP:Extra
http://p/4.ts
#EXTINF:-1,Nowhere
http://p/5.ts
''';

    test('the groups are counted in the order the playlist names them', () {
      expect(m3uGroupCounts(playlist), {'DE • Sport': 2, 'UK • News': 1, 'Extra': 1, '': 1});
    });

    test('an entry of a group left out is not kept', () {
      final kept = parseM3u(playlist, keepGroup: (group) => group == 'DE • Sport' || group == '');
      expect(kept.map((entry) => entry.name), ['Sport 1', 'Sport 2', 'Nowhere']);
    });
  });
}
