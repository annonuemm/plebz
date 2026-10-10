part of '../../video_player_screen.dart';

/// The guide's live preview, grown into this player and given back to the
/// guide on Back, with the stream never stopping (Plebz). The picture and its
/// rules: [LivePictureHandover].
extension _VideoPlayerLivePictureMethods on VideoPlayerScreenState {
  /// The preview's player, for this start to take on instead of building
  /// one, or null to build one. Asked once: a Retry opens the channel the
  /// ordinary way. A picture that does not fit what this start is about to
  /// do — another backend by now, an archive start — is released.
  LivePictureHandover? _takeHandedOverPicture({required bool useExoPlayer}) {
    final picture = _handedOverPicture;
    _handedOverPicture = null;
    if (picture == null) return null;
    final fits =
        picture.isAlive &&
        (picture.player is PlayerAndroid) == useExoPlayer &&
        widget.live?.startAtEpoch == null &&
        LivePictureHandover.canMove(picture.player, picture.session);
    if (!fits) {
      appLogger.d('Live picture: opening ${picture.channel.displayName} afresh instead');
      unawaited(picture.release());
      setStateIfMounted(() {});
      return null;
    }
    appLogger.d('Live picture: taking ${picture.channel.displayName} over from the guide');
    _takenOverPicture = picture;
    _grewOutOfGuidePicture = true;
    // Its frame is on screen already: no loading overlay over it while the
    // screen sets itself up around the picture.
    _firstFrame.markReady();
    return picture;
  }

  /// What the screen shows until the player is initialized when it grew out
  /// of the guide's preview: the picture itself, so the growth starts from a
  /// playing channel rather than from a spinner. Null otherwise. On the plane,
  /// the picture is behind the app, and this is the hole it shows through.
  Widget? _buildHandedOverPicture() {
    final picture = _takenOverPicture ?? _handedOverPicture;
    if (picture == null || !picture.isAlive) return null;
    if (LivePictureHandover.isOnPlane(picture.player)) return const VideoSurfaceHole();
    return ColoredBox(
      color: Colors.black,
      child: Video(player: picture.player),
    );
  }

  /// The taken-over picture, for the live start to adopt rather than tune.
  /// Once only, for the player it came with.
  LivePictureHandover? _pictureForLiveStart(Player currentPlayer) {
    final picture = _takenOverPicture;
    if (picture == null || _takenOverPictureStarted || !identical(picture.player, currentPlayer)) return null;
    _takenOverPictureStarted = true;
    return picture;
  }

  /// The live start for a taken-over picture: the session and the playing
  /// stream are adopted as they are and nothing is opened. Its first frame
  /// has long been on screen, so the screen is ready at once; the display is
  /// not negotiated (see [LivePictureHandover.enabledIn]).
  void _startFromTakenOverPicture(Player currentPlayer, LivePictureHandover picture, _PlaybackAttempt attempt) {
    final session = picture.session;
    _live.adoptSession(session);
    _live.markStreamTakenOverAtLiveEdge(session.captureBuffer, currentPlayer.state.position);
    _live.streamGeneration++;
    // The move's native steps, kept in the in-app log while the freeze after
    // the move on the user's box is open.
    _playerStreamSubscriptions.add(
      currentPlayer.streams.log
          .where((log) => log.prefix == 'picture-move')
          .listen((log) => appLogger.i('Live picture (native): ${log.text}')),
    );
    attempt.outcome.adoptPlayingFile();
    _firstFrame.markReady();
    _http503Watchdog.disarm();
    unawaited(_visualEffects.onFirstFrame());
    // On the plane already (the test alternative), nothing moves. Otherwise
    // the picture stays in the texture unless the viewer asked for the window
    // surface: moving a running decoder froze or desynced it now and then on
    // the user's box (see SettingsService.liveTvSeamlessWindowSurface).
    if (LivePictureHandover.isOnPlane(currentPlayer)) {
      appLogger.i('Live picture: on the video surface from the guide on');
    } else if (SettingsService.instanceOrNull?.read(SettingsService.liveTvSeamlessWindowSurface) ?? false) {
      unawaited(_moveTakenOverPictureToWindow(currentPlayer));
    } else {
      appLogger.i('Live picture: stays in the texture for full screen');
    }
  }

