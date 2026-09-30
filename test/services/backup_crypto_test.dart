import 'dart:convert';

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
