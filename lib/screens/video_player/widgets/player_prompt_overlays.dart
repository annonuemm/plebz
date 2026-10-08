import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show ValueListenable, listEquals;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../focus/focusable_button.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/ids.dart';
import '../../../media/media_item.dart';
import '../../../media/media_item_types.dart';
import '../../../providers/playback_state_provider.dart';
import '../../../redesign/ocker_skin.dart';
import '../../../services/download_artwork_service.dart';
import '../../../services/download_storage_service.dart';
import '../../../services/pip_service.dart';
import '../../../services/settings_service.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/platform_detector.dart';
import '../../../utils/provider_extensions.dart';
import '../../../watch_together/providers/watch_together_provider.dart';
import '../../../watch_together/widgets/watch_together_overlay.dart';
import '../../../widgets/app_icon.dart';
import '../../../widgets/optimized_media_image.dart';
import '../../../widgets/settings_builder.dart';
import '../../../widgets/video_controls/player_chrome_controller.dart';

class VideoPlayerMacPipPlaceholder extends StatelessWidget {
  const VideoPlayerMacPipPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: PipService().isPipActive,
      builder: (context, isInPip, child) {
        if (!isInPip) return const SizedBox.shrink();
        return Positioned.fill(
          child: Container(
            color: Colors.black,
            child: Center(
              child: Column(
                mainAxisSize: .min,
                children: [
                  AppIcon(Symbols.picture_in_picture_alt_rounded, size: 48, color: Colors.white.withValues(alpha: 0.5)),
                  const SizedBox(height: 12),
                  Text(
                    t.videoControls.pipActive,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The player's loading spinner.
///
/// Labelled rather than silent: a bare [CircularProgressIndicator] contributes
/// no semantics at all, so a screen reader announced nothing while the picture
/// was still coming up. The label also makes "the first frame has not rendered
/// yet" an observable state instead of something inferred from the chrome,
/// which a television no longer raises on startup (#1765).
class PlayerLoadingIndicator extends StatelessWidget {
  final double strokeWidth;

  const PlayerLoadingIndicator({super.key, this.strokeWidth = 4});

  @override
  Widget build(BuildContext context) {
    return CircularProgressIndicator(
      color: Colors.white,
      strokeWidth: strokeWidth,
      semanticsLabel: t.videoControls.loadingVideo,
    );
  }
}

class VideoPlayerBufferingOverlay extends StatefulWidget {
  final ValueListenable<bool> isBuffering;
  final ValueListenable<bool> hasFirstFrame;
  final ValueListenable<bool> isExiting;

  /// True while a live channel switch runs. The picture is frozen on the
  /// outgoing channel for that stretch rather than blanked; the spinner only
  /// joins it once the switch runs past [switchSpinnerDelay] (Plebz), to tell
  /// "slow" from "stuck" — a zap of a second showed it on every press, which
  /// the viewer found restless.
  final ValueListenable<bool> isSwitchingChannel;

  /// How long a channel switch runs quietly before the spinner shows.
  static const Duration switchSpinnerDelay = Duration(seconds: 2);

  const VideoPlayerBufferingOverlay({
    super.key,
    required this.isBuffering,
    required this.hasFirstFrame,
    required this.isExiting,
    required this.isSwitchingChannel,
  });

  @override
  State<VideoPlayerBufferingOverlay> createState() => _VideoPlayerBufferingOverlayState();
}

class _VideoPlayerBufferingOverlayState extends State<VideoPlayerBufferingOverlay> {
  Timer? _switchTimer;
  bool _switchOverdue = false;

  @override
  void initState() {
    super.initState();
    widget.isSwitchingChannel.addListener(_onSwitching);
    _onSwitching();
  }

  @override
  void didUpdateWidget(VideoPlayerBufferingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isSwitchingChannel != widget.isSwitchingChannel) {
      oldWidget.isSwitchingChannel.removeListener(_onSwitching);
      widget.isSwitchingChannel.addListener(_onSwitching);
      _onSwitching();
    }
  }

  @override
  void dispose() {
    widget.isSwitchingChannel.removeListener(_onSwitching);
    _switchTimer?.cancel();
    super.dispose();
  }

  /// A switch begun or ended: either way the next one starts quiet.
  void _onSwitching() {
    _switchTimer?.cancel();
    _switchTimer = null;
    if (widget.isSwitchingChannel.value) {
      _switchTimer = Timer(VideoPlayerBufferingOverlay.switchSpinnerDelay, () {
        if (mounted) setState(() => _switchOverdue = true);
      });
    }
    if (_switchOverdue && mounted) setState(() => _switchOverdue = false);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: PipService().isPipActive,
      builder: (context, isInPip, child) {
        if (isInPip) return const SizedBox.shrink();
        return ValueListenableBuilder<bool>(
          valueListenable: widget.isBuffering,
          builder: (context, buffering, child) {
            return ValueListenableBuilder<bool>(
              valueListenable: widget.isSwitchingChannel,
              builder: (context, switching, child) {
                return ValueListenableBuilder<bool>(
                  valueListenable: widget.hasFirstFrame,
                  builder: (context, hasFrame, child) {
                    if (widget.isExiting.value) return const SizedBox.shrink();
                    // A zap: the last frame stands still and nothing spins —
                    // not even for the new stream's own buffering — until it
                    // has taken longer than a zap should.
                    if (switching && !_switchOverdue) return const SizedBox.shrink();
                    if (!buffering && !switching && hasFrame) return const SizedBox.shrink();
                    return Positioned.fill(
                      child: IgnorePointer(
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                            ),
                            child: const PlayerLoadingIndicator(strokeWidth: 3),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

/// The channel banner a zap leaves behind: which channel this now is and what
/// is on it, shown briefly with the chrome down — the way a television does
/// it, so a walk through the channels does not need the full controls.
///
/// Under "Redesign – Glas" it is a pane of glass like the player's bottom bar
/// and the up-next panel, its words in the theme's ink; the picture keeps
/// playing through it.
class VideoPlayerZapBanner extends StatelessWidget {
  const VideoPlayerZapBanner({super.key, required this.visible, required this.channelName, required this.programTitle});

  final ValueListenable<bool> visible;
  final String? channelName;
  final String? programTitle;

  @override
  Widget build(BuildContext context) {
    final name = channelName;
    if (name == null || name.isEmpty) return const SizedBox.shrink();
    // Asked first: the theme may carry no tokens at all outside the redesign.
    final glass = ockerGlass(context);
    final tk = glass ? tokens(context) : null;
    final ink = tk?.ink(1) ?? Colors.white;
    final muted = tk?.ink(0.72) ?? Colors.white70;
    final lines = Column(
      crossAxisAlignment: .start,
      mainAxisSize: .min,
      children: [
        // The name alone, no channel number: the number said nothing the
        // name did not, and it pushed the name out of line with the
        // programme beneath it.
        Text(
          name,
          style: TextStyle(color: ink, fontSize: 20, fontWeight: .w600),
          maxLines: 1,
          overflow: .ellipsis,
        ),
        if (programTitle != null && programTitle!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            programTitle!,
            style: TextStyle(color: muted, fontSize: 15),
            maxLines: 1,
            overflow: .ellipsis,
          ),
        ],
      ],
    );

    return ValueListenableBuilder<bool>(
      valueListenable: visible,
      builder: (context, isVisible, child) {
        return Positioned(
          left: 32,
          bottom: 48,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: isVisible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: tk != null
                  // The words land where they did on the black box: the
                  // pane's inset plus a little more at the sides.
                  ? OckerGlass(
                      borderRadius: BorderRadius.all(Radius.circular(tk.radiusMd)),
                      scrimInset: 12,
                      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: lines),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(flatRadius(context, 12)),
                      ),
                      child: lines,
                    ),
            ),
          ),
        );
      },
    );
  }
}

class VideoPlayerWatchTogetherOverlays extends StatelessWidget {
  const VideoPlayerWatchTogetherOverlays({super.key});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Selector<WatchTogetherProvider, bool>(
            selector: (_, provider) => provider.isWaitingForHostReconnect,
            builder: (context, isWaiting, child) {
              if (!isWaiting) return const SizedBox.shrink();
              return Positioned(
                bottom: 120,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.all(Radius.circular(20)),
                    ),
                    child: Row(
                      mainAxisSize: .min,
                      children: [
                        if (PlatformDetector.isTV())
                          const AppIcon(Symbols.sync_rounded, size: 14, color: Colors.white)
                        else
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          ),
                        const SizedBox(width: 8),
                        Text(
                          t.watchTogether.reconnectingToHost,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const ParticipantNotificationOverlay(),
          const WaitingForParticipantsIndicator(),
          const SyncingIndicator(),
        ],
      ),
    );
  }
}

class VideoPlayerExitOverlay extends StatelessWidget {
  final ValueListenable<bool> isExiting;

  const VideoPlayerExitOverlay({super.key, required this.isExiting});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isExiting,
      builder: (context, exiting, child) {
        if (!exiting) return const SizedBox.shrink();
        return const Positioned.fill(child: ColoredBox(color: Colors.black));
      },
    );
  }
}

class VideoPlayerPlayNextOverlay extends StatelessWidget {
  final bool visible;
  final MediaItem? nextEpisode;
  final ValueListenable<int> autoPlayCountdown;
  final FocusNode cancelFocusNode;
  final FocusNode confirmFocusNode;
  final PlayerChromeController chromeController;
  final VoidCallback onCancel;
  final VoidCallback onPlayNext;

  const VideoPlayerPlayNextOverlay({
    super.key,
    required this.visible,
    required this.nextEpisode,
    required this.autoPlayCountdown,
    required this.cancelFocusNode,
    required this.confirmFocusNode,
    required this.chromeController,
    required this.onCancel,
    required this.onPlayNext,
  });

  @override
  Widget build(BuildContext context) {
    final episode = nextEpisode;
    if (episode == null) return const SizedBox.shrink();
    // Resolved only while shown: the overlay sits in the player build with
    // visible=false for the whole episode, and the lookup hashes the artwork
    // path per call.
    final backdrop = visible ? _buildThumbnailBackdrop(context, episode) : null;
    return _VideoPlayerPromptShell(
      visible: visible,
      chromeController: chromeController,
      focusNodes: [cancelFocusNode, confirmFocusNode],
      backdrop: backdrop,
      children: [
        // Clear region that keeps the still visible above the scrimmed text.
        if (backdrop != null) const SizedBox(height: 110),
        _PlayNextEpisodeHeader(episode: episode),
        const SizedBox(height: 12),
        _VideoPlayerPromptActions(
          cancelLabel: t.common.cancel,
          cancelFocusNode: cancelFocusNode,
          onCancel: onCancel,
          confirmFocusNode: confirmFocusNode,
          onConfirm: onPlayNext,
          confirmChildren: [
            ValueListenableBuilder<int>(
              valueListenable: autoPlayCountdown,
              builder: (context, countdown, child) {
                if (countdown <= 0) return Text(t.videoControls.playNext);
                return Row(
                  mainAxisSize: .min,
                  children: [
                    Text('$countdown'),
                    const SizedBox(width: 4),
                    const AppIcon(Symbols.play_arrow_rounded, fill: 1, size: 18),
                  ],
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  /// The next episode's 16:9 video-frame still, painted edge-to-edge behind
  /// the prompt text under the card's scrim (#2166).
  ///
  /// Null keeps the original text-only card: the item has no thumb, or
  /// nothing could serve one (no live client and no artwork directory for a
  /// downloaded copy). A load that starts and fails degrades to the dark card
  /// via the shrinking placeholder/error widgets instead of a fallback icon.
  Widget? _buildThumbnailBackdrop(BuildContext context, MediaItem episode) {
    final thumbPath = episode.thumbPath;
    if (thumbPath == null) return null;
    final serverId = serverIdOrNull(episode.serverId);
    final client = context.tryGetMediaClientForServer(serverId);
    final localFilePath = serverId == null
        ? null
        : DownloadArtworkService.localPathSync(DownloadStorageService.instance, serverId, thumbPath);
    if (client == null && localFilePath == null) return null;
    final image = OptimizedMediaImage.thumb(
      client: client,
      imagePath: thumbPath,
      localFilePath: localFilePath,
      fit: BoxFit.cover,
      placeholder: (_, _) => const SizedBox.shrink(),
      errorWidget: (_, _, _) => const SizedBox.shrink(),
    );
    // The next episode is unwatched by definition, so hide-spoilers users get
    // the same blurred still as the queue strip and episode cards.
    return SettingValueBuilder<bool>(
      pref: SettingsService.hideSpoilers,
      builder: (context, hideSpoilers, _) {
        if (!hideSpoilers || !episode.shouldHideSpoiler) return image;
        return ClipRect(
          child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12), child: image),
        );
      },
    );
  }
}

class _PlayNextEpisodeHeader extends StatelessWidget {
  final MediaItem episode;

  const _PlayNextEpisodeHeader({required this.episode});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: .start,
            children: [
              Consumer<PlaybackStateProvider>(
                builder: (context, playbackState, child) {
                  final isShuffleActive = playbackState.isShuffleActive;
                  return Row(
                    children: [
                      Text(
                        t.videoControls.nextEpisode,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12, fontWeight: .w500),
                      ),
                      if (isShuffleActive) ...[
                        const SizedBox(width: 4),
                        AppIcon(Symbols.shuffle_rounded, fill: 1, size: 12, color: Colors.white.withValues(alpha: 0.7)),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 4),
              if (episode.parentIndex != null && episode.index != null)
                Text(
                  'S${episode.parentIndex} E${episode.index} · ${episode.title}',
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: .w600),
                  maxLines: 2,
                  overflow: .ellipsis,
                )
              else
                Text(
                  episode.title!,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: .w600),
                  maxLines: 2,
                  overflow: .ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class VideoPlayerStillWatchingOverlay extends StatelessWidget {
  final bool visible;
  final ValueListenable<int> countdown;
  final FocusNode pauseFocusNode;
  final FocusNode continueFocusNode;
  final PlayerChromeController chromeController;
  final VoidCallback onPause;
  final VoidCallback onContinue;

  const VideoPlayerStillWatchingOverlay({
    super.key,
    required this.visible,
    required this.countdown,
    required this.pauseFocusNode,
    required this.continueFocusNode,
    required this.chromeController,
    required this.onPause,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return _VideoPlayerPromptShell(
      visible: visible,
      chromeController: chromeController,
      focusNodes: [pauseFocusNode, continueFocusNode],
      children: [
        Text(
          t.videoControls.stillWatching,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12, fontWeight: .w500),
        ),
        const SizedBox(height: 4),
        ValueListenableBuilder<int>(
          valueListenable: countdown,
          builder: (context, seconds, child) => Text(
            t.videoControls.pausingIn(seconds: '$seconds'),
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: .w600),
          ),
        ),
        const SizedBox(height: 12),
        _VideoPlayerPromptActions(
          cancelLabel: t.videoControls.pauseButton,
          cancelFocusNode: pauseFocusNode,
          onCancel: onPause,
          confirmFocusNode: continueFocusNode,
          onConfirm: onContinue,
          confirmChildren: [
            ValueListenableBuilder<int>(
              valueListenable: countdown,
              builder: (context, seconds, child) => Text('$seconds'),
            ),
            const SizedBox(width: 4),
            Text(t.videoControls.continueWatching),
          ],
        ),
      ],
    );
  }
}

class _VideoPlayerPromptShell extends StatelessWidget {
  final bool visible;
  final PlayerChromeController chromeController;
  final List<FocusNode> focusNodes;

  /// Full-bleed artwork painted behind [children] under a darkening scrim.
  final Widget? backdrop;
  final List<Widget> children;

  const _VideoPlayerPromptShell({
    required this.visible,
    required this.chromeController,
    required this.focusNodes,
    this.backdrop,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: PipService().isPipActive,
      builder: (context, isInPip, child) {
        if (isInPip || !visible) {
          return const SizedBox.shrink();
        }
        return _VideoPlayerPromptPosition(
          chromeController: chromeController,
          child: _VideoPlayerPromptInteractionHold(
            chromeController: chromeController,
            focusNodes: focusNodes,
            child: _VideoPlayerPromptCard(
              backdrop: backdrop,
              child: Column(mainAxisSize: .min, crossAxisAlignment: .start, children: children),
            ),
          ),
        );
      },
    );
  }
}

class _VideoPlayerPromptActions extends StatelessWidget {
  final String cancelLabel;
  final FocusNode cancelFocusNode;
  final VoidCallback onCancel;
  final FocusNode confirmFocusNode;
  final VoidCallback onConfirm;
  final List<Widget> confirmChildren;

  const _VideoPlayerPromptActions({
    required this.cancelLabel,
    required this.cancelFocusNode,
    required this.onCancel,
    required this.confirmFocusNode,
    required this.onConfirm,
    required this.confirmChildren,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FocusableButton(
            focusNode: cancelFocusNode,
            onPressed: onCancel,
            autoScroll: false,
            onNavigateRight: () => confirmFocusNode.requestFocus(),
            onNavigateUp: () {},
            onNavigateDown: () {},
            child: OutlinedButton(
              onPressed: onCancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(cancelLabel),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FocusableButton(
            focusNode: confirmFocusNode,
            onPressed: onConfirm,
            autoScroll: false,
            onNavigateLeft: () => cancelFocusNode.requestFocus(),
            onNavigateUp: () {},
            onNavigateDown: () {},
            useBackgroundFocus: true,
            child: FilledButton(
              onPressed: onConfirm,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Row(mainAxisAlignment: .center, children: confirmChildren),
            ),
          ),
        ),
      ],
    );
  }
}

class _VideoPlayerPromptPosition extends StatelessWidget {
  final PlayerChromeController chromeController;
  final Widget child;

  const _VideoPlayerPromptPosition({required this.chromeController, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: chromeController,
      builder: (context, controlsShown, child) {
        return AnimatedPositioned(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          right: 24,
          bottom: controlsShown ? 100 : 24,
          child: child!,
        );
      },
      child: child,
    );
  }
}

class _VideoPlayerPromptCard extends StatelessWidget {
  /// See [_VideoPlayerPromptShell.backdrop].
  final Widget? backdrop;
  final Widget child;

  const _VideoPlayerPromptCard({this.backdrop, required this.child});

  @override
  Widget build(BuildContext context) {
    final backdrop = this.backdrop;
    final content = Padding(padding: const EdgeInsets.all(16), child: child);
    final decoration = BoxDecoration(
      color: Colors.black.withValues(alpha: 0.9),
      borderRadius: BorderRadius.all(Radius.circular(flatRadius(context, 12))),
    );
    if (backdrop == null) {
      return Container(width: 320, decoration: decoration, child: content);
    }
    return Container(
      width: 320,
      clipBehavior: Clip.antiAlias,
      decoration: decoration,
      child: Stack(
        children: [
          Positioned.fill(child: backdrop),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.35, 0.78],
                  colors: [
                    Colors.black.withValues(alpha: 0.05),
                    Colors.black.withValues(alpha: 0.25),
                    Colors.black.withValues(alpha: 0.92),
                  ],
                ),
              ),
            ),
          ),
          content,
        ],
      ),
    );
  }
}

class _VideoPlayerPromptInteractionHold extends StatefulWidget {
  final PlayerChromeController chromeController;
  final List<FocusNode> focusNodes;
  final Widget child;

  const _VideoPlayerPromptInteractionHold({
    required this.chromeController,
    required this.focusNodes,
    required this.child,
  });

  @override
  State<_VideoPlayerPromptInteractionHold> createState() => _VideoPlayerPromptInteractionHoldState();
}

class _VideoPlayerPromptInteractionHoldState extends State<_VideoPlayerPromptInteractionHold> {
  bool _hovered = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _addFocusListeners(widget.focusNodes);
    _syncFocusState();
  }

  @override
  void didUpdateWidget(_VideoPlayerPromptInteractionHold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.focusNodes, widget.focusNodes)) {
      _removeFocusListeners(oldWidget.focusNodes);
      _addFocusListeners(widget.focusNodes);
      _syncFocusState();
    }
    if (oldWidget.chromeController != widget.chromeController) {
      oldWidget.chromeController.release(PlayerChromeHold.promptInteraction);
      _syncHold();
    }
  }

  @override
  void dispose() {
    _removeFocusListeners(widget.focusNodes);
    widget.chromeController.release(PlayerChromeHold.promptInteraction, notify: false, restartAutoHide: false);
    super.dispose();
  }

  void _addFocusListeners(List<FocusNode> nodes) {
    for (final node in nodes) {
      node.addListener(_syncFocusState);
    }
  }

  void _removeFocusListeners(List<FocusNode> nodes) {
    for (final node in nodes) {
      node.removeListener(_syncFocusState);
    }
  }

  void _syncFocusState() {
    final focused = widget.focusNodes.any((node) => node.hasFocus);
    if (_focused == focused) return;
    _focused = focused;
    _syncHold();
  }

  void _setHovered(bool hovered) {
    if (_hovered == hovered) return;
    _hovered = hovered;
    if (hovered) widget.chromeController.recordPointerActivity();
    _syncHold();
  }

  void _syncHold() {
    if (_hovered || _focused) {
      widget.chromeController.hold(PlayerChromeHold.promptInteraction);
    } else {
      widget.chromeController.release(PlayerChromeHold.promptInteraction);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onHover: (_) => widget.chromeController.recordPointerActivity(),
      onExit: (_) => _setHovered(false),
      child: widget.child,
    );
  }
}
