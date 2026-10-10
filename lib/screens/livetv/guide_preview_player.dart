import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../media/ids.dart';
import '../../media/live_tv_support.dart';
import '../../models/livetv_channel.dart';
import '../../utils/mpv_hwdec.dart';
import '../../mpv/mpv.dart';
import '../../mpv/player/video_rect_support.dart';
import '../../mpv/player/platform/player_android.dart';
import '../../mpv/player/platform/player_android_mpv.dart';
import '../../providers/multi_server_provider.dart';
import '../../services/iptv/iptv_live_tv_source.dart' show IptvPlaybackSession;
import '../../services/iptv/iptv_stream_probing.dart';
import '../../services/live_picture_handover.dart';
import '../../services/playback_coordinator.dart';
import '../../services/settings_service.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/app_logger.dart';
import '../../utils/live_tv_player_navigation.dart';
import '../../utils/platform_detector.dart';
import '../../utils/tone_mapped_logo_image.dart';
import '../../widgets/live_tv_channel_logo.dart';
import '../video_player/player_output_format.dart';

/// The guide's small live picture: whatever [channel] is showing right now.
///
/// Its own player, not the full-screen one. There is a single native player
/// core in the app, so the two can never run at once — which is why moving to
/// full screen stops this one first and the picture is rebuilt there rather
/// than handed over. The alternative, two cores, is a native change out of
/// proportion to a preview window. With "Vorschau nahtlos ins Vollbild"
/// (Plebz) on, the full-screen player takes this very player over instead
/// and gives it back on Back ([releaseForHandover], [adopt]).
///
/// Everything here is best-effort. A preview that cannot start says so and
/// leaves the guide alone: the channel is still one press away from playing
/// full screen, which is the path that reports its failures properly.
class GuidePreviewPlayer extends StatefulWidget {
  final LiveTvChannel? channel;

  /// Where the preview says what it is receiving — see [GuideStreamInfo].
  /// Null while nothing plays or nothing is known yet.
  final ValueNotifier<GuideStreamInfo?>? streamInfo;

  const GuidePreviewPlayer({super.key, required this.channel, this.streamInfo});

  @override
  State<GuidePreviewPlayer> createState() => GuidePreviewPlayerState();
}

class GuidePreviewPlayerState extends State<GuidePreviewPlayer> with WidgetsBindingObserver {
  /// Stops short of building the native player, so a widget test can drive
  /// the surrounding behaviour — which channel is previewed, when it is
  /// released — without a playback core it has no way to provide.
  @visibleForTesting
  static bool debugSuppressPlayback = false;

  /// Whether a picture can be shown in a box rather than on the whole screen.
  ///
  /// The video is not painted by this widget: it is a native surface the
  /// player places itself, and only a player that takes a rectangle from the
  /// widget tree can put it anywhere but the whole window. iOS is the one
  /// host left that cannot — there a preview would be sound under a black
  /// rectangle, so it gets the still picture instead.
  static bool get canPlayInline => Platform.isAndroid || Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Player? _player;
  LiveTvPlaybackSession? _session;

  /// Bumped by every start and every stop, so a slow session start that
  /// resolves after the channel changed cannot open the wrong stream.
  int _generation = 0;
  bool _starting = false;
  bool _failed = false;

  /// `mounted` is still true while [dispose] runs, and the stop it starts
  /// there must not ask for a rebuild of an element that is already going.
  bool _disposed = false;

  /// A picture the full-screen player gave back (Plebz), waiting for the guide
  /// to put its channel in the box. See [adopt].
  LivePictureHandover? _pendingAdoption;

