import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_logger.dart';
import 'device_channel.dart';

/// Plebz: hardware facts the fork's own defaults depend on, read once at
/// start-up (`SocVendor.kt` on Android).
abstract final class PlebzDevice {
  static bool _isAmlogic = false;

  /// Whether the device runs on an Amlogic SoC. False off Android, on a stale
  /// native build, and until [init] has run.
  static bool isAmlogic() => _isAmlogic;

  static Future<void> init() async {
    if (!Platform.isAndroid) return;
    try {
      _isAmlogic = await deviceChannel.invokeMethod<bool>('isAmlogicSoc') ?? false;
      appLogger.i('Plebz device: Amlogic SoC=$_isAmlogic');
    } on MissingPluginException {
      // Stale native build: no Amlogic-only defaults.
    } on PlatformException {
      // Query failed: no Amlogic-only defaults.
    }
  }

  @visibleForTesting
  static set debugIsAmlogic(bool value) => _isAmlogic = value;
}
