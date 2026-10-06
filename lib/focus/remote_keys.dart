import 'package:flutter/services.dart';

/// What the player does for a remote's extra buttons (fork addition) — the
/// ones beyond D-pad, OK, back and the transport keys of [classifyTransportKey].
///
/// Many TV remotes carry them: Stop, Info, subtitles (CC), audio track, the
/// programme guide, last channel and the digits. The four colour keys are the
/// viewer's to assign ([RemoteButtonFunction], [colourKeyOf]).
enum RemoteKeyAction {
  /// Leave the player.
  stop,

  /// Raise the controls, or lower them when they are up.
  info,

  /// Subtitles on or off.
  subtitles,

  /// The next audio track.
  audioTrack,

  /// Live TV: the channel list.
  channelList,

  /// Live TV: back to the channel watched before this one.
  lastChannel,
}

/// [keyboardLetters] adds the letters a USB IR receiver such as Flirc sends
/// for a universal remote's Info and Stop when set up the way Kodi reads them
/// — `i` and `x`, which no player shortcut uses. Television only: on a
/// computer they are typing.
RemoteKeyAction? classifyRemoteKey(LogicalKeyboardKey key, {bool keyboardLetters = false}) {
  if (keyboardLetters) {
    if (key == LogicalKeyboardKey.keyX) return RemoteKeyAction.stop;
    if (key == LogicalKeyboardKey.keyI) return RemoteKeyAction.info;
  }
  if (key == LogicalKeyboardKey.mediaStop) return RemoteKeyAction.stop;
  if (key == LogicalKeyboardKey.info || key == LogicalKeyboardKey.help || key == LogicalKeyboardKey.contextMenu) {
    return RemoteKeyAction.info;
  }
  if (key == LogicalKeyboardKey.closedCaptionToggle) return RemoteKeyAction.subtitles;
  if (key == LogicalKeyboardKey.mediaAudioTrack) return RemoteKeyAction.audioTrack;
  if (key == LogicalKeyboardKey.guide) return RemoteKeyAction.channelList;
  if (key == LogicalKeyboardKey.mediaLast) return RemoteKeyAction.lastChannel;
  return null;
}

/// The four colour keys, in the order remotes print them.
enum RemoteColourKey { red, green, yellow, blue }

RemoteColourKey? colourKeyOf(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.colorF0Red) return RemoteColourKey.red;
  if (key == LogicalKeyboardKey.colorF1Green) return RemoteColourKey.green;
  if (key == LogicalKeyboardKey.colorF2Yellow) return RemoteColourKey.yellow;
  if (key == LogicalKeyboardKey.colorF3Blue) return RemoteColourKey.blue;
  return null;
}

/// What a colour key can be set to do in the player. The names are persisted;
/// never rename one.
enum RemoteButtonFunction {
  none,
  subtitles,
  audioTrack,
  skipMarker,
  controls,

  /// The description of what is playing.
  description,

  /// The player's settings: quality, speed, picture, sound.
  playerSettings,

  /// Audio and subtitle tracks to choose from.
  tracks,
  chapters,
  channelList,
  lastChannel,
}

const _digits = [
  LogicalKeyboardKey.digit0,
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
];

const _numpadDigits = [
  LogicalKeyboardKey.numpad0,
  LogicalKeyboardKey.numpad1,
  LogicalKeyboardKey.numpad2,
  LogicalKeyboardKey.numpad3,
  LogicalKeyboardKey.numpad4,
  LogicalKeyboardKey.numpad5,
  LogicalKeyboardKey.numpad6,
  LogicalKeyboardKey.numpad7,
  LogicalKeyboardKey.numpad8,
  LogicalKeyboardKey.numpad9,
];

/// The digit a remote's number key stands for, or null for any other key.
int? remoteDigit(LogicalKeyboardKey key) {
  final index = _digits.indexOf(key);
  if (index >= 0) return index;
  final numpad = _numpadDigits.indexOf(key);
  return numpad >= 0 ? numpad : null;
}

/// The index in [numbers] of the channel numbered [typed], ignoring leading
/// zeros on either side; -1 when none is.
int channelIndexForNumber(List<String?> numbers, String typed) {
  final wanted = int.tryParse(typed);
  if (wanted == null) return -1;
  for (var i = 0; i < numbers.length; i++) {
    final number = numbers[i]?.trim();
    if (number != null && int.tryParse(number) == wanted) return i;
  }
  return -1;
}