  /// The picture handed to the full-screen player, still drawn here — not
  /// owned — until the player covers the box: the route's first frame is laid
  /// out offstage, and the box would show the channel's still for it.
  Player? _shownAfterHandover;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.channel != null) unawaited(_start(widget.channel!));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A preview has nothing to say in the background: no notification, no
    // resume, and it would hold both the stream and the native core.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) unawaited(_stop());
  }

  @override
  void didUpdateWidget(covariant GuidePreviewPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel?.key == widget.channel?.key) return;
    unawaited(_stop());
    if (widget.channel != null) unawaited(_start(widget.channel!));
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    final waiting = _pendingAdoption;
    _pendingAdoption = null;
    if (waiting != null) unawaited(waiting.release());
    // Nothing awaits this: the widget is going away and the native core has
    // to be released either way.
    unawaited(_stop());
    super.dispose();
  }

  /// Whether the preview is holding a stream — a player, a server-side tune,
  /// or both. False once it has let go.
  @visibleForTesting
  bool get isHoldingStream => _player != null || _session != null;

  /// Releases the player, so the full-screen one can take the core.
  Future<void> stopForHandover() => _stop();

  /// Lets go of the playing picture without stopping it, for the full-screen
  /// player to take on and grow out of this box (Plebz). Null when there is
  /// nothing fit to hand over: a preview still starting or failed, or one
  /// whose picture cannot leave its texture. The box falls back to the
  /// channel's still, which the growing picture covers.
  LivePictureHandover? releaseForHandover() {
    final player = _player;
    final session = _session;
    final channel = widget.channel;
    if (player == null || session == null || channel == null || _starting || _failed) return null;
    if (!LivePictureHandover.canMove(player, session)) return null;
    if (player case final VideoOutputHandover output when !output.rendersToTexture) return null;
    _generation++;
    _player = null;
    _session = null;
    _shownAfterHandover = player;
    // Covered by the growing player within a few frames; drawn on under it,
    // it would be a second live picture to composite through every frame of
    // the growth.
    Timer(const Duration(milliseconds: 120), () {
      if (_disposed || !mounted || !identical(_shownAfterHandover, player)) return;
      setState(() => _shownAfterHandover = null);
    });
    appLogger.d('Guide preview: handing ${channel.displayName} over to full screen');
    return LivePictureHandover(player: player, session: session, channel: channel);
  }

  /// Takes up a picture the full-screen player gave back (Plebz): at once when
  /// the box already shows its channel, else as soon as the guide puts that
  /// channel in it. A picture for another channel is released instead.
  void adopt(LivePictureHandover picture) {
    final waiting = _pendingAdoption;
    _pendingAdoption = null;
    if (waiting != null && !identical(waiting, picture)) unawaited(waiting.release());
    if (widget.channel?.key == picture.channel.key && _player == null && _session == null) {
      _install(picture);
      return;
    }
    _pendingAdoption = picture;
  }

  void _install(LivePictureHandover picture) {
    final generation = ++_generation;
    _shownAfterHandover = null;
    _player = picture.player;
    _session = picture.session;
    _failed = false;
    _starting = false;
    if (!_disposed && mounted) setState(() {});
    appLogger.d('Guide preview: ${picture.channel.displayName} plays on from full screen');
    if (widget.streamInfo != null) unawaited(_probeStreamInfo(picture.player, picture.channel, generation));
  }

  Future<void> _stop() async {
    if (_player != null || _session != null) appLogger.d('Guide preview: stopping');
    _generation++;
    _shownAfterHandover = null;
    final player = _player;
    final session = _session;
    _player = null;
    _session = null;
    _setStarting(false);
    if (session != null) await _endSession(session);
    if (player != null) {
      try {
        await player.dispose();
      } catch (e) {
        appLogger.d('Guide preview: player dispose failed', error: e);
      }
    }
  }

  void _setStarting(bool value) {
    if (_disposed || !mounted || _starting == value) return;
    setState(() => _starting = value);
  }

  Future<void> _endSession(LiveTvPlaybackSession session) async {
    try {
      // A server-side tune holds a capture session open; telling it we
      // stopped is what releases it. IPTV has nothing to tell.
      await session.reportTimeline(state: 'stopped', positionMs: 0, durationMs: 0);
    } catch (e) {
      appLogger.d('Guide preview: session teardown failed', error: e);
    }
  }

  Future<void> _start(LiveTvChannel channel) async {
    final adoption = _pendingAdoption;
    if (adoption != null) {
      _pendingAdoption = null;
      if (adoption.channel.key == channel.key && adoption.isAlive) {
        _install(adoption);
        return;
      }
      unawaited(adoption.release());
    }
    final generation = ++_generation;
    setState(() {
      _starting = true;
      _failed = false;
    });

    if (!canPlayInline) {
      // Nothing to start; the still says which channel is chosen and the next
      // press plays it where it can be seen.
      setState(() => _starting = false);
      return;
    }

    try {
      // One native core: a music session holds the only audio core until it
      // is told to let go.
      await PlaybackCoordinator.instance.claimVideo();
      if (!mounted || generation != _generation) return;

      appLogger.d('Guide preview: starting ${channel.displayName}');
      final session = await startLiveTvSession(context, channel);
      if (!mounted || generation != _generation) {
        if (session != null) await _endSession(session);
        return;
      }
      final url = await session?.streamUrlAt();
      if (!mounted || generation != _generation) {
        if (session != null) await _endSession(session);
        return;
      }
      if (url == null) {
        setState(() {
          _starting = false;
          _failed = true;
        });
        return;
      }

      if (debugSuppressPlayback) {
        _session = session;
        setState(() => _starting = false);
        return;
      }

      final settings = await SettingsService.getInstance();
      final hardwareDecoding = settings.read(SettingsService.enableHardwareDecoding);
      // A preview the full-screen player may take over as it plays (Plebz)
      // opens the way that player opens a channel; see [_applyOpeningRoute].
      final mayHandOver = LivePictureHandover.enabledIn(settings);
      final player = Player(
        // IPTV may have a player of its own; the full-screen player resolves
        // the same way, so a hand-over always finds the backend it expects.
        useExoPlayer: settings.useExoPlayerFor(iptv: session is IptvPlaybackSession),
        hardwareDecoding: hardwareDecoding,
      );
      // Before the first call that builds the native surface: the layer it is
      // composited in is read once, when it is created. Both Android backends
      // answer this — a picture inside the widget tree is a Flutter texture on
      // either, because a surface cannot be ordered that finely.
      switch (player) {
        case PlayerAndroid():
          player.inlineSurface = true;
          // Tunneled video lives on a hardware plane the app cannot place; a
          // picture in a box has to be composited the ordinary way.
          await player.setProperty('tunneled-playback', 'no');
          // Read when the player is built, so before the first call that builds it.
          if (mayHandOver) {
            await player.setProperty('exo-buffer-tier', settings.read(SettingsService.playbackBufferTier).nativeValue);
          }
        case PlayerAndroidMpv():
          player.inlineSurface = true;
        default:
          break;
      }
      // The decoder the full screen uses, after the surface choice above:
      // left unset, mpv decoded the preview in software (Plebz).
      await player.setProperty('hwdec', mpvHwdecValue(hardwareDecoding));
      if (mayHandOver) await _applyOpeningRoute(player, settings);
      await applyLiveStreamProbing(player, session);
      await _applyAudioSettings(player, settings);
      if (!mounted || generation != _generation) {
        await player.dispose();
        await _endSession(session!);
        return;
      }

      _session = session;
      _player = player;
      await player.open(Media(url, headers: session!.streamHeaders), play: true, isLive: true);
      if (!mounted || generation != _generation) return;
      appLogger.d('Guide preview: playing ${channel.displayName}');
      setState(() => _starting = false);
      if (widget.streamInfo != null) unawaited(_probeStreamInfo(player, channel, generation));
    } catch (e, stackTrace) {
      appLogger.w('Guide preview: could not start ${channel.displayName}', error: e, stackTrace: stackTrace);
      if (!mounted || generation != _generation) return;
      setState(() {
        _starting = false;
        _failed = true;
      });
    }
  }

  /// Reads what the stream turned out to be, a few times over its first
  /// seconds: the picture's size is known once the decoder has it, a rate
  /// often only after some frames, and a live stream can switch variant as
  /// it settles. Stops at the first read that knows all three, or after the
  /// last attempt — a header is not worth polling a player for.
  Future<void> _probeStreamInfo(Player player, LiveTvChannel channel, int generation) async {
    for (final wait in const [700, 1300, 2000, 4000]) {
      await Future<void>.delayed(Duration(milliseconds: wait));
      if (_disposed || generation != _generation || !identical(_player, player)) return;
      try {
        final format = await PlayerOutputFormat.read(player);
        if (_disposed || generation != _generation) return;
        final audio = _playingAudioTrack(player.state);
        final info = GuideStreamInfo(
          channelKey: channel.key,
          width: format.width,
          height: format.height,
          fps: format.fps,
          audioCodec: audio?.codec,
          audioChannels: audio?.channels,
        );
        _publishStreamInfo(info.isEmpty ? null : info);
        if (info.isComplete) return;
      } catch (e) {
        appLogger.d('Guide preview: stream info not read', error: e);
        return;
      }
    }
  }

  /// The track being heard: the chosen one, or where the player picks for
  /// itself, the stream's default and else its first.
  static AudioTrack? _playingAudioTrack(PlayerState state) {
    final chosen = state.track.audio;
    if (chosen != null && chosen.id != AudioTrack.auto.id && chosen.id != AudioTrack.off.id) {
      return state.tracks.audio.firstWhere((track) => track.id == chosen.id, orElse: () => chosen);
    }
    return state.tracks.audio.where((track) => track.isDefault).firstOrNull ?? state.tracks.audio.firstOrNull;
  }

  /// Only ever from [_probeStreamInfo], after an await: the header listening
  /// sits beside this widget, and a stop runs mid-build from
  /// [didUpdateWidget]. Whoever owns the notifier clears it when it changes
  /// the channel; a stale value is keyed to its channel and so never shown
  /// against another.
  void _publishStreamInfo(GuideStreamInfo? info) {
    final notifier = widget.streamInfo;
    if (_disposed || notifier == null || notifier.value == info) return;
    notifier.value = info;
  }

  /// What the full-screen player decides when it opens a channel, for a
  /// preview it may take over without opening anything (Plebz): these choose a
  /// file's route at open — the Dolby Vision handling, mpv's HDR-to-SDR
  /// route, its deinterlacer — and writing them under a running picture would
  /// reset its decoder.
  Future<void> _applyOpeningRoute(Player player, SettingsService settings) async {
    try {
      final dolbyVisionOff = settings.read(SettingsService.disableDolbyVision);
      final dvConversionMode = settings.read(SettingsService.dvConversionMode);
      await player.setProperty('dv-conversion-mode', dolbyVisionOff ? 'off' : dvConversionMode.nativeValue);
      if (player is PlayerAndroidMpv) {
        await player.setProperty('hdr-sdr-conversion', settings.read(SettingsService.hdrSdrConversion).nativeValue);
        if (settings.read(SettingsService.deinterlace)) await player.setProperty('deinterlace', 'auto');
      }
    } catch (e) {
      // The picture still plays; a full-screen take-over just inherits less.
      appLogger.d('Guide preview: opening route not applied', error: e);
    }
  }

  /// The same audio path the full-screen player takes.
  ///
  /// Without this the preview decoded to PCM while the player passed the
  /// stream through untouched, and the two came out at plainly different
  /// volumes: a receiver decoding AC-3 itself applies its own reference
  /// level, an app mixing to PCM does not. A preview of a channel should
  /// sound like the channel.
  Future<void> _applyAudioSettings(Player player, SettingsService settings) async {
    try {
      if (PlatformDetector.supportsAudioPassthrough()) {
        await player.setAudioPassthrough(settings.read(SettingsService.audioPassthrough));
      }
      if (settings.read(SettingsService.audioNormalization)) {
        await player.setAudioNormalization(true);
      }
      // After passthrough, as in the player: the stereo limit wins over it.
      final audioChannelLimit = settings.read(SettingsService.audioChannelLimit);
      if (audioChannelLimit != AudioChannelLimit.original) {
        await player.setAudioChannelLimit(
          audioChannelLimit,
          centerBoostDb: settings.read(SettingsService.downmixCenterBoost),
          normalize: settings.read(SettingsService.audioDownmixNormalize),
        );
      }
    } catch (e) {
      // A preview is not worth failing over an audio preference.
      appLogger.d('Guide preview: audio settings not applied', error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = _shownAfterHandover;
    final player = _player ?? (shown != null && !shown.disposed ? shown : null);
    return ClipRRect(
      borderRadius: BorderRadius.circular(flatRadius(context, 8)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildBacking(player),
          if (player != null) Video(player: player) else _buildPlaceholder(theme),
          if (_starting)
            const Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3))),
        ],
      ),
    );
  }

  /// What lies under the picture.
  ///
  /// Two different things, because the picture arrives two different ways. A
  /// texture ([VideoTextureTarget]) is ordinary Flutter content and wants an
  /// ordinary black backing — the letterbox around a channel that is not
  /// exactly the shape of the box.
  ///
  /// A native surface is the opposite: it is composited *behind* the whole
  /// Flutter view, so the box has to be a hole rather than a rectangle.
  /// Painted black, the black is what you get — the page's own background and
  /// this box between the viewer and a picture that is drawing perfectly well
  /// underneath. So those pixels are cleared instead, down to the window,
  /// which is what makes the surface visible at all.
  Widget _buildBacking(Player? player) {
    final showsSurface = player is VideoRectTarget && player is! VideoTextureTarget;
    if (!showsSurface) return const ColoredBox(color: Colors.black);
    return const _SurfaceHole();
  }

  Widget _buildPlaceholder(ThemeData theme) {
    final channel = widget.channel;
    if (channel == null) {
      return Center(
        child: Icon(Symbols.tv_rounded, size: 40, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
      );
    }
    if (_failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            t.liveTv.liveStreamFailed,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
          ),
        ),
      );
    }

    // The channel's own mark, the way the grid draws it: a station logo is
    // what the reader recognises, and it makes the still read as the chosen
    // channel rather than as an empty frame. A server-relative logo needs its
    // client to build a URL; an IPTV logo is already a full address.
    final serverId = serverIdOrNull(channel.serverId);
    final client = serverId == null ? null : context.read<MultiServerProvider>().getClientForServer(serverId);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LiveTvChannelLogo(
          channel: channel,
          client: client,
          // The picture's own backing is black in every theme.
          logoToneTarget: channelLogoToneTargetFor(surface: Colors.black, foreground: Colors.white),
          fallback: (_) => _buildName(theme, channel),
        ),
      ),
    );
  }

  Widget _buildName(ThemeData theme, LiveTvChannel channel) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Symbols.tv_rounded, size: 32, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
        const SizedBox(height: 6),
        Text(
          channel.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
        ),
      ],
    );
  }
}

