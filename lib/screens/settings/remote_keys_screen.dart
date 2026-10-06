import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../focus/remote_keys.dart';
import '../../i18n/strings.g.dart';
import '../../services/settings_service.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/focusable_list_tile.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import '../../widgets/setting_tile.dart';
import '../../widgets/settings_section.dart';
import 'settings_utils.dart';

/// Which remote button does what in the player (fork addition). The colour
/// keys are set here; every other row is read-only and takes focus only so a
/// remote can scroll through it.
///
/// Mirrors the player's key handling — `lib/focus/remote_keys.dart`,
/// `transport_keys.dart` and the controls' key events — so a change there
/// belongs here too.
class RemoteKeysScreen extends StatelessWidget {
  const RemoteKeysScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final keys = t.remoteKeys;
    final theme = Theme.of(context);
    Widget row(String key, String does) => FocusableListTile(title: Text(key), subtitle: Text(does));
    Widget note(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(text, style: theme.textTheme.bodyMedium),
    );

    return FocusedScrollScaffold(
      title: Text(keys.title),
      slivers: [
        SliverList(
          delegate: SliverChildListDelegate([
            note(keys.intro),
            SettingsGroup(
              title: keys.playbackGroup,
              children: [
                row(keys.keyOk, keys.doOk),
                row(keys.keyPlayPause, keys.doPlayPause),
                row(keys.keyStop, keys.doStop),
                row(keys.keySeek, keys.doSeek),
                row(keys.keyTrack, keys.doTrack),
                row(keys.keyLeftRight, keys.doLeftRight),
                row(keys.keyUpDown, keys.doUpDown),
                row(keys.keyBack, keys.doBack),
                row(keys.keyInfo, keys.doInfo),
                row(keys.keySubtitles, keys.doSubtitles),
                row(keys.keyAudio, keys.doAudio),
              ],
            ),
            SettingsGroup(
              title: keys.liveGroup,
              children: [
                row(keys.keyLiveUpDown, keys.doLiveUpDown),
                row(keys.keyLiveLeft, keys.doLiveLeft),
                row(keys.keyLiveRight, keys.doLiveRight),
                row(keys.keyChannel, keys.doChannel),
                row(keys.keyDigits, keys.doDigits),
                row(keys.keyLast, keys.doLast),
                row(keys.keyGuide, keys.doGuide),
              ],
            ),
            note(keys.colourGroupDescription),
            SettingsGroup(
              title: keys.colourGroup,
              children: [for (final colour in RemoteColourKey.values) _ColourKeyTile(colour)],
            ),
            SettingsGroup(
              title: keys.receiverGroup,
              children: [
                ListTile(
                  leading: const AppIcon(Symbols.settings_remote_rounded, fill: 1),
                  subtitle: Text(keys.receiverIntro),
                ),
                row(keys.keySpace, keys.doSpace),
                row(keys.keyEscape, keys.doEscape),
                row(keys.keyLetterI, keys.doLetterI),
                row(keys.keyLetterX, keys.doLetterX),
                row(keys.keyLetterS, keys.doLetterS),
                row(keys.keyLetterA, keys.doLetterA),
              ],
            ),
            const SizedBox(height: 24),
          ]),
        ),
      ],
    );
  }
}

/// One colour key and what it is set to do.
class _ColourKeyTile extends StatelessWidget {
  const _ColourKeyTile(this.colour);

  final RemoteColourKey colour;

  String get _name => switch (colour) {
    RemoteColourKey.red => t.remoteKeys.keyRed,
    RemoteColourKey.green => t.remoteKeys.keyGreen,
    RemoteColourKey.yellow => t.remoteKeys.keyYellow,
    RemoteColourKey.blue => t.remoteKeys.keyBlue,
  };

  @override
  Widget build(BuildContext context) => SettingSelectionTile<RemoteButtonFunction>(
    pref: SettingsService.remoteButtonPref(colour),
    icon: Symbols.radio_button_checked_rounded,
    title: _name,
    subtitleBuilder: remoteButtonFunctionLabel,
    options: [
      for (final function in RemoteButtonFunction.values)
        DialogOption(value: function, title: remoteButtonFunctionLabel(function)),
    ],
  );
}

String remoteButtonFunctionLabel(RemoteButtonFunction function) {
  final labels = t.remoteKeys.functions;
  return switch (function) {
    RemoteButtonFunction.none => labels.none,
    RemoteButtonFunction.subtitles => labels.subtitles,
    RemoteButtonFunction.audioTrack => labels.audioTrack,
    RemoteButtonFunction.skipMarker => labels.skipMarker,
    RemoteButtonFunction.controls => labels.controls,
    RemoteButtonFunction.description => labels.description,
    RemoteButtonFunction.playerSettings => labels.playerSettings,
    RemoteButtonFunction.tracks => labels.tracks,
    RemoteButtonFunction.chapters => labels.chapters,
    RemoteButtonFunction.channelList => labels.channelList,
    RemoteButtonFunction.lastChannel => labels.lastChannel,
  };
}
