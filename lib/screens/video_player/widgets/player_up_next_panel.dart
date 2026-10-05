import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../focus/focusable_wrapper.dart';
import '../../../focus/input_mode_tracker.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/ids.dart';
import '../../../media/media_item.dart';
import '../../../redesign/ocker_skin.dart';
import '../../../redesign/ocker_type.dart';
import '../../../services/pip_service.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/media_image_helper.dart';
import '../../../utils/provider_extensions.dart';
import '../../../widgets/app_icon.dart';
import '../../../widgets/optimized_media_image.dart';
import '../../../widgets/video_controls/player_chrome_controller.dart';

/// "Up next" while the episode is still running: what follows, and what to do
/// about it.
///
/// Sits along the right edge over the picture rather than across it, so the
/// last minutes stay watchable — the whole point of showing this before the
/// end rather than after it. Two ways out and no third: start the next
/// episode, or leave the player. Back dismisses the panel and lets the episode
/// finish, which is why neither button says "cancel".
class PlayerUpNextPanel extends StatefulWidget {
  final bool visible;
  final MediaItem? nextEpisode;
  final FocusNode playFocusNode;
  final FocusNode closeFocusNode;
  final VoidCallback onPlay;
  final VoidCallback onClose;

  /// Seconds left before the next episode starts by itself, once this one
  /// has ended and auto-play is on — the end-of-episode countdown, which this
  /// panel shows in place of Plezy's own prompt. Null while the episode still
  /// runs; a value below one means no countdown (auto-play off).
  final ValueListenable<int>? countdown;

  /// Held open while the panel is up. Without it the chrome auto-hides after a
  /// few seconds of stillness and takes the focus with it — the buttons lose
  /// their highlight and the cursor is suddenly on the player again, with no
  /// way back into an overlay that is still on screen.
  final PlayerChromeController chromeController;

  const PlayerUpNextPanel({
    super.key,
    required this.visible,
    required this.nextEpisode,
    required this.playFocusNode,
    required this.closeFocusNode,
    required this.onPlay,
    required this.onClose,
    required this.chromeController,
    this.countdown,
  });

  @override
  State<PlayerUpNextPanel> createState() => _PlayerUpNextPanelState();
}

class _PlayerUpNextPanelState extends State<PlayerUpNextPanel> {
  @override
  void initState() {
    super.initState();
    _syncHold();
    if (widget.visible) _claimFocus();
  }

