import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/strings.g.dart';
import '../../services/live_picture_handover.dart';
import '../../services/settings_service.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/setting_tile.dart';
import '../../widgets/settings_builder.dart';

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

/// Where that picture goes once it has grown to full screen: shown only while
/// the seamless switch is on, since it means nothing without it.
Widget? livePictureWindowSurfaceSettingTile() {
  if (!Platform.isAndroid || !PlatformDetector.isTV()) return null;
  return SettingValueBuilder<bool>(
    pref: SettingsService.liveTvSeamlessFullscreen,
    builder: (context, seamless, _) => !seamless
        ? const SizedBox.shrink()
        : SettingSwitchTile(
            pref: SettingsService.liveTvSeamlessWindowSurface,
            icon: Symbols.hdr_on_rounded,
            title: t.settings.liveTvSeamlessWindowSurface,
            subtitle: t.settings.liveTvSeamlessWindowSurfaceDescription,
          ),
  );
}

/// For the live frame-rate match and live tunnelling, which the switch above
/// turns off: turning either back on turns the switch off, so the settings
/// never claim both.
Future<void> turnOffSeamlessFullscreenIf(bool on) async {
  if (on) await SettingsService.instance.write(SettingsService.liveTvSeamlessFullscreen, false);
}
