import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/redesign/ocker_poster_tile.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';

import '../test_helpers/media_items.dart';
import '../test_helpers/prefs.dart';

/// The tile is handed its neighbours by whoever lays it out — a row that
/// scrolls, a browsing grid, or a library's virtualised grid. What it owes them
/// in return is that it asks for the right one, and says so when there is none:
/// the screens above it hang their "up goes to the tabs" on exactly that.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    await SettingsService.getInstance();
  });

  final hub = MediaHub(id: 'h', title: 'Filme', type: 'movie', items: const []);

  late List<String> exits;

  /// Which neighbour the tile asked for. Recorded rather than focused: a
  /// FocusNode with no widget behind it cannot take focus, so in a harness that
  /// mounts one tile the *request* is the observable thing — and that is also
  /// what the screens above depend on.
  late List<int> asked;
  late Map<int, FocusNode> nodes;

  Future<void> pumpGrid(
    WidgetTester tester, {
    required int index,
    int columns = 5,
    int itemCount = 12,
    bool onExitLeft = false,
  }) async {
    exits = [];
    asked = [];
    nodes = {for (var i = 0; i < itemCount; i++) i: FocusNode(debugLabel: 'cell:$i')};
    addTearDown(() {
      for (final node in nodes.values) {
        node.dispose();
      }
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true, variant: AppThemeVariant.glas),
        home: Scaffold(
          body: OckerPosterTile(
            item: testMediaItem(id: 'i$index', title: 'Titel'),
            hub: hub,
            index: index,
            itemCount: itemCount,
            posterMode: EpisodePosterMode.seriesPoster,
            mixedHub: false,
            hideSpoilers: false,
            tileWidth: 210,
            tileHeight: 315,
            focusNode: nodes[index]!,
            resolveClient: (_) => null,
            onPlay: () {},
            onFocused: () {},
            columns: columns,
            neighbour: (delta) {
              final next = index + delta;
              if (next < 0 || next >= itemCount) return null;
              asked.add(next);
              return nodes[next];
            },
            onExitUp: () => exits.add('up'),
            onExitDown: () => exits.add('down'),
            onExitRight: () => exits.add('right'),
            onExitLeft: onExitLeft ? () => exits.add('left') : null,
          ),
        ),
      ),
    );
    nodes[index]!.requestFocus();
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  testWidgets('UP from the first row leaves the grid upwards', (tester) async {
    await pumpGrid(tester, index: 2);

    await press(tester, LogicalKeyboardKey.arrowUp);

    expect(exits, ['up'], reason: 'the row above the grid is the screen\'s to fill');
  });

  testWidgets('UP from the second row stays inside, one row up', (tester) async {
    await pumpGrid(tester, index: 7);

    await press(tester, LogicalKeyboardKey.arrowUp);

    expect(exits, isEmpty, reason: 'there is a row above inside the grid');
    expect(asked, [2], reason: 'one row up in the same column');
  });

  testWidgets('LEFT in the first column does nothing at all', (tester) async {
    await pumpGrid(tester, index: 5);

    await press(tester, LogicalKeyboardKey.arrowLeft);

    expect(exits, isEmpty, reason: '§7: there is nothing to the left to reach');
    expect(asked, isEmpty, reason: 'and no neighbour is asked for either');
  });

  testWidgets('unless the host says there is — then LEFT hands focus over', (tester) async {
    // On the app's own layout the navigation is down the left, and swallowing
    // LEFT there left BACK as the only way out of a grid.
    await pumpGrid(tester, index: 5, onExitLeft: true);

    await press(tester, LogicalKeyboardKey.arrowLeft);

    expect(exits, ['left']);
    expect(asked, isEmpty, reason: 'still no neighbour inside the grid');
  });

  testWidgets('RIGHT in the last column hands focus on, where there is somewhere', (tester) async {
    await pumpGrid(tester, index: 4);

    await press(tester, LogicalKeyboardKey.arrowRight);

    expect(exits, ['right'], reason: 'the alphabet bar lives past the right edge');
  });

  testWidgets('DOWN reaches a short last row instead of stepping over it', (tester) async {
    // Twelve titles in fives: a full row, another, then a row of two. Column
    // four has nothing under it, and those two must still be reachable.
    await pumpGrid(tester, index: 8, itemCount: 12);

    await press(tester, LogicalKeyboardKey.arrowDown);

    expect(exits, isEmpty, reason: 'the short row is still inside the grid');
    expect(asked.last, 11, reason: 'the nearest title in the short row');
  });
}
