import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/models/livetv_channel.dart';
import 'package:plezy/models/livetv_program.dart';
import 'package:plezy/services/iptv/iptv_disk_cache.dart';

/// A playlist and a guide are expensive to fetch and slow to parse, and
/// neither changes by the hour — so they outlive the app session. What is
/// stored has to come back complete: a channel without its stream address is
/// a name nothing can play.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late IptvDiskCache cache;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('iptv_cache_test');
    cache = IptvDiskCache(directoryProvider: () async => root);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  IptvCacheEntry entry({DateTime? savedAt}) => IptvCacheEntry(
    savedAt: savedAt ?? DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000),
    channels: [
      LiveTvChannel(
        key: 'iptv:src:das-erste.de',
        identifier: 'das-erste.de',
        title: 'Das Erste HD',
        thumb: 'http://provider/logo.png',
        number: '1',
        hd: true,
        serverId: 'src',
        serverName: 'Mein IPTV',
        liveTvSourceTitle: 'Mein IPTV',
      ),
    ],
    programs: [
      LiveTvProgram(
        title: 'Tagesschau',
        summary: 'Nachrichten',
        beginsAt: 1_800_000_000,
        endsAt: 1_800_003_600,
        channelIdentifier: 'das-erste.de',
        serverId: 'src',
        serverName: 'Mein IPTV',
      ),
    ],
    streamUrls: {'iptv:src:das-erste.de': 'http://provider/stream/ard'},
    streamHeaders: {
      'iptv:src:das-erste.de': {'User-Agent': 'Plebz'},
    },
  );

  test('a source comes back whole, stream addresses included', () async {
    await cache.write('src', entry());

    final restored = await cache.read('src');

    expect(restored, isNotNull);
    expect(restored!.savedAt, entry().savedAt);

    final channel = restored.channels.single;
    expect(channel.key, 'iptv:src:das-erste.de');
    expect(channel.title, 'Das Erste HD');
    expect(channel.number, '1');
    expect(channel.hd, isTrue);
    // Set after parsing, and the reason a restored channel knows where it
    // came from.
    expect(channel.serverId, 'src');
    expect(channel.serverName, 'Mein IPTV');
    expect(channel.liveTvSourceTitle, 'Mein IPTV');

    final program = restored.programs.single;
    expect(program.title, 'Tagesschau');
    expect(program.summary, 'Nachrichten');
    expect(program.beginsAt, 1_800_000_000);
    expect(program.channelIdentifier, 'das-erste.de');
    expect(program.serverId, 'src');

    // The channel key is derived from the playlist entry, not from its URL,
    // so without this the restored list would play nothing.
    expect(restored.streamUrls['iptv:src:das-erste.de'], 'http://provider/stream/ard');
    expect(restored.streamHeaders['iptv:src:das-erste.de'], {'User-Agent': 'Plebz'});
  });

  test('nothing stored is a miss, not a failure', () async {
    expect(await cache.read('never-written'), isNull);
  });

  test('a damaged file is a miss too', () async {
    await cache.write('src', entry());
    final file = File('${root.path}/iptv_cache/src.json');
    await file.writeAsString('{not json');

    expect(await cache.read('src'), isNull);
  });

  test('clearing removes the stored copy', () async {
    await cache.write('src', entry());
    expect(await cache.read('src'), isNotNull);

    await cache.clear('src');

    expect(await cache.read('src'), isNull);
  });

  test('an empty source is not written at all', () async {
    await cache.write('src', IptvCacheEntry(savedAt: DateTime.now(), channels: const [], programs: const []));

    expect(await cache.read('src'), isNull);
  });
}
