import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import 'cpace.dart';

/// The companion remote's pairing: an eight-digit code shown on the host and
/// typed on the remote, run through [CPace] so that the code never becomes
/// something a listener could try guesses against.
///
/// Roles follow CPace's initiator/responder order: the remote (A) sends its
/// share first, the host (B) answers with its share and its confirmation tag,
/// the remote checks that tag and answers with its own. Both then hold the
/// same pairing key, derived from the session key and never sent.
///
/// The party identifiers — the two installs' remote device ids — go into
/// CPace's channel identifier, so a run is bound to these two devices.
abstract final class RemotePairingHandshake {
  /// Eight digits, as for Matter's setup code: ~27 bits, which a PAKE leaves
  /// to online guessing alone — one guess per run, and the host locks out.
  static const codeLength = 8;

  /// How long a code shown on the host stays good.
  static const codeLifetime = Duration(minutes: 2);

  static const _channelLabel = 'plebz-remote-pair-v1';

  /// A fresh code, uniformly random.
  static String newCode([Random? random]) {
    final source = random ?? Random.secure();
    return List<int>.generate(codeLength, (_) => source.nextInt(10)).join();
  }

  /// The code as typed: digits only, spaces and dashes dropped. Null when it
  /// is not [codeLength] digits.
  static String? normalizeCode(String input) {
    final digits = input.replaceAll(RegExp(r'[\s-]'), '');
    return RegExp('^[0-9]{$codeLength}\$').hasMatch(digits) ? digits : null;
  }

  /// "1234 5678": how the host shows it.
  static String formatCode(String code) =>
      code.length == codeLength ? '${code.substring(0, 4)} ${code.substring(4)}' : code;

  /// A fresh session id for one run.
  static Uint8List newSessionId([Random? random]) {
    final source = random ?? Random.secure();
    return Uint8List.fromList(List<int>.generate(16, (_) => source.nextInt(256)));
  }

  static Uint8List channelIdentifier({required String hostDeviceId, required String remoteDeviceId}) =>
      CPace.lvCat([utf8.encode(_channelLabel), utf8.encode(hostDeviceId), utf8.encode(remoteDeviceId)]);

  /// The long-term pairing key: HKDF-SHA256 over the session key, salted
  /// with the session id. 32 bytes, one HMAC block.
  static Uint8List pairingKey(List<int> isk, List<int> sid) {
    final prk = crypto.Hmac(crypto.sha256, sid).convert(isk).bytes;
    final okm = crypto.Hmac(crypto.sha256, prk).convert([...utf8.encode('plebz-remote-pairing-key-v1'), 1]).bytes;
    return Uint8List.fromList(okm);
  }
}

/// The remote's side of one run (CPace initiator A).
class RemotePairingInitiator {
  RemotePairingInitiator({
    required String code,
    required this.sid,
    required String hostDeviceId,
    required String remoteDeviceId,
    Random? random,
  }) : _scalar = CPace.sampleScalar(random) {
    final generator = CPace.calculateGenerator(
      prs: utf8.encode(code),
      ci: RemotePairingHandshake.channelIdentifier(hostDeviceId: hostDeviceId, remoteDeviceId: remoteDeviceId),
      sid: sid,
    );
    share = CPace.scalarMult(_scalar, generator);
  }

  final List<int> sid;
  final Uint8List _scalar;

  /// Ya, sent to the host.
  late final Uint8List share;

  /// Checks the host's answer. Null when the host's share is invalid or its
  /// tag does not match — a wrong code, or someone else in the middle.
  /// Otherwise this side's tag (to send back) and the pairing key.
  ({Uint8List tag, Uint8List pairingKey})? finish({required List<int> hostShare, required List<int> hostTag}) {
    final k = CPace.scalarMultVfy(_scalar, hostShare);
    if (k == null) return null;
    final isk = CPace.intermediateSessionKey(sid: sid, k: k, ya: share, ada: const [], yb: hostShare, adb: const []);
    final macKey = CPace.confirmationKey(sid, isk);
    if (!CPace.tagsEqual(CPace.confirmationTag(macKey, hostShare, const []), hostTag)) return null;
    return (
      tag: CPace.confirmationTag(macKey, share, const []),
      pairingKey: RemotePairingHandshake.pairingKey(isk, sid),
    );
  }
}

/// The host's side of one run (CPace responder B).
class RemotePairingResponder {
  RemotePairingResponder({
    required String code,
    required this.sid,
    required String hostDeviceId,
    required String remoteDeviceId,
    Random? random,
  }) : _scalar = CPace.sampleScalar(random),
       _generator = CPace.calculateGenerator(
         prs: utf8.encode(code),
         ci: RemotePairingHandshake.channelIdentifier(hostDeviceId: hostDeviceId, remoteDeviceId: remoteDeviceId),
         sid: sid,
       );

  final List<int> sid;
  final Uint8List _scalar;
  final Uint8List _generator;
  Uint8List? _macKey;
  Uint8List? _remoteShare;
  Uint8List? _isk;

  /// Answers the remote's share: this side's share and confirmation tag, or
  /// null when the remote's share is a low-order point.
  ({Uint8List share, Uint8List tag})? respond(List<int> remoteShare) {
    final share = CPace.scalarMult(_scalar, _generator);
    final k = CPace.scalarMultVfy(_scalar, remoteShare);
    if (k == null) return null;
    final isk = CPace.intermediateSessionKey(sid: sid, k: k, ya: remoteShare, ada: const [], yb: share, adb: const []);
    _isk = isk;
    _remoteShare = Uint8List.fromList(remoteShare);
    _macKey = CPace.confirmationKey(sid, isk);
    return (share: share, tag: CPace.confirmationTag(_macKey!, share, const []));
  }

  /// The remote's tag: the pairing key when it matches, null otherwise.
  Uint8List? verify(List<int> remoteTag) {
    final macKey = _macKey;
    final remoteShare = _remoteShare;
    final isk = _isk;
    if (macKey == null || remoteShare == null || isk == null) return null;
    if (!CPace.tagsEqual(CPace.confirmationTag(macKey, remoteShare, const []), remoteTag)) return null;
    return RemotePairingHandshake.pairingKey(isk, sid);
  }
}

/// What the host shows while a phone pairs: the code, and who asked for it.
class RemotePairingPrompt {
  const RemotePairingPrompt({
    required this.code,
    required this.deviceName,
    required this.platform,
    required this.expiresAt,
  });

  final String code;
  final String deviceName;
  final String platform;
  final DateTime expiresAt;
}
