import 'package:flutter/material.dart';

import '../focus/focusable_chip_mixin.dart';
import '../focus/input_mode_tracker.dart';
import '../redesign/ocker_skin.dart';
import '../redesign/ocker_type.dart';
import '../theme/mono_tokens.dart';
import '../utils/platform_detector.dart';
import 'focus_builders.dart';

/// Horizontally scrollable host for a row of [FocusableTabChip]s.
///
/// App-bar titles and header rows give the strip a bounded width; a plain
/// Row overflows it on narrow windows (visible as the striped overflow
/// indicator). The strip shrink-wraps like `mainAxisSize: min` and scrolls
/// instead. D-pad stays correct: chips center themselves on focus via the
/// chip mixin, so LEFT/RIGHT reaches off-screen tabs.
class TabChipStrip extends StatelessWidget {
  final List<Widget> children;

  const TabChipStrip({super.key, required this.children});

  /// How far the strip's pane reaches past its row under "Redesign – Glas":
  /// an even margin round every capsule, concentric. Each tab already stands
  /// its chip's padding, and the rule's room, off the row's edge.
  static EdgeInsets overhangOf(BuildContext context) {
    final scale = ockerScale(context);
    return ockerBandOverhang(
      context,
      wordInset: EdgeInsets.symmetric(horizontal: 11 * scale, vertical: 6 * scale + (4 + 2) * scale / 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      // Under "Redesign – Glas" the tabs lie on a pane that reaches past them.
      clipBehavior: ockerGlass(context) ? Clip.none : Clip.hardEdge,
      child: OckerGlassBand(
        overhang: overhangOf(context),
        child: Row(mainAxisSize: .min, children: children),
      ),
    );
  }
}

/// A focusable tab chip that shows a color change when focused or selected.
///
/// Used for tab navigation in LibrariesScreen. Handles:
/// - SELECT key to activate the tab
/// - LEFT/RIGHT arrows to switch between tabs
/// - DOWN arrow to navigate to tab content
/// - BACK key to navigate to sidenav
/// The colour that marks a tab as switched on.
///
/// A fixed red rather than anything from the scheme: the theme is monochrome by
/// design, so every scheme colour is already spoken for by focus, surfaces or
/// text, and "active" needs to be unmistakably none of those. Dark enough that
/// white sits on it at about 4.9:1, which clears AA for the chip's bold label.
const Color activeTabChipColor = Color(0xFFD32F2F);

/// Label colour on [activeTabChipColor]. Fixed for the same reason the
/// background is: it must not follow a light theme into dark text on red.
const Color onActiveTabChipColor = Color(0xFFFFFFFF);

class FocusableTabChip extends StatefulWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onSelect;

  /// Optional external focus node for programmatic focus control.
  final FocusNode? focusNode;

  /// Called when the user presses LEFT from this chip.
  /// Should switch to the previous tab.
  final VoidCallback? onNavigateLeft;

  /// Called when the user presses RIGHT from this chip.
  /// Should switch to the next tab.
  final VoidCallback? onNavigateRight;

  /// Called when the user presses DOWN from this chip.
  final VoidCallback? onNavigateDown;

  /// Called when the user presses UP from this chip.
  final VoidCallback? onNavigateUp;

  /// Called when the user presses BACK from this chip.
  final VoidCallback? onBack;

  /// Called when SELECT key is held (D-pad long press).
  final VoidCallback? onLongPress;

  /// Optional image to show above the label (e.g. a poster).
  /// When provided, the chip lays out vertically with image on top, label below.
  final Widget? topImage;

  const FocusableTabChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onSelect,
    this.focusNode,
    this.onNavigateLeft,
    this.onNavigateRight,
    this.onNavigateDown,
    this.onNavigateUp,
    this.onBack,
    this.onLongPress,
    this.topImage,
  });

  @override
  State<FocusableTabChip> createState() => _FocusableTabChipState();
}

class _FocusableTabChipState extends State<FocusableTabChip> with FocusableChipStateMixin<FocusableTabChip> {
  @override
  FocusNode? get widgetFocusNode => widget.focusNode;

