import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../mixins/disposable_change_notifier_mixin.dart';
import '../models/livetv_channel.dart';
import '../services/credential_fields.dart';
import '../services/iptv/iptv_local_files.dart';
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

  /// The sources' credentials ([iptvSealedFields]) are sealed with
  /// `CredentialVault` at rest. Sources stored before that are sealed on this
  /// load; a field the vault can no longer open is dropped, and that source
  /// asks for it again.
  Future<void> _load() async {
    var reseal = false;
    try {
      final settings = await SettingsService.getInstance();
      final raw = settings.read(_pref);
      final stored = raw == null || raw.trim().isEmpty ? const <Object?>[] : jsonDecode(raw);
      final opened = <Map<String, Object?>>[];
      for (final entry in stored is List ? stored : const <Object?>[]) {
        if (entry is! Map) continue;
        final result = await CredentialFields.reveal(Map<String, Object?>.from(entry), iptvSealedFields);
        reseal = reseal || result.hadPlaintext;
        if (result.lost > 0) appLogger.w('IPTV: a source lost credentials the vault could not open');
        opened.add(result.json);
      }
      _sources = [for (final json in opened) ?IptvSource.fromJson(json)];
    } catch (error, stackTrace) {
      appLogger.w('IPTV: could not read the configured sources', error: error, stackTrace: stackTrace);
      _sources = const [];
      reseal = false;
    }
    _registerForRedaction();
    _isLoaded = true;
    safeNotifyListeners();
    if (reseal) await _persist();
  }

  /// Keep the panel credentials out of the log.
  ///
  /// An Xtream panel carries the username and the password **in the path**
  /// (`/live/<user>/<pass>/…`), so every stream address that reaches a log
  /// line carries them too — and a log is the first thing a user copies into
  /// a chat when something misbehaves. Registered here because this is where
  /// the sources are known, and the redaction is global from then on.
  ///
  /// An M3U source has no separate login: its playlist and guide addresses
  /// carry it (`get.php?username=…&password=…`, or in the path), and name the
  /// provider. They are registered whole, which also masks the provider's host.
  void _registerForRedaction() {
    for (final source in _sources) {
      LogRedactionManager.registerCustomValue(source.username);
      LogRedactionManager.registerCustomValue(source.password);
      LogRedactionManager.registerServerUrl(source.playlistUrl);
      for (final url in source.epgUrls) {
        LogRedactionManager.registerServerUrl(url);
      }
    }
  }

  Future<void> _persist() async {
    _registerForRedaction();
    try {
      final settings = await SettingsService.getInstance();
      final sealed = [for (final source in _sources) await CredentialFields.protect(source.toJson(), iptvSealedFields)];
      await settings.write(_pref, jsonEncode(sealed));
    } catch (error, stackTrace) {
      appLogger.w('IPTV: could not save the configured sources', error: error, stackTrace: stackTrace);
    }
  }

  /// Add [source], or replace the entry with the same id.
  Future<void> save(IptvSource source) async {
    await ensureLoaded();
    final index = _sources.indexWhere((candidate) => candidate.id == source.id);
    // A stored copy of a list read from elsewhere, or cut to other groups,
    // describes another source: it must not answer the next read.
    if (index != -1 && _sources[index].channelListSignature != source.channelListSignature) {
      await IptvDiskCache().clear(source.id);
    }
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
    await IptvLocalFiles.deleteFor(sourceId);
  }

  /// The groups [draft]'s provider offers — for choosing them before the
  /// source is saved, so read through a source of its own that keeps nothing.
  Future<List<IptvGroupOption>?> groupOptionsFor(IptvSource draft) async {
    final reader = IptvLiveTvSource(draft.withGroups(null));
    try {
      return await reader.fetchGroupOptions();
    } catch (error, stackTrace) {
      appLogger.w('IPTV: groups of a source could not be read', error: error, stackTrace: stackTrace);
      return null;
    } finally {
      reader.close();
    }
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
