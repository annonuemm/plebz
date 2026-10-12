import 'dart:async' show unawaited;
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:window_manager/window_manager.dart' show windowManager;
import '../mixins/disposable_change_notifier_mixin.dart';
import '../services/native_window_service.dart';
import '../services/settings_binding_owner.dart';
import '../services/settings_service.dart' as settings;
import '../theme/glass_edge_spin.dart';
import '../theme/mono_theme.dart';
import '../utils/app_logger.dart';

class ThemeProvider extends ChangeNotifier with DisposableChangeNotifierMixin, WidgetsBindingObserver {
  late final SettingsBindingOwner _settingsBinding;
  settings.ThemeMode _themeMode = settings.ThemeMode.system;
  settings.AppThemeVariant _variant = settings.AppThemeVariant.standard;
  settings.GlasAccent _glasAccent = settings.GlasAccent.eisblau;
  Color _flachAccent = flachDefaultAccent;

  /// [settings.PlebzPrefs.flachPreset]: a ready-made Flach look, or empty
  /// for the viewer's own colours.
  String _flachPreset = '';

  /// The redesigns' plain ground where one is chosen, null for the design's
  /// own — see [plainGroundFrom].
  Color? _plainGround;
  late Brightness _systemBrightness;
  bool? _windowChromeDark;

  ThemeProvider() {
    _systemBrightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    // Seed synchronously when settings are already loaded (main() initializes
    // them before runApp) so the first frame paints the persisted theme; the
    // async path below lands a microtask too late for the first build.
    final loaded = settings.SettingsService.instanceOrNull;
    if (loaded != null) {
      _themeMode = loaded.read(settings.SettingsService.themeMode);
      _variant = supportedAppThemeVariant(loaded.read(settings.PlebzPrefs.appThemeVariant));
      _glasAccent = loaded.read(settings.PlebzPrefs.glasAccent);
      _flachAccent = flachAccentFromHex(loaded.read(settings.PlebzPrefs.flachAccent));
      _flachPreset = loaded.read(settings.PlebzPrefs.flachPreset);
      _plainGround = plainGroundFrom(loaded);
      GlassEdgeSpin.instance.enabled = loaded.read(settings.PlebzPrefs.glasSpinningFocus);
    }
    applyIconDefaultsFor(_variant);
    _settingsBinding = SettingsBindingOwner(
      prefs: const [
        settings.SettingsService.themeMode,
        settings.PlebzPrefs.appThemeVariant,
        settings.PlebzPrefs.glasAccent,
        settings.PlebzPrefs.flachAccent,
        settings.PlebzPrefs.flachPreset,
        settings.PlebzPrefs.redesignOffBlack,
        settings.PlebzPrefs.redesignCustomGround,
        settings.PlebzPrefs.redesignGroundColour,
        settings.PlebzPrefs.glasSpinningFocus,
      ],
      onRefresh: (service) {
        // Not part of the theme: the edge reads the turn itself, and a switch
        // needs no rebuild of anything.
        GlassEdgeSpin.instance.enabled = service.read(settings.PlebzPrefs.glasSpinningFocus);
        _sync(
          service.read(settings.SettingsService.themeMode),
          service.read(settings.PlebzPrefs.appThemeVariant),
          glasAccent: service.read(settings.PlebzPrefs.glasAccent),
          flachAccent: flachAccentFromHex(service.read(settings.PlebzPrefs.flachAccent)),
          flachPreset: service.read(settings.PlebzPrefs.flachPreset),
          ground: (colour: plainGroundFrom(service)),
        );
      },
    );
    unawaited(_settingsBinding.bind());
    WidgetsBinding.instance.addObserver(this);
    _syncWindowChrome();
  }

  @override
  void didChangePlatformBrightness() {
    _systemBrightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    if (_themeMode == settings.ThemeMode.system) {
      _syncWindowChrome();
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
    Color? flachAccent,
    String? flachPreset,
    ({Color? colour})? ground,
    bool forceNotify = false,
  }) {
    // What this host can draw, not what the profile asked for: a redesign
    // palette reaching a Mac in a restored backup settles on the standard
    // theme rather than painting a television interface into a window.
    final variant = supportedAppThemeVariant(stored);
    final accent = glasAccent ?? _glasAccent;
    final flat = flachAccent ?? _flachAccent;
    final preset = flachPreset ?? _flachPreset;
    final plain = ground == null ? _plainGround : ground.colour;
    final changed =
        _themeMode != mode ||
        _variant != variant ||
        _glasAccent != accent ||
        _flachAccent != flat ||
        _flachPreset != preset ||
        _plainGround != plain;
    _themeMode = mode;
    _glasAccent = accent;
    _flachAccent = flat;
    _flachPreset = preset;
    _plainGround = plain;
    if (_variant != variant) {
      _variant = variant;
      // Icon defaults are statics, not part of ThemeData: they have to be
      // pointed at the new variant before the rebuild this notify triggers.
      applyIconDefaultsFor(variant);
    }
    _updateSplashTheme(mode);
    _syncWindowChrome();
    if (changed || forceNotify) safeNotifyListeners();
  }

