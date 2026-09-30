import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../redesign/ocker_skin.dart';
import '../theme/mono_tokens.dart';
import '../utils/scroll_utils.dart';
import '../widgets/overlay_sheet.dart';
import 'dpad_navigator.dart';
import 'focus_theme.dart';
import 'key_event_utils.dart';

/// The fill that marks a row of a D-pad reorder list: the row being moved, or
/// the cursor standing on the row itself (column 0).
///
/// Taken from the ink, not from the scheme's container colours. The mono
/// schemes set `surfaceContainerHighest` and `primaryContainer` to the surface
/// itself, and a dialog is painted in exactly that surface — so a row marked
/// with them was marked in the dialog's own colour. The cursor did move up and
/// down; only the trailing buttons, which carry a fill of their own, ever
/// showed where it was, and the list read as one row that LEFT and RIGHT walk.
///
/// Null under "Glas", where [DpadReorderRowMark] marks the row with glass.
Color? dpadReorderRowColor(BuildContext context, {required bool isMoving, required bool isRowFocused}) {
  if (ockerGlass(context)) return null;
  final ink = tokens(context).text;
  if (isMoving) return ink.withValues(alpha: 0.2);
  if (isRowFocused) return ink.withValues(alpha: 0.12);
  return null;
}

/// Under "Glas", the pane behind a reorder row that marks it: bright glass
/// where the cursor stands on the row, the quiet accent-washed pane on the row
/// being moved — as the menus mark focus and the chosen entry. Elsewhere
/// [child] as it is; the row colours itself with [dpadReorderRowColor].
class DpadReorderRowMark extends StatelessWidget {
  const DpadReorderRowMark({super.key, required this.isMoving, required this.isRowFocused, required this.child});

  final bool isMoving;
  final bool isRowFocused;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!ockerGlass(context)) return child;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: isMoving || isRowFocused ? 1 : 0,
              duration: ockerInkFade(context),
              curve: Curves.easeOutCubic,
              child: OckerGlassFocusFill(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(tokens(context).radiusSm)),
                bright: !isMoving,
                tint: isMoving ? 1 : 0,
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Focus on one of a reorder row's trailing buttons — hide, options, remove.
/// Under "Glas" a round pane of bright glass behind the icon, elsewhere the
/// pale plate.
class DpadReorderButtonFocus extends StatelessWidget {
  const DpadReorderButtonFocus({super.key, required this.isFocused, required this.child});

  final bool isFocused;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!ockerGlass(context)) {
      return Container(
        decoration: FocusTheme.focusBackgroundDecoration(isFocused: isFocused, borderRadius: 20),
        child: child,
      );
    }
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: isFocused ? 1 : 0,
              duration: ockerInkFade(context),
              curve: Curves.easeOutCubic,
              child: const OckerGlassFocusFill(shape: CircleBorder()),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// D-pad "move mode" reordering for a remote/keyboard-driven list of rows
