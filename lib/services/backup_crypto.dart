import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Password protection for a settings export.
///
/// An export that carries server tokens and IPTV credentials is a key to the
/// user's servers, and it leaves the device by USB stick, cloud drive or chat.
/// So the file is encrypted with a password the user chooses, and the password
/// is never stored: lose it and the file is scrap, which is the point.
///
/// AES-256-GCM over the whole payload, the key stretched from the password
/// with PBKDF2-HMAC-SHA256. Both come from `package:cryptography`, which the
/// app already uses for its credential vault, so nothing new is pulled in.
class BackupCrypto {
  const BackupCrypto._();

  static const String algorithm = 'aes-256-gcm';
  static const String kdf = 'pbkdf2-hmac-sha256';

  /// Stretching cost. High enough that guessing a weak password is expensive,
  /// low enough that an Android TV box — which does this in pure Dart, without
  /// the hardware backing a phone would have — answers in about a second.
  static const int iterations = 120000;

  static const int _saltBytes = 16;

  static final AesGcm _cipher = AesGcm.with256bits();

  static Future<SecretKey> _deriveKey(String password, List<int> salt) {
    final pbkdf2 = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);
    return pbkdf2.deriveKeyFromPassword(password: password, nonce: salt);
  }

  static List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  /// Encrypts [payload] and returns the envelope fields to write beside it.
  static Future<Map<String, Object?>> encrypt(String payload, String password) async {
    final salt = _randomBytes(_saltBytes);
    final key = await _deriveKey(password, salt);
    final box = await _cipher.encrypt(utf8.encode(payload), secretKey: key);
    return {
      'encryption': {
        'algorithm': algorithm,
        'kdf': kdf,
        'iterations': iterations,
        'salt': base64Encode(salt),
        'nonce': base64Encode(box.nonce),
        'mac': base64Encode(box.mac.bytes),
      },
      'payload': base64Encode(box.cipherText),
    };
  }

  /// The payload behind [envelope], or null when [password] is wrong.
  ///
  /// A wrong password and a tampered file are the same event to GCM — the
  /// authentication tag simply does not match — and both come back as null so
  /// the caller can say "wrong password" without guessing.
  ///
  /// Throws [FormatException] when the envelope itself is not readable, which
  /// is a different problem and deserves a different message.
  static Future<String?> decrypt(Map<String, Object?> envelope, String password) async {
    final header = envelope['encryption'];
    final payload = envelope['payload'];
    if (header is! Map || payload is! String) {
      throw const FormatException('Export is not password protected');
    }
    if (header['algorithm'] != algorithm || header['kdf'] != kdf) {
      throw FormatException('Unsupported protection: ${header['algorithm']} / ${header['kdf']}');
    }
    final rounds = header['iterations'];
    final salt = header['salt'];
    final nonce = header['nonce'];
    final mac = header['mac'];
    if (rounds is! int || salt is! String || nonce is! String || mac is! String) {
      throw const FormatException('Export header is incomplete');
    }

    final Uint8List saltBytes;
    final SecretBox box;
    try {
      saltBytes = base64Decode(salt);
      box = SecretBox(base64Decode(payload), nonce: base64Decode(nonce), mac: Mac(base64Decode(mac)));
    } on FormatException {
      throw const FormatException('Export payload is not readable');
    }

    // The file's own round count, not ours: an export written by an older or
    // newer build has to stay readable.
    final key = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: rounds,
      bits: 256,
    ).deriveKeyFromPassword(password: password, nonce: saltBytes);

    try {
      return utf8.decode(await _cipher.decrypt(box, secretKey: key));
    } on SecretBoxAuthenticationError {
      return null;
    }
  }
}
