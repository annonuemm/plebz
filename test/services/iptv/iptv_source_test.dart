import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/iptv/iptv_catchup.dart';
import 'package:plezy/services/iptv/iptv_source.dart';

const _m3u = IptvSource(
  id: 'a',
  name: 'Mein IPTV',
  kind: IptvSourceKind.m3u,
  playlistUrl: 'http://provider/list.m3u',
  epgUrls: ['http://provider/epg.xml'],
);

const _xtream = IptvSource(
  id: 'b',
  name: 'Panel',
  kind: IptvSourceKind.xtream,
  baseUrl: 'http://panel:8080',
  username: 'u',
  password: 'p',
);

void main() {
  group('isComplete', () {
    test('an M3U source needs its playlist', () {
      expect(_m3u.isComplete, isTrue);
      expect(const IptvSource(id: 'a', name: 'A', kind: IptvSourceKind.m3u).isComplete, isFalse);
    });

    test('an M3U source without a guide is still usable', () {
      expect(
        const IptvSource(id: 'a', name: 'A', kind: IptvSourceKind.m3u, playlistUrl: 'http://p/l.m3u').isComplete,
        isTrue,
      );
    });

    test('an Xtream source needs all three of URL, user and password', () {
      expect(_xtream.isComplete, isTrue);
      expect(_xtream.copyWith(password: '').isComplete, isFalse);
      expect(const IptvSource(id: 'b', name: 'B', kind: IptvSourceKind.xtream).isComplete, isFalse);
    });
  });

  group('encode/decode', () {
    test('a source survives a round trip', () {
      final restored = IptvSource.decodeList(IptvSource.encodeList([_m3u, _xtream]));

      expect(restored, hasLength(2));
      expect(restored.first.id, 'a');
      expect(restored.first.kind, IptvSourceKind.m3u);
      expect(restored.first.playlistUrl, 'http://provider/list.m3u');
      expect(restored.first.epgUrls, ['http://provider/epg.xml']);
      expect(restored.last.kind, IptvSourceKind.xtream);
      expect(restored.last.username, 'u');
      expect(restored.last.password, 'p');
    });

    test('the stream format survives a round trip', () {
      final source = _xtream.copyWith(streamFormat: IptvStreamFormat.hls);

      expect(IptvSource.decodeList(IptvSource.encodeList([source])).single.streamFormat, IptvStreamFormat.hls);
      expect(IptvSource.decodeList(IptvSource.encodeList([_xtream])).single.streamFormat, IptvStreamFormat.mpegTs);
    });

    test('a source saved before the choice existed keeps what it was served', () {
      // The app asked every panel for HLS unconditionally. Reading a stored
      // source as MPEG-TS would silently change the stream under a setup that
      // was working.
      final restored = IptvSource.decodeList(
        '[{"id":"x","name":"X","kind":"xtream","baseUrl":"http://p:8080","username":"u","password":"p"}]',
      );

      expect(restored.single.streamFormat, IptvStreamFormat.hls);
    });

    test('several guides survive a round trip in order', () {
      final source = _m3u.copyWith(epgUrls: ['http://provider/epg.xml', 'http://other/epg.xml']);

      final restored = IptvSource.decodeList(IptvSource.encodeList([source]));

      expect(restored.single.epgUrls, ['http://provider/epg.xml', 'http://other/epg.xml']);
    });

    test('a source stored with the single-guide shape keeps its guide', () {
      // The shape this fork wrote before a source could carry more than one.
      final restored = IptvSource.decodeList(
        '[{"id":"a","name":"A","kind":"m3u","playlistUrl":"http://p","epgUrl":"http://p/epg.xml"}]',
      );

      expect(restored.single.epgUrls, ['http://p/epg.xml']);
    });

    test('a malformed entry is skipped, not fatal', () {
      final restored = IptvSource.decodeList(
        '[{"id":"a","name":"A","kind":"m3u","playlistUrl":"http://p"},{"name":"no id"},"garbage",{"id":"c","name":"C","kind":"unknown"}]',
      );

      expect(restored.map((source) => source.id), ['a']);
    });

    test('nothing stored yields no sources', () {
      expect(IptvSource.decodeList(null), isEmpty);
      expect(IptvSource.decodeList(''), isEmpty);
      expect(IptvSource.decodeList('not json'), isEmpty);
      expect(IptvSource.decodeList('{"not":"a list"}'), isEmpty);
    });
  });

  test('copyWith keeps the id, which channel keys and favorites depend on', () {
    expect(_m3u.copyWith(name: 'Umbenannt').id, 'a');
    expect(_m3u.copyWith(name: 'Umbenannt').name, 'Umbenannt');
    expect(_m3u.copyWith(name: 'Umbenannt').playlistUrl, 'http://provider/list.m3u');
  });

  group('catch-up settings', () {
    test('survive a save and a reload', () {
      const source = IptvSource(
        id: 'a',
        name: 'Panel',
        kind: IptvSourceKind.xtream,
        baseUrl: 'http://panel:8080',
        username: 'u',
        password: 'p',
        catchupMode: IptvCatchupMode.flussonic,
        catchupDays: 3,
      );

      final restored = IptvSource.decodeList(IptvSource.encodeList([source])).single;

      expect(restored.catchupMode, IptvCatchupMode.flussonic);
      expect(restored.catchupDays, 3);
    });

    test('a source saved before the setting existed reads as automatic', () {
      final restored = IptvSource.fromJson({'id': 'a', 'name': 'Alt', 'kind': 'm3u', 'playlistUrl': 'http://p/l.m3u'});

      expect(restored!.catchupMode, IptvCatchupMode.automatic);
      expect(restored.catchupDays, isNull);
    });
  });
}
