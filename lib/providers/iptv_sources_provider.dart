import 'dart:async';

import 'package:flutter/foundation.dart';

import '../mixins/disposable_change_notifier_mixin.dart';
import '../models/livetv_channel.dart';
import '../services/iptv/iptv_disk_cache.dart';
import 'live_tv_channel_layout_provider.dart';
import '../services/iptv/iptv_live_tv_source.dart';
import '../services/iptv/iptv_source.dart';
import '../services/sensitive_prefs.dart';
import '../services/settings_service.dart';
import '../utils/app_logger.dart';
import '../utils/log_redaction_manager.dart';

/// Owns the profile's IPTV sources and the live objects built from them.
///
/// Lives in the profile-keyed provider subtree: sources are per profile, the
/// same way tracker accounts and watch state are.
///
/// The [IptvLiveTvSource] instances are held here rather than rebuilt per use
/// because they cache the playlist and guide — a fresh instance per screen
/// visit would re-download a multi-megabyte guide every time.
class IptvSourcesProvider extends ChangeNotifier with DisposableChangeNotifierMixin {
  IptvSourcesProvider({
    required this.profileId,
    IptvLiveTvSource Function(IptvSource source)? buildSource,
    LiveTvChannelLayoutProvider? channelLayout,
  }) {
    _buildSource =
        buildSource ?? ((source) => _defaultSource(source, channelLayout, onLogosLearned: _bumpEpgLogoRevision));
    _loading = _load();
  }

  final String profileId;
  late final IptvLiveTvSource Function(IptvSource source) _buildSource;

  /// Bumped whenever a source's guide gave channels logos their playlist
  /// entries lack. The guide arrives after the channels are on screen, so
  /// whoever shows them listens and patches its list — see [withEpgLogo].
  final ValueNotifier<int> _epgLogoRevision = ValueNotifier(0);
  ValueListenable<int> get epgLogoRevision => _epgLogoRevision;

  void _bumpEpgLogoRevision() {
    if (!isDisposed) _epgLogoRevision.value++;
  }

  /// [channel] with the logo its source's guide gives it, where it has none.
  LiveTvChannel withEpgLogo(LiveTvChannel channel) {
    for (final source in _liveTvById.values) {
      final withLogo = source.withEpgLogo(channel);
      if (!identical(withLogo, channel)) return withLogo;
    }
    return channel;
  }

  /// The real thing: kept on disk, and re-read no more often than the user
  /// asked for. The interval is read per call, so changing it takes effect
  /// without rebuilding anything. The guide is read only for the channels the
  /// profile's arrangement ([channelLayout]) leaves showing.
  static IptvLiveTvSource _defaultSource(
    IptvSource source,
    LiveTvChannelLayoutProvider? channelLayout, {
    void Function()? onLogosLearned,
  }) => IptvLiveTvSource(
    source,
    diskCache: IptvDiskCache(),
    diskCacheMaxAge: () =>
        Duration(days: SettingsService.instanceOrNull?.read(SettingsService.iptvRefreshIntervalDays) ?? 1),
    mergeDuplicates: () => SettingsService.instanceOrNull?.read(SettingsService.iptvMergeDuplicateChannels) ?? false,
    channelLayout: channelLayout == null
        ? null
        : () async {
            await channelLayout.ensureLoaded();
            return channelLayout.layout;
          },
    onLogosLearned: onLogosLearned,
  );

  List<IptvSource> _sources = const [];
  final Map<String, IptvLiveTvSource> _liveTvById = {};
  late final Future<void> _loading;
  bool _isLoaded = false;

  /// Completes once the stored sources have been read.
  Future<void> ensureLoaded() => _loading;

  bool get isLoaded => _isLoaded;

  List<IptvSource> get sources => List.unmodifiable(_sources);

  /// Sources that can actually be queried, as Live TV backends.
  List<IptvLiveTvSource> get liveTvSources => [
    for (final source in _sources)
      if (source.isComplete) _liveTvFor(source),
  ];

  IptvLiveTvSource? liveTvForSourceId(String sourceId) {
    final source = _sources.where((candidate) => candidate.id == sourceId).firstOrNull;
    if (source == null || !source.isComplete) return null;
    return _liveTvFor(source);
  }

  IptvLiveTvSource _liveTvFor(IptvSource source) => _liveTvById.putIfAbsent(source.id, () => _buildSource(source));

  /// Falls back to an unscoped slot when there is no active profile, the same
  /// way the other per-profile stores do — a session without a profile still
  /// has to read and write something.
  NullableStringPref get _pref => profileId.trim().isEmpty
      ? const NullableStringPref(iptvSourcesBaseKey)
      : SettingsService.iptvSourcesForProfile(profileId);

  Future<void> _load() async {
    try {
      final settings = await SettingsService.getInstance();
      _sources = IptvSource.decodeList(settings.read(_pref));
    } catch (error, stackTrace) {
      appLogger.w('IPTV: could not read the configured sources', error: error, stackTrace: stackTrace);
      _sources = const [];
    }
    _registerForRedaction();
    _isLoaded = true;
    safeNotifyListeners();
  }

  /// Keep the panel credentials out of the log.
  ///
  /// An Xtream panel carries the username and the password **in the path**
  /// (`/live/<user>/<pass>/…`), so every stream address that reaches a log
  /// line carries them too — and a log is the first thing a user copies into
  /// a chat when something misbehaves. Registered here because this is where
  /// the sources are known, and the redaction is global from then on.
  void _registerForRedaction() {
    for (final source in _sources) {
      LogRedactionManager.registerCustomValue(source.username);
      LogRedactionManager.registerCustomValue(source.password);
    }
  }

  Future<void> _persist() async {
    _registerForRedaction();
    try {
      final settings = await SettingsService.getInstance();
      await settings.write(_pref, IptvSource.encodeList(_sources));
    } catch (error, stackTrace) {
      appLogger.w('IPTV: could not save the configured sources', error: error, stackTrace: stackTrace);
    }
  }

  /// Add [source], or replace the entry with the same id.
  Future<void> save(IptvSource source) async {
    await ensureLoaded();
    final index = _sources.indexWhere((candidate) => candidate.id == source.id);
    _sources = index == -1
        ? [..._sources, source]
        : [for (var i = 0; i < _sources.length; i++) i == index ? source : _sources[i]];
    // Its playlist, credentials or guide may have changed, so the cached
    // instance no longer describes it.
    _liveTvById.remove(source.id)?.close();
    safeNotifyListeners();
    await _persist();
  }

  Future<void> remove(String sourceId) async {
    await ensureLoaded();
    _sources = [
      for (final source in _sources)
        if (source.id != sourceId) source,
    ];
    _liveTvById.remove(sourceId)?.close();
    safeNotifyListeners();
    await _persist();
  }

  /// Drop cached playlists and guides so the next read hits the network.
  void refreshAll() {
    for (final source in _liveTvById.values) {
      source.invalidate();
    }
    safeNotifyListeners();
  }

  @override
  void dispose() {
    for (final source in _liveTvById.values) {
      source.close();
    }
    _liveTvById.clear();
    _epgLogoRevision.dispose();
    super.dispose();
  }
}
