import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:plezy/exceptions/media_server_exceptions.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/mixins/refreshable.dart';
import 'package:plezy/media/live_tv_support.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/media/server_capabilities.dart';
import 'package:plezy/models/livetv_channel.dart';
import 'package:plezy/models/livetv_program.dart';
import 'package:plezy/models/media_grab_operation.dart';
import 'package:plezy/models/media_subscription.dart';
import 'package:plezy/providers/live_tv_channel_layout_provider.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/screens/livetv/guide_search_sheet.dart';
import 'package:plezy/screens/livetv/live_tv_screen.dart';
import 'package:plezy/screens/livetv/live_tv_sidebar_actions.dart';
import 'package:plezy/screens/livetv/tabs/guide_tab.dart';
import 'package:plezy/services/live_tv_last_selection.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/redesign/ocker_skin.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/redesign/ocker_submenu.dart';
import 'package:plezy/screens/livetv/tabs/recordings_tab.dart';
import 'package:plezy/widgets/focusable_tab_chip.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/multi_server_fixtures.dart';
import '../../test_helpers/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('en'));

  setUp(() async {
    resetSharedPreferencesForTest();
    LocaleSettings.setLocaleSync(AppLocale.en);
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.liveTvDefaultFavorites, true);
  });

  testWidgets('loaded empty favorites shows the favorites empty state and can restore all channels', (tester) async {
    final harness = await _pumpLiveTvScreen(tester);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      harness.dispose();
    });

    expect(find.byIcon(Symbols.star_rounded), findsOneWidget);
    expect(_guideChannels(tester).map((channel) => channel.key), ['channel-a']);

    harness.liveTv.favorites.complete(const []);
    await tester.pumpAndSettle();

    expect(find.byType(GuideTab), findsNothing);
    expect(find.text(t.liveTv.noFavoriteChannels), findsOneWidget);
    expect(find.text(t.liveTv.showAllChannels), findsOneWidget);

    await tester.tap(find.text(t.liveTv.showAllChannels));
    await tester.pumpAndSettle();

    expect(find.text(t.liveTv.noFavoriteChannels), findsNothing);
    expect(find.byIcon(Symbols.star_outline_rounded), findsOneWidget);
    expect(_guideChannels(tester).map((channel) => channel.key), ['channel-a']);
  });

  testWidgets('favorites matching no loaded channel show the favorites empty state', (tester) async {
    final harness = await _pumpLiveTvScreen(tester);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      harness.dispose();
    });

    harness.liveTv.favorites.complete([FavoriteChannel(id: 'channel-gone', source: 'server://server-a/provider-a')]);
    await tester.pumpAndSettle();

    expect(find.byType(GuideTab), findsNothing);
    expect(find.text(t.liveTv.noFavoriteChannels), findsOneWidget);
    expect(find.text(t.liveTv.showAllChannels), findsOneWidget);
  });

  testWidgets('refresh keeps the favorites filter narrow while favorites reload', (tester) async {
    final harness = await _pumpLiveTvScreen(tester, channelKeys: const ['channel-a', 'channel-b']);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      harness.dispose();
    });

    final favorite = FavoriteChannel(id: 'channel-a', source: 'server://server-a/provider-a');
    harness.liveTv.favorites.complete([favorite]);
    await tester.pumpAndSettle();

    expect(_guideChannels(tester).map((channel) => channel.key), ['channel-a']);

    await tester.tap(find.byIcon(Symbols.refresh_rounded));
    await tester.pumpAndSettle();

    expect(_guideChannels(tester).map((channel) => channel.key), ['channel-a']);

    harness.liveTv.favorites.complete([favorite]);
    await tester.pumpAndSettle();

    expect(_guideChannels(tester).map((channel) => channel.key), ['channel-a']);
  });

  testWidgets('guide search covers all channels and selecting a non-favorite drops the favorites filter', (
    tester,
  ) async {
    final harness = await _pumpLiveTvScreen(tester, channelKeys: const ['channel-a', 'channel-b']);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      harness.dispose();
    });

    harness.liveTv.favorites.complete([FavoriteChannel(id: 'channel-a', source: 'server://server-a/provider-a')]);
    await tester.pumpAndSettle();
    expect(_guideChannels(tester).map((channel) => channel.key), ['channel-a']);

    await tester.tap(find.byIcon(Symbols.search_rounded));
    await tester.pumpAndSettle();

    // The sheet searches the full lineup, not the favorites-filtered one.
    final sheet = find.byType(GuideSearchSheet);
    expect(find.descendant(of: sheet, matching: find.text('Unique Channel A')), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('Unique Channel channel-b')), findsOneWidget);

    await tester.tap(find.descendant(of: sheet, matching: find.text('Unique Channel channel-b')));
    await tester.pumpAndSettle();

    // The target row must exist to land on, so the filter is dropped and the
    // guide widens to the full lineup.
    expect(_guideChannels(tester).map((channel) => channel.key), ['channel-a', 'channel-b']);
  });

  testWidgets('favorite read failure preserves raw Guide channels', (tester) async {
    final harness = await _pumpLiveTvScreen(tester);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      harness.dispose();
    });

    expect(_guideChannels(tester).map((channel) => channel.key), ['channel-a']);

    harness.liveTv.favorites.completeError(StateError('favorite read failed'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Symbols.star_rounded), findsOneWidget);
    expect(_guideChannels(tester).map((channel) => channel.key), ['channel-a']);
  });
  testWidgets('favorite failure keeps favorites loaded from healthy stores', (tester) async {
    final failedLiveTv = _FakeLiveTvSupport(serverId: 'server-a', storeKey: 'store-a');
    final healthyLiveTv = _FakeLiveTvSupport(serverId: 'server-b', storeKey: 'store-b');
    final failedClient = _FakeMediaServerClient(failedLiveTv, serverId: ServerId('server-a'));
    final healthyClient = _FakeMediaServerClient(healthyLiveTv, serverId: ServerId('server-b'));
    final manager = MultiServerManager()
      ..debugRegisterClientForTesting(failedClient)
      ..debugRegisterClientForTesting(healthyClient);
    final provider = testMultiServerProvider(manager);
    provider.debugSetLiveTvServersForTesting([
      LiveTvServerInfo(serverId: 'server-a', dvrKey: 'dvr-a', lineup: 'provider-a'),
      LiveTvServerInfo(serverId: 'server-b', dvrKey: 'dvr-b', lineup: 'provider-b'),
    ]);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      provider.dispose();
      manager.dispose();
    });
    await tester.pumpWidget(
      TranslationProvider(
        child: InputModeTracker(
          child: ChangeNotifierProvider<MultiServerProvider>.value(
            value: provider,
            child: MaterialApp(theme: monoTheme(dark: true), home: const LiveTvScreen()),
          ),
        ),
      ),
    );
    failedLiveTv.favorites.completeError(StateError('favorite read failed'));
    healthyLiveTv.favorites.complete([FavoriteChannel(id: 'channel-server-b', source: 'server://server-b/provider-b')]);
    await tester.pumpAndSettle();

    final guide = tester.widget<GuideTab>(find.byType(GuideTab));
    final healthyChannel = guide.channels.singleWhere((channel) => channel.serverId == 'server-b');
    expect(guide.isFavoriteChannel!(healthyChannel), isTrue);
    expect(guide.channels.map((channel) => channel.serverId), ['server-b']);
  });

  testWidgets('favorite write failure keeps optimistic state, shows feedback, and leaves the queue usable', (
    tester,
  ) async {
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.liveTvDefaultFavorites, false);
    final harness = await _pumpLiveTvScreen(tester);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      harness.dispose();
    });
    harness.liveTv.writeFailures.add(StateError('favorite write failed'));
    harness.liveTv.favorites.complete(const []);
    await tester.pumpAndSettle();

    // A hold opens the channel's menu; the favourite is one of its entries.
    await tester.longPress(find.text('Unique Channel A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.liveTv.addToFavorites));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    var guide = tester.widget<GuideTab>(find.byType(GuideTab));
    expect(guide.isFavoriteChannel!(guide.channels.single), isTrue);
    expect(find.text(t.liveTv.favoritesUpdateFailed), findsOneWidget);
    expect(harness.liveTv.writes.map((write) => write.map((favorite) => favorite.id).toList()), [
      ['channel-a'],
    ]);

    await tester.longPress(find.text('Unique Channel A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.liveTv.removeFromFavorites));
    await tester.pumpAndSettle();

    guide = tester.widget<GuideTab>(find.byType(GuideTab));
    expect(guide.isFavoriteChannel!(guide.channels.single), isFalse);
    expect(harness.liveTv.writes.map((write) => write.map((favorite) => favorite.id).toList()), [
      ['channel-a'],
      <String>[],
    ]);
  });

  testWidgets('the group bar scopes the guide to the picked group', (tester) async {
    // A playlist names its groups and a panel its categories; both land on
    // the channel's lineup, and hundreds of channels are unusable without a
    // way to narrow them.
    final harness = await _pumpLiveTvScreen(
      tester,
      channelKeys: const ['channel-a', 'channel-b', 'channel-c'],
      channelGroups: _channelGroups(),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      harness.dispose();
    });

    expect(_guideChannels(tester).map((channel) => channel.key), ['channel-a', 'channel-b', 'channel-c']);
    expect(find.text(t.liveTv.allChannels), findsOneWidget);
    expect(find.text('News'), findsOneWidget);
    expect(find.text('Sport'), findsOneWidget);

    await tester.tap(find.text('News'));
    await tester.pumpAndSettle();

    expect(_guideChannels(tester).map((channel) => channel.key), ['channel-a', 'channel-b']);

    await tester.tap(find.text(t.liveTv.allChannels));
    await tester.pumpAndSettle();

    expect(_guideChannels(tester).map((channel) => channel.key), ['channel-a', 'channel-b', 'channel-c']);
  });

  group('a channel handed over from the home screen', () {
    setUp(LiveTvLastSelection.instance.resetForTest);
    tearDown(LiveTvLastSelection.instance.resetForTest);

    String keyOf(WidgetTester tester, String channelKey) =>
        liveTvChannelScopeKey(_guideChannels(tester).singleWhere((channel) => channel.key == channelKey));

    int cursor(WidgetTester tester) => tester.state<GuideTabState>(find.byType(GuideTab)).debugCursorChannelIndex;

    testWidgets('brings the guide forward on its group, with the channel under the cursor', (tester) async {
      final harness = await _pumpLiveTvScreen(
        tester,
        channelKeys: const ['channel-a', 'channel-b', 'channel-c'],
        channelGroups: _channelGroups(),
        dvr: _FakeLiveTvDvrSupport(),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        harness.dispose();
      });
      final key = keyOf(tester, 'channel-b');
      await tester.tap(find.text(t.liveTv.recordings));
      await tester.pumpAndSettle();
      expect(find.byType(RecordingsTab), findsOneWidget);

      LiveTvLastSelection.instance.handOff(channelKey: key, group: 'News');
      await tester.pumpAndSettle();

      expect(find.byType(RecordingsTab), findsNothing, reason: 'the guide is what the player closes onto');
      expect(_guideChannels(tester).map((channel) => channel.key), ['channel-a', 'channel-b']);
      expect(cursor(tester), 1);
      expect(LiveTvLastSelection.instance.takeHandOff(), isFalse, reason: 'taken, not left for the next visit');
    });

    testWidgets('closing the player focuses the guide on that channel, not on its first', (tester) async {
      final harness = await _pumpLiveTvScreen(
        tester,
        channelKeys: const ['channel-a', 'channel-b', 'channel-c'],
        channelGroups: _channelGroups(),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        harness.dispose();
      });
      // A remote: the viewer navigates by focus.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      final key = keyOf(tester, 'channel-b');

      LiveTvLastSelection.instance.handOff(channelKey: key, group: 'News');
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      (tester.state(find.byType(LiveTvScreen)) as BackgroundSelectedTab).focusAfterBackgroundSelect();
      await tester.pumpAndSettle();

      expect(FocusManager.instance.primaryFocus?.debugLabel, 'guide_tab');
      expect(cursor(tester), 1, reason: 'an arrival would have put it on the first channel');
    });

    testWidgets('is taken by a Live TV built only now, once its channels are there', (tester) async {
      // The first visit to the tab: the screen is built behind the player,
      // after the hand-off, and its channels arrive later still.
      final first = await _pumpLiveTvScreen(
        tester,
        channelKeys: const ['channel-a', 'channel-b', 'channel-c'],
        channelGroups: _channelGroups(),
      );
      final key = keyOf(tester, 'channel-c');
      await tester.pumpWidget(const SizedBox.shrink());
      first.dispose();

      LiveTvLastSelection.instance.handOff(channelKey: key, group: 'Sport');
      final harness = await _pumpLiveTvScreen(
        tester,
        channelKeys: const ['channel-a', 'channel-b', 'channel-c'],
        channelGroups: _channelGroups(),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        harness.dispose();
      });

      expect(_guideChannels(tester).map((channel) => channel.key), ['channel-c']);
      expect(cursor(tester), 0);
      expect(LiveTvLastSelection.instance.takeHandOff(), isFalse);
    });
  });

  testWidgets('a group shown again has the guide ask for programmes again; one hidden does not', (tester) async {
    final harness = await _pumpLiveTvScreen(
      tester,
      channelKeys: const ['channel-a', 'channel-b', 'channel-c'],
      channelGroups: _channelGroups(),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      harness.dispose();
    });

    // An IPTV guide is read only for the channels showing, so hiding needs
    // nothing new from anyone.
    final atStart = harness.liveTv.scheduleRequests;
    await harness.layout.setGroupHidden('Sport', true);
    await tester.pumpAndSettle();
    expect(_guideChannels(tester).map((c) => c.key), isNot(contains('channel-c')));
    expect(harness.liveTv.scheduleRequests, atStart);

    // Shown again, it has no programmes until the guide asks again.
    await harness.layout.setGroupHidden('Sport', false);
    await tester.pumpAndSettle();
    expect(_guideChannels(tester).map((c) => c.key), contains('channel-c'));
    expect(harness.liveTv.scheduleRequests, greaterThan(atStart));
  });

  testWidgets('redesign: the page\'s views are rows under "Live-TV" in the rail, with no tab row on the page', (
    tester,
  ) async {
    // The rail is the television's; a phone keeps its tab row.
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    final harness = await _pumpLiveTvScreen(tester, dvr: _FakeLiveTvDvrSupport(), variant: AppThemeVariant.glas);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      harness.dispose();
    });

    // A DVR brings the recordings: two views, and no row of tabs for them.
    expect(find.byType(FocusableTabChip), findsNothing, reason: 'the views are in the rail');
    final host = tester.state(find.byType(LiveTvScreen)) as OckerSubmenuHost;
    final rows = host.ockerRailMenu!.items;
    expect(rows.where((row) => row.label == t.liveTv.guide), hasLength(1));
    rows.singleWhere((row) => row.label == t.liveTv.recordings).onSelect();
    await tester.pumpAndSettle();
    expect(find.byType(RecordingsTab), findsOneWidget, reason: 'the chosen view is on show');
  });

  testWidgets('redesign: "Sender verwalten" is a row under "Live-TV", even with the guide as the only view', (
    tester,
  ) async {
    // No DVR: the guide is the page's one view. There is no app bar and no
    // rail under the redesign, so without this entry a hidden group could
    // never be shown again.
    final harness = await _pumpLiveTvScreen(
      tester,
      channelKeys: const ['channel-a', 'channel-b', 'channel-c'],
      channelGroups: _channelGroups(),
      variant: AppThemeVariant.glas,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      harness.dispose();
    });

    final host = tester.state(find.byType(LiveTvScreen)) as OckerSubmenuHost;
    final rows = host.ockerRailMenu!.items;
    expect(rows.where((row) => row.label == t.liveTv.guide), isEmpty, reason: 'one view, no choice');

    rows.singleWhere((row) => row.label == t.liveTv.manageChannels).onSelect();
    await tester.pumpAndSettle();
    expect(find.text(t.liveTv.manageChannels), findsWidgets, reason: 'the arrangement sheet is open');
    expect(find.text('Sport'), findsWidgets);
  });

  testWidgets('redesign: the favourites filter and reloading the guide are rows under "Live-TV" too', (tester) async {
    final harness = await _pumpLiveTvScreen(
      tester,
      channelKeys: const ['channel-a', 'channel-b', 'channel-c'],
      variant: AppThemeVariant.glas,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      harness.dispose();
    });
    final host = tester.state(find.byType(LiveTvScreen)) as OckerSubmenuHost;
    final actions = tester.state(find.byType(LiveTvScreen)) as LiveTvSidebarActions;
    final before = actions.showsFavoritesOnly;

    final rows = host.ockerRailMenu!.items;
    expect(rows.where((row) => row.label == t.liveTv.reloadGuide), hasLength(1));
    rows.singleWhere((row) => row.label == t.liveTv.favorites).onSelect();
    await tester.pumpAndSettle();

    expect(actions.showsFavoritesOnly, !before, reason: 'the filter flipped');
  });

  testWidgets('standard: the views keep their tab row', (tester) async {
    final harness = await _pumpLiveTvScreen(tester, dvr: _FakeLiveTvDvrSupport());
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      harness.dispose();
    });
    expect(find.widgetWithText(FocusableTabChip, t.liveTv.recordings), findsOneWidget);
  });

  testWidgets('the groups are the column beside the channels, never a bar above them', (tester) async {
    final harness = await _pumpLiveTvScreen(
      tester,
      channelKeys: const ['channel-a', 'channel-b', 'channel-c'],
      channelGroups: _channelGroups(),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      harness.dispose();
    });

    // No bar of group chips over the guide, in any theme.
    expect(find.byWidgetPredicate((w) => w is FocusableTabChip && w.label == 'News'), findsNothing);
    // The column is the way in, one LEFT from the channels.
    expect(tester.widget<GuideTab>(find.byType(GuideTab)).onOpenGroups, isNotNull);

    // UP out of the guide lands above it, not on a group.
    _guideFocusNode(tester).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    final focused = FocusManager.instance.primaryFocus?.context;
    expect(focused, isNotNull, reason: 'the press lands somewhere');
    expect(focused!.findAncestorWidgetOfExactType<FocusableTabChip>(), isNull, reason: 'not on a chip of groups');
  });

  testWidgets('television: the group column opens standing still on a group far down the list', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    await SettingsService.getInstance();
    final keys = [for (var i = 0; i < 40; i++) 'channel-$i'];
    final harness = await _pumpLiveTvScreen(
      tester,
      channelKeys: keys,
      channelGroups: {for (final key in keys) key: 'Group $key'},
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      harness.dispose();
    });
    void open() => tester.widget<GuideTab>(find.byType(GuideTab)).onOpenGroups!();
    ScrollPosition list() => tester
        .state<ScrollableState>(find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first)
        .position;

    // Choose a group far down, which closes the column.
    open();
    await tester.pumpAndSettle();
    list().jumpTo(list().maxScrollExtent);
    await tester.pumpAndSettle();
    // The last group the list has built, down at its foot.
    final far = tester
        .widgetList<Text>(find.byWidgetPredicate((w) => w is Text && (w.data ?? '').startsWith('Group channel-')))
        .last
        .data!;
    await tester.tap(find.text(far));
    await tester.pumpAndSettle();

    // Leave the list somewhere else, then open it again: it must open where
    // it will stay — no jump, no glide once it is showing.
    list().jumpTo(0);
    await tester.pump();
    open();
    await tester.pump();
    await tester.pump();
    final opened = list().pixels;
    await tester.pumpAndSettle();
    expect(list().pixels, closeTo(opened, 1), reason: 'nothing moves once the column shows');
    expect(find.text(far), findsOneWidget);
  });

  for (final television in [false, true]) {
    testWidgets(
      '${television ? 'television' : 'desktop'}: the group column finds its chosen group again, however far down it was left',
      (tester) async {
        // A drawer on the television, a column standing open on the desktop.
        TvDetectionService.debugSetAppleTVOverride(television);
        addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
        // A long list, left scrolled far down: the chosen group — "all channels",
        // at the top — is no longer among the rows it built, and the column used
        // to open with no row to put the cursor on.
        await SettingsService.getInstance();
        final keys = [for (var i = 0; i < 40; i++) 'channel-$i'];
        final harness = await _pumpLiveTvScreen(
          tester,
          channelKeys: keys,
          channelGroups: {for (final key in keys) key: 'Group $key'},
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          harness.dispose();
        });

        void open() => tester.widget<GuideTab>(find.byType(GuideTab)).onOpenGroups!();
        bool aGroupHasFocus() {
          final focused = FocusManager.instance.primaryFocus?.context;
          return focused != null &&
              focused.findAncestorWidgetOfExactType<ListView>() != null &&
              find
                  .byType(ListTile)
                  .evaluate()
                  .any((row) => row == focused || focused.findAncestorWidgetOfExactType<ListTile>() != null);
        }

        open();
        await tester.pumpAndSettle();
        expect(aGroupHasFocus(), isTrue, reason: 'opened at the top');

        final list = tester.state<ScrollableState>(
          find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first,
        );
        list.position.jumpTo(list.position.maxScrollExtent);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        open();
        await tester.pumpAndSettle();
        expect(aGroupHasFocus(), isTrue, reason: 'a row holds the cursor, not an open column with none');
      },
    );
  }

  testWidgets('under glass the group column is a rounded pane, its counts quieter than its names', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    await SettingsService.getInstance();
    final harness = await _pumpLiveTvScreen(
      tester,
      channelKeys: const ['channel-a', 'channel-b', 'channel-c'],
      channelGroups: _channelGroups(),
      variant: AppThemeVariant.glas,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      harness.dispose();
    });

    tester.widget<GuideTab>(find.byType(GuideTab)).onOpenGroups!();
    await tester.pumpAndSettle();

    final pane = find.ancestor(of: find.byType(ListView).first, matching: find.byType(OckerGlass));
    expect(pane, findsOneWidget);
    expect(tester.widget<OckerGlass>(pane).borderRadius.topLeft.x, greaterThan(0), reason: 'no hard corners');

    final count = tester.widget<Text>(find.text(t.liveTv.channelCount(count: 2)));
    final name = tester.widget<Text>(find.text('News'));
    expect(count.style?.color?.a, lessThan(name.style?.color?.a ?? 1));
  });

  testWidgets('channels without groups get no group bar', (tester) async {
    final harness = await _pumpLiveTvScreen(tester, channelKeys: const ['channel-a', 'channel-b']);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      harness.dispose();
    });

    expect(find.text(t.liveTv.allChannels), findsNothing);
  });

  testWidgets('a session with neither hubs nor a DVR shows no tab bar', (tester) async {
    // The Jellyfin fake has no Plex client behind it, so "what's on" — which
    // is built from Plex's Live TV hubs — could only ever be empty.
    final harness = await _pumpLiveTvScreen(tester);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      harness.dispose();
    });

    expect(find.text(t.liveTv.whatsOn), findsNothing);
    expect(find.text(t.liveTv.guide), findsNothing, reason: 'a lone tab is not worth a bar');
  });

  testWidgets('hiding a group in the management sheet takes it out of the guide', (tester) async {
    final harness = await _pumpLiveTvScreen(
      tester,
      channelKeys: const ['channel-a', 'channel-b', 'channel-c'],
      channelGroups: _channelGroups(),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      harness.dispose();
    });

    await tester.tap(find.byIcon(Symbols.tune_rounded));
    await tester.pumpAndSettle();

    // The sheet's count — the column beside the guide names the same group,
    // with its count, where it stands open.
    expect(
      find.byWidgetPredicate((w) => w is Text && w.data == t.liveTv.channelCount(count: 2) && w.maxLines == 1),
      findsOneWidget,
      reason: 'the News group holds two channels',
    );

    await tester.tap(find.byTooltip(t.liveTv.hideFromGuide).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Symbols.close_rounded).last);
    await tester.pumpAndSettle();

    expect(_guideChannels(tester).map((channel) => channel.key), ['channel-c']);
    expect(find.text('News'), findsNothing, reason: 'a hidden group is not offered in the column either');
  });

  testWidgets('a channel\'s menu renames it everywhere, and hides it', (tester) async {
    final harness = await _pumpLiveTvScreen(tester, channelKeys: const ['channel-a', 'channel-b']);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      harness.dispose();
    });
    harness.liveTv.favorites.complete(const []);
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.liveTv.showAllChannels));
    await tester.pumpAndSettle();

    Future<void> openMenuFor(String key) async {
      final guide = tester.widget<GuideTab>(find.byType(GuideTab));
      guide.onChannelMenu!(guide.channels.firstWhere((channel) => channel.key == key));
      await tester.pumpAndSettle();
    }

    await openMenuFor('channel-a');
    expect(find.text(t.liveTv.addToFavorites), findsOneWidget);
    expect(find.text(t.liveTv.renameChannel), findsOneWidget);
    expect(find.text(t.liveTv.hideChannel), findsOneWidget);

    await tester.tap(find.text(t.liveTv.renameChannel));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Erstes');
    await tester.tap(find.text(t.common.save));
    await tester.pumpAndSettle();
    final renamed = _guideChannels(tester).firstWhere((channel) => channel.key == 'channel-a');
    expect(renamed.displayName, 'Erstes');
    expect(renamed.sourceName, 'Unique Channel A');

    await openMenuFor('channel-b');
    await tester.tap(find.text(t.liveTv.hideChannel));
    await tester.pumpAndSettle();
    expect(_guideChannels(tester).map((channel) => channel.key), ['channel-a']);
  });

  testWidgets('What\'s On is hidden when no Live TV server is Plex', (tester) async {
    final harness = await _pumpLiveTvScreen(tester);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      harness.dispose();
    });
    harness.liveTv.favorites.complete(const []);
    await tester.pumpAndSettle();

    // Without What's On and without a DVR the session is guide-only, and a
    // guide-only session shows no tab bar at all — so not even a Guide tab.
    expect(find.text(t.liveTv.whatsOn), findsNothing);
    expect(find.text(t.liveTv.guide), findsNothing);
  });

  testWidgets('a refresh that fails on every server keeps the loaded channels', (tester) async {
    final harness = await _pumpLiveTvScreen(tester, channelKeys: const ['channel-a', 'channel-b']);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      harness.dispose();
    });
    harness.liveTv.favorites.complete(const []);
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.liveTv.showAllChannels));
    await tester.pumpAndSettle();
    expect(_guideChannels(tester).map((channel) => channel.key), ['channel-a', 'channel-b']);

    harness.liveTv.channelsFailure = StateError('offline');
    await tester.tap(find.byIcon(Symbols.refresh_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(_guideChannels(tester).map((channel) => channel.key), ['channel-a', 'channel-b']);
    expect(find.text(t.errors.unableToLoad(context: t.liveTv.title)), findsOneWidget);
    expect(find.text(t.liveTv.noChannels), findsNothing);
  });

  testWidgets('a first load that fails on every server shows the error state', (tester) async {
    final harness = await _pumpLiveTvScreen(tester, channelsFailure: StateError('offline'));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      harness.dispose();
    });

    expect(find.text(t.errors.unableToLoad(context: t.liveTv.title)), findsOneWidget);
    expect(find.text(t.liveTv.noChannels), findsNothing);
  });

  testWidgets('guide refresh reports a DVR reload failure instead of success', (tester) async {
    final dvr = _FakeLiveTvDvrSupport(reloadFailure: StateError('reload failed'));
    final harness = await _pumpLiveTvScreen(tester, dvr: dvr);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      harness.dispose();
    });
    harness.liveTv.favorites.complete(const []);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Symbols.refresh_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(dvr.reloadedDvrKeys, ['dvr-a']);
    expect(find.text(t.liveTv.guideReloadFailed), findsOneWidget);
    expect(find.text(t.liveTv.guideReloadRequested), findsNothing);
  });

  testWidgets('guide refresh names the admin requirement when the DVR rejects it with 403', (tester) async {
    final dvr = _FakeLiveTvDvrSupport(
      reloadFailure: MediaServerHttpException(type: MediaServerHttpErrorType.unknown, statusCode: 403),
    );
    final harness = await _pumpLiveTvScreen(tester, dvr: dvr);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      harness.dispose();
    });
    harness.liveTv.favorites.complete(const []);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Symbols.refresh_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(t.liveTv.dvrAdminRequired), findsOneWidget);
    expect(find.text(t.liveTv.guideReloadRequested), findsNothing);
  });
}

