import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/strings.g.dart';
import '../../services/iptv/iptv_live_tv_source.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/focusable_list_tile.dart';
import '../../widgets/focused_scroll_scaffold.dart';

/// Choosing which of a provider's groups a source loads (fork addition).
///
/// Every group the provider offers, ticked where it is loaded. A group the
/// provider added since the last choice is marked "neu" and starts unticked:
/// new groups are not taken over by themselves, so a list cut down stays cut
/// down. Closes with the chosen keys, in the provider's order, or with null
/// when left without "Übernehmen".
class IptvGroupPickerScreen extends StatefulWidget {
  const IptvGroupPickerScreen({super.key, required this.options, required this.selected, required this.known});

  final List<IptvGroupOption> options;

  /// What is chosen now; null for every group.
  final List<String>? selected;

  /// Every group offered at the last choice; empty before the first.
  final List<String> known;

  static Route<List<String>> route({
    required List<IptvGroupOption> options,
    required List<String>? selected,
    required List<String> known,
  }) => MaterialPageRoute<List<String>>(
    builder: (_) => IptvGroupPickerScreen(options: options, selected: selected, known: known),
  );

  @override
  State<IptvGroupPickerScreen> createState() => _IptvGroupPickerScreenState();
}

class _IptvGroupPickerScreenState extends State<IptvGroupPickerScreen> {
  late final Set<String> _chosen = widget.selected?.toSet() ?? {for (final option in widget.options) option.key};

  bool _isNew(IptvGroupOption option) => widget.known.isNotEmpty && !widget.known.contains(option.key);

  void _setAll(bool on) => setState(() {
    _chosen.clear();
    if (on) _chosen.addAll(widget.options.map((option) => option.key));
  });

  void _apply() => Navigator.of(context).pop([
    for (final option in widget.options)
      if (_chosen.contains(option.key)) option.key,
  ]);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.7));
    final chosenChannels = widget.options.every((option) => option.channelCount != null)
        ? widget.options
              .where((option) => _chosen.contains(option.key))
              .fold<int>(0, (sum, option) => sum + option.channelCount!)
        : null;

    return FocusedScrollScaffold(
      title: Text(t.iptv.groupsTitle),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              chosenChannels == null
                  ? t.iptv.groupsChosenOf(chosen: _chosen.length, total: widget.options.length)
                  : t.iptv.groupsChosenWithChannels(
                      chosen: _chosen.length,
                      total: widget.options.length,
                      channels: chosenChannels,
                    ),
              style: muted,
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildListDelegate([
            // The three actions first, where UP from the list ends: a list of
            // hundreds of groups must not put the way out at its foot.
            FocusableListTile(
              leading: const AppIcon(Symbols.check_rounded, fill: 1),
              title: Text(t.iptv.groupsApply),
              onTap: _apply,
            ),
            FocusableListTile(
              leading: const AppIcon(Symbols.select_all_rounded, fill: 1),
              title: Text(t.iptv.groupsAll),
              onTap: () => _setAll(true),
            ),
            FocusableListTile(
              leading: const AppIcon(Symbols.deselect_rounded, fill: 1),
              title: Text(t.iptv.groupsNone),
              onTap: () => _setAll(false),
            ),
            const Divider(height: 16),
            for (final option in widget.options)
              FocusableListTile(
                leading: AppIcon(
                  _chosen.contains(option.key) ? Symbols.check_box_rounded : Symbols.check_box_outline_blank_rounded,
                  fill: 1,
                ),
                title: Text(option.label.isEmpty ? t.iptv.groupsWithout : option.label),
                subtitle: _subtitle(option),
                onTap: () => setState(() {
                  if (!_chosen.remove(option.key)) _chosen.add(option.key);
                }),
              ),
          ]),
        ),
      ],
    );
  }

  Widget? _subtitle(IptvGroupOption option) {
    final parts = [
      if (option.channelCount case final count?) t.iptv.groupsChannelCount(count: count),
      if (_isNew(option)) t.iptv.groupsNew,
    ];
    return parts.isEmpty ? null : Text(parts.join(' · '));
  }
}
