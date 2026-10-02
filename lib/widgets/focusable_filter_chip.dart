import 'package:flutter/material.dart';
import 'package:plezy/widgets/app_icon.dart';

import '../focus/focusable_chip_mixin.dart';
import '../focus/input_mode_tracker.dart';
import 'focus_builders.dart';
import '../redesign/ocker_filter_glyph.dart';
import '../redesign/ocker_skin.dart';
import '../theme/mono_tokens.dart';

/// A focusable filter chip that shows a color change when focused.
///
/// Unlike FocusableWrapper which uses scale + border, this widget
/// uses a background color change to indicate focus state.
class FocusableFilterChip extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  /// Optional external focus node for programmatic focus control.
  final FocusNode? focusNode;

  /// Called when the user presses DOWN from this chip.
  final VoidCallback? onNavigateDown;

  /// Called when the user presses UP from this chip.
  final VoidCallback? onNavigateUp;

  /// Called when the user presses LEFT from this chip.
  final VoidCallback? onNavigateLeft;

  /// Called when the user presses RIGHT from this chip.
  final VoidCallback? onNavigateRight;

  /// Called when the user presses BACK from this chip.
  final VoidCallback? onBack;

  const FocusableFilterChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.focusNode,
    this.onNavigateDown,
    this.onNavigateUp,
    this.onNavigateLeft,
    this.onNavigateRight,
    this.onBack,
  });

  @override
  State<FocusableFilterChip> createState() => _FocusableFilterChipState();
}

class _FocusableFilterChipState extends State<FocusableFilterChip> with FocusableChipStateMixin<FocusableFilterChip> {
  @override
  FocusNode? get widgetFocusNode => widget.focusNode;

  @override
  String get debugLabel => 'filter_chip_${widget.label}';

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    return handleChipKeyEvent(
      node,
      event,
      ChipKeyCallbacks(
        onSelect: widget.onPressed,
        onNavigateDown: widget.onNavigateDown,
        onNavigateUp: widget.onNavigateUp,
        onNavigateLeft: widget.onNavigateLeft,
        onNavigateRight: widget.onNavigateRight,
        onBack: widget.onBack,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Only show focus effects during keyboard/d-pad navigation
    final showFocus = isFocused && InputModeTracker.isKeyboardMode(context);

    // Under "Ocker" there is no plate at all — see [OckerFilterGlyph], which
    // the watchlist's own filter row draws too, so the two cannot drift apart
    // again.
    // On a phone, a tablet or the Mac the filters keep the line the screen
    // gives them and are pressed rather than focused, so the word is the only
    // way to tell them apart: a capsule of glass with the glyph and the word,
    // as the facts are set.
    if (isOcker(context) && ockerLookOnly(context)) {
      final tk = tokens(context);
      final ink = tk.ink(0.85);
      return FocusBuilders.buildFocusableChip(
        context: context,
        focusNode: focusNode,
        onKeyEvent: _handleKeyEvent,
        onTap: widget.onPressed,
        semanticLabel: widget.label,
        padding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        borderRadius: 0,
        child: OckerGlassPlate(
          shape: const StadiumBorder(),
          lit: false,
          firm: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: .min,
              children: [
                AppIcon(icon, size: 16, color: ink),
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: ink, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (isOcker(context)) {
      return FocusBuilders.buildFocusableChip(
        context: context,
        focusNode: focusNode,
        onKeyEvent: _handleKeyEvent,
        onTap: widget.onPressed,
        semanticLabel: widget.label,
        padding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        borderRadius: 0,
        // The word stays as the semantic name only: these sit on the same line
        // as the tabs, where a word spent here is a word taken from them, and
        // the sheet each one opens names itself anyway.
        child: OckerFilterGlyph(icon: icon, focused: showFocus),
      );
    }

    // Use primary color when focused, surface color when not
    final backgroundColor = showFocus ? colorScheme.primary : colorScheme.surfaceContainerHighest;
    final foregroundColor = showFocus ? colorScheme.onPrimary : colorScheme.onSurfaceVariant;

    return FocusBuilders.buildFocusableChip(
      context: context,
      focusNode: focusNode,
      onKeyEvent: _handleKeyEvent,
      onTap: widget.onPressed,
      semanticLabel: widget.label,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      backgroundColor: backgroundColor,
      child: Row(
        mainAxisSize: .min,
        children: [
          AppIcon(icon, size: 16, color: foregroundColor),
          const SizedBox(width: 6),
          Text(widget.label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: foregroundColor)),
        ],
      ),
    );
  }

  IconData get icon => widget.icon;
}