  /// Once the player has grown out of the box, the picture leaves the texture
  /// it played in there for the window surface a full-screen picture belongs
  /// on: the hardware plane, HDR, no copy through Flutter. The texture stays
  /// on screen until the window surface has the picture.
  Future<void> _moveTakenOverPictureToWindow(Player currentPlayer) async {
    if (currentPlayer case final VideoOutputHandover output) {
      if (!await _untilPictureHasGrown()) return;
      if (!mounted || _shuttingDown || _handingPictureBack || player != currentPlayer || !output.rendersToTexture) {
        return;
      }
      final moved = await output.moveOutputToWindow();
      appLogger.i('Live picture: ${moved ? 'moved to the window surface' : 'stays in the texture'}');
      if (moved) unawaited(_checkPictureAfterMove(currentPlayer));
    }
  }

  /// What mpv reports a moment after the picture moved, at info so the in-app
  /// log keeps it — the picture froze after the move on the user's box, cause
  /// unknown. And the one cure that costs nothing: a player the move left
  /// paused plays on.
  Future<void> _checkPictureAfterMove(Player currentPlayer) async {
    for (final wait in const [Duration(seconds: 2), Duration(seconds: 3)]) {
      await Future<void>.delayed(wait);
      if (!mounted || _shuttingDown || player != currentPlayer) return;
      final report = <String>[];
      String? paused;
      for (final name in const [
        'pause',
        'paused-for-cache',
        'core-idle',
        'time-pos',
        'vid',
        'hwdec-current',
        'estimated-vf-fps',
        'vo-configured',
        'avsync',
        'frame-drop-count',
        'decoder-frame-drop-count',
      ]) {
        String? value;
        try {
          value = await currentPlayer.getProperty(name);
        } catch (_) {
          value = '?';
        }
        if (name == 'pause') paused = value;
        report.add('$name=$value');
      }
      if (!mounted || player != currentPlayer) return;
      appLogger.i('Live picture after the move: ${report.join(' ')}');
      // mpv only: its `pause` is the pause flag, where ExoPlayer answers "not
      // playing" while it buffers too — and a play() then arms its own
      // resume-stall rescue, which seeks a live stream (seen in BlueStacks).
      if (paused == 'yes' && currentPlayer is PlayerNative && _playbackIntentShouldPlay && !_shuttingDown) {
        appLogger.w('Live picture: paused after the move, playing on');
        await currentPlayer.play();
      }
    }
  }

  /// Completes once the route has grown out of the guide's box: true when it
  /// got there, false when it was popped on the way.
  Future<bool> _untilPictureHasGrown() async {
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.status == AnimationStatus.completed) return true;
    final grown = Completer<bool>();
    void onStatus(AnimationStatus status) {
      if (grown.isCompleted) return;
      if (status == AnimationStatus.completed) grown.complete(true);
      if (status == AnimationStatus.reverse || status == AnimationStatus.dismissed) grown.complete(false);
    }

