import 'dart:async';

import 'package:flutter/material.dart';

import '../i18n/strings.g.dart';
import '../services/friends/friends_activity.dart';
import 'friend_watch_badge.dart';

/// Asks which friends watched a title and builds from the answer (Plebz).
///
/// [resolveId] names the title in Discover's ids; a title it cannot name, a
/// profile without friends, or the switch turned off all build from an empty
/// list — the surfaces then draw nothing at all, not an empty line.
class FriendsWatchedBuilder extends StatefulWidget {
  const FriendsWatchedBuilder({super.key, required this.titleKey, required this.resolveId, required this.builder});

  /// Changes when the page shows another title.
  final Object titleKey;
  final Future<String?> Function() resolveId;
  final Widget Function(BuildContext context, List<FriendWatch> watches) builder;

  @override
  State<FriendsWatchedBuilder> createState() => _FriendsWatchedBuilderState();
}

class _FriendsWatchedBuilderState extends State<FriendsWatchedBuilder> {
  List<FriendWatch> _watches = const [];
  int _request = 0;
  bool _wasEnabled = false;

  FriendsActivity get _friends => FriendsActivity.instance;

  @override
  void initState() {
    super.initState();
    _wasEnabled = _friends.isEnabled;
    _friends.addListener(_onFriendsChanged);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(FriendsWatchedBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.titleKey != widget.titleKey) {
      _watches = const [];
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _friends.removeListener(_onFriendsChanged);
    super.dispose();
  }

  void _onFriendsChanged() {
    final enabled = _friends.isEnabled;
    if (enabled == _wasEnabled) return;
    _wasEnabled = enabled;
    if (!enabled) {
      setState(() => _watches = const []);
    } else {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final request = ++_request;
    if (!_friends.isEnabled) return;
    final id = await widget.resolveId();
    if (id == null || !mounted || request != _request) return;
    final watches = await _friends.watchersOf(id);
    if (!mounted || request != _request) return;
    setState(() => _watches = watches);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _watches);
}

/// The friends as a glance: up to three pictures overlapping, then their
/// names — "Anna, Ben, Jonas +2".
class FriendsWatchedSummary extends StatelessWidget {
  const FriendsWatchedSummary({super.key, required this.watches, required this.style, this.avatarSize});

  final List<FriendWatch> watches;
  final TextStyle style;
  final double? avatarSize;

  static const shownNames = 3;

  /// "Anna, Ben, Jonas +2".
  static String namesOf(List<FriendWatch> watches) {
    final names = watches.take(shownNames).map((watch) => watch.friend.name).join(', ');
    final rest = watches.length - shownNames;
    return rest > 0 ? '$names ${t.friends.more(count: rest)}' : names;
  }

  @override
  Widget build(BuildContext context) {
    if (watches.isEmpty) return const SizedBox.shrink();
    final size = avatarSize ?? (style.fontSize ?? 14) * 1.6;
    final overlap = size * 0.3;
    final faces = watches.take(shownNames).toList();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size + (faces.length - 1) * (size - overlap),
          height: size,
          child: Stack(
            children: [
              for (var i = faces.length - 1; i >= 0; i--)
                Positioned(
                  left: i * (size - overlap),
                  child: FriendAvatar(
                    name: faces[i].friend.name,
                    initial: faces[i].friend.initial,
                    url: faces[i].friend.avatarUrl,
                    size: size,
                  ),
                ),
            ],
          ),
        ),
        SizedBox(width: size * 0.4),
        Flexible(
          child: Text(namesOf(watches), maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
        ),
      ],
    );
  }
}
