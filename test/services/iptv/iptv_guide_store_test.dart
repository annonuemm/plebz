import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/models/livetv_program.dart';
import 'package:plezy/services/iptv/iptv_guide_database.dart';
import 'package:plezy/services/iptv/iptv_guide_store.dart';

LiveTvProgram _program(String channel, int begins, int ends, {String? title}) => LiveTvProgram(
  key: 'iptv:$channel:$begins',
  title: title ?? '$channel@$begins',
  subtitle: 'Folge',
  genres: const ['Nachrichten', 'Politik'],
  beginsAt: begins,
  endsAt: ends,
  index: 3,
  parentIndex: 2,
  channelIdentifier: channel,
  channelCallSign: channel.toUpperCase(),
  serverId: 'iptv:src',
  serverName: 'Mein IPTV',
);

void main() {
  late IptvGuideDatabase db;
  late DriftIptvGuideStore store;

  setUp(() {
    db = IptvGuideDatabase(NativeDatabase.memory());
    store = DriftIptvGuideStore(db);
  });

  tearDown(() => db.close());

  Future<IptvGuideState> write(List<LiveTvProgram> programs, {Set<String>? coverage, String source = 'src'}) async {
    final writer = await store.begin(source);
    await writer.add(programs);
    return writer.commit(fetchedAt: DateTime(2026, 10, 8, 12), coverage: coverage);
  }

  test('a programme comes back as it went in', () async {
    final state = await write([_program('ard', 100, 200)], coverage: {'iptv:ard'});

    final back = (await store.window('src', state.generation)).single;
    expect(back.key, 'iptv:ard:100');
    expect(back.title, 'ard@100');
    expect(back.subtitle, 'Folge');
    expect(back.genres, ['Nachrichten', 'Politik']);
    expect((back.beginsAt, back.endsAt, back.index, back.parentIndex), (100, 200, 3, 2));
    expect((back.channelIdentifier, back.channelCallSign, back.serverId), ('ard', 'ARD', 'iptv:src'));

    final kept = await store.state('src');
    expect(kept?.generation, state.generation);
    expect(kept?.coverage, {'iptv:ard'});
    expect(kept?.lastStart, 100);
    expect(kept?.fetchedAt, DateTime(2026, 10, 8, 12));
  });

  test('a window holds what runs into it, by start, on the channels asked for', () async {
    final state = await write([
      _program('zdf', 300, 400),
      _program('ard', 100, 200),
      _program('ard', 200, 300),
      _program('ard', 400, 500),
    ]);

    final window = await store.window('src', state.generation, from: 250, to: 350);
    expect(window.map((p) => p.title), ['ard@200', 'zdf@300'], reason: 'one already running, one starting');

    final ardOnly = await store.window('src', state.generation, from: 0, to: 1000, channels: {'ard'});
    expect(ardOnly.map((p) => p.title), ['ard@100', 'ard@200', 'ard@400']);
  });

  test('a guide being read again leaves the old one in place until it is committed', () async {
    final first = await write([_program('ard', 100, 200, title: 'alt')]);

    final writer = await store.begin('src');
    await writer.add([_program('ard', 100, 200, title: 'neu')]);
    expect((await store.state('src'))?.generation, first.generation);
    expect((await store.window('src', first.generation)).map((p) => p.title), ['alt']);

    final second = await writer.commit(fetchedAt: DateTime(2026, 10, 9));
    expect((await store.window('src', second.generation)).map((p) => p.title), ['neu']);
    expect(await store.window('src', first.generation), isEmpty, reason: 'the old generation is gone');
  });

  test('an abandoned read leaves nothing behind, and the old guide stands', () async {
    final first = await write([_program('ard', 100, 200, title: 'alt')]);

    final writer = await store.begin('src');
    await writer.add([_program('ard', 100, 200, title: 'neu')]);
    await writer.abandon();

    expect((await store.state('src'))?.generation, first.generation);
    expect((await store.window('src', first.generation)).map((p) => p.title), ['alt']);
    expect(await db.select(db.guidePrograms).get(), hasLength(1));
  });

  test('sources keep apart, and clearing one leaves the other', () async {
    final a = await write([_program('ard', 100, 200)], source: 'a');
    final b = await write([_program('zdf', 100, 200)], source: 'b');

    await store.clear('a');

    expect(await store.state('a'), isNull);
    expect(await store.window('a', a.generation), isEmpty);
    expect((await store.window('b', b.generation)).single.channelIdentifier, 'zdf');
  });

  test('a programme filed under no channel stays whatever the channels asked for', () async {
    final state = await write([
      LiveTvProgram(title: 'ohne Kennung', beginsAt: 100, endsAt: 200),
      _program('ard', 100, 200),
    ]);

    final window = await store.window('src', state.generation, channels: {'zdf'});
    expect(window.single.title, 'ohne Kennung');
    expect(window.single.channelIdentifier, isNull);
  });

  test('the in-memory store answers the same', () async {
    final memory = MemoryIptvGuideStore();
    final writer = await memory.begin('src');
    await writer.add([_program('zdf', 300, 400), _program('ard', 200, 300), _program('ard', 400, 500)]);
    final state = await writer.commit(fetchedAt: DateTime(2026, 10, 8), coverage: {'x'});

    final window = await memory.window('src', state.generation, from: 250, to: 350);
    expect(window.map((p) => p.title), ['ard@200', 'zdf@300']);
    expect(state.lastStart, 400);
  });
}
