import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../focus/focusable_wrapper.dart';
import '../../../redesign/ocker_skin.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/scroll_utils.dart';

/// One entry of the group list: the key the session filters by, the name it
/// is shown under, and how many channels are in it.
typedef LiveChannelGroupOption = ({String? key, String label, int count});

/// The groups of the loaded channel list, as a strip over the picture.
///
/// The counterpart of the channel strip on the other side: that one answers
/// "what else is on", this one "what else is there". A playlist of several
/// thousand channels is not walked one press at a time, and the group is the
/// only handle a viewer has on it.
class LiveGroupStrip extends StatefulWidget {
  const LiveGroupStrip({
    super.key,
    required this.groups,
    required this.selected,
    required this.onGroupSelected,
    this.onNavigateUp,
    this.onFocusActivity,
  });

  final List<LiveChannelGroupOption> groups;

  /// The group in force, or null for all channels.
  final String? selected;
  final void Function(String? group) onGroupSelected;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onFocusActivity;

  /// How much of the screen's width the list takes where the player sets it
  /// over the picture.
  static const double widthFactor = 0.5;

  /// Room the list keeps at its sides: a focused row grows by the focus
  /// scale, and a list clips at its own edges, so rows that ran edge to edge
  /// lost the sides of their focus and of the group in force.
  static const double sideRoom = 12;

  @override
  State<LiveGroupStrip> createState() => LiveGroupStripState();
}

class LiveGroupStripState extends State<LiveGroupStrip> {
  final _controller = ScrollController();
  final _focusNodes = <int, FocusNode>{};
  int _focusedIndex = 0;

  @override
  void initState() {
    super.initState();
    _focusedIndex = widget.groups.indexWhere((group) => group.key == widget.selected);
    if (_focusedIndex < 0) _focusedIndex = 0;
  }

  @override
  void dispose() {
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    _controller.dispose();
    super.dispose();
  }

  FocusNode _nodeFor(int index) => _focusNodes.putIfAbsent(index, () => FocusNode(debugLabel: 'live_group_$index'));

  /// Opens on the group in force, not at the top: that is where the viewer
  /// left off, and scrolling back to it by hand is the work this saves.
  void requestInitialFocus() {
    if (widget.groups.isEmpty) return;
    _nodeFor(_focusedIndex).requestFocus();
    scrollListToIndex(_controller, _focusedIndex, itemExtent: _rowHeight);
  }

  static const double _rowHeight = 52;

  /// How far a row's words stand in from its own edge.
  static const double _textInset = 20;

  void _move(int delta) {
    final next = _focusedIndex + delta;
    if (next < 0) {
      widget.onNavigateUp?.call();
      return;
    }
    if (next >= widget.groups.length) return;
    setState(() => _focusedIndex = next);
    _nodeFor(next).requestFocus();
    scrollListToIndex(_controller, next, itemExtent: _rowHeight);
  }

  KeyEventResult _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    widget.onFocusActivity?.call();
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        _move(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _move(1);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.groups.isEmpty) return const SizedBox.shrink();
    if (ockerGlass(context)) return _buildGlass(context);

    return Focus(
      onKeyEvent: (_, event) => _onKey(event),
      child: SizedBox(
        height: _rowHeight * 5,
        child: ListView.builder(
          controller: _controller,
          padding: const EdgeInsets.symmetric(horizontal: LiveGroupStrip.sideRoom),
          itemExtent: _rowHeight,
          itemCount: widget.groups.length,
          itemBuilder: (context, index) {
            final group = widget.groups[index];
            final isSelected = group.key == widget.selected;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: FocusableWrapper(
                focusNode: _nodeFor(index),
                onSelect: () => widget.onGroupSelected(group.key),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: _textInset),
                  alignment: .centerLeft,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(flatRadius(context, 10)),
                  ),
                  child: Row(
                    children: [
                      // A bar rather than a tick: it marks the group in force
                      // the way the strip marks the channel on air.
                      Container(width: 3, height: 22, color: isSelected ? tokens(context).accent : Colors.transparent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          group.label,
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: isSelected ? .w700 : null),
                        ),
                      ),
                      Text(
                        '${group.count}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Under "Redesign – Glas": the list on one pane of glass, as the guide's
  /// group column is — focus a pane of bright glass behind the row, the group
  /// in force a quiet one washed with the accent, the count in grey. No bar,
  /// no plates.
  Widget _buildGlass(BuildContext context) {
    final tk = tokens(context);
    final theme = Theme.of(context);
    final rowRadius = tk.radiusSm;
    const inset = 8.0;
    return Focus(
      onKeyEvent: (_, event) => _onKey(event),
      child: OckerGlass(
        borderRadius: BorderRadius.circular(rowRadius + inset),
        scrimInset: inset,
        groundOpacity: 0.9,
        child: SizedBox(
          height: _rowHeight * 5,
          child: ListView.builder(
            controller: _controller,
            padding: const EdgeInsets.symmetric(horizontal: LiveGroupStrip.sideRoom),
            itemExtent: _rowHeight,
            itemCount: widget.groups.length,
            itemBuilder: (context, index) {
              final group = widget.groups[index];
              final isSelected = group.key == widget.selected;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: FocusableWrapper(
                  focusNode: _nodeFor(index),
                  onSelect: () => widget.onGroupSelected(group.key),
                  useBackgroundFocus: true,
                  glassFocus: true,
                  borderRadius: rowRadius,
                  child: Stack(
                    fit: StackFit.passthrough,
                    children: [
                      if (isSelected)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: OckerGlassFocusFill(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rowRadius)),
                              bright: false,
                              tint: 1,
                            ),
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: _textInset),
                        alignment: .centerLeft,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                group.label,
                                maxLines: 1,
                                overflow: .ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: tk.ink(isSelected ? 1 : 0.85),
                                  fontWeight: isSelected ? .w600 : null,
                                ),
                              ),
                            ),
                            Text('${group.count}', style: theme.textTheme.labelMedium?.copyWith(color: tk.ink(0.5))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
