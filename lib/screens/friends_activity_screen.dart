import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../focus/focusable_action_bar.dart';
import '../i18n/strings.g.dart';
import '../media/media_hub.dart';
import '../providers/discover_provider.dart' show friendsHubId;
import '../services/friends/friends_activity.dart';
import '../utils/dialogs.dart';
import 'hub_detail_screen.dart';

/// Erkunden → Freunde (Plebz): everything the Plex account's friends watched
/// lately, newest first, each poster wearing who and when.
///
/// The hub page every "Alle anzeigen" opens, so the grid, the describing
/// column under the redesign and the way a title opens are the ones the
/// viewer already knows. The friends narrow it from the action bar, behind
/// one word — a strip of names would not fit a large circle of friends.
class FriendsActivityScreen extends StatefulWidget {
  const FriendsActivityScreen({super.key});

  @override
  State<FriendsActivityScreen> createState() => _FriendsActivityScreenState();
}

class _FriendsActivityScreenState extends State<FriendsActivityScreen> {
  FriendsActivity get _friends => FriendsActivity.instance;

  /// The friend the page is narrowed to; null for everyone.
  String? _friendId;
  List<FriendTitle>? _shownFrom;
  String? _shownFor;
  MediaHub? _hub;

  @override
  void initState() {
    super.initState();
    _friends.addListener(_onFriendsChanged);
    unawaited(_friends.ensureFeed());
  }

  @override
  void dispose() {
    _friends.removeListener(_onFriendsChanged);
    super.dispose();
  }

  void _onFriendsChanged() {
    if (mounted) setState(() {});
  }

  /// The titles as a hub, rebuilt only when the feed or the choice changes:
  /// the page starts over on a new hub.
  MediaHub _hubFor(List<FriendTitle> titles) {
    final hub = _hub;
    if (hub != null && identical(titles, _shownFrom) && _shownFor == _friendId) return hub;
    _shownFrom = titles;
    _shownFor = _friendId;
    final friendId = _friendId;
    final items = [
      for (final title in titles)
        if (friendId == null)
          title.toMediaItem()
        else if (title.watches.where((watch) => watch.friend.id == friendId).firstOrNull case final watch?)
          title.toMediaItem(watch: watch),
    ];
    return _hub = MediaHub(
      id: '$friendsHubId:${friendId ?? 'all'}',
      title: t.friends.pageTitle,
      type: 'mixed',
      items: items,
      size: items.length,
    );
  }

  Future<void> _pickFriend() async {
    final friends = _friends.activeFriends;
    final picked = await showOptionPickerDialog<String>(
      context,
      title: t.friends.pageTitle,
      options: [
        (icon: Symbols.group_rounded, label: t.friends.all, value: ''),
        for (final friend in friends) (icon: Symbols.person_rounded, label: friend.name, value: friend.id),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() => _friendId = picked.isEmpty ? null : picked);
  }

  String get _friendLabel {
    final id = _friendId;
    if (id == null) return t.friends.all;
    return _friends.activeFriends.where((friend) => friend.id == id).firstOrNull?.name ?? t.friends.all;
  }

  @override
  Widget build(BuildContext context) {
    final hub = _hubFor(_friends.titles);
    return HubDetailScreen(
      key: ObjectKey(hub),
      hub: hub,
      hostAppBarActions: [
        FocusableAction(
          icon: Symbols.group_rounded,
          iconFill: _friendId == null ? 0 : 1,
          tooltip: _friendLabel,
          onPressed: _pickFriend,
        ),
      ],
    );
  }
}
