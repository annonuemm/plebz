import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../focus/dpad_reorder_mixin.dart';
import '../focus/input_mode_tracker.dart';
import '../i18n/strings.g.dart';
import 'app_icon.dart';
import 'bottom_sheet_header.dart';

/// The frame of a management list (Plebz): the TV dialog and the bottom sheet
/// differ only in framing. Shared by "Sender verwalten" and "Ligen verwalten".
class ManagementScaffold extends StatelessWidget {
  const ManagementScaffold({
    super.key,
    required this.isDialog,
    required this.title,
    required this.icon,
    required this.listFocusNode,
    required this.onKeyEvent,
    required this.child,
    this.onBack,
    this.onClose,
  });

  final bool isDialog;
  final String title;
  final IconData icon;
  final FocusNode listFocusNode;
  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;
  final Widget child;

  /// A group's channels, opened from the groups, lead back to them
  /// with an arrow of their own; their close closes the whole of it.
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final body = Focus(
      focusNode: listFocusNode,
      descendantsAreFocusable: false,
      autofocus: InputModeTracker.isKeyboardMode(context),
      onKeyEvent: onKeyEvent,
      child: child,
    );

    if (isDialog) {
      return Dialog(
        child: PopScope(
          canPop: false,
          // ignore: no-empty-block - required callback, blocks system back on Android TV
          onPopInvokedWithResult: (didPop, result) {},
          child: Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              leading: onBack == null
                  ? null
                  : IconButton(
                      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                      icon: const AppIcon(Symbols.arrow_back_rounded, fill: 1),
                      onPressed: onBack,
                    ),
              title: Row(
                children: [
                  if (onBack == null) ...[AppIcon(icon, fill: 1), const SizedBox(width: 12)],
                  Expanded(child: Text(title)),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: t.common.close,
                  icon: const AppIcon(Symbols.close_rounded, fill: 1),
                  onPressed: onClose ?? () => Navigator.pop(context),
                ),
              ],
            ),
            body: body,
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: .min,
      children: [
        BottomSheetHeader(title: title, icon: onBack == null ? icon : null, onBack: onBack, onClose: onClose),
        Flexible(child: body),
      ],
    );
  }
}

/// One reorderable row of a management list: drag handle, label, a visibility
/// toggle and, where there is more under it, a way in.
class ManagementTile extends StatelessWidget {
  const ManagementTile({
    super.key,
    required this.index,
    required this.title,
    required this.subtitle,
    required this.leadingIcon,
    required this.isHidden,
    required this.isFocused,
    required this.isMoving,
    required this.focusedColumn,
    required this.showTooltip,
    required this.hideTooltip,
    required this.onToggleHidden,
    this.openTooltip,
    this.onOpen,
  });

  final int index;
  final String title;
  final String? subtitle;
  final IconData leadingIcon;
  final bool isHidden;
  final bool isFocused;
  final bool isMoving;
  final int? focusedColumn;
  final String showTooltip;
  final String hideTooltip;
  final VoidCallback onToggleHidden;
  final String? openTooltip;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tileColor = dpadReorderRowColor(context, isMoving: isMoving, isRowFocused: isFocused && focusedColumn == 0);

    return Opacity(
      opacity: isHidden ? 0.5 : 1.0,
      child: DpadReorderRowMark(
        isMoving: isMoving,
        isRowFocused: isFocused && focusedColumn == 0,
        child: ListTile(
          tileColor: tileColor,
          onTap: onOpen,
          title: Text(title, maxLines: 1, overflow: .ellipsis),
          subtitle: subtitle == null ? null : Text(subtitle!, maxLines: 1, overflow: .ellipsis),
          leading: Row(
            mainAxisSize: .min,
            children: [
              // The grip's box takes in the gap after it and the row's height, so a
              // finger has more than the glyph to land on; nothing moves on screen.
              ReorderableDragStartListener(
                index: index,
                child: ColoredBox(
                  color: Colors.transparent,
                  child: SizedBox(
                    width: 32,
                    height: 48,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: AppIcon(
                        isMoving ? Symbols.swap_vert_rounded : Symbols.drag_indicator_rounded,
                        fill: 1,
                        color: isMoving ? colorScheme.primary : IconTheme.of(context).color?.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
              ),
              AppIcon(leadingIcon, fill: 1),
            ],
          ),
          trailing: Row(
            mainAxisSize: .min,
            children: [
              DpadReorderButtonFocus(
                isFocused: isFocused && focusedColumn == 1,
                child: IconButton(
                  icon: AppIcon(isHidden ? Symbols.visibility_off_rounded : Symbols.visibility_rounded, fill: 1),
                  tooltip: isHidden ? showTooltip : hideTooltip,
                  onPressed: onToggleHidden,
                ),
              ),
              if (onOpen != null)
                DpadReorderButtonFocus(
                  isFocused: isFocused && focusedColumn == 2,
                  child: IconButton(
                    icon: const AppIcon(Symbols.chevron_right_rounded, fill: 1),
                    tooltip: openTooltip,
                    onPressed: onOpen,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
