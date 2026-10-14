import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../focus/focusable_wrapper.dart';
import '../../../focus/input_mode_tracker.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/ids.dart';
import '../../../media/media_item.dart';
import '../../../media/media_item_types.dart';
import '../../../media/media_kind.dart';
import '../../../redesign/ocker_skin.dart';
import '../../../redesign/ocker_type.dart';
import '../../../services/download_artwork_service.dart';
import '../../../services/download_storage_service.dart';
import '../../../services/pip_service.dart';
import '../../../services/settings_service.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/formatters.dart';
import '../../../utils/platform_detector.dart';
import '../../../utils/provider_extensions.dart';
import '../../../widgets/app_icon.dart';
import '../../../widgets/optimized_media_image.dart';
import '../../../widgets/settings_builder.dart';
import '../../../widgets/video_controls/player_chrome_controller.dart';

part 'player_end_card.dart';

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

  /// Below this height a phone gets the small card (Plebz).
  static const compactBelowHeight = 520.0;

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
    // Plebz: for a remote or a keyboard only — the hold keeps the controls
    // from hiding behind the cursor in the panel. Under a finger it kept the
    // controls a tap had raised over the picture for the whole of the credits,
    // with no tap to take them away again.
    if (widget.visible && InputModeTracker.currentMode == InputMode.keyboard) {
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
        return LayoutBuilder(
          builder: (context, constraints) {
            Widget card({required bool compact}) => _UpNextCard(
              episode: episode,
              countdown: widget.countdown,
              playFocusNode: widget.playFocusNode,
              closeFocusNode: widget.closeFocusNode,
              onPlay: widget.onPlay,
              onClose: widget.onClose,
              compact: compact,
            );
            // Plebz: a phone on its side is too low for the full card — its
            // buttons fell below the screen's edge, out of a finger's reach. It
            // gets a small card in the corner instead, above the controls'
            // bottom bar and clear of a cutout.
            if (PlatformDetector.isMobile(context) && constraints.maxHeight < PlayerUpNextPanel.compactBelowHeight) {
              return SafeArea(
                child: Align(
                  alignment: AlignmentDirectional.bottomEnd,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(end: 16, bottom: 88),
                    child: SizedBox(
                      width: (constraints.maxWidth * 0.46).clamp(280.0, 380.0),
                      child: card(compact: true),
                    ),
                  ),
                ),
              );
            }
            return Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                // A share of the screen rather than a fixed width: the same
                // panel serves a phone in landscape and a television.
                width: (constraints.maxWidth * 0.34).clamp(280.0, 460.0),
                child: card(compact: false),
              ),
            );
          },
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

  /// The small card a phone on its side gets (Plebz): the still, the name and
  /// the two buttons side by side, no description.
  final bool compact;

  const _UpNextCard({
    required this.episode,
    required this.countdown,
    required this.playFocusNode,
    required this.closeFocusNode,
    required this.onPlay,
    required this.onClose,
    this.compact = false,
  });

  /// Plebz, as the end-of-episode prompt it stands in for: the still of a
  /// downloaded episode from its saved artwork when no server answers, and
  /// blurred when spoilers are hidden.
  Widget _still(BuildContext context, String thumb) => _episodeStill(context, episode, thumb);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tk = tokens(context);
    final ocker = isOcker(context);
    final series = episode.grandparentTitle;
    final summary = episode.summary;
    final spoilersHidden =
        (SettingsService.instanceOrNull?.read(SettingsService.hideSpoilers) ?? false) && episode.shouldHideSpoiler;

    // Over the picture in every theme. Standard keeps the player's own
    // white on black; the redesign sets it in its warm pair, the ground and
    // the bone-white ink its every other surface is drawn in.
    final ink = ocker ? tk.ink(1) : Colors.white;
    final muted = ocker ? tk.ink(0.6) : Colors.white70;
    final ground = ocker ? tk.bg.withValues(alpha: 0.94) : Colors.black.withValues(alpha: 0.88);
    final heading = ocker
        ? OckerType.of(context).eyebrow.copyWith(color: muted)
        : theme.textTheme.labelLarge?.copyWith(color: muted, letterSpacing: 1.2);

    if (compact) {
      final title = episode.title ?? episode.displayTitle;
      return _UpNextSurface(
        ground: ground,
        corner: BorderRadius.all(Radius.circular(tk.radiusMd)),
        compact: true,
        child: Row(
          children: [
            if (episode.thumbPath case final thumb?) ...[
              SizedBox(
                width: 96,
                child: ClipRRect(
                  borderRadius: BorderRadius.all(Radius.circular(artworkRadius(context))),
                  child: AspectRatio(aspectRatio: 16 / 9, child: _still(context, thumb)),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.videoControls.upNext, style: heading, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    series != null && series.isNotEmpty ? '$series · $title' : title,
                    style: theme.textTheme.bodyMedium?.copyWith(color: ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Flexible(
                        child: ValueListenableBuilder<int>(
                          valueListenable: countdown ?? _noCountdown,
                          builder: (context, left, _) => _UpNextButton(
                            focusNode: playFocusNode,
                            onPressed: onPlay,
                            icon: Symbols.play_arrow_rounded,
                            label: left > 0 ? t.videoControls.upNextStartsIn(seconds: left) : t.common.play,
                            offered: true,
                            compact: true,
                            onNavigateUp: () {},
                            onNavigateDown: () {},
                            onNavigateRight: () => closeFocusNode.requestFocus(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _UpNextButton(
                        focusNode: closeFocusNode,
                        onPressed: onClose,
                        icon: Symbols.close_rounded,
                        label: null,
                        tooltip: t.videoControls.closeUpNext,
                        offered: false,
                        compact: true,
                        onNavigateUp: () {},
                        onNavigateDown: () {},
                        onNavigateLeft: () => playFocusNode.requestFocus(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

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
                child: _still(context, thumb),
              ),
            ),
          ],
          // The next episode is unwatched by definition: with spoilers hidden
          // its synopsis is left out, as on its episode card.
          if (!spoilersHidden && summary != null && summary.trim().isNotEmpty) ...[
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

  /// Null for words alone (the end card's quieter buttons).
  final IconData? icon;

  /// Null for the small card's close button, which is its glyph alone.
  final String? label;
  final String? tooltip;
  final bool offered;
  final bool compact;
  final VoidCallback onNavigateUp;
  final VoidCallback onNavigateDown;
  final VoidCallback? onNavigateLeft;
  final VoidCallback? onNavigateRight;

  const _UpNextButton({
    required this.focusNode,
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.offered,
    required this.onNavigateUp,
    required this.onNavigateDown,
    this.tooltip,
    this.compact = false,
    this.onNavigateLeft,
    this.onNavigateRight,
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
      onNavigateLeft: widget.onNavigateLeft ?? () {},
      onNavigateRight: widget.onNavigateRight ?? () {},
      child: _button(fill, ink, shape),
    );
  }

  Widget _button(Color fill, Color ink, OutlinedBorder shape) {
    final label = widget.label;
    final compact = widget.compact;
    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(compact ? const Size(44, 40) : const Size.fromHeight(44)),
      padding: WidgetStatePropertyAll(
        compact
            ? EdgeInsets.symmetric(horizontal: label == null ? 10 : 14, vertical: 8)
            : const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      ),
      elevation: const WidgetStatePropertyAll(0),
      backgroundColor: WidgetStatePropertyAll(fill),
      foregroundColor: WidgetStatePropertyAll(ink),
      // Material's own focus wash would dim the fill that says "focused".
      overlayColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused) ? Colors.transparent : null,
      ),
      shape: WidgetStatePropertyAll(shape),
    );
    final glyph = widget.icon;
    if (glyph == null) {
      return FilledButton(
        onPressed: widget.onPressed,
        style: style,
        child: Text(label ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
      );
    }
    final icon = AppIcon(glyph, fill: 1, size: 20);
    if (label == null) {
      final button = FilledButton(onPressed: widget.onPressed, style: style, child: icon);
      return widget.tooltip == null ? button : Tooltip(message: widget.tooltip!, child: button);
    }
    return FilledButton.icon(
      onPressed: widget.onPressed,
      icon: icon,
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: style,
    );
  }
}

/// The card the panel is drawn on: filled, or under "Redesign – Glas" a pane
/// the picture keeps playing through, its words on the glass's firmer inner
/// ground and inset so they land where they did.
class _UpNextSurface extends StatelessWidget {
  const _UpNextSurface({required this.ground, required this.corner, required this.child, this.compact = false});

  final Color ground;
  final BorderRadius corner;
  final Widget child;

  /// The small card's: placed by its caller, so no margin, and less air.
  final bool compact;

  static const _margin = EdgeInsets.all(24);
  static const _padding = 20.0;
  static const _compactPadding = 12.0;
  static const _glassRim = 8.0;

  @override
  Widget build(BuildContext context) {
    final margin = compact ? EdgeInsets.zero : _margin;
    final padding = compact ? _compactPadding : _padding;
    if (ockerGlass(context)) {
      return Padding(
        padding: margin,
        child: OckerGlass(
          borderRadius: corner,
          scrimInset: _glassRim,
          child: Padding(padding: EdgeInsets.all(padding - (compact ? 4 : _glassRim)), child: child),
        ),
      );
    }
    return Container(
      margin: margin,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(color: ground, borderRadius: corner),
      child: child,
    );
  }
}

/// An episode's still (Plebz): from its saved artwork when it is downloaded
/// and no server answers, blurred when spoilers are hidden. Shared by the
/// panel and the end card.
Widget _episodeStill(BuildContext context, MediaItem episode, String thumb) {
  final serverId = serverIdOrNull(episode.serverId);
  final image = OptimizedMediaImage.thumb(
    client: context.tryGetMediaClientForServer(serverId),
    imagePath: thumb,
    localFilePath: serverId == null
        ? null
        : DownloadArtworkService.localPathSync(DownloadStorageService.instance, serverId, thumb),
    fit: BoxFit.cover,
    errorWidget: (context, _, _) => const SizedBox.shrink(),
  );
  if (SettingsService.instanceOrNull == null) return image;
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
