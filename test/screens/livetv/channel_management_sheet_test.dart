import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/models/live_tv_channel_layout.dart';
import 'package:plezy/models/livetv_channel.dart';
import 'package:plezy/screens/livetv/channel_management_sheet.dart';

LiveTvChannel _channel(String key, {String? group}) =>
    LiveTvChannel(key: key, title: key, serverId: 'src', lineup: group);

void main() {
  setUp(() => LocaleSettings.setLocaleSync(AppLocale.en));

  final channels = [
    _channel('a', group: 'News'),
    _channel('b', group: 'Sport'),
    _channel('c', group: 'News'),
    _channel('d'),
  ];

  String keyOf(String channelKey) => liveTvLayoutChannelKey(_channel(channelKey));

  group('liveTvChannelGroupEntries', () {
    test('counts the channels of every group, ungrouped included', () {
      final entries = liveTvChannelGroupEntries(channels, LiveTvChannelLayout.empty);

      expect(entries.map((entry) => entry.key), ['News', 'Sport', '']);
      expect(entries.map((entry) => entry.count), [2, 1, 1]);
      expect(entries.last.label, t.liveTv.ungrouped);
    });

    test('follows the arranged group order', () {
      final entries = liveTvChannelGroupEntries(channels, LiveTvChannelLayout.empty.withGroupOrder(['', 'Sport']));

      expect(entries.map((entry) => entry.key), ['', 'Sport', 'News']);
    });

    test('reports how many of a group are hidden, so they can be found again', () {
      final entries = liveTvChannelGroupEntries(
        channels,
        LiveTvChannelLayout.empty.withChannelHidden(keyOf('a'), true),
      );

      expect(entries.first.count, 2);
      expect(entries.first.hiddenCount, 1);
    });

    test('a hidden group is still listed — it is the only way back', () {
      final entries = liveTvChannelGroupEntries(channels, LiveTvChannelLayout.empty.withGroupHidden('News', true));

      expect(entries.map((entry) => entry.key), contains('News'));
    });
  });

  group('liveTvChannelsInGroup', () {
    test('returns only that group, in loaded order by default', () {
      final inGroup = liveTvChannelsInGroup(channels, 'News', LiveTvChannelLayout.empty);

      expect(inGroup.map((channel) => channel.key), ['a', 'c']);
    });

    test('follows the arranged channel order', () {
      final inGroup = liveTvChannelsInGroup(
        channels,
        'News',
        LiveTvChannelLayout.empty.withChannelOrder('News', [keyOf('c'), keyOf('a')]),
      );

      expect(inGroup.map((channel) => channel.key), ['c', 'a']);
    });

    test('lists hidden channels too, so they can be shown again', () {
      final inGroup = liveTvChannelsInGroup(
        channels,
        'News',
        LiveTvChannelLayout.empty.withChannelHidden(keyOf('a'), true),
      );

      expect(inGroup.map((channel) => channel.key), ['a', 'c']);
    });
  });
}
