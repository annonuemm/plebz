import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

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

  /// Stretching cost for new exports: OWASP's figure for PBKDF2-HMAC-SHA256
  /// (2023). Exports before 1.3.0 used 120000, which a TV box answered in
  /// about a second; this costs a few on one, off the UI thread — an export
  /// is made rarely and a weak password is guessed often.
  static const int iterations = 600000;

  /// The round counts a file may name. Its own count is used, so older and
  /// newer exports stay readable; the ceiling keeps a crafted file from
  /// holding the import for hours, the floor from passing for protection.
  static const int minIterations = 10000;
  static const int maxIterations = 5000000;

  /// For tests about everything around the encryption: a lower count for new
  /// exports, so a suite of backup round trips does not spend minutes
  /// stretching. Never below [minIterations].
  @visibleForTesting
  static int? debugIterations;

  static const int _saltBytes = 16;

  static final AesGcm _cipher = AesGcm.with256bits();

  /// PBKDF2 in its own isolate: pure Dart for several seconds on a TV box
  /// would freeze the screen.
  static Future<SecretKey> _deriveKey(String password, List<int> salt, int rounds) async {
    final bytes = await Isolate.run(() async {
      final key = await Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: rounds,
        bits: 256,
      ).deriveKeyFromPassword(password: password, nonce: salt);
      return key.extractBytes();
    });
    return SecretKey(bytes);
  }

  static List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  /// Encrypts [payload] and returns the envelope fields to write beside it.
  static Future<Map<String, Object?>> encrypt(String payload, String password) async {
    final salt = _randomBytes(_saltBytes);
    final rounds = debugIterations ?? iterations;
    final key = await _deriveKey(password, salt, rounds);
    final box = await _cipher.encrypt(utf8.encode(payload), secretKey: key);
    return {
      'encryption': {
        'algorithm': algorithm,
        'kdf': kdf,
        'iterations': rounds,
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
    if (rounds < minIterations || rounds > maxIterations) {
      throw FormatException('Unsupported protection: $rounds rounds');
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
    final key = await _deriveKey(password, saltBytes, rounds);

    try {
      return utf8.decode(await _cipher.decrypt(box, secretKey: key));
    } on SecretBoxAuthenticationError {
      return null;
    }
  }
}
