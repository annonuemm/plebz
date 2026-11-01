import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/models/livetv_channel.dart';
import 'package:plezy/mpv/mpv.dart';
import 'package:plezy/mpv/player/video_rect_support.dart';
import 'package:plezy/screens/livetv/guide_preview_panel.dart';
import 'package:plezy/screens/livetv/guide_preview_player.dart';
import 'package:plezy/services/iptv/iptv_live_tv_source.dart';
import 'package:plezy/services/live_picture_handover.dart';
import 'package:plezy/services/live_variant_fallback.dart';
import 'package:plezy/widgets/overlay_sheet.dart';
import 'package:plezy/widgets/video_surface_hole.dart';

import '../../test_helpers/theme.dart';

/// A playing picture in a texture on one of the Android backends, both of
/// which can also place their picture on the video plane; just enough of a
/// player for the preview box to draw it.
class _PicturePlayer implements Player, VideoViewportTarget, VideoTextureTarget {
  bool _disposed = false;

  @override
  bool get disposed => _disposed;

  @override
  Future<void> dispose({bool preserveDisplayMode = false}) async => _disposed = true;

  @override
  bool get followsVideoRect => false;

  @override
  bool videoRectDriven = false;

  @override
  Future<void> driveVideoRect({required int left, required int top, required int right, required int bottom}) async {}

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
class _PlanePicturePlayer extends _PicturePlayer {
  @override
  bool get followsVideoRect => true;
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

  testWidgets('the band offers a merged channel\'s copies beside full screen and keeps to the one picked', (
    tester,
  ) async {
    LiveCopyMemory.resetForTest();
    addTearDown(LiveCopyMemory.resetForTest);
    final copies = ValueNotifier<GuideLiveCopies?>(null);
    addTearDown(copies.dispose);

    Future<void> pumpBand(LiveTvChannel? channel) => tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [testMonoTokens]),
        home: OverlaySheetHost(
          child: Scaffold(
            body: SizedBox(
              width: 360,
              height: 202,
              child: GuidePreviewBand(
                playerKey: previewKey,
                previewChannel: channel,
                program: null,
                onFullScreen: () {},
                copies: copies,
              ),
            ),
          ),
        ),
      ),
    );

    // One address: nothing to choose.
    await pumpBand(null);
    previewKey.currentState!.adopt(_picture(_PicturePlayer()));
    await pumpBand(_channel);
    await tester.pump();
    expect(copies.value, isNull);
    expect(find.byTooltip(t.liveTv.chooseVariant), findsNothing);
    expect(find.byTooltip(t.common.fullscreen), findsOneWidget);

    await pumpBand(null);
    await tester.pump();
    const variants = [
      (url: 'http://provider.test/live/1.ts', headers: <String, String>{}, label: 'ARD HD'),
      (url: 'http://provider.test/live/2.ts', headers: <String, String>{}, label: 'ARD FHD'),
    ];
    previewKey.currentState!.adopt(
      LivePictureHandover(
        player: _PicturePlayer(),
        session: IptvPlaybackSession(variants: variants),
        channel: _channel,
      ),
    );
    await pumpBand(_channel);
    await tester.pump();
    expect(copies.value?.labels, ['ARD HD', 'ARD FHD']);
    expect(copies.value?.index, 0);

    await tester.tap(find.byTooltip(t.liveTv.chooseVariant));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ARD FHD'));
    await tester.pumpAndSettle();

    expect(
      LiveCopyMemory.startIndexFor(IptvPlaybackSession.memoryKeyFor(variants), variants.length),
      1,
      reason: 'a full screen that opens the channel afresh must find the copy the viewer picked',
    );
  });

  testWidgets('a picture in a texture is not handed over: only one on the plane grows', (tester) async {
    final player = _PicturePlayer();
    await pumpPreview(tester, null);
    previewKey.currentState!.adopt(_picture(player));
    await pumpPreview(tester, _channel);

    expect(previewKey.currentState!.releaseForHandover(), isNull);
    expect(previewKey.currentState!.isHoldingStream, isTrue);
  });

  testWidgets('the box hands its picture over without stopping it, and keeps drawing it until covered', (tester) async {
    final player = _PlanePicturePlayer();
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
