part of '../../video_player_screen.dart';

const _liveClockReadyTimeout = Duration(seconds: 15);

extension _VideoPlayerLiveTvMethods on VideoPlayerScreenState {
  /// Start periodic timeline heartbeats for live TV transcode session.
  void _startLiveTimelineUpdates() {
    if (_shuttingDown) return;
    final generation = ++_live.timelineGeneration;
    _live.timelineTimer?.cancel();
    _live.timelineTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (generation != _live.timelineGeneration) return;
      final state = player?.state.playing == true ? 'playing' : 'paused';
      _sendLiveTimeline(state);
    });
    // Delay initial heartbeat to let the transcode session stabilize.
    // Sending time=0 immediately after player.open() causes the server
    // to spawn a duplicate transcode job with offset=-1 that 404s.
    Future.delayed(const Duration(seconds: 3), () {
      if (_live.timelineTimer != null && generation == _live.timelineGeneration) {
        final state = player?.state.playing == true ? 'playing' : 'paused';
        _sendLiveTimeline(state);
      }
    });
  }

  /// Release a live start's or zap's transition lock and run recovery for a
  /// failure of its replacement stream that arrived before it committed.
  void _finishLiveReplacement(PlaybackTransitionLease lease, int replacement, {required bool committed}) {
    final ownsLock = _transitionGate.owns(lease);
    final runDeferred = _live.endReplacement(replacement, committed: committed && ownsLock);
    _transitionGate.release(lease);
    if (runDeferred && mounted && !_shuttingDown && !_isExiting.value && !_hasFatalPlaybackError) {
      appLogger.w('Replacement live stream failed before its transition committed; recovering now');
      _beginLiveLadderRetry();
    }
  }

  /// Advance the fallback ladder and retry — the error path's entry point.
  void _beginLiveLadderRetry() {
    if (_shuttingDown) return;
    // A start or zap that already opened its stream owns it but has not
    // adopted its session yet: recovering now would re-tune the session being
    // replaced, and the gate turns the retry away. Park the failure until the
    // replacement commits (see [_finishLiveReplacement]).
    final transition = _transitionGate.transition;
    if ((transition == PlaybackTransition.startingLive || transition == PlaybackTransition.switchingChannel) &&
        _live.deferReplacementFailure()) {
      appLogger.d('Live stream failure deferred until ${transition.name} commits');
      return;
    }
    _live.fallbackLevel++;
    _live.retrying = true;
    appLogger.w('Live stream failed, retrying with fallback level ${_live.fallbackLevel}');
    unawaited(_retryLiveStream());
  }

  /// Play pressed while the live stream is dead: reuse the ladder retry
  /// unless one is already in flight.
  Future<void> _retryLiveStreamForPlayIntent() {
    if (_shuttingDown || _live.retrying) return Future.value();
    _liveStallBudget.reset();
    _live.retrying = true;
    return _retryLiveStream();
  }

  /// A playback restart proves the current ladder level works; refill it.
  void _resetLiveLadderOnPlaybackRestart() {
    _live.fallbackLevel = 0;
    _live.retryFailed = false;
  }

  void _suspendLiveTimelineForBackground() {
    _live.resumeTimelineOnResume = _live.timelineTimer != null;
    _stopLiveTimelineUpdates();
  }

  void _resumeLiveTimelineAfterBackgroundIfNeeded() {
    final shouldResume = _live.resumeTimelineOnResume;
    _live.resumeTimelineOnResume = false;
    if (shouldResume && _live.session != null) {
      _startLiveTimelineUpdates();
    }
  }

  /// The TV background policy stopped the tuned session: exit the screen on
  /// the next resume instead of showing a dead stream.
  void _stopLiveSessionForTvBackground() {
    _live.exitOnResume = true;
    _live.resumeTimelineOnResume = false;
    _stopLiveTimelineUpdates();
  }

  /// Whether the background stop asked for an exit-on-resume; consuming the
  /// flag so the exit runs once.
  bool _consumeLiveExitOnResume() {
    if (!_live.exitOnResume) return false;
    _live.exitOnResume = false;
    return true;
  }

  void _stopLiveTimelineUpdates() {
    _live.timelineGeneration++;
    _live.timelineTimer?.cancel();
    _live.timelineTimer = null;
  }

  Future<void> _sendLiveTimeline(String state) async {
    if (_shuttingDown && state != 'stopped') return;
    final requestSession = _live.session;
    if (requestSession == null) return;
    final requestGeneration = _live.timelineGeneration;
    final requestStreamGeneration = _live.streamGeneration;
    // For live TV, player position/duration are unreliable (often 0). Use
    // elapsed wall-clock as the position and the program duration from tune
    // metadata; the per-backend session owns the wire mapping.
    final playbackTime = _live.playbackStartTime != null
        ? DateTime.now().difference(_live.playbackStartTime!).inMilliseconds
        : 0;

    try {
      await _live.timelineReports.send(
        stopped: state == 'stopped',
        report: () => runLiveTimelineReport(
          requestSession: requestSession,
          requestGeneration: requestGeneration,
          state: state,
          positionMs: playbackTime,
          currentSession: () => _live.session,
          currentGeneration: () => _live.timelineGeneration,
          isMounted: () => mounted,
          commit: (update) {
            final hadSeekWindow = _live.captureBuffer != null;
            _setPlayerState(() {
              final playbackStream = update.playbackStream;
              if (playbackStream != null &&
                  _live.adoptPlaybackStreamOrigin(playbackStream, generation: requestStreamGeneration)) {
                appLogger.d('Live clock re-anchored on playback transcode origin ${playbackStream.startedAt}');
              }
              final buffer = update.captureBuffer;
              if (buffer != null) _live.captureBuffer = buffer;
              final window = _live.captureBuffer;
              if (window != null) {
                _live.atLiveEdge =
                    (_currentPositionEpoch >=
                    window.seekableEndEpoch - VideoPlayerScreenState._liveEdgeThresholdSeconds);
              }
            });
            // Time-shift arrived with this heartbeat (Plex publishes the
            // capture buffer a beat after the tune): the session can now
            // advertise ±skip through it.
            if (!hadSeekWindow && _live.captureBuffer != null) {
              unawaited(_mediaControls.syncAvailability());
            }
          },
        ),
      );
    } catch (e) {
      appLogger.d('Live timeline update failed', error: e);
    }
  }

  /// Release a session that started but was never adopted (unmount or
  /// superseded mid-start) so the backend frees its tuner/transcode instead of
  /// holding it until an idle timeout, or forever (#2394).
  void _abandonLiveSession(LiveTvPlaybackSession session) => unawaited(session.discard());

  /// Announce the channel just switched to, then fade it out. Restarted on
  /// every zap so a walk through the channels keeps one banner, not a queue.
  void _showZapBanner() {
    _zapBannerTimer?.cancel();
    _zapBannerVisible.value = true;
    _zapBannerTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) _zapBannerVisible.value = false;
    });
  }

  /// The channel playing right now: the zapped-to one once a switch landed,
  /// the launch channel before that.
  LiveTvChannel? get _currentLiveChannel {
    final live = widget.live;
    if (live == null) return null;
    final channels = live.channels;
    if (channels == null || _live.channelIndex < 0 || _live.channelIndex >= channels.length) return live.channel;
    return channels[_live.channelIndex];
  }

  /// What the header names: the programme at the position being watched, not
  /// the one on air.
  ///
  /// The two are the same at the live edge and differ the moment playback sits
  /// in an archive — a catch-up programme was announced under the name of
  /// whatever the channel happened to be showing at that minute.
  LiveTvProgram? get _currentLiveProgram {
    final channel = _currentLiveChannel;
    if (channel == null) return null;
    // Before the first stream opens there is no position to read; the header
    // then names what is on, which is what it is about to play.
    if (_live.streamStartEpoch <= 0) return _live.currentProgramFor(channel);
    final watching = DateTime.fromMillisecondsSinceEpoch(_currentPositionEpoch * 1000);
    return _live.currentProgramFor(channel, now: () => watching);
  }

  /// The backend that owns [channel]: an IPTV source when the channel came
  /// from a playlist, otherwise the server's Live TV client. Mirrors the
  /// resolution [_startLiveSession] does, for the surfaces that need the
  /// guide rather than a stream.
  LiveTvSupport? _liveTvSupportFor(LiveTvChannel channel) {
    final iptv = context.read<IptvSourcesProvider?>()?.liveTvForSourceId(channel.serverId ?? '');
    if (iptv != null) return iptv;

    final multiServer = context.read<MultiServerProvider>();
    final serverInfo = liveTvServerInfoForChannel(multiServer, channel);
    if (serverInfo == null) return null;
    return multiServer.getClientForServer(ServerId(serverInfo.serverId))?.liveTv;
  }

  /// Read the guide for the channels this session can zap to.
  ///
  /// Deliberately fire-and-forget and never awaited by a tune: what is on
  /// air is decoration around the picture, and a slow or missing guide must
  /// not hold up a channel change. An IPTV source usually answers from its
  /// own cache — it loaded the guide when the channel was tuned.
  Future<void> _loadLiveSchedule({bool force = false}) async {
    final channels = widget.live?.channels;
    if (channels == null || channels.isEmpty || _live.programsLoading) return;

    final loadedAt = _live.programsLoadedAt;
    if (!force && loadedAt != null && DateTime.now().difference(loadedAt) < const Duration(minutes: 10)) return;

    final support = _liveTvSupportFor(widget.live!.channel);
    if (support == null) return;

    _live.programsLoading = true;
    try {
      final now = DateTime.now();
      final programs = await support.fetchSchedule(
        from: now.subtract(const Duration(hours: 1)),
        to: now.add(const Duration(hours: 4)),
      );
      if (!mounted) return;

      // Same matching the guide screen uses, so a channel resolves here
      // exactly as it does there.
      final byChannel = <String, List<LiveTvProgram>>{};
      final byIdentifier = <String, List<LiveTvProgram>>{};
      for (final program in programs) {
        final identifier = program.channelIdentifier?.trim();
        if (identifier == null || identifier.isEmpty) continue;
        (byIdentifier[identifier] ??= []).add(program);
      }
      for (final channel in channels) {
        final candidates = <LiveTvProgram>{
          ...?byIdentifier[channel.key],
          if (channel.identifier != null) ...?byIdentifier[channel.identifier!],
        };
        final matching = candidates.where((program) => liveTvProgramMatchesChannel(program, channel)).toList()
          ..sort((a, b) => (a.beginsAt ?? 0).compareTo(b.beginsAt ?? 0));
        if (matching.isNotEmpty) byChannel[liveTvChannelScopeKey(channel)] = matching;
      }

      _setPlayerState(() {
        _live.programsByChannel = byChannel;
        _live.programsLoadedAt = DateTime.now();
      });
    } catch (error, stackTrace) {
      // A guide that cannot be read costs the programme line, nothing else.
      appLogger.d('Live guide could not be read', error: error, stackTrace: stackTrace);
    } finally {
      _live.programsLoading = false;
    }
  }

  /// Resolve the owning live-TV server for [channel] and start a playback
  /// session on it — the shared resolution path for initial launch and
  /// channel zapping (Plex tunes a DVR, Jellyfin negotiates a direct URL).
  Future<LiveTvPlaybackSession?> _startLiveSession(LiveTvChannel channel) =>
      startLiveTvSession(context, channel, quality: _selectedQualityPreset);

  String? get _liveTitleWithVariant => LiveTvSessionState.titleWithVariant(
    _live.channelName,
    labels: _live.session?.variantLabels ?? const [],
    index: _live.session?.variantIndex ?? 0,
  );

  /// Play this channel over one of its other addresses.
  ///
  /// A station a playlist carries several times over is one channel here, and
  /// the copies are routes to the same picture — one can be down while
  /// another works, and one can simply be better. The switch re-opens the
  /// stream the same way recovery does.
  Future<void> _switchLiveVariant(int index) async {
    final currentPlayer = player;
    final session = _live.session;
    if (!mounted || currentPlayer == null || session == null) return;
    final generation = _transitionGate.generation;
    bool isCurrent() => _isCurrentPlaybackGeneration(generation, currentPlayer);

    CaptureBuffer? recoveredCaptureBuffer;
    LiveTvPlaybackSession? switched;
    await runLiveStreamRetry<LiveTvPlaybackSession>(
      recover: () => session.switchVariant(index),
      lookupStreamUrl: (recovered) {
        switched = recovered;
        recoveredCaptureBuffer = recovered.captureBuffer;
        return recovered.streamUrlAt();
      },
      applyPlayerOptions: () => _setLiveStreamOptions(currentPlayer),
      open: (streamUrl) async {
        _live.markStreamRestartedAtLiveEdge(recoveredCaptureBuffer);
        final targetEpoch = recoveredCaptureBuffer == null ? null : _live.streamStartEpoch.round();
        await _openLiveStream(
          currentPlayer,
          streamUrl,
          targetEpoch: targetEpoch,
          applyOptions: false,
          session: switched,
        );
      },
      isCurrent: isCurrent,
      currentSession: () => _live.session,
      adoptSession: (recovered) {
        _live.adoptSession(recovered);
        // The name at the top carries which copy is playing, and it is read
        // at build time — without this the picture would change under an
        // unchanged title.
        setStateIfMounted(() {});
      },
      discardSession: _abandonLiveSession,
      reportFailure: (error, stackTrace) {
        appLogger.w('Could not switch live variant', error: error, stackTrace: stackTrace);
        showGlobalErrorSnackBar(t.messages.liveStreamInterrupted);
      },
      onFinished: () {},
    );
  }

  /// The item that stands in for [channel] once a zap adopts its session.
  ///
  /// Resolves the channel's server the same way [_startLiveSession] does, so a
  /// cross-server channel list cannot leave every `_currentMetadata` consumer
  /// describing the channel that was tuned first.
  MediaItem _liveChannelItem(LiveTvChannel channel) {
    final multiServer = context.read<MultiServerProvider>();
    final serverInfo = liveTvServerInfoForChannel(multiServer, channel);
    // An unscoped channel names no server of its own; the live TV server the
    // tune would pick is the one that can serve its logo.
    final serverId = serverInfo?.serverId ?? channel.serverId;
    final client = serverId == null ? null : multiServer.getClientForServer(ServerId(serverId));
    return liveTvChannelItem(channel, backend: client?.backend ?? _currentMetadata.backend, serverId: serverId);
  }

  /// Retry the live stream with degraded direct-stream settings.
  ///
  /// The session owns the per-backend recovery: Plex re-tunes the channel
  /// for a fresh capture session (the previous one expires while MPV
  /// exhausts its reconnect attempts) applying the degradation flags;
  /// Jellyfin re-opens its session-less URL.
  Future<void> _retryLiveStream() async {
    _liveSeek.cancel();
    final currentPlayer = player;
    if (!mounted || _shuttingDown || currentPlayer == null) return;
    final session = _live.session;
    if (session == null) {
      _live.retrying = false;
      appLogger.w('Cannot retry live stream — no session');
      showGlobalErrorSnackBar(_redactPlayerError(_lastLogError ?? t.liveTv.liveStreamFailed));
      unawaited(_handleBackButton());
      return;
    }

    // Recovery reopens the stream, so it holds the transition lock like any
    // other in-place transition. A zap or start in flight is replacing the
    // stream that failed; recovering the old session under it would reopen
    // the previous channel over the new one. The new stream reports its own
    // failures once it is in place.
    final lease = _transitionGate.tryAcquire(PlaybackTransition.recoveringLive);
    if (lease == null) {
      _live.retrying = false;
      appLogger.d('Live stream retry skipped: ${_transitionGate.transition.name} in flight');
      return;
    }
    try {
      await _recoverLiveStream(currentPlayer, session, lease);
    } finally {
      _transitionGate.release(lease);
    }
  }

  Future<void> _recoverLiveStream(
    Player currentPlayer,
    LiveTvPlaybackSession session,
    PlaybackTransitionLease lease,
  ) async {
    final generation = _transitionGate.generation;
    // A zap supersedes the recovery by taking the lock over (see
    // [_switchLiveChannel]); everything recovered after that is discarded.
    bool isCurrent() =>
        _isCurrentPlaybackGeneration(generation, currentPlayer) &&
        _transitionGate.owns(lease, expected: PlaybackTransition.recoveringLive);

    final ds = _live.fallbackLevel < 1;
    final dsa = _live.fallbackLevel < 2;
    appLogger.i('Retrying live stream: directStream=$ds directStreamAudio=$dsa');

    // Carried across the re-tune: stream ids are tune-scoped, so the choice
    // is re-mapped onto the recovered session's track list. Recovering the
    // video outranks keeping subtitles — a failed burn re-apply drops them.
    MediaSubtitleTrack? recoveredSubtitle;
    CaptureBuffer? recoveredCaptureBuffer;
    LiveTvPlaybackSession? recoveredSession;
    final result = await runLiveStreamRetry<LiveTvPlaybackSession>(
      recover: () => session.recover(directStream: ds, directStreamAudio: dsa),
      lookupStreamUrl: (recovered) async {
        recoveredSession = recovered;
        recoveredCaptureBuffer = recovered.captureBuffer;
        recoveredSubtitle = LiveTvSessionState.remapSubtitleSelection(recovered.subtitleTracks, _live.selectedSubtitle);
        if (recoveredSubtitle != null) {
          final url = await recovered.streamUrlAt(subtitleTrack: recoveredSubtitle);
          if (url != null) return url;
          appLogger.w('Live recovery could not re-apply the subtitle burn; retrying without subtitles');
          recoveredSubtitle = null;
        }
        return recovered.streamUrlAt();
      },
      applyPlayerOptions: () => _setLiveStreamOptions(currentPlayer),
      open: (streamUrl) async {
        _live.markStreamRestartedAtLiveEdge(recoveredCaptureBuffer);
        final targetEpoch = recoveredCaptureBuffer == null ? null : _live.streamStartEpoch.round();
        await _openLiveStream(
          currentPlayer,
          streamUrl,
          targetEpoch: targetEpoch,
          applyOptions: false,
          session: recoveredSession,
        );
      },
      isCurrent: isCurrent,
      adoptSession: (recovered) {
        _live.adoptSession(recovered);
        _live.selectedSubtitle = recoveredSubtitle;
      },
      // Jellyfin's recover() returns the receiver, so the recovered object can
      // be the still-current session; the retry helper skips the discard by
      // identity so a failed retry cannot terminally release it.
      currentSession: () => _live.session,
      discardSession: _abandonLiveSession,
      reportFailure: (error, stackTrace) {
        appLogger.e('Failed to recover live stream', error: error, stackTrace: stackTrace);
        _live.retryFailed = true;
        showGlobalErrorSnackBar(t.messages.liveStreamInterrupted);
      },
      onFinished: () {
        if (isCurrent()) _live.retrying = false;
      },
    );
    if (result == LiveStreamRetryResult.succeeded && isCurrent()) {
      _live.retryFailed = false;
    }
  }

  /// Headers for a live stream open. `Accept-Language` is what the backends
  /// have always been sent; an IPTV session adds whatever its playlist entry
  /// insisted on (a user agent its provider checks, a referer).
  Map<String, String> _liveMediaHeaders(LiveTvPlaybackSession? session) => {
    'Accept-Language': 'en',
    ...?session?.streamHeaders,
  };

  /// Configure MPV options for live streaming.
  /// The official Plex Media Player does not set client-side reconnect options —
  /// reconnection is handled by the server's transcoder on the input side.
  /// [session] is the one the next open belongs to, where the screen has not
  /// adopted it yet (a zap adopts after the open).
  ///
  /// [channel] is the one the next open tunes, where the screen has not
  /// adopted it yet; its decode mode ([applyLiveDecodeMode], Plebz) is set
  /// here too and watched once the open starts ([_armLiveDecodeGuard]).
  Future<void> _setLiveStreamOptions(Player player, {LiveTvPlaybackSession? session, LiveTvChannel? channel}) async {
    await player.setProperty('force-seekable', 'no');
    await applyLiveStreamProbing(player, session ?? _live.session);
    final target = channel ?? _currentLiveChannel;
    _liveDecodeGuard.prepare(target, await applyLiveDecodeMode(player, target));
  }

  /// Right before a live open: watch it for a hardware decoder that never
  /// shows a frame (Plebz). Only an open at the live edge — an archive or
  /// time-shift open is the channel's stream at another point, and a channel
  /// that needs software has been remembered by its live open already.
  void _armLiveDecodeGuard(Player player, {required bool timeShifted}) {
    if (timeShifted) {
      _liveDecodeGuard
        ..prepare(null, LiveDecodeMode.untouched)
        ..disarm();
      return;
    }
    _liveDecodeGuard.armForOpen(player, onStuck: (channel) => unawaited(_reopenLiveInSoftware(player, channel)));
  }

  /// Right before a live open: watch a merged channel's copy for one that
  /// never shows a frame or plays an off-air clip, and move on to the next
  /// copy (Plebz). Only at the live edge — an archive is reached through a
  /// copy of its own, and is a file with a length.
  void _armLiveVariantFallback(Player player, LiveTvPlaybackSession? session, {required bool timeShifted}) {
    if (timeShifted || session == null) {
      _liveVariantFallback.disarm();
      return;
    }
    final stream = _live.streamGeneration;
    _liveVariantFallback.armForOpen(
      player,
      session,
      onStuck: (next) => _moveToNextLiveVariant(player, session, next, stream),
    );
  }

  /// The copy [session] opened is not the channel ([LiveVariantFallbackGuard]):
  /// play it over copy [next] instead. The open's own start or zap may not
  /// have adopted [session] yet, so a moment is given for that; any newer
  /// open replaced the stream and settles this.
  void _moveToNextLiveVariant(
    Player currentPlayer,
    LiveTvPlaybackSession session,
    int next,
    int stream, {
    int wait = 0,
  }) {
    if (!mounted || _shuttingDown || _isExiting.value || player != currentPlayer) return;
    if (_live.streamGeneration != stream || _hasFatalPlaybackError) return;
    if (!identical(_live.session, session) || _transitionGate.transition != PlaybackTransition.idle) {
      if (wait >= 5) return;
      Timer(
        const Duration(seconds: 1),
        () => _moveToNextLiveVariant(currentPlayer, session, next, stream, wait: wait + 1),
      );
      return;
    }
    unawaited(_switchLiveVariant(next));
  }

  /// Right before a live open: watch the stream for a picture that stands
  /// still while playing, and reopen it (Plebz). Not a time-shifted open —
  /// an archive is a file that really ends.
  void _armLiveStallGuard(Player player, {required bool timeShifted}) {
    if (timeShifted) {
      _liveStallGuard.disarm();
      return;
    }
    final stream = _live.streamGeneration;
    _liveStallGuard.armForOpen(
      player,
      playing: player.state.playing,
      onStalled: (why) => unawaited(_onLiveStalled(player, stream, why)),
    );
  }

  /// The live stream [stream] stopped coming ([LiveStallGuard]). A playlist
  /// channel is opened again on the same copy, as a zap away and back would;
  /// a server's channel goes through its own recovery, which re-tunes it. A
  /// channel that keeps stopping is left to the viewer after
  /// [maxLiveStallReopens] tries: Play tries again.
  Future<void> _onLiveStalled(Player currentPlayer, int stream, String why) async {
    if (!mounted || _shuttingDown || _isExiting.value || player != currentPlayer) return;
    if (_live.streamGeneration != stream || _hasFatalPlaybackError || _live.retrying) return;
    final session = _live.session;
    // A transition in flight opens a stream of its own, which is watched anew.
    if (session == null || _transitionGate.transition != PlaybackTransition.idle) return;
    if (!_liveStallBudget.take(DateTime.now())) {
      appLogger.w('Live TV: stream $why again — leaving it to the viewer');
      _live.retryFailed = true;
      showGlobalErrorSnackBar(t.messages.liveStreamInterrupted);
      return;
    }
    appLogger.w('Live TV: stream $why — reopening');
    if (session is! IptvPlaybackSession) {
      _live.retrying = true;
      await _retryLiveStream();
      return;
    }
    final channel = _currentLiveChannel;
    final lease = _transitionGate.tryAcquire(PlaybackTransition.recoveringLive);
    if (lease == null) return;
    final generation = _transitionGate.generation;
    bool isCurrent() =>
        _isCurrentPlaybackGeneration(generation, currentPlayer) &&
        _transitionGate.owns(lease, expected: PlaybackTransition.recoveringLive) &&
        identical(_live.session, session);
    try {
      final streamUrl = await session.streamUrlAt();
      if (streamUrl == null || !isCurrent()) return;
      _live.markStreamRestartedAtLiveEdge(session.captureBuffer);
      await _openLiveStream(
        currentPlayer,
        streamUrl,
        targetEpoch: session.captureBuffer == null ? null : _live.streamStartEpoch.round(),
        channel: channel,
      );
    } catch (e, stackTrace) {
      appLogger.w('Live TV: reopening the stalled stream failed', error: e, stackTrace: stackTrace);
    } finally {
      _transitionGate.release(lease);
    }
  }

  /// The hardware decoder took [channel]'s stream and showed nothing
  /// ([LiveSoftwareDecodeGuard]): remember the channel on this device and open
  /// the same session's stream again, which now decodes in software. A zap or
  /// recovery already in flight replaces the stream anyway — and opens it in
  /// software too, since the channel is remembered first.
  Future<void> _reopenLiveInSoftware(Player currentPlayer, LiveTvChannel channel) async {
    await rememberLiveSoftwareDecode(channel);
    final session = _live.session;
    final playing = _currentLiveChannel;
    if (!mounted || _shuttingDown || player != currentPlayer || session == null || _firstFrame.rendered) return;
    if (playing == null || liveSoftwareDecodeKey(playing) != liveSoftwareDecodeKey(channel)) return;
    final lease = _transitionGate.tryAcquire(PlaybackTransition.recoveringLive);
    if (lease == null) return;
    final generation = _transitionGate.generation;
    bool isCurrent() =>
        _isCurrentPlaybackGeneration(generation, currentPlayer) &&
        _transitionGate.owns(lease, expected: PlaybackTransition.recoveringLive) &&
        _live.session == session;
    try {
      final streamUrl = await session.streamUrlAt();
      if (streamUrl == null || !isCurrent()) return;
      appLogger.i('Live TV: reopening ${channel.displayName} in software');
      _live.markStreamRestartedAtLiveEdge(session.captureBuffer);
      await _openLiveStream(
        currentPlayer,
        streamUrl,
        targetEpoch: session.captureBuffer == null ? null : _live.streamStartEpoch.round(),
        channel: playing,
      );
    } catch (e, stackTrace) {
      appLogger.w('Live TV: software reopen failed', error: e, stackTrace: stackTrace);
    } finally {
      _transitionGate.release(lease);
    }
  }

  /// Re-opens the current session's live stream at [streamUrl].
  ///
  /// Offset-based MPV opens register their requested absolute [targetEpoch]
  /// before `loadfile` and bind that registration to the source id the load
  /// reports, so only that source's events can calibrate it. When [awaitClock]
  /// is true, success means the new source's first rendered player position
  /// has been mapped to that epoch.
  Future<bool> _openLiveStream(
    Player player,
    String streamUrl, {
    int? targetEpoch,
    bool awaitClock = false,
    bool? play,
    bool applyOptions = true,
    bool timeShifted = false,
    void Function()? onOpenStarted,
    LiveTvPlaybackSession? session,
    LiveTvChannel? channel,
  }) async {
    if (_shuttingDown || !_launchCurrent) return false;
    _live.streamGeneration++;
    // The session this stream belongs to: a zap, a recovery and a copy switch
    // adopt theirs only after the open, and the headers are that copy's own.
    final openSession = session ?? _live.session;
    final media = Media(streamUrl, headers: _liveMediaHeaders(openSession));
    final playNow = play ?? automotivePlaybackAllowedNow();
    if (targetEpoch == null || player is! PlayerNative) {
      if (applyOptions) await _setLiveStreamOptions(player, session: session, channel: channel);
      if (_shuttingDown || !_launchCurrent) return false;
      onOpenStarted?.call();
      _armLiveDecodeGuard(player, timeShifted: timeShifted);
      _armLiveVariantFallback(player, openSession, timeShifted: timeShifted);
      _armLiveStallGuard(player, timeShifted: timeShifted);
      await player.open(media, play: playNow, isLive: true);
      return true;
    }

    final clockGeneration = _live.beginClockOpen(targetEpoch);
    final clockResult = _live.clockOpenResult(clockGeneration);
    final int? sourceId;
    try {
      if (applyOptions) await _setLiveStreamOptions(player, session: session, channel: channel);
      if (_shuttingDown || !_launchCurrent) return false;
      onOpenStarted?.call();
      _armLiveDecodeGuard(player, timeShifted: timeShifted);
      _armLiveVariantFallback(player, openSession, timeShifted: timeShifted);
      _armLiveStallGuard(player, timeShifted: timeShifted);
      sourceId = await player.open(media, play: playNow, isLive: true, startLivePlaylistFromBeginning: timeShifted);
    } catch (_) {
      _live.failClockOpen(clockGeneration);
      rethrow;
    }
    if (sourceId == null) {
      // The load never reached mpv (core unavailable), so no source will ever
      // report for this open.
      _live.failClockOpen(clockGeneration);
      return false;
    }
    _live.bindClockOpen(clockGeneration, sourceId);

    if (!awaitClock) {
      unawaited(clockResult);
      return true;
    }
    return clockResult.timeout(
      _liveClockReadyTimeout,
      onTimeout: () {
        _live.timeoutClockOpen(clockGeneration);
        appLogger.w('Live time-shift source did not report a rendered clock position');
        return false;
      },
    );
  }

  /// Arm display negotiation for a live open that tunes a channel — the
  /// launch and every zap. Android mpv and Apple TV open the stream paused
  /// and negotiate from what the player presents at its first frame, the way
  /// a VOD open does ([_firstFrameStartupPlan]). Broadcast is where
  /// interlaced video lives, and a MediaCodec decoder that deinterlaces by
  /// itself presents one frame per field with only the measured cadence to
  /// say so: matched from the container rate, 1080i25 got a 25 Hz mode that
  /// dropped every other frame and let video fall behind audio (#2568).
  ///
  /// [firstFrame] is the open's first-frame signal, armed before the open:
  /// the launch's attempt outcome, or the one a zap arms for itself. Null —
  /// open as before — on ExoPlayer, which keeps its post-first-frame
  /// detection, and on desktop. Time-shift seeks, subtitle rebuilds and
  /// stream recovery reopen the same channel and keep its negotiated mode.
  ///
  /// [firstFrame] is only called when there is something to match: with
  /// nothing to match a channel opens as it always did (Plebz) — live matching
  /// is off by default, and the seamless preview turns it off.
  _FrameRateStartupPlan? _armLiveDisplayNegotiation(Player currentPlayer, PlaybackOpenOutcome Function() firstFrame) {
    final plan = _firstFrameStartupPlan(currentPlayer, SettingsService.instance, hasVideoUrl: true);
    if (plan == null || !plan.needsFirstFrameSwitch) return null;
    _frameRate.resetForNewItem();
    if (plan.countsAsApplied) _frameRate.applied = true;
    plan.armFirstFrameGate(firstFrame(), _frameRate);
    return plan;
  }

  /// Release a gate [_armLiveDisplayNegotiation] armed: negotiate the display
  /// at the stream's first frame, then resume it. Runs once the start or zap
  /// gave up its transition lock, so a channel that never shows a frame
  /// cannot hold the next zap up. Any later live open (zap, recovery,
  /// time-shift seek, subtitle rebuild) supersedes it and owns the play state
  /// it leaves. [stream] is the [LiveTvSessionState.streamGeneration] the
  /// gated open produced; null when that open did not commit, which only
  /// releases the first-frame hold.
  Future<void> _releaseLiveDisplayNegotiation(
    Player currentPlayer,
    _FrameRateStartupPlan plan, {
    required int? stream,
  }) async {
    final generation = _transitionGate.generation;
    try {
      if (stream == null || !plan.holdPlaybackStart) return;
      await _releaseFrameRateStartupGate(
        currentPlayer: currentPlayer,
        settingsService: SettingsService.instance,
        plan: plan,
        isCurrent: () => _isCurrentPlaybackGeneration(generation, currentPlayer) && _live.streamGeneration == stream,
        resumeAfterStartupGate: (reason) =>
            _resumeAfterFrameRateStartupGate(currentPlayer: currentPlayer, reason: reason),
      );
    } finally {
      _frameRate.endDisplayNegotiation(plan.displayNegotiation);
    }
  }

  int _liveEpochForPosition(Duration position) => _liveSeek.pendingEpoch ?? _live.epochForPosition(position);

  /// Current playback position in absolute epoch seconds.
  int get _rawPositionEpoch => _live.epochForPosition(player?.currentPosition ?? Duration.zero);

  /// While a relative skip is queued, its accumulated target remains
  /// authoritative until the replacement source clock is calibrated.
  int get _currentPositionEpoch => _liveEpochForPosition(player?.currentPosition ?? Duration.zero);

  /// Show "Watch from Start" / "Watch Live" dialog.
  /// Returns true if user chose "Watch from start", false for "Watch Live", null if dismissed.
  Future<bool?> _showWatchFromStartDialog(int effectiveStartEpoch, int nowEpoch) {
    final minutesAgo = ((nowEpoch - effectiveStartEpoch) / 60).round();
    return showOptionPickerDialog<bool>(
      context,
      title: t.liveTv.joinSession,
      options: [
        (icon: Symbols.replay_rounded, label: t.liveTv.watchFromStart(minutes: minutesAgo), value: true),
        (icon: Symbols.live_tv_rounded, label: t.liveTv.watchLive, value: false),
      ],
    );
  }

  /// Seek the live TV stream to an absolute epoch second by rebuilding the
  /// stream at the target offset. The session returns null when the backend
  /// can't time-shift (Jellyfin), and its capture buffer is null there too,
  /// so both guards cover it. Returns whether the rebuilt stream was opened.
  Future<bool> _seekLivePosition(int targetEpochSeconds) async {
    final currentPlayer = player;
    if (_shuttingDown || currentPlayer == null) return false;
    final session = _live.session;
    final buffer = _live.captureBuffer;
    if (session == null || buffer == null) return false;

    final clamped = targetEpochSeconds.clamp(buffer.seekableStartEpoch, buffer.seekableEndEpoch);
    final offsetSeconds = clamped - buffer.startedAt.round();

    final streamUrl = await session.streamUrlAt(offsetSeconds: offsetSeconds, subtitleTrack: _live.selectedSubtitle);
    if (streamUrl == null || !mounted || _shuttingDown || player != currentPlayer) return false;

    if (currentPlayer is! PlayerNative) {
      _live.streamStartEpoch = buffer.startedAt + offsetSeconds;
    }
    _live.atLiveEdge = (clamped >= buffer.seekableEndEpoch - VideoPlayerScreenState._liveEdgeThresholdSeconds);
    _live.playbackStartTime = DateTime.now();

    final opened = await _openLiveStream(
      currentPlayer,
      streamUrl,
      targetEpoch: clamped,
      awaitClock: currentPlayer is PlayerNative,
      timeShifted: true,
    );
    if (!mounted || player != currentPlayer) return false;
    _setPlayerState(() {});
    return opened;
  }

  /// Apply a source subtitle choice to the live stream by rebuilding it with
  /// the backend's server-side delivery (Plex points the part's selection at
  /// the stream and burns it). The live counterpart of the VOD source switch:
  /// same [PlaybackSourceSubtitleChoice], but the restart is the raw
  /// `streamUrlAt → open(isLive: true)` every live URL change uses.
  Future<PlaybackSourceChangeOutcome> _switchLiveSubtitle(PlaybackSourceSubtitleChoice choice) async {
    final currentPlayer = player;
    final session = _live.session;
    if (currentPlayer == null || session == null) return PlaybackSourceChangeOutcome.unavailable;

    MediaSubtitleTrack? target;
    if (!choice.isOff) {
      for (final track in session.subtitleTracks) {
        if (track.id == choice.sourceStreamId) {
          target = track;
          break;
        }
      }
      if (target == null) return PlaybackSourceChangeOutcome.unavailable;
    }
    final previous = _live.selectedSubtitle;
    if (target?.id == previous?.id) return PlaybackSourceChangeOutcome.unchanged;

    _live.selectedSubtitle = target;

    // Keep the viewer's position: rebuild at the time-shift offset when
    // behind the live edge, otherwise re-open at the edge.
    if (_live.captureBuffer != null && !_live.atLiveEdge) {
      if (await _seekLivePosition(_currentPositionEpoch)) return PlaybackSourceChangeOutcome.applied;
      _live.selectedSubtitle = previous;
      return PlaybackSourceChangeOutcome.failed;
    }

    final streamUrl = await session.streamUrlAt(subtitleTrack: target);
    if (!mounted || player != currentPlayer || _live.session != session) {
      return PlaybackSourceChangeOutcome.superseded;
    }
    if (streamUrl == null) {
      _live.selectedSubtitle = previous;
      return PlaybackSourceChangeOutcome.failed;
    }
    _live.markStreamRestartedAtLiveEdge(_live.captureBuffer);
    await _openLiveStream(
      currentPlayer,
      streamUrl,
      targetEpoch: _live.captureBuffer == null ? null : _live.streamStartEpoch.round(),
    );
    if (mounted) _setPlayerState(() {});
    return PlaybackSourceChangeOutcome.applied;
  }

  /// Current seekable epoch window for [_liveSeek], or null when there is no
  /// live capture buffer.
  LiveSeekBounds? _liveSeekBounds() {
    final buffer = _live.captureBuffer;
    if (buffer == null) return null;
    return (start: buffer.seekableStartEpoch, end: buffer.seekableEndEpoch);
  }

  /// Rebuild and refresh live-edge state when [_liveSeek]'s pending target
  /// changes (a skip was accumulated, or the post-seek pin was released).
  void _onLiveSeekTargetChanged() {
    if (!mounted) return;
    final pending = _liveSeek.pendingEpoch;
    final buffer = _live.captureBuffer;
    // Hold the picture while the viewer skips: what plays now is about to be
    // left, and the re-open at the target starts playback again (Plebz).
    final currentPlayer = player;
    if (pending != null && currentPlayer != null && currentPlayer.state.playing) {
      unawaited(currentPlayer.pause());
    }
    _setPlayerState(() {
      if (pending != null && buffer != null) {
        _live.atLiveEdge = pending >= buffer.seekableEndEpoch - VideoPlayerScreenState._liveEdgeThresholdSeconds;
      }
    });
  }

  /// Re-open the live stream at [targetEpochSeconds], logging failures.
  Future<bool> _runLiveSeek(int targetEpochSeconds) async {
    try {
      final opened = await _seekLivePosition(targetEpochSeconds);
      if (!opened) {
        appLogger.w('Live time-shift seek did not reach a calibrated source');
      }
      return opened;
    } catch (e, st) {
      appLogger.w('Live time-shift seek failed', error: e, stackTrace: st);
      return false;
    }
  }

  /// Seek the live stream to an absolute epoch (scrubber / jump-to-live). Drops
  /// any pending relative-skip burst first so a queued seek can't override it.
  Future<void> _seekLiveToEpoch(int targetEpochSeconds) async {
    _liveSeek.cancel();
    await _runLiveSeek(targetEpochSeconds);
  }

  Future<void> _jumpToLiveEdge() async {
    if (_live.captureBuffer == null) return;
    await _seekLiveToEpoch(_live.captureBuffer!.seekableEndEpoch);
  }

  /// The groups the loaded channels fall into, in the order they appear, with
  /// the name the guide shows them under.
  List<LiveChannelGroupOption> _liveGroupOptions() {
    final channels = widget.live?.channels ?? const <LiveTvChannel>[];
    final counts = <String, int>{};
    for (final channel in channels) {
      final group = liveTvChannelGroup(channel);
      if (group == null) continue;
      counts[group] = (counts[group] ?? 0) + 1;
    }
    if (counts.length < 2) return const [];
    final hidePrefix = SettingsService.instanceOrNull?.read(PlebzPrefs.iptvHideGroupCountryPrefix) ?? false;
    return [
      (key: null, label: t.liveTv.allChannels, count: channels.length),
      for (final entry in counts.entries)
        (key: entry.key, label: liveTvGroupLabel(entry.key, stripCountryPrefix: hidePrefix), count: entry.value),
    ];
  }

  /// Confine the session to [group] and tune its first channel.
  ///
  /// Tuning is what makes the choice real: a group the viewer picked but is
  /// not watching would leave the picture where it was and the list somewhere
  /// else.
  Future<void> _selectLiveGroup(String? group) async {
    if (_live.activeGroup == group) return;
    setStateIfMounted(() => _live.activeGroup = group);
    _rememberLiveSelection();
    final channels = _live.channelsIn(widget.live?.channels ?? const []);
    if (channels.isEmpty) return;
    final playing = _currentLiveChannel;
    if (playing != null && channels.any((c) => liveTvChannelScopeKey(c) == liveTvChannelScopeKey(playing))) {
      // Already inside the new group — the viewer keeps watching what they
      // were watching, and only the list around it narrows.
      return;
    }
    await _tuneVisibleChannel(0);
  }

  /// Tune the channel at [index] of the group-narrowed list.
  Future<void> _tuneVisibleChannel(int index) async {
    final all = widget.live?.channels;
    if (all == null || all.isEmpty) return;
    final visible = _live.channelsIn(all);
    if (index < 0 || index >= visible.length) return;
    final target = liveTvChannelScopeKey(visible[index]);
    final absolute = all.indexWhere((channel) => liveTvChannelScopeKey(channel) == target);
    if (absolute < 0) return;
    await _switchLiveChannel(absolute - _live.channelIndex);
  }

  /// Hand the guide where this session ended up, so returning to it lands on
  /// what was being watched rather than on what was open when the player
  /// started.
  void _rememberLiveSelection() {
    final channel = _currentLiveChannel;
    LiveTvLastSelection.instance.record(
      channelKey: channel == null ? null : liveTvChannelScopeKey(channel),
      group: _live.activeGroup,
    );
  }

  Future<void> _switchLiveChannel(int delta) async {
    if (_shuttingDown) return;
    final channels = widget.live?.channels;
    if (channels == null || channels.isEmpty) return;
    final newIndex = _live.channelIndex + delta;
    if (newIndex < 0 || newIndex >= channels.length) return;
    final currentPlayer = player;
    if (currentPlayer == null) return;
    _liveStallBudget.reset();

    // Zapping away from a failing channel must not wait out its recovery (a
    // re-tune can take the whole tune budget): the zap replaces that stream,
    // so it supersedes the recovery, which discards whatever it recovered.
    if (_transitionGate.transition == PlaybackTransition.recoveringLive) {
      _transitionGate.forceIdle();
      _live.retrying = false;
    }
    final transitionLease = _transitionGate.tryAcquire(PlaybackTransition.switchingChannel);
    if (transitionLease == null) return; // debounce concurrent switches
    final replacement = _live.beginReplacement();
    var committed = false;
    bool isCurrentChannelSwitch() =>
        mounted &&
        !_shuttingDown &&
        player == currentPlayer &&
        _transitionGate.owns(transitionLease, expected: PlaybackTransition.switchingChannel);
    _liveSeek.cancel();

    final previousSession = _live.session;
    final previousFirstFrame = _firstFrame.snapshot();
    final channel = channels[newIndex];
    appLogger.d('Switching to channel: ${channel.displayName} (${channel.key})');

    // The picture stays on the last frame of the channel being left until the
    // new one renders. Nothing clears the video surface between two opens, so
    // the freeze costs nothing — the black it replaces was this screen
    // painting over a surface that still held a perfectly good frame.
    _isSwitchingChannel.value = true;

    LiveTvPlaybackSession? session;
    var replacementOpenStarted = false;
    PlaybackOpenOutcome? zapOutcome;
    _FrameRateStartupPlan? frameRatePlan;
    int? openedStream;
    try {
      // Channel switch IS a fresh start: same resolution path as launch. Keep
      // the old session alive until the replacement stream is actually open so
      // a failed zap does not tell the server to reclaim the still-playing
      // tuner/transcode session.
      session = await _startLiveSession(channel);
      if (session == null) {
        // Jellyfin's negotiation returns null instead of throwing, so this
        // is not covered by the catch below; without feedback a failed zap
        // looks like a dead remote (#2198).
        if (mounted) showErrorSnackBar(context, t.liveTv.failedToStartChannel);
        return;
      }
      if (!isCurrentChannelSwitch()) {
        _abandonLiveSession(session);
        return;
      }

      final streamUrl = await session.streamUrlAt();
      if (streamUrl == null || !isCurrentChannelSwitch()) {
        _abandonLiveSession(session);
        return;
      }

      // Only the reporting latch: the *UI* readiness flag stays true, which
      // is what keeps the outgoing channel's last frame on screen. Clearing
      // it would make `Video` paint its opaque backing over a surface that
      // still holds a perfectly good picture — the black this zap exists to
      // avoid. The spinner still comes up; it rides `_isSwitchingChannel`.
      _firstFrame.resetRenderedForAttempt();
      _live.markStreamRestartedAtLiveEdge(session.captureBuffer);
      final targetEpoch = session.captureBuffer == null ? null : _live.streamStartEpoch.round();
      // A zap starts no playback attempt, so it arms its own first-frame
      // signal; the deadline bounds a stream that stops moving before one.
      frameRatePlan = _armLiveDisplayNegotiation(
        currentPlayer,
        () => zapOutcome = PlaybackOpenOutcome.arm(currentPlayer, deadline: VideoPlayerScreenState._openDeadline),
      );
      final opened = await _openLiveStream(
        currentPlayer,
        streamUrl,
        targetEpoch: targetEpoch,
        session: session,
        channel: channel,
        play: (frameRatePlan?.holdPlaybackStart ?? false) ? false : null,
        onOpenStarted: () {
          replacementOpenStarted = true;
          // The native state belongs to the replacement from this point,
          // before its session/channel is adopted after timeline reporting.
          // Detach the receipt, not the screen's launch lifetime fence.
          widget.launchObserver?.detach();
        },
      );
      if (opened) openedStream = _live.streamGeneration;
      if (!isCurrentChannelSwitch()) {
        _abandonLiveSession(session);
        return;
      }

      // The new stream is now the active local playback. Stop the old heartbeat
      // and send its terminal timeline before adopting the replacement session.
      _stopLiveTimelineUpdates();
      if (previousSession != null) {
        await _sendLiveTimeline('stopped');
      }
      if (!isCurrentChannelSwitch()) {
        _abandonLiveSession(session);
        return;
      }

      _live.adoptSession(session);
      _live.fallbackLevel = 0;
      committed = true;

      if (!mounted) return;
      _setPlayerState(() {
        _live.channelIndex = newIndex;
        _rememberLiveSelection();
        _live.channelName = channel.displayName;
        _currentMetadata = _liveChannelItem(channel);
      });
      _showZapBanner();

      // The screen now describes a different channel: republish before the
      // heartbeats restart, or the OS controls, the client lookups and the
      // scoped player preferences stay pinned to the channel tuned first.
      final mediaControlsManager = _mediaControlsManager;
      if (mediaControlsManager != null) {
        unawaited(
          mediaControlsManager.updateMetadata(
            metadata: _currentMetadata,
            client: _getOnlineMediaServerClient(context),
            duration: null,
          ),
        );
      }
      unawaited(_mediaControls.syncAvailability());

      // Restart timeline heartbeats for the new session
      _startLiveTimelineUpdates();
    } catch (e) {
      // A session that tuned but was never adopted (streamUrlAt/open threw)
      // would otherwise hold its server-side tuner until the backend times out.
      final orphan = session;
      if (orphan != null && _live.session != orphan) _abandonLiveSession(orphan);
      if (!isCurrentChannelSwitch()) return;
      if (replacementOpenStarted && mounted && _live.session == previousSession) {
        _setPlayerState(() {
          _firstFrame.restore(previousFirstFrame);
        });
      }
      appLogger.e('Failed to switch channel', error: e);
      if (mounted) showErrorSnackBar(context, t.liveTv.channelSwitchFailed(reason: localizedErrorReason(e)));
    } finally {
      _isSwitchingChannel.value = false;
      _finishLiveReplacement(transitionLease, replacement, committed: committed);
      // The guide ages while a session runs; a zap is the natural moment to
      // re-read it, and it never blocks the picture.
      unawaited(_loadLiveSchedule());
      if (!committed) zapOutcome?.abort('channel switch did not commit');
      final plan = frameRatePlan;
      if (plan != null) {
        await _releaseLiveDisplayNegotiation(currentPlayer, plan, stream: committed ? openedStream : null);
      }
    }
  }

  /// One channel along the group-narrowed list — what UP and DOWN do.
  ///
  /// Not `_switchLiveChannel(±1)`, which steps the *whole* list: with a group
  /// active that walked straight out of it at its first and last channel,
  /// which is the one thing a group is for. It reads through
  /// [LiveTvSessionState.channelsIn] like everything else that walks channels,
  /// so the group the viewer picked — or the one the guide was showing when
  /// they pressed play — is the list they stay in.
  Future<void> _zapChannel(int delta) async {
    final all = widget.live?.channels;
    if (all == null || all.isEmpty || _live.channelIndex < 0) return;
    await _tuneVisibleChannel(_live.visibleIndexIn(all) + delta);
  }

  bool get _hasNextChannel {
    final all = widget.live?.channels;
    if (all == null || all.isEmpty || _live.channelIndex < 0) return false;
    return _live.visibleIndexIn(all) < _live.channelsIn(all).length - 1;
  }

  bool get _hasPreviousChannel {
    final all = widget.live?.channels;
    if (all == null || all.isEmpty || _live.channelIndex < 0) return false;
    return _live.visibleIndexIn(all) > 0;
  }
}
