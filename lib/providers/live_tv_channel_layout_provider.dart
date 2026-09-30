import 'dart:async';

import 'package:flutter/foundation.dart';

import '../mixins/disposable_change_notifier_mixin.dart';
import '../models/live_tv_channel_layout.dart';
import '../services/sensitive_prefs.dart';
import '../services/settings_service.dart';
import '../utils/app_logger.dart';

/// Owns the profile's Live TV arrangement — which groups and channels are
/// hidden and the order they appear in.
///
/// Lives in the profile-keyed provider subtree next to the IPTV sources: the
/// arrangement describes the combined channel list of every backend the
/// profile sees, so it belongs to the profile rather than to any one source.
class LiveTvChannelLayoutProvider extends ChangeNotifier with DisposableChangeNotifierMixin {
  LiveTvChannelLayoutProvider({required this.profileId}) {
    _loading = _load();
  }

  final String profileId;

  LiveTvChannelLayout _layout = LiveTvChannelLayout.empty;
  late final Future<void> _loading;
  bool _isLoaded = false;

  /// Completes once the stored arrangement has been read.
  Future<void> ensureLoaded() => _loading;

  bool get isLoaded => _isLoaded;

  LiveTvChannelLayout get layout => _layout;

  /// Falls back to an unscoped slot when there is no active profile, the same
  /// way the other per-profile stores do.
  NullableStringPref get _pref => profileId.trim().isEmpty
      ? const NullableStringPref(liveTvChannelLayoutBaseKey)
      : SettingsService.liveTvChannelLayoutForProfile(profileId);

  Future<void> _load() async {
    try {
      final settings = await SettingsService.getInstance();
      _layout = LiveTvChannelLayout.decode(settings.read(_pref));
    } catch (error, stackTrace) {
      appLogger.w('Live TV: could not read the channel arrangement', error: error, stackTrace: stackTrace);
      _layout = LiveTvChannelLayout.empty;
    }
    _isLoaded = true;
    safeNotifyListeners();
  }

  /// Commit [layout] in memory first so the list reorders under the user's
  /// finger, then persist.
  Future<void> _update(LiveTvChannelLayout layout) async {
    await ensureLoaded();
    _layout = layout;
    safeNotifyListeners();
    try {
      final settings = await SettingsService.getInstance();
      await settings.write(_pref, layout.isEmpty ? null : layout.encode());
    } catch (error, stackTrace) {
      appLogger.w('Live TV: could not save the channel arrangement', error: error, stackTrace: stackTrace);
    }
  }

  Future<void> setGroupHidden(String groupKey, bool hidden) => _update(_layout.withGroupHidden(groupKey, hidden));

  Future<void> setChannelHidden(String channelKey, bool hidden) =>
      _update(_layout.withChannelHidden(channelKey, hidden));

  /// Rename [groupKey], or hand it back its provider name with a null [name].
  Future<void> setGroupName(String groupKey, String? name) => _update(_layout.withGroupName(groupKey, name));

  Future<void> setGroupOrder(List<String> groupKeys) => _update(_layout.withGroupOrder(groupKeys));

  Future<void> setChannelOrder(String groupKey, List<String> channelKeys) =>
      _update(_layout.withChannelOrder(groupKey, channelKeys));

  /// Back to the order and visibility the backends provide.
  Future<void> reset() => _update(LiveTvChannelLayout.empty);
}