    animation.addStatusListener(onStatus);
    final hasGrown = await grown.future;
    animation.removeStatusListener(onStatus);
    return hasGrown;
  }

  /// How far ahead of the page the picture on the plane is placed while the
  /// player grows or shrinks, in animation progress (about two frames of the
  /// 300 ms): the plane follows a frame or so behind Flutter, and a picture a
  /// little larger than the hole hides under the guide where one a little
  /// smaller would leave a black edge inside it.
  static const double _planeLead = 0.1;

  /// The picture on the plane moved with the page frame by frame while the
  /// route grows ([growing]) or shrinks back into the guide's box, and placed
  /// exactly where the page ends up. The `Video` widgets' own reports wait
  /// meanwhile (`VideoViewportTarget.videoRectDriven`).
  void _movePlaneWithRoute(Player currentPlayer, {required bool growing}) {
    if (currentPlayer case final VideoViewportTarget plane when plane.followsVideoRect) {
      final route = ModalRoute.of(context);
      final from = route is VideoPlayerRoute ? route.pictureFrom : null;
      final animation = route?.animation;
      if (from == null || animation == null) return;
      final view = View.of(context);
      final ratio = view.devicePixelRatio;
      final screen = view.physicalSize / ratio;
      void place(double value) {
        final rect = VideoPlayerRoute.pictureRectAt(from, screen, value);
        unawaited(
          plane.driveVideoRect(
            left: (rect.left * ratio).floor(),
            top: (rect.top * ratio).floor(),
            right: (rect.right * ratio).ceil(),
            bottom: (rect.bottom * ratio).ceil(),
          ),
        );
      }

      if (growing && animation.status != AnimationStatus.forward) {
        place(animation.value);
        return;
      }
      void onTick() => place((animation.value + _planeLead).clamp(0.0, 1.0));
      late final AnimationStatusListener onStatus;
      onStatus = (status) {
        if (status != AnimationStatus.completed && status != AnimationStatus.dismissed) return;
        animation.removeListener(onTick);
        animation.removeStatusListener(onStatus);
        place(animation.value);
        plane.videoRectDriven = false;
      };
      plane.videoRectDriven = true;
      animation.addListener(onTick);
      animation.addStatusListener(onStatus);
      if (growing) onTick();
    }
  }

  /// Whether Back gives the picture back to the guide's preview instead of
  /// stopping it: only a session that grew out of it, still on an IPTV
  /// stream at the live edge, playing and settled.
  bool get _canHandPictureBack {
    if (!widget.isLive || !_grewOutOfGuidePicture || _handingPictureBack) return false;
    final currentPlayer = player;
    if (currentPlayer == null || !LivePictureHandover.canMove(currentPlayer, _live.session)) return false;
    if (_currentLiveChannel == null || !currentPlayer.state.isActive) return false;
    if (!_firstFrame.rendered || _hasFatalPlaybackError || _playbackFailureMessage != null) return false;
    if (!_live.atLiveEdge || _live.retrying || _transitionGate.transition != PlaybackTransition.idle) return false;
    if (_watchTogetherProvider?.isInSession ?? false) return false;
    final settings = SettingsService.instanceOrNull;
    return settings != null && LivePictureHandover.enabledIn(settings);
  }

  /// Back, with the picture going home to the guide's preview: it moves into
  /// a texture, the window surface goes once Flutter shows that texture, and
  /// the player shrinks into the box while the guide takes the picture up
  /// ([LivePictureReturn]). Anything that goes wrong on the way leaves the
  /// ordinary way out.
  Future<void> _handPictureBackToGuide() async {
    final currentPlayer = player;
    final session = _live.session;
    final channel = _currentLiveChannel;
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    if (currentPlayer == null ||
        currentPlayer is! VideoOutputHandover ||
        session == null ||
        channel == null ||
        route == null ||
        !route.isCurrent ||
        !navigator.canPop()) {
      return _exitPlayerRoute(navigateHome: false);
    }
    final output = currentPlayer as VideoOutputHandover;
    _handingPictureBack = true;
    _chromeController.hide(ignoreHolds: true);

    // A picture on the plane in a box stays where it is and only shrinks with
    // the page; one on the window surface goes back into a texture first.
    final onPlane = LivePictureHandover.isOnPlane(currentPlayer);
    var inPlace = output.rendersToTexture || onPlane;
    if (!inPlace) {
      final size = View.of(context).physicalSize;
      inPlace = await output.moveOutputToTexture(width: size.width.round(), height: size.height.round());
      if (inPlace && mounted) {
        await SchedulerBinding.instance.endOfFrame;
        unawaited(output.releaseWindowOutput());
      }
    }
    if (!mounted) return;
    if (!inPlace || _shuttingDown || player != currentPlayer || !route.isCurrent || !navigator.canPop()) {
      _handingPictureBack = false;
      return _exitPlayerRoute(navigateHome: false);
    }

    appLogger.d('Live picture: giving ${channel.displayName} back to the guide');
    _setPlayerState(() => _pictureHandedBack = true);
    if (route is VideoPlayerRoute) route.shrinkIntoPictureOnPop();
    if (onPlane) _movePlaneWithRoute(currentPlayer, growing: false);
    LivePictureReturn.instance.leave(LivePictureHandover(player: currentPlayer, session: session, channel: channel));
    await _exitPlayerRoute(navigateHome: false);
  }
}
