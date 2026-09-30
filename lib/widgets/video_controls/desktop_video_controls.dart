import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:plezy/widgets/app_icon.dart';
import 'package:plezy/widgets/focusable_list_tile.dart';
import 'package:plezy/widgets/overlay_sheet.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';

import '../../focus/dpad_navigator.dart';
import '../../media/media_item.dart';
import '../../models/livetv_channel.dart';
import '../../models/livetv_program.dart';
import '../../media/stepped_seek.dart';
import '../../mpv/mpv.dart';
import '../../media/media_source_info.dart';
import '../../services/fullscreen_state_manager.dart';
import '../../services/live_seek_accumulator.dart';
import '../../services/scrub_preview_source.dart';
import '../../services/video_volume_controller.dart';
import '../../utils/desktop_window_padding.dart';
import '../../utils/platform_detector.dart';
import '../../utils/formatters.dart';
import '../../i18n/strings.g.dart';
import '../../models/livetv_capture_buffer.dart';
import 'models/track_controls_state.dart';
import 'player_chrome_controller.dart';
import 'widgets/content_strip.dart';
import 'widgets/content_strip_panel.dart';
import 'widgets/live_channel_strip.dart';
import 'widgets/live_group_strip.dart';
import 'widgets/live_timeline_bar.dart';
import 'widgets/first_frame_guard.dart';
import 'widgets/play_pause_stream_builder.dart';
import 'widgets/video_controls_header.dart';
import 'widgets/video_timeline_bar.dart';
import 'widgets/volume_control.dart';
import 'widgets/track_chapter_controls.dart';
import 'video_control_button.dart';
import '../../redesign/ocker_skin.dart';
import '../../theme/mono_tokens.dart';

/// Desktop-specific video controls layout with top bar and bottom controls
class DesktopVideoControls extends StatefulWidget {
  final Player player;
  final VideoVolumeController volumeController;
  final MediaItem metadata;
  final VoidCallback? onNext;
  final VoidCallback? onPrevious;
  final VoidCallback onPlayPause;
  final List<MediaChapter> chapters;
  final bool chaptersLoaded;
  final bool showChapterMarkersOnTimeline;
  final int seekTimeSmall;
  final VoidCallback onSeekToPreviousChapter;
  final VoidCallback onSeekToNextChapter;
  final VoidCallback? onSeekBackward;
  final VoidCallback? onSeekForward;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<Duration> onSeekEnd;
  final VoidCallback? onScrubStart;
  final VoidCallback? onScrubEnd;
  final IconData Function(int) getReplayIcon;
  final IconData Function(int) getForwardIcon;

  /// Called when focus activity occurs (to reset hide timer)
  final VoidCallback? onFocusActivity;

  /// Called to request focus on play/pause button (e.g., when controls shown via keyboard)
  final VoidCallback? onRequestPlayPauseFocus;

  /// Called when user navigates up from timeline (to hide controls)
  final VoidCallback? onHideControls;

  final TrackControlsState trackControlsState;
  final VoidCallback? onBack;

  /// Notifier for whether first video frame has rendered (shows loading state when false).
  final ValueNotifier<bool>? hasFirstFrame;

  /// Optional callback that returns thumbnail image bytes for a given timestamp.
  final ScrubFrame? Function(Duration time)? thumbnailDataBuilder;

  final String? liveChannelName;

  /// The live session's channel list, shown as the strip and walked by the
  /// remote's vertical keys. Empty outside live TV.
  final List<LiveTvChannel> liveChannels;

  /// Index of the playing channel within [liveChannels], or -1 when unknown.
  final int liveChannelIndex;

  /// Switch to the channel at that index of [liveChannels].
  final ValueChanged<int>? onLiveChannelSelected;

  /// The addresses this one channel can be played from, named for a menu.
  /// More than one only where a playlist's repeats of a station were merged;
  /// empty everywhere else, and the control is then absent.
  final List<String> liveVariantLabels;

  /// Which of [liveVariantLabels] is playing.
  final int liveVariantIndex;

  /// Play the variant at that index of [liveVariantLabels].
  final ValueChanged<int>? onLiveVariantSelected;

  /// What is on the playing channel right now, for the header's second line.
  final String? liveProgramTitle;

  /// What is on [channel] right now, for the channel strip's info line.
  final LiveTvProgram? Function(LiveTvChannel channel)? liveProgramFor;
  final LiveTvProgram? Function(LiveTvChannel channel)? liveNextProgramFor;
  final List<LiveChannelGroupOption> liveGroups;
  final String? liveGroup;
  final void Function(String? group)? onLiveGroupSelected;

  // Live TV time-shift
  final CaptureBuffer? captureBuffer;
  final bool isAtLiveEdge;
  final int Function(Duration position)? liveEpochForPosition;
  final ValueChanged<int>? onLiveSeek;

  /// Relative live-TV skip entry point (delta seconds); the parent accumulates
  /// and debounces, and reports back the seconds it actually applied.
  final LiveSeekBy? onLiveSeekBy;
  final VoidCallback? onJumpToLive;

  /// Whether to use dpad navigation for content strip (TV or keyboard nav mode)
  final bool useDpadNavigation;

  final String? serverId;

  final bool showQueueTab;

  /// Called when a queue item is selected in the content strip
  final Function(MediaItem)? onQueueItemSelected;

  /// Called to cancel auto-hide timer (e.g., when content strip is shown)
  final VoidCallback? onCancelAutoHide;

  final VoidCallback? onStartAutoHide;

  /// Called when content strip visibility changes
  final ValueChanged<bool>? onContentStripVisibilityChanged;
  final PlayerChromeController? chromeController;

