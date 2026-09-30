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

  @visibleForTesting
  void resetForTest() {
    _channelKey = null;
    _group = null;
    _groupKnown = false;
  }
}
