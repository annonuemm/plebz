import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

/// CPace over X25519 with SHA-512 (draft-irtf-cfrg-cpace-18, cipher suite
/// CPACE-X25519-SHA512): a balanced PAKE, the CFRG's recommendation.
///
/// What it buys the companion remote's pairing: two devices that share only a
/// short code (the PRS, eight digits typed from one screen into the other)
/// end with a strong shared key, and nobody watching or even sitting in the
/// middle learns anything that would let them try codes offline. Each run
/// tests exactly one guess; wrong guesses are a matter of the host's lockout.
///
/// Every function here follows the draft's definitions by name and is pinned
/// to its test vectors (Appendix B.1) in `test/services/cpace_test.dart`.
abstract final class CPace {
  /// G_X25519.DSI.
  static final Uint8List dsi = Uint8List.fromList('CPace255'.codeUnits);

  /// SHA-512's input block size, H.s_in_bytes.
  static const _hashBlockBytes = 128;

  static const _fieldBytes = 32;

  /// 2^255 - 19.
  static final BigInt _p = (BigInt.one << 255) - BigInt.from(19);

  /// Curve25519's Montgomery parameter A.
  static final BigInt _a = BigInt.from(486662);

  /// The non-square Elligator 2 uses for Curve25519.
  static final BigInt _z = BigInt.two;

  static const _x25519 = DartX25519();

  // ── String utilities (Appendix A.1) ──

  /// LEB128 length, then the bytes.
  static Uint8List prependLen(List<int> data) {
    final length = <int>[];
    var remaining = data.length;
    while (true) {
      if (remaining < 128) {
        length.add(remaining);
      } else {
        length.add((remaining & 0x7f) + 0x80);
      }
      remaining >>= 7;
      if (remaining == 0) break;
    }
    return Uint8List.fromList([...length, ...data]);
  }

  static Uint8List lvCat(List<List<int>> parts) => Uint8List.fromList([for (final part in parts) ...prependLen(part)]);

  /// generator_string (Appendix A.2): the DSI and the PRS fill the first hash
  /// block together with zero padding, so the time spent hashing does not
  /// depend on the code.
  static Uint8List generatorString({required List<int> prs, required List<int> ci, required List<int> sid}) {
    final zpad = max(0, _hashBlockBytes - 1 - prependLen(prs).length - prependLen(dsi).length);
    return lvCat([dsi, prs, Uint8List(zpad), ci, sid]);
  }

  /// transcript_ir: initiator A's share and data, then responder B's.
  static Uint8List transcriptIr(List<int> ya, List<int> ada, List<int> yb, List<int> adb) => Uint8List.fromList([
    ...lvCat([ya, ada]),
    ...lvCat([yb, adb]),
  ]);

  // ── Group operations (Section 7.2) ──

  /// G.calculate_generator: the generator for this code and session, a point
  /// whose discrete logarithm nobody knows.
  static Uint8List calculateGenerator({required List<int> prs, required List<int> ci, required List<int> sid}) {
    final hash = crypto.sha512.convert(generatorString(prs: prs, ci: ci, sid: sid)).bytes.sublist(0, _fieldBytes);
    return _encodeU(_elligator2(_decodeU(hash)));
  }

  /// G.sample_scalar: 32 random bytes; X25519 clamps them.
  static Uint8List sampleScalar([Random? random]) {
    final source = random ?? Random.secure();
    return Uint8List.fromList(List<int>.generate(_fieldBytes, (_) => source.nextInt(256)));
  }

