import 'dart:async' show unawaited;
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../mixins/disposable_change_notifier_mixin.dart';
import '../services/settings_binding_owner.dart';
import '../services/settings_service.dart' as settings;
import '../theme/glass_edge_spin.dart';
import '../theme/mono_theme.dart';

class ThemeProvider extends ChangeNotifier with DisposableChangeNotifierMixin, WidgetsBindingObserver {
  late final SettingsBindingOwner _settingsBinding;
  settings.ThemeMode _themeMode = settings.ThemeMode.system;
  settings.AppThemeVariant _variant = settings.AppThemeVariant.standard;
  settings.GlasAccent _glasAccent = settings.GlasAccent.eisblau;
  late Brightness _systemBrightness;

  ThemeProvider() {
    _systemBrightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    // Seed synchronously when settings are already loaded (main() initializes
    // them before runApp) so the first frame paints the persisted theme; the
    // async path below lands a microtask too late for the first build.
    final loaded = settings.SettingsService.instanceOrNull;
    if (loaded != null) {
      _themeMode = loaded.read(settings.SettingsService.themeMode);
      _variant = supportedAppThemeVariant(loaded.read(settings.SettingsService.appThemeVariant));
      _glasAccent = loaded.read(settings.SettingsService.glasAccent);
      GlassEdgeSpin.instance.enabled = loaded.read(settings.SettingsService.glasSpinningFocus);
    }
    applyIconDefaultsFor(_variant);
    _settingsBinding = SettingsBindingOwner(
      prefs: const [
        settings.SettingsService.themeMode,
        settings.SettingsService.appThemeVariant,
        settings.SettingsService.glasAccent,
        settings.SettingsService.glasSpinningFocus,
      ],
      onRefresh: (service) {
        // Not part of the theme: the edge reads the turn itself, and a switch
        // needs no rebuild of anything.
        GlassEdgeSpin.instance.enabled = service.read(settings.SettingsService.glasSpinningFocus);
        _sync(
          service.read(settings.SettingsService.themeMode),
          service.read(settings.SettingsService.appThemeVariant),
          glasAccent: service.read(settings.SettingsService.glasAccent),
        );
      },
    );
    unawaited(_settingsBinding.bind());
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangePlatformBrightness() {
    _systemBrightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    if (_themeMode == settings.ThemeMode.system) {
      safeNotifyListeners();
    }
  }

  @override
  void dispose() {
    _settingsBinding.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _sync(
    settings.ThemeMode mode,
    settings.AppThemeVariant stored, {
    settings.GlasAccent? glasAccent,
    bool forceNotify = false,
  }) {
    // What this host can draw, not what the profile asked for: a redesign
    // palette reaching a Mac in a restored backup settles on the standard
    // theme rather than painting a television interface into a window.
    final variant = supportedAppThemeVariant(stored);
    final accent = glasAccent ?? _glasAccent;
    final changed = _themeMode != mode || _variant != variant || _glasAccent != accent;
    _themeMode = mode;
    _glasAccent = accent;
    if (_variant != variant) {
      _variant = variant;
      // Icon defaults are statics, not part of ThemeData: they have to be
      // pointed at the new variant before the rebuild this notify triggers.
      applyIconDefaultsFor(variant);
    }
    _updateSplashTheme(mode);
    if (changed || forceNotify) safeNotifyListeners();
  }

  settings.AppThemeVariant get variant => _variant;

  settings.GlasAccent get glasAccent => _glasAccent;

  settings.ThemeMode get themeMode => _themeMode;

  /// Dark palette for [mode], honouring the OLED variant.
  ///
  /// Static so the pre-provider startup frame can resolve the same theme this
  /// provider will settle on, instead of guessing from platform brightness
  /// and flashing when the two disagree (#1833).
  static ThemeData darkThemeFor(
    settings.ThemeMode mode, {
    settings.AppThemeVariant variant = settings.AppThemeVariant.standard,
    settings.GlasAccent glasAccent = settings.GlasAccent.eisblau,
  }) => monoTheme(dark: true, oled: mode == settings.ThemeMode.oled, variant: variant, glasAccent: glasAccent);

  /// Material equivalent of the app's own [settings.ThemeMode].
  static ThemeMode materialThemeModeFor(settings.ThemeMode mode) => switch (mode) {
    settings.ThemeMode.light => ThemeMode.light,
    settings.ThemeMode.dark => ThemeMode.dark,
    settings.ThemeMode.oled => ThemeMode.dark,
    settings.ThemeMode.system => ThemeMode.system,
  };

  ThemeData get lightTheme => monoTheme(dark: false, variant: _variant, glasAccent: _glasAccent);
  ThemeData get darkTheme => darkThemeFor(_themeMode, variant: _variant, glasAccent: _glasAccent);

  ThemeMode get materialThemeMode => materialThemeModeFor(_themeMode);

  bool get isDarkMode {
    switch (_themeMode) {
      case settings.ThemeMode.light:
        return false;
      case settings.ThemeMode.dark:
        return true;
      case settings.ThemeMode.oled:
        return true;
      case settings.ThemeMode.system:
        return _systemBrightness == Brightness.dark;
    }
  }

  static const _themeChannel = MethodChannel('com.plezy/theme');

  @visibleForTesting
  Future<void> setThemeMode(settings.ThemeMode mode) async {
    if (_themeMode == mode) return;
    final service = _settingsBinding.settings ?? await settings.SettingsService.getInstance();
    await service.write(settings.SettingsService.themeMode, mode);
    if (_settingsBinding.settings == null) _sync(mode, _variant);
  }

  Future<void> reload() async {
    await _settingsBinding.bind();
    final service = _settingsBinding.settings;
    if (service != null) {
      _sync(
        service.read(settings.SettingsService.themeMode),
        service.read(settings.SettingsService.appThemeVariant),
        glasAccent: service.read(settings.SettingsService.glasAccent),
        forceNotify: true,
      );
    }
  }

  void _updateSplashTheme(settings.ThemeMode mode) {
    if (!Platform.isAndroid) return;
    final name = switch (mode) {
      settings.ThemeMode.dark => 'dark',
      settings.ThemeMode.oled => 'oled',
      settings.ThemeMode.light => 'light',
      settings.ThemeMode.system => 'system',
    };
    _themeChannel.invokeMethod('setSplashTheme', {'mode': name});
  }

  IconData get themeModeIcon {
    switch (_themeMode) {
      case settings.ThemeMode.light:
        return Symbols.light_mode_rounded;
      case settings.ThemeMode.dark:
        return Symbols.dark_mode_rounded;
      case settings.ThemeMode.oled:
        return Symbols.contrast_rounded;
      case settings.ThemeMode.system:
        return Symbols.brightness_auto_rounded;
    }
  }
}
