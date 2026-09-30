import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/models/livetv_channel.dart';
import 'package:plezy/screens/video_player/live_tv_session_state.dart';
import 'package:plezy/services/live_tv_last_selection.dart';

LiveTvChannel _channel(String key, String group) => LiveTvChannel(key: key, title: key, serverId: 'src', lineup: group);

final _channels = [
  _channel('ard', 'DE - Vollprogramm'),
  _channel('zdf', 'DE - Vollprogramm'),
  _channel('arte', 'DE - Kultur'),
  _channel('3sat', 'DE - Kultur'),
];

void main() {
  group('a group narrows the session', () {
    test('no group leaves every channel reachable', () {
      final state = LiveTvSessionState(null);

      expect(state.channelsIn(_channels), hasLength(4));
    });

    test('a group leaves only its own', () {
      final state = LiveTvSessionState(null)..activeGroup = 'DE - Kultur';

      expect(state.channelsIn(_channels).map((c) => c.key), ['arte', '3sat']);
    });

    test('the playing channel keeps its place in the narrowed list', () {
      // The strip opens on the channel that is playing, and it opens on the
      // index it is given.
      final state = LiveTvSessionState(null)
        ..activeGroup = 'DE - Kultur'
        ..channelIndex = 3;

      expect(state.visibleIndexIn(_channels), 1, reason: '3sat is the second of its group');
    });

    test('a group that matches nothing hands every channel back', () {
      // A stale group must not leave the viewer with an empty list and no way
      // out of it.
      final state = LiveTvSessionState(null)..activeGroup = 'gone';

      expect(state.channelsIn(_channels), hasLength(4));
    });

    test('a channel outside the group falls to the first of it', () {
      final state = LiveTvSessionState(null)
        ..activeGroup = 'DE - Kultur'
        ..channelIndex = 0;

      expect(state.visibleIndexIn(_channels), 0);
    });
  });

  group('what the guide is told', () {
    setUp(LiveTvLastSelection.instance.resetForTest);

    test('nothing until the player has been in', () {
      expect(LiveTvLastSelection.instance.hasSelection, isFalse);
    });

    test('a group with no channel is still an answer', () {
      // "All channels" is a real selection, and the guide has to be able to
      // tell it from never having been in the player.
      LiveTvLastSelection.instance.record(channelKey: null, group: null);

      expect(LiveTvLastSelection.instance.hasSelection, isTrue);
      expect(LiveTvLastSelection.instance.group, isNull);
    });

    test('the last zap is what the guide hears about', () {
      var notified = 0;
      void listener() => notified++;
      LiveTvLastSelection.instance.addListener(listener);
      addTearDown(() => LiveTvLastSelection.instance.removeListener(listener));

      LiveTvLastSelection.instance.record(channelKey: 'src ard', group: 'DE - Kultur');
      LiveTvLastSelection.instance.record(channelKey: 'src 3sat', group: 'DE - Kultur');
      LiveTvLastSelection.instance.record(channelKey: 'src 3sat', group: 'DE - Kultur');

      expect(LiveTvLastSelection.instance.channelKey, 'src 3sat');
      expect(notified, 2, reason: 'the same selection twice is not news');
    });

    test('a hand-off from the home screen is news, and is taken once', () {
      var notified = 0;
      void listener() => notified++;
      LiveTvLastSelection.instance.addListener(listener);
      addTearDown(() => LiveTvLastSelection.instance.removeListener(listener));

      LiveTvLastSelection.instance.handOff(channelKey: 'src ard', group: 'DE - Kultur');

      expect(notified, 1);
      expect(LiveTvLastSelection.instance.channelKey, 'src ard');
      expect(LiveTvLastSelection.instance.group, 'DE - Kultur');
      expect(LiveTvLastSelection.instance.takeHandOff(), isTrue);
      expect(LiveTvLastSelection.instance.takeHandOff(), isFalse, reason: 'one guide takes it');

      LiveTvLastSelection.instance.record(channelKey: 'src 3sat', group: 'DE - Kultur');
      expect(LiveTvLastSelection.instance.takeHandOff(), isFalse, reason: 'a zap in the player is no hand-off');
    });
  });
}
