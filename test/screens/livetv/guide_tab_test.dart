import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/live_tv_support.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/media/server_capabilities.dart';
import 'package:plezy/focus/dpad_navigator.dart';
import 'package:plezy/focus/dpad_select_long_press_controller.dart';
import 'package:plezy/models/livetv_channel.dart';
import 'package:plezy/models/livetv_program.dart';
import 'package:plezy/screens/livetv/guide_preview_panel.dart';
import 'package:plezy/screens/livetv/guide_preview_player.dart';
import 'package:plezy/screens/livetv/tabs/guide_tab.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/providers/iptv_sources_provider.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/services/iptv/iptv_live_tv_source.dart';
import 'package:plezy/services/iptv/iptv_source.dart';
import 'package:plezy/services/live_tv_last_selection.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/widgets/app_icon.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/multi_server_fixtures.dart';
import '../../test_helpers/prefs.dart';

const _selectDown = KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.enter,
  logicalKey: LogicalKeyboardKey.enter,
  timeStamp: Duration.zero,
);

LiveTvChannel _channel({String key = 'channel/7'}) =>
    LiveTvChannel(key: key, identifier: 'station-7', callSign: 'SEVEN', serverId: 'server-a', liveDvrKey: 'dvr-a');

LiveTvProgram _program({String ratingKey = 'program/42', int beginsAt = 1_800_000_000, int endsAt = 1_800_003_600}) =>
    LiveTvProgram(
      ratingKey: ratingKey,
      title: 'Evening News',
      beginsAt: beginsAt,
      endsAt: endsAt,
      channelIdentifier: 'station-7',
      serverId: 'server-a',
      liveDvrKey: 'dvr-a',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('en'));
  setUp(() {
    LocaleSettings.setLocaleSync(AppLocale.en);
    TvDetectionService.debugSetAppleTVOverride(false);
    // Say which host this is, rather than inheriting the machine running the
    // suite: the preview band is drawn on a television *and* on a desktop
    // window with room for it, so "not a television" alone no longer decides
    // whether the guide has one. The cases that want the band turn the
    // television on for themselves.
    PlatformDetector.debugSetIsDesktopOSOverride(false);
  });
  tearDown(() {
    SelectKeyUpSuppressor.clearSuppression();
    TvDetectionService.debugSetAppleTVOverride(null);
    PlatformDetector.debugSetIsDesktopOSOverride(null);
  });

  test('SELECT hold survives equivalent fresh guide objects and opens details once', () {
    fakeAsync((async) {
      final controller = DpadSelectLongPressController();
      var focusedChannel = _channel();
      var focusedProgram = _program();
      final pressedIdentity = guideAiringIdentity(focusedChannel, focusedProgram);
      var detailsOpened = 0;

      controller.handleKeyEvent(
        _selectDown,
        isOwnerActive: () => guideAiringIdentity(focusedChannel, focusedProgram) == pressedIdentity,
        onShortPress: () {},
        onLongPress: () {
          controller.reset();
          detailsOpened++;
        },
      );

      async.elapse(const Duration(milliseconds: 250));
      final replacementChannel = _channel();
      final replacementProgram = _program();
      expect(identical(replacementChannel, focusedChannel), isFalse);
      expect(identical(replacementProgram, focusedProgram), isFalse);
      focusedChannel = replacementChannel;
      focusedProgram = replacementProgram;

      async.elapse(const Duration(milliseconds: 249));
      expect(detailsOpened, 0);
      async.elapse(const Duration(milliseconds: 1));
      expect(detailsOpened, 1);

      async.elapse(const Duration(seconds: 1));
      expect(detailsOpened, 1);
      controller.dispose();
    });
  });

  test('SELECT hold does not open details after focus moves to a different airing', () {
    fakeAsync((async) {
      final controller = DpadSelectLongPressController();
      final focusedChannel = _channel();
      var focusedProgram = _program();
      final pressedIdentity = guideAiringIdentity(focusedChannel, focusedProgram);
      var detailsOpened = 0;

      controller.handleKeyEvent(
        _selectDown,
        isOwnerActive: () => guideAiringIdentity(focusedChannel, focusedProgram) == pressedIdentity,
        onShortPress: () {},
        onLongPress: () => detailsOpened++,
      );

      async.elapse(const Duration(milliseconds: 250));
      focusedProgram = _program(beginsAt: 1_800_003_600, endsAt: 1_800_007_200);
      expect(guideAiringIdentity(focusedChannel, focusedProgram), isNot(pressedIdentity));

      async.elapse(const Duration(milliseconds: 250));
      expect(detailsOpened, 0);
      async.elapse(const Duration(seconds: 1));
      expect(detailsOpened, 0);
      controller.dispose();
    });
  });

  testWidgets('superseded guide load keeps one interval and cannot replace current programs', (tester) async {
    final harness = _GuideHarness.twoServers();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await harness.completeInitial(tester);

    final rightButton = _rightTimeButton();
    expect(rightButton, findsOneWidget);
    await tester.tap(rightButton);
    await tester.tap(rightButton);

    expect(harness.serverA.schedule.requests, hasLength(3));
    final older = harness.serverA.schedule.requests[1];
    final newer = harness.serverA.schedule.requests[2];
    expect(older.to.difference(older.from), const Duration(hours: 6));
    expect(newer.to.difference(newer.from), const Duration(hours: 6));
    expect(newer.from.difference(older.from), const Duration(hours: 2));

    harness.serverA.schedule.complete(2, 'Current A');
    await tester.pump();
    expect(harness.serverB!.schedule.requests, hasLength(2));
    final currentB = harness.serverB!.schedule.requests[1];
    expect(currentB.from, newer.from);
    expect(currentB.to, newer.to);

    harness.serverB!.schedule.complete(1, 'Current B');
    await tester.pumpAndSettle();
    expect(find.text('Current A'), findsOneWidget);
    expect(find.text('Current B'), findsOneWidget);

    harness.serverA.schedule.complete(1, 'Obsolete A');
    await tester.pump();
    await tester.pump();
    expect(harness.serverB!.schedule.requests, hasLength(2));
    expect(find.text('Obsolete A'), findsNothing);
    expect(find.text('Current A'), findsOneWidget);
    expect(find.text('Current B'), findsOneWidget);
  });

  testWidgets('obsolete completion cannot clear loading owned by a newer guide request', (tester) async {
    final harness = _GuideHarness.oneServer();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await harness.completeInitial(tester);

    final rightButton = _rightTimeButton();
    await tester.tap(rightButton);
    await tester.tap(rightButton);
    expect(harness.serverA.schedule.requests, hasLength(3));

    harness.serverA.schedule.complete(1, 'Obsolete');
    await tester.pump();
    await tester.pump();
    // In-session reloads keep the guide mounted: the indicator is the
    // lightweight overlay rather than a full-screen spinner, and the guide
    // Focus + day chip stay in the tree so D-pad navigation survives.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.byWidgetPredicate((widget) => widget is Focus && widget.focusNode?.debugLabel == 'guide_tab'),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate((widget) => widget is AppIcon && widget.icon == Symbols.arrow_drop_down_rounded),
      findsOneWidget,
    );
    expect(find.text('Obsolete'), findsNothing);
  });

  testWidgets('picking a day applies it immediately and slot-menu dismissal keeps it', (tester) async {
    final harness = _GuideHarness.oneServer();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await harness.completeInitial(tester);

    _guideTabFocusNode(tester).requestFocus();
    await tester.pump();

    await _openDayPicker(tester);
    // The day menu labels tomorrow via the translation.
    expect(find.text(t.liveTv.tomorrow), findsOneWidget);
    await _selectTomorrowInDayMenu(tester);

    // The picked day is applied right away: a fetch for it already went out,
    // keeping the current window's time-of-day.
    final requests = harness.serverA.schedule.requests;
    expect(requests, hasLength(2));
    final first = requests[0];
    final dayRequest = requests[1];
    final gridStartLocal = first.from.toLocal();
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    final expectedFrom = DateTime(
      tomorrow.year,
      tomorrow.month,
      tomorrow.day,
      gridStartLocal.hour,
      gridStartLocal.minute,
    ).toUtc();
    expect(dayRequest.from, expectedFrom);
    expect(dayRequest.to, expectedFrom.add(const Duration(hours: 6)));

    // Dismissing the refinement menu keeps the already-applied day, and the
    // day chip renders the picked day via the translation too.
    await tester.tapAt(const Offset(1270, 700));
    await _pumpMenuTransition(tester);
    expect(harness.serverA.schedule.requests, hasLength(2));
    expect(find.text(t.liveTv.tomorrow), findsOneWidget);
  });

  testWidgets('picking a slot after the day refines the window to that slot', (tester) async {
    final harness = _GuideHarness.oneServer();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await harness.completeInitial(tester);

    _guideTabFocusNode(tester).requestFocus();
    await tester.pump();
    await _openDayPicker(tester);
    await _selectTomorrowInDayMenu(tester);
    expect(harness.serverA.schedule.requests, hasLength(2));

    await tester.tap(find.text(t.liveTv.morning));
    await _pumpMenuTransition(tester);

    final requests = harness.serverA.schedule.requests;
    expect(requests, hasLength(3));
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    final expectedFrom = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 6).toUtc();
    expect(requests[2].from, expectedFrom);
    expect(requests[2].to, expectedFrom.add(const Duration(hours: 6)));
  });

  testWidgets('after a day change completes the guide keeps D-pad focus', (tester) async {
    final harness = _GuideHarness.oneServer();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await harness.completeInitial(tester);

    _guideTabFocusNode(tester).requestFocus();
    await tester.pump();
    await _openDayPicker(tester);
    await _selectTomorrowInDayMenu(tester);

    // Dismiss the refinement menu without picking: focus returns to the guide.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _pumpMenuTransition(tester);
    expect(_guideTabFocusNode(tester).hasFocus, isTrue);

    // Completing the day fetch must not drop focus (the remote stays alive).
    harness.serverA.schedule.complete(1, 'Tomorrow Programs');
    await tester.pumpAndSettle();
    expect(_guideTabFocusNode(tester).hasFocus, isTrue);
    expect(find.text('Tomorrow Programs'), findsOneWidget);
  });

  testWidgets('horizontal guide virtualization keeps the D-pad focus target rendered', (tester) async {
    final harness = _GuideHarness.oneServer();
    addTearDown(harness.dispose);
    await harness.pump(tester);

    harness.serverA.schedule.completeSlots(0, 12);
    await tester.pumpAndSettle();
    expect(find.text('Slot 12'), findsNothing);

    final guideFocus = tester.widget<Focus>(
      find.byWidgetPredicate((widget) => widget is Focus && widget.focusNode?.debugLabel == 'guide_tab'),
    );
    guideFocus.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    for (var index = 0; index < 12; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }

    final primary = Theme.of(tester.element(find.byType(GuideTab))).colorScheme.primary;
    final focusedMaterial = find.byWidgetPredicate((widget) => widget is Material && widget.color == primary);
    expect(find.text('Slot 1'), findsNothing);
    expect(find.text('Slot 12'), findsOneWidget);
    expect(find.ancestor(of: find.text('Slot 12'), matching: focusedMaterial), findsOneWidget);
  });

  testWidgets('vertical navigation follows displayed source-group order, not flat channel order', (tester) async {
    // Flat list mirrors live_tv_screen ordering: number-sorted across servers,
    // which interleaves the two source groups when numbers overlap.
    final harness = _GuideHarness.twoServersWithChannels([
      _guideChannel(serverId: 'server-a', stationId: 'st-a1', callSign: 'A1', number: '1'),
      _guideChannel(serverId: 'server-a', stationId: 'st-a2', callSign: 'A2', number: '2'),
      _guideChannel(serverId: 'server-b', stationId: 'st-b21', callSign: 'B21', number: '2.1'),
      _guideChannel(serverId: 'server-a', stationId: 'st-a3', callSign: 'A3', number: '3'),
      _guideChannel(serverId: 'server-a', stationId: 'st-a4', callSign: 'A4', number: '4'),
      _guideChannel(serverId: 'server-b', stationId: 'st-b41', callSign: 'B41', number: '4.1'),
      _guideChannel(serverId: 'server-b', stationId: 'st-b43', callSign: 'B43', number: '4.3'),
      _guideChannel(serverId: 'server-b', stationId: 'st-b44', callSign: 'B44', number: '4.4'),
      _guideChannel(serverId: 'server-a', stationId: 'st-a5', callSign: 'A5', number: '5'),
      _guideChannel(serverId: 'server-b', stationId: 'st-b51', callSign: 'B51', number: '5.1'),
    ]);
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await harness.completeInitialEmpty(tester);

    await _focusGrid(tester);
    _expectFocusedChannel(tester, 'A1');

    const displayOrder = ['A1', 'A2', 'A3', 'A4', 'A5', 'B21', 'B41', 'B43', 'B44', 'B51'];
    for (final callSign in displayOrder.skip(1)) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      _expectFocusedChannel(tester, callSign);
    }

    // Down on the last displayed row is a no-op.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    _expectFocusedChannel(tester, 'B51');

    for (final callSign in displayOrder.reversed.skip(1)) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      _expectFocusedChannel(tester, callSign);
    }
  });

  testWidgets('down reaches the last displayed row when the flat-last channel sits mid-guide', (tester) async {
    // Flat order: 1 (A), 2 (B), 10 (A). Displayed order groups by source:
    // A1, A10, then B2 — the flat-last channel is not the displayed-last row.
    final harness = _GuideHarness.twoServersWithChannels([
      _guideChannel(serverId: 'server-a', stationId: 'st-a1', callSign: 'A1', number: '1'),
      _guideChannel(serverId: 'server-b', stationId: 'st-b2', callSign: 'B2', number: '2'),
      _guideChannel(serverId: 'server-a', stationId: 'st-a10', callSign: 'A10', number: '10'),
    ]);
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await harness.completeInitialEmpty(tester);

    await _focusGrid(tester);
    _expectFocusedChannel(tester, 'A1');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    _expectFocusedChannel(tester, 'A10');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    _expectFocusedChannel(tester, 'B2');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    _expectFocusedChannel(tester, 'B2');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    _expectFocusedChannel(tester, 'A10');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    _expectFocusedChannel(tester, 'A1');

    // Up on the first displayed row exits the grid to the time navigation.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(_focusedCellFinder(tester), findsNothing);
  });

  testWidgets('an IPTV source contributes its guide, with no server involved', (tester) async {
    // The regression this guards: the guide only ever asked the media
    // servers, so an IPTV channel showed "no programs" however complete its
    // XMLTV guide was.
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();

    final now = DateTime.now().toUtc();
    String xmltvTime(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}${value.month.toString().padLeft(2, '0')}'
        '${value.day.toString().padLeft(2, '0')}${value.hour.toString().padLeft(2, '0')}'
        '${value.minute.toString().padLeft(2, '0')}00 +0000';
    final guide =
        '''
<tv>
  <programme start="${xmltvTime(now.subtract(const Duration(minutes: 30)))}" stop="${xmltvTime(now.add(const Duration(minutes: 30)))}" channel="das-erste.de">
    <title>Tagesschau</title>
  </programme>
</tv>
''';
    const playlist = '''
#EXTM3U
#EXTINF:-1 tvg-id="das-erste.de",Das Erste HD
http://provider/stream/ard
''';

    final iptv = IptvSourcesProvider(
      profileId: 'profile-1',
      buildSource: (source) => IptvLiveTvSource(
        source,
        httpClient: MockClient(
          (request) async => http.Response(request.url.path.endsWith('.m3u') ? playlist : guide, 200),
        ),
      ),
    );
    addTearDown(iptv.dispose);
    await iptv.save(
      const IptvSource(
        id: 'src',
        name: 'Mein IPTV',
        kind: IptvSourceKind.m3u,
        playlistUrl: 'http://provider/list.m3u',
        epgUrls: ['http://provider/epg.xml'],
      ),
    );

    final multiServer = testMultiServerProvider(MultiServerManager());
    addTearDown(multiServer.dispose);

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    await tester.pumpWidget(
      TranslationProvider(
        child: InputModeTracker(
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
              ChangeNotifierProvider<IptvSourcesProvider>.value(value: iptv),
            ],
            child: MaterialApp(
              theme: monoTheme(dark: true),
              home: Scaffold(
                body: GuideTab(
                  channels: [
                    LiveTvChannel(
                      key: 'iptv:src:das-erste.de',
                      identifier: 'das-erste.de',
                      title: 'Das Erste HD',
                      serverId: 'src',
                      serverName: 'Mein IPTV',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // The playlist and guide are fetched and parsed for real (the XMLTV parse
    // runs on its own isolate), so the load needs wall-clock time rather than
    // pumped frames.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Tagesschau'), findsOneWidget);
  });

  /// The band -- live picture, title of what is on, description -- used to be
  /// drawn only on a television, which left every desktop window with a bare
  /// grid: no picture, no title, nothing written anywhere. The rule it was
  /// always meant to follow is room, and a window can have it.
  Future<void> pumpDesktopGuide(WidgetTester tester, Size size) async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    TvDetectionService.debugSetAppleTVOverride(false);
    PlatformDetector.debugSetIsDesktopOSOverride(true);
    GuidePreviewPlayerState.debugSuppressPlayback = true;
    addTearDown(() => GuidePreviewPlayerState.debugSuppressPlayback = false);

    final multiServer = testMultiServerProvider(MultiServerManager());
    addTearDown(multiServer.dispose);

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    await tester.pumpWidget(
      TranslationProvider(
        child: InputModeTracker(
          child: MultiProvider(
            providers: [ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer)],
            child: MaterialApp(
              theme: monoTheme(dark: true),
              home: Scaffold(body: GuideTab(channels: [_channel()])),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('a desktop window with room for it gets the band', (tester) async {
    await pumpDesktopGuide(tester, const Size(1280, 720));

    expect(find.byType(GuidePreviewPanel), findsOneWidget);
  });

  testWidgets('a window too small keeps the whole height for the schedule', (tester) async {
    // Seven tenths of 500 is the eight rows at their floor and nothing over:
    // below this the band would be bought with the guide itself.
    await pumpDesktopGuide(tester, const Size(1280, 500));

    expect(find.byType(GuidePreviewPanel), findsNothing);
  });

  testWidgets('the preview box is 16:9, not as wide as the band lets it be', (tester) async {
    // A row hands its children a tight height, so asking an AspectRatio for
    // 16:9 inside a fixed width did nothing at all: the box came out as tall
    // as the band and as wide as it was told.
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    TvDetectionService.debugSetAppleTVOverride(true);
    GuidePreviewPlayerState.debugSuppressPlayback = true;
    addTearDown(() => GuidePreviewPlayerState.debugSuppressPlayback = false);

    final multiServer = testMultiServerProvider(MultiServerManager());
    addTearDown(multiServer.dispose);

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 600);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    await tester.pumpWidget(
      TranslationProvider(
        child: InputModeTracker(
          child: MultiProvider(
            providers: [ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer)],
            child: MaterialApp(
              theme: monoTheme(dark: true),
              home: Scaffold(body: GuideTab(channels: [_channel()])),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final box = tester.getSize(find.byType(GuidePreviewPlayer));
    expect(box.width / box.height, closeTo(16 / 9, 0.02));
  });

  testWidgets('with the time strip hidden, one press leaves the grid upwards', (tester) async {
    // The strip is a focus stop of its own. Hidden, it still took a press and
    // showed nothing for it — the cursor seemed to vanish for a beat somewhere
    // above the grid.
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.liveTvGuideTimeNavigation, false);
    TvDetectionService.debugSetAppleTVOverride(true);
    GuidePreviewPlayerState.debugSuppressPlayback = true;
    addTearDown(() => GuidePreviewPlayerState.debugSuppressPlayback = false);

    final multiServer = testMultiServerProvider(MultiServerManager());
    addTearDown(multiServer.dispose);

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 600);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    var leftUpwards = 0;
    await tester.pumpWidget(
      TranslationProvider(
        child: InputModeTracker(
          child: MultiProvider(
            providers: [ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer)],
            child: MaterialApp(
              theme: monoTheme(dark: true),
              home: Scaffold(
                body: GuideTab(channels: [_channel()], onNavigateUp: () => leftUpwards++),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final guideFocus = tester.widget<Focus>(
      find.byWidgetPredicate((widget) => widget is Focus && widget.focusNode?.debugLabel == 'guide_tab'),
    );
    guideFocus.focusNode!.requestFocus();
    await tester.pump();
    // Into the grid, then straight back out of the top of it.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();

    expect(leftUpwards, 1);
  });

  testWidgets('LEFT on a channel opens the groups where the host offers them', (tester) async {
    // TiviMate's gesture: at the left edge of the channel column, LEFT is
    // "step out one level" rather than "leave the guide" — but only where the
    // host has a column of groups to open. Without one, LEFT still leaves.
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.liveTvGuideTimeNavigation, false);
    TvDetectionService.debugSetAppleTVOverride(true);
    GuidePreviewPlayerState.debugSuppressPlayback = true;
    addTearDown(() => GuidePreviewPlayerState.debugSuppressPlayback = false);

    final multiServer = testMultiServerProvider(MultiServerManager());
    addTearDown(multiServer.dispose);

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 600);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    var opened = 0;
    var left = 0;
    await tester.pumpWidget(
      TranslationProvider(
        child: InputModeTracker(
          child: MultiProvider(
            providers: [ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer)],
            child: MaterialApp(
              theme: monoTheme(dark: true),
              home: Scaffold(
                body: GuideTab(channels: [_channel()], onBack: () => left++, onOpenGroups: () => opened++),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final guideFocus = tester.widget<Focus>(
      find.byWidgetPredicate((widget) => widget is Focus && widget.focusNode?.debugLabel == 'guide_tab'),
    );
    guideFocus.focusNode!.requestFocus();
    await tester.pump();
    // Into the grid, standing on the channel column, then LEFT.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();

    expect(opened, 1);
    expect(left, 0, reason: 'the guide is not left when there is a column to step into');
  });

  testWidgets('BACK leaves the schedule for the group it was read in', (tester) async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    TvDetectionService.debugSetAppleTVOverride(true);
    GuidePreviewPlayerState.debugSuppressPlayback = true;
    addTearDown(() => GuidePreviewPlayerState.debugSuppressPlayback = false);

    final multiServer = testMultiServerProvider(MultiServerManager());
    addTearDown(multiServer.dispose);

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 600);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    var leftUpwards = 0;
    await tester.pumpWidget(
      TranslationProvider(
        child: InputModeTracker(
          child: MultiProvider(
            providers: [ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer)],
            child: MaterialApp(
              theme: monoTheme(dark: true),
              home: Scaffold(
                body: GuideTab(channels: [_channel()], onNavigateUp: () => leftUpwards++),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final guideFocus = tester.widget<Focus>(
      find.byWidgetPredicate((widget) => widget is Focus && widget.focusNode?.debugLabel == 'guide_tab'),
    );
    guideFocus.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    // Escape rather than the TV back key: the test simulator has no physical
    // mapping for that one, and the guide treats both alike.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    // Not one row up into the time strip: out of the schedule, to the bar the
    // schedule was scoped by.
    expect(leftUpwards, 1);
  });

  group('BACK deep in the grid', () {
    Future<(GuideTabState, int Function())> pumpGuide(WidgetTester tester, List<LiveTvChannel> channels) async {
      resetSharedPreferencesForTest();
      SettingsService.resetForTesting();
      await SettingsService.getInstance();
      TvDetectionService.debugSetAppleTVOverride(true);
      addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
      GuidePreviewPlayerState.debugSuppressPlayback = true;
      addTearDown(() => GuidePreviewPlayerState.debugSuppressPlayback = false);
      LiveTvLastSelection.instance.resetForTest();
      addTearDown(LiveTvLastSelection.instance.resetForTest);

      final multiServer = testMultiServerProvider(MultiServerManager());
      addTearDown(multiServer.dispose);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 600);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });

      var leftUpwards = 0;
      await tester.pumpWidget(
        TranslationProvider(
          child: InputModeTracker(
            child: MultiProvider(
              providers: [ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer)],
              child: MaterialApp(
                theme: monoTheme(dark: true),
                home: Scaffold(
                  body: GuideTab(channels: channels, onNavigateUp: () => leftUpwards++),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final focus = tester.widget<Focus>(
        find.byWidgetPredicate((widget) => widget is Focus && widget.focusNode?.debugLabel == 'guide_tab'),
      );
      focus.focusNode!.requestFocus();
      await tester.pump();
      return (tester.state<GuideTabState>(find.byType(GuideTab)), () => leftUpwards);
    }

    List<LiveTvChannel> threeChannels() => [
      for (var i = 1; i <= 3; i++)
        LiveTvChannel(key: 'channel/$i', identifier: 'station-$i', callSign: 'CH$i', serverId: 'server-a'),
    ];

    Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }

    testWidgets('comes home to the first channel before it leaves the grid', (tester) async {
      final (guide, leftUpwards) = await pumpGuide(tester, threeChannels());
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(guide.debugCursorChannelIndex, 2);

      await press(tester, LogicalKeyboardKey.escape);
      expect(guide.debugCursorChannelIndex, 0, reason: 'home first');
      expect(guide.debugCursorColumn, 0, reason: 'on the logo at the far left, not on a programme');
      expect(leftUpwards(), 0, reason: 'not straight up into the navigation');

      await press(tester, LogicalKeyboardKey.escape);
      expect(leftUpwards(), 1, reason: 'from home, BACK leaves the schedule');
    });

    testWidgets('home is the channel last watched full screen', (tester) async {
      final channels = threeChannels();
      final (guide, leftUpwards) = await pumpGuide(tester, channels);
      LiveTvLastSelection.instance.record(channelKey: liveTvChannelScopeKey(channels[1]), group: null);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(guide.debugCursorChannelIndex, 0);

      await press(tester, LogicalKeyboardKey.escape);
      expect(guide.debugCursorChannelIndex, 1);
      expect(guide.debugCursorColumn, 0);
      expect(leftUpwards(), 0);
    });
  });

  for (final withMenu in [false, true]) {
    testWidgets(
      'SELECT on a channel previews it rather than opening full screen${withMenu ? ', with its hold menu wired' : ''}',
      (tester) async {
        // With a hold action wired — as the Live TV screen always does — the
        // hold-aware SELECT handler caught the press first and went straight to
        // full screen.
        // The programme cells took the two steps; the channel column still went
        // straight to full screen, so the same press meant two different things
        // one column apart.
        resetSharedPreferencesForTest();
        SettingsService.resetForTesting();
        await SettingsService.getInstance();
        TvDetectionService.debugSetAppleTVOverride(true);
        GuidePreviewPlayerState.debugSuppressPlayback = true;
        addTearDown(() => GuidePreviewPlayerState.debugSuppressPlayback = false);

        final multiServer = testMultiServerProvider(MultiServerManager());
        addTearDown(multiServer.dispose);

        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1280, 600);
        addTearDown(() {
          tester.view.resetDevicePixelRatio();
          tester.view.resetPhysicalSize();
        });

        final fullScreen = <String>[];
        final channel = LiveTvChannel(
          key: 'channel/1',
          identifier: 'station-1',
          title: 'Sender 1',
          serverId: 'server-a',
        );

        await tester.pumpWidget(
          TranslationProvider(
            child: InputModeTracker(
              child: MultiProvider(
                providers: [ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer)],
                child: MaterialApp(
                  theme: monoTheme(dark: true),
                  home: Scaffold(
                    body: GuideTab(
                      channels: [channel],
                      onPlayChannel: (played) async => fullScreen.add(played.key),
                      onChannelMenu: withMenu ? (_) {} : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final guideFocus = tester.widget<Focus>(
          find.byWidgetPredicate((widget) => widget is Focus && widget.focusNode?.debugLabel == 'guide_tab'),
        );
        guideFocus.focusNode!.requestFocus();
        await tester.pump();
        // Into the grid, on the channel column.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();

        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pump();

        final panel = tester.widget<GuidePreviewPanel>(find.byType(GuidePreviewPanel));
        expect(panel.previewChannel?.key, channel.key);
        expect(fullScreen, isEmpty);

        // The second press on the same channel takes the whole screen.
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(fullScreen, [channel.key]);
      },
    );
  }

  testWidgets('six channels fit under the preview on a TV-sized guide', (tester) async {
    // What a guide is judged by: how much of the list you can compare at
    // once. Four rows was the complaint; the row height and the band's share
    // are set against this number, so it belongs in a test rather than in a
    // comment.
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    TvDetectionService.debugSetAppleTVOverride(true);
    GuidePreviewPlayerState.debugSuppressPlayback = true;
    addTearDown(() => GuidePreviewPlayerState.debugSuppressPlayback = false);

    final multiServer = testMultiServerProvider(MultiServerManager());
    addTearDown(multiServer.dispose);

    // The guide's own area on a 720p TV, once the app bar and the tab chips
    // above it have taken their share.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 600);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final channels = [
      for (var i = 0; i < 12; i++)
        LiveTvChannel(key: 'channel/$i', identifier: 'station-$i', title: 'Sender $i', serverId: 'server-a'),
    ];

    await tester.pumpWidget(
      TranslationProvider(
        child: InputModeTracker(
          child: MultiProvider(
            providers: [ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer)],
            child: MaterialApp(
              theme: monoTheme(dark: true),
              home: Scaffold(body: GuideTab(channels: channels)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final visible = [
      for (var i = 0; i < channels.length; i++)
        if (find.text('Sender $i').hitTestable().evaluate().isNotEmpty) i,
    ];

    expect(visible.length, greaterThanOrEqualTo(6), reason: 'four rows is too few to compare a schedule');
  });

  testWidgets('a new channel list is shown from its first channel', (tester) async {
    // Switching group replaces the list under a grid that keeps its scroll
    // offset: the new group opened wherever the previous one had been read,
    // swallowing its first channels until a key press dragged them into view.
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    TvDetectionService.debugSetAppleTVOverride(true);
    GuidePreviewPlayerState.debugSuppressPlayback = true;
    addTearDown(() => GuidePreviewPlayerState.debugSuppressPlayback = false);

    final multiServer = testMultiServerProvider(MultiServerManager());
    addTearDown(multiServer.dispose);

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 600);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final guideKey = GlobalKey<GuideTabState>();
    List<LiveTvChannel> group(String label) => [
      for (var i = 0; i < 20; i++)
        LiveTvChannel(key: '$label/$i', identifier: '$label-$i', title: '$label $i', serverId: 'server-a'),
    ];

    Future<void> pumpGuide(List<LiveTvChannel> channels) async {
      await tester.pumpWidget(
        TranslationProvider(
          child: InputModeTracker(
            child: MultiProvider(
              providers: [ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer)],
              child: MaterialApp(
                theme: monoTheme(dark: true),
                home: Scaffold(
                  body: GuideTab(key: guideKey, channels: channels),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    await pumpGuide(group('Erste'));
    // The second row, not the first: the preview band names the channel it is
    // showing, so row 0's title appears twice and cannot report the scroll.
    expect(find.text('Erste 1').hitTestable(), findsOneWidget);

    // Read the group a good way down, the way anyone browsing it would.
    await tester.dragFrom(const Offset(600, 400), const Offset(0, -240));
    await tester.pumpAndSettle();
    expect(find.text('Erste 1').hitTestable(), findsNothing, reason: 'the drag must actually leave the top');

    // The group switch: a different list, then the screen asks for its top.
    await pumpGuide(group('Zweite'));
    guideKey.currentState!.showFirstChannel();
    await tester.pumpAndSettle();

    expect(find.text('Zweite 1').hitTestable(), findsOneWidget);
  });

  testWidgets('a past programme still in the archive is not greyed out', (tester) async {
    // The whole marking: the grid already dims the past to mean "nothing to
    // get here", and an archive makes that false for some cells. Taking the
    // dimming away is what says so — no badge competes for a 48px row.
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    TvDetectionService.debugSetAppleTVOverride(true);
    GuidePreviewPlayerState.debugSuppressPlayback = true;
    addTearDown(() => GuidePreviewPlayerState.debugSuppressPlayback = false);

    final multiServer = testMultiServerProvider(MultiServerManager());
    addTearDown(multiServer.dispose);

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 600);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final channels = [
      LiveTvChannel(key: 'archived', identifier: 'arch', title: 'Mit Archiv', serverId: 'server-a', catchupDays: 7),
      LiveTvChannel(key: 'plain', identifier: 'plain', title: 'Ohne Archiv', serverId: 'server-a'),
    ];

    await tester.pumpWidget(
      TranslationProvider(
        child: InputModeTracker(
          child: MultiProvider(
            providers: [ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer)],
            child: MaterialApp(
              theme: monoTheme(dark: true),
              home: Scaffold(body: GuideTab(channels: channels)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Only the channel that keeps one is marked as keeping one.
    expect(find.byIcon(Symbols.history_rounded), findsOneWidget);
  });

  testWidgets('the time strip goes away when the setting says so', (tester) async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    final settings = await SettingsService.getInstance();
    TvDetectionService.debugSetAppleTVOverride(true);

    final multiServer = testMultiServerProvider(MultiServerManager());
    addTearDown(multiServer.dispose);

    Future<void> pumpGuide() async {
      await tester.pumpWidget(
        TranslationProvider(
          child: InputModeTracker(
            child: MultiProvider(
              providers: [ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer)],
              child: MaterialApp(
                theme: monoTheme(dark: true),
                home: Scaffold(body: GuideTab(channels: [_channel()])),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    await pumpGuide();
    expect(find.text(t.liveTv.today), findsOneWidget);

    await settings.write(SettingsService.liveTvGuideTimeNavigation, false);
    await pumpGuide();

    // Hidden, the guide opens on now and is travelled with the D-pad alone.
    expect(find.text(t.liveTv.today), findsNothing);
  });

  testWidgets('on TV the first press previews the channel and the second hands over', (tester) async {
    // TiVimate's shape: the picture opens small beside what is on, and only a
    // second press on the same channel takes the whole screen.
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    TvDetectionService.debugSetAppleTVOverride(true);
    // No playback core in a widget test; what is under test is which channel
    // the preview holds and when it lets go.
    GuidePreviewPlayerState.debugSuppressPlayback = true;
    addTearDown(() => GuidePreviewPlayerState.debugSuppressPlayback = false);

    final now = DateTime.now().toUtc();
    String xmltvTime(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}${value.month.toString().padLeft(2, '0')}'
        '${value.day.toString().padLeft(2, '0')}${value.hour.toString().padLeft(2, '0')}'
        '${value.minute.toString().padLeft(2, '0')}00 +0000';
    final guide =
        '''
<tv>
  <programme start="${xmltvTime(now.subtract(const Duration(minutes: 30)))}" stop="${xmltvTime(now.add(const Duration(minutes: 30)))}" channel="das-erste.de">
    <title>Tagesschau</title>
    <desc>Nachrichten aus aller Welt</desc>
  </programme>
</tv>
''';
    const playlist = '''
#EXTM3U
#EXTINF:-1 tvg-id="das-erste.de",Das Erste HD
http://provider/stream/ard
''';

    final iptv = IptvSourcesProvider(
      profileId: 'profile-1',
      buildSource: (source) => IptvLiveTvSource(
        source,
        httpClient: MockClient(
          (request) async => http.Response(request.url.path.endsWith('.m3u') ? playlist : guide, 200),
        ),
      ),
    );
    addTearDown(iptv.dispose);
    await iptv.save(
      const IptvSource(
        id: 'src',
        name: 'Mein IPTV',
        kind: IptvSourceKind.m3u,
        playlistUrl: 'http://provider/list.m3u',
        epgUrls: ['http://provider/epg.xml'],
      ),
    );

    final multiServer = testMultiServerProvider(MultiServerManager());
    addTearDown(multiServer.dispose);

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1920, 1080);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final fullScreen = <String>[];
    var previewHeldStream = true;
    final channel = LiveTvChannel(
      key: 'iptv:src:das-erste.de',
      identifier: 'das-erste.de',
      title: 'Das Erste HD',
      serverId: 'src',
      serverName: 'Mein IPTV',
    );

    await tester.pumpWidget(
      TranslationProvider(
        child: InputModeTracker(
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
              ChangeNotifierProvider<IptvSourcesProvider>.value(value: iptv),
            ],
            child: MaterialApp(
              theme: monoTheme(dark: true),
              home: Scaffold(
                body: GuideTab(
                  channels: [channel],
                  onPlayChannel: (played) async {
                    // Read at the moment the player is opened: the preview
                    // must have let the stream and the native core go by
                    // then, because the two cannot both hold them.
                    previewHeldStream = tester
                        .state<GuidePreviewPlayerState>(find.byType(GuidePreviewPlayer))
                        .isHoldingStream;
                    fullScreen.add(played.key);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // What is on stands beside the picture, not only in the grid cell.
    expect(find.text('Nachrichten aus aller Welt'), findsOneWidget);

    GuidePreviewPanel panel() => tester.widget<GuidePreviewPanel>(find.byType(GuidePreviewPanel));
    expect(panel().previewChannel, isNull, reason: 'nothing is tuned until a channel is chosen');

    // The title now appears twice — beside the picture and in the grid. The
    // grid cell is the one that can be pressed.
    final gridCell = find.descendant(of: find.byType(GuideTab), matching: find.text('Tagesschau')).hitTestable().last;

    await tester.tap(gridCell);
    await tester.pump();

    expect(panel().previewChannel?.key, channel.key, reason: 'the first press opens the small picture');

    expect(fullScreen, isEmpty, reason: 'the first press stays in the guide');

    await tester.tap(gridCell);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    // The second press hands the picture over: the preview releases the
    // native core (the two cannot both hold it) and the player opens.
    expect(fullScreen, [channel.key]);
    expect(previewHeldStream, isFalse, reason: 'the preview lets the stream and the core go first');
    // And when the viewer comes back from the player, the picture they left
    // is in the box again.
    expect(panel().previewChannel?.key, channel.key);
  });

  testWidgets('up/down in the program column keeps the focused time', (tester) async {
    final harness = _GuideHarness.twoServers();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    harness.serverA.schedule.completeSlots(0, 12);
    await tester.pump();
    harness.serverB!.schedule.completeSlots(0, 12);
    await tester.pumpAndSettle();

    await _focusGrid(tester);
    _expectFocusedChannel(tester, 'A');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    // The window opens an hour before the current half-hour, so what airs
    // now is always the third slot.
    expect(find.ancestor(of: find.text('Slot 3'), matching: _focusedCellFinder(tester)), findsOneWidget);
    for (var i = 0; i < 5; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
    }
    expect(find.ancestor(of: find.text('Slot 8'), matching: _focusedCellFinder(tester)), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    final focusedSlot8 = find.ancestor(of: find.text('Slot 8'), matching: _focusedCellFinder(tester));
    expect(focusedSlot8, findsOneWidget);
    // It is channel B's block, and it was scrolled into view.
    expect(tester.getCenter(focusedSlot8).dy, closeTo(tester.getCenter(find.text('B')).dy, 20));
    expect(tester.getRect(focusedSlot8).overlaps(tester.getRect(find.byType(GuideTab))), isTrue);
  });

  testWidgets('moving into a row with no programs focuses its channel cell', (tester) async {
    final harness = _GuideHarness.twoServers();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    harness.serverA.schedule.completeSlots(0, 12);
    await tester.pump();
    harness.serverB!.schedule.completeEmpty(0);
    await tester.pumpAndSettle();

    await _focusGrid(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.ancestor(of: find.text('Slot 3'), matching: _focusedCellFinder(tester)), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    _expectFocusedChannel(tester, 'B');
  });

  testWidgets('the context-menu key toggles the focused channel favorite once per press', (tester) async {
    final toggled = <String?>[];
    final harness = _GuideHarness.oneServer();
    addTearDown(harness.dispose);
    await harness.pump(tester, onToggleFavorite: (channel) => toggled.add(channel.callSign));
    await harness.completeInitialEmpty(tester);

    await _focusGrid(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.gameButtonX);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.gameButtonX);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.gameButtonX);
    await tester.pump();

    expect(toggled, ['A']);
  });

  testWidgets('on TV a SELECT hold on a channel cell toggles its favorite', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    final toggled = <String?>[];
    final harness = _GuideHarness.oneServer();
    addTearDown(harness.dispose);
    await harness.pump(tester, onToggleFavorite: (channel) => toggled.add(channel.callSign));
    await harness.completeInitialEmpty(tester);

    await _focusGrid(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(toggled, ['A']);
  });

  testWidgets('with a channel menu on offer, a SELECT hold opens it instead of flipping the favorite', (tester) async {
    // A hold used to toggle the favorite without a word; the screen now hands
    // the guide the channel's own menu — favourite, rename, hide.
    TvDetectionService.debugSetAppleTVOverride(true);
    final toggled = <String?>[];
    final menus = <String?>[];
    final harness = _GuideHarness.oneServer();
    addTearDown(harness.dispose);
    await harness.pump(
      tester,
      onToggleFavorite: (channel) => toggled.add(channel.callSign),
      onChannelMenu: (channel) => menus.add(channel.callSign),
    );
    await harness.completeInitialEmpty(tester);

    await _focusGrid(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonX);
    await tester.pumpAndSettle();

    expect(menus, ['A', 'A'], reason: 'the hold and the context-menu key');
    expect(toggled, isEmpty);
  });

  testWidgets('guide-search jump during load is stashed, wins over default anchoring, and lands focus', (tester) async {
    final harness = _GuideHarness.twoServers();
    addTearDown(harness.dispose);
    await harness.pump(tester);

    // Keyboard mode while the initial load is still in flight; the jump is
    // stashed and replayed once the load commits.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    tester.state<GuideTabState>(find.byType(GuideTab)).jumpToChannel(harness.channels[1]);

    await harness.completeInitialEmpty(tester);

    _expectFocusedChannel(tester, 'B');
  });

  testWidgets('jumpToProgram shifts the guide window to the airing and lands focus on its block', (tester) async {
    final harness = _GuideHarness.oneServer();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await harness.completeInitial(tester);

    await _focusGrid(tester);
    _expectFocusedChannel(tester, 'A');

    // An airing 8 hours past the window start, outside the visible 6 hours.
    final initial = harness.serverA.schedule.requests[0];
    final beginEpoch = initial.from.millisecondsSinceEpoch ~/ 1000 + 8 * 3600;
    final target = LiveTvProgram(
      ratingKey: 'search-target',
      title: 'Search Target',
      beginsAt: beginEpoch,
      endsAt: beginEpoch + 1800,
      channelIdentifier: 'station-a',
      serverId: 'server-a',
    );

    final state = tester.state<GuideTabState>(find.byType(GuideTab));
    unawaited(state.jumpToProgram(harness.channels.single, target));
    await tester.pump();

    // A fresh 6-hour window anchored one slot before the airing was requested.
    expect(harness.serverA.schedule.requests, hasLength(2));
    final shifted = harness.serverA.schedule.requests[1];
    final expectedFrom = DateTime.fromMillisecondsSinceEpoch((beginEpoch - 1800) * 1000, isUtc: true);
    expect(shifted.from, expectedFrom);
    expect(shifted.to, expectedFrom.add(const Duration(hours: 6)));

    // Slot 2 of the completed window begins exactly at the airing's start, so
    // the jump re-resolves onto it and lands D-pad focus on the block.
    harness.serverA.schedule.completeSlots(1, 2);
    await tester.pumpAndSettle();
    expect(find.ancestor(of: find.text('Slot 2'), matching: _focusedCellFinder(tester)), findsOneWidget);
  });
}

Finder _rightTimeButton() {
  final icon = find.byWidgetPredicate((widget) => widget is AppIcon && widget.icon == Symbols.chevron_right_rounded);
  return find.ancestor(of: icon, matching: find.byType(IconButton));
}

Future<void> _focusGrid(WidgetTester tester) async {
  final guideFocus = tester.widget<Focus>(
    find.byWidgetPredicate((widget) => widget is Focus && widget.focusNode?.debugLabel == 'guide_tab'),
  );
  guideFocus.focusNode!.requestFocus();
  await tester.pump();
  // Enters the grid from the time navigation zone.
  await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
  await tester.pumpAndSettle();
}

Finder _focusedCellFinder(WidgetTester tester) {
  final primary = Theme.of(tester.element(find.byType(GuideTab))).colorScheme.primary;
  return find.byWidgetPredicate((widget) => widget is Material && widget.color == primary);
}

void _expectFocusedChannel(WidgetTester tester, String callSign) {
  expect(
    find.ancestor(of: find.text(callSign), matching: _focusedCellFinder(tester)),
    findsOneWidget,
    reason: 'expected focused channel $callSign',
  );
}

FocusNode _guideTabFocusNode(WidgetTester tester) {
  final guideFocus = tester.widget<Focus>(
    find.byWidgetPredicate((widget) => widget is Focus && widget.focusNode?.debugLabel == 'guide_tab'),
  );
  return guideFocus.focusNode!;
}

/// Opens the day picker menu via SELECT on the focused time-nav day chip.
Future<void> _openDayPicker(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
}

/// Selects 'Tomorrow' in the open day menu by tapping its entry; the slot
/// refinement menu opens on top. The keyboard open/close paths are covered by
/// the focus test; menu entry taps keep this selection deterministic.
Future<void> _selectTomorrowInDayMenu(WidgetTester tester) async {
  await tester.tap(find.text(t.liveTv.tomorrow));
  await _pumpMenuTransition(tester);
}

/// Pumps through a menu open/close transition (120ms). Cannot pumpAndSettle:
/// while a guide load is in flight the overlay's indeterminate spinner keeps
/// scheduling frames forever.
Future<void> _pumpMenuTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

final class _GuideHarness {
  _GuideHarness._({required this.serverA, required this.serverB, required this.provider, required this.channels});

  factory _GuideHarness.oneServer() => _GuideHarness._create(includeServerB: false);

  factory _GuideHarness.twoServers() => _GuideHarness._create(includeServerB: true);

  factory _GuideHarness.twoServersWithChannels(List<LiveTvChannel> channels) =>
      _GuideHarness._create(includeServerB: true, channels: channels);

  factory _GuideHarness._create({required bool includeServerB, List<LiveTvChannel>? channels}) {
    final serverA = _FakeMediaServerClient(serverId: 'server-a', stationId: 'station-a');
    final serverB = includeServerB ? _FakeMediaServerClient(serverId: 'server-b', stationId: 'station-b') : null;
    final manager = MultiServerManager()..debugRegisterClientForTesting(serverA);
    if (serverB != null) manager.debugRegisterClientForTesting(serverB);
    final provider = testMultiServerProvider(manager)
      ..debugSetLiveTvServersForTesting([
        LiveTvServerInfo(serverId: 'server-a', dvrKey: 'dvr-a'),
        if (serverB != null) LiveTvServerInfo(serverId: 'server-b', dvrKey: 'dvr-b'),
      ]);
    return _GuideHarness._(
      serverA: serverA,
      serverB: serverB,
      provider: provider,
      channels:
          channels ??
          [
            _guideChannel(serverId: 'server-a', stationId: 'station-a', callSign: 'A'),
            if (serverB != null) _guideChannel(serverId: 'server-b', stationId: 'station-b', callSign: 'B'),
          ],
    );
  }

  final _FakeMediaServerClient serverA;
  final _FakeMediaServerClient? serverB;
  final MultiServerProvider provider;
  final List<LiveTvChannel> channels;

  Future<void> pump(
    WidgetTester tester, {
    void Function(LiveTvChannel)? onToggleFavorite,
    void Function(LiveTvChannel)? onChannelMenu,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    await tester.pumpWidget(
      TranslationProvider(
        child: InputModeTracker(
          child: ChangeNotifierProvider<MultiServerProvider>.value(
            value: provider,
            child: MaterialApp(
              theme: monoTheme(dark: true),
              home: Scaffold(
                body: GuideTab(channels: channels, onToggleFavorite: onToggleFavorite, onChannelMenu: onChannelMenu),
              ),
            ),
          ),
        ),
      ),
    );
    expect(serverA.schedule.requests, hasLength(1));
  }

  Future<void> completeInitial(WidgetTester tester) async {
    serverA.schedule.complete(0, 'Initial A');
    await tester.pump();
    final serverB = this.serverB;
    if (serverB != null) {
      expect(serverB.schedule.requests, hasLength(1));
      serverB.schedule.complete(0, 'Initial B');
    }
    await tester.pumpAndSettle();
    expect(find.text('Initial A'), findsOneWidget);
    if (serverB != null) expect(find.text('Initial B'), findsOneWidget);
  }

  Future<void> completeInitialEmpty(WidgetTester tester) async {
    serverA.schedule.completeEmpty(0);
    await tester.pump();
    final serverB = this.serverB;
    if (serverB != null) {
      expect(serverB.schedule.requests, hasLength(1));
      serverB.schedule.completeEmpty(0);
    }
    await tester.pumpAndSettle();
  }

  void dispose() => provider.dispose();
}

LiveTvChannel _guideChannel({
  required String serverId,
  required String stationId,
  required String callSign,
  String? number,
}) => LiveTvChannel(
  key: 'channel-$stationId',
  identifier: stationId,
  callSign: callSign,
  serverId: serverId,
  liveDvrKey: 'dvr-$serverId',
  number: number,
);

final class _FakeMediaServerClient implements MediaServerClient {
  _FakeMediaServerClient({required String serverId, required String stationId})
    : serverId = ServerId(serverId),
      schedule = _ControllableLiveTvSupport(serverId: serverId, stationId: stationId);

  @override
  final ServerId serverId;
  final _ControllableLiveTvSupport schedule;

  @override
  LiveTvSupport get liveTv => schedule;

  @override
  String get serverName => serverId.value;

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => const ServerCapabilities(liveTv: true);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ControllableLiveTvSupport implements LiveTvSupport {
  _ControllableLiveTvSupport({required this.serverId, required this.stationId});

  final String serverId;
  final String stationId;
  final List<_ScheduleRequest> requests = [];

  @override
  LiveTvDvrSupport? get dvr => null;

  @override
  Future<List<LiveTvProgram>> fetchSchedule({DateTime? from, DateTime? to}) {
    final request = _ScheduleRequest(from: from!, to: to!);
    requests.add(request);
    return request.completer.future;
  }

  void complete(int index, String title) {
    final request = requests[index];
    final beginsAt = request.from.millisecondsSinceEpoch ~/ 1000 + 600;
    request.completer.complete([
      LiveTvProgram(
        ratingKey: '$serverId-$index',
        title: title,
        beginsAt: beginsAt,
        endsAt: beginsAt + 3600,
        channelIdentifier: stationId,
        serverId: serverId,
      ),
    ]);
  }

  void completeEmpty(int index) => requests[index].completer.complete(const []);

  void completeSlots(int index, int count) {
    final request = requests[index];
    final startEpoch = request.from.millisecondsSinceEpoch ~/ 1000;
    request.completer.complete([
      for (var slot = 0; slot < count; slot++)
        LiveTvProgram(
          ratingKey: '$serverId-$index-$slot',
          title: 'Slot ${slot + 1}',
          beginsAt: startEpoch + slot * 30 * 60,
          endsAt: startEpoch + (slot + 1) * 30 * 60,
          channelIdentifier: stationId,
          serverId: serverId,
        ),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ScheduleRequest {
  _ScheduleRequest({required this.from, required this.to});

  final DateTime from;
  final DateTime to;
  final Completer<List<LiveTvProgram>> completer = Completer<List<LiveTvProgram>>();
}