  settings.AppThemeVariant get variant => _variant;

  settings.GlasAccent get glasAccent => _glasAccent;

  /// Flach's accent as drawn: the look's where one is chosen.
  Color get flachAccent => _activeFlachPreset?.accent ?? _flachAccent;

  /// The look Flach wears, while it is the design on show.
  FlachPreset? get _activeFlachPreset =>
      _variant == settings.AppThemeVariant.flach ? flachPresetById(_flachPreset) : null;

  /// The redesigns' plain ground as drawn: under Flach the look's own ground
  /// where one is chosen, otherwise the settings' ([plainGroundFrom]).
  Color? get _drawnPlainGround => _activeFlachPreset?.ground ?? _plainGround;

  /// The redesigns' plain ground as the settings choose it: the viewer's own
  /// colour where that is on, off-black where that is, null for the design's
  /// own. OLED is the theme mode's and decided apart from this.
  static Color? plainGroundFrom(settings.SettingsService service) {
    if (service.read(settings.PlebzPrefs.redesignCustomGround)) {
      return redesignGroundFromHex(service.read(settings.PlebzPrefs.redesignGroundColour));
    }
    return service.read(settings.PlebzPrefs.redesignOffBlack) ? redesignOffBlackGround : null;
  }

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
    Color flachAccent = flachDefaultAccent,
    Color? plainGround,
  }) => monoTheme(
    dark: true,
    oled: mode == settings.ThemeMode.oled,
    plainGround: plainGround,
    variant: variant,
    glasAccent: glasAccent,
    flachAccent: flachAccent,
  );

  /// Material equivalent of the app's own [settings.ThemeMode].
  static ThemeMode materialThemeModeFor(settings.ThemeMode mode) => switch (mode) {
    settings.ThemeMode.light => ThemeMode.light,
    settings.ThemeMode.dark => ThemeMode.dark,
    settings.ThemeMode.oled => ThemeMode.dark,
    settings.ThemeMode.system => ThemeMode.system,
  };

  ThemeData get lightTheme =>
      monoTheme(dark: false, variant: _variant, glasAccent: _glasAccent, flachAccent: flachAccent);
  ThemeData get darkTheme => darkThemeFor(
    _themeMode,
    variant: _variant,
    glasAccent: _glasAccent,
    flachAccent: flachAccent,
    plainGround: _drawnPlainGround,
  );

  ThemeMode get materialThemeMode => materialThemeModeFor(_themeMode);

  /// Whether [mode] resolves to a dark theme when the platform reports [platformBrightness].
  static bool isDarkFor(settings.ThemeMode mode, Brightness platformBrightness) => switch (mode) {
    settings.ThemeMode.light => false,
    settings.ThemeMode.dark || settings.ThemeMode.oled => true,
    settings.ThemeMode.system => platformBrightness == Brightness.dark,
  };

  bool get isDarkMode => isDarkFor(_themeMode, _systemBrightness);

  /// Themes the native window frame, which Flutter does not paint, to match the app.
  ///
  /// Neither desktop frame follows the app on its own: the GTK3 title bar on Linux keeps the GTK theme's light
  /// variant even under GNOME's dark style, and the Windows caption follows the OS app theme (#2622). macOS needs
  /// nothing: its title bar is transparent over Flutter content. Best-effort, because a frame left in the platform's
  /// own theme is the correct fallback.
  ///
  /// Static so startup can theme the frame as soon as settings load, before this provider exists.
  static void applyWindowChromeBrightness(bool dark) {
    final Future<void> applied;
    if (Platform.isLinux) {
      applied = windowManager.setBrightness(dark ? Brightness.dark : Brightness.light);
    } else if (Platform.isWindows) {
      applied = NativeWindowService.setDarkMode(dark);
    } else {
      return;
    }
    unawaited(
      applied.catchError((Object error, StackTrace stackTrace) {
        appLogger.d('Window frame theme not applied', error: error, stackTrace: stackTrace);
      }),
    );
  }

  void _syncWindowChrome() {
    if (isDisposed) return;
    final dark = isDarkMode;
    if (_windowChromeDark == dark) return;
    _windowChromeDark = dark;
    applyWindowChromeBrightness(dark);
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
        service.read(settings.PlebzPrefs.appThemeVariant),
        glasAccent: service.read(settings.PlebzPrefs.glasAccent),
        flachAccent: flachAccentFromHex(service.read(settings.PlebzPrefs.flachAccent)),
        flachPreset: service.read(settings.PlebzPrefs.flachPreset),
        ground: (colour: plainGroundFrom(service)),
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
