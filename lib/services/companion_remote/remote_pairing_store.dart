import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';

import '../../utils/app_logger.dart';
import '../base_shared_preferences_service.dart';
import '../credential_vault.dart';
import '../sensitive_prefs.dart';

/// Which side of a pairing this install is.
enum RemotePairingRole {
  /// The device being controlled (a TV, a desktop): it showed the code.
  host,

  /// The phone or tablet that controls: it typed the code.
  remote,
}

/// One paired device: who it is, and the key both sides derived from the
/// pairing run. The key is the only secret; [id] is derived from it and safe
/// to send.
@immutable
class RemotePairing {
  const RemotePairing({
    required this.peerDeviceId,
    required this.peerName,
    required this.peerPlatform,
    required this.key,
    required this.pairedAt,
  });

  final String peerDeviceId;
  final String peerName;
  final String peerPlatform;
  final List<int> key;
  final DateTime pairedAt;

  /// Names the pairing in the handshake without revealing the key.
  String get id => pairingIdForKey(key);

  static String pairingIdForKey(List<int> key) {
    final bytes = crypto.Hmac(crypto.sha256, key).convert(utf8.encode('plebz-remote-pairing-id')).bytes.take(16);
    return 'p1.${base64UrlEncode(bytes.toList()).replaceAll('=', '')}';
  }
}

/// The companion remote's pairings, on both sides, and this install's own
/// remote device id. Kept in [companionRemotePairingsPref], every key sealed
/// with [CredentialVault].
///
/// Pairings belong to the device, not to a profile: a phone paired with the
/// television stays paired whoever is signed in on either.
class RemotePairingStore {
  RemotePairingStore._();

  static RemotePairingStore instance = RemotePairingStore._();

  @visibleForTesting
  static void resetForTesting() => instance = RemotePairingStore._();

  /// An in-memory store for tests that do not exercise persistence.
  @visibleForTesting
  static RemotePairingStore memoryForTesting({String deviceId = 'test-device'}) => RemotePairingStore._()
    .._deviceId = deviceId
    .._loaded = true
    .._inMemory = true;

  String? _deviceId;
  final Map<RemotePairingRole, List<RemotePairing>> _pairings = {
    RemotePairingRole.host: [],
    RemotePairingRole.remote: [],
  };
  bool _loaded = false;
  bool _inMemory = false;
  Future<void>? _loading;

  /// Notifies when a pairing is added or removed — the host's list of paired
  /// devices follows it.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  /// This install's id in pairings: random, made once, never derived from an
  /// account.
  Future<String> deviceId() async {
    await ensureLoaded();
    final existing = _deviceId;
    if (existing != null) return existing;
    final random = Random.secure();
    final id = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    _deviceId = id;
    await _save();
    return id;
  }

  Future<List<RemotePairing>> pairings(RemotePairingRole role) async {
    await ensureLoaded();
    return List.unmodifiable(_pairings[role]!);
  }

  Future<RemotePairing?> forId(RemotePairingRole role, String id) async {
    for (final pairing in await pairings(role)) {
      if (pairing.id == id) return pairing;
    }
    return null;
  }

  Future<RemotePairing?> forPeer(RemotePairingRole role, String peerDeviceId) async {
    for (final pairing in await pairings(role)) {
      if (pairing.peerDeviceId == peerDeviceId) return pairing;
    }
    return null;
  }

  /// Adds [pairing], replacing an older one with the same device.
  Future<void> add(RemotePairingRole role, RemotePairing pairing) async {
    await ensureLoaded();
    _pairings[role] = [
      for (final existing in _pairings[role]!)
        if (existing.peerDeviceId != pairing.peerDeviceId) existing,
      pairing,
    ];
    await _save();
    revision.value++;
  }

  Future<void> remove(RemotePairingRole role, String peerDeviceId) async {
    await ensureLoaded();
    final before = _pairings[role]!.length;
    _pairings[role] = [
      for (final existing in _pairings[role]!)
        if (existing.peerDeviceId != peerDeviceId) existing,
    ];
    if (_pairings[role]!.length == before) return;
    await _save();
    revision.value++;
  }

  Future<void> _load() async {
    if (_inMemory) {
      _loaded = true;
      return;
    }
    try {
      final prefs = await BaseSharedPreferencesService.sharedCache();
      final raw = readTolerantString(prefs, companionRemotePairingsPref);
      if (raw != null && raw.isNotEmpty) {
        final json = jsonDecode(raw);
        if (json is Map<String, dynamic>) {
          final deviceId = json['deviceId'];
          if (deviceId is String && deviceId.isNotEmpty) _deviceId = deviceId;
          for (final role in RemotePairingRole.values) {
            final list = json[role.name];
            if (list is! List) continue;
            for (final entry in list) {
              final pairing = await _decode(entry);
              if (pairing != null) _pairings[role]!.add(pairing);
            }
          }
        }
      }
    } catch (error) {
      appLogger.w('CompanionRemote: pairings unreadable, starting without', error: error);
    }
    _loaded = true;
  }

  Future<RemotePairing?> _decode(Object? entry) async {
    if (entry is! Map) return null;
    final peerDeviceId = entry['peer'];
    final sealedKey = entry['key'];
    if (peerDeviceId is! String || sealedKey is! String) return null;
    final key = await CredentialVault.reveal(sealedKey);
    if (key == null) return null;
    final List<int> keyBytes;
    try {
      keyBytes = base64Decode(key);
    } catch (_) {
      return null;
    }
    if (keyBytes.length != 32) return null;
    return RemotePairing(
      peerDeviceId: peerDeviceId,
      peerName: entry['name'] is String ? entry['name'] as String : '',
      peerPlatform: entry['platform'] is String ? entry['platform'] as String : '',
      key: keyBytes,
      pairedAt: DateTime.tryParse(entry['pairedAt'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Future<void> _save() async {
    if (_inMemory) return;
    final json = <String, Object?>{'deviceId': _deviceId};
    for (final role in RemotePairingRole.values) {
      json[role.name] = [
        for (final pairing in _pairings[role]!)
          {
            'peer': pairing.peerDeviceId,
            'name': pairing.peerName,
            'platform': pairing.peerPlatform,
            'key': await CredentialVault.protect(base64Encode(pairing.key)),
            'pairedAt': pairing.pairedAt.toUtc().toIso8601String(),
          },
      ];
    }
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setString(companionRemotePairingsPref, jsonEncode(json));
  }
}
