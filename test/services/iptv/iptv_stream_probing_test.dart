import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/live_tv_support.dart';
import 'package:plezy/mpv/mpv.dart';
import 'package:plezy/services/iptv/iptv_live_tv_source.dart';
import 'package:plezy/services/iptv/iptv_stream_probing.dart';

class _RecordingPlayer implements Player {
  _RecordingPlayer({this.refuse = false});

  final bool refuse;
  final Map<String, String> written = {};

  @override
  Future<void> setProperty(String name, String value) async {
    if (refuse) throw StateError('property refused');
    written[name] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ServerSession implements LiveTvPlaybackSession {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

IptvPlaybackSession _iptvSession() =>
    IptvPlaybackSession(variants: const [(url: 'http://provider.test/live/1.ts', headers: {}, label: 'A')]);

void main() {
  test('an IPTV stream is studied for 1.5 s instead of FFmpeg\'s seven', () async {
    final player = _RecordingPlayer();

    await applyLiveStreamProbing(player, _iptvSession());

    expect(player.written['demuxer-lavf-analyzeduration'], '1.5');
  });

  test("a server's live stream, or none yet, gets mpv's own default back", () async {
    final player = _RecordingPlayer();

    await applyLiveStreamProbing(player, _iptvSession());
    await applyLiveStreamProbing(player, _ServerSession());
    expect(player.written['demuxer-lavf-analyzeduration'], '0');

    await applyLiveStreamProbing(player, _iptvSession());
    await applyLiveStreamProbing(player, null);
    expect(player.written['demuxer-lavf-analyzeduration'], '0');
  });

  test('a refused write does not stop the stream from opening', () async {
    await expectLater(applyLiveStreamProbing(_RecordingPlayer(refuse: true), _iptvSession()), completes);
  });
}
