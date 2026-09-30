import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../focus/dpad_reorder_mixin.dart';
import '../../focus/input_mode_tracker.dart';
import '../../i18n/strings.g.dart';
import '../../models/live_tv_channel_layout.dart';
import '../../models/livetv_channel.dart';
import '../../providers/live_tv_channel_layout_provider.dart';
import '../../services/settings_service.dart';
import '../../utils/dialogs.dart';
import '../../utils/live_tv_group_label.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/bottom_sheet_header.dart';
import '../../widgets/overlay_sheet.dart';

/// One group as the management list shows it.
typedef ChannelGroupEntry = ({String key, String label, int count, int hiddenCount});

/// Whether group names here read the way the group bar shows them.
bool _hideGroupCountryPrefix() =>
    SettingsService.instanceOrNull?.read(SettingsService.iptvHideGroupCountryPrefix) ?? false;

/// Open the channel arrangement UI: groups first, each opening its channels.
///
/// [channels] must be the **unfiltered** list — a hidden group cannot be
/// brought back from a list it was already removed from.
Future<void> showChannelManagementSheet(BuildContext context, {required List<LiveTvChannel> channels}) {
  final layoutProvider = context.read<LiveTvChannelLayoutProvider>();
  final groups = liveTvChannelGroupEntries(channels, layoutProvider.layout);

  // A single group is no arrangement worth showing — go straight to its
  // channels. That is what the Plex and Jellyfin lineups look like.
  final Widget Function({required bool isDialog}) build = groups.length > 1
      ? ({required bool isDialog}) => _GroupManagementList(isDialog: isDialog, channels: channels)
      : ({required bool isDialog}) =>
            _ChannelManagementList(isDialog: isDialog, channels: channels, groupKey: groups.singleOrNull?.key ?? '');

  if (PlatformDetector.isTV()) {
    return showScopedDialog<void>(context: context, builder: (context) => build(isDialog: true));
  }
  return OverlaySheetController.showAdaptive<void>(
    context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => build(isDialog: false),
  );
}

/// The groups [channels] fall into, in the arranged order, each with how many
/// channels it holds and how many of those are hidden.
List<ChannelGroupEntry> liveTvChannelGroupEntries(List<LiveTvChannel> channels, LiveTvChannelLayout layout) {
  final counts = <String, int>{};
  final hiddenCounts = <String, int>{};
  for (final channel in channels) {
    final key = liveTvLayoutGroupKey(channel);
    counts[key] = (counts[key] ?? 0) + 1;
    if (layout.isChannelHidden(liveTvLayoutChannelKey(channel))) {
      hiddenCounts[key] = (hiddenCounts[key] ?? 0) + 1;
    }
  }

  final ranks = <String, int>{for (var i = 0; i < layout.groupOrder.length; i++) layout.groupOrder[i]: i};
  final keys = counts.keys.toList();
  final appearance = <String, int>{for (var i = 0; i < keys.length; i++) keys[i]: i};
  keys.sort((a, b) {
    final rankA = ranks[a] ?? (ranks.length + appearance[a]!);
    final rankB = ranks[b] ?? (ranks.length + appearance[b]!);
    return rankA.compareTo(rankB);
  });

  return [
    for (final key in keys)
      (
        key: key,
        label: key.isEmpty
            ? t.liveTv.ungrouped
            : liveTvGroupLabel(key, stripCountryPrefix: _hideGroupCountryPrefix(), customName: layout.groupNames[key]),
        count: counts[key] ?? 0,
        hiddenCount: hiddenCounts[key] ?? 0,
      ),
  ];
}

/// The channels of one group, in the arranged order.
List<LiveTvChannel> liveTvChannelsInGroup(List<LiveTvChannel> channels, String groupKey, LiveTvChannelLayout layout) {
  final inGroup = [
    for (final channel in channels)
      if (liveTvLayoutGroupKey(channel) == groupKey) channel,
  ];
  final order = layout.channelOrder[groupKey] ?? const <String>[];
  if (order.isEmpty) return inGroup;

  final ranks = <String, int>{for (var i = 0; i < order.length; i++) order[i]: i};
  final ranked = [
    for (var i = 0; i < inGroup.length; i++)
      (channel: inGroup[i], rank: ranks[liveTvLayoutChannelKey(inGroup[i])] ?? (order.length + i)),
  ]..sort((a, b) => a.rank.compareTo(b.rank));
  return [for (final entry in ranked) entry.channel];
}

/// Shared chrome: the TV dialog and the bottom sheet differ only in framing.
class _ManagementScaffold extends StatelessWidget {
  const _ManagementScaffold({
    required this.isDialog,
    required this.title,
    required this.icon,
    required this.listFocusNode,
    required this.onKeyEvent,
    required this.child,
  });

