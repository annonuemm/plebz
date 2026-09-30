import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/models/livetv_channel.dart';
import 'package:plezy/models/livetv_program.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/services/settings_service.dart' show AppThemeVariant;
import 'package:plezy/redesign/ocker_skin.dart';
import 'package:plezy/focus/focusable_wrapper.dart';
import 'package:plezy/widgets/video_controls/widgets/live_channel_strip.dart';

List<LiveTvChannel> _channels(int count) => [
  for (var i = 0; i < count; i++)
    LiveTvChannel(key: 'iptv:src:$i', title: 'Channel $i', number: '${i + 1}', serverId: 'src'),
];

void main() {
  Future<GlobalKey<LiveChannelStripState>> pumpStrip(
    WidgetTester tester, {
    required List<LiveTvChannel> channels,
    required int currentIndex,
    required void Function(int) onSelected,
    VoidCallback? onNavigateUp,
    LiveTvProgram? Function(LiveTvChannel channel)? programFor,
    LiveTvProgram? Function(LiveTvChannel channel)? nextProgramFor,
    AppThemeVariant variant = AppThemeVariant.standard,
  }) async {
    final key = GlobalKey<LiveChannelStripState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true, variant: variant),
        home: Scaffold(
          body: Align(
            alignment: .bottomCenter,
            child: LiveChannelStrip(
              key: key,
              channels: channels,
              currentIndex: currentIndex,
              onChannelSelected: onSelected,
              programFor: programFor,
              nextProgramFor: nextProgramFor,
              onNavigateUp: onNavigateUp,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return key;
  }

  testWidgets('opens on the channel that is playing, however far down the list', (tester) async {
    // The strip is built lazily for playlists of thousands, so the cell it
    // opens on has to be scrolled into existence before it can take focus.
    final selected = <int>[];
    await pumpStrip(tester, channels: _channels(200), currentIndex: 120, onSelected: selected.add);

    tester.state<LiveChannelStripState>(find.byType(LiveChannelStrip)).requestInitialFocus();
    await tester.pumpAndSettle();

    // Twice now: the focused cell and the info line above the strip.
    expect(find.text('121  Channel 120'), findsWidgets);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(selected, [120]);
  });

  testWidgets('the info line follows the focus, with what is on and what it is about', (tester) async {
    LiveTvProgram programFor(LiveTvChannel channel) => LiveTvProgram(
      key: 'p-${channel.key}',
      title: 'On ${channel.title}',
      summary: 'What ${channel.title} is showing.',
      beginsAt: DateTime(2024, 5, 4, 20, 15).millisecondsSinceEpoch ~/ 1000,
      endsAt: DateTime(2024, 5, 4, 21, 45).millisecondsSinceEpoch ~/ 1000,
    );

    await pumpStrip(tester, channels: _channels(4), currentIndex: 0, onSelected: (_) {}, programFor: programFor);

    tester.state<LiveChannelStripState>(find.byType(LiveChannelStrip)).requestInitialFocus();
    await tester.pumpAndSettle();

    expect(find.textContaining('On Channel 0'), findsOneWidget);
    expect(find.text('What Channel 0 is showing.'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(find.textContaining('On Channel 1'), findsOneWidget, reason: 'the info follows the cursor, not the player');
    expect(find.text('What Channel 0 is showing.'), findsNothing);
  });

  testWidgets('without a guide the info line is just the channel', (tester) async {
    await pumpStrip(tester, channels: _channels(3), currentIndex: 0, onSelected: (_) {});

    tester.state<LiveChannelStripState>(find.byType(LiveChannelStrip)).requestInitialFocus();
    await tester.pumpAndSettle();

    expect(find.text('1  Channel 0'), findsWidgets);
    expect(find.textContaining('·'), findsNothing, reason: 'no programme, so no time slot line');
  });

  testWidgets('the guide facts stand on their own line, and once', (tester) async {
    // Providers write them twice: in the XMLTV fields and glued to the front
    // of the description, where they read as the opening of the plot.
    LiveTvProgram programFor(LiveTvChannel channel) => LiveTvProgram(
      key: 'p-${channel.key}',
      title: 'Endlich Witwer',
      summary: 'Tragikomödie, Deutschland 2019Georg verliert seine Frau und entdeckt die Freiheit.',
      genres: const ['Tragikomödie'],
      country: 'Deutschland',
      year: 2019,
      beginsAt: DateTime(2024, 5, 4, 20, 15).millisecondsSinceEpoch ~/ 1000,
      endsAt: DateTime(2024, 5, 4, 21, 45).millisecondsSinceEpoch ~/ 1000,
    );

    await pumpStrip(tester, channels: _channels(3), currentIndex: 0, onSelected: (_) {}, programFor: programFor);
    tester.state<LiveChannelStripState>(find.byType(LiveChannelStrip)).requestInitialFocus();
    await tester.pumpAndSettle();

    expect(find.text('Tragikomödie  ·  Deutschland  ·  2019'), findsOneWidget);
    expect(
      find.text('Georg verliert seine Frau und entdeckt die Freiheit.'),
      findsOneWidget,
      reason: 'the run-together prefix belongs to the facts line, not the plot',
    );
  });

  testWidgets('a description without a facts prefix is left whole', (tester) async {
    LiveTvProgram programFor(LiveTvChannel channel) => LiveTvProgram(
      key: 'p-${channel.key}',
      title: 'Doku',
      summary: 'Ein Rückblick auf das Jahr 2019 und was danach kam.',
      year: 2024,
      beginsAt: DateTime(2024, 5, 4, 20, 15).millisecondsSinceEpoch ~/ 1000,
      endsAt: DateTime(2024, 5, 4, 21, 45).millisecondsSinceEpoch ~/ 1000,
    );

    await pumpStrip(tester, channels: _channels(3), currentIndex: 0, onSelected: (_) {}, programFor: programFor);
    tester.state<LiveChannelStripState>(find.byType(LiveChannelStrip)).requestInitialFocus();
    await tester.pumpAndSettle();

    expect(find.text('Ein Rückblick auf das Jahr 2019 und was danach kam.'), findsOneWidget);
  });

  testWidgets('what follows is named under what is on', (tester) async {
    LiveTvProgram nextFor(LiveTvChannel channel) => LiveTvProgram(
      key: 'n-${channel.key}',
      title: 'Tagesschau',
      beginsAt: DateTime(2024, 5, 4, 21, 45).millisecondsSinceEpoch ~/ 1000,
    );

    await pumpStrip(
      tester,
      channels: _channels(3),
      currentIndex: 0,
      onSelected: (_) {},
      programFor: (channel) => LiveTvProgram(
        key: 'p-${channel.key}',
        title: 'Endlich Witwer',
        beginsAt: DateTime(2024, 5, 4, 20, 15).millisecondsSinceEpoch ~/ 1000,
        endsAt: DateTime(2024, 5, 4, 21, 45).millisecondsSinceEpoch ~/ 1000,
      ),
      nextProgramFor: nextFor,
    );
    tester.state<LiveChannelStripState>(find.byType(LiveChannelStrip)).requestInitialFocus();
    await tester.pumpAndSettle();

    expect(find.textContaining('Tagesschau'), findsOneWidget);
  });

  testWidgets('the tiles carry no name of their own', (tester) async {
    // The header above names the focused channel, and a channel without a
    // logo puts its name in the tile itself — a label row under every tile
    // said it a third time.
    await pumpStrip(tester, channels: _channels(3), currentIndex: 0, onSelected: (_) {});
    tester.state<LiveChannelStripState>(find.byType(LiveChannelStrip)).requestInitialFocus();
    await tester.pumpAndSettle();

    expect(find.text('1  Channel 0'), findsOneWidget, reason: 'the header, and nothing under the tile');
    expect(find.text('Channel 0'), findsOneWidget, reason: 'the fallback where a logo would be');
  });

  testWidgets('the logo is given the whole tile, so a small one lands in the middle', (tester) async {
    // The regression, at the level it happened: a Stack leaves an
    // unpositioned child loose, and a logo sized to itself then draws in the
    // top corner. Tight constraints are what puts it in the middle — the
    // name fallback centres either way and says nothing about it.
    await pumpStrip(tester, channels: _channels(3), currentIndex: 0, onSelected: (_) {});
    tester.state<LiveChannelStripState>(find.byType(LiveChannelStrip)).requestInitialFocus();
    await tester.pumpAndSettle();

    final logoArea = find.ancestor(of: find.text('Channel 0'), matching: find.byType(Padding)).first;

    expect(tester.renderObject<RenderBox>(logoArea).constraints.isTight, isTrue);
  });

  testWidgets('left and right walk the list, select switches', (tester) async {
    final selected = <int>[];
    await pumpStrip(tester, channels: _channels(6), currentIndex: 2, onSelected: selected.add);

    tester.state<LiveChannelStripState>(find.byType(LiveChannelStrip)).requestInitialFocus();
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();

    expect(selected, isEmpty, reason: 'walking the strip must not switch channels');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(selected, [3]);
  });

  testWidgets('up leaves the strip, down stays in it', (tester) async {
    var navigatedUp = 0;
    await pumpStrip(
      tester,
      channels: _channels(4),
      currentIndex: 0,
      onSelected: (_) {},
      onNavigateUp: () => navigatedUp++,
    );

    tester.state<LiveChannelStripState>(find.byType(LiveChannelStrip)).requestInitialFocus();
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(navigatedUp, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(navigatedUp, 1);
  });

  testWidgets('the edges of the list are not a way out', (tester) async {
    final selected = <int>[];
    await pumpStrip(tester, channels: _channels(3), currentIndex: 0, onSelected: selected.add);

    tester.state<LiveChannelStripState>(find.byType(LiveChannelStrip)).requestInitialFocus();
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(selected, [0], reason: 'left on the first channel stays on it');
  });

  group('under "Redesign – Glas"', () {
    Size tileSize(WidgetTester tester) => tester.getSize(find.byType(FocusableWrapper).first);

    testWidgets('the tiles look as the guide\'s channel cells do, the one on air washed with the accent', (
      tester,
    ) async {
      await pumpStrip(
        tester,
        channels: _channels(5),
        currentIndex: 1,
        onSelected: (_) {},
        variant: AppThemeVariant.glas,
      );

      final wrappers = tester.widgetList<FocusableWrapper>(find.byType(FocusableWrapper));
      expect(wrappers.every((w) => w.glassFocus), isTrue, reason: 'focus a pane of bright glass');
      final onAir = tester.widgetList<OckerGlassFocusFill>(find.byType(OckerGlassFocusFill)).where((f) => f.tint == 1);
      expect(onAir, hasLength(1), reason: 'the channel on air, washed with the accent');
      expect(
        find.byWidgetPredicate((w) => w is Container && w.constraints?.maxHeight == 3),
        findsNothing,
        reason: 'no bar beside it',
      );
    });

    testWidgets('only the look changes: the tiles keep their size', (tester) async {
      await pumpStrip(tester, channels: _channels(5), currentIndex: 1, onSelected: (_) {});
      final standard = tileSize(tester);
      await pumpStrip(
        tester,
        channels: _channels(5),
        currentIndex: 1,
        onSelected: (_) {},
        variant: AppThemeVariant.glas,
      );

      expect(tileSize(tester), standard);
    });
  });
}
