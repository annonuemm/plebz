import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../utils/platform_detector.dart';
import '../settings_service.dart';
import 'ambient_feed.dart';

/// The app's own screensaver (Plebz, "Bildschirmschoner in Plebz"), for TV
/// devices that offer no way to choose a screensaver: after the viewer's time
/// without input, the app lays Plebz Ambient over itself — only while the app
/// is in front, nothing holds the screen on (a playing video) and no text is
/// being typed. Android's own slot ([AmbientFeed], `PlebzAmbientDream`) stays
/// as it is; this is an addition beside it, off until switched on.
///
/// The clock is kept here because Flutter sees every input: the remote's keys
/// (which on a TV reach Flutter before the activity's own input hooks), a
/// pointer, and the phone remote ([noteActivity]). Drawing is the Android
/// side's (`AmbientInApp`), the same stage as the system screensaver's.
class AmbientInApp with WidgetsBindingObserver {
  AmbientInApp({AmbientFeed? feed, Future<bool> Function()? screenHeld, bool Function()? typing, bool? supported})
    : feed = feed ?? AmbientFeed.instance,
      _screenHeld = screenHeld ?? (() => WakelockPlus.enabled),
      _typing = typing ?? _textFieldFocused,
      _supportedOverride = supported;

  static final AmbientInApp instance = AmbientInApp();

  /// The times the settings offer, in minutes.
  static const List<int> minuteChoices = [1, 2, 5, 10, 15, 30];

  final AmbientFeed feed;
  final Future<bool> Function() _screenHeld;
  final bool Function() _typing;
  final bool? _supportedOverride;

  bool _started = false;
  bool _enabled = false;
  Duration _delay = const Duration(minutes: 5);
  bool _hooked = false;
  bool _keptAwake = false;
  bool _showing = false;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  Timer? _timer;

  /// Counts input and changes, so a show that was on its way when the viewer
  /// pressed something does not go through.
  int _attempt = 0;

  /// Android TV only: elsewhere a phone keeps its own screen timeout, and
  /// Apple's platforms have no such slot to stand in for.
  bool get supported => _supportedOverride ?? (!kIsWeb && Platform.isAndroid && PlatformDetector.isTV());

  bool get showing => _showing;

  /// Follows the switch and the time in the settings; safe to call again.
  void start() {
    if (_started || !supported) return;
    final settings = SettingsService.instanceOrNull;
    if (settings == null) return;
    _started = true;
    final enabled = settings.listenable(PlebzPrefs.ambientInApp);
    final minutes = settings.listenable(PlebzPrefs.ambientInAppMinutes);
    void apply() => configure(
      enabled: enabled.value,
      delay: Duration(minutes: minutes.value.clamp(1, 60)),
    );
    enabled.addListener(apply);
    minutes.addListener(apply);
    apply();
  }

  /// Switches the screensaver on or off and sets its time.
  void configure({required bool enabled, required Duration delay}) {
    if (!supported) return;
    _attempt++;
    _enabled = enabled;
    _delay = delay;
    if (enabled) {
      _hook();
    } else {
      _unhook();
      _timer?.cancel();
      _timer = null;
      if (_showing) _hide();
    }
    _updateKeepAwake();
    _arm();
  }

  /// Any input the app sees: the screensaver goes, the clock starts over.
  void noteActivity() {
    if (!_enabled) return;
    _attempt++;
    if (_showing) _hide();
    _arm();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    _attempt++;
    _updateKeepAwake();
    if (state != AppLifecycleState.resumed) {
      _timer?.cancel();
      _timer = null;
      if (_showing) _hide();
      return;
    }
    _arm();
  }

  void _hook() {
    if (_hooked) return;
    _hooked = true;
    HardwareKeyboard.instance.addHandler(_onKey);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    WidgetsBinding.instance.addObserver(this);
    _lifecycle = WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    feed.onInAppClosed = _onClosed;
  }

  void _unhook() {
    if (!_hooked) return;
    _hooked = false;
    HardwareKeyboard.instance.removeHandler(_onKey);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    WidgetsBinding.instance.removeObserver(this);
    if (feed.onInAppClosed == _onClosed) feed.onInAppClosed = null;
  }

  bool _onKey(KeyEvent event) {
    noteActivity();
    return false;
  }

  void _onPointer(PointerEvent event) => noteActivity();

  /// A key ended it on the Android side.
  void _onClosed() {
    _showing = false;
    _attempt++;
    _arm();
  }

  bool get _inFront => _lifecycle == AppLifecycleState.resumed;

  void _arm() {
    _timer?.cancel();
    _timer = null;
    if (!_enabled || !_inFront || _showing) return;
    _timer = Timer(_delay, () => unawaited(_fire()));
  }

  Future<void> _fire() async {
    _timer = null;
    final attempt = _attempt;
    if (!_enabled || !_inFront || _showing) return;
    if (_typing() || await _screenHeld()) {
      if (attempt == _attempt) _arm();
      return;
    }
    await feed.flush();
    if (attempt != _attempt || !_enabled || !_inFront || _showing) return;
    _showing = true;
    final shown = await feed.showInApp();
    if (!shown) {
      _showing = false;
      if (attempt == _attempt) _arm();
    } else if (attempt != _attempt) {
      _hide();
      _arm();
    }
  }

  void _hide() {
    _showing = false;
    unawaited(feed.hideInApp());
  }

  void _updateKeepAwake() {
    final wanted = _enabled && _inFront;
    if (wanted == _keptAwake) return;
    _keptAwake = wanted;
    unawaited(feed.setKeepAwake(wanted));
  }

  static bool _textFieldFocused() {
    final context = FocusManager.instance.primaryFocus?.context;
    return context != null && context.findAncestorStateOfType<EditableTextState>() != null;
  }

  @visibleForTesting
  void debugReset() {
    _timer?.cancel();
    _timer = null;
    _unhook();
    _started = false;
    _enabled = false;
    _keptAwake = false;
    _showing = false;
    _lifecycle = AppLifecycleState.resumed;
  }
}
