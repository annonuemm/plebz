import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/companion_remote/remote_pairing_handshake.dart';

void main() {
  ({Uint8List? remoteKey, Uint8List? hostKey}) run({required String typed, required String shown}) {
    final sid = RemotePairingHandshake.newSessionId();
    final remote = RemotePairingInitiator(code: typed, sid: sid, hostDeviceId: 'tv', remoteDeviceId: 'phone');
    final host = RemotePairingResponder(code: shown, sid: sid, hostDeviceId: 'tv', remoteDeviceId: 'phone');
    final answer = host.respond(remote.share)!;
    final finished = remote.finish(hostShare: answer.share, hostTag: answer.tag);
    return (remoteKey: finished?.pairingKey, hostKey: finished == null ? null : host.verify(finished.tag));
  }

  test('the same code pairs, and both sides hold the same key', () {
    final result = run(typed: '12345678', shown: '12345678');
    expect(result.remoteKey, isNotNull);
    expect(result.hostKey, result.remoteKey);
    expect(result.remoteKey, hasLength(32));
  });

  test('a wrong code fails on the remote, before it answers', () {
    final result = run(typed: '12345678', shown: '12345679');
    expect(result.remoteKey, isNull, reason: "the host's tag does not match");
    expect(result.hostKey, isNull);
  });

  test('each run makes a new key, even with the same code', () {
    expect(
      run(typed: '11112222', shown: '11112222').remoteKey,
      isNot(run(typed: '11112222', shown: '11112222').remoteKey),
    );
  });

  test('a run is bound to the two devices', () {
    final sid = RemotePairingHandshake.newSessionId();
    final remote = RemotePairingInitiator(code: '12345678', sid: sid, hostDeviceId: 'tv', remoteDeviceId: 'phone');
    final host = RemotePairingResponder(code: '12345678', sid: sid, hostDeviceId: 'tv', remoteDeviceId: 'laptop');
    final answer = host.respond(remote.share)!;
    expect(remote.finish(hostShare: answer.share, hostTag: answer.tag), isNull);
  });

  test("the host refuses a low-order share and a forged tag", () {
    final sid = RemotePairingHandshake.newSessionId();
    final host = RemotePairingResponder(code: '12345678', sid: sid, hostDeviceId: 'tv', remoteDeviceId: 'phone');
    expect(host.respond(Uint8List(32)), isNull);

    final remote = RemotePairingInitiator(code: '12345678', sid: sid, hostDeviceId: 'tv', remoteDeviceId: 'phone');
    host.respond(remote.share);
    expect(host.verify(Uint8List(64)), isNull);
  });

  test('codes: eight random digits, shown in two halves, typed loosely', () {
    final code = RemotePairingHandshake.newCode();
    expect(code, matches(RegExp(r'^[0-9]{8}$')));
    expect(RemotePairingHandshake.formatCode('12345678'), '1234 5678');
    expect(RemotePairingHandshake.normalizeCode(' 1234 5678 '), '12345678');
    expect(RemotePairingHandshake.normalizeCode('1234-5678'), '12345678');
    expect(RemotePairingHandshake.normalizeCode('1234567'), isNull);
    expect(RemotePairingHandshake.normalizeCode('1234567a'), isNull);
  });
}
