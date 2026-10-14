import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/focus_theme.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/utils/platform_detector.dart';

import '../test_helpers/prefs.dart';

/// "Weiches Scrollen" (Plebz): an Android television glides its rows and
/// posters as the Apple TV does unless the switch is off; elsewhere Plezy's
/// quick step stays.
void main() {
  setUp(resetSharedPreferencesForTest);
  tearDown(() {
    PlatformDetector.setLayoutMode(LayoutMode.auto);
    TvDetectionService.debugSetAppleTVOverride(null);
  });

  const glide = Duration(milliseconds: 500);
  const step = Duration(milliseconds: 150);

  test('an Android television glides by default, and steps quickly with the switch off', () async {
    final settings = await SettingsService.getInstance();
    PlatformDetector.setLayoutMode(LayoutMode.tv);
    expect(FocusTheme.navigationScrollDuration(), glide);

    await settings.write(PlebzPrefs.smoothScroll, false);
    expect(FocusTheme.navigationScrollDuration(), step);
  });

  test('the Apple TV always glides; a phone, a tablet or the Mac keeps the quick step', () async {
    final settings = await SettingsService.getInstance();
    await settings.write(PlebzPrefs.smoothScroll, false);
    TvDetectionService.debugSetAppleTVOverride(true);
    expect(FocusTheme.navigationScrollDuration(), glide);

    TvDetectionService.debugSetAppleTVOverride(null);
    await settings.write(PlebzPrefs.smoothScroll, true);
    expect(FocusTheme.navigationScrollDuration(), step, reason: 'not a television');
  });
}
