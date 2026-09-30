import 'dart:convert';

import 'livetv_channel.dart';
import '../utils/live_tv_matching.dart';

/// The key a channel is filed under in a [LiveTvChannelLayout]. Scoped by
/// server/DVR like everywhere else in Live TV, so two backends carrying the
/// same channel key stay apart.
String liveTvLayoutChannelKey(LiveTvChannel channel) => liveTvChannelScopeKey(channel);

/// The group a channel belongs to — a playlist's `group-title` or an Xtream
/// category. Channels without one share the empty group, which is how the
/// Plex and Jellyfin lineups look.
String liveTvLayoutGroupKey(LiveTvChannel channel) => liveTvNonEmpty(channel.lineup) ?? '';

/// How the user arranged the Live TV channel list: which groups and channels
/// are hidden, and the order they appear in.
///
/// Providers hand out hundreds of groups and thousands of channels in an
/// order nobody chose, so the list is only usable once it can be cut down and
/// rearranged. Deliberately stored per profile rather than per source: the
/// guide shows every backend at once, and the arrangement is a property of
/// that combined list.
class LiveTvChannelLayout {
  const LiveTvChannelLayout({
    this.groupOrder = const [],
    this.hiddenGroups = const {},
    this.channelOrder = const {},
    this.hiddenChannels = const {},
    this.groupNames = const {},
    this.channelNames = const {},
  });

  /// Group keys in the order the user put them. Groups missing from this list
  /// keep their first-appearance order behind the arranged ones.
  final List<String> groupOrder;

  final Set<String> hiddenGroups;

  /// Group key → its channels in the user's order. Kept per group because
  /// that is how they are edited: nobody reorders 5,000 channels at once.
  final Map<String, List<String>> channelOrder;

  final Set<String> hiddenChannels;

  /// Group key → the name the user gave it. Providers write group names for
  /// their own filing ("DE • Sport • Bundesliga • RAW"), and a viewer who has
  /// to read that row every time is entitled to call it what they call it.
  /// The key stays the provider's, so the group survives being renamed.
  final Map<String, String> groupNames;

  /// Channel key → the name the user gave it. A playlist names its channels
  /// for its own filing too ("DE: Das Erste HD RAW"); the viewer's name is
  /// shown everywhere the channel is, while the provider's stays what anything
  /// recognising the channel reads (see [LiveTvChannel.sourceName]).
  final Map<String, String> channelNames;

  static const empty = LiveTvChannelLayout();

  /// True when nothing was arranged, so the loaded order stands untouched.
  bool get isEmpty =>
      groupOrder.isEmpty &&
      hiddenGroups.isEmpty &&
      channelOrder.isEmpty &&
      hiddenChannels.isEmpty &&
      groupNames.isEmpty &&
      channelNames.isEmpty;

  bool isGroupHidden(String groupKey) => hiddenGroups.contains(groupKey);

  bool isChannelHidden(String channelKey) => hiddenChannels.contains(channelKey);

  /// Whether [channel] is left out — on its own, or with its group.
  bool hides(LiveTvChannel channel) =>
      isGroupHidden(liveTvLayoutGroupKey(channel)) || isChannelHidden(liveTvLayoutChannelKey(channel));

  LiveTvChannelLayout copyWith({
    List<String>? groupOrder,
    Set<String>? hiddenGroups,
    Map<String, List<String>>? channelOrder,
    Set<String>? hiddenChannels,
    Map<String, String>? groupNames,
    Map<String, String>? channelNames,
  }) => LiveTvChannelLayout(
    groupOrder: groupOrder ?? this.groupOrder,
    hiddenGroups: hiddenGroups ?? this.hiddenGroups,
    channelOrder: channelOrder ?? this.channelOrder,
    hiddenChannels: hiddenChannels ?? this.hiddenChannels,
    groupNames: groupNames ?? this.groupNames,
    channelNames: channelNames ?? this.channelNames,
  );

  /// [hidden] toggled for [groupKey].
  LiveTvChannelLayout withGroupHidden(String groupKey, bool hidden) => copyWith(
    hiddenGroups: {
      for (final key in hiddenGroups)
        if (key != groupKey) key,
      if (hidden) groupKey,
    },
  );

  LiveTvChannelLayout withChannelHidden(String channelKey, bool hidden) => copyWith(
    hiddenChannels: {
      for (final key in hiddenChannels)
        if (key != channelKey) key,
      if (hidden) channelKey,
    },
  );

  /// [groupKey] renamed to [name], or back to the provider's own name when
  /// [name] is null or blank.
  LiveTvChannelLayout withGroupName(String groupKey, String? name) {
    final trimmed = name?.trim();
    return copyWith(
      groupNames: {
        for (final entry in groupNames.entries)
          if (entry.key != groupKey) entry.key: entry.value,
        if (trimmed != null && trimmed.isNotEmpty) groupKey: trimmed,
      },
    );
  }

