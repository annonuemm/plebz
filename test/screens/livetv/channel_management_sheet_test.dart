import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/providers/live_tv_channel_layout_provider.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:provider/provider.dart';
import 'package:plezy/models/live_tv_channel_layout.dart';
import 'package:plezy/models/livetv_channel.dart';
import 'package:plezy/screens/livetv/channel_management_sheet.dart';

import '../../test_helpers/prefs.dart';

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

  group('a group\'s channels lead back to the groups (Plebz)', () {
    setUp(() async {
      resetSharedPreferencesForTest();
      SettingsService.resetForTesting();
      await SettingsService.getInstance();
    });
    tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

    Future<LiveTvChannelLayoutProvider> openManagement(WidgetTester tester, {bool withRemote = false}) async {
      final layout = LiveTvChannelLayoutProvider(profileId: 'profile-1');
      addTearDown(layout.dispose);
      await tester.runAsync(layout.ensureLoaded);
      await tester.pumpWidget(
        TranslationProvider(
          child: InputModeTracker(
            child: ChangeNotifierProvider<LiveTvChannelLayoutProvider>.value(
              value: layout,
              child: MaterialApp(
                theme: monoTheme(dark: true),
                home: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      autofocus: true,
                      onPressed: () => showChannelManagementSheet(context, channels: channels),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      if (withRemote) {
        // A remote announces itself with its first key, then OK on the button.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      } else {
        await tester.tap(find.text('open'));
      }
      await tester.pumpAndSettle();
      expect(find.text('Sport'), findsOneWidget, reason: 'the groups are listed');
      return layout;
    }

    testWidgets('on a phone, back from a group\'s channels shows the groups again', (tester) async {
      TvDetectionService.debugSetAppleTVOverride(false);
      await openManagement(tester);

      await tester.tap(find.text('News'));
      await tester.pumpAndSettle();
      expect(find.text('a'), findsOneWidget, reason: 'the group\'s channels');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Sport'), findsOneWidget);
      expect(find.text('a'), findsNothing);
    });

    testWidgets('on a phone the channels page has a back arrow to the groups', (tester) async {
      TvDetectionService.debugSetAppleTVOverride(false);
      await openManagement(tester);

      await tester.tap(find.text('News'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Symbols.arrow_back_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Sport'), findsOneWidget);
      expect(find.text('a'), findsNothing);
    });

    for (final tv in [false, true]) {
      testWidgets('${tv ? 'on a television' : 'on a phone'} the close of a group\'s channels closes it all', (
        tester,
      ) async {
        TvDetectionService.debugSetAppleTVOverride(tv);
        await openManagement(tester);

        await tester.tap(find.text('News'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip(t.common.close).last);
        await tester.pumpAndSettle();
        expect(find.text('Sport'), findsNothing);
        expect(find.text('open'), findsOneWidget);
      });
    }

    testWidgets('on a television the channels have a back arrow too', (tester) async {
      TvDetectionService.debugSetAppleTVOverride(true);
      await openManagement(tester);

      await tester.tap(find.text('News'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Symbols.arrow_back_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Sport'), findsOneWidget);
      expect(find.text('a'), findsNothing);
    });

    testWidgets('on a television, BACK from a group\'s channels shows the groups again', (tester) async {
      TvDetectionService.debugSetAppleTVOverride(true);
      await openManagement(tester, withRemote: true);

      // To the row's "open" column, and in.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.text('a'), findsOneWidget, reason: 'the first group\'s channels');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Sport'), findsOneWidget);
      expect(find.text('a'), findsNothing);

      // And the remote still works there: down to the second group, into it.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.text('b'), findsOneWidget, reason: 'Sport\'s channel: the cursor came back with the groups');
    });

    testWidgets('a channel hidden in a group leaves the groups in place behind it', (tester) async {
      TvDetectionService.debugSetAppleTVOverride(false);
      final layout = await openManagement(tester);

      await tester.tap(find.text('News'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => layout.setChannelHidden(keyOf('a'), true));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Sport'), findsOneWidget);
    });
  });
}
