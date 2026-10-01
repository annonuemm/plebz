import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/models/companion_remote/remote_command.dart';
import 'package:plezy/services/companion_remote/companion_remote_peer_service.dart';
import 'package:plezy/services/companion_remote/remote_auth_context.dart';
import 'package:plezy/services/companion_remote/remote_pairing_handshake.dart';
import 'package:plezy/services/companion_remote/remote_pairing_store.dart';

const _ioTimeout = Duration(seconds: 5);

final _account = RemoteAuthContext(
  id: 'context-1',
  backend: 'jellyfin',
  connectionId: 'connection-1',
  homeSecret: List<int>.generate(32, (index) => index),
  discoveryKey: List<int>.generate(32, (index) => 255 - index),
  clientIdentifier: 'host-client',
  userUuid: 'user-1',
  allowedUserUuids: const ['user-1'],
);

void main() {
  late RemotePairingStore tvStore;
  late RemotePairingStore phoneStore;
  late CompanionRemotePeerService tv;
  late CompanionRemotePeerService phone;
  late int port;

  setUp(() async {
    LocaleSettings.setLocaleSync(AppLocale.en);
    tvStore = RemotePairingStore.memoryForTesting(deviceId: 'tv');
    phoneStore = RemotePairingStore.memoryForTesting(deviceId: 'phone');
    tv = CompanionRemotePeerService.forTesting(pairingStore: tvStore);
    phone = CompanionRemotePeerService.forTesting(pairingStore: phoneStore);
    port = (await tv.createSessionForContexts('Wohnzimmer', 'android_tv', [_account])).port;
  });

  tearDown(() async {
    await phone.dispose();
    await tv.dispose();
  });

  Future<void> join({Future<String?> Function(String hostName)? requestPairingCode}) => phone.joinSessionWithContexts(
    'Handy',
    'android',
    '127.0.0.1:$port',
    [_account],
    authContextId: _account.id,
    expectedHostClientId: _account.clientIdentifier,
    requestPairingCode: requestPairingCode,
  );

  test('the first connect pairs with the code the host shows, then signs in with the pairing', () async {
    final prompts = <RemotePairingPrompt?>[];
    final subscription = tv.onPairingPrompt.listen(prompts.add);
    addTearDown(subscription.cancel);
    final shown = tv.onPairingPrompt.firstWhere((prompt) => prompt != null);
    String? askedBy;

    await join(
      requestPairingCode: (hostName) async {
        askedBy = hostName;
        return RemotePairingHandshake.formatCode((await shown)!.code);
      },
    ).timeout(_ioTimeout);

    expect(askedBy, 'Wohnzimmer');
    expect(prompts.first?.deviceName, 'Handy');
    expect(prompts.last, isNull, reason: 'the code leaves the screen once paired');
    final tvSide = await tvStore.pairings(RemotePairingRole.host);
    final phoneSide = await phoneStore.pairings(RemotePairingRole.remote);
    expect(tvSide.single.peerDeviceId, 'phone');
    expect(phoneSide.single.peerDeviceId, 'tv');
    expect(phoneSide.single.key, tvSide.single.key, reason: 'both derived the same key, none was sent');

    final received = tv.onCommandReceived.firstWhere((command) => command.type == RemoteCommandType.play);
    phone.sendCommand(const RemoteCommand(type: RemoteCommandType.play));
    await received.timeout(_ioTimeout);

    // The next connect asks for nothing.
    await phone.disconnect();
    await join().timeout(_ioTimeout);
    expect(phone.isConnected, isTrue);
  });

  test('a wrong code pairs nothing and leaves the host free', () async {
    final prompts = <RemotePairingPrompt?>[];
    final subscription = tv.onPairingPrompt.listen(prompts.add);
    addTearDown(subscription.cancel);
    final shown = tv.onPairingPrompt.firstWhere((prompt) => prompt != null);

    await expectLater(
      join(
        requestPairingCode: (_) async {
          final code = (await shown)!.code;
          return code == '00000000' ? '11111111' : '00000000';
        },
      ).timeout(_ioTimeout),
      throwsA(isA<RemotePeerError>().having((e) => e.message, 'message', t.companionRemote.pairing.wrongCode)),
    );
    await _waitFor(() => prompts.isNotEmpty && prompts.last == null);
    expect(await tvStore.pairings(RemotePairingRole.host), isEmpty);
    expect(await phoneStore.pairings(RemotePairingRole.remote), isEmpty);
  });

  test('without someone to type a code, an unpaired remote is refused', () async {
    await expectLater(
      join().timeout(_ioTimeout),
      throwsA(isA<RemotePeerError>().having((e) => e.message, 'message', t.companionRemote.pairing.pairingRequired)),
    );
  });

  test('cancelling the code entry ends the run on both sides', () async {
    final prompts = <RemotePairingPrompt?>[];
    final subscription = tv.onPairingPrompt.listen(prompts.add);
    addTearDown(subscription.cancel);
    await expectLater(
      join(requestPairingCode: (_) async => null).timeout(_ioTimeout),
      throwsA(isA<RemotePeerError>().having((e) => e.message, 'message', t.companionRemote.pairing.cancelled)),
    );
    await _waitFor(() => prompts.isNotEmpty && prompts.last == null);
  });

  test('a pairing removed on the host is dropped on the remote too', () async {
    final shown = tv.onPairingPrompt.firstWhere((prompt) => prompt != null);
    await join(requestPairingCode: (_) async => (await shown)!.code).timeout(_ioTimeout);
    await phone.disconnect();

    await tvStore.remove(RemotePairingRole.host, 'phone');
    await expectLater(join().timeout(_ioTimeout), throwsA(isA<RemotePeerError>()));
    await _waitFor(() async => (await phoneStore.pairings(RemotePairingRole.remote)).isEmpty);
  });

  test('a browser page cannot open the socket', () async {
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.getUrl(Uri.parse('http://127.0.0.1:$port/ws'));
    request.headers
      ..set('Connection', 'Upgrade')
      ..set('Upgrade', 'websocket')
      ..set('Sec-WebSocket-Version', '13')
      ..set('Sec-WebSocket-Key', 'dGhlIHNhbXBsZSBub25jZQ==')
      ..set('Origin', 'https://evil.example');
    final response = await request.close().timeout(_ioTimeout);
    expect(response.statusCode, HttpStatus.forbidden);
    await response.drain<void>();
  });

  test('asking for codes without ever entering one ends in a lockout', () async {
    // Each run costs an attempt until one pairs, so a device on the network
    // cannot keep putting codes on the screen.
    final strict = CompanionRemotePeerService.forTesting(pairingStore: tvStore, maxFailedAuthAttempts: 2);
    addTearDown(strict.dispose);
    final strictPort = (await strict.createSessionForContexts('Wohnzimmer', 'android_tv', [_account])).port;
    var prompts = 0;
    final subscription = strict.onPairingPrompt.listen((prompt) {
      if (prompt != null) prompts++;
    });
    addTearDown(subscription.cancel);

    Future<void> ask() => phone.joinSessionWithContexts(
      'Handy',
      'android',
      '127.0.0.1:$strictPort',
      [_account],
      authContextId: _account.id,
      requestPairingCode: (_) async => null,
    );
    for (var i = 0; i < 2; i++) {
      await expectLater(ask().timeout(_ioTimeout), throwsA(isA<RemotePeerError>()));
    }
    await expectLater(ask().timeout(_ioTimeout), throwsA(anything));
    expect(prompts, 2, reason: 'the third asker is turned away before any code is made');
  });

  test('a second phone asking while a code is up is told the host is busy', () async {
    final shown = tv.onPairingPrompt.firstWhere((prompt) => prompt != null);
    final typing = Completer<String?>();
    final first = join(requestPairingCode: (_) => typing.future);
    await shown.timeout(_ioTimeout);

    final otherStore = RemotePairingStore.memoryForTesting(deviceId: 'tablet');
    final other = CompanionRemotePeerService.forTesting(pairingStore: otherStore);
    addTearDown(other.dispose);
    await expectLater(
      other
          .joinSessionWithContexts(
            'Tablet',
            'android',
            '127.0.0.1:$port',
            [_account],
            authContextId: _account.id,
            requestPairingCode: (_) async => '12345678',
          )
          .timeout(_ioTimeout),
      throwsA(isA<RemotePeerError>().having((e) => e.message, 'message', t.companionRemote.pairing.busy)),
    );

    typing.complete((await shown)!.code);
    await first.timeout(_ioTimeout);
    expect(phone.isConnected, isTrue);
  });
}

Future<void> _waitFor(FutureOr<bool> Function() condition) async {
  final deadline = DateTime.now().add(_ioTimeout);
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition not met in time');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