  /// [channelKey] renamed to [name], or back to the provider's own name when
  /// [name] is null or blank.
  LiveTvChannelLayout withChannelName(String channelKey, String? name) {
    final trimmed = name?.trim();
    return copyWith(
      channelNames: {
        for (final entry in channelNames.entries)
          if (entry.key != channelKey) entry.key: entry.value,
        if (trimmed != null && trimmed.isNotEmpty) channelKey: trimmed,
      },
    );
  }

  LiveTvChannelLayout withGroupOrder(List<String> order) => copyWith(groupOrder: List.unmodifiable(order));

  LiveTvChannelLayout withChannelOrder(String groupKey, List<String> order) =>
      copyWith(channelOrder: {...channelOrder, groupKey: List.unmodifiable(order)});

  Map<String, Object?> toJson() => {
    if (groupOrder.isNotEmpty) 'groupOrder': groupOrder,
    if (hiddenGroups.isNotEmpty) 'hiddenGroups': hiddenGroups.toList(),
    if (channelOrder.isNotEmpty) 'channelOrder': channelOrder,
    if (hiddenChannels.isNotEmpty) 'hiddenChannels': hiddenChannels.toList(),
    if (groupNames.isNotEmpty) 'groupNames': groupNames,
    if (channelNames.isNotEmpty) 'channelNames': channelNames,
  };

  String encode() => jsonEncode(toJson());

  /// Tolerant decode: a stored arrangement that cannot be read costs the user
  /// their layout, not their channels, so anything unexpected falls back to
  /// [empty] rather than throwing.
  static LiveTvChannelLayout decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return empty;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return empty;

      List<String> strings(Object? value) => value is List ? [for (final entry in value) ?_string(entry)] : const [];

      final channelOrder = <String, List<String>>{};
      final storedChannelOrder = decoded['channelOrder'];
      if (storedChannelOrder is Map) {
        for (final entry in storedChannelOrder.entries) {
          final groupKey = _string(entry.key);
          if (groupKey == null) continue;
          final order = strings(entry.value);
          if (order.isNotEmpty) channelOrder[groupKey] = order;
        }
      }

      Map<String, String> names(Object? stored) => {
        if (stored is Map)
          for (final entry in stored.entries)
            if (_string(entry.key) case final key?)
              if (_string(entry.value) case final name? when name.isNotEmpty) key: name,
      };

      return LiveTvChannelLayout(
        groupOrder: strings(decoded['groupOrder']),
        hiddenGroups: strings(decoded['hiddenGroups']).toSet(),
        channelOrder: channelOrder,
        hiddenChannels: strings(decoded['hiddenChannels']).toSet(),
        groupNames: names(decoded['groupNames']),
        channelNames: names(decoded['channelNames']),
      );
    } on FormatException {
      return empty;
    }
  }
}

String? _string(Object? value) => value is String ? value : null;

/// Apply [layout] to [channels]: drop what is hidden, name what the user
/// renamed, then order what is left.
///
/// Ordering is by group first and channel second, but only where the user
/// actually arranged something — an untouched layout returns the list in the
/// order it arrived, which is the channel numbering the backends provide.
List<LiveTvChannel> applyLiveTvChannelLayout(List<LiveTvChannel> channels, LiveTvChannelLayout layout) {
  if (layout.isEmpty) return channels;

  final visible = [
    for (final channel in channels)
      if (!layout.hides(channel))
        switch (layout.channelNames[liveTvLayoutChannelKey(channel)]) {
          final name? => channel.copyWith(nameOverride: name),
          null => channel,
        },
  ];
  if (layout.groupOrder.isEmpty && layout.channelOrder.isEmpty) return visible;

  final groupRanks = <String, int>{for (var i = 0; i < layout.groupOrder.length; i++) layout.groupOrder[i]: i};
  final firstAppearance = <String, int>{};
  for (final channel in visible) {
    firstAppearance.putIfAbsent(liveTvLayoutGroupKey(channel), () => firstAppearance.length);
  }

  int groupRank(String groupKey) =>
      groupRanks[groupKey] ?? (layout.groupOrder.length + (firstAppearance[groupKey] ?? 0));

  final ranked = <({LiveTvChannel channel, int group, int channelRank})>[];
  for (var index = 0; index < visible.length; index++) {
    final channel = visible[index];
    final groupKey = liveTvLayoutGroupKey(channel);
    final order = layout.channelOrder[groupKey] ?? const <String>[];
    final position = order.indexOf(liveTvLayoutChannelKey(channel));
    ranked.add((
      channel: channel,
      group: groupRank(groupKey),
      // Channels the user never moved keep their loaded order behind the
      // arranged ones instead of jumping to the front.
      channelRank: position >= 0 ? position : order.length + index,
    ));
  }

  ranked.sort((a, b) {
    final byGroup = a.group.compareTo(b.group);
    return byGroup != 0 ? byGroup : a.channelRank.compareTo(b.channelRank);
  });
  return [for (final entry in ranked) entry.channel];
}