  /// Called when a seek should be executed by the owning screen.
  final Future<void> Function(Duration position)? onSeekRequested;

  /// Called when a seek operation completes successfully.
  final Function(Duration position)? onSeekCompleted;

  const DesktopVideoControls({
    super.key,
    required this.player,
    required this.volumeController,
    required this.metadata,
    this.onNext,
    this.onPrevious,
    required this.onPlayPause,
    required this.chapters,
    required this.chaptersLoaded,
    this.showChapterMarkersOnTimeline = true,
    required this.seekTimeSmall,
    required this.onSeekToPreviousChapter,
    required this.onSeekToNextChapter,
    this.onSeekBackward,
    this.onSeekForward,
    required this.onSeek,
    required this.onSeekEnd,
    this.onScrubStart,
    this.onScrubEnd,
    required this.getReplayIcon,
    required this.getForwardIcon,
    this.onFocusActivity,
    this.onRequestPlayPauseFocus,
    this.onHideControls,
    this.trackControlsState = const TrackControlsState(),
    this.onBack,
    this.hasFirstFrame,
    this.thumbnailDataBuilder,
    this.liveChannelName,
    this.liveChannels = const [],
    this.liveVariantLabels = const [],
    this.liveVariantIndex = 0,
    this.onLiveVariantSelected,
    this.liveChannelIndex = -1,
    this.onLiveChannelSelected,
    this.liveProgramTitle,
    this.liveProgramFor,
    this.liveNextProgramFor,
    this.liveGroups = const [],
    this.liveGroup,
    this.onLiveGroupSelected,
    this.captureBuffer,
    this.isAtLiveEdge = true,
    this.liveEpochForPosition,
    this.onLiveSeek,
    this.onLiveSeekBy,
    this.onJumpToLive,
    required this.useDpadNavigation,
    this.serverId,
    this.showQueueTab = false,
    this.onQueueItemSelected,
    this.onCancelAutoHide,
    this.onStartAutoHide,
    this.onContentStripVisibilityChanged,
    this.chromeController,
    this.onSeekRequested,
    this.onSeekCompleted,
  });

  @override
  State<DesktopVideoControls> createState() => DesktopVideoControlsState();
}

class DesktopVideoControlsState extends State<DesktopVideoControls> {
  TrackControlsState get _trackControlsState => widget.trackControlsState;
  bool get _canControl => _trackControlsState.canControl;
  bool get _isLive => _trackControlsState.isLive;

  late final FocusNode _prevItemFocusNode;
  late final FocusNode _prevChapterFocusNode;
  late final FocusNode _skipBackFocusNode;
  late final FocusNode _playPauseFocusNode;
  late final FocusNode _skipForwardFocusNode;
  late final FocusNode _nextChapterFocusNode;
  late final FocusNode _nextItemFocusNode;
  late final FocusNode _goToLiveFocusNode;
  late final FocusNode _timelineFocusNode;

  late final FocusNode _volumeFocusNode;

  late final List<FocusNode> _trackControlFocusNodes;

  late final List<FocusNode> _buttonFocusNodes;
  late Stream<String?> _previousChapterLabelStream;
  late Stream<String?> _nextChapterLabelStream;

  final FocusNode _variantFocusNode = FocusNode(debugLabel: 'LiveVariant');

  LogicalKeyboardKey? _seekDirection; // Current direction being held
  int _seekRepeatCount = 0; // Consecutive key repeats for acceleration

  bool _showKeyRepeatThumbnail = false;
  Timer? _keyRepeatThumbnailTimer;
  late final DebouncedSeekAccumulator _timelineSeek;
  static const _keyRepeatThumbnailTimeout = Duration(milliseconds: 400);

  bool _contentStripVisible = false;

  /// See [stripOpenedFromPicture].
  bool _stripOpenedFromPicture = false;
  final GlobalKey<ContentStripState> _contentStripKey = GlobalKey<ContentStripState>();
  final GlobalKey<LiveChannelStripState> _channelStripKey = GlobalKey<LiveChannelStripState>();

  FocusNode? _lastFocusedButtonNode;

  /// Live TV replaces the chapter/queue strip with its channel list: a
  /// channel has no chapters, and its "queue" is the list itself.
  bool get _hasChannelStrip => widget.liveChannels.isNotEmpty && widget.onLiveChannelSelected != null;

  /// Fewer than two groups is nothing to choose between.
  bool get _hasGroupStrip => widget.liveGroups.length > 1 && widget.onLiveGroupSelected != null;

  /// Which list the panel is showing. One panel, three contents: chapters off
  /// live TV, channels on LEFT, groups on RIGHT.
  _ContentStripMode _stripMode = _ContentStripMode.chapters;

  final GlobalKey<LiveGroupStripState> _groupStripKey = GlobalKey<LiveGroupStripState>();

  bool get _hasStripContent {
    if (_hasChannelStrip) return true;
    return widget.chapters.isNotEmpty || (widget.showQueueTab && widget.onQueueItemSelected != null);
  }

