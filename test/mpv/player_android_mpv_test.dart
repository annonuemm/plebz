import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/mpv/player/platform/player_android_mpv.dart';

import '../test_helpers/mock_player_channels.dart';
import '../test_helpers/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(resetSharedPreferencesForTest);

  Future<List<MethodCall>> initializeWith({required bool inlineSurface}) async {
    final calls = <MethodCall>[];
    await withMockPlayerChannels(
      methodChannelName: 'com.plezy/mpv_player',
      eventChannelName: 'com.plezy/mpv_player/events',
      methodHandler: (call) async {
        calls.add(call);
        return switch (call.method) {
          'initialize' => true,
          'createTextureOutput' => 7,
          _ => null,
        };
      },
      testBody: () async {
        final player = PlayerAndroidMpv()..inlineSurface = inlineSurface;
        // Any call that needs the native core brings the init handshake with
        // it; the player has no separate initialize of its own.
        await player.setProperty('pause', 'no');
        await player.dispose();
      },
    );
    return calls;
  }

  group('the Android mpv backend and the picture in a box', () {
    test('asks for a texture and says so, so the core skips its window surface', () async {
      final calls = await initializeWith(inlineSurface: true);

      final texture = calls.indexWhere((call) => call.method == 'createTextureOutput');
      final initialize = calls.indexWhere((call) => call.method == 'initialize');
      expect(texture, isNonNegative, reason: 'a picture in the widget tree has to be a texture');
      expect(
        texture,
        lessThan(initialize),
        reason: 'the core builds its render scaffold on this answer, so it must arrive first',
      );
      expect(calls[initialize].arguments['inlineSurface'], isTrue);
    });

    test('the full-screen session keeps its own surface and asks for nothing', () async {
      final calls = await initializeWith(inlineSurface: false);

      expect(calls.map((call) => call.method), isNot(contains('createTextureOutput')));
      final initialize = calls.firstWhere((call) => call.method == 'initialize');
      expect(initialize.arguments.containsKey('inlineSurface'), isFalse);
    });
  });
}
