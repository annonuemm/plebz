import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/models/live_tv_channel_layout.dart';
import 'package:plezy/models/livetv_channel.dart';
import 'package:plezy/models/livetv_program.dart';
import 'package:plezy/services/favorite_channels_repository.dart';
import 'package:plezy/services/iptv/iptv_disk_cache.dart';
import 'package:plezy/services/iptv/iptv_catchup.dart';
import 'package:plezy/services/iptv/iptv_live_tv_source.dart';
import 'package:plezy/services/iptv/iptv_source.dart';

const _playlist = '''
#EXTM3U
#EXTINF:-1 tvg-id="das-erste.de" tvg-logo="http://logo/ard.png" group-title="Vollprogramm",Das Erste HD
http://provider/stream/ard
#EXTINF:-1,Kein EPG
http://provider/stream/other
''';

/// The same station three times over, as a provider lists it: same `tvg-id`,
/// different names and addresses.
const _repeatedPlaylist = '''
#EXTM3U
#EXTINF:-1 tvg-id="das-erste.de" tvg-logo="http://logo/ard.png",Das Erste HD
http://provider/stream/ard
#EXTINF:-1 tvg-id="das-erste.de",Das Erste HD 2
http://provider/stream/ard2
#EXTINF:-1 tvg-id="das-erste.de",Das Erste HD 3
http://provider/stream/ard3
#EXTINF:-1 tvg-id="zdf.de",ZDF HD
http://provider/stream/zdf
''';

/// The user's own shape: copies ordered by quality, and the archive on a
/// lesser one — RAW plays first and has none.
const _repeatedWithArchive = '''
#EXTM3U
#EXTINF:-1 tvg-id="das-erste.de",Das Erste RAW
http://provider/stream/ard-raw
#EXTINF:-1 tvg-id="das-erste.de" catchup="shift" catchup-days="7",Das Erste FHD
http://provider/stream/ard-fhd
#EXTINF:-1 tvg-id="das-erste.de" catchup="shift" catchup-days="3",Das Erste HD
http://provider/stream/ard-hd
''';

const _guide = '''
<tv>
  <programme start="20240504201500 +0000" stop="20240504214500 +0000" channel="das-erste.de">
    <title>Tagesschau</title>
  </programme>
</tv>
''';

/// [_guide] packed as xz by the reference tool (`xz`/liblzma), not by the
/// archive package, whose encoder only writes uncompressed blocks.
final _guideXz = base64.decode(
  '/Td6WFoAAATm1rRGAgAhARYAAAB0L+Wj4ACWAHBdAAUQBzf7NqDHXHl1qJVH6oUfMwYAzjjm7T1T9roysQ2qgEj7vh9uXf7wnsNbhv8aoPMYjCXF+hRyoT4lPVkEmZcnmRy64Dg/6Ccxv3SBHqoD9K3/nvl+JtilO0dMeDoiAzBH9GSvu4nC+6DccGh/XAAAt/IfGQSxOGAAAYwBlwEAAOSaEraxxGf7AgAAAAAEWVo=',
);

/// [_guide] followed by a megabyte of spaces, packed as xz: a few hundred
/// bytes that unpack to a megabyte.
final _guideXzBomb = base64.decode(
  '/Td6WFoAAATm1rRGAgAhARYAAAB0L+Wj8ACWAUZdAAUQBzf7NqDHXHl1qJVH6oUfMwYAzjjm7T1T9roysQ2qgEj7vh9uXf7wnsNbhv8aoPMYjCXF+hRyoT4lPVkEmZcnmRy64Dg/6Ccxv3SBHqoD9K3/nvl+JtilO0dMeDoiAzBH9GSvu4nC+6DdO5Tn49FPJh0OSUBCVpytAYhmxqsEHq1gCxXN/LQXTMw2uii2ifipdBy8JiYzq9Y+8bDDfteq4pxGouvh5b9S1LD7Qge1/BAiHLr38G3EAprxtqM4F9c7YBA9PQA+rSbAQACPtRlaVTnhvaI+VmV+SPTQdFaDnARuzL3Z6Iqtly3/LuuaHbrOsScYXFmG6WZSWL7pdqxZ5OVbBQj5x9qt/PtSK3TNHlsgQvndUz34KWQJO4DLKmzftTvwxL0uX6oPPktmQpATDv8Qk/hxeFn4C83/lShGD5Glx1oAAAAAXEX4M611k2IAAeICl4FAAJvaANKxxGf7AgAAAAAEWVo=',
);

/// Favorites kept in memory, so the tests never touch SharedPreferences.
class _MemoryFavorites implements FavoriteChannelsRepository {
  final Map<String, List<FavoriteChannel>> stored = {};

  @override
  Future<List<FavoriteChannel>> read({
    required String key,
    required String legacyKey,
    bool migrate = true,
    void Function()? checkCurrent,
  }) async {
    checkCurrent?.call();
    return stored[key] ?? const [];
  }

  @override
  Future<void> write(String key, List<FavoriteChannel> channels, {void Function()? checkCurrent}) async {
    checkCurrent?.call();
    stored[key] = channels;
  }
}

IptvLiveTvSource _m3uSource(
  MockClient client, {
  String? epgUrl,
  List<String>? epgUrls,
  FavoriteChannelsRepository? favorites,
  DateTime Function()? now,
  IptvDiskCache? diskCache,
  Duration Function()? diskCacheMaxAge,
  bool mergeDuplicates = false,
  LiveTvChannelLayout Function()? layout,
  int maxResponseBytes = IptvLiveTvSource.defaultMaxResponseBytes,
}) => IptvLiveTvSource(
  IptvSource(
    id: 'src',
    name: 'Mein IPTV',
    kind: IptvSourceKind.m3u,
    playlistUrl: 'http://provider/list.m3u',
    epgUrls: epgUrls ?? [?epgUrl],
  ),
  httpClient: client,
  favorites: favorites ?? _MemoryFavorites(),
  now: now ?? DateTime.now,
  diskCache: diskCache,
  diskCacheMaxAge: diskCacheMaxAge,
  mergeDuplicates: () => mergeDuplicates,
  channelLayout: layout == null ? null : () async => layout(),
  maxResponseBytes: maxResponseBytes,
);

/// A playlist whose one entry keeps a five-day archive in the query form.
const _catchupPlaylist = '''
#EXTM3U
#EXTINF:-1 tvg-id="ard" catchup="shift" catchup-days="5",Das Erste HD
http://provider/stream/ard
''';

IptvLiveTvSource _xtreamCatchupSource(
  MockClient client, {
  IptvCatchupMode mode = IptvCatchupMode.automatic,
  int? days,
  DateTime Function()? now,
}) => IptvLiveTvSource(
  IptvSource(
    id: 'src',
    name: 'Panel',
    kind: IptvSourceKind.xtream,
    baseUrl: 'http://panel:8080',
    username: 'u',
    password: 'p',
    catchupMode: mode,
    catchupDays: days,
  ),
  httpClient: client,
  favorites: _MemoryFavorites(),
  now: now ?? DateTime.now,
);

