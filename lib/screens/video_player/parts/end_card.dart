part of '../../video_player_screen.dart';

/// The end card (Plebz, the user's design 2026-10-14) — one of the three ways
/// an episode can close ([PlebzPrefs.endOfEpisodeStyle]). The card itself is
/// [PlayerEndCard]; this is when it comes, what it counts, and where the
/// picture goes.
///
/// - It opens on its own when the credits begin (the server's marker) or,
///   without one, at [endCardFraction] of the runtime; and with Back from
///   [PlebzPrefs.endCardBackFrom] percent on.
/// - It counts nothing while the episode plays out in its box; at its end the
///   play-next countdown runs and then the next episode starts. Play starts it
///   at once.
/// - Back on it grows the picture back to the whole screen and stops the
///   count; Back past the chosen share opens it again, every time, and its
///   "Beenden" leaves the player.
extension _VideoPlayerEndCardMethods on VideoPlayerScreenState {
  EndOfEpisodeStyle get _endOfEpisodeStyle =>
      SettingsService.instanceOrNull?.read(PlebzPrefs.endOfEpisodeStyle) ?? EndOfEpisodeStyle.upNextPanel;

  bool get _endCardChosen => !widget.isLive && _endOfEpisodeStyle == EndOfEpisodeStyle.endCard;

  /// Whether this player can move its picture into the card's box, rather
  /// than the box showing the episode's still.
  bool get _endCardMovesPicture => switch (player) {
    final VideoViewportTarget plane when Platform.isAndroid => plane.followsVideoRect,
    final VideoRectTarget _ when Platform.isIOS || Platform.isMacOS => true,
    _ => false,
  };

  /// Puts the playing picture at [box] (logical pixels), or back on the whole
  /// screen.
  void _placeEndCardPicture(Rect? box) {
    final currentPlayer = player;
    if (currentPlayer == null || !mounted) return;
    final view = View.of(context);
    final ratio = view.devicePixelRatio;
    final screen = Offset.zero & (view.physicalSize / ratio);
    final rect = box ?? screen;
    switch (currentPlayer) {
      case final VideoViewportTarget plane when Platform.isAndroid && plane.followsVideoRect:
        plane.videoRectDriven = box != null;
        unawaited(
          plane.driveVideoRect(
            left: (rect.left * ratio).floor(),
            top: (rect.top * ratio).floor(),
            right: (rect.right * ratio).ceil(),
            bottom: (rect.bottom * ratio).ceil(),
          ),
        );
      case final VideoRectTarget target when Platform.isIOS || Platform.isMacOS:
        unawaited(
          target.setVideoRect(
            left: (rect.left * ratio).floor(),
            top: (rect.top * ratio).floor(),
            right: (rect.right * ratio).ceil(),
            bottom: (rect.bottom * ratio).ceil(),
            devicePixelRatio: ratio,
          ),
        );
      default:
        break;
    }
  }

  /// From the position stream, as the panel is: opens the card when its time
  /// has come, keeps its remaining time current, and closes it after a seek
  /// back out of the end or once the next episode it started is showing.
  void _evaluateEndCard(Duration position, Duration duration) {
    if (_endCardOpen && _endCardStarting) {
      // The next episode, started from the card, has its picture: it grows
      // out of the box to the whole screen.
      if (_currentMetadata.globalKey != _endCardCurrent?.globalKey && _firstFrame.uiReady.value) _closeEndCard();
      return;
    }
    if (_endCardChosen && _episode.next == null && position.inMilliseconds >= duration.inMilliseconds * 0.8) {
      _primeEndCardSuggestion();
    }
    if (!_endCardChosen || !_endCardHasContent) {
      if (_endCardOpen) _closeEndCard();
      return;
    }
    final left = duration > position ? duration - position : Duration.zero;
    if (_endCardOpen) {
      if (_endCardCountdown == null) _endCardRemaining.value = left;
      final stillDue = _endCardOpenedByBack
          ? endCardBackOpens(position: position, duration: duration, percent: _endCardBackFromPercent)
          : shouldOpenEndCard(position: position, duration: duration, creditsStart: _creditsStartOfThisEpisode);
      if (!stillDue) _closeEndCard();
      return;
    }
    if (_endCardBackedOutFor == _currentMetadata.globalKey) return;
    if (shouldOpenEndCard(position: position, duration: duration, creditsStart: _creditsStartOfThisEpisode)) {
      _openEndCard(byBack: false);
    }
  }

