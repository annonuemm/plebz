part of '../video_controls.dart';

extension _PlexVideoControlsKeyEventMethods on _PlexVideoControlsState {
  Future<void> _initKeyboardService() async {
    _keyboardService = await KeyboardShortcutsService.getInstance();
  }

  void _showScreenshotToast() {
    widget.toastController.show(Symbols.photo_camera_rounded, t.videoControls.screenshotSaved);
  }

  /// The remote's dedicated channel keys, P+/P− on a European remote.
  bool _isChannelKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.channelUp || key == LogicalKeyboardKey.channelDown;

  /// Zap on P+/P−, whether the controls are up or down.
  ///
  /// Unlike the arrow keys these mean nothing else anywhere in the player, so
  /// there is no state in which handling them would steal something. Always
  /// on since 1.9.1 (the switch for them went): a remote without the keys
  /// never sends them, and a device that keeps them for its own tuner never
  /// passes them on.
  KeyEventResult _handleChannelKey(KeyEvent event, LogicalKeyboardKey key) {
    if (!_isChannelKey(key)) return KeyEventResult.ignored;
    if (!_canZapChannels || !widget.canControl) return KeyEventResult.ignored;

    // Key-down only, for the same reason the arrow keys are: a held key would
    // queue switches the tuner cannot keep up with.
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    _flushHiddenDirectionalSeek();
    (key == LogicalKeyboardKey.channelUp ? widget.onPrevious : widget.onNext)?.call();
    return KeyEventResult.handled;
  }

  /// Resolve the transport intent for a key event, or null when the key is not
  /// a transport key. Hardware `mediaPlay`/`mediaPause` stay *directed*; the
  /// configured hotkey is always a toggle.
  TransportCommand? _transportCommandFor(KeyEvent event) {
    // Always accept hardware media transport keys (Android TV remotes)
    final hardware = classifyTransportKey(event.logicalKey);
    if (hardware != null) return hardware;

    final physicalKey = event.physicalKey;

    // When the shortcuts service is available, respect the configured play/pause hotkey
    if (_keyboardService != null) {
      final hotkey = _keyboardService!.hotkeys['play_pause'];
      if (hotkey == null) return null;
      return hotkey.key == physicalKey ? TransportCommand.toggle : null;
    }

    // Fallback to defaults while the service is loading
    if (physicalKey == PhysicalKeyboardKey.space || physicalKey == PhysicalKeyboardKey.mediaPlayPause) {
      return TransportCommand.toggle;
    }
    return null;
  }

  TransportCommand? _playPauseActivation(KeyEvent event) {
    return event is KeyDownEvent ? _transportCommandFor(event) : null;
  }

  /// The player surface's Select action.
  ///
  /// [requestFocus] is the caller's `eventRequestsFocusNavigation` answer, so a
  /// remote OK lands on Play/Pause while a physical-keyboard Enter leaves focus
  /// where it is — activation is not a request to start navigating.
  void _activatePlayerSurfaceSelect({required bool requestFocus}) {
    if (!widget.canControl) {
      _showControlsWithFocus(requestFocus: requestFocus);
      return;
    }
    // Skip-Intro is the primary action only while the chrome is down and the
    // button is the sole affordance on screen; with the OSD up it is a real
    // focusable control and Select must stay "toggle playback".
    if (!_showControls && _isSkipMarkerButtonVisible) {
      _activateSkipMarker();
      return;
    }
    // Raise the chrome *before* toggling: Select is the deliberate "show me the
    // controls" affordance, and the visible chrome suppresses the transient
    // transport disc that would otherwise flash underneath it.
    _showControlsWithFocus(requestFocus: requestFocus);
    // In a live session Select is only ever "show me the controls".
    //
    // It used to pause as well wherever a capture buffer existed — the one
    // case where pausing live is technically possible — but that is not what
    // the press means here. OK on a live picture is how a viewer asks what
    // they are watching and what else is on; stopping the picture to answer is
    // the opposite of the question. Without a buffer it was already this way,
    // since pausing there drops the viewer permanently behind, and having the
    // same key do two different things depending on a property of the channel
    // is not something anyone can learn. Pause has not gone anywhere: it is
    // the first control on the chrome this press just raised.
    if (widget.isLive) return;
    unawaited(_playOrPause());
  }

  /// Whether this live session can be zapped through — the player screen only
  /// hands down a channel list when it launched from one.
  bool get _canZapChannels => widget.isLive && widget.liveChannels.length > 1;