IptvLiveTvSource _xtreamSource(MockClient client, {LiveTvChannelLayout Function()? layout}) => IptvLiveTvSource(
  const IptvSource(
    id: 'src',
    name: 'Panel',
    kind: IptvSourceKind.xtream,
    baseUrl: 'http://panel:8080',
    username: 'u',
    password: 'p',
  ),
  httpClient: client,
  favorites: _MemoryFavorites(),
  channelLayout: layout == null ? null : () async => layout(),
);

/// Two channels in two groups, and a guide for both.
const _twoGroupsPlaylist = '''
#EXTM3U
#EXTINF:-1 tvg-id="das-erste.de" group-title="Vollprogramm",Das Erste HD
http://provider/stream/ard
#EXTINF:-1 tvg-id="zdf.de" group-title="Ausgeblendet",ZDF HD
http://provider/stream/zdf
''';

const _twoChannelGuide = '''
<tv>
  <programme start="20240504201500 +0000" stop="20240504214500 +0000" channel="das-erste.de">
    <title>Tagesschau</title>
  </programme>
  <programme start="20240504201500 +0000" stop="20240504214500 +0000" channel="zdf.de">
    <title>heute</title>
  </programme>
</tv>
''';

const _hideSecondGroup = LiveTvChannelLayout(hiddenGroups: {'Ausgeblendet'});

http.Response _ok(String body) => http.Response(body, 200);
http.Response _okJson(Object body) => http.Response(jsonEncode(body), 200);

