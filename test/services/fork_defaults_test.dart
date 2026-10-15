import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/utils/plebz_device.dart';

import '../test_helpers/prefs.dart';

/// Plebz's own defaults: the redesign on a television, "Original" elsewhere;
/// mpv's empty letterbox on Amlogic boxes.
void main() {
  setUpAll(() => LocaleSettings.setLocaleSync(AppLocale.en));

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  tearDown(() {
    TvDetectionService.setForceTVSync(false);
    PlebzDevice.debugIsAmlogic = false;
    SettingsService.resetForTesting();
  });

  test('a television starts in the redesign', () async {
    await TvDetectionService.getInstance(forceTv: true);
    TvDetectionService.setForceTVSync(true);

    expect(SettingsService.instance.read(PlebzPrefs.appThemeVariant), AppThemeVariant.glas);
  });

  test('a phone, tablet or desktop starts in Original', () {
    TvDetectionService.setForceTVSync(false);

    expect(SettingsService.instance.read(PlebzPrefs.appThemeVariant), AppThemeVariant.standard);
    expect(t.settings.appThemeVariantStandard, 'Original');
  });

  test('a stored choice wins over the default', () async {
    await TvDetectionService.getInstance(forceTv: true);
    TvDetectionService.setForceTVSync(true);
    await SettingsService.instance.write(PlebzPrefs.appThemeVariant, AppThemeVariant.standard);

    expect(SettingsService.instance.read(PlebzPrefs.appThemeVariant), AppThemeVariant.standard);
  });

  test('an Amlogic box keeps the HDR bars empty by default', () {
    PlebzDevice.debugIsAmlogic = true;

    expect(SettingsService.instance.read(PlebzPrefs.mpvOsdPictureOnly), isTrue);
  });

  test('any other device paints them as before', () {
    PlebzDevice.debugIsAmlogic = false;

    expect(SettingsService.instance.read(PlebzPrefs.mpvOsdPictureOnly), isFalse);
  });

  test('a stored choice wins over the Amlogic default', () async {
    PlebzDevice.debugIsAmlogic = true;
    await SettingsService.instance.write(PlebzPrefs.mpvOsdPictureOnly, false);

    expect(SettingsService.instance.read(PlebzPrefs.mpvOsdPictureOnly), isFalse);
  });
}
