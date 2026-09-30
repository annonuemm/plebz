import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// The slow turn of the glass focus edge, when the viewer has switched it on
/// (`SettingsService.glasSpinningFocus`).
///
/// One turn for the whole app: every focus edge on screen reads [turn], and
/// only an edge that is showing listens. What it costs is the thing to watch.
/// A turning edge means a frame every vsync for as long as it turns — on a
/// television that is always, since something always has focus — so:
///
/// * The ticker runs only while an edge actually paints. An edge on a route
///   under the player, or under a sheet, is still mounted but never painted;
///   one tick after the last edge stopped painting, the ticker stops, and the
///   next edge to paint starts it again.
/// * Only the focused thing repaints: an edge at rest (opacity 0) never
///   listens.
/// * It holds still while keys are coming — moving along a row, or holding a
///   key down — and turns on again once they have been quiet for [settle].
///   The frames are being drawn then anyway; a glint swirling while the focus
///   jumps would only be noise.
class GlassEdgeSpin extends ChangeNotifier {
  GlassEdgeSpin._();

  static final GlassEdgeSpin instance = GlassEdgeSpin._();

  /// One full turn.
  static const period = Duration(seconds: 7);

  /// How long keys must be quiet before the edge turns again.
  static const settle = Duration(milliseconds: 450);

  bool _enabled = false;
  double _turn = 0;
  Ticker? _ticker;
  Duration _last = Duration.zero;
  Duration _quietFor = settle;
  bool _painted = false;
  bool _awaitingPaint = false;

  /// How far round the edge has turned, 0 to 1; 0 while switched off, which
  /// is the edge as it stands still.
  double get turn => _enabled ? _turn : 0;

  bool get enabled => _enabled;

  /// Whether the ticker is running, for tests.
  @visibleForTesting
  bool get isTicking => _ticker?.isActive ?? false;

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (value) {
      HardwareKeyboard.instance.addHandler(_onKey);
    } else {
      HardwareKeyboard.instance.removeHandler(_onKey);
      _stop();
      _turn = 0;
    }
    // Every showing edge repaints once: into the turn, or back to rest.
    notifyListeners();
  }

  /// Called by an edge each time it paints. Starts the turn if it had stopped.
  void notePainted() {
    if (!_enabled) return;
    _painted = true;
    final ticker = _ticker ??= Ticker(_onTick, debugLabel: 'GlassEdgeSpin');
    if (!ticker.isActive) {
      _last = Duration.zero;
      _awaitingPaint = false;
      ticker.start();
    }
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) _quietFor = Duration.zero;
    return false;
  }

  void _onTick(Duration elapsed) {
    final dt = elapsed - _last;
    _last = elapsed;
    _quietFor += dt;
    if (_quietFor < settle) {
      // Held still: keep time, turn nothing, and ask nothing of the edges.
      _awaitingPaint = false;
      return;
    }
    if (_awaitingPaint && !_painted) {
      // Asked the edges to turn last frame and none painted: none is showing.
      _stop();
      return;
    }
    _painted = false;
    _awaitingPaint = true;
    _turn = (_turn + dt.inMicroseconds / period.inMicroseconds) % 1;
    notifyListeners();
  }

  void _stop() {
    _ticker?.stop();
    _awaitingPaint = false;
  }

  @visibleForTesting
  void debugReset() {
    enabled = false;
    _ticker?.dispose();
    _ticker = null;
    _turn = 0;
    _quietFor = settle;
    _painted = false;
  }
}