  /// G.scalar_mult_vfy: X25519(y, g), or null where the result is the neutral
  /// element — a low-order point, on the curve or its twist. Both parties
  /// MUST abort then.
  static Uint8List? scalarMultVfy(List<int> scalar, List<int> point) {
    if (scalar.length != _fieldBytes || point.length != _fieldBytes) return null;
    final keyPair = SimpleKeyPairData(
      Uint8List.fromList(scalar),
      publicKey: SimplePublicKey(Uint8List(_fieldBytes), type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
    final shared = _x25519.sharedSecretSync(
      keyPairData: keyPair,
      remotePublicKey: SimplePublicKey(Uint8List.fromList(point), type: KeyPairType.x25519),
    );
    final bytes = Uint8List.fromList((shared as SecretKeyData).bytes);
    var acc = 0;
    for (final byte in bytes) {
      acc |= byte;
    }
    return acc == 0 ? null : bytes;
  }

  /// G.scalar_mult: a party's public share Y = y*g. The generator is never a
  /// low-order point, so this cannot fail for a real one.
  static Uint8List scalarMult(List<int> scalar, List<int> generator) =>
      scalarMultVfy(scalar, generator) ?? (throw StateError('CPace: generator of low order'));

  // ── Key derivation ──

  /// ISK = H.hash(lv_cat(DSI || "_ISK", sid, K) || transcript_ir(...)).
  static Uint8List intermediateSessionKey({
    required List<int> sid,
    required List<int> k,
    required List<int> ya,
    required List<int> ada,
    required List<int> yb,
    required List<int> adb,
  }) {
    final input = [
      ...lvCat([
        [...dsi, ...'_ISK'.codeUnits],
        sid,
        k,
      ]),
      ...transcriptIr(ya, ada, yb, adb),
    ];
    return Uint8List.fromList(crypto.sha512.convert(input).bytes);
  }

  /// Explicit key confirmation (Section 9.4): mac_key = H("CPaceMac" || sid || ISK).
  static Uint8List confirmationKey(List<int> sid, List<int> isk) =>
      Uint8List.fromList(crypto.sha512.convert([...'CPaceMac'.codeUnits, ...sid, ...isk]).bytes);

  /// A party's tag over the message it sent: HMAC(mac_key, lv_cat(Y, AD)).
  static Uint8List confirmationTag(List<int> macKey, List<int> share, List<int> associatedData) =>
      Uint8List.fromList(crypto.Hmac(crypto.sha512, macKey).convert(lvCat([share, associatedData])).bytes);

  /// Constant-time comparison for the tags.
  static bool tagsEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  // ── RFC 7748 coordinates and RFC 9380's Elligator 2 (Appendix A.4, A.5) ──

  /// decodeUCoordinate for 255 bits: little-endian, the top bit ignored.
  static BigInt _decodeU(List<int> bytes) {
    final copy = Uint8List.fromList(bytes);
    copy[_fieldBytes - 1] &= 0x7f;
    var value = BigInt.zero;
    for (var i = _fieldBytes - 1; i >= 0; i--) {
      value = (value << 8) | BigInt.from(copy[i]);
    }
    return value;
  }

  static Uint8List _encodeU(BigInt value) {
    final out = Uint8List(_fieldBytes);
    var rest = value % _p;
    for (var i = 0; i < _fieldBytes; i++) {
      out[i] = (rest & BigInt.from(0xff)).toInt();
      rest >>= 8;
    }
    return out;
  }

  /// elligator2(r): v = -A / (1 + z r²); ε = Legendre(v³ + A v² + v);
  /// x = ε v − (1 − ε) A / 2. Division by zero follows RFC 9380's inv0.
  static BigInt _elligator2(BigInt r) {
    final p = _p;
    BigInt mod(BigInt x) => x % p;
    BigInt inv0(BigInt x) => mod(x) == BigInt.zero ? BigInt.zero : mod(x).modPow(p - BigInt.two, p);

    final v = mod(-_a * inv0(BigInt.one + _z * r * r));
    final rhs = mod(v * v * v + _a * v * v + v);
    final legendre = rhs.modPow((p - BigInt.one) >> 1, p);
    final epsilon = legendre == p - BigInt.one ? BigInt.from(-1) : legendre;
    final halfA = mod(_a * inv0(BigInt.two));
    return mod(epsilon * v - (BigInt.one - epsilon) * halfA);
  }
}
