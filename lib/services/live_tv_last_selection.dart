import 'package:flutter/foundation.dart';

/// Where the viewer was when they last left the live player.
///
/// The guide is a screen the player is launched from and returned to, and
/// coming back to the group and channel it was opened with — rather than the
/// one being watched a second ago — makes the return feel like a different
/// place than the one just left. The player writes here as it zaps; the guide
/// reads it when it comes back to the foreground.
///
/// Deliberately not persisted: this is about one journey away from the guide
/// and back, not about what was on last week.
class LiveTvLastSelection extends ChangeNotifier {
  LiveTvLastSelection._();

  static final LiveTvLastSelection instance = LiveTvLastSelection._();

  String? _channelKey;
  String? _group;
  bool _groupKnown = false;

  /// The channel that was playing, by its scope key.
  String? get channelKey => _channelKey;

  /// The group the player was confined to, null for "all channels".
  String? get group => _group;

  /// Whether anything was recorded at all. Distinguishes "no group" — which
  /// is a real answer — from "never been in the player".
  bool get hasSelection => _channelKey != null || _groupKnown;

  void record({required String? channelKey, required String? group}) {
    if (_channelKey == channelKey && _group == group && _groupKnown) return;
    _channelKey = channelKey;
    _group = group;
    _groupKnown = true;
    notifyListeners();
  }

  bool _handedOff = false;

  /// A channel started from somewhere other than the guide — the home
  /// screen's "Jetzt live" — with the guide switched to behind the player, so
  /// leaving the player lands in the guide on that channel's group.
  ///
  /// Recorded like a zap, and marked: the guide may only be built in this
  /// very moment, after the notification it would have listened for.
  void handOff({required String? channelKey, required String? group}) {
    _handedOff = true;
    // Notified even when nothing changed: a guide already on screen has to
    // move to it all the same.
    _channelKey = channelKey;
    _group = group;
    _groupKnown = true;
    notifyListeners();
  }

  /// Whether a [handOff] is waiting for a guide to take it; clears it.
  bool takeHandOff() {
    final handedOff = _handedOff;
    _handedOff = false;
    return handedOff;
  }

  @visibleForTesting
  void resetForTest() {
    _channelKey = null;
    _group = null;
    _groupKnown = false;
    _handedOff = false;
  }
}
