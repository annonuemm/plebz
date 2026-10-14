import 'dart:async';

import 'package:plezy/screens/video_player_screen.dart';

/// Suite-wide settings (Plebz). Plebz asks for a second Back before a player
/// closes; the suite's players are left with one Back, as upstream's tests
/// expect, and `player_back_again_test.dart` turns the rule on for itself.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  VideoPlayerScreenState.backAgainToExit = false;
  await testMain();
}