/// What the preview is actually receiving, read off its player once the
/// stream plays — not what a playlist or a guide claims about the channel.
@immutable
class GuideStreamInfo {
  const GuideStreamInfo({
    required this.channelKey,
    this.width = 0,
    this.height = 0,
    this.fps,
    this.audioCodec,
    this.audioChannels,
  });

  /// [LiveTvChannel.key] of the channel playing, so a header describing
  /// another channel never borrows these.
  final String channelKey;

  /// Decoded picture size; 0 while unknown.
  final int width;
  final int height;

  /// The presented frame rate — see [PlayerOutputFormat.fps].
  final double? fps;

  /// As the backend names it: ffmpeg's (`aac`), or ExoPlayer's (`mp4a.40.2`).
  final String? audioCodec;
  final int? audioChannels;

  bool get hasDimensions => width > 0 && height > 0;
  bool get hasAudio => audioCodec != null && audioCodec!.isNotEmpty;
  bool get isEmpty => !hasDimensions && fps == null && !hasAudio;
  bool get isComplete => hasDimensions && fps != null && hasAudio;

  @override
  bool operator ==(Object other) =>
      other is GuideStreamInfo &&
      other.channelKey == channelKey &&
      other.width == width &&
      other.height == height &&
      other.fps == fps &&
      other.audioCodec == audioCodec &&
      other.audioChannels == audioChannels;

  @override
  int get hashCode => Object.hash(channelKey, width, height, fps, audioCodec, audioChannels);
}

/// Erases the pixels behind it, so a native surface composited under the
/// Flutter view shows through.
///
/// `Colors.transparent` would not do: it means *paint nothing*, which leaves
/// whatever the page painted earlier — its background — exactly where it was.
class _SurfaceHole extends StatelessWidget {
  const _SurfaceHole();

  @override
  Widget build(BuildContext context) => const SizedBox.expand(child: CustomPaint(painter: _ClearPainter()));
}

class _ClearPainter extends CustomPainter {
  const _ClearPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..blendMode = BlendMode.clear);
  }

  @override
  bool shouldRepaint(_ClearPainter oldDelegate) => false;
}