  int get _endCardBackFromPercent => SettingsService.instanceOrNull?.read(PlebzPrefs.endCardBackFrom) ?? 95;

  /// Whether Back, now, opens the card rather than leaving the player.
  bool get _backOpensEndCard {
    // Always, even after it was put away: Back is the way to it by hand (the
    // user's call). From here on Back only moves between the card and the
    // whole screen; "Beenden" on the card leaves.
    if (!_endCardChosen || _endCardOpen || !_endCardHasContent) return false;
    final state = player?.state;
    if (state == null) return false;
    return endCardBackOpens(position: state.position, duration: state.duration, percent: _endCardBackFromPercent);
  }

  /// Something to set beside the playing title: the next episode, or else a
  /// suggestion like it.
  bool get _endCardHasContent =>
      _episode.next != null || _endCardSuggestionFor == _currentMetadata.globalKey && _endCardSuggestion != null;

  /// Fetches, once per title, one like it for when nothing follows (Plebz,
  /// the user's call 2026-10-14): a series' last episode suggests another
  /// series, a film another film, from the server's "more like this".
  void _primeEndCardSuggestion() {
    final item = _currentMetadata;
    if (_offlineLibraryMode || _endCardSuggestionFor == item.globalKey) return;
    _endCardSuggestionFor = item.globalKey;
    _endCardSuggestion = null;
    final isEpisode = item.kind == MediaKind.episode;
    final id = isEpisode ? item.grandparentId : item.id;
    if (id == null) return;
    final client = context.tryGetMediaClientForServer(serverIdOrNull(item.serverId));
    if (client == null) return;
    unawaited(() async {
      try {
        final hubs = await client.fetchRelatedHubs(id, count: 12);
        final pick = pickEndCardSuggestion(hubs, kind: isEpisode ? MediaKind.show : MediaKind.movie, exclude: {id});
        if (pick != null && mounted && _endCardSuggestionFor == item.globalKey) {
          setStateIfMounted(() => _endCardSuggestion = pick);
        }
      } catch (e) {
        appLogger.d('End card: no suggestion for ${item.globalKey}', error: e);
      }
    }());
  }

  void _openEndCard({required bool byBack, bool atEnd = false}) {
    final suggests = _episode.next == null;
    final next = suggests ? _endCardSuggestion : (_upNextDetails ?? _episode.next);
    if (next == null) return;
    final state = player?.state;
    final position = state?.position ?? Duration.zero;
    final duration = state?.duration ?? Duration.zero;
    _endCardTimer?.cancel();
    _chromeController.hide(ignoreHolds: true);
    setStateIfMounted(() {
      _endCardOpen = true;
      _endCardOpenedByBack = byBack;
      _endCardStarting = false;
      _endCardCurrent = _currentMetadata;
      _endCardNext = next;
      _endCardSuggests = suggests;
      _endCardCountdown = null;
    });
    _endCardRemaining.value = atEnd || duration <= position ? null : duration - position;
    _endCardPlayLabel.value = suggests ? t.videoControls.endCardDetails : t.videoControls.endCardPlayNow;
    // Nothing starts on its own from a suggestion: the card stays.
    if (atEnd && !suggests) _startEndCardCountdown();
  }

