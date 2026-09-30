import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The zap's freeze is a *call-site* property: [FirstFrameGate] behaves the
/// same either way, and the screen that would prove it needs a live session,
/// a native player and a server. So the invariant is stated against the source
/// — which is also where it was lost once already, silently, to an upstream
/// merge that rewrote this function around its own full reset.
void main() {
  test('a live zap never clears UI readiness, so the last frame stays up', () {
    final source = File('lib/screens/video_player/parts/live_tv.dart').readAsStringSync();

    expect(
      source,
      contains('_firstFrame.resetRenderedForAttempt()'),
      reason: 'a new stream owns the reporting latch from the zap onwards',
    );
    expect(
      source,
      isNot(contains('_firstFrame.reset()')),
      reason:
          'the full reset drops uiReady, and Video then paints its opaque backing over a surface '
          'that still holds the outgoing channel — the black this freeze exists to avoid',
    );
  });
}
