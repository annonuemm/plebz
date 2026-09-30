import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/mpv/models.dart';
import 'package:plezy/mpv/player/platform/player_android.dart';
import 'package:plezy/services/settings_service.dart';

import '../test_helpers/mock_player_channels.dart';
import '../test_helpers/prefs.dart';

/// A picture drawn beside other content is a Flutter texture, and the player
/// has to be told so before it builds its video output. A surface of its own
/// cannot be ordered against the Flutter view finely enough to sit in a box:
/// five attempts at that produced a black window with the sound running.
Future<MethodCall> _captureInitialize({bool inline = false}) async {
  late MethodCall initialize;
  await withMockPlayerChannels(
    methodChannelName: 'com.plezy/exo_player',
    eventChannelName: 'com.plezy/exo_player/events',
    methodHandler: (call) async {
      if (call.method == 'initialize') {
        initialize = call;
        return true;
      }
      // The texture is asked for before initialize; the id it answers with is
      // what the widget renders.
      if (call.method == 'createTextureOutput') return 7;
      return null;
    },
    testBody: () async {
      final player = PlayerAndroid();
      try {
        player.inlineSurface = inline;
        await player.open(const Media('https://example.test/a.mkv'), play: false);
      } finally {
        await player.dispose();
      }
    },
  );
  return initialize;
}

Map<Object?, Object?> _args(MethodCall call) => call.arguments as Map<Object?, Object?>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  test('a boxed picture says so before the surface is made', () async {
    expect(_args(await _captureInitialize(inline: true))['inlineSurface'], isTrue);
  });

  test('a full-screen picture keeps the default layer', () async {
    // A surface of its own, behind the transparent Flutter view — which is
    // what lets the controls be drawn over the picture.
    expect(_args(await _captureInitialize())['inlineSurface'], isFalse);
  });

  test('a boxed picture takes a texture, a full-screen one does not', () async {
    final calls = <String>[];
    Future<int?> run({required bool inline}) async {
      int? textureId;
      await withMockPlayerChannels(
        methodChannelName: 'com.plezy/exo_player',
        eventChannelName: 'com.plezy/exo_player/events',
        methodHandler: (call) async {
          calls.add(call.method);
          if (call.method == 'initialize') return true;
          if (call.method == 'createTextureOutput') return 7;
          return null;
        },
        testBody: () async {
          final player = PlayerAndroid();
          try {
            player.inlineSurface = inline;
            await player.open(const Media('https://example.test/a.mkv'), play: false);
            textureId = player.videoTextureId.value;
          } finally {
            await player.dispose();
          }
        },
      );
      return textureId;
    }

    expect(await run(inline: true), 7);
    expect(calls, contains('createTextureOutput'));

    calls.clear();
    expect(await run(inline: false), isNull);
    expect(calls, isNot(contains('createTextureOutput')), reason: 'full screen keeps its own surface');
  });
}
