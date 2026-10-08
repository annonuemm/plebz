import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/iptv/xmltv_parser.dart';
import 'package:plezy/services/iptv/xmltv_stream_reader.dart';

const _guide = '''<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <channel id="ard.de"><display-name>Das Erste HD</display-name><icon src="http://logo/ard.png"/></channel>
  <channel id="zdf.de"><display-name>ZDF</display-name></channel>
  <programme start="20240504201500 +0000" stop="20240504214500 +0000" channel="ard.de">
    <title>Tagesschau</title><sub-title>Nachrichten &amp; Wetter</sub-title><desc>Die Übersicht.</desc>
  </programme>
  <programme start="20240504214500 +0000" stop="20240504230000 +0000" channel="zdf.de">
    <title>heute journal</title>
  </programme>
  <programme start="20240504214500 +0000" stop="20240504230000 +0000" channel="other.de">
    <title>Nicht gefragt</title>
  </programme>
</tv>
''';

/// [bytes] cut into pieces of [size], so tags, entities and multi-byte
/// characters fall across the cuts.
Stream<List<int>> _pieces(List<int> bytes, int size) async* {
  for (var start = 0; start < bytes.length; start += size) {
    yield bytes.sublist(start, start + size > bytes.length ? bytes.length : start + size);
  }
}

void main() {
  final plain = utf8.encode(_guide);

  test('reads a guide arriving in pieces as the whole of it would read', () async {
    final whole = parseXmltvGuide(_guide, channelIds: {'ard.de'}, channelNames: {'zdf'});

    final result = await readXmltvStream(
      _pieces(plain, 7),
      channelIds: {'ard.de'},
      channelNames: {'zdf'},
      maxBytes: 1 << 20,
    );

    final guide = (result as XmltvStreamRead).guide;
    expect(guide.programs.map((p) => (p.channelId, p.title, p.subtitle, p.summary)), [
      ('ard.de', 'Tagesschau', 'Nachrichten & Wetter', 'Die Übersicht.'),
      ('zdf.de', 'heute journal', null, null),
    ]);
    expect(guide.programs.map((p) => p.title), whole.programs.map((p) => p.title));
    expect(guide.matchedChannelNames, {'zdf.de': 'zdf'});
    expect(guide.channelIcons, {'ard.de': 'http://logo/ard.png'});
    expect(result.packedBytes, plain.length);
  });

  test('reads a gzipped guide without unpacking it whole first', () async {
    final result = await readXmltvStream(_pieces(gzip.encode(plain), 11), channelIds: {'ard.de'}, maxBytes: 1 << 20);

    expect((result as XmltvStreamRead).guide.programs.single.title, 'Tagesschau');
    expect(result.unpackedBytes, plain.length);
  });

  test('gives up on a guide past the size cap, packed or not', () async {
    final big = utf8.encode(_guide + ' ' * 4096);
    expect(await readXmltvStream(_pieces(big, 512), maxBytes: 2048), isA<XmltvStreamTooLarge>());

    // Small packed, large unpacked: the cap is on what it unpacks to.
    final bomb = gzip.encode(big);
    expect(bomb.length, lessThan(2048));
    expect(await readXmltvStream(_pieces(bomb, 512), maxBytes: 2048), isA<XmltvStreamTooLarge>());
  });

  test('a download that fails part way is unreadable, not a guide', () async {
    Stream<List<int>> failing() async* {
      yield plain.sublist(0, 100);
      throw const SocketException('connection reset');
    }

    expect(await readXmltvStream(failing(), maxBytes: 1 << 20), isA<XmltvStreamUnreadable>());
  });

  test('something that is not XML reads as a guide with nothing in it', () async {
    final result = await readXmltvStream(
      _pieces(utf8.encode('{"user_info":{"auth":0}}'), 5),
      channelIds: {'ard.de'},
      maxBytes: 1 << 20,
    );

    expect(result, isA<XmltvStreamRead>());
    expect((result as XmltvStreamRead).guide.programs, isEmpty);
  });
}