  /// Whether the picture is behind the live edge — the viewer went back, so
  /// the timeline is what they are working in.
  ///
  /// Not "could this be rewound": an IPTV channel with an archive and a Plex
  /// DVR channel can both be rewound at any moment, and asking that question
  /// would cost them the channel list entirely.
  bool get _isTimeShifted => widget.captureBuffer != null && !widget.isAtLiveEdge;

  /// Whether LEFT should open the channel list rather than seek.
  ///
  /// While the picture is live it is the list: that is the one thing LEFT is
  /// good for when there is nothing behind you. Once the viewer has moved
  /// back — an archive programme started from the guide, a recording rewound
  /// — LEFT and RIGHT belong to the timeline they are moving in.
  bool get _leftOpensChannelList => _canZapChannels && !_isTimeShifted && widget.onLiveChannelSelected != null;

  /// Whether RIGHT should offer the groups. Same rule as LEFT, and only where
  /// there is more than one group to move between.
  bool get _rightOpensGroupList =>
      widget.isLive && !_isTimeShifted && widget.liveGroups.length > 1 && widget.onLiveGroupSelected != null;

  /// Raise the chrome, then open one of its lists. A strip lives inside the
  /// chrome, so it can only be opened once that has been raised and laid out.
  void _openStrip(void Function(DesktopVideoControlsState controls) open) {
    _flushHiddenDirectionalSeek();
    _showControlsWithFocus(requestFocus: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controls = _desktopControlsKey.currentState;
      if (mounted && controls != null) open(controls);
    });
  }

  /// Live TV's directional keys while the chrome is down: UP/DOWN zap a
  /// channel each, LEFT opens the channel list. Returns
  /// [KeyEventResult.ignored] when the key is not one of those, so the
  /// ordinary seek/raise-chrome behaviour still runs.
  KeyEventResult _handleHiddenChromeLiveKey(KeyEvent event, LogicalKeyboardKey key) {
    if (!widget.canControl) return KeyEventResult.ignored;
    // A single channel still gets the group list: the groups are how a
    // viewer reaches the rest of the playlist.
    if (!_canZapChannels && !_rightOpensGroupList) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
      // Key-down only: a held key would queue switches the tuner cannot keep
      // up with, and each one costs a stream re-open.
      if (event is! KeyDownEvent) return KeyEventResult.handled;
      _flushHiddenDirectionalSeek();
      // Down goes down the channel list, which is the next channel.
      final zap = key == LogicalKeyboardKey.arrowDown ? widget.onNext : widget.onPrevious;
      zap?.call();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowLeft && _leftOpensChannelList) {
      if (event is! KeyDownEvent) return KeyEventResult.handled;
      _openStrip((controls) => controls.showChannelStrip());
      return KeyEventResult.handled;
    }

    // RIGHT is the other half of the same idea: the channels of this group on
    // one side, the groups themselves on the other.
    if (key == LogicalKeyboardKey.arrowRight && _rightOpensGroupList) {
      if (event is! KeyDownEvent) return KeyEventResult.handled;
      _openStrip((controls) => controls.showGroupStrip());
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  KeyEventResult _handleLocalPlayerNavigationKeyEvent(
    KeyEvent event,
    PlayerNavigationKey navigationKey,
    bool isMobile,
  ) {
    if (navigationKey == PlayerNavigationKey.none || navigationKey == PlayerNavigationKey.home) {
      return KeyEventResult.ignored;
    }
    if (PlatformDetector.isTV() && event is KeyDownEvent) {
      BackKeyCoordinator.markHandled();
    }

    final sheetController = OverlaySheetController.maybeOf(context);
    if (sheetController?.isOpen ?? false) {
      return handlePlayerNavigationKeyAction(event, navigationKey, sheetController!.pop);
    }

    if (widget.chromeController.contentStripVisible) {
      return handlePlayerNavigationKeyAction(event, navigationKey, () {
        final controls = _desktopControlsKey.currentState;
        // A strip opened over the bare picture (live TV's LEFT/RIGHT) closes
        // back to the bare picture. The chrome underneath was raised only to
        // host the strip — leaving it up costs the viewer a second Back, or
        // spends their next dpad press on a control they never asked for.
        final backToPicture = controls?.stripOpenedFromPicture ?? false;
        controls?.dismissContentStrip(restoreFocus: !backToPicture);
        widget.chromeController.setContentStripVisible(false);
        if (backToPicture) {
          _hideControls();
        } else {
          _restartHideTimerForCurrentPlaybackState();
        }
      });
    }

    // A skip prompt is a local layer like the sheet and the content strip
    // above it: Select takes the skip, Back declines it. Without this stage the
    // only key that reads as "no thanks" on a remote is also the one that walks
    // the screen's exit chain, so declining an intro costs the viewer the rest
    // of the episode.
    //
    // The claim is latched for the whole press rather than re-derived per
    // event. handleBackKeyAction consumes the key-down and acts on the key-up,
    // and the button's own 7s dismiss timer — armed for every prompt while
    // auto-skip is off, which is the default — can fire in between. Asking the
    // full question again on the key-up would hand that press back to the
    // screen and exit the player, which is the bug this stage exists to
    // prevent.
    //
    // The button vanishing is the only race the latch covers. The chrome
    // coming up, or a prompt opening, genuinely moves the key back to the
    // screen's stages, so those release the claim mid-press.
    final skipMarkerOwnsPress = event is KeyDownEvent
        ? shouldDismissSkipMarkerOnBack(
            navigationKey: navigationKey,
            controlsVisible: _showControls,
            skipMarkerButtonVisible: _isSkipMarkerButtonVisible,
            canControl: widget.canControl,
            isMobile: isMobile,
            playbackPromptOpen: widget.playbackPromptOpen,
          )
        : _skipMarkerOwnsBackPress && !_showControls && !widget.playbackPromptOpen;
    _skipMarkerOwnsBackPress = event is KeyUpEvent ? false : skipMarkerOwnsPress;
    if (skipMarkerOwnsPress) {
      return handlePlayerNavigationKeyAction(event, navigationKey, _dismissSkipMarker);
    }

    // The enclosing player screen is the sole owner of fullscreen, chrome,
    // prompt, and route-exit stages.
    return KeyEventResult.ignored;
  }

  KeyEventResult _dispatchShortcut(KeyEvent event, {VoidCallback? onSkipMarker}) {
    return _keyboardService!.handleVideoPlayerKeyEvent(
      event,
      widget.player,
      _toggleFullscreen,
      _toggleSubtitles,
      _nextAudioTrack,
      _nextSubtitleTrack,
      _nextChapter,
      _previousChapter,
      canControlPlayback: widget.canControl,
      canNavigateMediaItems: widget.canNavigateMediaItems,
      onPlayPause: () => unawaited(_playOrPause()),
      onToggleShader: _toggleShader,
      onSkipMarker: onSkipMarker,
      onNextEpisode: _abandoningBurst(widget.onNext),
      onPreviousEpisode: _abandoningBurst(widget.onPrevious),
      onScreenshot: _showScreenshotToast,
      onZoomIn: widget.onZoomIn,
      onZoomOut: widget.onZoomOut,
      onZoomReset: widget.onResetVideoZoom,
      onVolumeUp: () => widget.volumeController.adjust(10),
      onVolumeDown: () => widget.volumeController.adjust(-10),
      onToggleMute: widget.volumeController.toggleMute,
      onSpeedPersist: (rate) =>
          unawaited(ScopedPlayerPrefs.write(ScopedPlayerPrefs.playbackSpeed, widget.metadata, rate)),
      onSeekRequested: widget.onSeekRequested,
      onRateRequested: widget.onRateRequested,
      onSeekBy: _keyboardSeekBy,
    );
  }

  /// Global key event handler for focus-independent shortcuts (desktop only)
  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (!mounted) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;

    // Any actionable key (keyboard / dpad / controller) cancels an in-progress
    // auto-skip countdown. Non-consuming — we fall through so the key still
    // performs its normal action. Single cancel point for keys.
    if (event.isActionable) _cancelAutoSkipFromUserInteraction();

    // When an overlay sheet is open (e.g. subtitle search with text fields),
    // don't consume key events — let text input work normally.
    if (OverlaySheetController.maybeOf(context)?.isOpen ?? false) {
      return false;
    }

    // Native key events also continue through the focus tree after global
    // handlers run. Player navigation must only mutate state there.
    if (classifyPlayerNavigationKey(event, isAppleTV: PlatformDetector.isAppleTV()) != PlayerNavigationKey.none) {
      return false;
    }

    // Only handle when video player navigation is disabled (desktop mode without D-pad nav)
    if (videoPlayerNavigationPreference()) return false;

    // Skip on mobile (unless TV)
    final isMobile = PlatformDetector.isMobile(context) && !PlatformDetector.isTV();
    if (isMobile) return false;

    // Handle play/pause globally - works regardless of focus. The screen
    // announces the accepted command with a transient disc, so the chrome
    // stays down and subtitles stay readable (#1676).
    final globalCommand = _playPauseActivation(event);
    if (globalCommand != null) {
      unawaited(_playOrPause(command: globalCommand));
      return true; // Event handled, stop propagation
    }

    // Fallback: handle all other shortcuts when focus has drifted away
    // (e.g. after controls auto-hide). The !hasFocus guard prevents
    // double-handling when the Focus onKeyEvent already processes the event.
    if (!_focusNode.hasFocus && _keyboardService != null) {
      // Drift means focus fell back to a scope or to an ancestor of the
      // controls. A prompt holding focus (Play Next, Still Watching) moves
      // between its buttons with the arrows, so those stay with it.
      if (event.logicalKey.isDpadDirection && _focusRestsOnAnotherControl()) return false;
      final result = _dispatchShortcut(event);
      if (result == KeyEventResult.handled) {
        _focusNode.requestFocus(); // self-heal focus
        return true;
      }
    }

    return false;
  }

  /// Whether primary focus sits on a control outside this one rather than
  /// having drifted to a scope or up to an ancestor of [_focusNode].
  bool _focusRestsOnAnotherControl() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null || primary is FocusScopeNode) return false;
    return !_focusNode.ancestors.contains(primary);
  }

  KeyEventResult _handleControlsKeyEvent(KeyEvent event, bool isMobile) {
    final navigationKey = classifyPlayerNavigationKey(event, isAppleTV: PlatformDetector.isAppleTV());
    final navigationResult = _handleLocalPlayerNavigationKeyEvent(event, navigationKey, isMobile);
    if (navigationResult != KeyEventResult.ignored) {
      return navigationResult;
    }
    if (navigationKey != PlayerNavigationKey.none) return KeyEventResult.ignored;

    // Releasing a key ends its seek burst, before the KeyUp is consumed below.
    // Two independent reasons to fire:
    //  - a released hidden-chrome arrow must reset the acceleration tier even
    //    when nothing is pending, because live TV (and a zero-duration item)
    //    seeks straight through onLiveSeekBy without touching the accumulator;
    //  - any key holding a pending target commits it now, so rebound shortcuts
    //    and Shift+arrow large seeks land promptly rather than on the debounce.
    if (event is KeyUpEvent &&
        ((!_showControls && (event.logicalKey.isLeftKey || event.logicalKey.isRightKey)) ||
            _hiddenSeek.pendingPosition != null)) {
      _flushHiddenDirectionalSeek();
    }

    // Hardware media seek/track keys (Android TV remotes, HID media
    // keyboards). Tested ahead of the actionable filter below and consumed
    // for down, repeat and up alike: anything that escapes this node reaches
    // Android's own MediaSession, whose fixed 15-second fast-forward re-enters
    // the screen once per auto-repeat and drags the playhead minutes away
    // (#1375). Only the initial press acts — the repeats are the same press.
    final seekDirection = classifyPlayerSkipKey(event.logicalKey);
    if (seekDirection != null) {
      // Same chrome treatment every other key reaching here gets: a visible
      // OSD stays up for the press, a hidden one stays down (#1676).
      if (_showControls && event.isActionable) {
        _restartHideTimerForCurrentPlaybackState();
      }
      // Uses chapter navigation when the item has chapters, otherwise a
      // coalesced skip by the configured time.
      if (event is KeyDownEvent && widget.canControl) {
        _seekToChapterWithFeedback(forward: seekDirection == MediaSeekDirection.forward);
      }
      return KeyEventResult.handled;
    }

    // Only handle KeyDown and KeyRepeat events.
    // Consume KeyUp events for navigation keys to prevent leaking to previous routes.
    // Let non-navigation keys (volume, etc.) pass through to the OS.
    if (!event.isActionable) {
      if (!event.logicalKey.isReservedControlKey) return KeyEventResult.ignored;
      return KeyEventResult.handled;
    }

    // Reset hide timer on any keyboard/controller input when controls are visible.
    if (_showControls) {
      _restartHideTimerForCurrentPlaybackState();
    }

    final key = event.logicalKey;
    final transportCommand = _transportCommandFor(event);

    // Always consume transport keys to prevent propagation to background routes.
    // On TV/mobile, handle them here; on desktop, the global handler does it.
    // The chrome deliberately stays down — the screen announces the accepted
    // command with a centred transient disc instead (#1676).
    if (transportCommand != null) {
      if ((videoPlayerNavigationPreference() || isMobile) && event is KeyDownEvent) {
        unawaited(_playOrPause(command: transportCommand));
      }
      return KeyEventResult.handled;
    }

    // Select on the player surface. Only intercept when this Focus node itself
    // holds primary focus — a focused OSD control owns its own activation.
    // Whether the raised chrome also takes focus is the key's own answer, so
    // mode and focus can never disagree: a remote OK starts a focus session, a
    // physical-keyboard Enter just shows the controls and toggles playback.
    if (key.isSelectKey && _focusNode.hasPrimaryFocus) {
      return handleOneShotSelect(
        event,
        () => _activatePlayerSurfaceSelect(requestFocus: eventRequestsFocusNavigation(event, focused: _focusNode)),
      );
    }

    final channelResult = _handleChannelKey(event, key);
    if (channelResult != KeyEventResult.ignored) return channelResult;

    // Stop, Info, CC, audio, guide, last channel, colours and digits (Plebz).
    final remoteResult = _handleRemoteKey(event, key);
    if (remoteResult != KeyEventResult.ignored) return remoteResult;

    // Tab is the deliberate way into the OSD (#1797). With the chrome down,
    // raise it and hand it focus; with the chrome up, let Flutter's app-level
    // Shortcuts run NextFocusAction and walk in, rather than consuming the key
    // into a dead end below. Returning ignored cannot leak to the route below:
    // key dispatch only walks the current focus chain, and covered routes are
    // not on it.
    if (key == LogicalKeyboardKey.tab && _focusNode.hasPrimaryFocus) {
      if (event is! KeyDownEvent) return KeyEventResult.handled;
      if (_showControls) return KeyEventResult.ignored;
      _showControlsWithFocus();
      return KeyEventResult.handled;
    }

    // On desktop/TV, directional input drives the player without the chrome.
    // LEFT/RIGHT seeks in place with a transient badge; UP/DOWN is the
    // deliberate "show me the controls" gesture. Live TV spends both on
    // channels instead — see [_handleHiddenChromeLiveKey].
    if (!isMobile && key.isDpadDirection && playerDirectionalNavigationEnabled()) {
      if (!_showControls) {
        final liveResult = _handleHiddenChromeLiveKey(event, key);
        if (liveResult != KeyEventResult.ignored) return liveResult;

        if (key.isLeftKey || key.isRightKey) {
          if (shouldStartHiddenDirectionalSeek(event)) {
            _hiddenDirectionalSeek(forward: key == LogicalKeyboardKey.arrowRight, isRepeat: event is KeyRepeatEvent);
          }
        } else {
          _flushHiddenDirectionalSeek();
          _showControlsWithFocus();
        }
        return KeyEventResult.handled;
      }
      // Children (DesktopVideoControls) handle navigation first via their own
      // onKeyEvent. Reaching here with the surface still focused means nothing
      // in the chrome owns focus yet — hand it over instead of consuming the
      // key into nothing. This is the same key that just switched the app into
      // keyboard mode, so focus has to become visible or the two diverge.
      if (_focusNode.hasPrimaryFocus) {
        _desktopControlsKey.currentState?.requestPlayPauseFocus();
      }
      return KeyEventResult.handled;
    }

    // Reserved control keys are consumed rather than returned as ignored, so
    // they cannot leak to the route below. Tab is the exception: app-level
    // Shortcuts turn it into NextFocusAction, which is how focus traverses
    // *inside* the chrome, and key dispatch only walks the current focus chain
    // so it cannot reach a covered route anyway.
    final consumeToPreventLeak = key.isReservedControlKey && key != LogicalKeyboardKey.tab;

    // Pass other events to the keyboard shortcuts service.
    if (_keyboardService == null) {
      return consumeToPreventLeak ? KeyEventResult.handled : KeyEventResult.ignored;
    }

    final result = _dispatchShortcut(event, onSkipMarker: _performAutoSkip);
    if (!consumeToPreventLeak) return result;
    return result == KeyEventResult.ignored ? KeyEventResult.handled : result;
  }
}
