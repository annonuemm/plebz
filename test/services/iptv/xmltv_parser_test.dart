import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/models/livetv_program.dart';
import 'package:plezy/services/iptv/xmltv_parser.dart';

const _guide = '''
<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <channel id="das-erste.de">
    <display-name>Das Erste</display-name>
  </channel>
  <programme start="20240504201500 +0200" stop="20240504214500 +0200" channel="das-erste.de">
    <title lang="de">Tagesschau</title>
    <desc lang="de">Nachrichten</desc>
    <icon src="http://img/tagesschau.png" />
    <episode-num system="xmltv_ns">1.4.</episode-num>
  </programme>
  <programme start="20240504214500 +0200" stop="20240504224500 +0200" channel="zdf.de">
    <title>Heute Journal</title>
  </programme>
</tv>
''';

void main() {
  group('parseXmltvTime', () {
    test('reads a timestamp with an offset as that instant', () {
      // 20:15 at +0200 is 18:15 UTC.
      expect(parseXmltvTime('20240504201500 +0200'), DateTime.utc(2024, 5, 4, 18, 15).millisecondsSinceEpoch ~/ 1000);
    });

    test('a negative offset moves the other way', () {
      expect(parseXmltvTime('20240504201500 -0500'), DateTime.utc(2024, 5, 5, 1, 15).millisecondsSinceEpoch ~/ 1000);
    });

    test('an offset with minutes is honoured', () {
      expect(parseXmltvTime('20240504201500 +0530'), DateTime.utc(2024, 5, 4, 14, 45).millisecondsSinceEpoch ~/ 1000);
    });

    test('seconds may be omitted', () {
      expect(parseXmltvTime('202405042015 +0000'), DateTime.utc(2024, 5, 4, 20, 15).millisecondsSinceEpoch ~/ 1000);
    });

    test('without an offset the guide is read as local time', () {
      expect(parseXmltvTime('20240504201500'), DateTime(2024, 5, 4, 20, 15).millisecondsSinceEpoch ~/ 1000);
    });

    test('garbage yields null rather than a wrong instant', () {
      expect(parseXmltvTime('not a time'), isNull);
      expect(parseXmltvTime(null), isNull);
      expect(parseXmltvTime(''), isNull);
    });
  });

  group('parseXmltv', () {
    test('reads title, description, icon and slot', () {
      final programs = parseXmltv(_guide);

      final first = programs.firstWhere((p) => p.channelId == 'das-erste.de');
      expect(first.title, 'Tagesschau');
      expect(first.summary, 'Nachrichten');
      expect(first.icon, 'http://img/tagesschau.png');
      expect(first.beginsAt, DateTime.utc(2024, 5, 4, 18, 15).millisecondsSinceEpoch ~/ 1000);
      expect(first.endsAt, DateTime.utc(2024, 5, 4, 19, 45).millisecondsSinceEpoch ~/ 1000);
    });

    test('reads the facts the guide keeps in fields of their own', () {
      // What the strip shows on its own line instead of taking it out of the
      // description, where providers also glue it to the front of the plot.
      final programs = parseXmltv('''
<tv>
  <programme start="20240504201500 +0200" stop="20240504214500 +0200" channel="das-erste.de">
    <title>Endlich Witwer</title>
    <category lang="de">Tragikomödie</category>
    <category lang="de">Spielfilm</category>
    <category lang="de">Drama</category>
    <country>Deutschland</country>
    <date>20190101</date>
  </programme>
</tv>
''');

      expect(programs.single.genres, ['Tragikomödie', 'Spielfilm', 'Drama']);
      expect(programs.single.country, 'Deutschland');
      expect(programs.single.year, 2019, reason: 'the year off the front of the date');
    });

    test('reads the sub-title, where a sports guide puts the pairing', () {
      final programs = parseXmltv('''
<tv>
  <programme start="20261010133000 +0000" stop="20261010160000 +0000" channel="sky.bl1">
    <title lang="de">Bundesliga</title>
    <sub-title lang="de">Borussia Dortmund - Werder Bremen</sub-title>
  </programme>
</tv>
''');

      expect(programs.single.title, 'Bundesliga');
      expect(programs.single.subtitle, 'Borussia Dortmund - Werder Bremen');
      expect(parseXmltv(_guide).first.subtitle, isNull);

      final mapped = programsFromXmltv(programs, channelsByXmltvId: const {'sky.bl1': LiveTvChannelRef(key: 'k')});
      expect(mapped.single.subtitle, 'Borussia Dortmund - Werder Bremen');
      // And through the disk cache, which stores programmes as JSON.
      expect(LiveTvProgram.fromJson(mapped.single.toJson()).subtitle, 'Borussia Dortmund - Werder Bremen');
    });

    test('a programme without those fields carries none', () {
      final first = parseXmltv(_guide).firstWhere((p) => p.channelId == 'das-erste.de');

      expect(first.genres, anyOf(isNull, isEmpty));
      expect(first.country, isNull);
      expect(first.year, isNull);
    });

    test('xmltv_ns episode numbers are zero-based and get corrected', () {
      final first = parseXmltv(_guide).firstWhere((p) => p.channelId == 'das-erste.de');

      expect(first.seasonNumber, 2, reason: '1. means the second season');
      expect(first.episodeNumber, 5, reason: '4. means the fifth episode');
    });

    test('an onscreen episode number is read as written', () {
      final programs = parseXmltv('''
<tv><programme start="20240504201500 +0000" stop="20240504211500 +0000" channel="a">
<title>Show</title><episode-num system="onscreen">S03E07</episode-num>
</programme></tv>
''');

      expect(programs.single.seasonNumber, 3);
      expect(programs.single.episodeNumber, 7);
    });

    test('restricting to known channels drops the rest', () {
      final programs = parseXmltv(_guide, channelIds: {'das-erste.de'});

      expect(programs, hasLength(1));
      expect(programs.single.channelId, 'das-erste.de');
    });

    test('a programme without a usable slot or title is skipped', () {
      final programs = parseXmltv('''
<tv>
  <programme channel="a"><title>No times</title></programme>
  <programme start="20240504201500 +0000" stop="20240504211500 +0000" channel="a"></programme>
  <programme start="20240504201500 +0000" stop="20240504211500 +0000" channel="a"><title>Good</title></programme>
</tv>
''');

      expect(programs, hasLength(1));
      expect(programs.single.title, 'Good');
    });

    test('CDATA text is read like ordinary text', () {
      final programs = parseXmltv('''
<tv><programme start="20240504201500 +0000" stop="20240504211500 +0000" channel="a">
<title><![CDATA[Tatort: Der Fall]]></title>
</programme></tv>
''');

      expect(programs.single.title, 'Tatort: Der Fall');
    });

    test('the channel display block does not leak into a programme', () {
      // <display-name> sits outside <programme>; its text must never become a
      // programme title.
      final programs = parseXmltv('''
<tv>
  <channel id="a"><display-name>Channel A</display-name></channel>
  <programme start="20240504201500 +0000" stop="20240504211500 +0000" channel="a"><title>Real</title></programme>
</tv>
''');

      expect(programs.single.title, 'Real');
    });

    test('a channel is matched by its display name when the ids disagree', () {
      // The usual provider mismatch: the playlist says `tvg-id="ard"`, the
      // guide calls the same channel something else entirely.
      final guide = parseXmltvGuide(
        '''
<tv>
  <channel id="ARD.de"><display-name>Das Erste HD</display-name></channel>
  <programme start="20240504201500 +0000" stop="20240504214500 +0000" channel="ARD.de">
    <title>Tagesschau</title>
  </programme>
</tv>
''',
        channelIds: const {'ard'},
        channelNames: const {'daserstehd'},
      );

      expect(guide.matchedChannelNames, {'ARD.de': 'daserstehd'});
      expect(guide.programs.single.title, 'Tagesschau');
    });

    test('a quality suffix on one side only still matches', () {
      final guide = parseXmltvGuide(
        '''
<tv>
  <channel id="zdf"><display-name>ZDF HD</display-name></channel>
  <programme start="20240504201500 +0000" stop="20240504214500 +0000" channel="zdf"><title>heute</title></programme>
</tv>
''',
        channelIds: const {},
        channelNames: const {'zdf'},
      );

      expect(guide.matchedChannelNames, {'zdf': 'zdf'});
      expect(guide.programs, hasLength(1));
    });

    test('a compacted name is never mistaken for a quality marker', () {
      // "ZDF HD" compacts to `zdfhd`, which ends with `fhd` without carrying
      // that marker — stripping letters instead of words would leave `zd`.
      expect(xmltvChannelNameVariants('ZDF HD'), {'zdfhd', 'zdf'});
      expect(xmltvChannelNameVariants('Sky Sport Bundesliga 1 FHD'), {'skysportbundesliga1fhd', 'skysportbundesliga1'});
      expect(xmltvChannelNameVariants('HD'), {'hd'}, reason: 'a channel is not stripped down to nothing');
    });

    test('quality words written together are quality words too', () {
      // The user's guide names its whole line-up "… HDraw", under ids that
      // are hashes; the playlist says "… HD".
      expect(xmltvChannelNameVariants('Sky Bundesliga 2 HDraw'), {'skybundesliga2hdraw', 'skybundesliga2'});
      expect(xmltvChannelNameVariants('RAW TV'), {'rawtv'}, reason: 'a word of its own is not a marker');

      final guide = parseXmltvGuide(
        '''
<tv>
  <channel id="44ca1aa29408dcbc6e94799fc11619a8"><display-name>Sky Bundesliga 2 HDraw</display-name></channel>
  <programme start="20240504201500 +0000" stop="20240504214500 +0000" channel="44ca1aa29408dcbc6e94799fc11619a8">
    <title>Konferenz</title>
  </programme>
</tv>
''',
        channelIds: const {'sky-bl-2'},
        channelNames: xmltvChannelNameVariants('Sky Bundesliga 2 HD'),
      );

      expect(guide.matchedChannelNames, {'44ca1aa29408dcbc6e94799fc11619a8': 'skybundesliga2'});
      expect(guide.programs.single.title, 'Konferenz');
    });

    test('a name nobody asked for is not matched', () {
      final guide = parseXmltvGuide(
        '''
<tv>
  <channel id="rtl"><display-name>RTL</display-name></channel>
  <programme start="20240504201500 +0000" stop="20240504214500 +0000" channel="rtl"><title>Show</title></programme>
</tv>
''',
        channelIds: const {'ard'},
        channelNames: const {'daserste'},
      );

      expect(guide.matchedChannelNames, isEmpty);
      expect(guide.programs, isEmpty);
    });

    test('keeps the logo a channel block names, for the channels asked for', () {
      final guide = parseXmltvGuide(
        '''
<tv>
  <channel id="sky-mix"><display-name>Sky Sport Mix</display-name><icon src=" http://logos/sky-mix.png "/></channel>
  <channel id="ARD.de"><display-name>Das Erste HD</display-name><icon src="http://logos/ard.png"/></channel>
  <channel id="rtl"><display-name>RTL</display-name><icon src="http://logos/rtl.png"/></channel>
  <programme start="20240504201500 +0000" stop="20240504214500 +0000" channel="sky-mix">
    <title>Bundesliga</title>
    <icon src="http://pictures/match.jpg"/>
  </programme>
</tv>
''',
        channelIds: const {'sky-mix'},
        channelNames: const {'daserstehd'},
      );

      expect(guide.channelIcons, {
        'sky-mix': 'http://logos/sky-mix.png',
        'ARD.de': 'http://logos/ard.png',
      }, reason: 'by id and by name; nobody asked for RTL');
      expect(guide.programs.single.icon, 'http://pictures/match.jpg', reason: 'a programme keeps its own picture');
    });

    test('an empty guide is empty, not an error', () {
      expect(parseXmltv('<tv></tv>'), isEmpty);
    });
  });

  group('programsFromXmltv', () {
    test('attaches entries to the channels a source carries', () {
      final programs = programsFromXmltv(
        parseXmltv(_guide),
        channelsByXmltvId: const {
          'das-erste.de': LiveTvChannelRef(
            key: 'iptv:s:1',
            identifier: 'das-erste.de',
            serverId: 's',
            serverName: 'Panel',
          ),
        },
      );

      expect(programs, hasLength(1), reason: 'the zdf.de entry has no channel here');
      expect(programs.single.title, 'Tagesschau');
      expect(programs.single.serverName, 'Panel');
      expect(programs.single.channelIdentifier, 'das-erste.de');
    });

    test('a channel matched under a foreign guide id is keyed on its own', () {
      // A name match resolves an id the channel never carried, so keying the
      // programme on the guide's id would leave it unmatchable.
      final programs = programsFromXmltv(
        parseXmltv(_guide),
        channelsByXmltvId: const {'das-erste.de': LiveTvChannelRef(key: 'iptv:s:1')},
      );

      expect(programs.single.channelIdentifier, 'iptv:s:1');
    });

    test('programmes come back in chronological order', () {
      final programs = programsFromXmltv(
        parseXmltv('''
<tv>
  <programme start="20240504220000 +0000" stop="20240504230000 +0000" channel="a"><title>Later</title></programme>
  <programme start="20240504200000 +0000" stop="20240504210000 +0000" channel="a"><title>Earlier</title></programme>
</tv>
'''),
        channelsByXmltvId: const {'a': LiveTvChannelRef(key: 'iptv:s:1')},
      );

      expect(programs.map((p) => p.title), ['Earlier', 'Later']);
    });
  });
}
