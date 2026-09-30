import 'package:flutter/widgets.dart';

import '../widgets/app_menu.dart';

/// A destination with something more behind its name in the side rail.
///
/// Implemented by the screen rather than answered by the rail, because only
/// the screen knows whether there is anything to list: one connected provider
/// is not a choice.
abstract mixin class OckerSubmenuHost {
  /// The destination's sub-navigation as rows, which the rail lists under it
  /// while it is open. Null where there is nothing to list.
  OckerRailMenu? get ockerRailMenu => null;

  /// A second press on the destination where it lists no rows: opens what is
  /// behind it — the libraries' column. False when there was nothing to open.
  bool showOckerSubmenu() => false;
}

/// A destination's sub-navigation, as the side rail lists it.
class OckerRailMenu {
  const OckerRailMenu(this.items);

  final List<OckerRailItem> items;

  /// The rows for [entries], each choosing its value through [onChosen].
  /// Dividers become a gap before the next row; headers are left out.
  static OckerRailMenu? fromEntries<T>(List<AppMenuEntry<T>> entries, void Function(T value) onChosen) {
    final items = <OckerRailItem>[];
    var gap = false;
    for (final entry in entries) {
      if (entry is AppMenuDivider<T>) {
        gap = items.isNotEmpty;
        continue;
      }
      if (entry is! AppMenuItem<T> || !entry.enabled) continue;
      final label = entry.label;
      if (label == null) continue;
      items.add(
        OckerRailItem(
          label: label,
          icon: entry.icon,
          leading: entry.leading,
          selected: entry.selected,
          gapBefore: gap,
          onSelect: () => onChosen(entry.value),
        ),
      );
      gap = false;
    }
    return items.isEmpty ? null : OckerRailMenu(items);
  }
}

/// One row of a [OckerRailMenu].
class OckerRailItem {
  const OckerRailItem({
    required this.label,
    required this.onSelect,
    this.icon,
    this.leading,
    this.selected = false,
    this.gapBefore = false,
  });

  final String label;
  final IconData? icon;

  /// Drawn instead of [icon] — a provider's mark.
  final Widget? leading;

  /// The one on show: a view, a list, a league — or a filter that is on.
  final bool selected;

  /// A little air before it, where the list has a divider.
  final bool gapBefore;

  final VoidCallback onSelect;
}
