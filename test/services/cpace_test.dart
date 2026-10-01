import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/companion_remote/cpace.dart';

/// draft-irtf-cfrg-cpace-18, Appendix B.1: CPace on X25519 with SHA-512.
Uint8List _hex(String hex) {
  final clean = hex.replaceAll(RegExp(r'\s'), '');
  return Uint8List.fromList([
    for (var i = 0; i < clean.length; i += 2) int.parse(clean.substring(i, i + 2), radix: 16),
  ]);
}

String _toHex(List<int> bytes) => [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

void main() {
  group('string utilities (A.1)', () {
    test('prepend_len', () {
      expect(_toHex(CPace.prependLen(const [])), '00');
      expect(_toHex(CPace.prependLen(utf8.encode('1234'))), '0431323334');
      expect(CPace.prependLen(List<int>.generate(127, (i) => i)).first, 0x7f);
      final long = CPace.prependLen(List<int>.generate(128, (i) => i));
      expect(_toHex(long.sublist(0, 3)), '800100');
      expect(long, hasLength(130));
    });

    test('lv_cat', () {
      expect(
        _toHex(CPace.lvCat([utf8.encode('1234'), utf8.encode('5'), const [], utf8.encode('678')])),
        '043132333401350003363738',
      );
    });

    test('transcript_ir', () {
      expect(
        _toHex(
          CPace.transcriptIr(utf8.encode('123'), utf8.encode('PartyA'), utf8.encode('234'), utf8.encode('PartyB')),
        ),
        '03313233065061727479410332333406506172747942',
      );
    });
  });

  group('the protocol (B.1)', () {
    final prs = utf8.encode('Password');
    final ci = _hex('6f630b425f726573706f6e6465720b415f696e69746961746f72');
    final sid = _hex('7e4b4791d6a8ef019b936c79fb7f2c57');
    final ya = _hex('21b4f4bd9e64ed355c3eb676a28ebedaf6d8f17bdc365995b319097153044080');
    final yb = _hex('848b0779ff415f0af4ea14df9dd1d3c29ac41d836c7808896c4eba19c51ac40a');
    final ada = utf8.encode('ADa');
    final adb = utf8.encode('ADb');

    test('the generator string and the generator', () {
      final genStr = CPace.generatorString(prs: prs, ci: ci, sid: sid);
      expect(genStr, hasLength(172));
      expect(
        _toHex(genStr),
        '0843506163653235350850617373776f72646d'
        '${'00' * 109}'
        '1a6f630b425f726573706f6e6465720b415f696e69746961746f72107e4b4791d6a8ef019b936c79fb7f2c57',
      );
      expect(
        _toHex(CPace.calculateGenerator(prs: prs, ci: ci, sid: sid)),
        '64e8099e3ea682cfdc5cb665c057ebb514d06bf23ebc9f743b51b82242327074',
      );
    });

    test('the shares, the secret point and the session key', () {
      final g = CPace.calculateGenerator(prs: prs, ci: ci, sid: sid);
      final shareA = CPace.scalarMult(ya, g);
      final shareB = CPace.scalarMult(yb, g);
      expect(_toHex(shareA), '1b02dad6dbd29a07b6d28c9e04cb2f184f0734350e32bb7e62ff9dbcfdb63d15');
      expect(_toHex(shareB), '20cda5955f82c4931545bcbf40758ce1010d7db4db2a907013d79c7a8fcf957f');

      final kA = CPace.scalarMultVfy(ya, shareB)!;
      final kB = CPace.scalarMultVfy(yb, shareA)!;
      expect(_toHex(kA), 'f97fdfcfff1c983ed6283856a401de3191ca919902b323c5f950c9703df7297a');
      expect(kB, kA);

      final isk = CPace.intermediateSessionKey(sid: sid, k: kA, ya: shareA, ada: ada, yb: shareB, adb: adb);
      expect(
        _toHex(isk),
        'a051ee5ee2499d16da3f69f430218b8ea94a18a45b67f9e86495b382c33d14a5'
        'c38cecc0cc834f960e39e0d1bf7d76b9ef5d54eecc5e0f386c97ad12da8c3d5f',
      );
    });

    test('a different code gives a different key', () {
      final g1 = CPace.calculateGenerator(prs: utf8.encode('12345678'), ci: ci, sid: sid);
      final g2 = CPace.calculateGenerator(prs: utf8.encode('12345679'), ci: ci, sid: sid);
      final shareA = CPace.scalarMult(ya, g1);
      final shareB = CPace.scalarMult(yb, g2);
      final iskA = CPace.intermediateSessionKey(
        sid: sid,
        k: CPace.scalarMultVfy(ya, shareB)!,
        ya: shareA,
        ada: ada,
        yb: shareB,
        adb: adb,
      );
      final iskB = CPace.intermediateSessionKey(
        sid: sid,
        k: CPace.scalarMultVfy(yb, shareA)!,
        ya: shareA,
        ada: ada,
        yb: shareB,
        adb: adb,
      );
      expect(iskA, isNot(iskB));
    });
  });

  group('scalar_mult_vfy on low-order points (B.1.10)', () {
    final s = _hex('af46e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449aff');
    const cases = {
      'u0': ('0000000000000000000000000000000000000000000000000000000000000000', null),
      'u1': ('0100000000000000000000000000000000000000000000000000000000000000', null),
      'u2': ('ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f', null),
      'u3': ('e0eb7a7c3b41b8ae1656e3faf19fc46ada098deb9c32b1fd866205165f49b800', null),
      'u4': ('5f9c95bca3508c24b1d0b1559c83ef5b04445cc4581c8e86d8224eddd09f1157', null),
      'u5': ('edffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f', null),
      'u6': (
        'daffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
        'd8e2c776bbacd510d09fd9278b7edcd25fc5ae9adfba3b6e040e8d3b71b21806',
      ),
      'u7': ('eeffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f', null),
      'u8': (
        'dbffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
        'c85c655ebe8be44ba9c0ffde69f2fe10194458d137f09bbff725ce58803cdb38',
      ),
      'u9': (
        'd9ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
        'db64dafa9b8fdd136914e61461935fe92aa372cb056314e1231bc4ec12417456',
      ),
      'ua': (
        'cdeb7a7c3b41b8ae1656e3faf19fc46ada098deb9c32b1fd866205165f49b880',
        'e062dcd5376d58297be2618c7498f55baa07d7e03184e8aada20bca28888bf7a',
      ),
      'ub': (
        '4c9c95bca3508c24b1d0b1559c83ef5b04445cc4581c8e86d8224eddd09f11d7',
        '993c6ad11c4c29da9a56f7691fd0ff8d732e49de6250b6c2e80003ff4629a175',
      ),
    };
    cases.forEach((name, value) {
      test(name, () {
        final result = CPace.scalarMultVfy(s, _hex(value.$1));
        if (value.$2 == null) {
          expect(result, isNull, reason: 'a low-order point must abort');
        } else {
          expect(_toHex(result!), value.$2);
        }
      });
    });
  });

  test('key confirmation tags agree only on the same key', () {
    final sid = _hex('7e4b4791d6a8ef019b936c79fb7f2c57');
    final key = CPace.confirmationKey(sid, List<int>.filled(64, 7));
    final other = CPace.confirmationKey(sid, List<int>.filled(64, 8));
    final tag = CPace.confirmationTag(key, List<int>.filled(32, 1), utf8.encode('A'));
    expect(CPace.tagsEqual(tag, CPace.confirmationTag(key, List<int>.filled(32, 1), utf8.encode('A'))), isTrue);
    expect(CPace.tagsEqual(tag, CPace.confirmationTag(other, List<int>.filled(32, 1), utf8.encode('A'))), isFalse);
  });
}
