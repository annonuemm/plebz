import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../navigation/navigation_tabs.dart' show navIconWeight;
import '../theme/liquid_glass.dart';
import '../theme/mono_tokens.dart';
import '../widgets/app_icon.dart';
import '../widgets/navigation_label_fit.dart';
import 'ocker_skin.dart';

/// One place in [OckerFloatingTabBar].
class OckerFloatingTabBarItem {
  const OckerFloatingTabBarItem({required this.icon, required this.label, this.onLongPress});

  final IconData icon;
  final String label;

  /// A hold on this place (the libraries' quick picker).
  final VoidCallback? onLongPress;
}

/// The phone's bottom navigation as Apple's apps draw it (Plebz, iPhone and
/// iPad upright on Apple's build — see `ockerGlasTouch`): a capsule of glass
/// floating over the page, clear of the screen's edges, and the place one is at
/// standing on a capsule of its own in the accent, its glyph filled.
///
/// The same places as the Material bar it stands in for, in the same order,
/// answering the same taps and the same hold — only drawn differently. The
/// page still ends above it.
class OckerFloatingTabBar extends StatelessWidget {
  const OckerFloatingTabBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.showLabels = true,
  });

  final List<OckerFloatingTabBarItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool showLabels;

  /// The capsule's height with and without labels.
  static const double labelledHeight = 60;
  static const double compactHeight = 50;

  /// How far the capsule stays from the screen's sides.
  static const double sideMargin = 12;

  /// The widest the capsule grows: on an upright iPad a bar the screen's
  /// width would spread its places across most of a metre of glass. Each
  /// place gets [maxPlaceWidth] at most, and the bar never less than 560.
  static const double maxWidth = 560;
  static const double maxPlaceWidth = 88;

  /// The inset of each place's own capsule inside the bar, all round —
  /// concentric with the bar's ends.
  static const double platterInset = 4;

  static const double labelSize = 11;

  @override
  Widget build(BuildContext context) {
    final height = showLabels ? labelledHeight : compactHeight;
    // Over the home indicator, as Apple's bar sits: part of the way into the
    // inset rather than on top of it.
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final bottom = bottomInset > 0 ? bottomInset * 0.6 : 12.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(sideMargin, 6, sideMargin, bottom),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: math.max(maxWidth, items.length * maxPlaceWidth),
            minHeight: height,
            maxHeight: height,
          ),
          child: OckerGlass(
            borderRadius: BorderRadius.circular(height / 2),
            scrimInset: 0,
            liquid: true,
            // A bar this narrow keeps the thin rim of the buttons' bubble:
            // the pane's own would bend most of what passes under it.
            lensThickness: OckerLiquidGlass.bubbleThickness,
            lensStrength: OckerLiquidGlass.bubbleStrength,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final itemWidth = items.isEmpty ? 0.0 : constraints.maxWidth / items.length;
                final row = Row(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      Expanded(
                        child: _Place(
                          item: items[i],
                          selected: i == selectedIndex,
                          showLabel: showLabels,
                          onTap: () => onSelected(i),
                        ),
                      ),
                  ],
                );
                if (!showLabels) return row;
                return NavigationLabelScale(
                  labels: [for (final item in items) item.label],
                  labelWidth: itemWidth - 2 * (platterInset + _Place.labelPadding),
                  style: _Place.labelStyle(context),
                  child: row,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Place extends StatelessWidget {
  const _Place({required this.item, required this.selected, required this.showLabel, required this.onTap});

  final OckerFloatingTabBarItem item;
  final bool selected;
  final bool showLabel;
  final VoidCallback onTap;

  /// Room either side of a label inside its place's capsule.
  static const double labelPadding = 2;

  static TextStyle labelStyle(BuildContext context) => (Theme.of(context).textTheme.labelSmall ?? const TextStyle())
      .copyWith(fontSize: OckerFloatingTabBar.labelSize, fontWeight: FontWeight.w500, height: 1.1);

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    // The places not chosen at 85 %: over a bright poster under the glass a
    // quieter ink was lost.
    final ink = selected ? tk.accent : tk.ink(0.85);
    // The place one is at: the accent's wash under glass, Flach's lighter ink
    // segment flat.
    final platter = !selected
        ? Colors.transparent
        : (tk.flat ? tk.ink(0.12) : tk.accent.withValues(alpha: tk.accentWash));
    final glyph = AppIcon(item.icon, fill: selected ? 1 : 0, weight: navIconWeight, size: 24, color: ink);
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.all(OckerFloatingTabBar.platterInset),
        child: InkWell(
          onTap: onTap,
          onLongPress: item.onLongPress,
          customBorder: const StadiumBorder(),
          child: AnimatedContainer(
            duration: tk.fast,
            decoration: ShapeDecoration(color: platter, shape: const StadiumBorder()),
            padding: const EdgeInsets.symmetric(horizontal: labelPadding),
            alignment: Alignment.center,
            child: showLabel
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      glyph,
                      const SizedBox(height: 2),
                      Text(
                        item.label,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: labelStyle(context).copyWith(color: ink),
                      ),
                    ],
                  )
                : glyph,
          ),
        ),
      ),
    );
  }
}