void main() {
  group('repeats of the same station', () {
    MockClient repeated() =>
        MockClient((request) async => _ok(request.url.path.endsWith('.m3u') ? _repeatedPlaylist : _guide));

    test('off, every copy is its own channel', () async {
      final source = _m3uSource(repeated());
      addTearDown(source.close);

      final channels = await source.fetchChannels();

      expect(channels.map((channel) => channel.title), ['Das Erste HD', 'Das Erste HD 2', 'Das Erste HD 3', 'ZDF HD']);
    });

    test('on, one channel per station, named and keyed after the first', () async {
      final source = _m3uSource(repeated(), mergeDuplicates: true);
      addTearDown(source.close);

      final channels = await source.fetchChannels();

      expect(channels.map((channel) => channel.title), ['Das Erste HD', 'ZDF HD']);
      // The merged channel *is* the first copy: favourites are stored by key
      // and must keep pointing at something real when the setting is flipped.
      final unmerged = await _m3uSource(repeated()).fetchChannels();
      expect(channels.first.key, unmerged.first.key);
    });

    test('the station keeps the archive of whichever copy has one', () async {
      // Ordered by quality, so the copy that plays is the best one — and the
      // archive often sits on a lesser copy. Judged by the first copy alone
      // the station would look archive-less and the guide would offer nothing
      // to scroll back to.
      final source = _m3uSource(
        MockClient((request) async => _ok(request.url.path.endsWith('.m3u') ? _repeatedWithArchive : _guide)),
        mergeDuplicates: true,
      );
      addTearDown(source.close);

      final channels = await source.fetchChannels();

      expect(channels.single.title, 'Das Erste RAW', reason: 'the order stands: best quality still plays');
      expect(channels.single.catchupDays, 7, reason: 'the deepest archive in the group speaks for the station');
    });

    test('the archive is addressed through the copy that has it', () async {
      final source = _m3uSource(
        MockClient((request) async => _ok(request.url.path.endsWith('.m3u') ? _repeatedWithArchive : _guide)),
        mergeDuplicates: true,
      );
      addTearDown(source.close);
      final channels = await source.fetchChannels();

      final session = await source.startPlayback(channels.single.key);
      final live = await session!.streamUrlAt();
      final archive = await session.streamUrlAt(offsetSeconds: 60);

      expect(live, 'http://provider/stream/ard-raw', reason: 'live still plays the first copy');
      expect(
        archive,
        contains('ard-fhd'),
        reason: 'the archive URL is built from the copy that keeps one, not from the one playing',
      );
    });

    test('a station whose copies all lack an archive keeps none', () async {
      final source = _m3uSource(repeated(), mergeDuplicates: true);
      addTearDown(source.close);

      final channels = await source.fetchChannels();

      expect(channels.first.catchupDays, isNull);
    });

    test('a station with no id stands alone, whatever it is called', () async {
      // Grouping on the name would fold SPORT1 into SPORT1+ sooner or later.
      final source = _m3uSource(
        MockClient((request) async => _ok(request.url.path.endsWith('.m3u') ? _playlist : _guide)),
        mergeDuplicates: true,
      );
      addTearDown(source.close);

      final channels = await source.fetchChannels();

      expect(channels.map((channel) => channel.title), ['Das Erste HD', 'Kein EPG']);
    });

    test('the player is offered the copies by name, and can pick one', () async {
      final source = _m3uSource(repeated(), mergeDuplicates: true);
      addTearDown(source.close);
      final channels = await source.fetchChannels();

      final session = await source.startPlayback(channels.first.key);

      // Named after the playlist entries, which is what tells two routes to
      // the same station apart in a menu.
      expect(session!.variantLabels, ['Das Erste HD', 'Das Erste HD 2', 'Das Erste HD 3']);
      expect(session.variantIndex, 0);

      final third = await session.switchVariant(2);
      expect(await third!.streamUrlAt(), 'http://provider/stream/ard3');
      expect(third.variantIndex, 2);

      // Nothing to do for the one already playing, or for an index that is
      // not there.
      expect(await third.switchVariant(2), isNull);
      expect(await third.switchVariant(9), isNull);
    });

    test('a channel with one address offers no choice at all', () async {
      final source = _m3uSource(
        MockClient((request) async => _ok(request.url.path.endsWith('.m3u') ? _playlist : _guide)),
        mergeDuplicates: true,
      );
      addTearDown(source.close);
      final channels = await source.fetchChannels();

      final session = await source.startPlayback(channels.first.key);

      // Empty rather than one entry: the control is absent, not a switch with
      // nothing to switch to.
      expect(session!.variantLabels, isEmpty);
    });

    test('playback starts on the first copy and recovery moves to the next', () async {
      final source = _m3uSource(repeated(), mergeDuplicates: true);
      addTearDown(source.close);
      final channels = await source.fetchChannels();

      final first = await source.startPlayback(channels.first.key);
      expect(await first!.streamUrlAt(), 'http://provider/stream/ard');

      // Before merging this was a no-op: three attempts at the same failing
      // address, because a playlist has no server session to reconfigure.
      final second = await first.recover(directStream: false, directStreamAudio: false);
      expect(await second!.streamUrlAt(), 'http://provider/stream/ard2');

      final third = await second.recover(directStream: false, directStreamAudio: false);
      expect(await third!.streamUrlAt(), 'http://provider/stream/ard3');

      // Nothing left to try: the last one is re-opened rather than giving up.
      final again = await third.recover(directStream: false, directStreamAudio: false);
      expect(await again!.streamUrlAt(), 'http://provider/stream/ard3');
    });
  });

  group('kept across restarts', () {
    late Directory root;
    late IptvDiskCache cache;
    var now = DateTime(2026, 8, 29, 12);

    setUp(() async {
      root = await Directory.systemTemp.createTemp('iptv_source_cache');
      cache = IptvDiskCache(directoryProvider: () async => root);
      now = DateTime(2026, 8, 29, 12);
    });

    tearDown(() async {
      // Every source above awaits its write before closing. Without that a
      // fire-and-forget write outlives the test and lands after this line,
      // failing against a directory that is no longer there.
      if (await root.exists()) await root.delete(recursive: true);
    });

    /// A fresh source over the same store, the way a restart brings one up.
    IptvLiveTvSource restart(MockClient client, {Duration maxAge = const Duration(days: 1)}) => _m3uSource(
      client,
      epgUrl: 'http://provider/epg.xml',
      now: () => now,
      diskCache: cache,
      diskCacheMaxAge: () => maxAge,
    );

    test('a restart reads the stored copy instead of the network', () async {
      var requests = 0;
      MockClient counting() => MockClient((request) async {
        requests++;
        return _ok(request.url.path.endsWith('.m3u') ? _playlist : _guide);
      });

      final first = restart(counting());
      await first.fetchChannels();
      await first.fetchSchedule();
      final afterFirst = requests;
      expect(afterFirst, greaterThan(0));
      // The write is fire-and-forget; wait for the one in flight rather than
      // sleeping and hoping.
      await first.pendingDiskWrite;
      first.close();

      final second = restart(counting());
      final channels = await second.fetchChannels();
      final programs = await second.fetchSchedule();
      await second.pendingDiskWrite;
      second.close();

      expect(channels, isNotEmpty);
      expect(programs, isNotEmpty);
      expect(requests, afterFirst, reason: 'nothing was fetched a second time');
      // And what came back can still be played.
      expect(await second.startPlayback(channels.first.key), isNotNull);
    });

    test('on a restart, callers arriving together all read the stored copy', () async {
      // The guide, "Jetzt im TV" and Sport ask at once when Live TV opens.
      // Only the first of them read the disk; the others found nothing in
      // memory yet and fetched the playlist and the guide from the network.
      var requests = 0;
      MockClient counting() => MockClient((request) async {
        requests++;
        return _ok(request.url.path.endsWith('.m3u') ? _playlist : _guide);
      });

      final first = restart(counting(), maxAge: const Duration(days: 3));
      await first.fetchChannels();
      await first.fetchSchedule();
      await first.pendingDiskWrite;
      first.close();
      final afterFirst = requests;

      now = now.add(const Duration(days: 2));
      final second = restart(counting(), maxAge: const Duration(days: 3));
      final results = await Future.wait<Object>([
        second.fetchChannels(),
        second.fetchSchedule(),
        second.fetchSchedule(),
        second.fetchChannels(),
      ]);
      await second.pendingDiskWrite;
      second.close();

      expect(requests, afterFirst, reason: 'two days into a three-day interval nothing is fetched');
      expect(results.whereType<List<Object>>().every((list) => list.isNotEmpty), isTrue);
    });

    test('callers arriving together with nothing stored share one download of each', () async {
      final paths = <String>[];
      final source = restart(
        MockClient((request) async {
          paths.add(request.url.path);
          return _ok(request.url.path.endsWith('.m3u') ? _playlist : _guide);
        }),
      );

      await Future.wait<Object>([
        source.fetchChannels(),
        source.fetchSchedule(),
        source.fetchSchedule(),
        source.fetchChannels(),
      ]);
      await source.pendingDiskWrite;
      source.close();

      expect(paths.where((path) => path.endsWith('.m3u')), hasLength(1), reason: 'one playlist download');
      expect(paths.where((path) => path.endsWith('epg.xml')), hasLength(1), reason: 'one guide download');
    });

    test('two writes at once leave the later one readable', () async {
      final channel = LiveTvChannel(key: 'iptv:src:a', title: 'A');
      IptvCacheEntry entry(String title) => IptvCacheEntry(
        savedAt: now,
        channels: [channel],
        programs: [LiveTvProgram(title: title, beginsAt: 1, endsAt: 2)],
      );

      await Future.wait([cache.write('src', entry('earlier')), cache.write('src', entry('later'))]);

      final stored = await cache.read('src');
      expect(stored, isNotNull, reason: 'a torn file reads as nothing, and the next start fetches everything');
      expect(stored!.programs.single.title, 'later');
    });

    test('past the interval it fetches again', () async {
      var requests = 0;
      MockClient counting() => MockClient((request) async {
        requests++;
        return _ok(request.url.path.endsWith('.m3u') ? _playlist : _guide);
      });

      final first = restart(counting());
      await first.fetchChannels();
      await first.pendingDiskWrite;
      first.close();
      final afterFirst = requests;

      now = now.add(const Duration(days: 2));
      final second = restart(counting());
      await second.fetchChannels();
      await second.pendingDiskWrite;
      second.close();

      expect(requests, greaterThan(afterFirst));
    });

    test('a refresh by hand drops the stored copy', () async {
      var requests = 0;
      MockClient counting() => MockClient((request) async {
        requests++;
        return _ok(request.url.path.endsWith('.m3u') ? _playlist : _guide);
      });

      final first = restart(counting());
      await first.fetchChannels();
      await first.pendingDiskWrite;
      // What the user's refresh button does.
      first.invalidate();
      await first.fetchChannels();
      await first.pendingDiskWrite;
      first.close();
      final afterRefresh = requests;

      final second = restart(counting());
      await second.fetchChannels();
      await second.pendingDiskWrite;
      second.close();

      expect(
        requests,
        afterRefresh,
        reason: 'the refresh stored what it fetched, so the next start still reads from disk',
      );
    });
  });

  group('M3U', () {
    test('lists the playlist channels', () async {
      final source = _m3uSource(MockClient((_) async => _ok(_playlist)));

      final channels = await source.fetchChannels();

      expect(channels.map((c) => c.title), ['Das Erste HD', 'Kein EPG']);
      expect(channels.first.identifier, 'das-erste.de');
      expect(channels.first.serverName, 'Mein IPTV');
    });

    test('plays the stream URL behind the channel', () async {
      // The regression this guards: the channel key is built from tvg-id, so
      // the stream address has to be remembered when the playlist is read —
      // it cannot be recovered from the key.
      final source = _m3uSource(MockClient((_) async => _ok(_playlist)));
      final channels = await source.fetchChannels();

      final session = await source.startPlayback(channels.first.key);

      expect(session, isNotNull);
      expect(await session!.streamUrlAt(), 'http://provider/stream/ard');
    });

    test('plays a channel that has no tvg-id', () async {
      final source = _m3uSource(MockClient((_) async => _ok(_playlist)));
      final channels = await source.fetchChannels();

      final session = await source.startPlayback(channels.last.key);

      expect(await session!.streamUrlAt(), 'http://provider/stream/other');
    });

    test('a session carries the headers its playlist entry asked for', () async {
      // Providers that check the user agent hand out a playlist that plays
      // nowhere without it.
      const guarded = '''
#EXTM3U
#EXTINF:-1,Guarded
#EXTVLCOPT:http-user-agent=Mozilla/5.0 (SmartTV)
http://provider/stream/guarded
''';
      final source = _m3uSource(MockClient((_) async => _ok(guarded)));
      final channels = await source.fetchChannels();

      final session = await source.startPlayback(channels.single.key);

      expect(session!.streamHeaders, {'User-Agent': 'Mozilla/5.0 (SmartTV)'});
    });

    test('a session for an entry without headers sends none', () async {
      final source = _m3uSource(MockClient((_) async => _ok(_playlist)));
      final channels = await source.fetchChannels();

      final session = await source.startPlayback(channels.first.key);

      expect(session!.streamHeaders, isEmpty);
    });

    test('an unknown channel yields no session rather than a broken one', () async {
      final source = _m3uSource(MockClient((_) async => _ok(_playlist)));

      expect(await source.startPlayback('iptv:src:nope'), isNull);
    });

    test('reads the guide and attaches it to the matching channel', () async {
      final source = _m3uSource(
        MockClient((request) async => _ok(request.url.path.endsWith('.m3u') ? _playlist : _guide)),
        epgUrl: 'http://provider/epg.xml',
      );

      final programs = await source.fetchSchedule();

      expect(programs, hasLength(1));
      expect(programs.single.title, 'Tagesschau');
      expect(programs.single.channelIdentifier, 'das-erste.de');
    });

    test('a second guide fills the holes the first leaves', () async {
      const second = '''
<tv>
  <programme start="20240504201500 +0000" stop="20240504214500 +0000" channel="das-erste.de">
    <title>Duplicate slot</title>
  </programme>
  <programme start="20240504214500 +0000" stop="20240504224500 +0000" channel="das-erste.de">
    <title>Tatort</title>
  </programme>
</tv>
''';
      final source = _m3uSource(
        MockClient((request) async {
          if (request.url.path.endsWith('.m3u')) return _ok(_playlist);
          return _ok(request.url.path.contains('second') ? second : _guide);
        }),
        epgUrls: ['http://provider/epg.xml', 'http://provider/second.xml'],
      );

      final programs = await source.fetchSchedule();

      expect(programs.map((p) => p.title), [
        'Tagesschau',
        'Tatort',
      ], reason: 'the first guide keeps the slot it already filled');
    });

    test('a second guide running a few minutes apart lays nothing over the first', () async {
      // Two timetables for one channel whose starts differ: keyed on the start
      // alone both survived, and the grid printed their titles over each other.
      const second = '''
<tv>
  <programme start="20240504201000 +0000" stop="20240504215000 +0000" channel="das-erste.de">
    <title>Shifted</title>
  </programme>
  <programme start="20240504214500 +0000" stop="20240504224500 +0000" channel="das-erste.de">
    <title>Tatort</title>
  </programme>
</tv>
''';
      final source = _m3uSource(
        MockClient((request) async {
          if (request.url.path.endsWith('.m3u')) return _ok(_playlist);
          return _ok(request.url.path.contains('second') ? second : _guide);
        }),
        epgUrls: ['http://provider/epg.xml', 'http://provider/second.xml'],
      );

      final programs = await source.fetchSchedule();

      expect(programs.map((p) => p.title), ['Tagesschau', 'Tatort'], reason: 'only the hole after 21:45 is filled');
    });

    test('in one guide the channel matched by id owns the timeline, one matched by name fills its holes', () async {
      // Listed first on purpose: the order in the file is not what decides.
      const both = '''
<tv>
  <channel id="ARD.de"><display-name>Das Erste HD</display-name></channel>
  <programme start="20240504200000 +0000" stop="20240504203000 +0000" channel="ARD.de">
    <title>Name match</title>
  </programme>
  <programme start="20240504220000 +0000" stop="20240504230000 +0000" channel="ARD.de">
    <title>Late</title>
  </programme>
  <programme start="20240504201500 +0000" stop="20240504214500 +0000" channel="das-erste.de">
    <title>Tagesschau</title>
  </programme>
</tv>
''';
      final source = _m3uSource(
        MockClient((request) async => _ok(request.url.path.endsWith('.m3u') ? _playlist : both)),
        epgUrl: 'http://provider/epg.xml',
      );

      final programs = await source.fetchSchedule();

      expect(programs.map((p) => p.title), ['Tagesschau', 'Late']);
    });

    test('a guide whose ids do not match the playlist is matched by name', () async {
      // The provider's own mismatch: the playlist says `das-erste.de`, its
      // guide calls the same channel `ARD.de`.
      const foreignIds = '''
<tv>
  <channel id="ARD.de"><display-name>Das Erste HD</display-name></channel>
  <programme start="20240504201500 +0000" stop="20240504214500 +0000" channel="ARD.de">
    <title>Tagesschau</title>
  </programme>
</tv>
''';
      final source = _m3uSource(
        MockClient((request) async => _ok(request.url.path.endsWith('.m3u') ? _playlist : foreignIds)),
        epgUrl: 'http://provider/epg.xml',
      );

      final programs = await source.fetchSchedule();

      expect(programs.single.title, 'Tagesschau');
      expect(
        programs.single.channelIdentifier,
        'das-erste.de',
        reason: 'the programme must be keyed on the app channel, not on the guide id it was found under',
      );
    });

    test('the guide is re-read once its cache expires, and then cached again', () async {
      // The regression this guards: stamping only the first read expires the
      // cache permanently, so every later call re-downloads the guide.
      var guideRequests = 0;
      var now = DateTime(2024, 5, 4, 20);
      final source = _m3uSource(
        MockClient((request) async {
          if (request.url.path.endsWith('.m3u')) return _ok(_playlist);
          guideRequests++;
          return _ok(_guide);
        }),
        epgUrl: 'http://provider/epg.xml',
        now: () => now,
      );

      await source.fetchSchedule();
      await source.fetchSchedule();
      expect(guideRequests, 1);

      now = now.add(const Duration(hours: 3));
      await source.fetchSchedule();
      expect(guideRequests, 2);

      await source.fetchSchedule();
      expect(guideRequests, 2, reason: 'the re-read must restart the cache window');
    });

    test('a gzipped guide is unpacked before it is read', () async {
      // Most published XMLTV lists are `.xml.gz`, and a file served as
      // application/gzip arrives packed — nothing in the HTTP layer unpacks
      // it, so reading the bytes as text yields a guide of noise.
      final packed = gzip.encode(utf8.encode(_guide));
      final source = _m3uSource(
        MockClient((request) async {
          if (request.url.path.endsWith('.m3u')) return _ok(_playlist);
          return http.Response.bytes(packed, 200);
        }),
        epgUrl: 'http://provider/epg.xml.gz',
      );

      final programs = await source.fetchSchedule();

      expect(programs.single.title, 'Tagesschau');
    });

    test('a gzipped playlist is unpacked too', () async {
      final source = _m3uSource(MockClient((_) async => http.Response.bytes(gzip.encode(utf8.encode(_playlist)), 200)));

      expect((await source.fetchChannels()).map((c) => c.title), ['Das Erste HD', 'Kein EPG']);
    });

    test('a guide larger than the cap is dropped, the channels stay', () async {
      // A stream address entered as a guide, or a provider gone wrong, would
      // otherwise grow in memory until the app is killed.
      final source = _m3uSource(
        MockClient((request) async {
          if (request.url.path.endsWith('.m3u')) return _ok(_playlist);
          return _ok(_guide + ' ' * 4096);
        }),
        epgUrl: 'http://provider/epg.xml',
        maxResponseBytes: 2048,
      );

      expect((await source.fetchChannels()).map((c) => c.title), ['Das Erste HD', 'Kein EPG']);
      expect(await source.fetchSchedule(), isEmpty);
    });

    test('a gzip bomb stops at the cap instead of unpacking whole', () async {
      // A few kilobytes that unpack to a megabyte: the cap has to hold for
      // the unpacked size, not just for what came over the wire.
      final bomb = gzip.encode(utf8.encode(_guide + ' ' * (1024 * 1024)));
      expect(bomb.length, lessThan(4096));
      final source = _m3uSource(
        MockClient((request) async {
          if (request.url.path.endsWith('.m3u')) return _ok(_playlist);
          return http.Response.bytes(bomb, 200);
        }),
        epgUrl: 'http://provider/epg.xml.gz',
        maxResponseBytes: 64 * 1024,
      );

      expect(await source.fetchSchedule(), isEmpty);
    });

    test('an xz guide is unpacked before it is read', () async {
      // The Rytec lists — the free German guide that reaches a week ahead —
      // are published as `.xz` only.
      final source = _m3uSource(
        MockClient((request) async {
          if (request.url.path.endsWith('.m3u')) return _ok(_playlist);
          return http.Response.bytes(_guideXz, 200);
        }),
        epgUrl: 'http://rytec/rytecDE_Basic.xz',
      );

      expect((await source.fetchSchedule()).single.title, 'Tagesschau');
    });

    test('an xz bomb stops at the cap, and the same file under a larger cap is read', () async {
      expect(_guideXzBomb.length, lessThan(1024));
      IptvLiveTvSource sourceWithCap(int cap) => _m3uSource(
        MockClient((request) async {
          if (request.url.path.endsWith('.m3u')) return _ok(_playlist);
          return http.Response.bytes(_guideXzBomb, 200);
        }),
        epgUrl: 'http://rytec/rytecDE_Basic.xz',
        maxResponseBytes: cap,
      );

      expect(await sourceWithCap(64 * 1024).fetchSchedule(), isEmpty);
      expect((await sourceWithCap(2 * 1024 * 1024).fetchSchedule()).single.title, 'Tagesschau');
    });

    test('a damaged xz guide is skipped, the channels stay', () async {
      final damaged = [..._guideXz.take(40), ...List.filled(40, 0x55)];
      final source = _m3uSource(
        MockClient((request) async {
          if (request.url.path.endsWith('.m3u')) return _ok(_playlist);
          return http.Response.bytes(damaged, 200);
        }),
        epgUrl: 'http://rytec/rytecDE_Basic.xz',
      );

      expect((await source.fetchChannels()).map((c) => c.title), ['Das Erste HD', 'Kein EPG']);
      expect(await source.fetchSchedule(), isEmpty);
    });

    test('a guide under the cap is read as before', () async {
      final packed = gzip.encode(utf8.encode(_guide));
      final source = _m3uSource(
        MockClient((request) async {
          if (request.url.path.endsWith('.m3u')) return _ok(_playlist);
          return http.Response.bytes(packed, 200);
        }),
        epgUrl: 'http://provider/epg.xml.gz',
        // Exactly the larger of the two files: at the cap is still under it.
        maxResponseBytes: math.max(utf8.encode(_guide).length, utf8.encode(_playlist).length),
      );

      expect((await source.fetchSchedule()).single.title, 'Tagesschau');
    });

    test('the start of the last programme is known once the guide is read, never loading it', () async {
      final source = _m3uSource(
        MockClient((request) async => _ok(request.url.path.endsWith('.m3u') ? _playlist : _guide)),
        epgUrl: 'http://provider/epg.xml',
      );
      expect(source.lastProgrammeStart, isNull, reason: 'nothing read yet, and asking does not read');

      await source.fetchSchedule();

      expect(source.lastProgrammeStart, DateTime.utc(2024, 5, 4, 20, 15).millisecondsSinceEpoch ~/ 1000);
    });

    test('without a guide URL there is simply no guide', () async {
      final source = _m3uSource(MockClient((_) async => _ok(_playlist)));

      expect(await source.fetchSchedule(), isEmpty);
    });

    test('a failing playlist yields no channels instead of throwing', () async {
      final source = _m3uSource(MockClient((_) async => http.Response('nope', 500)));

      expect(await source.fetchChannels(), isEmpty);
    });

    test('the playlist is read once and then served from cache', () async {
      var requests = 0;
      final source = _m3uSource(
        MockClient((_) async {
          requests++;
          return _ok(_playlist);
        }),
      );

      await source.fetchChannels();
      await source.fetchChannels();

      expect(requests, 1);
    });

    test('invalidate forces a re-read', () async {
      var requests = 0;
      final source = _m3uSource(
        MockClient((_) async {
          requests++;
          return _ok(_playlist);
        }),
      );

      await source.fetchChannels();
      source.invalidate();
      await source.fetchChannels();

      expect(requests, 2);
    });
  });

  group('hidden channels', () {
    late int playlistRequests;
    late int guideRequests;
    late LiveTvChannelLayout layout;

    MockClient counting() => MockClient((request) async {
      if (request.url.path.endsWith('.m3u')) {
        playlistRequests++;
        return _ok(_twoGroupsPlaylist);
      }
      guideRequests++;
      return _ok(_twoChannelGuide);
    });

    IptvLiveTvSource source({IptvDiskCache? diskCache}) => _m3uSource(
      counting(),
      epgUrl: 'http://provider/epg.xml',
      diskCache: diskCache,
      diskCacheMaxAge: () => const Duration(days: 3),
      layout: () => layout,
    );

    setUp(() {
      playlistRequests = 0;
      guideRequests = 0;
      layout = LiveTvChannelLayout.empty;
    });

    test('the guide is read only for the channels left showing', () async {
      layout = _hideSecondGroup;
      final iptv = source();
      addTearDown(iptv.close);

      expect((await iptv.fetchSchedule()).map((p) => p.title), ['Tagesschau']);
      expect(await iptv.fetchChannels(), hasLength(2), reason: 'the playlist stays whole: hidden is not gone');
    });

    test('hiding more narrows the guide without a download', () async {
      final iptv = source();
      addTearDown(iptv.close);
      expect(await iptv.fetchSchedule(), hasLength(2));

      layout = _hideSecondGroup;
      expect((await iptv.fetchSchedule()).map((p) => p.title), ['Tagesschau']);
      expect(guideRequests, 1);
    });

    test('a channel shown again has its guide read again, and only the guide', () async {
      layout = _hideSecondGroup;
      final iptv = source();
      addTearDown(iptv.close);
      expect(await iptv.fetchSchedule(), hasLength(1));

      layout = LiveTvChannelLayout.empty;
      expect((await iptv.fetchSchedule()).map((p) => p.title).toSet(), {'Tagesschau', 'heute'});
      expect(guideRequests, 2);
      expect(playlistRequests, 1);
    });

    test('what the stored guide was read for survives a restart', () async {
      final root = await Directory.systemTemp.createTemp('iptv_hidden_cache');
      addTearDown(() => root.delete(recursive: true));
      final cache = IptvDiskCache(directoryProvider: () async => root);

      layout = _hideSecondGroup;
      final first = source(diskCache: cache);
      await first.fetchSchedule();
      await first.pendingDiskWrite;
      first.close();

      final second = source(diskCache: cache);
      expect(await second.fetchSchedule(), hasLength(1));
      await second.pendingDiskWrite;
      second.close();
      expect((playlistRequests, guideRequests), (1, 1), reason: 'the same arrangement reads from disk');

      layout = LiveTvChannelLayout.empty;
      final third = source(diskCache: cache);
      expect(await third.fetchSchedule(), hasLength(2));
      await third.pendingDiskWrite;
      third.close();
      expect((playlistRequests, guideRequests), (1, 2), reason: 'a group shown again reads the guide, not the list');
    });

    test('a panel without XMLTV asks for the channels showing, not the first ones listed', () async {
      final asked = <String>[];
      final iptv = _xtreamSource(
        MockClient((request) async {
          final action = request.url.queryParameters['action'];
          return switch (action) {
            'get_live_categories' => _okJson([
              {'category_id': '1', 'category_name': 'Ausgeblendet'},
              {'category_id': '2', 'category_name': 'Vollprogramm'},
            ]),
            'get_live_streams' => _okJson([
              {'stream_id': 1, 'name': 'Versteckt', 'num': 1, 'category_id': '1'},
              {'stream_id': 2, 'name': 'Das Erste HD', 'num': 2, 'category_id': '2'},
            ]),
            'get_short_epg' => () {
              asked.add(request.url.queryParameters['stream_id']!);
              return _okJson({'epg_listings': const []});
            }(),
            _ => _okJson({'user_info': {}}),
          };
        }),
        layout: () => _hideSecondGroup,
      );
      addTearDown(iptv.close);

      await iptv.fetchSchedule();

      expect(asked, ['2']);
    });
  });

  group('logos from the guide', () {
    const playlist = '''
#EXTM3U
#EXTINF:-1 tvg-id="sky-mix",Sky Sport Mix
http://provider/stream/sky
#EXTINF:-1 tvg-id="das-erste.de" tvg-logo="http://playlist/ard.png",Das Erste HD
http://provider/stream/ard
''';
    const guide = '''
<tv>
  <channel id="sky-mix"><display-name>Sky Sport Mix</display-name><icon src="http://guide/sky-mix.png"/></channel>
  <channel id="das-erste.de"><display-name>Das Erste</display-name><icon src="http://guide/ard.png"/></channel>
  <programme start="20240504201500 +0000" stop="20240504214500 +0000" channel="sky-mix"><title>Bundesliga</title></programme>
</tv>
''';

    IptvLiveTvSource source({IptvDiskCache? diskCache, void Function()? learned}) => IptvLiveTvSource(
      const IptvSource(
        id: 'src',
        name: 'Mein IPTV',
        kind: IptvSourceKind.m3u,
        playlistUrl: 'http://provider/list.m3u',
        epgUrls: ['http://provider/epg.xml'],
      ),
      httpClient: MockClient((request) async => _ok(request.url.path.endsWith('.m3u') ? playlist : guide)),
      favorites: _MemoryFavorites(),
      diskCache: diskCache,
      diskCacheMaxAge: () => const Duration(days: 3),
      onLogosLearned: learned,
    );

    String? logoOf(List<LiveTvChannel> channels, String name) => channels.firstWhere((c) => c.title == name).thumb;

    test('a channel without a logo takes the one the guide names; one with a logo keeps its own', () async {
      var learned = 0;
      final iptv = source(learned: () => learned++);
      addTearDown(iptv.close);

      expect(logoOf(await iptv.fetchChannels(), 'Sky Sport Mix'), isNull, reason: 'the guide is not read yet');
      await iptv.fetchSchedule();
      final channels = await iptv.fetchChannels();

      expect(logoOf(channels, 'Sky Sport Mix'), 'http://guide/sky-mix.png');
      expect(logoOf(channels, 'Das Erste HD'), 'http://playlist/ard.png');
      expect(
        channels.firstWhere((c) => c.title == 'Das Erste HD').guideLogo,
        'http://guide/ard.png',
        reason: 'the one to try where the playlist\'s own does not load',
      );
      expect(learned, 1, reason: 'the screen showing the channels is told once');

      await iptv.fetchSchedule();
      expect(learned, 1, reason: 'nothing new, nothing to tell');
    });

    test('a guide stored before logos were read from guides is read once more, the playlist is not', () async {
      final root = await Directory.systemTemp.createTemp('iptv_old_cache');
      addTearDown(() => root.delete(recursive: true));
      final cache = IptvDiskCache(directoryProvider: () async => root);
      final first = source(diskCache: cache);
      final channels = await first.fetchChannels();
      await first.pendingDiskWrite;
      first.close();
      // What an earlier build stored: a guide, and no word on logos.
      await cache.write(
        'src',
        IptvCacheEntry(
          savedAt: DateTime.now(),
          channels: channels,
          programs: [LiveTvProgram(title: 'Alt', beginsAt: 1, endsAt: 2, channelIdentifier: 'sky-mix')],
        ),
      );

      final paths = <String>[];
      final second = IptvLiveTvSource(
        const IptvSource(
          id: 'src',
          name: 'Mein IPTV',
          kind: IptvSourceKind.m3u,
          playlistUrl: 'http://provider/list.m3u',
          epgUrls: ['http://provider/epg.xml'],
        ),
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          return _ok(request.url.path.endsWith('.m3u') ? playlist : guide);
        }),
        favorites: _MemoryFavorites(),
        diskCache: cache,
        diskCacheMaxAge: () => const Duration(days: 3),
      );
      addTearDown(second.close);

      expect((await second.fetchSchedule()).single.title, 'Bundesliga');
      expect(logoOf(await second.fetchChannels(), 'Sky Sport Mix'), 'http://guide/sky-mix.png');
      expect(paths, ['/epg.xml']);
      await second.pendingDiskWrite;
    });

    test('the logos come back with the stored copy', () async {
      final root = await Directory.systemTemp.createTemp('iptv_logo_cache');
      addTearDown(() => root.delete(recursive: true));
      final cache = IptvDiskCache(directoryProvider: () async => root);

      final first = source(diskCache: cache);
      await first.fetchSchedule();
      await first.pendingDiskWrite;
      first.close();

      final second = source(diskCache: cache);
      expect(logoOf(await second.fetchChannels(), 'Sky Sport Mix'), 'http://guide/sky-mix.png');
      await second.pendingDiskWrite;
      second.close();
    });
  });

  group('Xtream', () {
    MockClient panel({List<Object>? streams, List<Object>? epg}) => MockClient((request) async {
      final action = request.url.queryParameters['action'];
      return switch (action) {
        'get_live_categories' => _okJson([
          {'category_id': '5', 'category_name': 'Vollprogramm'},
        ]),
        'get_live_streams' => _okJson(
          streams ??
              [
                {'stream_id': 1234, 'name': 'Das Erste HD', 'num': 1, 'category_id': '5'},
              ],
        ),
        'get_short_epg' => _okJson({'epg_listings': epg ?? const []}),
        _ => _okJson({'user_info': {}}),
      };
    });

    test('lists the panel channels with their category', () async {
      final source = _xtreamSource(panel());

      final channels = await source.fetchChannels();

      expect(channels.single.title, 'Das Erste HD');
      expect(channels.single.lineup, 'Vollprogramm');
      expect(channels.single.key, 'iptv:src:1234');
    });

    test('builds the stream URL from the credentials, in the chosen container', () async {
      final source = _xtreamSource(panel());
      final channels = await source.fetchChannels();

      final session = await source.startPlayback(channels.single.key);

      // The transport stream is what most panels serve reliably, and what the
      // player can hand to its extractor without being told it is a playlist.
      expect(await session!.streamUrlAt(), 'http://panel:8080/live/u/p/1234.ts');
    });

    test('the panel guide is read whole from xmltv.php, not channel by channel', () async {
      // get_short_epg is one request per channel and therefore capped; the
      // XMLTV endpoint is the only way a panel's full guide arrives.
      var shortEpgRequests = 0;
      final source = _xtreamSource(
        MockClient((request) async {
          if (request.url.path.endsWith('xmltv.php')) {
            return _ok('''
<tv>
  <programme start="20240504201500 +0000" stop="20240504214500 +0000" channel="ard">
    <title>Tagesschau</title>
  </programme>
</tv>
''');
          }
          return switch (request.url.queryParameters['action']) {
            'get_live_categories' => _okJson(const []),
            'get_live_streams' => _okJson([
              {'stream_id': 1234, 'name': 'Das Erste HD', 'epg_channel_id': 'ard', 'num': 1},
            ]),
            'get_short_epg' => () {
              shortEpgRequests++;
              return _okJson({'epg_listings': const []});
            }(),
            _ => _okJson({'user_info': {}}),
          };
        }),
      );

      final programs = await source.fetchSchedule();

      expect(programs.single.title, 'Tagesschau');
      expect(shortEpgRequests, 0);
    });

    test('a panel without an XMLTV endpoint still gets its per-channel guide', () async {
      final source = _xtreamSource(
        panel(
          epg: [
            {'title': 'VGFnZXNzY2hhdQ==', 'start_timestamp': 1714853700, 'stop_timestamp': 1714859100},
          ],
        ),
      );

      final programs = await source.fetchSchedule();

      expect(programs.single.title, 'Tagesschau');
    });

    test('reads the guide out of the epg_listings envelope', () async {
      // The trap: get_short_epg wraps its rows in an object, while the other
      // actions return bare arrays.
      final source = _xtreamSource(
        panel(
          epg: [
            {'title': 'VGFnZXNzY2hhdQ==', 'start_timestamp': 100, 'stop_timestamp': 200},
          ],
        ),
      );

      final programs = await source.fetchSchedule();

      expect(programs, hasLength(1));
      expect(programs.single.title, 'Tagesschau');
    });

    test('a panel that rejects the credentials yields no channels', () async {
      final source = _xtreamSource(
        MockClient(
          (_) async => _okJson({
            'user_info': {'auth': 0},
          }),
        ),
      );

      expect(await source.fetchChannels(), isEmpty);
    });
  });

  group('playback session', () {
    test('cannot time-shift, and refuses an offset rather than jumping to live', () async {
      final source = _m3uSource(MockClient((_) async => _ok(_playlist)));
      final channels = await source.fetchChannels();
      final session = (await source.startPlayback(channels.first.key))!;

      expect(session.canTimeShift, isFalse);
      expect(await session.streamUrlAt(offsetSeconds: 60), isNull);
      expect(session.captureBuffer, isNull);
      expect(session.subtitleTracks, isEmpty);
    });

    test('recovery re-opens the same URL', () async {
      final source = _m3uSource(MockClient((_) async => _ok(_playlist)));
      final channels = await source.fetchChannels();
      final session = (await source.startPlayback(channels.first.key))!;

      final recovered = await session.recover(directStream: true, directStreamAudio: true);

      expect(await recovered!.streamUrlAt(), 'http://provider/stream/ard');
    });
  });

  group('capabilities', () {
    test('offers no recording, because nothing here can record', () {
      expect(_m3uSource(MockClient((_) async => _ok(''))).dvr, isNull);
    });

    test('is available only once configured', () async {
      expect(await _m3uSource(MockClient((_) async => _ok(''))).isAvailable(), isTrue);
      expect(
        await IptvLiveTvSource(
          const IptvSource(id: 'x', name: 'X', kind: IptvSourceKind.m3u),
          httpClient: MockClient((_) async => _ok('')),
        ).isAvailable(),
        isFalse,
      );
    });

    test('favorites are stored per source', () async {
      final favorites = _MemoryFavorites();
      final source = _m3uSource(MockClient((_) async => _ok(_playlist)), favorites: favorites);

      await source.setFavoriteChannels([FavoriteChannel(source: 'iptv://src', id: 'iptv:src:das-erste.de')]);

      expect(favorites.stored['iptv:src'], hasLength(1));
      expect(await source.fetchFavoriteChannels(), hasLength(1));
    });
  });

  group('catch-up', () {
    final fixedNow = DateTime(2026, 8, 30, 22, 0);

    test('a channel with no archive gets no seekable window', () async {
      final source = _m3uSource(MockClient((request) async => _ok(_playlist)));
      addTearDown(source.close);
      final channels = await source.fetchChannels();

      final session = await source.startPlayback(channels.first.key);

      expect(session!.canTimeShift, isFalse);
      expect(session.captureBuffer, isNull);
      // A refusal, not a silent jump to the live edge.
      expect(await session.streamUrlAt(offsetSeconds: 60), isNull);
    });

    test("a playlist's declared archive becomes a window the player can seek", () async {
      final source = _m3uSource(MockClient((request) async => _ok(_catchupPlaylist)), now: () => fixedNow);
      addTearDown(source.close);
      final channels = await source.fetchChannels();
      expect(channels.single.catchupDays, 5);

      final session = await source.startPlayback(channels.single.key);

      expect(session!.canTimeShift, isTrue);
      final buffer = session.captureBuffer!;
      expect(buffer.seekableStartEpoch, fixedNow.subtract(const Duration(days: 5)).millisecondsSinceEpoch ~/ 1000);
      expect(buffer.seekableEndEpoch, fixedNow.millisecondsSinceEpoch ~/ 1000);
    });

    test('an offset into the window builds the provider\'s archive URL', () async {
      final source = _m3uSource(MockClient((request) async => _ok(_catchupPlaylist)), now: () => fixedNow);
      addTearDown(source.close);
      final channels = await source.fetchChannels();
      final session = await source.startPlayback(channels.single.key);
      final buffer = session!.captureBuffer!;

      // Yesterday evening, addressed from the window's origin the way the
      // player addresses a seek.
      final target = fixedNow.subtract(const Duration(days: 1));
      final offset = (target.millisecondsSinceEpoch ~/ 1000) - buffer.startedAt.round();

      final url = await session.streamUrlAt(offsetSeconds: offset);

      expect(url, startsWith('http://provider/stream/ard?utc='));
      expect(url, contains('${target.millisecondsSinceEpoch ~/ 1000}'));
    });

    test('the live edge is still just the live URL', () async {
      final source = _m3uSource(MockClient((request) async => _ok(_catchupPlaylist)), now: () => fixedNow);
      addTearDown(source.close);
      final channels = await source.fetchChannels();
      final session = await source.startPlayback(channels.single.key);

      expect(await session!.streamUrlAt(), 'http://provider/stream/ard');
    });

    test('an archive never prompts to watch from start', () async {
      // It is there on every channel at every hour; asking each time would put
      // a dialog in front of every tune.
      final source = _m3uSource(MockClient((request) async => _ok(_catchupPlaylist)), now: () => fixedNow);
      addTearDown(source.close);
      final channels = await source.fetchChannels();

      final session = await source.startPlayback(channels.single.key);

      expect(session!.promptsWatchFromStart, isFalse);
    });

    test('a panel that reports an archive is addressed the Xtream way', () async {
      final source = _xtreamCatchupSource(
        MockClient((request) async {
          if (request.url.queryParameters['action'] == 'get_live_categories') return _ok('[]');
          if (request.url.queryParameters['action'] == 'get_live_streams') {
            return _ok('[{"stream_id":42,"name":"ARD","tv_archive":1,"tv_archive_duration":7}]');
          }
          return _ok('[]');
        }),
        now: () => fixedNow,
      );
      addTearDown(source.close);
      final channels = await source.fetchChannels();
      expect(channels.single.catchupDays, 7);

      final session = await source.startPlayback(channels.single.key);
      final buffer = session!.captureBuffer!;
      final target = DateTime(2026, 8, 29, 20, 15);
      final offset = (target.millisecondsSinceEpoch ~/ 1000) - buffer.startedAt.round();

      final url = await session.streamUrlAt(offsetSeconds: offset);

      expect(url, startsWith('http://panel:8080/timeshift/u/p/'));
      expect(url, contains('/2026-08-29:20-15/42.ts'));
    });

    test('a running programme is only asked for the part that has happened', () async {
      // Starting one over used to ask the panel for the whole slot — ninety
      // minutes of which twenty existed — and a panel answers that with an
      // error rather than with the twenty.
      final start = fixedNow.subtract(const Duration(minutes: 20));
      final source = _xtreamCatchupSource(
        MockClient((request) async {
          if (request.url.queryParameters['action'] == 'get_live_streams') {
            return _ok('[{"stream_id":42,"name":"ARD","tv_archive":1,"tv_archive_duration":7}]');
          }
          return _ok('[]');
        }),
        now: () => fixedNow,
      );
      addTearDown(source.close);
      final channels = await source.fetchChannels();

      final session = await source.startPlayback(channels.single.key);
      final buffer = session!.captureBuffer!;
      final offset = (start.millisecondsSinceEpoch ~/ 1000) - buffer.startedAt.round();

      final url = await session.streamUrlAt(offsetSeconds: offset);

      // The minutes segment of `/timeshift/u/p/{minutes}/{stamp}/{id}.ts`.
      final minutes = int.parse(Uri.parse(url!).pathSegments[3]);
      expect(minutes, lessThanOrEqualTo(20), reason: 'never more archive than exists');
      expect(minutes, greaterThan(0));
    });

    test('a finished programme still gets its whole length', () async {
      // The clamp must bite only where the end lies ahead: an hour that ended
      // yesterday exists in full.
      final source = _xtreamCatchupSource(
        MockClient((request) async {
          if (request.url.queryParameters['action'] == 'get_live_streams') {
            return _ok('[{"stream_id":42,"name":"ARD","tv_archive":1,"tv_archive_duration":7}]');
          }
          return _ok('[]');
        }),
        now: () => fixedNow,
      );
      addTearDown(source.close);
      final channels = await source.fetchChannels();

      final session = await source.startPlayback(channels.single.key);
      final buffer = session!.captureBuffer!;
      final target = fixedNow.subtract(const Duration(days: 1));
      final offset = (target.millisecondsSinceEpoch ~/ 1000) - buffer.startedAt.round();

      final url = await session.streamUrlAt(offsetSeconds: offset);

      // No guide here, so the two-hour fallback stands — undamaged, because
      // yesterday's two hours have all happened.
      expect(int.parse(Uri.parse(url!).pathSegments[3]), 120);
    });

    test('the switch to another copy keeps the archive', () async {
      final source = _m3uSource(
        MockClient((request) async => _ok(request.url.path.endsWith('.m3u') ? _repeatedPlaylist : _guide)),
        mergeDuplicates: true,
        now: () => fixedNow,
      );
      addTearDown(source.close);
      final channels = await source.fetchChannels();
      final session = await source.startPlayback(channels.first.key);
      // The merged playlist declares no archive, so this one has none either
      // way; what matters is that switching does not invent one or drop one.
      final second = await session!.switchVariant(1);

      expect(second!.canTimeShift, session.canTimeShift);
    });
  });
}