  @override
  void initState() {
    super.initState();
    _prevItemFocusNode = FocusNode(debugLabel: 'PrevItem');
    _prevChapterFocusNode = FocusNode(debugLabel: 'PrevChapter');
    _skipBackFocusNode = FocusNode(debugLabel: 'SkipBack');
    _playPauseFocusNode = FocusNode(debugLabel: 'PlayPause');
    _skipForwardFocusNode = FocusNode(debugLabel: 'SkipForward');
    _nextChapterFocusNode = FocusNode(debugLabel: 'NextChapter');
    _nextItemFocusNode = FocusNode(debugLabel: 'NextItem');
    _goToLiveFocusNode = FocusNode(debugLabel: 'GoToLive');
    _timelineFocusNode = FocusNode(debugLabel: 'Timeline');
    _volumeFocusNode = FocusNode(debugLabel: 'Volume');

    // Create focus nodes for track controls. The row is at its longest with
    // the description button on a phone (settings, tracks, info, chapters,
    // queue, PiP, fit, rotation lock, screen lock); a button past the end of
    // this list still draws, but silently takes no focus and is unreachable
    // with a remote.
    _trackControlFocusNodes = List.generate(9, (i) => FocusNode(debugLabel: 'TrackControl$i'));

    _buttonFocusNodes = [
      _prevItemFocusNode,
      _prevChapterFocusNode,
      _skipBackFocusNode,
      _playPauseFocusNode,
      _skipForwardFocusNode,
      _nextChapterFocusNode,
      _nextItemFocusNode,
      _goToLiveFocusNode,
      // Appended rather than slotted in: the index is the position in this
      // list and left/right walks it, so a new button belongs at the end of
      // the row as well as of the list.
      _variantFocusNode,
    ];
    _bindChapterLabelStreams();
    widget.chromeController?.addListener(_onChromeControllerChanged);
    _timelineSeek = DebouncedSeekAccumulator(
      currentPosition: () => widget.player.state.position,
      duration: () => widget.player.state.duration,
      seek: widget.onSeekEnd,
      playheadJumps: widget.player.streams.playheadJump,
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
  }

  /// Drop a coalesced timeline burst that will never be committed, because what
  /// it was seeking through is being replaced.
  void abandonPendingSeek() => _timelineSeek.cancel();

  void _bindChapterLabelStreams() {
    if (widget.chapters.isEmpty) {
      _previousChapterLabelStream = const Stream<String?>.empty();
      _nextChapterLabelStream = const Stream<String?>.empty();
      return;
    }

    _previousChapterLabelStream = widget.player.streams.position.map(_getPreviousChapterLabel).distinct();
    _nextChapterLabelStream = widget.player.streams.position.map(_getNextChapterLabel).distinct();
  }

  @override
  void didUpdateWidget(DesktopVideoControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.player, widget.player) || !identical(oldWidget.chapters, widget.chapters)) {
      _bindChapterLabelStreams();
    }
    if (oldWidget.player != widget.player) {
      _timelineSeek.attachPlayheadJumps(widget.player.streams.playheadJump);
    }
    if (oldWidget.chromeController != widget.chromeController) {
      oldWidget.chromeController?.removeListener(_onChromeControllerChanged);
      widget.chromeController?.addListener(_onChromeControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.chromeController?.removeListener(_onChromeControllerChanged);
    _keyRepeatThumbnailTimer?.cancel();
    _timelineSeek.dispose();
    _prevItemFocusNode.dispose();
    _prevChapterFocusNode.dispose();
    _skipBackFocusNode.dispose();
    _playPauseFocusNode.dispose();
    _skipForwardFocusNode.dispose();
    _nextChapterFocusNode.dispose();
    _nextItemFocusNode.dispose();
    _goToLiveFocusNode.dispose();
    _variantFocusNode.dispose();
    _timelineFocusNode.dispose();
    _volumeFocusNode.dispose();
    for (final node in _trackControlFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _onChromeControllerChanged() {
    if (widget.chromeController?.contentStripVisible == false) {
      hideContentStrip();
    }
  }

  /// Move focus to the play/pause button.
  ///
  /// Raw mechanism: it does not decide whether focus *should* enter the chrome.
  /// A key that raises the chrome makes that decision with
  /// `eventRequestsFocusNavigation` before queueing a play/pause focus request
  /// on the chrome; internal hand-offs (the skip-marker button's
  /// ArrowDown, an item swap) are already inside a focus session.
  void requestPlayPauseFocus() {
    _playPauseFocusNode.requestFocus();
  }

  /// Hide content strip (called by parent when controls hide)
  void hideContentStrip() {
    if (_contentStripVisible) {
      setState(() {
        _contentStripVisible = false;
      });
      widget.onContentStripVisibilityChanged?.call(false);
    }
  }

  /// Whether the strip on screen was opened over the bare picture — live TV's
  /// LEFT/RIGHT on the remote — rather than from the chrome.
  ///
  /// The chrome under such a strip was raised only to host it; the viewer
  /// never asked for the controls, so closing the strip belongs back at the
  /// picture.
  bool get stripOpenedFromPicture => _contentStripVisible && _stripOpenedFromPicture;

  /// Dismiss content strip and restore focus (called by parent on BACK key).
  ///
  /// [restoreFocus] is what the chrome wants and the bare picture does not: a
  /// focus request into controls that are about to be hidden lands on nodes
  /// whose subtree is being dropped.
  void dismissContentStrip({bool restoreFocus = true}) {
    if (!_contentStripVisible) return;
    _onContentStripNavigateUp(restoreFocus: restoreFocus);
  }

  /// Handle left navigation from first track control - go to volume (or last button on TV)
  void navigateFromTrackToVolume() {
    if (PlatformDetector.isTV()) {
      // On TV (no volume), go to last mounted button
      for (int i = _buttonFocusNodes.length - 1; i >= 0; i--) {
        if (_buttonFocusNodes[i].context != null) {
          _buttonFocusNodes[i].requestFocus();
          widget.onFocusActivity?.call();
          return;
        }
      }
      _playPauseFocusNode.requestFocus(); // fallback
    } else {
      _volumeFocusNode.requestFocus();
    }
    widget.onFocusActivity?.call();
  }

  void _onFocusChange(bool hasFocus) {
    if (hasFocus) {
      widget.onFocusActivity?.call();
    } else {
      // Reset progressive seek state when timeline loses focus
      _timelineSeek.flush();
      _resetSeekState();
    }
  }

  /// Track the last focused button node for returning from content strip
  void _onButtonRowFocusChange(bool hasFocus) {
    if (hasFocus) {
      widget.onFocusActivity?.call();
      // Find which button or track control has focus
      for (final node in _buttonFocusNodes) {
        if (node.hasFocus) {
          _lastFocusedButtonNode = node;
          return;
        }
      }
      for (final node in _trackControlFocusNodes) {
        if (node.hasFocus) {
          _lastFocusedButtonNode = node;
          return;
        }
      }
      if (_volumeFocusNode.hasFocus) {
        _lastFocusedButtonNode = _volumeFocusNode;
      }
    }
  }

  void _showContentStrip({bool fromPicture = false}) {
    if (!widget.useDpadNavigation || !_hasStripContent) return;
    if (_contentStripVisible) {
      // Already visible - focus into it
      _requestStripFocus();
      return;
    }

    setState(() {
      _contentStripVisible = true;
      _stripOpenedFromPicture = fromPicture;
    });
    widget.onContentStripVisibilityChanged?.call(true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _requestStripFocus();
    });
  }

  void _requestStripFocus() {
    switch (_stripMode) {
      case _ContentStripMode.groups:
        _groupStripKey.currentState?.requestInitialFocus();
      case _ContentStripMode.channels:
        _channelStripKey.currentState?.requestInitialFocus();
      case _ContentStripMode.chapters:
        _contentStripKey.currentState?.requestInitialFocus();
    }
  }

  /// Open the channel list from outside the chrome (the remote's LEFT key).
  void showChannelStrip() {
    if (!_hasChannelStrip) return;
    setState(() => _stripMode = _ContentStripMode.channels);
    _showContentStrip(fromPicture: true);
  }

  /// Open the group list (the remote's RIGHT key).
  void showGroupStrip() {
    if (!_hasGroupStrip) return;
    setState(() => _stripMode = _ContentStripMode.groups);
    _showContentStrip(fromPicture: true);
  }

  void _onContentStripNavigateUp({bool restoreFocus = true}) {
    // Hide content strip and show normal controls again
    setState(() {
      _contentStripVisible = false;
      _stripOpenedFromPicture = false;
    });
    widget.onContentStripVisibilityChanged?.call(false);
    if (!restoreFocus) return;

    // Return focus to the last focused button (or play/pause as fallback)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _lastFocusedButtonNode;
      if (target != null && target.context != null) {
        target.requestFocus();
      } else {
        _playPauseFocusNode.requestFocus();
      }
      widget.onFocusActivity?.call();
    });
  }

