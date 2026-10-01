import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/backup_crypto.dart';

void main() {
  group('a protected export', () {
    test('comes back exactly as it went in', () async {
      const payload = '{"prefs":{"theme":"dark"},"connections":[{"id":"plex-1"}]}';

      final envelope = await BackupCrypto.encrypt(payload, 'correct horse');

      expect(await BackupCrypto.decrypt(envelope, 'correct horse'), payload);
    });

    test('keeps nothing of the payload in the clear', () async {
      final envelope = await BackupCrypto.encrypt('{"token":"plex-secret-value"}', 'pw');

      expect(jsonEncode(envelope), isNot(contains('plex-secret-value')));
      expect(jsonEncode(envelope), isNot(contains('token')));
    });

    test('does not carry the password', () async {
      final envelope = await BackupCrypto.encrypt('{}', 'hunter2');

      expect(jsonEncode(envelope), isNot(contains('hunter2')));
    });

    test('yields nothing for the wrong password, rather than nonsense', () async {
      final envelope = await BackupCrypto.encrypt('{"a":1}', 'right');

      expect(await BackupCrypto.decrypt(envelope, 'wrong'), isNull);
    });

    test('yields nothing when the file was tampered with', () async {
      // Same signal as a wrong password: GCM cannot tell the caller which of
      // the two happened, and neither answer should return a payload.
      final envelope = await BackupCrypto.encrypt('{"a":1}', 'pw');
      final cipher = base64Decode(envelope['payload']! as String)..[0] ^= 0xFF;

      expect(await BackupCrypto.decrypt({...envelope, 'payload': base64Encode(cipher)}, 'pw'), isNull);
    });

    test('two exports of the same payload look nothing alike', () async {
      // A fresh salt and nonce every time: equal files would say that two
      // backups hold the same settings, and would reuse a key stream.
      final first = await BackupCrypto.encrypt('{"a":1}', 'pw');
      final second = await BackupCrypto.encrypt('{"a":1}', 'pw');

      expect(first['payload'], isNot(second['payload']));
      expect((first['encryption']! as Map)['salt'], isNot((second['encryption']! as Map)['salt']));
    });

    test('reads a file written with another round count', () async {
      // The header carries the count the file was written with, so an export
      // from an older or newer build still opens.
      final envelope = await BackupCrypto.encrypt('{"a":1}', 'pw');
      final header = Map<String, Object?>.of(envelope['encryption']! as Map<String, Object?>);

      expect(header['iterations'], BackupCrypto.iterations);
      expect(header['algorithm'], 'aes-256-gcm');
    });

    test('new exports stretch with OWASP\'s count; an export from before 1.3.0 still opens', () async {
      final envelope = await BackupCrypto.encrypt('{"a":1}', 'pw');
      expect((envelope['encryption']! as Map)['iterations'], 600000);

      // Written the way 1.2 wrote it: 120000 rounds.
      final salt = List<int>.generate(16, (i) => i);
      final key = await Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: 120000,
        bits: 256,
      ).deriveKeyFromPassword(password: 'pw', nonce: salt);
      final box = await AesGcm.with256bits().encrypt(utf8.encode('{"old":true}'), secretKey: key);
      final legacy = <String, Object?>{
        'encryption': {
          'algorithm': 'aes-256-gcm',
          'kdf': 'pbkdf2-hmac-sha256',
          'iterations': 120000,
          'salt': base64Encode(salt),
          'nonce': base64Encode(box.nonce),
          'mac': base64Encode(box.mac.bytes),
        },
        'payload': base64Encode(box.cipherText),
      };
      expect(await BackupCrypto.decrypt(legacy, 'pw'), '{"old":true}');
    });

    test('a file naming an absurd round count is refused before any work', () async {
      // Otherwise a crafted file holds the import for hours.
      final envelope = await BackupCrypto.encrypt('{"a":1}', 'pw');
      for (final rounds in [BackupCrypto.maxIterations + 1, 1 << 40, BackupCrypto.minIterations - 1, 1]) {
        final header = {...envelope['encryption']! as Map<String, Object?>, 'iterations': rounds};
        await expectLater(
          BackupCrypto.decrypt({...envelope, 'encryption': header}, 'pw'),
          throwsA(isA<FormatException>()),
          reason: '$rounds',
        );
      }
    });

    test('an unprotected or broken envelope is named as such', () async {
      await expectLater(BackupCrypto.decrypt({'prefs': {}}, 'pw'), throwsA(isA<FormatException>()));
      await expectLater(
        BackupCrypto.decrypt({
          'encryption': {'algorithm': 'rot13', 'kdf': 'none'},
          'payload': 'x',
        }, 'pw'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
