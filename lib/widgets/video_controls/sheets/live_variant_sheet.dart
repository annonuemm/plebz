import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../i18n/strings.g.dart';
import '../../app_icon.dart';
import '../../focusable_list_tile.dart';
import '../../overlay_sheet.dart';

/// The copies of this station, to pick from.
///
/// Marked with the one playing: the point of the list is to say where you are
/// as much as to offer somewhere else. Scrolls because a playlist can carry a
/// station six times, and a phone on its side has room for four.
Future<void> showLiveVariantSheet(
  BuildContext context, {
  required List<String> labels,
  required int index,
  required ValueChanged<int>? onSelected,
}) async {
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
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var row = 0; row < labels.length; row++)
                    FocusableListTile(
                      autofocus: row == index,
                      leading: AppIcon(
                        row == index ? Symbols.play_circle_rounded : Symbols.circle_rounded,
                        fill: row == index ? 1 : 0,
                      ),
                      title: Text(labels[row]),
                      // closeAdaptive, not Navigator.pop: showAdaptive renders
                      // inside the player's OverlaySheetHost rather than as a
                      // route, and a route pop there closes nothing and returns
                      // no value — the picker stayed open and the switch never ran.
                      onTap: () => OverlaySheetController.closeAdaptive(sheetContext, row),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
  if (chosen != null && chosen != index) onSelected?.call(chosen);
}
