import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/settings_service.dart';

import '../test_helpers/prefs.dart';

/// Plezy's choices Plebz fixed to their default (2026-11-01): a stored one
/// is dropped at start and none of them travels in a backup.
void main() {
  setUp(SettingsService.resetForTesting);

  test('an updated install drops a stored choice once: everyone reads the default', () async {
    resetSharedPreferencesForTest(
      initialAsync: {
        'plebz_last_seen_build': 897,
        'use_global_hubs': false,
        'show_server_name_on_hubs': true,
        'remember_track_selections': false,
      },
    );
    final settings = await SettingsService.getInstance();

    expect(settings.read(SettingsService.useGlobalHubs), isTrue);
    expect(settings.read(SettingsService.showServerNameOnHubs), isFalse);
    expect(settings.read(SettingsService.rememberTrackSelections), isTrue);
  });

  test('a fresh store is left alone', () async {
    resetSharedPreferencesForTest(initialAsync: {'remember_track_selections': false});
    final settings = await SettingsService.getInstance();

    expect(settings.read(SettingsService.rememberTrackSelections), isFalse);
  });

  test('none of them is exported', () {
    final portable = SettingsService.portablePrefs.map((pref) => pref.key);
    for (final pref in PlebzPrefs.fixedToDefault) {
      expect(portable, isNot(contains(pref.key)), reason: pref.key);
    }
  });
}
