import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:plezy/models/audio_channel_limit.dart';
import 'package:plezy/models/shader_preset.dart';
import 'package:plezy/connection/connection.dart';
import 'package:plezy/models/seerr/seerr_session.dart';
import 'package:plezy/services/credential_vault.dart';
import 'package:plezy/services/base_shared_preferences_service.dart';
import 'package:plezy/services/file_picker_service.dart';
import 'package:plezy/services/backup_crypto.dart';
import 'package:plezy/services/credential_fields.dart';
import 'package:plezy/services/iptv/iptv_source.dart' show iptvSealedFields;
import 'package:plezy/services/settings_export_service.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/trackers/tracker_constants.dart';

import '../test_helpers/prefs.dart';

JellyfinConnection _jellyfin({required String id, DateTime? createdAt}) => JellyfinConnection(
  id: id,
  baseUrl: 'https://jellyfin.example',
  serverName: 'Wohnzimmer',
  serverMachineId: 'machine-1',
  userId: 'user-1',
  userName: 'Alice',
  accessToken: 'token-abc',
  deviceId: 'device-1',
  createdAt: createdAt ?? DateTime(2026, 1, 2),
);

SeerrSession _seerrSession(String secret) => SeerrSession(
  baseUrl: 'https://seerr.example',
  method: SeerrAuthMethod.local,
  identifier: 'alice@example.com',
  secret: secret,
  cookie: 'connect.sid=abc',
  userId: 1,
  permissions: 2,
  displayName: 'Alice',
  instanceLabel: 'Seerr',
  createdAt: DateTime(2026, 1, 2).millisecondsSinceEpoch,
);

