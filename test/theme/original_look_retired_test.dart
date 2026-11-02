import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';

import '../test_helpers/prefs.dart';

/// Plebz has two looks since 2026-11-02: "Glas – v2" and Flach. Upstream's own
/// ("Original") and the first Glas stay only for the suite
/// ([PlebzPrefs.debugOriginalLook]); these cases switch that off to see what
/// the app does.
void main() {
  setUp(() {
    PlebzPrefs.debugOriginalLook = false;
    SettingsService.resetForTesting();
  });
  tearDown(() => PlebzPrefs.debugOriginalLook = true);

  test('Glas – v2 and Flach are the only looks offered, Glas – v2 first', () {
    expect(offeredAppThemeVariants, [AppThemeVariant.glasV2, AppThemeVariant.flach]);
  });

  test('Glas – v2 is the default off a television too', () async {
    resetSharedPreferencesForTest();
    final settings = await SettingsService.getInstance();
    expect(settings.read(PlebzPrefs.appThemeVariant), AppThemeVariant.glasV2);
  });

  test('Milchglas is on until switched off', () async {
    resetSharedPreferencesForTest();
    final settings = await SettingsService.getInstance();
    expect(settings.read(PlebzPrefs.glasV2Frost), isTrue);

    await settings.write(PlebzPrefs.glasV2Frost, false);
    expect(settings.read(PlebzPrefs.glasV2Frost), isFalse);
  });

  test('a stored or restored "Original" or Glas is drawn as Glas – v2', () {
    expect(supportedAppThemeVariant(AppThemeVariant.standard), AppThemeVariant.glasV2);
    expect(supportedAppThemeVariant(AppThemeVariant.glas), AppThemeVariant.glasV2);
    expect(supportedAppThemeVariant(AppThemeVariant.flach), AppThemeVariant.flach);
  });

  test('an updated install on a look no longer offered now stores Glas – v2', () async {
    for (final stored in ['glas', 'standard', 'klar', 'ocker', 'schwarz']) {
      SettingsService.resetForTesting();
      resetSharedPreferencesForTest(initialAsync: {'plebz_last_seen_build': 897, 'app_theme_variant': stored});
      final settings = await SettingsService.getInstance();
      expect(settings.read(PlebzPrefs.appThemeVariant), AppThemeVariant.glasV2, reason: stored);
    }
  });

  test('a chosen Flach is left alone', () async {
    resetSharedPreferencesForTest(initialAsync: {'plebz_last_seen_build': 897, 'app_theme_variant': 'flach'});
    final settings = await SettingsService.getInstance();
    expect(settings.read(PlebzPrefs.appThemeVariant), AppThemeVariant.flach);
  });
}
