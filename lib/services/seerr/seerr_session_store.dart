import '../../models/seerr/seerr_session.dart';
import '../../profiles/profile.dart';
import '../../utils/serial_future_queue.dart';
import '../base_shared_preferences_service.dart';
import '../credential_vault.dart';

/// Per-Plex-profile persistence for the Seerr session, mirroring
/// `TrackerAccountStore`'s `user_{uuid}_{baseKey}` scoping.
///
/// The password ([SeerrSession.secret]) and the session cookie
/// ([SeerrSession.cookie], as good as a sign-in while it lasts) are
/// CredentialVault-protected at the store boundary. A failed decrypt of the
/// password degrades to an empty secret (the session keeps working until its
/// cookie expires); of the cookie, to an empty one (the password signs in
/// again). A cookie stored before sealing began is sealed on its next load.
class SeerrSessionStore {
  static const String _baseKey = 'seerr_session';

  // Shared across profile-keyed provider/store lifetimes. Enqueue the entire
  // operation before any preferences/vault await so a new load or clear cannot
  // overtake an old provider's still-encrypting save.
  static final SerialFutureQueue _persistence = SerialFutureQueue();

  const SeerrSessionStore();

  String _scopedKey(String userUuid) => profileScopedPrefsKey(userUuid, _baseKey);

  Future<SeerrSession?> load(String userUuid) => _persistence.run(() async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    // Outside the try below on purpose: an unreadable credential must
    // reach the repair prompt, not be swallowed as 'no session'.
    final raw = readTolerantString(prefs, _scopedKey(userUuid));
    if (raw == null) return null;
    try {
      final session = SeerrSession.decode(raw);
      final cookieWasPlain = session.cookie.isNotEmpty && !CredentialVault.isProtected(session.cookie);
      final opened = session.copyWith(
        secret: session.secret.isEmpty ? '' : await CredentialVault.reveal(session.secret) ?? '',
        cookie: session.cookie.isEmpty ? '' : await CredentialVault.reveal(session.cookie) ?? '',
      );
      if (cookieWasPlain) await prefs.setString(_scopedKey(userUuid), (await _seal(opened)).encode());
      return opened;
    } catch (_) {
      return null;
    }
  });

  static Future<SeerrSession> _seal(SeerrSession session) async => session.copyWith(
    secret: session.secret.isEmpty ? '' : await CredentialVault.protect(session.secret),
    cookie: session.cookie.isEmpty ? '' : await CredentialVault.protect(session.cookie),
  );

  Future<void> save(String userUuid, SeerrSession session) => _persistence.run(() async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setString(_scopedKey(userUuid), (await _seal(session)).encode());
  });

  Future<void> clear(String userUuid) => _persistence.run(() async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.remove(_scopedKey(userUuid));
  });
}