void main() {
  // These are about the backup's contents and flow; the stretching itself is
  // tested in backup_crypto_test.dart at its real cost.
  setUpAll(() => BackupCrypto.debugIterations = BackupCrypto.minIterations);
  tearDownAll(() => BackupCrypto.debugIterations = null);

  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeFilePicker picker;

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsExportService.debugBeforeImportWrite = null;
    picker = _FakeFilePicker();
    FilePickerService.setDelegateForTesting(picker);
    PackageInfo.setMockInitialValues(
      appName: 'Plezy',
      packageName: 'com.example.plezy',
      version: '1.2.3',
      buildNumber: '4',
      buildSignature: '',
    );
  });

  tearDown(() {
    SettingsExportService.debugBeforeImportWrite = null;
    FilePickerService.setDelegateForTesting(null);
  });

  group('the full backup', () {
    test('an ordinary export leaves the credentials behind', () async {
      // The line that keeps a settings file harmless: an IPTV source is a
      // panel password and a subscription address.
      final prefs = await BaseSharedPreferencesService.sharedCache();
      await prefs.setString('user_alice_iptv_sources', '[{"name":"Anbieter","password":"geheim"}]');
      await prefs.setString('user_alice_live_tv_channel_layout', '{"hiddenGroups":["DE"]}');
      await prefs.setString('iptv:src-1', '[{"id":"ard"}]');
      await prefs.setBool('enable_hardware_decoding', true);

      final plain = SettingsExportService.buildExportMap(prefs, currentUserUuid: 'alice')['prefs']! as Map;

      expect(plain.keys, contains('enable_hardware_decoding'));
      expect(plain.keys, isNot(contains('iptv_sources')));
      expect(plain.keys, isNot(contains('live_tv_channel_layout')));
      expect(plain.keys, isNot(contains('iptv:src-1')));
      expect(jsonEncode(plain), isNot(contains('geheim')));
    });

    test('a backup carries the IPTV sources, their arrangement and favourites', () async {
      final prefs = await BaseSharedPreferencesService.sharedCache();
      await prefs.setString('user_alice_iptv_sources', '[{"name":"Anbieter"}]');
      await prefs.setString('user_alice_live_tv_channel_layout', '{"hiddenGroups":["DE"]}');
      await prefs.setString('iptv:src-1', '[{"id":"ard"}]');

      final backup =
          SettingsExportService.buildExportMap(prefs, currentUserUuid: 'alice', withCredentials: true)['prefs']! as Map;

      expect(backup.keys, containsAll(['iptv_sources', 'live_tv_channel_layout', 'iptv:src-1']));
    });

    test('the Seerr login and the TMDB key ride along, and only in a backup', () async {
      final prefs = await BaseSharedPreferencesService.sharedCache();
      await prefs.setString('tmdb_api_key', 'tmdb-secret');
      await prefs.setString('user_alice_seerr_session', '{"baseUrl":"https://seerr","secret":"pw"}');

      final plain = SettingsExportService.buildExportMap(prefs, currentUserUuid: 'alice')['prefs']! as Map;
      final backup =
          SettingsExportService.buildExportMap(prefs, currentUserUuid: 'alice', withCredentials: true)['prefs']! as Map;

      expect(plain.keys, isNot(contains('tmdb_api_key')));
      expect(plain.keys, isNot(contains('seerr_session')));
      expect(backup.keys, containsAll(['tmdb_api_key', 'seerr_session']));
    });

    test('the Seerr password is re-keyed for the device that restores it', () async {
      // Stored sealed with this installation's vault key, which does not
      // travel. Carried over as-is it would be unreadable on the new device.
      final prefs = await BaseSharedPreferencesService.sharedCache();
      final sealed = await CredentialVault.protect('mein-seerr-passwort');
      await prefs.setString('user_alice_seerr_session', _seerrSession(sealed).encode());

      final exported = SettingsExportService.buildExportMap(prefs, currentUserUuid: 'alice', withCredentials: true);
      final exportedPrefs = exported['prefs']! as Map<String, dynamic>;
      await SettingsExportService.revealSecretsForExport(exportedPrefs);

      final inFile = SeerrSession.decode((exportedPrefs['seerr_session']! as Map)['value']! as String);
      expect(inFile.secret, 'mein-seerr-passwort', reason: 'out of the vault, into the encrypted file');
      expect(CredentialVault.isProtected(inFile.secret), isFalse);

      // And back in on the other side.
      await SettingsExportService.protectSecretsForImport(exportedPrefs);
      final restored = SeerrSession.decode((exportedPrefs['seerr_session']! as Map)['value']! as String);
      expect(CredentialVault.isProtected(restored.secret), isTrue);
      expect(await CredentialVault.reveal(restored.secret), 'mein-seerr-passwort');
    });

    test('a Seerr session that cannot be read is left out rather than restored broken', () async {
      final prefs = <String, dynamic>{
        'seerr_session': {'type': 'string', 'value': 'not json at all'},
      };

      await SettingsExportService.revealSecretsForExport(prefs);

      expect(prefs.keys, isNot(contains('seerr_session')));
    });

    test('restoring re-scopes the sources onto the profile doing the restoring', () async {
      // The new device has its own profile id; a source filed under the old
      // one would belong to nobody.
      final prefs = await BaseSharedPreferencesService.sharedCache();
      await prefs.setString('user_alice_iptv_sources', '[{"name":"Anbieter"}]');
      final backup = SettingsExportService.buildExportMap(prefs, currentUserUuid: 'alice', withCredentials: true);
      await prefs.remove('user_alice_iptv_sources');

      await SettingsExportService.applyImportMap(backup, prefs, currentUserUuid: 'bob', withCredentials: true);

      expect(prefs.getString('user_bob_iptv_sources'), '[{"name":"Anbieter"}]');
      expect(prefs.getString('user_alice_iptv_sources'), isNull);
    });

    test('a backup opened without admitting credentials drops them again', () async {
      // Belt and braces: the flag gates the import as well, so a file cannot
      // smuggle a credential key into an ordinary settings restore.
      final prefs = await BaseSharedPreferencesService.sharedCache();
      await prefs.setString('user_alice_iptv_sources', '[{"name":"Anbieter"}]');
      final backup = SettingsExportService.buildExportMap(prefs, currentUserUuid: 'alice', withCredentials: true);

      final result = await SettingsExportService.applyImportMap(backup, prefs, currentUserUuid: 'bob');

      expect(prefs.getString('user_bob_iptv_sources'), isNull);
      expect(result.keysSkipped, greaterThan(0));
    });

    test('servers travel as plain config and come back as connections', () async {
      final connection = _jellyfin(id: 'jf-1', createdAt: DateTime(2026, 1, 2));

      final entries = SettingsExportService.buildConnectionEntries([connection]);
      final restored = <Connection>[];
      final count = await SettingsExportService.applyConnections(entries, (c) async => restored.add(c));

      expect(count, 1);
      final back = restored.single as JellyfinConnection;
      expect(back.id, 'jf-1');
      expect(back.baseUrl, 'https://jellyfin.example');
      expect(back.accessToken, 'token-abc', reason: 'without the token the server is a name and nothing else');
      expect(back.createdAt, DateTime(2026, 1, 2));
    });

    test('a server that cannot be read costs only itself', () async {
      final good = SettingsExportService.buildConnectionEntries([_jellyfin(id: 'jf-1')]);
      final entries = [
        {'id': 'broken', 'kind': 'nonsense', 'config': <String, Object?>{}},
        'not even a map',
        ...good,
      ];

      final restored = <Connection>[];
      final count = await SettingsExportService.applyConnections(entries, (c) async => restored.add(c));

      expect(count, 1);
      expect(restored.single.id, 'jf-1');
    });

    test('a write that fails does not stop the rest', () async {
      final entries = SettingsExportService.buildConnectionEntries([_jellyfin(id: 'a'), _jellyfin(id: 'b')]);

      final count = await SettingsExportService.applyConnections(entries, (c) async {
        if (c.id == 'a') throw StateError('database busy');
      });

      expect(count, 1, reason: 'one server failing must not cost the others');
    });
  });

  group('portable settings registry', () {
    test('exports scalar and JSON-backed values and strips only the active-user library scope', () async {
      final prefs = await BaseSharedPreferencesService.sharedCache();
      await prefs.setBool('enable_hardware_decoding', true);
      await prefs.setInt('seek_time_small', 42);
      await prefs.setDouble('volume', 75.5);
      await prefs.setString('subtitle_text_color', '#FF00FF');
      await prefs.setString('user_alice_hidden_libraries', jsonEncode(['server-a:hidden']));
      await prefs.setString('user_alice_library_order', jsonEncode(['movies', 'shows']));
      await prefs.setString('user_bob_hidden_libraries', jsonEncode(['private-hidden']));
      await prefs.setString('user_bob_library_order', jsonEncode(['private-order']));

      final out = SettingsExportService.buildExportMap(prefs, currentUserUuid: 'alice', appVersion: '1.2.3');
      final exported = out['prefs'] as Map<String, dynamic>;

      expect(out['formatVersion'], SettingsExportService.formatVersion);
      expect(out['appVersion'], '1.2.3');
      expect(DateTime.tryParse(out['exportedAt'] as String), isNotNull);
      expect(exported['enable_hardware_decoding'], {'type': 'bool', 'value': true});
      expect(exported['seek_time_small'], {'type': 'int', 'value': 42});
      expect(exported['volume'], {'type': 'double', 'value': 75.5});
      expect(exported['subtitle_text_color'], {'type': 'string', 'value': '#FF00FF'});
      expect(exported['hidden_libraries'], {
        'type': 'string',
        'value': jsonEncode(['server-a:hidden']),
      });
      expect(exported['library_order'], {
        'type': 'string',
        'value': jsonEncode(['movies', 'shows']),
      });
      expect(jsonEncode(out), isNot(contains('private-hidden')));
      expect(jsonEncode(out), isNot(contains('private-order')));
    });

    test('excludes device-local download roots while preserving portable download controls', () async {
      const sourcePath = '/source-device/downloads';
      final prefs = await BaseSharedPreferencesService.sharedCache();
      await prefs.setString('custom_download_path', sourcePath);
      await prefs.setString('custom_download_path_type', 'saf');
      await prefs.setBool('download_on_wifi_only', false);

      final out = SettingsExportService.buildExportMap(prefs, currentUserUuid: 'alice');
      final exported = out['prefs'] as Map<String, dynamic>;
      final encoded = jsonEncode(out);

      expect(out['formatVersion'], 1);
      expect(exported['download_on_wifi_only'], {'type': 'bool', 'value': false});
      expect(exported, isNot(contains('custom_download_path')));
      expect(exported, isNot(contains('custom_download_path_type')));
      expect(encoded, isNot(contains(sourcePath)));
    });

    test('round-trips a custom shader selection as a portable disabled selection', () async {
      const custom = ShaderPreset(
        id: 'custom_local-only.glsl',
        name: 'Local only',
        type: ShaderPresetType.custom,
        fileName: 'local-only.glsl',
      );
      final prefs = await BaseSharedPreferencesService.sharedCache();
      await prefs.setString('custom_shader_presets', jsonEncode([custom.toJson()]));
      await prefs.setString('global_shader_preset', custom.id);

      final export = SettingsExportService.buildExportMap(prefs, currentUserUuid: 'alice');
      final exported = export['prefs'] as Map<String, dynamic>;
      expect(exported['global_shader_preset'], {'type': 'string', 'value': ShaderPreset.none.id});
      expect(exported, isNot(contains('custom_shader_presets')));
      expect(jsonEncode(export), isNot(contains(custom.fileName!)));

      await prefs.clear();
      final result = await SettingsExportService.applyImportMap(export, prefs, currentUserUuid: 'bob');

      expect(result.keysImported, 1);
      expect(result.keysSkipped, 0);
      expect(prefs.getString('global_shader_preset'), ShaderPreset.none.id);
      expect(prefs.getString('custom_shader_presets'), isNull);
    });

    test('restores disabled subtitle margins from backup and retains them after settings recreation', () async {
      final settings = await SettingsService.getInstance();
      await settings.write(SettingsService.subtitleUseMargins, false);
      final export = SettingsExportService.buildExportMap(settings.prefs, currentUserUuid: 'source-user');

      await settings.resetAllSettings();
      expect(settings.read(SettingsService.subtitleUseMargins), isTrue);

      await SettingsExportService.applyImportMap(export, settings.prefs, currentUserUuid: 'target-user');
      expect(settings.read(SettingsService.subtitleUseMargins), isFalse);

      SettingsService.resetForTesting();
      BaseSharedPreferencesService.resetForTesting();
      final recreated = await SettingsService.getInstance();
      expect(recreated.read(SettingsService.subtitleUseMargins), isFalse);
    });

    test('fails closed for unknown, credential, account, path, history, and runtime keys', () async {
      const canaries = ['SEERR-BEARER-CANARY', 'ACCOUNT-ID-CANARY', 'DEVICE-PATH-CANARY', 'RUNTIME-TIME-CANARY'];
      final prefs = await BaseSharedPreferencesService.sharedCache();
      await prefs.setBool('enable_trakt_scrobble', true);
      await prefs.setString('user_alice_seerr_session', '{"cookie":"${canaries[0]}","account":"${canaries[1]}"}');
      await prefs.setString('current_user_uuid', canaries[1]);
      await prefs.setString('custom_download_path', canaries[2]);
      await prefs.setString('custom_download_path_type', 'saf');
      await prefs.setBool('crash_reporting', true);
      await prefs.setString('custom_relay_url', 'https://${canaries[2]}.invalid');
      await prefs.setString('update_last_check_time', canaries[3]);
      await prefs.setString('watch_together_recent_rooms', canaries[1]);
      await prefs.setString('user_alice_watch_together_recent_rooms', canaries[1]);
      await prefs.setString('future_runtime_key', 'unknown');

      final out = SettingsExportService.buildExportMap(prefs, currentUserUuid: 'alice');
      final encoded = jsonEncode(out);
      final exported = out['prefs'] as Map<String, dynamic>;

      expect(exported.keys, contains('enable_trakt_scrobble'));
      expect(exported.keys, isNot(contains('seerr_session')));
      expect(exported.keys, isNot(contains('current_user_uuid')));
      expect(exported.keys, isNot(contains('custom_download_path')));
      expect(exported.keys, isNot(contains('custom_download_path_type')));
      expect(exported.keys, isNot(contains('crash_reporting')));
      expect(exported.keys, isNot(contains('custom_relay_url')));
      expect(exported.keys, isNot(contains('update_last_check_time')));
      expect(exported.keys, isNot(contains('watch_together_recent_rooms')));
      expect(exported.keys, isNot(contains('user_alice_watch_together_recent_rooms')));
      expect(exported.keys, isNot(contains('future_runtime_key')));
      for (final canary in canaries) {
        expect(encoded, isNot(contains(canary)));
      }
    });

    test('does not export any user-scoped value without an active user', () async {
      final prefs = await BaseSharedPreferencesService.sharedCache();
      await prefs.setString('user_alice_library_order', jsonEncode(['movies']));
      await prefs.setBool('enable_hdr', true);

      final exported = SettingsExportService.buildExportMap(prefs)['prefs'] as Map<String, dynamic>;

      expect(exported, contains('enable_hdr'));
      expect(exported, isNot(contains('library_order')));
    });

    test('never exports tvOS database recovery generations or payloads', () async {
      const canary = 'PROTECTED-RECOVERY-PAYLOAD-CANARY';
      final prefs = await BaseSharedPreferencesService.sharedCache();
      await prefs.setString('tvos_db_recovery_manifest_v1', '{"state":"committed"}');
      await prefs.setString('tvos_db_recovery_identity_v1', canary);
      await prefs.setString('tvos_db_recovery_pending_v1', canary);
      await prefs.setBool('enable_hdr', true);

      final export = SettingsExportService.buildExportMap(prefs, currentUserUuid: 'alice');
      final encoded = jsonEncode(export);
      final exported = export['prefs'] as Map<String, dynamic>;

      expect(exported, contains('enable_hdr'));
      expect(exported.keys.where((key) => key.startsWith('tvos_db_recovery_')), isEmpty);
      expect(encoded, isNot(contains(canary)));
    });
    test('exports cold-start string lists while rejecting lists with non-string elements', () async {
      resetSharedPreferencesForTest(
        initialAsync: {
          'tracker_library_filter_mode_trakt': 'blacklist',
          'tracker_library_filter_ids_trakt': <Object?>['srv-1:lib-a', 'srv-1:lib-b'],
          'tracker_library_filter_ids_simkl': <Object?>['ok', 7],
        },
      );
      final prefs = await BaseSharedPreferencesService.sharedCache();

      final exported =
          SettingsExportService.buildExportMap(prefs, currentUserUuid: 'alice')['prefs'] as Map<String, dynamic>;

      expect(exported['tracker_library_filter_ids_trakt'], {
        'type': 'stringList',
        'value': ['srv-1:lib-a', 'srv-1:lib-b'],
      });
      expect(exported, isNot(contains('tracker_library_filter_ids_simkl')));
    });
  });

  group('audio downmix backup compatibility', () {
    test('restores a stereo downmix backup as the stereo channel limit', () async {
      final prefs = await BaseSharedPreferencesService.sharedCache();
      final result = await SettingsExportService.applyImportMap(
        {
          'formatVersion': 1,
          'appVersion': '2.21.0',
          'prefs': {
            'audio_downmix': {'type': 'bool', 'value': true},
          },
        },
        prefs,
        currentUserUuid: 'target-user',
      );

      expect(result.keysImported, 1);
      expect(result.keysSkipped, 0);
      BaseSharedPreferencesService.resetForTesting();
      SettingsService.resetForTesting();
      final settings = await SettingsService.getInstance();
      expect(settings.read(SettingsService.audioChannelLimit), AudioChannelLimit.stereo);
    });

    test('exports an unread stereo downmix toggle as the stereo channel limit', () async {
      resetSharedPreferencesForTest(initialAsync: const {'audio_downmix': true});
      final prefs = await BaseSharedPreferencesService.sharedCache();

      expect(SettingsExportService.buildExportMap(prefs)['prefs'], {
        'audio_channel_limit': {'type': 'string', 'value': 'stereo'},
      });
    });
  });

  group('skip marker backup compatibility', () {
    for (final introAuto in [true, false]) {
      test('exports legacy intro=$introAuto identically before and after typed reads', () async {
        resetSharedPreferencesForTest(initialAsync: {'auto_skip_intro': introAuto, 'auto_skip_credits': !introAuto});
        final prefs = await BaseSharedPreferencesService.sharedCache();
        final expected = {
          'skip_intro_mode': {'type': 'string', 'value': introAuto ? 'auto' : 'button'},
          'skip_credits_mode': {'type': 'string', 'value': introAuto ? 'button' : 'auto'},
        };

        expect(SettingsExportService.buildExportMap(prefs)['prefs'], expected);
        expect(prefs.getBool('auto_skip_intro'), introAuto);
        expect(prefs.getBool('auto_skip_credits'), !introAuto);
        final settings = await SettingsService.getInstance();
        expect(settings.read(SettingsService.skipIntroMode), introAuto ? SkipMarkerMode.auto : SkipMarkerMode.button);
        expect(SettingsExportService.buildExportMap(prefs)['prefs'], expected);
        expect(settings.read(SettingsService.skipCreditsMode), introAuto ? SkipMarkerMode.button : SkipMarkerMode.auto);
        expect(SettingsExportService.buildExportMap(prefs)['prefs'], expected);
      });

      for (final target in ['empty', 'legacy', 'canonical']) {
        test('restores a 2.18.0 intro=$introAuto backup over a $target target', () async {
          resetSharedPreferencesForTest(
            initialAsync: {
              if (target == 'legacy') ...{'auto_skip_intro': !introAuto, 'auto_skip_credits': introAuto},
              if (target == 'canonical') ...{
                'skip_intro_mode': introAuto ? 'off' : 'auto',
                'skip_credits_mode': introAuto ? 'auto' : 'off',
              },
              'seek_time_small': 45,
            },
          );
          final prefs = await BaseSharedPreferencesService.sharedCache();
          final result = await SettingsExportService.applyImportMap(
            {
              'formatVersion': 1,
              'appVersion': '2.18.0',
              'prefs': {
                'auto_skip_intro': {'type': 'bool', 'value': introAuto},
                'auto_skip_credits': {'type': 'bool', 'value': !introAuto},
              },
            },
            prefs,
            currentUserUuid: 'target-user',
          );
          final expected = {
            'skip_intro_mode': {'type': 'string', 'value': introAuto ? 'auto' : 'button'},
            'skip_credits_mode': {'type': 'string', 'value': introAuto ? 'button' : 'auto'},
            'seek_time_small': {'type': 'int', 'value': 45},
          };

          expect(result.keysImported, 2);
          expect(result.keysSkipped, 0);
          expect(prefs.containsKey('auto_skip_intro'), isFalse);
          expect(prefs.containsKey('auto_skip_credits'), isFalse);
          expect(SettingsExportService.buildExportMap(prefs)['prefs'], expected);
          var settings = await SettingsService.getInstance();
          for (var read = 0; read < 2; read++) {
            expect(
              settings.read(SettingsService.skipIntroMode),
              introAuto ? SkipMarkerMode.auto : SkipMarkerMode.button,
            );
            expect(
              settings.read(SettingsService.skipCreditsMode),
              introAuto ? SkipMarkerMode.button : SkipMarkerMode.auto,
            );
          }
          BaseSharedPreferencesService.resetForTesting();
          SettingsService.resetForTesting();
          settings = await SettingsService.getInstance();
          expect(settings.read(SettingsService.skipIntroMode), introAuto ? SkipMarkerMode.auto : SkipMarkerMode.button);
          expect(
            settings.read(SettingsService.skipCreditsMode),
            introAuto ? SkipMarkerMode.button : SkipMarkerMode.auto,
          );
          expect(SettingsExportService.buildExportMap(settings.prefs)['prefs'], expected);
        });
      }
    }

    test('canonical imports replace unread legacy choices through restart and re-export', () async {
      resetSharedPreferencesForTest(initialAsync: const {'auto_skip_intro': true, 'auto_skip_credits': false});
      final prefs = await BaseSharedPreferencesService.sharedCache();
      const expected = {
        'skip_intro_mode': {'type': 'string', 'value': 'off'},
        'skip_credits_mode': {'type': 'string', 'value': 'auto'},
      };

      await SettingsExportService.applyImportMap(
        {'formatVersion': 1, 'prefs': expected},
        prefs,
        currentUserUuid: 'target-user',
      );

      expect(prefs.containsKey('auto_skip_intro'), isFalse);
      expect(prefs.containsKey('auto_skip_credits'), isFalse);
      expect(SettingsExportService.buildExportMap(prefs)['prefs'], expected);
      var settings = await SettingsService.getInstance();
      expect(settings.read(SettingsService.skipIntroMode), SkipMarkerMode.off);
      expect(settings.read(SettingsService.skipCreditsMode), SkipMarkerMode.auto);
      expect(SettingsExportService.buildExportMap(prefs)['prefs'], expected);

      BaseSharedPreferencesService.resetForTesting();
      SettingsService.resetForTesting();
      settings = await SettingsService.getInstance();
      expect(settings.read(SettingsService.skipIntroMode), SkipMarkerMode.off);
      expect(settings.read(SettingsService.skipCreditsMode), SkipMarkerMode.auto);
      expect(SettingsExportService.buildExportMap(settings.prefs)['prefs'], expected);
    });

    for (final canonicalFirst in [false, true]) {
      test('canonical payload precedence is independent of order: first=$canonicalFirst', () async {
        final prefs = await BaseSharedPreferencesService.sharedCache();
        const canonical = {
          'skip_intro_mode': {'type': 'string', 'value': 'off'},
          'skip_credits_mode': {'type': 'string', 'value': 'auto'},
        };
        const legacy = {
          'auto_skip_intro': {'type': 'bool', 'value': true},
          'auto_skip_credits': {'type': 'bool', 'value': false},
        };
        await SettingsExportService.applyImportMap(
          {
            'formatVersion': 1,
            'prefs': canonicalFirst ? {...canonical, ...legacy} : {...legacy, ...canonical},
          },
          prefs,
          currentUserUuid: 'target-user',
        );

        final settings = await SettingsService.getInstance();
        expect(settings.read(SettingsService.skipIntroMode), SkipMarkerMode.off);
        expect(settings.read(SettingsService.skipCreditsMode), SkipMarkerMode.auto);
        expect(SettingsExportService.buildExportMap(prefs)['prefs'], canonical);
      });
    }

    test('export gives coexisting canonical values precedence before any migration', () async {
      resetSharedPreferencesForTest(
        initialAsync: const {
          'auto_skip_intro': true,
          'skip_intro_mode': 'off',
          'auto_skip_credits': false,
          'skip_credits_mode': 'auto',
        },
      );
      final prefs = await BaseSharedPreferencesService.sharedCache();
      const expected = {
        'skip_intro_mode': {'type': 'string', 'value': 'off'},
        'skip_credits_mode': {'type': 'string', 'value': 'auto'},
      };

      expect(SettingsExportService.buildExportMap(prefs)['prefs'], expected);
      final settings = await SettingsService.getInstance();
      expect(settings.read(SettingsService.skipIntroMode), SkipMarkerMode.off);
      expect(settings.read(SettingsService.skipCreditsMode), SkipMarkerMode.auto);
      expect(SettingsExportService.buildExportMap(prefs)['prefs'], expected);
    });

    test('omitted logical preferences and unrelated settings remain untouched', () async {
      resetSharedPreferencesForTest(
        initialAsync: const {'auto_skip_intro': true, 'auto_skip_credits': true, 'seek_time_small': 45},
      );
      final prefs = await BaseSharedPreferencesService.sharedCache();
      await SettingsExportService.applyImportMap(
        {
          'formatVersion': 1,
          'prefs': {
            'auto_skip_intro': {'type': 'bool', 'value': false},
          },
        },
        prefs,
        currentUserUuid: 'target-user',
      );

      expect(prefs.getBool('auto_skip_credits'), isTrue);
      expect(prefs.containsKey('skip_credits_mode'), isFalse);
      expect(prefs.getInt('seek_time_small'), 45);
      final settings = await SettingsService.getInstance();
      expect(settings.read(SettingsService.skipIntroMode), SkipMarkerMode.button);
      expect(settings.read(SettingsService.skipCreditsMode), SkipMarkerMode.auto);
    });

    test('invalid legacy entries neither migrate nor retire target choices', () async {
      resetSharedPreferencesForTest(initialAsync: const {'auto_skip_intro': false, 'skip_credits_mode': 'off'});
      final prefs = await BaseSharedPreferencesService.sharedCache();
      final result = await SettingsExportService.applyImportMap(
        {
          'formatVersion': 1,
          'prefs': {
            'auto_skip_intro': {'type': 'bool', 'value': 'true'},
            'auto_skip_credits': {'type': 'string', 'value': true},
          },
        },
        prefs,
        currentUserUuid: 'target-user',
      );

      expect(result.keysImported, 0);
      expect(result.keysSkipped, 2);
      expect(prefs.getBool('auto_skip_intro'), isFalse);
      expect(prefs.containsKey('skip_intro_mode'), isFalse);
      final settings = await SettingsService.getInstance();
      expect(settings.read(SettingsService.skipIntroMode), SkipMarkerMode.button);
      expect(settings.read(SettingsService.skipCreditsMode), SkipMarkerMode.off);
    });

    test('an invalid canonical entry does not fall through to a conflicting legacy entry', () async {
      resetSharedPreferencesForTest(initialAsync: const {'skip_intro_mode': 'off'});
      final prefs = await BaseSharedPreferencesService.sharedCache();
      await SettingsExportService.applyImportMap(
        {
          'formatVersion': 1,
          'prefs': {
            'auto_skip_intro': {'type': 'bool', 'value': true},
            'skip_intro_mode': {'type': 'bool', 'value': false},
          },
        },
        prefs,
        currentUserUuid: 'target-user',
      );

      final settings = await SettingsService.getInstance();
      expect(settings.read(SettingsService.skipIntroMode), SkipMarkerMode.off);
    });

    for (final failAt in ['auto_skip_intro', 'skip_credits_mode']) {
      test('rolls back both representations when mutation fails at $failAt', () async {
        resetSharedPreferencesForTest(
          initialAsync: {
            'auto_skip_intro': true,
            if (failAt == 'auto_skip_intro') 'skip_intro_mode': 'button',
            'auto_skip_credits': false,
            'seek_time_small': 45,
          },
        );
        final prefs = await BaseSharedPreferencesService.sharedCache();
        final before = {for (final key in prefs.keys) key: prefs.get(key)};
        final exportedBefore = SettingsExportService.buildExportMap(prefs)['prefs'];
        SettingsExportService.debugBeforeImportWrite = (key) {
          if (key == failAt) throw StateError('synthetic write failure');
        };

        await expectLater(
          SettingsExportService.applyImportMap(
            {
              'formatVersion': 1,
              'prefs': {
                'skip_intro_mode': {'type': 'string', 'value': 'off'},
                'auto_skip_credits': {'type': 'bool', 'value': true},
              },
            },
            prefs,
            currentUserUuid: 'target-user',
          ),
          throwsA(isA<StateError>()),
        );

        expect({for (final key in prefs.keys) key: prefs.get(key)}, before);
        expect(SettingsExportService.buildExportMap(prefs)['prefs'], exportedBefore);
        BaseSharedPreferencesService.resetForTesting();
        SettingsService.resetForTesting();
        final restarted = await BaseSharedPreferencesService.sharedCache();
        expect({for (final key in restarted.keys) key: restarted.get(key)}, before);
        expect(SettingsExportService.buildExportMap(restarted)['prefs'], exportedBefore);
        final settings = await SettingsService.getInstance();
        expect(
          settings.read(SettingsService.skipIntroMode),
          failAt == 'auto_skip_intro' ? SkipMarkerMode.button : SkipMarkerMode.auto,
        );
        expect(settings.read(SettingsService.skipCreditsMode), SkipMarkerMode.button);
      });
    }
  });

  group('transactional import', () {
    test('validates version and structure before writing', () async {
      final prefs = await BaseSharedPreferencesService.sharedCache();

      await expectLater(
        SettingsExportService.applyImportMap({'prefs': const {}}, prefs, currentUserUuid: 'alice'),
        throwsA(isA<InvalidExportFileException>()),
      );
      await expectLater(
        SettingsExportService.applyImportMap(
          {'formatVersion': SettingsExportService.formatVersion + 1, 'prefs': const {}},
          prefs,
          currentUserUuid: 'alice',
        ),
        throwsA(isA<InvalidExportFileException>()),
      );
      await expectLater(
        SettingsExportService.applyImportMap(
          {'formatVersion': SettingsExportService.formatVersion, 'prefs': 'invalid'},
          prefs,
          currentUserUuid: 'alice',
        ),
        throwsA(isA<InvalidExportFileException>()),
      );
      expect(prefs.getBool('enable_hdr'), isNull);
    });

    test('round-trips both filter modes and IDs for every tracker service', () async {
      final prefs = await BaseSharedPreferencesService.sharedCache();

      for (final mode in TrackerLibraryFilterMode.values) {
        await prefs.clear();
        for (final service in TrackerService.values) {
          await prefs.setString(SettingsService.trackerFilterModePref(service).key, mode.name);
          await prefs.setStringList(SettingsService.trackerFilterIdsPref(service).key, [
            '${service.name}:library-a',
            '${service.name}:library-b',
          ]);
        }

        final export = SettingsExportService.buildExportMap(prefs, currentUserUuid: 'source-user');
        final exported = export['prefs'] as Map<String, dynamic>;
        for (final service in TrackerService.values) {
          final modeKey = SettingsService.trackerFilterModePref(service).key;
          final idsKey = SettingsService.trackerFilterIdsPref(service).key;
          expect(exported[modeKey], {'type': 'string', 'value': mode.name});
          expect(exported[idsKey], {
            'type': 'stringList',
            'value': ['${service.name}:library-a', '${service.name}:library-b'],
          });
        }

        await prefs.clear();
        final result = await SettingsExportService.applyImportMap(export, prefs, currentUserUuid: 'target-user');

        expect(result.keysImported, TrackerService.values.length * 2);
        expect(result.keysSkipped, 0);
        for (final service in TrackerService.values) {
          expect(prefs.getString(SettingsService.trackerFilterModePref(service).key), mode.name);
          expect(prefs.getStringList(SettingsService.trackerFilterIdsPref(service).key), [
            '${service.name}:library-a',
            '${service.name}:library-b',
          ]);
        }
      }
    });

    test('preserves an empty whitelist so import cannot broaden tracker access', () async {
      final prefs = await BaseSharedPreferencesService.sharedCache();
      for (final service in TrackerService.values) {
        await prefs.setString(
          SettingsService.trackerFilterModePref(service).key,
          TrackerLibraryFilterMode.whitelist.name,
        );
        await prefs.setStringList(SettingsService.trackerFilterIdsPref(service).key, const []);
      }

      final export = SettingsExportService.buildExportMap(prefs, currentUserUuid: 'source-user');
      await prefs.clear();
      final result = await SettingsExportService.applyImportMap(export, prefs, currentUserUuid: 'target-user');
      final settings = await SettingsService.getInstance();

      expect(result.keysImported, TrackerService.values.length * 2);
      expect(result.keysSkipped, 0);
      for (final service in TrackerService.values) {
        expect(settings.read(SettingsService.trackerFilterModePref(service)), TrackerLibraryFilterMode.whitelist);
        expect(settings.read(SettingsService.trackerFilterIdsPref(service)), isEmpty);
        expect(settings.isLibraryAllowedForTracker(service, '${service.name}:unlisted'), isFalse);
        expect(settings.isLibraryAllowedForTracker(service, null), isFalse);
      }
    });

    test('rejects tracker preference keys with unknown service suffixes', () async {
      const modeKey = 'tracker_library_filter_mode_future';
      const idsKey = 'tracker_library_filter_ids_future';
      final prefs = await BaseSharedPreferencesService.sharedCache();
      await prefs.setString(modeKey, 'local-mode');
      await prefs.setStringList(idsKey, const ['local-id']);

      final exported = SettingsExportService.buildExportMap(prefs, currentUserUuid: 'alice')['prefs'] as Map;
      expect(exported, isNot(contains(modeKey)));
      expect(exported, isNot(contains(idsKey)));

      final result = await SettingsExportService.applyImportMap(
        {
          'formatVersion': SettingsExportService.formatVersion,
          'prefs': {
            modeKey: {'type': 'string', 'value': TrackerLibraryFilterMode.whitelist.name},
            idsKey: {
              'type': 'stringList',
              'value': ['crafted-id'],
            },
          },
        },
        prefs,
        currentUserUuid: 'alice',
      );

      expect(result.keysImported, 0);
      expect(result.keysSkipped, 2);
      expect(prefs.getString(modeKey), 'local-mode');
      expect(prefs.getStringList(idsKey), ['local-id']);
    });

    test('normalizes format-v1 hidden and order string lists into JSON string storage', () async {
      final prefs = await BaseSharedPreferencesService.sharedCache();

      final result = await SettingsExportService.applyImportMap(
        {
          'formatVersion': 1,
          'prefs': {
            'hidden_libraries': {
              'type': 'stringList',
              'value': ['server-a:hidden'],
            },
            'library_order': {
              'type': 'stringList',
              'value': ['server-b:movies', 'server-a:shows'],
            },
          },
        },
        prefs,
        currentUserUuid: 'target-user',
      );

      expect(result.keysImported, 2);
      expect(result.keysSkipped, 0);
      expect(prefs.getString('user_target-user_hidden_libraries'), jsonEncode(['server-a:hidden']));
      expect(prefs.getString('user_target-user_library_order'), jsonEncode(['server-b:movies', 'server-a:shows']));
    });

    test('imports allowlisted values, re-scopes library settings, and skips unsafe entries', () async {
      const seerrCanary = 'SEERR-IMPORT-CANARY';
      final prefs = await BaseSharedPreferencesService.sharedCache();
      await prefs.setString('update_last_check_time', 'local-valid-value');
      await prefs.setString('custom_download_path', '/target/device/downloads');
      await prefs.setString('custom_download_path_type', 'file');
      await prefs.setBool('crash_reporting', false);

      final result = await SettingsExportService.applyImportMap(
        {
          'formatVersion': SettingsExportService.formatVersion,
          'prefs': {
            'enable_hardware_decoding': {'type': 'bool', 'value': true},
            'default_playback_speed': {'type': 'double', 'value': 1},
            'library_order': {
              'type': 'string',
              'value': jsonEncode(['movies']),
            },
            'library_sort_movies': {'type': 'string', 'value': '{"key":"titleSort"}'},
            'seerr_session': {'type': 'string', 'value': seerrCanary},
            'update_last_check_time': {'type': 'string', 'value': 'crafted-invalid'},
            'custom_download_path': {'type': 'string', 'value': '/source/device/downloads'},
            'custom_download_path_type': {'type': 'string', 'value': 'saf'},
            'crash_reporting': {'type': 'bool', 'value': true},
            'custom_relay_url': {'type': 'string', 'value': 'https://relay.example.test'},
            'watch_together_recent_rooms': {'type': 'string', 'value': '[]'},
            'unknown_future_key': {'type': 'bool', 'value': true},
          },
        },
        prefs,
        currentUserUuid: 'alice',
      );

      expect(result.keysImported, 4);
      expect(result.keysSkipped, 8);
      expect(prefs.getBool('enable_hardware_decoding'), isTrue);
      expect(prefs.getDouble('default_playback_speed'), 1.0);
      expect(prefs.getString('user_alice_library_order'), jsonEncode(['movies']));
      expect(prefs.getString('user_alice_library_sort_movies'), '{"key":"titleSort"}');
      expect(prefs.getString('seerr_session'), isNull);
      expect(prefs.getString('user_alice_seerr_session'), isNull);
      expect(prefs.getString('update_last_check_time'), 'local-valid-value');
      expect(prefs.getString('custom_download_path'), '/target/device/downloads');
      expect(prefs.getString('custom_download_path_type'), 'file');
      expect(prefs.getBool('crash_reporting'), isFalse);
      expect(prefs.getString('custom_relay_url'), isNull);
      expect(prefs.getString('user_alice_watch_together_recent_rooms'), isNull);
      expect(prefs.getBool('unknown_future_key'), isNull);
    });

    test('skips source download roots and preserves the target device root', () async {
      const targetPath = '/target-device/downloads';
      const sourcePath = '/source-device/downloads';
      final prefs = await BaseSharedPreferencesService.sharedCache();
      await prefs.setString('custom_download_path', targetPath);
      await prefs.setString('custom_download_path_type', 'file');
      await prefs.setBool('download_on_wifi_only', true);

      final result = await SettingsExportService.applyImportMap(
        {
          'formatVersion': 1,
          'prefs': {
            'custom_download_path': {'type': 'string', 'value': sourcePath},
            'custom_download_path_type': {'type': 'string', 'value': 'saf'},
            'download_on_wifi_only': {'type': 'bool', 'value': false},
          },
        },
        prefs,
        currentUserUuid: 'alice',
      );

      expect(result.keysImported, 1);
      expect(result.keysSkipped, 2);
      expect(prefs.getBool('download_on_wifi_only'), isFalse);
      expect(prefs.getString('custom_download_path'), targetPath);
      expect(prefs.getString('custom_download_path_type'), 'file');
      expect(prefs.getString('custom_download_path'), isNot(contains(sourcePath)));
    });

    test('reports an unresolved custom shader selection as skipped', () async {
      final prefs = await BaseSharedPreferencesService.sharedCache();
      await prefs.setString('global_shader_preset', ShaderPreset.nvscalerDefault.id);

      final result = await SettingsExportService.applyImportMap(
        {
          'formatVersion': SettingsExportService.formatVersion,
          'prefs': {
            'global_shader_preset': {'type': 'string', 'value': 'custom_missing.glsl'},
          },
        },
        prefs,
        currentUserUuid: 'alice',
      );

      expect(result.keysImported, 0);
      expect(result.keysSkipped, 1);
      expect(prefs.getString('global_shader_preset'), ShaderPreset.nvscalerDefault.id);
    });

    test('skips malformed or mismatched entries before applying valid mutations', () async {
      final prefs = await BaseSharedPreferencesService.sharedCache();

      final result = await SettingsExportService.applyImportMap(
        {
          'formatVersion': SettingsExportService.formatVersion,
          'prefs': {
            'enable_hdr': {'type': 'bool', 'value': 'yes'},
            'seek_time_small': {'type': 'string', 'value': '10'},
            'volume': {'value': 50},
            'preferred_video_codec': 'not-an-entry',
            'enable_hardware_decoding': {'type': 'bool', 'value': true},
          },
        },
        prefs,
        currentUserUuid: 'alice',
      );

      expect(result.keysImported, 1);
      expect(result.keysSkipped, 4);
      expect(prefs.getBool('enable_hardware_decoding'), isTrue);
      expect(prefs.getBool('enable_hdr'), isNull);
      expect(prefs.getInt('seek_time_small'), isNull);
    });

    test('skips values that the settings screens would reject', () async {
      final prefs = await BaseSharedPreferencesService.sharedCache();

      final result = await SettingsExportService.applyImportMap(
        {
          'formatVersion': SettingsExportService.formatVersion,
          'prefs': {
            'view_mode': {'type': 'string', 'value': 'carousel'},
            'seek_time_small': {'type': 'int', 'value': 5000},
            'subtitle_text_color': {'type': 'string', 'value': 'red'},
            'keyboard_hotkeys': {'type': 'string', 'value': 'not json'},
            'seek_time_large': {'type': 'int', 'value': 45},
            'subtitle_border_color': {'type': 'string', 'value': '#102030'},
          },
        },
        prefs,
        currentUserUuid: 'alice',
      );

      expect(result.keysImported, 2);
      expect(result.keysSkipped, 4);
      expect(prefs.getString('view_mode'), isNull);
      expect(prefs.getInt('seek_time_small'), isNull);
      expect(prefs.getString('subtitle_text_color'), isNull);
      expect(prefs.getString('keyboard_hotkeys'), isNull);
      expect(prefs.getInt('seek_time_large'), 45);
      expect(prefs.getString('subtitle_border_color'), '#102030');
    });

    test('rolls every mutation back when a later preference write fails', () async {
      final prefs = await BaseSharedPreferencesService.sharedCache();
      await prefs.setBool('enable_hdr', false);
      var writes = 0;
      SettingsExportService.debugBeforeImportWrite = (_) {
        writes++;
        if (writes == 2) throw StateError('synthetic write failure');
      };

      await expectLater(
        SettingsExportService.applyImportMap(
          {
            'formatVersion': SettingsExportService.formatVersion,
            'prefs': {
              'enable_hdr': {'type': 'bool', 'value': true},
              'seek_time_small': {'type': 'int', 'value': 15},
            },
          },
          prefs,
          currentUserUuid: 'alice',
        ),
        throwsA(isA<StateError>()),
      );

      expect(prefs.getBool('enable_hdr'), isFalse);
      expect(prefs.getInt('seek_time_small'), isNull);
    });

    test('round-trips portable values across user scopes without account identifiers', () async {
      final prefs = await BaseSharedPreferencesService.sharedCache();
      await prefs.setBool('enable_hardware_decoding', true);
      await prefs.setString('user_alice_hidden_libraries', jsonEncode(['server-a:hidden']));
      await prefs.setString('user_alice_library_order', jsonEncode(['server-b:movies']));

      final export = SettingsExportService.buildExportMap(prefs, currentUserUuid: 'alice');
      expect(jsonEncode(export), isNot(contains('alice')));
      await prefs.clear();

      final result = await SettingsExportService.applyImportMap(export, prefs, currentUserUuid: 'bob');

      expect(result.keysImported, 3);
      expect(result.keysSkipped, 0);
      expect(prefs.getBool('enable_hardware_decoding'), isTrue);
      expect(prefs.getString('user_bob_hidden_libraries'), jsonEncode(['server-a:hidden']));
      expect(prefs.getString('user_bob_library_order'), jsonEncode(['server-b:movies']));
      expect(prefs.getString('user_alice_hidden_libraries'), isNull);
      expect(prefs.getString('user_alice_library_order'), isNull);
    });

    test('malicious import cannot replace any tvOS database recovery key', () async {
      const originalManifest = 'LOCAL-MANIFEST';
      const originalIdentity = 'LOCAL-IDENTITY';
      const originalPending = 'LOCAL-PENDING';
      final prefs = await BaseSharedPreferencesService.sharedCache();
      await prefs.setString('tvos_db_recovery_manifest_v1', originalManifest);
      await prefs.setString('tvos_db_recovery_identity_v1', originalIdentity);
      await prefs.setString('tvos_db_recovery_pending_v1', originalPending);

      final result = await SettingsExportService.applyImportMap(
        {
          'formatVersion': SettingsExportService.formatVersion,
          'prefs': {
            'tvos_db_recovery_manifest_v1': {'type': 'string', 'value': 'MALICIOUS-MANIFEST'},
            'tvos_db_recovery_identity_v1': {'type': 'string', 'value': 'MALICIOUS-IDENTITY'},
            'tvos_db_recovery_pending_v1': {'type': 'string', 'value': 'MALICIOUS-PENDING'},
          },
        },
        prefs,
        currentUserUuid: 'alice',
      );

      expect(result.keysImported, 0);
      expect(result.keysSkipped, 3);
      expect(prefs.getString('tvos_db_recovery_manifest_v1'), originalManifest);
      expect(prefs.getString('tvos_db_recovery_identity_v1'), originalIdentity);
      expect(prefs.getString('tvos_db_recovery_pending_v1'), originalPending);
    });
  });

  group('file orchestration', () {
    Future<void> seedActiveProfile() async {
      final prefs = await BaseSharedPreferencesService.sharedCache();
      await prefs.setString('active_app_profile_id', 'profile-a');
      await prefs.setBool('enable_hdr', true);
    }

    Uint8List importBytes({bool enableHdr = false}) {
      return Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'formatVersion': SettingsExportService.formatVersion,
            'prefs': {
              'enable_hdr': {'type': 'bool', 'value': enableHdr},
            },
          }),
        ),
      );
    }

    test('exports captured JSON bytes with package version and requested file contract', () async {
      await seedActiveProfile();
      picker.saveResult = '/tmp/plezy-settings.json';

      final path = await SettingsExportService.exportToFile();

      expect(path, '/tmp/plezy-settings.json');
      expect(picker.lastSaveName, matches(RegExp(r'^plezy-settings-\d{8}\.json$')));
      expect(picker.lastSaveExtensions, ['json']);
      final decoded = jsonDecode(utf8.decode(picker.lastSaveBytes!)) as Map<String, dynamic>;
      expect(decoded['appVersion'], '1.2.3');
      expect((decoded['prefs'] as Map)['enable_hdr'], {'type': 'bool', 'value': true});
    });

    test('a backup makes the round trip: settings, IPTV and servers', () async {
      await seedActiveProfile();
      final prefs = await BaseSharedPreferencesService.sharedCache();
      await prefs.setString('user_profile-a_iptv_sources', '[{"name":"Anbieter","password":"geheim"}]');
      picker.saveResult = '/tmp/plesy-backup.json';

      final path = await SettingsExportService.exportBackupToFile(
        password: 'ein gutes passwort',
        readConnections: () async => [_jellyfin(id: 'jf-1')],
      );

      expect(path, '/tmp/plesy-backup.json');
      expect(picker.lastSaveName, matches(RegExp(r'^plesy-backup-\d{8}\.json$')));
      final written = utf8.decode(picker.lastSaveBytes!);
      expect(written, isNot(contains('geheim')), reason: 'the file is sealed, not merely zipped');
      expect(written, isNot(contains('token-abc')));
      expect(jsonDecode(written), containsPair('contains', ['settings', 'servers', 'iptv']));

      // Now the other device: nothing of this installation left behind.
      await prefs.remove('user_profile-a_iptv_sources');
      await prefs.setBool('enable_hdr', false);
      picker.pickResult = FilePickerResult([
        PlatformFile(name: 'backup.json', size: picker.lastSaveBytes!.length, bytes: picker.lastSaveBytes),
      ]);
      final restored = <Connection>[];

      final result = await SettingsExportService.importFromFile(
        askPassword: () async => 'ein gutes passwort',
        writeConnection: (connection) async => restored.add(connection),
      );

      expect(result!.connectionsImported, 1);
      expect(restored.single.id, 'jf-1');
      // Restored sealed with this device's vault, and opening to the same password.
      final restoredSources = prefs.getString('user_profile-a_iptv_sources')!;
      expect(restoredSources, isNot(contains('geheim')));
      final opened = await CredentialFields.reveal(
        Map<String, Object?>.from((jsonDecode(restoredSources) as List).single as Map),
        iptvSealedFields,
      );
      expect(opened.json, {'name': 'Anbieter', 'password': 'geheim'});
      expect(prefs.getBool('enable_hdr'), isTrue);
    });

    test('the shared Download folder of every volume comes first', () async {
      // Derived from the app's own folder on each volume, so a USB stick is
      // found the same way as internal storage — and the removable one is
      // offered first, because that is what a backup is carried on.
      final paths = SettingsExportService.publicDownloadPathsFrom([
        '/storage/emulated/0/Android/data/com.plesy/files',
        '/storage/1A2B-3C4D/Android/data/com.plesy/files',
      ]);

      expect(paths, ['/storage/1A2B-3C4D/Download', '/storage/emulated/0/Download']);
    });

    test('a path that names no volume yields no download folder', () async {
      expect(SettingsExportService.publicDownloadPathsFrom(['/data/user/0/com.plesy/app_flutter']), isEmpty);
    });

    test('a folder that refuses the file hands it to the next one', () async {
      // Whether the shared folder accepts a write depends on the Android
      // version; the fall has to be caught rather than predicted.
      final root = await Directory.systemTemp.createTemp('plesy-backup-fallback-');
      addTearDown(() async {
        await Process.run('chmod', ['700', p.join(root.path, 'closed')]);
        await root.delete(recursive: true);
      });
      final closed = await Directory(p.join(root.path, 'closed')).create();
      await Process.run('chmod', ['500', closed.path]);
      final open = await Directory(p.join(root.path, 'open')).create();

      final written = await SettingsExportService.writeToFirstWritable(
        [closed, open],
        'plesy-backup-20260905.json',
        Uint8List.fromList(utf8.encode('{}')),
      );

      expect(p.dirname(written), open.path);
      expect(File(written).readAsStringSync(), '{}');
    });

    test('nowhere to write is an error that names the problem', () async {
      final root = await Directory.systemTemp.createTemp('plesy-backup-nowhere-');
      addTearDown(() async {
        await Process.run('chmod', ['700', p.join(root.path, 'closed')]);
        await root.delete(recursive: true);
      });
      final closed = await Directory(p.join(root.path, 'closed')).create();
      await Process.run('chmod', ['500', closed.path]);

      await expectLater(
        SettingsExportService.writeToFirstWritable([closed], 'x.json', Uint8List(0)),
        throwsA(isA<SettingsExportException>()),
      );
    });

    test('a backup is restored from a path, the way a television has to', () async {
      // No document picker there: the file is put in place by hand and read
      // from where it lies.
      await seedActiveProfile();
      final prefs = await BaseSharedPreferencesService.sharedCache();
      await prefs.setString('user_profile-a_iptv_sources', '[{"name":"Anbieter"}]');
      picker.saveResult = '/tmp/plesy-backup.json';
      await SettingsExportService.exportBackupToFile(
        password: 'pw',
        readConnections: () async => [_jellyfin(id: 'jf-1')],
      );
      final directory = await Directory.systemTemp.createTemp('plesy-backup-path-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File(p.join(directory.path, 'plesy-backup-20260905.json'));
      await file.writeAsBytes(picker.lastSaveBytes!);
      await prefs.remove('user_profile-a_iptv_sources');
      final restored = <Connection>[];

      final result = await SettingsExportService.importFromPath(
        file.path,
        askPassword: () async => 'pw',
        writeConnection: (connection) async => restored.add(connection),
      );

      expect(result!.connectionsImported, 1);
      expect(prefs.getString('user_profile-a_iptv_sources'), '[{"name":"Anbieter"}]');
      expect(picker.pickCalls, 0, reason: 'no picker was opened');
    });

    test('a path that holds no file is named as unreadable', () async {
      await seedActiveProfile();

      await expectLater(
        SettingsExportService.importFromPath('/definitely/not/here.json'),
        throwsA(isA<InvalidExportFileException>()),
      );
    });

    test('the wrong password is refused, and nothing is written', () async {
      await seedActiveProfile();
      picker.saveResult = '/tmp/plesy-backup.json';
      await SettingsExportService.exportBackupToFile(
        password: 'richtig',
        readConnections: () async => [_jellyfin(id: 'jf-1')],
      );
      final prefs = await BaseSharedPreferencesService.sharedCache();
      await prefs.setBool('enable_hdr', false);
      picker.pickResult = FilePickerResult([
        PlatformFile(name: 'backup.json', size: picker.lastSaveBytes!.length, bytes: picker.lastSaveBytes),
      ]);
      final restored = <Connection>[];

      await expectLater(
        SettingsExportService.importFromFile(
          askPassword: () async => 'falsch',
          writeConnection: (connection) async => restored.add(connection),
        ),
        throwsA(isA<WrongBackupPasswordException>()),
      );
      expect(restored, isEmpty);
      expect(prefs.getBool('enable_hdr'), isFalse, reason: 'a refused backup changes nothing');
    });

    test('cancelling the password prompt cancels the restore', () async {
      await seedActiveProfile();
      picker.saveResult = '/tmp/plesy-backup.json';
      await SettingsExportService.exportBackupToFile(password: 'pw', readConnections: () async => const []);
      picker.pickResult = FilePickerResult([
        PlatformFile(name: 'backup.json', size: picker.lastSaveBytes!.length, bytes: picker.lastSaveBytes),
      ]);

      expect(await SettingsExportService.importFromFile(askPassword: () async => null), isNull);
    });

    test('a settings file still imports without a password being asked for', () async {
      // The older, unprotected export has to keep working — and must never
      // prompt, which would be a question with no answer.
      await seedActiveProfile();
      final bytes = importBytes(enableHdr: true);
      picker.pickResult = FilePickerResult([PlatformFile(name: 's.json', size: bytes.length, bytes: bytes)]);
      var asked = false;

      final result = await SettingsExportService.importFromFile(
        askPassword: () async {
          asked = true;
          return 'pw';
        },
      );

      expect(asked, isFalse);
      expect(result!.connectionsImported, 0);
      expect(result.keysImported, greaterThan(0));
    });

    test('a backup needs a password to be written at all', () async {
      await seedActiveProfile();

      await expectLater(
        SettingsExportService.exportBackupToFile(password: '', readConnections: () async => const []),
        throwsA(isA<SettingsExportException>()),
      );
    });

    test('save cancellation and failure release the picker guard for a later operation', () async {
      await seedActiveProfile();
      picker.saveResult = null;
      expect(await SettingsExportService.exportToFile(), isNull);

      picker.saveError = PlatformException(code: 'save_failed');
      await expectLater(SettingsExportService.exportToFile(), throwsA(isA<PlatformException>()));

      picker.saveError = null;
      picker.saveResult = '/tmp/recovered.json';
      expect(await SettingsExportService.exportToFile(), '/tmp/recovered.json');
      expect(picker.saveCalls, 3);
    });

    test('imports in-memory bytes and path-backed files', () async {
      await seedActiveProfile();
      final prefs = await BaseSharedPreferencesService.sharedCache();
      picker.pickResult = FilePickerResult([PlatformFile(name: 'settings.json', size: 1, bytes: importBytes())]);

      final memoryResult = await SettingsExportService.importFromFile();
      expect(memoryResult?.keysImported, 1);
      expect(prefs.getBool('enable_hdr'), isFalse);

      final directory = await Directory.systemTemp.createTemp('plezy-settings-import-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/settings.json');
      await file.writeAsBytes(importBytes(enableHdr: true));
      picker.pickResult = FilePickerResult([
        PlatformFile(name: 'settings.json', size: await file.length(), path: file.path),
      ]);

      final pathResult = await SettingsExportService.importFromFile();
      expect(pathResult?.keysImported, 1);
      expect(prefs.getBool('enable_hdr'), isTrue);
    });

    test('picker cancellation, malformed input, and unreadable path release the guard', () async {
      await seedActiveProfile();
      picker.pickResult = null;
      expect(await SettingsExportService.importFromFile(), isNull);

      picker.pickResult = FilePickerResult([
        PlatformFile(name: 'bad.json', size: 1, bytes: Uint8List.fromList(utf8.encode('{bad'))),
      ]);
      await expectLater(SettingsExportService.importFromFile(), throwsA(isA<InvalidExportFileException>()));

      picker.pickResult = FilePickerResult([
        PlatformFile(name: 'missing.json', size: 1, path: '/path/that/does/not/exist.json'),
      ]);
      await expectLater(SettingsExportService.importFromFile(), throwsA(isA<FileSystemException>()));

      picker.pickResult = FilePickerResult([PlatformFile(name: 'settings.json', size: 1, bytes: importBytes())]);
      expect((await SettingsExportService.importFromFile())?.keysImported, 1);
      expect(picker.pickCalls, 4);

      picker.pickError = PlatformException(code: 'pick_failed');
      await expectLater(SettingsExportService.importFromFile(), throwsA(isA<PlatformException>()));
    });

    test('missing active profile rejects before opening the picker', () async {
      await expectLater(SettingsExportService.importFromFile(), throwsA(isA<NoUserSignedInException>()));
      expect(picker.pickCalls, 0);
    });
  });
}

class _FakeFilePicker implements FilePickerDelegate {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  FilePickerResult? pickResult;
  String? saveResult;
  Object? pickError;
  Object? saveError;
  int pickCalls = 0;
  int saveCalls = 0;
  String? lastSaveName;
  List<String>? lastSaveExtensions;
  Uint8List? lastSaveBytes;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    pickCalls++;
    final error = pickError;
    if (error != null) throw error;
    return pickResult;
  }

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    saveCalls++;
    lastSaveName = fileName;
    lastSaveExtensions = allowedExtensions;
    lastSaveBytes = bytes;
    final error = saveError;
    if (error != null) throw error;
    return saveResult;
  }
}
