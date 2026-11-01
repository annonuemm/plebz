import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/focus_theme.dart';
import 'package:plezy/services/device_performance.dart';
import 'package:plezy/utils/platform_detector.dart';

import '../test_helpers/prefs.dart';

/// Plebz: a television glides its rows and posters as the Apple TV does,
/// unless the visual effects are reduced; elsewhere Plezy's quick step stays.
void main() {
  setUp(resetSharedPreferencesForTest);
  tearDown(() {
    PlatformDetector.setLayoutMode(LayoutMode.auto);
    TvDetectionService.debugSetAppleTVOverride(null);
    DevicePerformance.debugReset();
  });

  const glide = Duration(milliseconds: 500);
  const step = Duration(milliseconds: 150);

  test('an Android television and the Apple TV glide', () {
    PlatformDetector.setLayoutMode(LayoutMode.tv);
    expect(FocusTheme.navigationScrollDuration(), glide);

    PlatformDetector.setLayoutMode(LayoutMode.auto);
    TvDetectionService.debugSetAppleTVOverride(true);
    expect(FocusTheme.navigationScrollDuration(), glide);
  });

  test('reduced visual effects keep the quick step on an Android television, not on the Apple TV', () {
    DevicePerformance.debugReset(override: VisualEffectsSetting.reduced);
    PlatformDetector.setLayoutMode(LayoutMode.tv);
    expect(FocusTheme.navigationScrollDuration(), step);

    PlatformDetector.setLayoutMode(LayoutMode.auto);
    TvDetectionService.debugSetAppleTVOverride(true);
    expect(FocusTheme.navigationScrollDuration(), glide, reason: 'as Plezy has it');
  });

  test('a phone, a tablet or the Mac keeps the quick step', () {
    expect(FocusTheme.navigationScrollDuration(), step, reason: 'not a television');
  });
}
