import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/focus/dpad_navigator.dart';
import 'package:plezy/focus/dpad_reorder_mixin.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/providers/hidden_libraries_provider.dart';
import 'package:plezy/providers/libraries_provider.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/redesign/ocker_skin.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/plex_api_cache.dart';
import 'package:plezy/services/settings_service.dart' show AppThemeVariant;
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/widgets/library_management_sheet.dart';
import 'package:plezy/widgets/overlay_sheet.dart';
import 'package:provider/provider.dart';

import '../test_helpers/backend_client_fixtures.dart';
import '../test_helpers/multi_server_fixtures.dart';

import '../test_helpers/prefs.dart';

const _qualifiedLibrary = MediaLibrary(
  id: 'shared-section',
  backend: MediaBackend.plex,
  title: 'Movies',
  kind: MediaKind.movie,
  serverId: 'server-a',
);

Future<({int Function() selects, int Function() backs, LibrariesProvider libraries})> _pumpLibraryManagementLauncher(
  WidgetTester tester, {
  MediaLibrary library = _qualifiedLibrary,
  List<MediaLibrary>? libraries,
  MultiServerProvider? multiServerProvider,
  ThemeData? theme,
  // Admin actions are offered to owners and administrators only. Most tests
  // exercise the actions themselves, so they skip that check; null keeps it.
  bool Function(MediaLibrary library)? canAdministerLibrary = _alwaysAdmin,
}) async {
  final librariesProvider = LibrariesProvider();
  await librariesProvider.updateLibraryOrder(libraries ?? [library]);
  addTearDown(librariesProvider.dispose);

  final hiddenLibrariesProvider = HiddenLibrariesProvider();
  await hiddenLibrariesProvider.ensureInitialized();
  addTearDown(hiddenLibrariesProvider.dispose);

  final fallbackManager = multiServerProvider == null ? MultiServerManager() : null;
  final effectiveMultiServerProvider = multiServerProvider ?? testMultiServerProvider(fallbackManager!);
  if (fallbackManager != null) {
    addTearDown(() {
      effectiveMultiServerProvider.dispose();
      fallbackManager.dispose();
    });
  }

  var underlyingSelects = 0;
  var underlyingBacks = 0;

  await tester.pumpWidget(
    TranslationProvider(
      child: InputModeTracker(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<LibrariesProvider>.value(value: librariesProvider),
            ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hiddenLibrariesProvider),
            ChangeNotifierProvider<MultiServerProvider>.value(value: effectiveMultiServerProvider),
          ],
          child: MaterialApp(
            theme: theme ?? monoTheme(dark: true),
            home: Focus(
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent && event.logicalKey.isSelectKey) underlyingSelects++;
                if (event is KeyDownEvent && event.logicalKey.isBackKey) underlyingBacks++;
                return KeyEventResult.ignored;
              },
              child: OverlaySheetHost(
                child: Scaffold(
                  body: Center(
                    child: Builder(
                      builder: (context) => ElevatedButton(
                        autofocus: true,
                        onPressed: () =>
                            showLibraryManagementSheet(context, canAdministerLibrary: canAdministerLibrary),
                        child: const Text('Open library management'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return (selects: () => underlyingSelects, backs: () => underlyingBacks, libraries: librariesProvider);
}

bool _alwaysAdmin(MediaLibrary library) => true;

Future<void> _openScanConfirmation(WidgetTester tester) async {
  // Switch from the desktop pointer default to keyboard mode, then activate the
  // focused launcher using the same key path as a keyboard/remote user.
  await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();

  expect(find.text(t.libraries.manageLibraries), findsOneWidget);

  // The sheet owns one focus node for its virtual row/column navigation. Move
  // from the row to its options column and open the real AppMenuSheet.
  await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
  await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();

  expect(find.text(t.libraries.scanLibraryFiles), findsOneWidget);

  // The hosted menu focuses its first entry in keyboard mode. Selecting it
  // must close the whole hosted sheet before presenting the confirmation.
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();

  expect(find.byType(AlertDialog), findsOneWidget);
  expect(find.text(t.libraries.manageLibraries), findsNothing);
  expect(find.text(t.libraries.scanLibraryFiles), findsNothing);
  expect(OverlaySheetController.openSheetCount.value, 0);

  final dialogElement = tester.element(find.byType(AlertDialog));
  final primaryFocusContext = FocusManager.instance.primaryFocus?.context;
  var dialogOwnsPrimaryFocus = false;
  primaryFocusContext?.visitAncestorElements((element) {
    if (identical(element, dialogElement)) {
      dialogOwnsPrimaryFocus = true;
      return false;
    }
    return true;
  });
  expect(dialogOwnsPrimaryFocus, isTrue);
}

Future<void> _confirmLibraryAction(WidgetTester tester, String actionLabel) async {
  await tester.tap(find.text('Open library management'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip(t.libraries.libraryOptions));
  await tester.pumpAndSettle();
  await tester.tap(find.text(actionLabel));
  await tester.pumpAndSettle();

  expect(find.byType(AlertDialog), findsOneWidget);
  await tester.tap(find.text(t.common.confirm));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(seconds: 2));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(seconds: 2));
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('a server moves as one block, not library by library', (tester) async {
    // The sidebar takes its server order from the library order, so moving a
    // server used to mean dragging every one of its libraries past the other
    // server's. One action now moves the whole block, and each block keeps its
    // own order.
    const a1 = MediaLibrary(
      id: 'a1',
      backend: MediaBackend.plex,
      title: 'Filme A',
      kind: MediaKind.movie,
      serverId: 'server-a',
      serverName: 'Server A',
    );
    const a2 = MediaLibrary(
      id: 'a2',
      backend: MediaBackend.plex,
      title: 'Serien A',
      kind: MediaKind.show,
      serverId: 'server-a',
      serverName: 'Server A',
    );
    const b1 = MediaLibrary(
      id: 'b1',
      backend: MediaBackend.plex,
      title: 'Filme B',
      kind: MediaKind.movie,
      serverId: 'server-b',
      serverName: 'Server B',
    );

    final harness = await _pumpLibraryManagementLauncher(tester, libraries: const [a1, a2, b1]);
    await tester.tap(find.text('Open library management'));
    await tester.pumpAndSettle();

    // The options of the last row, which is the one library of Server B.
    await tester.tap(find.byTooltip(t.libraries.libraryOptions).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.libraries.moveServerUp(name: 'Server B')));
    await tester.pumpAndSettle();

    expect(harness.libraries.libraries.map((library) => library.id), [
      'b1',
      'a1',
      'a2',
    ], reason: 'the block moved as a whole and Server A kept its own order');
  });

  testWidgets('the topmost server is not offered a move up', (tester) async {
    const a1 = MediaLibrary(
      id: 'a1',
      backend: MediaBackend.plex,
      title: 'Filme A',
      kind: MediaKind.movie,
      serverId: 'server-a',
      serverName: 'Server A',
    );
    const b1 = MediaLibrary(
      id: 'b1',
      backend: MediaBackend.plex,
      title: 'Filme B',
      kind: MediaKind.movie,
      serverId: 'server-b',
      serverName: 'Server B',
    );

    await _pumpLibraryManagementLauncher(tester, libraries: const [a1, b1]);
    await tester.tap(find.text('Open library management'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(t.libraries.libraryOptions).first);
    await tester.pumpAndSettle();

    expect(find.text(t.libraries.moveServerUp(name: 'Server A')), findsNothing);
    expect(find.text(t.libraries.moveServerDown(name: 'Server A')), findsOneWidget);
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;

  setUp(() {
    resetSharedPreferencesForTest();
    LocaleSettings.setLocaleSync(AppLocale.en);
    TvDetectionService.debugSetAppleTVOverride(false);
    TvDetectionService.setForceTVSync(false);
    PlatformDetector.debugSetIsDesktopOSOverride(false);
    database = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(database);
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    TvDetectionService.setForceTVSync(false);
    PlatformDetector.debugSetIsDesktopOSOverride(null);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });
  tearDown(() => database.close());

  for (final interaction in [
    (name: 'Enter', key: LogicalKeyboardKey.enter),
    (name: 'Back', key: LogicalKeyboardKey.escape),
  ]) {
    testWidgets('${interaction.name} is handled by confirmation after the hosted action sheet closes', (tester) async {
      final underlyingActions = await _pumpLibraryManagementLauncher(tester);
      await _openScanConfirmation(tester);

      // Ignore launcher/menu navigation. From this point onward, neither key
      // may reach the underlying page while the modal confirmation has focus.
      final selectsBeforeDialogAction = underlyingActions.selects();
      final backsBeforeDialogAction = underlyingActions.backs();

      await tester.sendKeyEvent(interaction.key);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Open library management'), findsOneWidget);
      expect(underlyingActions.selects(), selectsBeforeDialogAction);
      expect(underlyingActions.backs(), backsBeforeDialogAction);
      expect(OverlaySheetController.openSheetCount.value, 0);
    });
  }

  // The rows were marked in `surfaceContainerHighest`, which the mono schemes
  // set to the surface a dialog is painted in: UP and DOWN moved an invisible
  // cursor, and only the trailing buttons' own fill ever showed.
  for (final variant in [AppThemeVariant.standard]) {
    testWidgets('the cursor row is marked in a colour the ${variant.name} dialog does not have', (tester) async {
      TvDetectionService.debugSetAppleTVOverride(true);
      debugRedesignOfferedHere = true;
      addTearDown(() => debugRedesignOfferedHere = null);
      final theme = monoTheme(dark: true, variant: variant);
      await _pumpLibraryManagementLauncher(
        tester,
        theme: theme,
        libraries: [
          for (var i = 0; i < 3; i++)
            MediaLibrary(
              id: 'section-$i',
              backend: MediaBackend.plex,
              title: 'Library $i',
              kind: MediaKind.movie,
              serverId: 'server-a',
            ),
        ],
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);

      Color? rowColor(int index) => tester.widget<ListTile>(find.byType(ListTile).at(index)).tileColor;
      final dialogColor =
          Theme.of(tester.element(find.byType(Dialog))).dialogTheme.backgroundColor ??
          Theme.of(tester.element(find.byType(Dialog))).colorScheme.surfaceContainerHigh;

      expect(rowColor(0), isNotNull);
      expect(rowColor(0)!.a, greaterThan(0));
      expect(Color.alphaBlend(rowColor(0)!, dialogColor), isNot(dialogColor));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(rowColor(0), isNull, reason: 'the cursor left the first row');
      expect(rowColor(1), isNotNull, reason: 'DOWN puts the cursor on the second row');

      // In move mode the row carries a fill of its own, deeper than the cursor's.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        rowColor(1)!.a,
        greaterThan(dpadReorderRowColor(tester.element(find.byType(Dialog)), isMoving: false, isRowFocused: true)!.a),
      );
    });
  }

  // Under glass the cursor is a pane of glass behind the row, as in the menus,
  // not a colour on it; the row being moved wears the quiet accent pane.
  testWidgets('under glas the cursor row is marked with a pane of glass that follows the cursor', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    debugRedesignOfferedHere = true;
    addTearDown(() => debugRedesignOfferedHere = null);
    await _pumpLibraryManagementLauncher(
      tester,
      theme: monoTheme(dark: true, variant: AppThemeVariant.glas),
      libraries: [
        for (var i = 0; i < 3; i++)
          MediaLibrary(
            id: 'section-$i',
            backend: MediaBackend.plex,
            title: 'Library $i',
            kind: MediaKind.movie,
            serverId: 'server-a',
          ),
      ],
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);

    DpadReorderRowMark mark(int index) => tester.widget<DpadReorderRowMark>(find.byType(DpadReorderRowMark).at(index));
    Color? rowColor(int index) => tester.widget<ListTile>(find.byType(ListTile).at(index)).tileColor;

    expect(mark(0).isRowFocused, isTrue);
    expect(rowColor(0), isNull, reason: 'the glass marks it, not a colour');
    // The row's own pane comes first; its buttons carry panes of their own.
    final fill = find
        .descendant(of: find.byType(DpadReorderRowMark).at(0), matching: find.byType(OckerGlassFocusFill))
        .first;
    expect(tester.widget<OckerGlassFocusFill>(fill).bright, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(mark(0).isRowFocused, isFalse, reason: 'the cursor left the first row');
    expect(mark(1).isRowFocused, isTrue, reason: 'DOWN puts the cursor on the second row');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(mark(1).isMoving, isTrue);
    final moving = tester.widget<OckerGlassFocusFill>(
      find.descendant(of: find.byType(DpadReorderRowMark).at(1), matching: find.byType(OckerGlassFocusFill)).first,
    );
    expect(moving.bright, isFalse);
    expect(moving.tint, 1, reason: 'the quiet pane, washed with the accent');
  });

  testWidgets('the D-pad cursor stays on screen while walking a long library list', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    // Shield-class TV output: 1080p at a 2.0 ratio.
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpLibraryManagementLauncher(
      tester,
      libraries: [
        for (var i = 0; i < 60; i++)
          MediaLibrary(
            id: 'section-$i',
            backend: MediaBackend.plex,
            title: 'Library $i',
            kind: MediaKind.movie,
            serverId: 'server-a',
          ),
      ],
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    // One server means no server subtitle, so rows are shorter than the
    // two-line height the reveal arithmetic used to assume.
    final firstRow = tester.getRect(find.byType(ListTile).at(0));
    final rowPitch = tester.getRect(find.byType(ListTile).at(1)).top - firstRow.top;
    expect(rowPitch, lessThan(72.0));

    final viewport = tester.getRect(find.descendant(of: find.byType(Dialog), matching: find.byType(Scrollable)).first);

    for (var index = 1; index <= 20; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      final row = find.text('Library $index');
      expect(row, findsOneWidget, reason: 'focused row $index scrolled out of the built range');
      final rect = tester.getRect(row);
      expect(rect.top, greaterThanOrEqualTo(viewport.top), reason: 'focused row $index sits above the viewport');
      expect(rect.bottom, lessThanOrEqualTo(viewport.bottom), reason: 'focused row $index sits below the viewport');
    }
  });

  test('reconcileLibraryOrder keeps the sheet order over the current libraries', () {
    MediaLibrary library(String id, {String title = ''}) =>
        MediaLibrary(id: id, backend: MediaBackend.plex, title: title, kind: MediaKind.movie, serverId: 'server-a');

    final reconciled = reconcileLibraryOrder(
      [library('b'), library('gone'), library('a')],
      [library('a', title: 'fresh'), library('b'), library('new')],
    );

    expect(reconciled.map((l) => l.id), ['b', 'a', 'new']);
    expect(reconciled[1].title, 'fresh');
  });

  testWidgets('a reorder after libraries load mid-sheet keeps the new libraries', (tester) async {
    MediaLibrary library(String id) => MediaLibrary(
      id: id,
      backend: MediaBackend.plex,
      title: 'Library $id',
      kind: MediaKind.movie,
      serverId: 'server-a',
    );

    final launcher = await _pumpLibraryManagementLauncher(tester, libraries: [library('a'), library('b')]);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    // Another server's libraries finish loading while the sheet is open.
    await launcher.libraries.updateLibraryOrder([library('a'), library('b'), library('c')]);
    await tester.pumpAndSettle();
    expect(find.text('Library c'), findsOneWidget);

    // Move the first row down one place and confirm.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(launcher.libraries.libraries.map((l) => l.id), ['b', 'a', 'c']);
  });

  testWidgets('library admin actions are offered only on servers the user administers', (tester) async {
    final adminClient = testJellyfinClient(
      connection: testJellyfinConnection(machineId: 'admin-srv', isAdministrator: true),
    );
    final userClient = testJellyfinClient(connection: testJellyfinConnection(machineId: 'user-srv'));
    final manager = MultiServerManager()
      ..debugRegisterJellyfinClientForTesting(adminClient)
      ..debugRegisterJellyfinClientForTesting(userClient);
    final provider = testMultiServerProvider(manager);
    addTearDown(() {
      provider.dispose();
      manager.dispose();
    });

    MediaLibrary library(String serverId, String title) => MediaLibrary(
      id: '$serverId-movies',
      backend: MediaBackend.jellyfin,
      title: title,
      kind: MediaKind.movie,
      serverId: serverId,
    );

    await _pumpLibraryManagementLauncher(
      tester,
      libraries: [library('admin-srv', 'Admin Movies'), library('user-srv', 'User Movies')],
      multiServerProvider: provider,
      canAdministerLibrary: null,
    );
    await tester.tap(find.text('Open library management'));
    await tester.pumpAndSettle();

    Finder optionsIn(String title) => find.descendant(
      of: find.ancestor(of: find.text(title), matching: find.byType(ListTile)),
      matching: find.byTooltip(t.libraries.libraryOptions),
    );
    expect(optionsIn('Admin Movies'), findsOneWidget);

    // The row still has a menu here — two servers, so moving this one is on
    // offer, and that is not an admin action — but nothing an admin does.
    await tester.tap(optionsIn('User Movies'));
    await tester.pumpAndSettle();
    expect(find.text(t.libraries.moveServerUp(name: 'user-srv')), findsOneWidget);
    expect(find.text(t.libraries.refreshMetadata), findsNothing);
    expect(find.text(t.libraries.scanLibraryFiles), findsNothing);
  });

  for (final action in ['scan', 'empty_trash']) {
    testWidgets('$action refuses an absent library owner while another Plex server is online', (tester) async {
      final harness = _LibraryActionHarness(includeOwner: false);
      addTearDown(harness.dispose);
      await _pumpLibraryManagementLauncher(tester, multiServerProvider: harness.provider);

      final label = action == 'scan' ? t.libraries.scanLibraryFiles : t.libraries.emptyTrash;
      await _confirmLibraryAction(tester, label);

      expect(harness.replacementRequests, isEmpty);
      expect(find.textContaining(t.errors.noClientAvailable), findsOneWidget);
    });

    testWidgets('$action reaches only the exact library owner with the original section id', (tester) async {
      final harness = _LibraryActionHarness(includeOwner: true);
      addTearDown(harness.dispose);
      await _pumpLibraryManagementLauncher(tester, multiServerProvider: harness.provider);

      final label = action == 'scan' ? t.libraries.scanLibraryFiles : t.libraries.emptyTrash;
      await _confirmLibraryAction(tester, label);

      expect(harness.replacementRequests, isEmpty);
      expect(harness.ownerRequests, hasLength(1));
      final expectedPath = action == 'scan'
          ? '/library/sections/shared-section/refresh'
          : '/library/sections/shared-section/emptyTrash';
      expect(harness.ownerRequests.single.url.path, expectedPath);
      final successMessage = action == 'scan'
          ? t.messages.libraryScanStarted(title: _qualifiedLibrary.title)
          : t.libraries.trashEmptied(title: _qualifiedLibrary.title);
      expect(find.text(successMessage), findsOneWidget);
    });
  }
}

class _LibraryActionHarness {
  final ownerRequests = <http.Request>[];
  final replacementRequests = <http.Request>[];
  late final MultiServerManager manager;
  late final MultiServerProvider provider;

  _LibraryActionHarness({required bool includeOwner}) {
    final replacement = testPlexClient(
      serverId: ServerId('server-b'),
      handler: (request) async {
        replacementRequests.add(request);
        return http.Response('{}', 200, headers: const {'content-type': 'application/json'});
      },
    );
    manager = MultiServerManager()..debugRegisterClientForTesting(replacement);
    if (includeOwner) {
      final owner = testPlexClient(
        serverId: ServerId('server-a'),
        handler: (request) async {
          ownerRequests.add(request);
          return http.Response('{}', 200, headers: const {'content-type': 'application/json'});
        },
      );
      manager.debugRegisterClientForTesting(owner);
    }
    provider = testMultiServerProvider(manager);
  }

  void dispose() {
    provider.dispose();
    manager.dispose();
  }
}