FocusNode _guideFocusNode(WidgetTester tester) => tester
    .widget<Focus>(find.byWidgetPredicate((widget) => widget is Focus && widget.focusNode?.debugLabel == 'guide_tab'))
    .focusNode!;

List<LiveTvChannel> _guideChannels(WidgetTester tester) => tester.widget<GuideTab>(find.byType(GuideTab)).channels;

Map<String, String> _channelGroups() => const {'channel-a': 'News', 'channel-b': 'News', 'channel-c': 'Sport'};

Future<_LiveTvHarness> _pumpLiveTvScreen(
  WidgetTester tester, {
  List<String>? channelKeys,
  Map<String, String>? channelGroups,
  _FakeLiveTvDvrSupport? dvr,
  AppThemeVariant variant = AppThemeVariant.standard,
  Object? channelsFailure,
}) async {
  final liveTv = _FakeLiveTvSupport(channelKeys: channelKeys, channelGroups: channelGroups ?? const {}, dvr: dvr)
    ..channelsFailure = channelsFailure;
  final client = _FakeMediaServerClient(liveTv);
  final manager = MultiServerManager()..debugRegisterClientForTesting(client);
  final provider = testMultiServerProvider(manager);
  provider.debugSetLiveTvServersForTesting([
    LiveTvServerInfo(serverId: client.serverId.value, dvrKey: 'dvr-a', lineup: 'provider-a'),
  ]);
  final layout = LiveTvChannelLayoutProvider(profileId: 'profile-1');
  final harness = _LiveTvHarness(manager: manager, provider: provider, liveTv: liveTv, layout: layout);

  await tester.pumpWidget(
    TranslationProvider(
      child: InputModeTracker(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<MultiServerProvider>.value(value: provider),
            ChangeNotifierProvider<LiveTvChannelLayoutProvider>.value(value: layout),
          ],
          child: MaterialApp(
            theme: monoTheme(dark: true, variant: variant),
            home: const LiveTvScreen(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

class _LiveTvHarness {
  const _LiveTvHarness({required this.manager, required this.provider, required this.liveTv, required this.layout});

  final MultiServerManager manager;
  final MultiServerProvider provider;
  final _FakeLiveTvSupport liveTv;
  final LiveTvChannelLayoutProvider layout;

  void dispose() {
    layout.dispose();
    provider.dispose();
    manager.dispose();
  }
}

class _FakeMediaServerClient implements MediaServerClient {
  _FakeMediaServerClient(this.liveTv, {ServerId? serverId}) : serverId = serverId ?? ServerId('server-a');

  @override
  final LiveTvSupport liveTv;

  @override
  final ServerId serverId;

  @override
  String? get serverName => 'Server ${serverId.value}';

  @override
  MediaBackend get backend => MediaBackend.jellyfin;

  @override
  ServerCapabilities get capabilities => ServerCapabilities(liveTv: true, liveTvDvr: liveTv.dvr != null);

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLiveTvSupport implements LiveTvSupport {
  _FakeLiveTvSupport({
    this.serverId = 'server-a',
    this.storeKey = 'test-store',
    List<String>? channelKeys,
    this.channelGroups = const {},
    this.dvr,
  }) : channelKeys = channelKeys ?? [serverId == 'server-a' ? 'channel-a' : 'channel-$serverId'];

  final String serverId;
  final String storeKey;
  final List<String> channelKeys;

  /// Channel key → the group it belongs to, as a playlist's `group-title` or
  /// an Xtream category arrives.
  final Map<String, String> channelGroups;
  Object? channelsFailure;
  final List<Completer<List<FavoriteChannel>>> _favoriteRequests = [];
  int _servedFavoriteRequests = 0;

  Completer<List<FavoriteChannel>> get favorites {
    if (_favoriteRequests.length > _servedFavoriteRequests) {
      return _favoriteRequests[_servedFavoriteRequests];
    }
    if (_servedFavoriteRequests > 0 && !_favoriteRequests[_servedFavoriteRequests - 1].isCompleted) {
      return _favoriteRequests[_servedFavoriteRequests - 1];
    }
    final request = Completer<List<FavoriteChannel>>();
    _favoriteRequests.add(request);
    return request;
  }

  @override
  final LiveTvDvrSupport? dvr;

  @override
  String get favoriteStoreKey => storeKey;

  @override
  FavoriteChannelPersistenceMode get favoritePersistenceMode => FavoriteChannelPersistenceMode.serverSlice;

  @override
  Future<String> buildFavoriteChannelSource({String? lineup}) async => 'server://$serverId/${lineup ?? 'default'}';

  @override
  Future<List<LiveTvChannel>> fetchChannels({String? lineup}) async => [
    if (channelsFailure case final failure?) throw failure,
    for (final key in channelKeys)
      LiveTvChannel(
        key: key,
        title: key == 'channel-a' ? 'Unique Channel A' : 'Unique Channel $key',
        serverId: serverId,
        lineup: channelGroups[key],
      ),
  ];

  /// How often the guide asked for programmes.
  int scheduleRequests = 0;

  @override
  Future<List<LiveTvProgram>> fetchSchedule({DateTime? from, DateTime? to}) async {
    scheduleRequests++;
    return const [];
  }

  @override
  Future<List<FavoriteChannel>> fetchFavoriteChannels({bool migrate = true, void Function()? checkCurrent}) {
    if (_favoriteRequests.length == _servedFavoriteRequests) {
      _favoriteRequests.add(Completer<List<FavoriteChannel>>());
    }
    return _favoriteRequests[_servedFavoriteRequests++].future;
  }

  final List<Object> writeFailures = [];
  final List<List<FavoriteChannel>> writes = [];

  @override
  Future<void> setFavoriteChannels(List<FavoriteChannel> channels, {void Function()? checkCurrent}) async {
    checkCurrent?.call();
    writes.add(List.of(channels));
    if (writeFailures.isNotEmpty) throw writeFailures.removeAt(0);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLiveTvDvrSupport implements LiveTvDvrSupport {
  _FakeLiveTvDvrSupport({this.reloadFailure});

  final Object? reloadFailure;
  final List<String> reloadedDvrKeys = [];

  @override
  bool get supportsRuleProcessing => false;

  @override
  Future<void> reloadGuide(String dvrId) async {
    reloadedDvrKeys.add(dvrId);
    if (reloadFailure != null) throw reloadFailure!;
  }

  // The Recordings tab is built alongside the guide once a DVR exists.
  @override
  Future<List<MediaGrabOperation>> fetchScheduledRecordings() async => const [];

  @override
  Future<List<MediaSubscription>> fetchRecordingRules({bool includeGrabs = true, bool includeStorage = true}) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