  /// Handle directional navigation for bottom control row.
  ///
  /// Returns [KeyEventResult.handled] if the key was processed,
  /// [KeyEventResult.ignored] otherwise.
  /// UP always navigates to timeline.
  KeyEventResult _handleDirectionalNavigation(KeyEvent event, {FocusNode? leftTarget, FocusNode? rightTarget}) {
    if (!event.isActionable) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowLeft) {
      leftTarget?.requestFocus();
      widget.onFocusActivity?.call();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      rightTarget?.requestFocus();
      widget.onFocusActivity?.call();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      _timelineFocusNode.requestFocus();
      widget.onFocusActivity?.call();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      if (widget.useDpadNavigation && _hasStripContent) {
        _showContentStrip();
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// Handle key events for horizontal button navigation
  /// The copies of this station, to pick from.
  ///
  /// Marked with the one playing: the point of the list is to say where you
  /// are as much as to offer somewhere else.
  Future<void> _showVariantPicker(BuildContext context) async {
    final labels = widget.liveVariantLabels;
    if (labels.length < 2) return;
    final chosen = await OverlaySheetController.showAdaptive<int>(
      context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text(t.liveTv.chooseVariant, style: Theme.of(sheetContext).textTheme.titleMedium),
            ),
            for (var index = 0; index < labels.length; index++)
              FocusableListTile(
                autofocus: index == widget.liveVariantIndex,
                leading: AppIcon(
                  index == widget.liveVariantIndex ? Symbols.play_circle_rounded : Symbols.circle_rounded,
                  fill: index == widget.liveVariantIndex ? 1 : 0,
                ),
                title: Text(labels[index]),
                // closeAdaptive, not Navigator.pop: showAdaptive renders
                // inside the player's OverlaySheetHost rather than as a
                // route, and a route pop there closes nothing and returns
                // no value — the picker stayed open and the switch never ran.
                onTap: () => OverlaySheetController.closeAdaptive(sheetContext, index),
              ),
          ],
        ),
      ),
    );
    if (chosen != null && chosen != widget.liveVariantIndex) widget.onLiveVariantSelected?.call(chosen);
  }

  KeyEventResult _handleButtonKeyEvent(FocusNode _, KeyEvent event, int index) {
    // Find nearest mounted left neighbor
    FocusNode? leftTarget;
    for (int i = index - 1; i >= 0; i--) {
      if (_buttonFocusNodes[i].context != null) {
        leftTarget = _buttonFocusNodes[i];
        break;
      }
    }

    // Find nearest mounted right neighbor, falling through to volume/track controls
    FocusNode? rightTarget;
    for (int i = index + 1; i < _buttonFocusNodes.length; i++) {
      if (_buttonFocusNodes[i].context != null) {
        rightTarget = _buttonFocusNodes[i];
        break;
      }
    }
    rightTarget ??= PlatformDetector.isTV()
        ? (_trackControlFocusNodes.isNotEmpty ? _trackControlFocusNodes.first : null)
        : _volumeFocusNode;

    return _handleDirectionalNavigation(event, leftTarget: leftTarget, rightTarget: rightTarget);
  }

  /// Handle key events for volume control navigation
  KeyEventResult _handleVolumeKeyEvent(FocusNode _, KeyEvent event) {
    return _handleDirectionalNavigation(
      event,
      leftTarget: _nextItemFocusNode,
      rightTarget: _trackControlFocusNodes.isNotEmpty ? _trackControlFocusNodes.first : null,
    );
  }

  void _resetSeekState() {
    _seekDirection = null;
    _seekRepeatCount = 0;
    _keyRepeatThumbnailTimer?.cancel();
    _keyRepeatThumbnailTimer = null;
    if (_showKeyRepeatThumbnail) {
      setState(() => _showKeyRepeatThumbnail = false);
    }
  }

  /// Show the timeline preview thumbnail during sustained key-repeat seeking.
  /// Arms a short timer that hides the thumbnail once repeats stop.
  void _triggerKeyRepeatThumbnail() {
    if (!_showKeyRepeatThumbnail) {
      setState(() => _showKeyRepeatThumbnail = true);
    }
    _keyRepeatThumbnailTimer?.cancel();
    _keyRepeatThumbnailTimer = Timer(_keyRepeatThumbnailTimeout, () {
      if (!mounted) return;
      setState(() => _showKeyRepeatThumbnail = false);
    });
  }

  /// Handle key events for timeline navigation
  KeyEventResult _handleTimelineKeyEvent(FocusNode _, KeyEvent event) {
    final key = event.logicalKey;

    // Handle key release: commit the accumulated scrub target with a single
    // seek (a no-op when nothing is pending) and reset progressive seek state.
    if (event is KeyUpEvent) {
      if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {
        _timelineSeek.flush();
        _resetSeekState();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (!event.isActionable) {
      return KeyEventResult.ignored;
    }

    final duration = widget.player.state.duration;

    // UP arrow - hide controls and reset seek state
    if (key == LogicalKeyboardKey.arrowUp) {
      _timelineSeek.flush();
      _resetSeekState();
      widget.onHideControls?.call();
      return KeyEventResult.handled;
    }

    // DOWN arrow - move focus to play/pause button and reset seek state
    if (key == LogicalKeyboardKey.arrowDown) {
      _timelineSeek.flush();
      _resetSeekState();
      _playPauseFocusNode.requestFocus();
      widget.onFocusActivity?.call();
      return KeyEventResult.handled;
    }

    // LEFT/RIGHT for smooth scrubbing with progressive acceleration
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {
      // Ignore seeking if user cannot control
      if (!_canControl) return KeyEventResult.handled;

      // Track direction change - reset if direction changes
      if (_seekDirection != key) {
        _seekDirection = key;
        _seekRepeatCount = 0;
      }
      if (event is KeyRepeatEvent) {
        _seekRepeatCount++;
        _triggerKeyRepeatThumbnail();
      }

      final isForward = key == LogicalKeyboardKey.arrowRight;
      final effectiveMultiplier = event is KeyRepeatEvent ? steppedSeekMultiplier(_seekRepeatCount) : 1.0;

      // Live TV: relative epoch-based seeking via the parent accumulator, which
      // coalesces a rapid/held burst into one transcode re-open (#1253). The
      // acceleration multiplier still grows the per-press step; the accumulator
      // sums them.
      if (_isLive && widget.onLiveSeekBy != null) {
        final stepSeconds = (widget.seekTimeSmall * effectiveMultiplier).clamp(1, 300).round();
        widget.onLiveSeekBy!(isForward ? stepSeconds : -stepSeconds);
        widget.onFocusActivity?.call();
        return KeyEventResult.handled;
      }

      if (duration.inMilliseconds <= 0) return KeyEventResult.handled;

      final baseStepMs = widget.seekTimeSmall * 1000;
      final stepMs = (baseStepMs * effectiveMultiplier).clamp(500, 120_000).toInt();
      final step = Duration(milliseconds: stepMs);

      _timelineSeek.seekBy(isForward ? step : -step);

      // Move only the preview while the key is held; commit a single seek once
      // the burst pauses (debounce) or the key is released. Firing a real seek
      // per key-repeat floods a direct/progressive stream with overlapping range
      // requests and wedges low-power devices (e.g. Fire TV Stick) in BUFFERING.
      // The player's `buffering` flag lags the key-repeat rate, so it can't gate
      // this reliably — coalescing unconditionally matches the existing transcode
      // path and cannot flood regardless of hardware.
      widget.onFocusActivity?.call();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Top bar with back button and title (always visible)
        _buildTopBar(context),
        FirstFrameGuard(
          hasFirstFrame: widget.hasFirstFrame,
          placeholder: const Expanded(child: SizedBox.shrink()),
          builder: (context) => Expanded(
            child: Column(
              children: [
                const Spacer(),
                // When content strip is visible, hide the normal controls (like mobile)
                if (!_contentStripVisible)
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _glassBottomControls(context, _buildBottomControlsContent(context, hasFrame: true)),
                      // Down arrow hint when strip content is available
                      if (widget.useDpadNavigation && _hasStripContent)
                        const ContentStripHint(Symbols.keyboard_arrow_down_rounded),
                    ],
                  ),
                // Content strip (TV/dpad only) — replaces normal controls
                if (_contentStripVisible && widget.useDpadNavigation && _stripMode == _ContentStripMode.groups)
                  ContentStripPanel(
                    padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8, top: 32),
                    chevron: Symbols.keyboard_arrow_up_rounded,
                    // Under glass the list is a pane of its own, on its own
                    // ground; the scrim behind it was a dark box round it.
                    scrim: !ockerGlass(context),
                    // Half the screen, in the middle under the chevron: a list
                    // of group names across the whole width was mostly empty
                    // pane.
                    child: FractionallySizedBox(
                      widthFactor: LiveGroupStrip.widthFactor,
                      child: LiveGroupStrip(
                        key: _groupStripKey,
                        groups: widget.liveGroups,
                        selected: widget.liveGroup,
                        onGroupSelected: (group) {
                          widget.onLiveGroupSelected?.call(group);
                          _onContentStripNavigateUp();
                        },
                        onNavigateUp: _onContentStripNavigateUp,
                        onFocusActivity: widget.onFocusActivity,
                      ),
                    ),
                  )
                else if (_contentStripVisible && widget.useDpadNavigation && _hasChannelStrip)
                  ContentStripPanel(
                    padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8, top: 32),
                    chevron: Symbols.keyboard_arrow_up_rounded,
                    child: LiveChannelStrip(
                      key: _channelStripKey,
                      channels: widget.liveChannels,
                      currentIndex: widget.liveChannelIndex,
                      programFor: widget.liveProgramFor,
                      nextProgramFor: widget.liveNextProgramFor,
                      onChannelSelected: (index) {
                        widget.onLiveChannelSelected?.call(index);
                        _onContentStripNavigateUp();
                      },
                      onNavigateUp: _onContentStripNavigateUp,
                      onFocusActivity: widget.onFocusActivity,
                    ),
                  )
                else if (_contentStripVisible && widget.useDpadNavigation)
                  ContentStripPanel(
                    padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8, top: 32),
                    chevron: Symbols.keyboard_arrow_up_rounded,
                    // Under glass the strip stands on a pane, as the control
                    // bar it takes the place of does, and needs no scrim.
                    scrim: !ockerGlass(context),
                    child: _glassContentStrip(
                      context,
                      ContentStrip(
                        key: _contentStripKey,
                        player: widget.player,
                        chapters: widget.chapters,
                        serverId: widget.serverId,
                        canControl: _canControl,
                        showQueueTab: widget.showQueueTab,
                        onQueueItemSelected: widget.onQueueItemSelected,
                        onSeekRequested: widget.onSeekRequested,
                        onSeekCompleted: widget.onSeekCompleted,
                        useFocusNavigation: true,
                        onNavigateUp: _onContentStripNavigateUp,
                        onFocusActivity: widget.onFocusActivity,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar(BuildContext _) {
    // Use global fullscreen state for padding
    return ListenableBuilder(
      listenable: FullscreenStateManager(),
      builder: (context, _) {
        // On macOS the traffic lights need clearing in normal mode; they auto-hide in fullscreen.
        final leftPadding = Platform.isMacOS ? DesktopWindowPadding.macOSLeftCurrent : 0.0;

        return _buildTopBarContent(context, leftPadding);
      },
    );
  }

  Widget _buildTopBarContent(BuildContext _, double leftPadding) {
    final topBar = Padding(
      padding: .only(left: leftPadding, right: 16),
      child: Row(
        children: [
          Expanded(
            child: VideoControlsHeader(
              metadata: widget.metadata,
              titleOverride: widget.liveChannelName,
              subtitle: widget.liveProgramTitle,
              style: Platform.isMacOS ? VideoHeaderStyle.singleLine : VideoHeaderStyle.multiLine,
              onBack: widget.onBack,
              onCancelAutoHide: widget.onCancelAutoHide,
              onStartAutoHide: widget.onStartAutoHide,
            ),
          ),
          if (_isLive && (widget.captureBuffer == null || widget.isAtLiveEdge)) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: const BoxDecoration(color: Colors.red, borderRadius: BorderRadius.all(Radius.circular(4))),
              child: Text(
                t.liveTv.live,
                style: const TextStyle(color: Colors.white, fontWeight: .bold, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );

    return DesktopAppBarHelper.wrapWithGestureDetector(topBar, opaque: true);
  }

  /// Under "Redesign – Glas" the bar is a pane over the picture rather than
  /// bare controls on the scrim. The controls keep their own padding inside
  /// it; the pane sits just outside them.
  /// The chapter and queue strip on the same glass as [_glassBottomControls],
  /// under "Redesign – Glas"; [strip] alone everywhere else. The pane clips
  /// what scrolls, so an item passing its edge goes under the rim rather than
  /// out over the picture.
  Widget _glassContentStrip(BuildContext context, Widget strip) {
    if (!ockerGlass(context)) return strip;
    final radius = BorderRadius.all(Radius.circular(tokens(context).radiusMd));
    return OckerGlass(
      borderRadius: radius,
      scrimInset: 0,
      child: ClipRRect(
        borderRadius: radius,
        child: Padding(padding: const EdgeInsets.all(8), child: strip),
      ),
    );
  }

  Widget _glassBottomControls(BuildContext context, Widget controls) {
    if (!ockerGlass(context)) return controls;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: OckerGlass(borderRadius: BorderRadius.all(Radius.circular(tokens(context).radiusMd)), child: controls),
    );
  }

  Widget _buildBottomControlsContent(BuildContext _, {required bool hasFrame}) {
    final canInteract = _canControl && hasFrame;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          // The bar cannot place anything without the epoch mapping, so it is
          // part of the condition rather than a bang on the next line.
          if (_isLive && widget.captureBuffer != null && widget.liveEpochForPosition != null) ...[
            LiveTimelineBar(
              player: widget.player,
              captureBuffer: widget.captureBuffer!,
              epochForPosition: widget.liveEpochForPosition!,
              isAtLiveEdge: widget.isAtLiveEdge,
              onSeekEnd: widget.onLiveSeek,
              horizontalLayout: true,
              focusNode: _timelineFocusNode,
              onKeyEvent: _handleTimelineKeyEvent,
              onFocusChange: _onFocusChange,
              enabled: canInteract,
            ),
          ] else if (!_isLive) ...[
            VideoTimelineBar(
              player: widget.player,
              chapters: widget.chapters,
              chaptersLoaded: widget.chaptersLoaded,
              showChapterMarkersOnTimeline: widget.showChapterMarkersOnTimeline,
              onSeek: widget.onSeek,
              onSeekEnd: widget.onSeekEnd,
              onScrubStart: widget.onScrubStart,
              onScrubEnd: widget.onScrubEnd,
              horizontalLayout: true,
              focusNode: _timelineFocusNode,
              onKeyEvent: _handleTimelineKeyEvent,
              onFocusChange: _onFocusChange,
              enabled: canInteract,
              thumbnailDataBuilder: widget.thumbnailDataBuilder,
              showKeyRepeatThumbnail: _showKeyRepeatThumbnail,
              previewPosition: _timelineSeek.pendingPosition,
            ),
          ],
          Focus(
            onFocusChange: _onButtonRowFocusChange,
            skipTraversal: true,
            child: Row(
              children: [
                if (!_isLive) ...[
                  Opacity(
                    opacity: _canControl ? 1.0 : 0.5,
                    child: _buildFocusableButton(
                      focusNode: _prevItemFocusNode,
                      index: 0,
                      icon: Symbols.skip_previous_rounded,
                      color: widget.onPrevious != null && _canControl ? Colors.white : Colors.white54,
                      onPressed: _canControl ? widget.onPrevious : null,
                      semanticLabel: t.videoControls.previousButton,
                    ),
                  ),
                  // Previous chapter
                  StreamBuilder<String?>(
                    stream: _previousChapterLabelStream,
                    initialData: _getPreviousChapterLabel(widget.player.state.position),
                    builder: (context, prevLabelSnapshot) {
                      return Opacity(
                        opacity: _canControl ? 1.0 : 0.5,
                        child: _buildFocusableButton(
                          focusNode: _prevChapterFocusNode,
                          index: 1,
                          icon: Symbols.fast_rewind_rounded,
                          color: widget.chapters.isNotEmpty && _canControl ? Colors.white : Colors.white54,
                          onPressed: _canControl && widget.chapters.isNotEmpty ? widget.onSeekToPreviousChapter : null,
                          semanticLabel: t.videoControls.previousChapterButton,
                          tooltip: prevLabelSnapshot.data,
                        ),
                      );
                    },
                  ),
                ],
                if (!_isLive || widget.captureBuffer != null) ...[
                  // Skip backward
                  Opacity(
                    opacity: _canControl ? 1.0 : 0.5,
                    child: _buildFocusableButton(
                      focusNode: _skipBackFocusNode,
                      index: 2,
                      icon: widget.getReplayIcon(widget.seekTimeSmall),
                      onPressed: _canControl ? widget.onSeekBackward : null,
                      semanticLabel: t.videoControls.seekBackwardButton(seconds: widget.seekTimeSmall),
                    ),
                  ),
                ],
                // Play/Pause
                Opacity(
                  opacity: _canControl ? 1.0 : 0.5,
                  child: PlayPauseStreamBuilder(
                    player: widget.player,
                    builder: (context, isPlaying) {
                      return _buildFocusableButton(
                        focusNode: _playPauseFocusNode,
                        index: 3,
                        icon: isPlaying ? Symbols.pause_rounded : Symbols.play_arrow_rounded,
                        iconSize: 32,
                        onPressed: _canControl ? widget.onPlayPause : null,
                        semanticLabel: isPlaying ? t.videoControls.pauseButton : t.videoControls.playButton,
                      );
                    },
                  ),
                ),
                if (!_isLive || widget.captureBuffer != null) ...[
                  // Skip forward
                  Opacity(
                    opacity: _canControl ? 1.0 : 0.5,
                    child: _buildFocusableButton(
                      focusNode: _skipForwardFocusNode,
                      index: 4,
                      icon: widget.getForwardIcon(widget.seekTimeSmall),
                      onPressed: _canControl ? widget.onSeekForward : null,
                      semanticLabel: t.videoControls.seekForwardButton(seconds: widget.seekTimeSmall),
                    ),
                  ),
                ],
                // Go to Live button (only when time-shifted behind live edge)
                if (_isLive && widget.captureBuffer != null && !widget.isAtLiveEdge && widget.onJumpToLive != null) ...[
                  _buildFocusableButton(
                    focusNode: _goToLiveFocusNode,
                    index: 7,
                    icon: Symbols.stream_rounded,
                    onPressed: _canControl ? widget.onJumpToLive : null,
                    semanticLabel: t.liveTv.goToLive,
                    tooltip: t.liveTv.goToLive,
                  ),
                ],
                if (!_isLive) ...[
                  // Next chapter
                  StreamBuilder<String?>(
                    stream: _nextChapterLabelStream,
                    initialData: _getNextChapterLabel(widget.player.state.position),
                    builder: (context, nextLabelSnapshot) {
                      return Opacity(
                        opacity: _canControl ? 1.0 : 0.5,
                        child: _buildFocusableButton(
                          focusNode: _nextChapterFocusNode,
                          index: 5,
                          icon: Symbols.fast_forward_rounded,
                          color: widget.chapters.isNotEmpty && _canControl ? Colors.white : Colors.white54,
                          onPressed: _canControl && widget.chapters.isNotEmpty ? widget.onSeekToNextChapter : null,
                          semanticLabel: t.videoControls.nextChapterButton,
                          tooltip: nextLabelSnapshot.data,
                        ),
                      );
                    },
                  ),
                  // Next item
                  Opacity(
                    opacity: _canControl ? 1.0 : 0.5,
                    child: _buildFocusableButton(
                      focusNode: _nextItemFocusNode,
                      index: 6,
                      icon: Symbols.skip_next_rounded,
                      color: widget.onNext != null && _canControl ? Colors.white : Colors.white54,
                      onPressed: _canControl ? widget.onNext : null,
                      semanticLabel: t.videoControls.nextButton,
                    ),
                  ),
                ],
                // Which route to the station is playing, where a playlist
                // offered several and they were merged into one channel.
                // A list rather than a step-to-the-next: with three copies to
                // choose from, cycling tells the viewer neither where they
                // are nor what else there is.
                if (widget.liveVariantLabels.length > 1)
                  Opacity(
                    opacity: _canControl ? 1.0 : 0.5,
                    child: _buildFocusableButton(
                      focusNode: _variantFocusNode,
                      index: _buttonFocusNodes.indexOf(_variantFocusNode),
                      icon: Symbols.swap_horiz_rounded,
                      onPressed: _canControl ? () => unawaited(_showVariantPicker(context)) : null,
                      semanticLabel: t.liveTv.chooseVariant,
                      tooltip: t.liveTv.variantOf(
                        current: widget.liveVariantIndex + 1,
                        total: widget.liveVariantLabels.length,
                        name: widget.liveVariantLabels[widget.liveVariantIndex],
                      ),
                    ),
                  ),
                // Finish time (hidden for live TV, faded when too narrow)
                if (_isLive)
                  const Spacer()
                else
                  Expanded(
                    child: StreamBuilder<Duration>(
                      stream: widget.player.streams.duration,
                      initialData: widget.player.state.duration,
                      builder: (context, durationSnapshot) {
                        final duration = durationSnapshot.data ?? Duration.zero;
                        return StreamBuilder<double>(
                          stream: widget.player.streams.rate,
                          initialData: widget.player.state.rate,
                          builder: (context, rateSnapshot) {
                            final rate = rateSnapshot.data ?? 1.0;
                            final initialRemaining = duration - widget.player.state.position;
                            return StreamBuilder<Duration>(
                              stream: widget.player.streams.position.map((position) => duration - position).distinct((
                                previous,
                                next,
                              ) {
                                final previousHasRemaining = previous.inSeconds > 0;
                                final nextHasRemaining = next.inSeconds > 0;
                                return previousHasRemaining == nextHasRemaining &&
                                    (!previousHasRemaining || previous.inMinutes == next.inMinutes);
                              }),
                              initialData: initialRemaining,
                              builder: (context, remainingSnapshot) {
                                final remaining = remainingSnapshot.data ?? Duration.zero;
                                if (remaining.inSeconds <= 0) return const SizedBox.shrink();

                                final text = t.videoControls.endsAt(
                                  time: formatFinishTime(
                                    remaining,
                                    rate: rate,
                                    is24Hour: MediaQuery.alwaysUse24HourFormatOf(context),
                                  ),
                                );
                                const style = TextStyle(color: Colors.white70, fontSize: 13);

                                return Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Text(text, style: style, maxLines: 1, softWrap: false, overflow: .fade),
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                // Volume control (hidden on TV — hardware handles volume)
                if (!PlatformDetector.isTV()) ...[
                  VolumeControl(
                    volumeController: widget.volumeController,
                    focusNode: _volumeFocusNode,
                    onKeyEvent: _handleVolumeKeyEvent,
                    onFocusChange: _onFocusChange,
                    onFocusActivity: widget.onFocusActivity,
                  ),
                  const SizedBox(width: 16),
                ],
                // Audio track, subtitle, and chapter controls
                TrackChapterControls(
                  player: widget.player,
                  chapters: widget.chapters,
                  chaptersLoaded: widget.chaptersLoaded,
                  trackControlsState: _trackControlsState,
                  onSeekRequested: widget.onSeekRequested,
                  onSeekCompleted: widget.onSeekCompleted,
                  focusNodes: _trackControlFocusNodes,
                  onFocusChange: _onFocusChange,
                  onNavigateLeft: navigateFromTrackToVolume,
                  onNavigateUp: () {
                    _timelineFocusNode.requestFocus();
                    widget.onFocusActivity?.call();
                  },
                  onNavigateDown: () {
                    if (widget.useDpadNavigation && _hasStripContent) {
                      _showContentStrip();
                    }
                  },
                  hideChaptersAndQueue: widget.useDpadNavigation && _hasStripContent,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Returns the label of the next chapter the user would seek to, or null.
  String? _getNextChapterLabel(Duration position) {
    final index = MediaChapter.seekTargetIndex(position, widget.chapters, forward: true);
    return index == null ? null : widget.chapters[index].label;
  }

  /// Returns the label of the previous chapter the user would seek to, or null.
  String? _getPreviousChapterLabel(Duration position) {
    final index = MediaChapter.seekTargetIndex(position, widget.chapters, forward: false);
    return index == null ? null : widget.chapters[index].label;
  }

  Widget _buildFocusableButton({
    required FocusNode focusNode,
    required int index,
    required IconData icon,
    required VoidCallback? onPressed,
    required String semanticLabel,
    Color color = Colors.white,
    double iconSize = 24,
    String? tooltip,
  }) {
    return VideoControlButton(
      icon: icon,
      iconSize: iconSize,
      color: color,
      tooltip: tooltip,
      semanticLabel: semanticLabel,
      focusNode: focusNode,
      onKeyEvent: (node, event) => _handleButtonKeyEvent(node, event, index),
      onFocusChange: _onFocusChange,
      onPressed: onPressed,
    );
  }
}

/// What the one content panel is showing.
enum _ContentStripMode { chapters, channels, groups }