  /// The episode has ended under the card: the play-next countdown runs, and
  /// then the next episode starts. Before the end nothing counts — the
  /// episode plays out in its box (the user's call, 2026-10-14: the card
  /// waits for the end, it does not cut it short).
  void _startEndCardCountdown() {
    final settings = SettingsService.instanceOrNull;
    if (!(settings?.read(SettingsService.autoPlayNextEpisode) ?? true)) return;
    final countdown = settings?.read(SettingsService.playNextCountdown) ?? 5;
    _endCardTimer?.cancel();
    // Over: nothing left to name under the box.
    _endCardRemaining.value = null;
    if (countdown <= 0) {
      _endCardPlayNow();
      return;
    }
    setStateIfMounted(() => _endCardCountdown = countdown);
    _setEndCardCountdownLabel(countdown);
    _endCardTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || !_endCardOpen) {
        timer.cancel();
        return;
      }
      // Held while the app is out of sight, as Plezy's countdown is.
      if (_playNextPromptBackgrounded()) return;
      final left = (_endCardCountdown ?? 0) - 1;
      _endCardCountdown = left;
      _setEndCardCountdownLabel(left);
      if (left <= 0) {
        timer.cancel();
        _endCardPlayNow();
      }
    });
  }

  void _setEndCardCountdownLabel(int seconds) =>
      _endCardPlayLabel.value = t.videoControls.endCardStartsIn(time: '${seconds.clamp(0, 999)} s');

  /// Back on the card, or its "watch the credits": the picture grows back and
  /// the count stops; the card does not come again on its own for this
  /// episode.
  void _endCardBack() {
    // Only a card that came on its own stays away afterwards: one opened by
    // hand before its time still comes at the credits or at 98 %.
    if (!_endCardOpenedByBack) _endCardBackedOutFor = _currentMetadata.globalKey;
    _closeEndCard();
  }

  void _closeEndCard() {
    _endCardTimer?.cancel();
    _endCardTimer = null;
    setStateIfMounted(() {
      _endCardOpen = false;
      _endCardOpenedByBack = false;
      _endCardStarting = false;
      _endCardCountdown = null;
    });
  }

  /// The next episode, now: it opens in the card's box, and the card closes
  /// once its first frame is there, the picture growing to the whole screen.
  /// The card's first button: the next episode, or the suggestion's page.
  void _endCardPrimary() => _endCardSuggests ? unawaited(_endCardOpenSuggestion()) : _endCardPlayNow();

  /// Leaves the player for the suggested title's page.
  Future<void> _endCardOpenSuggestion() async {
    final item = _endCardNext;
    if (item == null) return;
    final navigator = Navigator.of(context);
    await _handleBackButton(fromEndCard: true);
    if (_routeExitOperation == null && mounted) return; // the exit was not taken (a guest said no)
    unawaited(navigator.push(MaterialPageRoute<void>(builder: (_) => MediaDetailScreen(metadata: item))));
  }

  void _endCardPlayNow() {
    _endCardTimer?.cancel();
    _endCardTimer = null;
    setStateIfMounted(() => _endCardStarting = true);
    unawaited(
      _playNext().then((_) {
        // Nothing moved on (no next after all, a failed open, which brings
        // Plezy's retry prompt): the card goes.
        if (mounted && _endCardStarting && _currentMetadata.globalKey == _endCardCurrent?.globalKey) _closeEndCard();
      }),
    );
  }

  /// At the end of the episode, with the end card chosen: true when the card
  /// took it over — the next episode started at once, or the card opened to
  /// count down — so Plezy's prompt stays away.
  bool _endCardTakesCompletion({required bool autoPlayEnabled}) {
    if (!_endCardChosen) return false;
    if (_endCardOpen) {
      if (_endCardCountdown == null) _startEndCardCountdown();
    } else {
      _openEndCard(byBack: false, atEnd: true);
    }
    return true;
  }

  /// At the end of a title nothing follows, with the end card chosen and a
  /// suggestion found: the card stays (or opens) instead of the player
  /// leaving on its own.
  bool _endCardTakesExit() {
    if (!_endCardChosen || !_endCardHasContent) return false;
    if (!_endCardOpen) _openEndCard(byBack: false, atEnd: true);
    _endCardRemaining.value = null;
    return _endCardOpen;
  }

  Widget _buildEndCard() => PlayerEndCard(
    open: _endCardOpen,
    current: _endCardCurrent ?? _currentMetadata,
    next: _endCardNext ?? _upNextDetails ?? _episode.next ?? _endCardSuggestion,
    movesPicture: _endCardMovesPicture,
    placePicture: _placeEndCardPicture,
    playLabel: _endCardPlayLabel,
    remaining: _endCardRemaining,
    playFocusNode: _endCardPlayFocusNode,
    creditsFocusNode: _endCardCreditsFocusNode,
    suggestion: _endCardSuggests,
    onPlay: _endCardPrimary,
    onWatchCredits: _endCardBack,
    exitFocusNode: _endCardExitFocusNode,
    onExit: _endCardExit,
  );

  /// "Stop watching" on the card: nothing more starts, and the player goes
  /// the way Back takes it (a Watch Together guest is asked first).
  void _endCardExit() {
    _endCardBack();
    unawaited(_handleBackButton(fromEndCard: true));
  }
}
