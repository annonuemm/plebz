import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/screens/libraries/library_quick_picker_sheet.dart';
import 'package:plezy/services/settings_service.dart' show AppThemeVariant, GlasAccent;
import 'package:plezy/redesign/ocker_skin.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/app_icon.dart';

import '../test_helpers/prefs.dart';

/// The sheet that opens when "Mediatheken" is pressed a second time is the
/// redesign's library navigation — the horizontal group bar the plan drew never
/// happened, this took its place. So it has to be in the design's own language
/// rather than in the shared Material chooser's, and the three ways it was not
/// are the three things worth pinning.
/// The redesign's accent in its default palette.
final _accent = glasPalette(GlasAccent.eisblau).accent;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(resetSharedPreferencesForTest);

  const libraries = [
    MediaLibrary(id: '1', backend: MediaBackend.plex, title: 'Filme', kind: MediaKind.movie, serverId: 's'),
    MediaLibrary(id: '2', backend: MediaBackend.plex, title: 'Serien', kind: MediaKind.show, serverId: 's'),
  ];

  Future<void> pumpSheet(WidgetTester tester, AppThemeVariant variant, {String? selected}) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true, variant: variant),
        home: Scaffold(
          // As the sheet host sets it: on glass, its rows' marks are glass.
          body: OckerOnGlass(
            child: LibraryQuickPickerSheet(
              libraries: libraries,
              selectedLibraryKey: selected,
              isLoading: false,
              groupByServer: false,
              emptyMessage: 'leer',
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The rules that the accent's own fill can be read off: every solid colour
  /// painted by a Container in the tree.
  List<Color> fillsIn(WidgetTester tester) =>
      tester.widgetList<Container>(find.byType(Container)).map((c) => c.color).whereType<Color>().toList();

  testWidgets('names the libraries without a glyph beside them', (tester) async {
    await pumpSheet(tester, AppThemeVariant.glas);

    expect(find.text('Filme'), findsOneWidget);
    expect(find.text('Serien'), findsOneWidget);
    // The design turns section icons off: at television distance a word is
    // read and an outline symbol is guessed, and this list is only words.
    expect(find.byType(AppIcon), findsNothing);
  });

  testWidgets('marks the open library with the accent, once', (tester) async {
    await pumpSheet(tester, AppThemeVariant.glas, selected: libraries.first.globalKey);

    // Under glass the chosen one is a pane washed with the accent, as in
    // every glass menu — not a rule under it.
    expect(
      tester.widgetList<OckerGlassFocusFill>(find.byType(OckerGlassFocusFill)).where((fill) => fill.tint == 1),
      hasLength(1),
    );
    // Not also a tick. One state, one mark — and the accent is the mark this
    // design gives "active", here as everywhere else.
    expect(find.byIcon(Icons.check), findsNothing);
    expect(find.byType(AppIcon), findsNothing);
  });

  testWidgets('leaves the other variants on the chooser they had', (tester) async {
    // The rows here are shared with every settings list in the app, so the
    // branch has to be a branch and not a replacement.
    await pumpSheet(tester, AppThemeVariant.standard, selected: libraries.first.globalKey);

    expect(find.byType(AppIcon), findsWidgets, reason: 'Standard keeps its icons and its tick');
    expect(fillsIn(tester), isNot(contains(_accent)));
  });
}
