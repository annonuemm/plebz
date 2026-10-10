import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/strings.g.dart';
import '../../services/live_picture_handover.dart';
import '../../services/settings_service.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/setting_tile.dart';

/// "Vorschau nahtlos ins Vollbild" (Plebz): where the guide shows its live
/// preview on Android, which is the TV layout. Turning it on turns off what
/// would interrupt the picture; see [LivePictureHandover].
Widget? livePictureHandoverSettingTile() {
  if (!Platform.isAndroid || !PlatformDetector.isTV()) return null;
  return SettingSwitchTile(
    pref: SettingsService.liveTvSeamlessFullscreen,
    icon: Symbols.open_in_full_rounded,
    title: t.settings.liveTvSeamlessFullscreen,
    subtitle: t.settings.liveTvSeamlessFullscreenDescription,
    onAfterWrite: (on) async {
      if (on) await LivePictureHandover.turnOffWhatInterrupts(SettingsService.instance);
    },
  );
}

/// The prefs [livePictureSettingTiles] reads, for the builder it sits in.
const livePictureSettingPrefs = [SettingsService.liveTvSeamlessFullscreen, SettingsService.liveTvSeamlessPlanePreview];

/// The seamless switch and, while it is on, its sub-choices: the test
/// alternative on the video plane, and — while that is off — whether full
/// screen moves to the video surface. Built as plain rows (a hidden row as an
/// empty child would bend a settings group's corners), so the caller sits in
/// a builder on [livePictureSettingPrefs].
List<Widget> livePictureSettingTiles() {
  final main = livePictureHandoverSettingTile();
  if (main == null) return const [];
  final settings = SettingsService.instance;
  final seamless = settings.read(SettingsService.liveTvSeamlessFullscreen);
  final onPlane = settings.read(SettingsService.liveTvSeamlessPlanePreview);
  return [
    main,
    if (seamless)
      SettingSwitchTile(
        pref: SettingsService.liveTvSeamlessPlanePreview,
        icon: Symbols.picture_in_picture_alt_rounded,
        title: t.settings.liveTvSeamlessPlanePreview,
        subtitle: t.settings.liveTvSeamlessPlanePreviewDescription,
      ),
    if (seamless && !onPlane)
      SettingSwitchTile(
        pref: SettingsService.liveTvSeamlessWindowSurface,
        icon: Symbols.hdr_on_rounded,
        title: t.settings.liveTvSeamlessWindowSurface,
        subtitle: t.settings.liveTvSeamlessWindowSurfaceDescription,
      ),
  ];
}

/// For the live frame-rate match and live tunnelling, which the switch above
/// turns off: turning either back on turns the switch off, so the settings
/// never claim both.
Future<void> turnOffSeamlessFullscreenIf(bool on) async {
  if (on) await SettingsService.instance.write(SettingsService.liveTvSeamlessFullscreen, false);
}
