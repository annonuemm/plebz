import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/models/seerr/seerr_session.dart';
import 'package:plezy/providers/iptv_sources_provider.dart';
import 'package:plezy/services/base_shared_preferences_service.dart';
import 'package:plezy/services/credential_vault.dart';
import 'package:plezy/services/iptv/iptv_live_tv_source.dart';
import 'package:plezy/services/iptv/iptv_source.dart';
import 'package:plezy/services/seerr/seerr_session_store.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/trackers/tracker_account_store.dart';
import 'package:plezy/services/trackers/tracker_constants.dart';
import 'package:plezy/services/trackers/tracker_session.dart';

import '../test_helpers/prefs.dart';

Future<String?> _raw(String key) async => (await BaseSharedPreferencesService.sharedCache()).getString(key);
Future<void> _setRaw(String key, String value) async =>
    (await BaseSharedPreferencesService.sharedCache()).setString(key, value);

void main() {
  setUp(() async {
    resetSharedPreferencesForTest();
    CredentialVault.resetKeyForTesting();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  group('tracker sessions', () {
    final store = TrackerAccountStore.forService(TrackerService.trakt);
    final session = TrackerSession(
      accessToken: 'access-abc',
      refreshToken: 'refresh-def',
      expiresAt: 4102444800,
      username: 'anna',
      createdAt: 1,
    );

    test('are stored with their tokens sealed and the rest readable', () async {
      await store.save('alice', session);
      final stored = (await _raw('user_alice_trakt_session'))!;
      expect(stored, allOf(isNot(contains('access-abc')), isNot(contains('refresh-def'))));
      expect(jsonDecode(stored), containsPair('username', 'anna'), reason: 'the repair still recognises it');

      final loaded = await store.load('alice');
      expect(loaded?.accessToken, 'access-abc');
      expect(loaded?.refreshToken, 'refresh-def');
    });

    test('one stored in the clear before is sealed on its next load', () async {
      await _setRaw('user_alice_trakt_session', session.encode());
      expect((await store.load('alice'))?.accessToken, 'access-abc');
      await Future<void>.delayed(Duration.zero);
      expect(await _raw('user_alice_trakt_session'), isNot(contains('access-abc')));
    });
  });

  group('the Seerr session cookie', () {
    const store = SeerrSessionStore();
    SeerrSession session(String cookie) => SeerrSession.decode(
      jsonEncode({
        'base_url': 'https://seerr.example.com',
        'method': 'local',
        'identifier': 'anna@example.com',
        'secret': '',
        'cookie': cookie,
        'user_id': 1,
        'permissions': 0,
        'created_at': 1,
      }),
    );

    test('is stored sealed and comes back as it was', () async {
      await store.save('alice', session('s%3Asid-123'));
      expect(await _raw('user_alice_seerr_session'), isNot(contains('sid-123')));
      expect((await store.load('alice'))?.cookie, 's%3Asid-123');
    });

    test('one stored in the clear before is sealed on its next load', () async {
      await _setRaw('user_alice_seerr_session', session('s%3Asid-123').encode());
      expect((await store.load('alice'))?.cookie, 's%3Asid-123');
      expect(await _raw('user_alice_seerr_session'), isNot(contains('sid-123')));
    });
  });

  group('IPTV sources', () {
    IptvSourcesProvider provider() {
      final p = IptvSourcesProvider(
        profileId: 'profile-1',
        buildSource: (source) =>
            IptvLiveTvSource(source, httpClient: MockClient((_) async => http.Response('#EXTM3U', 200))),
      );
      addTearDown(p.dispose);
      return p;
    }

    const source = IptvSource(
      id: 'a',
      name: 'Mein IPTV',
      kind: IptvSourceKind.m3u,
      playlistUrl: 'http://provider/get.php?username=anna&password=geheim',
      epgUrls: ['http://provider/xmltv.php?username=anna&password=geheim'],
    );

    test('keep their password and addresses sealed, and give them back whole', () async {
      final first = provider();
      await first.ensureLoaded();
      await first.save(source);
      expect(await _raw('user_profile-1_iptv_sources'), isNot(contains('geheim')));

      final second = provider();
      await second.ensureLoaded();
      expect(second.sources.single.playlistUrl, source.playlistUrl);
      expect(second.sources.single.epgUrls, source.epgUrls);
    });

    test('stored in the clear before, are sealed on their next load', () async {
      await _setRaw('user_profile-1_iptv_sources', IptvSource.encodeList([source]));
      final loaded = provider();
      await loaded.ensureLoaded();
      expect(loaded.sources.single.playlistUrl, source.playlistUrl);
      expect(await _raw('user_profile-1_iptv_sources'), isNot(contains('geheim')));
    });
  });
}