  @override
  String get debugLabel => 'tab_chip_${widget.label}';

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    return handleChipKeyEvent(
      node,
      event,
      ChipKeyCallbacks(
        onSelect: widget.onSelect,
        onLongPress: widget.onLongPress,
        onNavigateLeft: widget.onNavigateLeft,
        onNavigateRight: widget.onNavigateRight,
        onNavigateDown: widget.onNavigateDown,
        onNavigateUp: widget.onNavigateUp,
        onBack: widget.onBack,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Only show focus effects during keyboard/d-pad navigation
    final showFocus = isFocused && InputModeTracker.isKeyboardMode(context);

    if (isOcker(context)) return _buildOcker(context, showFocus: showFocus);

    // Two states, two colours, so they can never be read as the same thing:
    // - Active: the accent, which nothing else in this monochrome theme uses.
    // - Focused: the plain light chip that marks focus everywhere else.
    // - Both: the focus chip with the accent moved into the label — where you
    //   are and what is switched on, without inventing a third treatment.
    Color backgroundColor;
    Color foregroundColor;

    if (widget.isSelected && showFocus) {
      backgroundColor = colorScheme.primary;
      foregroundColor = activeTabChipColor;
    } else if (widget.isSelected) {
      backgroundColor = activeTabChipColor;
      foregroundColor = onActiveTabChipColor;
    } else if (showFocus) {
      backgroundColor = colorScheme.primary;
      foregroundColor = colorScheme.onPrimary;
    } else {
      // Neither selected nor focused
      if (PlatformDetector.isTV()) {
        backgroundColor = colorScheme.secondaryContainer.withValues(alpha: 0.38);
        foregroundColor = colorScheme.onSecondaryContainer;
      } else {
        backgroundColor = colorScheme.surfaceContainerHighest;
        foregroundColor = colorScheme.onSurfaceVariant;
      }
    }

    final isHighlighted = showFocus || widget.isSelected;

    final label = Text(
      widget.label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: foregroundColor,
        fontWeight: isHighlighted ? FontWeight.w600 : FontWeight.normal,
      ),
    );

    final hasImage = widget.topImage != null;
    return FocusBuilders.buildFocusableChip(
      context: context,
      focusNode: focusNode,
      onKeyEvent: _handleKeyEvent,
      onTap: widget.onSelect,
      semanticLabel: widget.label,
      selected: widget.isSelected,
      padding: hasImage ? const EdgeInsets.all(8) : const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      backgroundColor: backgroundColor,
      borderRadius: hasImage ? 12 : 20,
      child: hasImage
          ? Column(
              mainAxisSize: .min,
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(flatRadius(context, 6)), child: widget.topImage!),
                const SizedBox(height: 6),
                label,
              ],
            )
          : label,
    );
  }

  /// The same chip as "Ocker" draws it: no plate at all.
  ///
  /// The design has one treatment for "this is the section you are in", and it
  /// is not a filled shape — it is the word at full strength with a 2 px ocher
  /// rule beneath it, everything else dimmed. That keeps the accent inside the
  /// three jobs it is allowed (progress, the now-line, the active entry) and
  /// spares the app a second one: a red plate here would be a colour that
  /// appears nowhere else in the design and says nothing the weight does not.
  ///
  /// Focus stays what it is everywhere else — a hairline ink ring, held off the
  /// word — so "where I am" and "what is switched on" still read as two
  /// different things when they land on the same chip.
  Widget _buildOcker(BuildContext context, {required bool showFocus}) {
    final tk = tokens(context);
    final type = OckerType.of(context);
    final scale = ockerScale(context);
    final active = widget.isSelected;
    final glass = ockerGlass(context);
    final markRoom = (4 + 2) * scale / 2;

    // Faded under glass, in step with the capsule.
    final label = OckerInk(
      color: active || showFocus ? tk.ink(1) : tk.ink(0.5),
      builder: (context, ink) => Text(
        widget.label,
        // On a phone or tablet at the size the original look sets its tabs, a
        // point up: at the redesign's own a library's three views no longer
        // fit across a phone, and the row began to scroll where it had not.
        style: type
            .groupEntry(active: active)
            .copyWith(color: ink, fontSize: PlatformDetector.isMobile(context) ? 15 : null),
      ),
    );

    final body = widget.topImage == null
        ? label
        : Column(
            mainAxisSize: .min,
            children: [
              widget.topImage!,
              SizedBox(height: 6 * scale),
              label,
            ],
          );

    return FocusBuilders.buildFocusableChip(
      context: context,
      focusNode: focusNode,
      onKeyEvent: _handleKeyEvent,
      onTap: widget.onSelect,
      semanticLabel: widget.label,
      selected: widget.isSelected,
      padding: EdgeInsets.zero,
      backgroundColor: Colors.transparent,
      borderRadius: 0,
      child: Padding(
        // Horizontal room between neighbouring words; the ring's own offset
        // supplies the rest.
        padding: EdgeInsets.symmetric(horizontal: 11 * scale, vertical: 6 * scale),
        // IntrinsicWidth so the rule below can be exactly as wide as the word
        // above it: the strip is laid out in an unbounded Row, where a
        // stretched child has nothing to stretch to.
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            children: [
              // Under glass the capsule marks the tab on show, so the rule
              // gives way; its room is split above and below the word, which
              // then sits in the middle of the glass at the same height.
              if (glass) SizedBox(height: markRoom),
              // The ring, or under glass a capsule — see [OckerWordFocus].
              OckerWordFocus(
                focused: showFocus,
                active: active,
                child: Padding(padding: EdgeInsets.all(tk.focusRingOffset), child: body),
              ),
              if (glass)
                SizedBox(height: markRoom)
              else ...[
                // The same short gap the header's destinations use, so the two
                // rows of words are marked the same way.
                SizedBox(height: 4 * scale),
                // Drawn whether active or not, so the row never changes height
                // as the selection moves along it.
                Container(height: 2 * scale, color: active ? tk.accent : Colors.transparent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
