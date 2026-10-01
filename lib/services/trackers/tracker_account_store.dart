import 'dart:async';
import 'dart:convert';

import '../../profiles/profile.dart';
import '../../utils/app_logger.dart';
import '../base_shared_preferences_service.dart';
import '../credential_fields.dart';
import 'tracker_constants.dart';
import 'tracker_session.dart';

/// Per-Plex-profile session persistence for any tracker service.
///
/// Keyed by `user_{uuid}_{baseKey}` so each Plex Home profile gets its own
/// stored session. The storage key remains service-specific, while the payload
/// is the unified [TrackerSession] JSON shape.
///
/// Pass an empty `userUuid` to fall back to a single global slot (used
/// before a profile has been selected).
///
/// The access and refresh tokens are sealed with `CredentialVault`; the rest
/// of the JSON stays readable, so the preference repair can still recognise a
/// session. One stored before sealing began is sealed on its next load.
class TrackerAccountStore {
  static const _sealedFields = ['access_token', 'refresh_token'];

  static final Map<TrackerService, TrackerAccountStore> _stores = {
    TrackerService.mal: TrackerAccountStore._(TrackerService.mal, 'mal_session'),
    TrackerService.anilist: TrackerAccountStore._(TrackerService.anilist, 'anilist_session'),
    TrackerService.simkl: TrackerAccountStore._(TrackerService.simkl, 'simkl_session'),
    TrackerService.trakt: TrackerAccountStore._(TrackerService.trakt, 'trakt_session'),
    TrackerService.mdblist: TrackerAccountStore._(TrackerService.mdblist, 'mdblist_session'),
  };

  static TrackerAccountStore forService(TrackerService service) => _stores[service]!;

  final TrackerService service;
  final String _baseKey;

  TrackerAccountStore._(this.service, this._baseKey);

  String _scopedKey(String userUuid) => profileScopedPrefsKey(userUuid, _baseKey);

  Future<TrackerSession?> load(String userUuid) async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final raw = readTolerantString(prefs, _scopedKey(userUuid));
    if (raw == null) return null;
    try {
      final opened = await CredentialFields.reveal(Map<String, Object?>.from(jsonDecode(raw) as Map), _sealedFields);
      // A token the vault can no longer open is a session to sign in again.
      if (opened.lost > 0) return null;
      final session = TrackerSession.fromJson(opened.json.cast<String, dynamic>(), service: service);
      if (opened.hadPlaintext) {
        unawaited(
          save(
            userUuid,
            session,
          ).catchError((Object error) => appLogger.d('Trackers: sealing a stored session failed', error: error)),
        );
      }
      return session;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String userUuid, TrackerSession session) async {
    final sealed = await CredentialFields.protect(Map<String, Object?>.from(session.toJson()), _sealedFields);
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setString(_scopedKey(userUuid), jsonEncode(sealed));
  }

  Future<void> clear(String userUuid) async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.remove(_scopedKey(userUuid));
  }
}

TrackerAccountStore trackerAccountStore(TrackerService service) => TrackerAccountStore.forService(service);
