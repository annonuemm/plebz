import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/models/live_tv_channel_layout.dart';
import 'package:plezy/models/livetv_channel.dart';

LiveTvChannel _channel(String key, {String? group}) =>
    LiveTvChannel(key: key, title: key, serverId: 'src', lineup: group);

List<String> _keys(List<LiveTvChannel> channels) => [for (final channel in channels) channel.key];

void main() {
  final channels = [
    _channel('a', group: 'News'),
    _channel('b', group: 'Sport'),
    _channel('c', group: 'News'),
    _channel('d'),
  ];

  String keyOf(String channelKey) => liveTvLayoutChannelKey(_channel(channelKey));

  group('applyLiveTvChannelLayout', () {
    test('an untouched arrangement leaves the loaded order alone', () {
      expect(applyLiveTvChannelLayout(channels, LiveTvChannelLayout.empty), same(channels));
    });

    test('a hidden group takes its channels with it', () {
      final layout = LiveTvChannelLayout.empty.withGroupHidden('News', true);

      expect(_keys(applyLiveTvChannelLayout(channels, layout)), ['b', 'd']);
    });

    test('a hidden channel goes without touching its group', () {
      final layout = LiveTvChannelLayout.empty.withChannelHidden(keyOf('a'), true);

      expect(_keys(applyLiveTvChannelLayout(channels, layout)), ['b', 'c', 'd']);
    });

    test('unhiding puts it back', () {
      final layout = LiveTvChannelLayout.empty.withChannelHidden(keyOf('a'), true).withChannelHidden(keyOf('a'), false);

      expect(_keys(applyLiveTvChannelLayout(channels, layout)), ['a', 'b', 'c', 'd']);
    });

    test('group order clusters the channels behind it', () {
      final layout = LiveTvChannelLayout.empty.withGroupOrder(['Sport', 'News']);

      expect(_keys(applyLiveTvChannelLayout(channels, layout)), ['b', 'a', 'c', 'd']);
    });

    test('a group nobody arranged keeps its place behind the arranged ones', () {
      final layout = LiveTvChannelLayout.empty.withGroupOrder(['Sport']);

      expect(_keys(applyLiveTvChannelLayout(channels, layout)), ['b', 'a', 'c', 'd']);
    });

    test('channel order applies within its own group only', () {
      final layout = LiveTvChannelLayout.empty.withChannelOrder('News', [keyOf('c'), keyOf('a')]);

      expect(_keys(applyLiveTvChannelLayout(channels, layout)), ['c', 'a', 'b', 'd']);
    });

    test('a channel the user never moved stays behind the ones they did', () {
      final withE = [...channels, _channel('e', group: 'News')];
      final layout = LiveTvChannelLayout.empty.withChannelOrder('News', [keyOf('c')]);

      expect(_keys(applyLiveTvChannelLayout(withE, layout)), ['c', 'a', 'e', 'b', 'd']);
    });
  });

  group('encode/decode', () {
    test('an arrangement survives a round trip', () {
      final layout = LiveTvChannelLayout.empty
          .withGroupOrder(['Sport', 'News'])
          .withGroupHidden('Adult', true)
          .withChannelOrder('News', [keyOf('c'), keyOf('a')])
          .withChannelHidden(keyOf('b'), true)
          .withGroupName('DE • Doku • RAW', 'Doku');

      final restored = LiveTvChannelLayout.decode(layout.encode());

      expect(restored.groupOrder, ['Sport', 'News']);
      expect(restored.hiddenGroups, {'Adult'});
      expect(restored.groupNames, {'DE • Doku • RAW': 'Doku'});
      expect(restored.channelOrder, {
        'News': [keyOf('c'), keyOf('a')],
      });
      expect(restored.hiddenChannels, {keyOf('b')});
    });

    test('nothing stored is an empty arrangement, not an error', () {
      expect(LiveTvChannelLayout.decode(null).isEmpty, isTrue);
      expect(LiveTvChannelLayout.decode('').isEmpty, isTrue);
      expect(LiveTvChannelLayout.decode('not json').isEmpty, isTrue);
      expect(LiveTvChannelLayout.decode('["a list"]').isEmpty, isTrue);
    });

    test('a malformed field costs that field, not the arrangement', () {
      final restored = LiveTvChannelLayout.decode('{"groupOrder":["Sport",7],"hiddenGroups":"nope"}');

      expect(restored.groupOrder, ['Sport']);
      expect(restored.hiddenGroups, isEmpty);
    });

    test('a group name that is not a string is dropped, the rest is kept', () {
      final restored = LiveTvChannelLayout.decode('{"groupNames":{"Sport":"Fußball","News":7,"Doku":""}}');

      expect(restored.groupNames, {'Sport': 'Fußball'});
    });
  });

  group('renaming a group', () {
    test('keeps the provider key, so the channels stay where they are', () {
      final layout = LiveTvChannelLayout.empty
          .withChannelOrder('DE • Doku • RAW', [keyOf('a')])
          .withGroupName('DE • Doku • RAW', 'Doku');

      expect(layout.groupNames['DE • Doku • RAW'], 'Doku');
      expect(layout.channelOrder['DE • Doku • RAW'], [keyOf('a')]);
    });

    test('a second rename replaces the first', () {
      final layout = LiveTvChannelLayout.empty.withGroupName('Sport', 'Fußball').withGroupName('Sport', 'Bundesliga');

      expect(layout.groupNames, {'Sport': 'Bundesliga'});
    });

    test('an empty name hands the group back its own', () {
      final named = LiveTvChannelLayout.empty.withGroupName('Sport', 'Fußball');

      expect(named.withGroupName('Sport', null).groupNames, isEmpty);
      expect(named.withGroupName('Sport', '   ').groupNames, isEmpty, reason: 'blank is not a name');
    });

    test('a name is trimmed, because a leading space is not a rename', () {
      expect(LiveTvChannelLayout.empty.withGroupName('Sport', '  Fußball ').groupNames, {'Sport': 'Fußball'});
    });

    test('a renamed group is an arrangement worth storing', () {
      expect(LiveTvChannelLayout.empty.withGroupName('Sport', 'Fußball').isEmpty, isFalse);
    });
  });

  group('renaming a channel', () {
    test('shows the new name, while the provider\'s stays what recognises the channel', () {
      final layout = LiveTvChannelLayout.empty.withChannelName(keyOf('a'), 'Erstes');
      final renamed = applyLiveTvChannelLayout(channels, layout).firstWhere((c) => c.key == 'a');

      expect(renamed.displayName, 'Erstes');
      expect(renamed.sourceName, 'a', reason: 'the Sport broadcaster match reads this one');
      expect(renamed.title, 'a', reason: 'and a favourite stored with Plex keeps the provider\'s name');
      expect(_keys(applyLiveTvChannelLayout(channels, layout)), _keys(channels), reason: 'the order is untouched');
    });

    test('an empty name hands the channel back its own', () {
      final named = LiveTvChannelLayout.empty.withChannelName(keyOf('a'), 'Erstes');

      expect(named.withChannelName(keyOf('a'), null).channelNames, isEmpty);
      expect(named.withChannelName(keyOf('a'), '  ').channelNames, isEmpty);
      expect(named.isEmpty, isFalse, reason: 'a renamed channel is an arrangement worth storing');
    });

    test('survives a round trip, and a name that is not a string is dropped', () {
      final layout = LiveTvChannelLayout.empty.withChannelName(keyOf('a'), 'Erstes');
      expect(LiveTvChannelLayout.decode(layout.encode()).channelNames, {keyOf('a'): 'Erstes'});
      expect(LiveTvChannelLayout.decode('{"channelNames": {"x": 3, "y": "Why"}}').channelNames, {'y': 'Why'});
    });

    test('a hidden channel stays hidden under its new name', () {
      final layout = LiveTvChannelLayout.empty
          .withChannelName(keyOf('a'), 'Erstes')
          .withChannelHidden(keyOf('a'), true);
      expect(_keys(applyLiveTvChannelLayout(channels, layout)), isNot(contains('a')));
    });
  });
}