  final bool isDialog;
  final String title;
  final IconData icon;
  final FocusNode listFocusNode;
  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;
  final Widget child;

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
              title: Row(
                children: [
                  AppIcon(icon, fill: 1),
                  const SizedBox(width: 12),
                  Expanded(child: Text(title)),
                ],
              ),
              actions: [
                IconButton(
                  icon: const AppIcon(Symbols.close_rounded, fill: 1),
                  onPressed: () => Navigator.pop(context),
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
        BottomSheetHeader(title: title, icon: icon),
        Flexible(child: body),
      ],
    );
  }
}

class _GroupManagementList extends StatefulWidget {
  const _GroupManagementList({required this.isDialog, required this.channels});

  final bool isDialog;
  final List<LiveTvChannel> channels;

  @override
  State<_GroupManagementList> createState() => _GroupManagementListState();
}

class _GroupManagementListState extends State<_GroupManagementList>
    with DpadReorderListMixin<ChannelGroupEntry, _GroupManagementList> {
  final _listFocusNode = FocusNode(debugLabel: 'channel_group_management');
  final _scrollController = ScrollController();
  late List<ChannelGroupEntry> _groups;

  @override
  List<ChannelGroupEntry> get reorderItems => _groups;

  @override
  set reorderItems(List<ChannelGroupEntry> value) => _groups = value;

  @override
  int get lastReorderColumn => 2;

  @override
  ScrollController? get reorderScrollController => _scrollController;

  @override
  void onReorderMoveConfirmed() => _persistOrder();

  @override
  void onReorderColumnActivated(int column, int index) {
    if (column == 1) {
      _toggleHidden(_groups[index]);
    } else if (column == 2) {
      _openChannels(_groups[index]);
    }
  }

  @override
  void initState() {
    super.initState();
    _groups = liveTvChannelGroupEntries(widget.channels, context.read<LiveTvChannelLayoutProvider>().layout);
  }

  @override
  void dispose() {
    _listFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _persistOrder() {
    unawaited(context.read<LiveTvChannelLayoutProvider>().setGroupOrder([for (final group in _groups) group.key]));
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      final group = _groups.removeAt(oldIndex);
      _groups.insert(newIndex, group);
    });
    _persistOrder();
  }

  void _toggleHidden(ChannelGroupEntry group) {
    final provider = context.read<LiveTvChannelLayoutProvider>();
    unawaited(provider.setGroupHidden(group.key, !provider.layout.isGroupHidden(group.key)));
  }

  void _openChannels(ChannelGroupEntry group) {
    final channels = widget.channels;
    if (widget.isDialog) {
      unawaited(
        showScopedDialog<void>(
          context: context,
          builder: (context) => _ChannelManagementList(isDialog: true, channels: channels, groupKey: group.key),
        ),
      );
      return;
    }
    OverlaySheetController.pushAdaptive<void>(
      context,
      builder: (context) => _ChannelManagementList(isDialog: false, channels: channels, groupKey: group.key),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<LiveTvChannelLayoutProvider>().layout;
    final isKeyboardMode = InputModeTracker.isKeyboardMode(context);

    return _ManagementScaffold(
      isDialog: widget.isDialog,
      title: t.liveTv.manageChannels,
      icon: Symbols.tune_rounded,
      listFocusNode: _listFocusNode,
      onKeyEvent: handleReorderKeyEvent,
      child: ReorderableListView.builder(
        scrollController: _scrollController,
        shrinkWrap: !widget.isDialog,
        onReorderItem: _reorder,
        itemCount: _groups.length,
        padding: const EdgeInsets.symmetric(vertical: 8),
        buildDefaultDragHandles: false,
        itemBuilder: (context, index) {
          final group = _groups[index];
          final isFocused = isKeyboardMode && index == focusedIndex;
          return _ManagementTile(
            key: ValueKey(group.key),
            index: index,
            title: group.label,
            subtitle: group.hiddenCount == 0
                ? t.liveTv.channelCount(count: group.count)
                : t.liveTv.channelCountWithHidden(count: group.count, hidden: group.hiddenCount),
            leadingIcon: group.key.isEmpty ? Symbols.live_tv_rounded : Symbols.folder_rounded,
            isHidden: layout.isGroupHidden(group.key),
            isFocused: isFocused,
            isMoving: index == movingIndex,
            focusedColumn: isFocused ? focusedColumn : null,
            onToggleHidden: () => _toggleHidden(group),
            onOpen: () => _openChannels(group),
          );
        },
      ),
    );
  }
}

class _ChannelManagementList extends StatefulWidget {
  const _ChannelManagementList({required this.isDialog, required this.channels, required this.groupKey});

  final bool isDialog;
  final List<LiveTvChannel> channels;
  final String groupKey;

