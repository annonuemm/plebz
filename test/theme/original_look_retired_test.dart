import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';

import '../test_helpers/prefs.dart';

/// Plebz has two looks since 2026-11-01: Glas and Flach. Upstream's own
/// ("Original") stays only for the suite ([PlebzPrefs.debugOriginalLook]);
/// these cases switch that off to see what the app does.
void main() {
  setUp(() {
    PlebzPrefs.debugOriginalLook = false;
    SettingsService.resetForTesting();
  });
  tearDown(() => PlebzPrefs.debugOriginalLook = true);

  test('Glas and Flach are the only looks offered', () {
    expect(offeredAppThemeVariants, [AppThemeVariant.glas, AppThemeVariant.flach]);
  });

  test('Glas is the default off a television too', () async {
    resetSharedPreferencesForTest();
    final settings = await SettingsService.getInstance();
    expect(settings.read(PlebzPrefs.appThemeVariant), AppThemeVariant.glas);
  });

  test('a stored or restored "Original" is drawn as Glas', () {
    expect(supportedAppThemeVariant(AppThemeVariant.standard), AppThemeVariant.glas);
    expect(supportedAppThemeVariant(AppThemeVariant.flach), AppThemeVariant.flach);
  });

  test('an updated install that chose "Original" or "Klar" now stores Glas', () async {
    for (final stored in ['standard', 'klar']) {
      SettingsService.resetForTesting();
      resetSharedPreferencesForTest(initialAsync: {'plebz_last_seen_build': 897, 'app_theme_variant': stored});
      final settings = await SettingsService.getInstance();
      expect(settings.read(PlebzPrefs.appThemeVariant), AppThemeVariant.glas, reason: stored);
    }
  });

  test('a chosen Flach is left alone', () async {
    resetSharedPreferencesForTest(initialAsync: {'plebz_last_seen_build': 897, 'app_theme_variant': 'flach'});
    final settings = await SettingsService.getInstance();
    expect(settings.read(PlebzPrefs.appThemeVariant), AppThemeVariant.flach);
  });
}