  @override
  void didUpdateWidget(PlayerUpNextPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      // After the frame: the hold tells the chrome, which is built in this
      // same pass — the end-of-episode countdown raises the panel from the
      // screen's own rebuild, and a notification in the middle of it marks
      // the chrome dirty after it was built.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncHold();
      });
    }
    if (widget.visible && !oldWidget.visible) _claimFocus();
  }

  @override
  void dispose() {
    widget.chromeController.release(PlayerChromeHold.promptInteraction, notify: false, restartAutoHide: false);
    super.dispose();
  }

  void _syncHold() {
    if (widget.visible) {
      // Without raising the chrome: the offer is the panel, and the episode
      // is still running behind it.
      widget.chromeController.hold(PlayerChromeHold.promptInteraction, reveal: false);
    } else {
      widget.chromeController.release(PlayerChromeHold.promptInteraction);
    }
  }

  /// After the frame, because the buttons do not exist until the panel is
  /// built: a request on an unmounted node is dropped, and the cursor stays
  /// wherever it was — on the player, with the offer sitting unreachable.
  void _claimFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.visible) widget.playFocusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final episode = widget.nextEpisode;
    if (episode == null) return const SizedBox.shrink();

    return ValueListenableBuilder<bool>(
      valueListenable: PipService().isPipActive,
      builder: (context, isInPip, _) {
        if (isInPip || !widget.visible) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.centerRight,
          child: LayoutBuilder(
            builder: (context, constraints) => SizedBox(
              // A share of the screen rather than a fixed width: the same
              // panel serves a phone in landscape and a television.
              width: (constraints.maxWidth * 0.34).clamp(280.0, 460.0),
              child: _UpNextCard(
                episode: episode,
                countdown: widget.countdown,
                playFocusNode: widget.playFocusNode,
                closeFocusNode: widget.closeFocusNode,
                onPlay: widget.onPlay,
                onClose: widget.onClose,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Stands in for a countdown while the episode is still running.
final ValueListenable<int> _noCountdown = ValueNotifier<int>(0);

class _UpNextCard extends StatelessWidget {
  final MediaItem episode;
  final ValueListenable<int>? countdown;
  final FocusNode playFocusNode;
  final FocusNode closeFocusNode;
  final VoidCallback onPlay;
  final VoidCallback onClose;

  const _UpNextCard({
    required this.episode,
    required this.countdown,
    required this.playFocusNode,
    required this.closeFocusNode,
    required this.onPlay,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tk = tokens(context);
    final ocker = isOcker(context);
    final series = episode.grandparentTitle;
    final summary = episode.summary;

    // Over the picture in every theme. Standard keeps the player's own
    // white on black; the redesign sets it in its warm pair, the ground and
    // the bone-white ink its every other surface is drawn in.
    final ink = ocker ? tk.ink(1) : Colors.white;
    final muted = ocker ? tk.ink(0.6) : Colors.white70;
    final ground = ocker ? tk.bg.withValues(alpha: 0.94) : Colors.black.withValues(alpha: 0.88);
    final heading = ocker
        ? OckerType.of(context).eyebrow.copyWith(color: muted)
        : theme.textTheme.labelLarge?.copyWith(color: muted, letterSpacing: 1.2);

    return _UpNextSurface(
      ground: ground,
      corner: BorderRadius.all(Radius.circular(tk.radiusMd)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.videoControls.upNext, style: heading),
          const SizedBox(height: 10),
          if (series != null && series.isNotEmpty) ...[
            Text(
              series,
              style: theme.textTheme.titleMedium?.copyWith(color: ink, fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
          ],
          Text(
            // The episode's own name: displayTitle renders the series for an
            // episode, which is already the line above.
            episode.title ?? episode.displayTitle,
            style: theme.textTheme.bodyLarge?.copyWith(color: ink),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (episode.thumbPath case final thumb?) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(artworkRadius(context))),
              child: AspectRatio(
                // The episode still, in the shape it was made in. A missing
                // one leaves the panel to its text rather than a grey box.
                aspectRatio: 16 / 9,
                child: OptimizedMediaImage(
                  client: context.tryGetMediaClientForServer(serverIdOrNull(episode.serverId)),
                  imagePath: thumb,
                  imageType: ImageType.thumb,
                  fit: BoxFit.cover,
                  fallbackIcon: null,
                  errorWidget: (context, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          ],
          if (summary != null && summary.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              summary,
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 18),
          // Every direction is answered, so nothing walks out of the panel:
          // the controls underneath would take the focus and there is no way
          // back in — the panel has no cursor of its own to return to.
          // The countdown rides on the play button rather than taking a line
          // of its own: on a television a taller card pushed its foot out of
          // the picture.
          ValueListenableBuilder<int>(
            valueListenable: countdown ?? _noCountdown,
            builder: (context, left, _) => _UpNextButton(
              focusNode: playFocusNode,
              onPressed: onPlay,
              icon: Symbols.play_arrow_rounded,
              label: left > 0 ? t.videoControls.upNextStartsIn(seconds: left) : t.common.play,
              offered: true,
              onNavigateUp: () {},
              onNavigateDown: () => closeFocusNode.requestFocus(),
            ),
          ),
          const SizedBox(height: 8),
          _UpNextButton(
            focusNode: closeFocusNode,
            onPressed: onClose,
            icon: Symbols.close_rounded,
            label: t.videoControls.closeUpNext,
            offered: false,
            onNavigateUp: () => playFocusNode.requestFocus(),
            onNavigateDown: () {},
          ),
        ],
      ),
    );
  }
}

/// One of the panel's two buttons, shaped as the theme shapes its buttons —
/// a pill in Standard, the redesign's cornered box there — and
/// focused the way the detail page's buttons are: the button fills, and no
/// ring is drawn round it.
///
/// The two are the same shape and the same size, so they read as a choice
/// between two things rather than as a button and a link beside it. Under a
/// remote the lit one is the one the cursor is on. Under a finger or a mouse
/// nothing is focused, and [offered] — Play — stays lit as the one the panel
/// is offering.
class _UpNextButton extends StatefulWidget {
  final FocusNode focusNode;
  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final bool offered;
  final VoidCallback onNavigateUp;
  final VoidCallback onNavigateDown;

  const _UpNextButton({
    required this.focusNode,
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.offered,
    required this.onNavigateUp,
    required this.onNavigateDown,
  });

  @override
  State<_UpNextButton> createState() => _UpNextButtonState();
}

class _UpNextButtonState extends State<_UpNextButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final ocker = isOcker(context);
    final lit = InputModeTracker.isKeyboardMode(context) ? _focused : widget.offered;
    final (fill, ink) = ocker
        ? (lit ? tk.ink(1) : tk.ink(0.12), lit ? tk.bg : tk.ink(0.75))
        : (lit ? Colors.white : Colors.white.withValues(alpha: 0.14), lit ? Colors.black : Colors.white);
    final OutlinedBorder shape = ocker
        ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(tk.radiusSm))
        : const StadiumBorder();

    return FocusableWrapper(
      focusNode: widget.focusNode,
      onSelect: widget.onPressed,
      onFocusChange: (focused) => setState(() => _focused = focused),
      // The fill is the focus mark. A ring round it would be a second one, and
      // a round ring round a cornered button was half of what did not match.
      delegateFocusBorder: true,
      disableScale: true,
      autoScroll: false,
      descendantsAreFocusable: false,
      onNavigateUp: widget.onNavigateUp,
      onNavigateDown: widget.onNavigateDown,
      onNavigateLeft: () {},
      onNavigateRight: () {},
      child: FilledButton.icon(
        onPressed: widget.onPressed,
        icon: AppIcon(widget.icon, fill: 1, size: 20),
        label: Text(widget.label),
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(44)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 18, vertical: 10)),
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: WidgetStatePropertyAll(fill),
          foregroundColor: WidgetStatePropertyAll(ink),
          // Material's own focus wash would dim the fill that says "focused".
          overlayColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.focused) ? Colors.transparent : null,
          ),
          shape: WidgetStatePropertyAll(shape),
        ),
      ),
    );
  }
}

/// The card the panel is drawn on: filled, or under "Redesign – Glas" a pane
/// the picture keeps playing through, its words on the glass's firmer inner
/// ground and inset so they land where they did.
class _UpNextSurface extends StatelessWidget {
  const _UpNextSurface({required this.ground, required this.corner, required this.child});

  final Color ground;
  final BorderRadius corner;
  final Widget child;

  static const _margin = EdgeInsets.all(24);
  static const _padding = 20.0;
  static const _glassRim = 8.0;

  @override
  Widget build(BuildContext context) {
    if (ockerGlass(context)) {
      return Padding(
        padding: _margin,
        child: OckerGlass(
          borderRadius: corner,
          scrimInset: _glassRim,
          child: Padding(padding: const EdgeInsets.all(_padding - _glassRim), child: child),
        ),
      );
    }
    return Container(
      margin: _margin,
      padding: const EdgeInsets.all(_padding),
      decoration: BoxDecoration(color: ground, borderRadius: corner),
      child: child,
    );
  }
}