/// inside a sheet or dialog.
///
/// The host keeps its list and row widgets; this mixin owns the virtual cursor
/// ([focusedIndex] / [focusedColumn]), the move-mode state and the key handler.
/// Wire it up by passing [handleReorderKeyEvent] to the list's
/// `Focus.onKeyEvent` and by reading [focusedIndex], [focusedColumn] and
/// [movingIndex] when building rows.
///
/// Navigation mode: UP/DOWN move between rows (resetting to column 0),
/// LEFT/RIGHT move between the row (column 0) and the trailing action columns
/// up to [lastReorderColumn], SELECT on column 0 enters move mode and on any
/// other column calls [onReorderColumnActivated].
///
/// Move mode: UP/DOWN swap the moving row with its neighbour, SELECT confirms
/// through [onReorderMoveConfirmed], and BACK restores the order captured when
/// move mode was entered. BACK outside move mode dismisses the hosting sheet.
/// D-pad keys are consumed at the list boundaries so focus cannot escape.
mixin DpadReorderListMixin<E, W extends StatefulWidget> on State<W> {
  /// Fraction of the viewport kept above the focused row when it is scrolled
  /// into view.
  static const double _revealAlignment = 0.25;

  /// Row the virtual cursor sits on.
  int focusedIndex = 0;

  /// Column within [focusedIndex]: 0 is the row itself, 1..[lastReorderColumn]
  /// are the trailing action buttons.
  int focusedColumn = 0;

  /// Row being moved, or null when not in move mode.
  int? movingIndex;

  int? _originalIndex;
  List<E>? _originalOrder;
  bool _backKeyDownSeen = false;

  /// The list being reordered. Mutated in place while moving and replaced
  /// wholesale when a move is cancelled.
  List<E> get reorderItems;
  set reorderItems(List<E> value);

  /// Right-most focusable column index (0 when the row has no action buttons).
  int get lastReorderColumn;

  /// Scrollable holding the rows, or null when the host does not scroll the
  /// focused row into view.
  ScrollController? get reorderScrollController;

  /// Called when SELECT confirms a move; [reorderItems] already holds the new
  /// order.
  void onReorderMoveConfirmed();

  /// Called when SELECT activates a trailing action column (1 or greater).
  void onReorderColumnActivated(int column, int index);

  /// Scrolls [focusedIndex] into view, parking it ~25% from the viewport top.
  void ensureFocusedVisible() {
    final scrollController = reorderScrollController;
    if (scrollController == null || !scrollController.hasClients) return;
    scrollIndexIntoView(scrollController, focusedIndex, alignment: _revealAlignment);
  }

  KeyEventResult handleReorderKeyEvent(FocusNode _, KeyEvent event) {
    final key = event.logicalKey;

    // Track back key down/up pairing. If focus was elsewhere during KeyDown
    // (e.g., on a bottom sheet) and returns here before KeyUp, we get a stray
    // KeyUp that would incorrectly pop the dialog. Consume it instead.
    if (key.isBackKey) {
      if (event is KeyDownEvent) {
        _backKeyDownSeen = true;
      } else if (event is KeyUpEvent && !_backKeyDownSeen) {
        return KeyEventResult.handled;
      }
      if (event is KeyUpEvent) {
        _backKeyDownSeen = false;
      }
    }

    final backResult = handleBackKeyAction(event, () {
      if (movingIndex != null) {
        setState(() {
          final originalOrder = _originalOrder;
          if (originalOrder != null) {
            reorderItems = List<E>.from(originalOrder);
          }
          focusedIndex = _originalIndex ?? 0;
          movingIndex = null;
          _originalIndex = null;
          _originalOrder = null;
        });
      } else {
        OverlaySheetController.popAdaptive(context);
      }
    });
    if (backResult != KeyEventResult.ignored) {
      return backResult;
    }

    // SELECT is one-shot: holding OK must not repeat a destructive column
    // action (e.g. removing a favorite) or flip move mode on and off.
    final selectResult = handleOneShotSelect(event, _activateSelect);
    if (selectResult != KeyEventResult.ignored) return selectResult;

    if (!event.isActionable) return KeyEventResult.ignored;

    final int? moving = movingIndex;
    if (moving != null) {
      // Move mode - arrows reorder the item
      if (key.isUpKey && moving > 0) {
        _swapMovingItem(moving, moving - 1);
        return KeyEventResult.handled;
      }
      if (key.isDownKey && moving < reorderItems.length - 1) {
        _swapMovingItem(moving, moving + 1);
        return KeyEventResult.handled;
      }
    } else {
      // Navigation mode
      if (key.isUpKey && focusedIndex > 0) {
        setState(() {
          focusedIndex--;
          focusedColumn = 0; // Reset to row when changing rows
        });
        ensureFocusedVisible();
        return KeyEventResult.handled;
      }
      if (key.isDownKey && focusedIndex < reorderItems.length - 1) {
        setState(() {
          focusedIndex++;
          focusedColumn = 0; // Reset to row when changing rows
        });
        ensureFocusedVisible();
        return KeyEventResult.handled;
      }
      if (key.isLeftKey && focusedColumn > 0) {
        setState(() => focusedColumn--);
        return KeyEventResult.handled;
      }
      if (key.isRightKey && focusedColumn < lastReorderColumn) {
        setState(() => focusedColumn++);
        return KeyEventResult.handled;
      }
    }

    // Block d-pad keys at boundaries so focus doesn't escape the dialog
    if (key.isDpadDirection) {
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _activateSelect() {
    if (movingIndex != null) {
      // Confirm move - apply the reorder
      onReorderMoveConfirmed();
      setState(() {
        movingIndex = null;
        _originalIndex = null;
        _originalOrder = null;
      });
      return;
    }
    if (focusedIndex >= reorderItems.length) return;
    if (focusedColumn == 0) {
      // Enter move mode
      setState(() {
        movingIndex = focusedIndex;
        _originalIndex = focusedIndex;
        _originalOrder = List<E>.from(reorderItems);
      });
    } else {
      onReorderColumnActivated(focusedColumn, focusedIndex);
    }
  }

  void _swapMovingItem(int from, int to) {
    setState(() {
      final item = reorderItems.removeAt(from);
      reorderItems.insert(to, item);
      movingIndex = to;
      focusedIndex = to;
    });
    ensureFocusedVisible();
  }
}
