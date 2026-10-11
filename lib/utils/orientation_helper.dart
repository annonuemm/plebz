import 'dart:async';

import 'package:flutter/services.dart';
import 'platform_detector.dart';

class OrientationHelper {
  /// Whether the platform, not the app, owns display rotation.
  ///
  /// Cars are fixed-orientation head units, and a TV never rotates at all.
  /// Asking anyway is not a harmless no-op there: Flutter encodes
  /// [DeviceOrientation.values] as Android's `SCREEN_ORIENTATION_FULL_USER`,
  /// which is one of only two request values that make WindowManager accept a
  /// 180° display rotation — every app that leaves orientation alone has that
  /// rotation filtered out by `config_allowAllRotations`. On a TV box that does
  /// not pin rotation itself, the app alone then renders upside down (#2401).
  ///
  /// Plebz: the hardware decides, not the layout picked in the settings — a TV
  /// box set to the phone layout is still a TV that must not be asked.
  static bool get _platformOwnsOrientation => PlatformDetector.isAutomotive() || PlatformDetector.isTvDevice();

  /// Restores the app's default orientation preferences: every orientation
  /// on every handheld. Phones rotate into the landscape shell (leading
  /// navigation rail) like tablets do; the video player owns its own lock.
  ///
  /// This should be called when leaving full-screen experiences like
  /// the video player to restore the app's default orientation behavior.
  static Future<void> restoreDefaultOrientations() async {
    if (_platformOwnsOrientation) return;
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  /// Plebz: set while a live picture is on the whole screen because the phone
  /// was turned on its side. The player then follows the phone instead of
  /// pinning landscape, so turning it upright again hands the picture back to
  /// the guide's band. Cleared when the player restores the orientation.
  static bool followDeviceRotation = false;

  /// Pins playback to landscape without touching system UI, for the player's
  /// rotation-lock toggle.
  static Future<void> lockLandscapeOrientation() async {
    if (_platformOwnsOrientation) return;
    if (followDeviceRotation) {
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      return;
    }
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  /// Enters the player's full-screen presentation with rotation locked.
  static void setLandscapeOrientation() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    unawaited(lockLandscapeOrientation());
  }

  /// Restores the app's default visible system UI mode.
  ///
  /// Should be called when exiting full-screen mode.
  static Future<void> restoreSystemUI() async {
    // Explicitly show both overlays first to clear any legacy immersive flags.
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
}
