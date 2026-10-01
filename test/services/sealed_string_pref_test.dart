import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/credential_vault.dart';
import 'package:plezy/services/settings_service.dart';

import '../test_helpers/prefs.dart';

void main() {
  setUp(resetSharedPreferencesForTest);

  const pref = SettingsService.tmdbApiKey;

  test('a written key reads back as itself and lies sealed in the preferences', () async {
    final settings = await SettingsService.getInstance();

    await settings.write(pref, 'tmdb-secret');

    expect(settings.read(pref), 'tmdb-secret');
    final stored = settings.prefs.getString(pref.key)!;
    expect(CredentialVault.isProtected(stored), isTrue);
    expect(stored, isNot(contains('tmdb-secret')));
  });

  test('a key stored in clear text before 1.3.1 is sealed when it is loaded', () async {
    final settings = await SettingsService.getInstance();
    await settings.prefs.setString(pref.key, 'old-plain-key');
    expect(settings.read(pref), 'old-plain-key', reason: 'readable before the migration');

    await pref.load(settings);

    expect(CredentialVault.isProtected(settings.prefs.getString(pref.key)!), isTrue);
    expect(settings.read(pref), 'old-plain-key');
  });

  test('a sealed value written behind its back is read after a load, not from the stale copy', () async {
    final settings = await SettingsService.getInstance();
    await settings.write(pref, 'first');
    await settings.prefs.setString(pref.key, await CredentialVault.protect('second'));

    expect(settings.read(pref), isNull, reason: 'not revealed yet, and the remembered value is for another form');

    await pref.load(settings);
    expect(settings.read(pref), 'second');
  });

  test('clearing and resetting remove the key', () async {
    final settings = await SettingsService.getInstance();
    await settings.write(pref, 'tmdb-secret');

    await settings.write(pref, null);
    expect(settings.read(pref), isNull);
    expect(settings.prefs.getString(pref.key), isNull);

    await settings.write(pref, 'tmdb-secret');
    await settings.reset(pref);
    expect(settings.read(pref), isNull);
  });
}
