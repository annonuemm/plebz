import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/utils/platform_detector.dart';

import '../test_helpers/prefs.dart';

/// Plebz's own defaults: the redesign on a television, "Original" elsewhere.
void main() {
  setUpAll(() => LocaleSettings.setLocaleSync(AppLocale.en));

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  tearDown(() {
    TvDetectionService.setForceTVSync(false);
    SettingsService.resetForTesting();
  });

  test('a television starts in the redesign', () async {
    await TvDetectionService.getInstance(forceTv: true);
    TvDetectionService.setForceTVSync(true);

    expect(SettingsService.instance.read(SettingsService.appThemeVariant), AppThemeVariant.glas);
  });

  test('a phone, tablet or desktop starts in Original', () {
    TvDetectionService.setForceTVSync(false);

    expect(SettingsService.instance.read(SettingsService.appThemeVariant), AppThemeVariant.standard);
    expect(t.settings.appThemeVariantStandard, 'Original');
  });

  test('a stored choice wins over the default', () async {
    await TvDetectionService.getInstance(forceTv: true);
    TvDetectionService.setForceTVSync(true);
    await SettingsService.instance.write(SettingsService.appThemeVariant, AppThemeVariant.standard);

    expect(SettingsService.instance.read(SettingsService.appThemeVariant), AppThemeVariant.standard);
  });
}
