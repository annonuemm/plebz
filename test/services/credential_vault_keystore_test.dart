import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/base_shared_preferences_service.dart';
import 'package:plezy/services/credential_vault.dart';
import 'package:plezy/services/sensitive_prefs.dart';
import 'package:plezy/services/vault_key_wrap.dart';

import '../test_helpers/prefs.dart';

/// A stand-in Keystore: wraps by XOR, in the real layout (IV, key, tag).
class _FakeKeystore {
  String? failUnwrapWith;
  bool corruptRoundTrip = false;
  int wraps = 0;
  int unwraps = 0;

  Uint8List _xor(List<int> bytes) => Uint8List.fromList([for (final b in bytes) b ^ 0x5a]);

  Future<Object?> handle(MethodCall call) async {
    final bytes = call.arguments as Uint8List;
    switch (call.method) {
      case 'wrap':
        wraps++;
        return Uint8List.fromList([...List<int>.filled(12, 1), ..._xor(bytes), ...List<int>.filled(16, 2)]);
      case 'unwrap':
        unwraps++;
        final code = failUnwrapWith;
        if (code != null) throw PlatformException(code: code, message: 'fake');
        final key = _xor(bytes.sublist(12, bytes.length - 16));
        if (corruptRoundTrip) key[0] ^= 0xff;
        return key;
    }
    return null;
  }
}

Future<String?> _storedKey() async =>
    readTolerantString(await BaseSharedPreferencesService.sharedCache(), credentialVaultKeyPref);

void main() {
  late _FakeKeystore keystore;

  setUp(() {
    resetSharedPreferencesForTest();
    CredentialVault.resetKeyForTesting();
    keystore = _FakeKeystore();
    VaultKeyWrap.debugSupported = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      VaultKeyWrap.channel,
      keystore.handle,
    );
  });

  tearDown(() {
    VaultKeyWrap.debugSupported = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      VaultKeyWrap.channel,
      null,
    );
  });

  /// What a restart does to the vault: forget the key in memory.
  void restart() => CredentialVault.resetKeyForTesting();

  test('a new key is stored wrapped, and opens again after a restart', () async {
    final sealed = await CredentialVault.protect('server-token');
    final stored = await _storedKey();
    expect(stored, startsWith('ks1:'));
    expect(CredentialVault.isStoredKeyForm(stored!), isTrue);

    restart();
    expect(await CredentialVault.reveal(sealed), 'server-token');
    expect(keystore.unwraps, greaterThan(0));
  });

  test('a key stored before is wrapped on its next use, and its tokens still open', () async {
    VaultKeyWrap.debugSupported = false;
    final sealed = await CredentialVault.protect('server-token');
    final plain = await _storedKey();
    expect(plain, isNot(startsWith('ks1:')));

    VaultKeyWrap.debugSupported = true;
    restart();
    expect(await CredentialVault.reveal(sealed), 'server-token');
    expect(await _storedKey(), startsWith('ks1:'));

    restart();
    expect(await CredentialVault.reveal(sealed), 'server-token', reason: 'the wrapped key is the same key');
  });

  test('a Keystore that gives back something else is never trusted with the key', () async {
    VaultKeyWrap.debugSupported = false;
    final sealed = await CredentialVault.protect('server-token');
    final plain = await _storedKey();

    VaultKeyWrap.debugSupported = true;
    keystore.corruptRoundTrip = true;
    restart();
    expect(await CredentialVault.reveal(sealed), 'server-token');
    expect(await _storedKey(), plain, reason: 'left as it was');
  });

  test('a Keystore not answering for now overwrites nothing, and the next access gets through', () async {
    final sealed = await CredentialVault.protect('server-token');
    final wrapped = await _storedKey();

    keystore.failUnwrapWith = 'UNAVAILABLE';
    restart();
    expect(await CredentialVault.reveal(sealed), isNull, reason: 'not now');
    expect(await _storedKey(), wrapped, reason: 'nothing replaced');

    keystore.failUnwrapWith = null;
    expect(await CredentialVault.reveal(sealed), 'server-token', reason: 'the failure was not kept');
  });

  test('a wrapping key that is gone starts a new vault key, so signing in works again', () async {
    final sealed = await CredentialVault.protect('server-token');
    final wrapped = await _storedKey();

    keystore.failUnwrapWith = 'KEY_GONE';
    restart();
    expect(await CredentialVault.reveal(sealed), isNull, reason: 'what it sealed is lost');
    expect(await _storedKey(), isNot(wrapped));

    keystore.failUnwrapWith = null;
    final fresh = await CredentialVault.protect('new-token');
    restart();
    expect(await CredentialVault.reveal(fresh), 'new-token');
  });

  test('without a Keystore the key is stored as it always was', () async {
    VaultKeyWrap.debugSupported = false;
    await CredentialVault.protect('server-token');
    final stored = await _storedKey();
    expect(base64Decode(stored!), hasLength(32));
    expect(keystore.wraps, 0);
  });

  test('both stored forms count as a vault key for the preference repair', () {
    expect(CredentialVault.isStoredKeyForm(base64Encode(List<int>.filled(32, 7))), isTrue);
    expect(CredentialVault.isStoredKeyForm('ks1:${base64Encode(List<int>.filled(60, 7))}'), isTrue);
    expect(CredentialVault.isStoredKeyForm('ks1:${base64Encode(List<int>.filled(32, 7))}'), isFalse);
    expect(CredentialVault.isStoredKeyForm('not a key'), isFalse);
  });
}
