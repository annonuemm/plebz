part of '../video_controls.dart';

/// What the remote's extra keys remember between presses, per player.
class _RemoteKeyMemory {
  /// The live channel seen at the last key press, and the one before it.
  int? seenChannel;
  int? previousChannel;

  /// A channel number being typed, and when it is taken as complete.
  String digits = '';
  Timer? digitTimer;
}

final Expando<_RemoteKeyMemory> _remoteKeyMemories = Expando<_RemoteKeyMemory>();

/// The remote's buttons beyond D-pad, OK, back and transport (fork addition;
/// see [RemoteKeyAction]).
extension _PlexVideoControlsRemoteKeys on _PlexVideoControlsState {
  _RemoteKeyMemory get _remoteMemory => _remoteKeyMemories[this] ??= _RemoteKeyMemory();

  /// How long after the last digit a typed channel number is tuned.
  static const Duration _digitPause = Duration(milliseconds: 1500);

  KeyEventResult _handleRemoteKey(KeyEvent event, LogicalKeyboardKey key) {
    _noteLiveChannel();

    final digit = remoteDigit(key);
    if (digit != null && widget.isLive && widget.onLiveChannelSelected != null && widget.liveChannels.isNotEmpty) {
      if (event is KeyDownEvent) _typeChannelDigit(digit);
      return KeyEventResult.handled;
    }

    // A colour key does what the viewer set it to; the other buttons are fixed.
    final colour = colourKeyOf(key);
    final action = colour == null ? classifyRemoteKey(key, keyboardLetters: PlatformDetector.isTV()) : null;
    if (colour == null && action == null) return KeyEventResult.ignored;
    // One press, one action: a held key must not cycle through every track.
    if (event is! KeyDownEvent) return KeyEventResult.handled;

    if (colour != null) {
      _runRemoteFunction(SettingsService.instance.read(SettingsService.remoteButtonPref(colour)));
      return KeyEventResult.handled;
    }
    switch (action!) {
      case RemoteKeyAction.stop:
        _flushHiddenDirectionalSeek();
        final back = widget.onBack;
        if (back != null) {
          back();
        } else {
          unawaited(Navigator.of(context).maybePop());
        }
      case RemoteKeyAction.info:
        _runRemoteFunction(RemoteButtonFunction.controls);
      case RemoteKeyAction.subtitles:
        _runRemoteFunction(RemoteButtonFunction.subtitles);
      case RemoteKeyAction.audioTrack:
        _runRemoteFunction(RemoteButtonFunction.audioTrack);
      case RemoteKeyAction.channelList:
        _runRemoteFunction(RemoteButtonFunction.channelList);
      case RemoteKeyAction.lastChannel:
        _runRemoteFunction(RemoteButtonFunction.lastChannel);
    }
    return KeyEventResult.handled;
  }

  /// One of the things a remote button can be set to do.
  void _runRemoteFunction(RemoteButtonFunction function) {
    switch (function) {
      case RemoteButtonFunction.none:
        return;
      case RemoteButtonFunction.controls:
        if (_showControls) {
          _hideControls();
        } else {
          _showControlsWithFocus();
        }
      case RemoteButtonFunction.subtitles:
        if (widget.canControl) _toggleSubtitles();
      case RemoteButtonFunction.audioTrack:
        _nextAudioTrack();
      case RemoteButtonFunction.skipMarker:
        if (widget.canControl) _activateSkipMarker();
      case RemoteButtonFunction.channelList:
        if (_leftOpensChannelList && widget.canControl) {
          _openStrip((controls) => controls.showChannelStrip());
        }
      case RemoteButtonFunction.lastChannel:
        final previous = _remoteMemory.previousChannel;
        final select = widget.onLiveChannelSelected;
        if (widget.isLive && widget.canControl && previous != null && select != null) {
          if (previous >= 0 && previous < widget.liveChannels.length) select(previous);
        }
      case RemoteButtonFunction.description:
        // Live TV's summary is the launch placeholder, not what is on air —
        // the controls leave it out for the same reason.
        final text = widget.isLive ? null : widget.metadata.summary?.trim();
        if (text != null && text.isNotEmpty) _openRemoteSheet((_) => DescriptionSheet(text: text));
      case RemoteButtonFunction.playerSettings:
        _openRemoteSheet((_) => VideoSettingsSheet(player: widget.player, trackControlsState: _remoteTrackState()));
      case RemoteButtonFunction.tracks:
        _openRemoteSheet((_) => TrackSheet(player: widget.player, trackControlsState: _remoteTrackState()));
      case RemoteButtonFunction.chapters:
        if (_chapters.isEmpty) return;
        _openRemoteSheet(
          (_) => ChapterSheet(
            player: widget.player,
            chapters: _chapters,
            chaptersLoaded: _chaptersLoaded,
            canControl: widget.canControl,
            serverId: widget.metadata.serverId,
            onSeekRequested: widget.onSeekRequested,
            onSeekCompleted: widget.onSeekCompleted,
          ),
        );
    }
  }

  TrackControlsState _remoteTrackState() => _buildTrackControlsState(
    playbackState: context.read<PlaybackStateProvider>(),
    onToggleAlwaysOnTop: _toggleAlwaysOnTop,
  );

  /// One of the chrome's sheets, opened straight from a key: the chrome stays
  /// up while it is open, as when its button opens it.
  void _openRemoteSheet(WidgetBuilder builder) {
    final sheets = OverlaySheetController.maybeOf(context);
    if (sheets == null || sheets.isOpen) return;
    _flushHiddenDirectionalSeek();
    widget.chromeController.cancelAutoHide();
    unawaited(
      sheets.show(builder: builder).whenComplete(() {
        if (mounted) _startHideTimer();
      }),
    );
  }

  /// Keeps the channel watched before this one, for the last-channel key —
  /// however the switch came about, by key, list or guide.
  void _noteLiveChannel() {
    if (!widget.isLive) return;
    final memory = _remoteMemory;
    final current = widget.liveChannelIndex;
    if (current < 0 || current == memory.seenChannel) return;
    if (memory.seenChannel != null) memory.previousChannel = memory.seenChannel;
    memory.seenChannel = current;
  }

  void _typeChannelDigit(int digit) {
    final memory = _remoteMemory;
    if (memory.digits.length >= 4) memory.digits = '';
    memory.digits += '$digit';
    widget.toastController.show(
      Symbols.dialpad_rounded,
      t.videoControls.channelNumberTyped(number: memory.digits),
      duration: _digitPause + const Duration(milliseconds: 300),
    );
    memory.digitTimer?.cancel();
    memory.digitTimer = Timer(_digitPause, _tuneTypedChannel);
  }

  void _tuneTypedChannel() {
    final memory = _remoteMemory;
    final typed = memory.digits;
    memory.digits = '';
    if (!mounted || typed.isEmpty) return;
    final select = widget.onLiveChannelSelected;
    if (select == null || !widget.canControl) return;
    final index = channelIndexForNumber([for (final channel in widget.liveChannels) channel.number], typed);
    if (index < 0) {
      widget.toastController.show(Symbols.dialpad_rounded, t.videoControls.channelNumberMissing(number: typed));
      return;
    }
    if (index != widget.liveChannelIndex) select(index);
  }
}