  @override
  State<_ChannelManagementList> createState() => _ChannelManagementListState();
}

class _ChannelManagementListState extends State<_ChannelManagementList>
    with DpadReorderListMixin<LiveTvChannel, _ChannelManagementList> {
  final _listFocusNode = FocusNode(debugLabel: 'channel_management');
  final _scrollController = ScrollController();
  late List<LiveTvChannel> _channels;

  @override
  List<LiveTvChannel> get reorderItems => _channels;

  @override
  set reorderItems(List<LiveTvChannel> value) => _channels = value;

  @override
  int get lastReorderColumn => 1;

  @override
  ScrollController? get reorderScrollController => _scrollController;

  @override
  void onReorderMoveConfirmed() => _persistOrder();

  @override
  void onReorderColumnActivated(int column, int index) {
    if (column == 1) _toggleHidden(_channels[index]);
  }

  @override
  void initState() {
    super.initState();
    _channels = liveTvChannelsInGroup(
      widget.channels,
      widget.groupKey,
      context.read<LiveTvChannelLayoutProvider>().layout,
    );
  }

  @override
  void dispose() {
    _listFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _persistOrder() {
    unawaited(
      context.read<LiveTvChannelLayoutProvider>().setChannelOrder(widget.groupKey, [
        for (final channel in _channels) liveTvLayoutChannelKey(channel),
      ]),
    );
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      final channel = _channels.removeAt(oldIndex);
      _channels.insert(newIndex, channel);
    });
    _persistOrder();
  }

  void _toggleHidden(LiveTvChannel channel) {
    final provider = context.read<LiveTvChannelLayoutProvider>();
    final key = liveTvLayoutChannelKey(channel);
    unawaited(provider.setChannelHidden(key, !provider.layout.isChannelHidden(key)));
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<LiveTvChannelLayoutProvider>().layout;
    final isKeyboardMode = InputModeTracker.isKeyboardMode(context);

    return _ManagementScaffold(
      isDialog: widget.isDialog,
      title: widget.groupKey.isEmpty
          ? t.liveTv.manageChannels
          : liveTvGroupLabel(
              widget.groupKey,
              stripCountryPrefix: _hideGroupCountryPrefix(),
              customName: layout.groupNames[widget.groupKey],
            ),
      icon: Symbols.tune_rounded,
      listFocusNode: _listFocusNode,
      onKeyEvent: handleReorderKeyEvent,
      child: ReorderableListView.builder(
        scrollController: _scrollController,
        shrinkWrap: !widget.isDialog,
        onReorderItem: _reorder,
        itemCount: _channels.length,
        padding: const EdgeInsets.symmetric(vertical: 8),
        buildDefaultDragHandles: false,
        itemBuilder: (context, index) {
          final channel = _channels[index];
          final isFocused = isKeyboardMode && index == focusedIndex;
          return _ManagementTile(
            key: ValueKey(liveTvLayoutChannelKey(channel)),
            index: index,
            // The name the viewer gave it, as everywhere else; the sheet lists
            // hidden channels too, so it reads the arrangement itself.
            title: layout.channelNames[liveTvLayoutChannelKey(channel)] ?? channel.displayName,
            subtitle: channel.number,
            leadingIcon: Symbols.live_tv_rounded,
            isHidden: layout.isChannelHidden(liveTvLayoutChannelKey(channel)),
            isFocused: isFocused,
            isMoving: index == movingIndex,
            focusedColumn: isFocused ? focusedColumn : null,
            onToggleHidden: () => _toggleHidden(channel),
          );
        },
      ),
    );
  }
}

/// One reorderable row: drag handle, label, a visibility toggle and — for a
/// group — a way into its channels.
class _ManagementTile extends StatelessWidget {
  const _ManagementTile({
    super.key,
    required this.index,
    required this.title,
    required this.subtitle,
    required this.leadingIcon,
    required this.isHidden,
    required this.isFocused,
    required this.isMoving,
    required this.focusedColumn,
    required this.onToggleHidden,
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
  final VoidCallback onToggleHidden;
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
              ReorderableDragStartListener(
                index: index,
                child: AppIcon(
                  isMoving ? Symbols.swap_vert_rounded : Symbols.drag_indicator_rounded,
                  fill: 1,
                  color: isMoving ? colorScheme.primary : IconTheme.of(context).color?.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(width: 8),
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
                  tooltip: isHidden ? t.liveTv.showInGuide : t.liveTv.hideFromGuide,
                  onPressed: onToggleHidden,
                ),
              ),
              if (onOpen != null)
                DpadReorderButtonFocus(
                  isFocused: isFocused && focusedColumn == 2,
                  child: IconButton(
                    icon: const AppIcon(Symbols.chevron_right_rounded, fill: 1),
                    tooltip: t.liveTv.manageChannels,
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
