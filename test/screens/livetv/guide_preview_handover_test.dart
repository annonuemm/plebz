import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/models/livetv_channel.dart';
import 'package:plezy/mpv/mpv.dart';
import 'package:plezy/mpv/player/video_rect_support.dart';
import 'package:plezy/screens/livetv/guide_preview_player.dart';
import 'package:plezy/services/iptv/iptv_live_tv_source.dart';
import 'package:plezy/services/live_picture_handover.dart';
import 'package:plezy/widgets/video_surface_hole.dart';

/// A playing picture whose output can leave its texture, as both Android
/// backends' can; just enough of a player for the preview box to draw it.
class _PicturePlayer implements Player, VideoOutputHandover, VideoTextureTarget {
  bool _disposed = false;

  @override
  bool get disposed => _disposed;

  @override
  Future<void> dispose({bool preserveDisplayMode = false}) async => _disposed = true;

  @override
  bool get rendersToTexture => true;

  @override
  final ValueListenable<int?> videoTextureId = ValueNotifier<int?>(null);

  @override
  late final PlayerStreams streams = PlayerStreams(
    playing: const Stream.empty(),
    completed: const Stream.empty(),
    buffering: const Stream.empty(),
    position: const Stream.empty(),
    duration: const Stream.empty(),
    seekable: const Stream.empty(),
    buffer: const Stream.empty(),
    volume: const Stream.empty(),
    rate: const Stream.empty(),
    tracks: const Stream.empty(),
    track: const Stream.empty(),
    log: const Stream.empty(),
    error: const Stream.empty(),
    audioDevice: const Stream.empty(),
    audioDevices: const Stream.empty(),
    bufferRanges: const Stream.empty(),
    playbackRestart: const Stream.empty(),
    fileStarted: const Stream.empty(),
    fileLoaded: const Stream.empty(),
    fileLoadFailed: const Stream.empty(),
    primaryMediaReady: const Stream.empty(),
    backendSwitched: const Stream.empty(),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The same picture on the video plane, in a box behind the guide.
class _PlanePicturePlayer extends _PicturePlayer implements VideoViewportTarget {
  @override
  bool get rendersToTexture => false;

  @override
  bool get followsVideoRect => true;

  @override
  bool videoRectDriven = false;

  @override
  Future<void> driveVideoRect({required int left, required int top, required int right, required int bottom}) async {}
}

final _channel = LiveTvChannel(key: 'iptv-1', identifier: 'das-erste', callSign: 'Das Erste HD');

LivePictureHandover _picture(Player player, {LiveTvChannel? channel}) => LivePictureHandover(
  player: player,
  session: IptvPlaybackSession(variants: const [(url: 'http://provider.test/live/1.ts', headers: {}, label: 'A')]),
  channel: channel ?? _channel,
);

void main() {
  final previewKey = GlobalKey<GuidePreviewPlayerState>();

  Future<void> pumpPreview(WidgetTester tester, LiveTvChannel? channel) => tester.pumpWidget(
    MaterialApp(
      home: SizedBox(
        width: 320,
        height: 180,
        child: GuidePreviewPlayer(key: previewKey, channel: channel),
      ),
    ),
  );

  testWidgets('a picture given back plays on in the box once the guide shows its channel', (tester) async {
    final player = _PicturePlayer();
    await pumpPreview(tester, null);

    previewKey.currentState!.adopt(_picture(player));
    await pumpPreview(tester, _channel);

    expect(previewKey.currentState!.isHoldingStream, isTrue);
    expect(find.byType(Video), findsOneWidget);
    expect(player.disposed, isFalse);
  });

  testWidgets('the box hands its picture over without stopping it, and keeps drawing it until covered', (tester) async {
    final player = _PicturePlayer();
    await pumpPreview(tester, null);
    previewKey.currentState!.adopt(_picture(player));
    await pumpPreview(tester, _channel);

    final handover = previewKey.currentState!.releaseForHandover();
    await tester.pump();

    expect(handover?.player, same(player));
    expect(previewKey.currentState!.isHoldingStream, isFalse);
    expect(find.byType(Video), findsOneWidget, reason: "the player route's first frame is offstage");

    // Covered by the growing player a few frames on: no second live picture
    // to composite through the growth.
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byType(Video), findsNothing);
    expect(player.disposed, isFalse);

    // The player covers the guide, which takes the channel out of the box:
    // the picture is the full-screen player's now, not the box's to stop.
    await pumpPreview(tester, null);
    expect(find.byType(Video), findsNothing);
    expect(player.disposed, isFalse);
  });

  testWidgets('a picture on the plane plays through a hole, at once, and can be handed on', (tester) async {
    final player = _PlanePicturePlayer();
    await pumpPreview(tester, null);
    previewKey.currentState!.adopt(_picture(player));
    await pumpPreview(tester, _channel);

    expect(find.byType(VideoSurfaceHole), findsOneWidget);
    // Back from full screen it is playing already: no black wait for a first frame.
    final video = tester.widget<Video>(find.byType(Video));
    expect(video.hasFirstFrame?.value, isTrue);

    expect(previewKey.currentState!.releaseForHandover()?.player, same(player));
    await tester.pump(const Duration(milliseconds: 150));
  });

  testWidgets('a picture waiting for its channel is stopped when another replaces it or the box goes', (tester) async {
    final first = _PicturePlayer();
    final second = _PicturePlayer();
    await pumpPreview(tester, null);

    previewKey.currentState!.adopt(_picture(first));
    previewKey.currentState!.adopt(_picture(second));
    await tester.pump();
    expect(first.disposed, isTrue);
    expect(second.disposed, isFalse);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(second.disposed, isTrue);
  });
}
