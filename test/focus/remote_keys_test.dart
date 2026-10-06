import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/remote_keys.dart';

void main() {
  test('the extra remote keys', () {
    expect(classifyRemoteKey(LogicalKeyboardKey.mediaStop), RemoteKeyAction.stop);
    expect(classifyRemoteKey(LogicalKeyboardKey.info), RemoteKeyAction.info);
    expect(classifyRemoteKey(LogicalKeyboardKey.contextMenu), RemoteKeyAction.info);
    expect(classifyRemoteKey(LogicalKeyboardKey.closedCaptionToggle), RemoteKeyAction.subtitles);
    expect(classifyRemoteKey(LogicalKeyboardKey.mediaAudioTrack), RemoteKeyAction.audioTrack);
    expect(classifyRemoteKey(LogicalKeyboardKey.guide), RemoteKeyAction.channelList);
    expect(classifyRemoteKey(LogicalKeyboardKey.mediaLast), RemoteKeyAction.lastChannel);

    for (final colour in [
      LogicalKeyboardKey.colorF0Red,
      LogicalKeyboardKey.colorF1Green,
      LogicalKeyboardKey.colorF2Yellow,
      LogicalKeyboardKey.colorF3Blue,
    ]) {
      expect(classifyRemoteKey(colour), isNull, reason: 'the colour keys are the viewer\'s to assign');
    }
  });

  test('keys the player already handles are not claimed here', () {
    for (final key in [
      LogicalKeyboardKey.mediaPlayPause,
      LogicalKeyboardKey.mediaFastForward,
      LogicalKeyboardKey.channelUp,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.select,
    ]) {
      expect(classifyRemoteKey(key), isNull, reason: key.debugName);
    }
  });

  test('digits from the number row and the keypad', () {
    expect(remoteDigit(LogicalKeyboardKey.digit0), 0);
    expect(remoteDigit(LogicalKeyboardKey.digit7), 7);
    expect(remoteDigit(LogicalKeyboardKey.numpad3), 3);
    expect(remoteDigit(LogicalKeyboardKey.keyA), isNull);
  });

  test('a typed number finds its channel, leading zeros or not', () {
    final numbers = ['1', '02', null, '10', ' 7 '];
    expect(channelIndexForNumber(numbers, '2'), 1);
    expect(channelIndexForNumber(numbers, '010'), 3);
    expect(channelIndexForNumber(numbers, '7'), 4);
    expect(channelIndexForNumber(numbers, '5'), -1);
  });

  test('the letters an IR receiver sends stand in for Info and Stop on a television only', () {
    expect(classifyRemoteKey(LogicalKeyboardKey.keyX, keyboardLetters: true), RemoteKeyAction.stop);
    expect(classifyRemoteKey(LogicalKeyboardKey.keyI, keyboardLetters: true), RemoteKeyAction.info);
    expect(classifyRemoteKey(LogicalKeyboardKey.keyX), isNull);
    expect(classifyRemoteKey(LogicalKeyboardKey.keyS, keyboardLetters: true), isNull, reason: 'a player shortcut');
  });

  test('the colour keys in the order remotes print them', () {
    expect(colourKeyOf(LogicalKeyboardKey.colorF0Red), RemoteColourKey.red);
    expect(colourKeyOf(LogicalKeyboardKey.colorF1Green), RemoteColourKey.green);
    expect(colourKeyOf(LogicalKeyboardKey.colorF2Yellow), RemoteColourKey.yellow);
    expect(colourKeyOf(LogicalKeyboardKey.colorF3Blue), RemoteColourKey.blue);
    expect(colourKeyOf(LogicalKeyboardKey.info), isNull);
  });
}
