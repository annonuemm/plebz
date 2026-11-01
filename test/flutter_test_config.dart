import 'dart:async';

import 'package:plezy/screens/video_player_screen.dart';
import 'package:plezy/services/settings_service.dart' show PlebzPrefs;

/// Suite-wide settings (Plebz). Plebz asks for a second Back before a player
/// closes; the suite's players are left with one Back, as upstream's tests
/// expect, and `player_back_again_test.dart` turns the rule on for itself.
/// Upstream's own look, gone from the app, stays the suite's default off a
/// television: upstream's tests are written against it.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  VideoPlayerScreenState.backAgainToExit = false;
  PlebzPrefs.debugOriginalLook = true;
  await testMain();
}
