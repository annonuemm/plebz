import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/redesign/ocker_library_column.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';

void main() {
  testWidgets('UP and DOWN stop at the ends of the column instead of leaving it', (tester) async {
    final libraries = [
      for (final title in ['Filme', 'Serien', 'TV - TalkShow'])
        MediaLibrary(id: title, backend: MediaBackend.plex, title: title, serverId: 'plex'),
    ];
    final columnKey = GlobalKey<OckerLibraryColumnState>();
    final poster = FocusNode(debugLabel: 'poster');
    addTearDown(poster.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true, variant: AppThemeVariant.flach),
        home: Scaffold(
          body: OckerLibraryColumn(
            key: columnKey,
            libraries: libraries,
            selectedKey: libraries.first.globalKey,
            groupByServer: false,
            onSelected: (_) {},
            onFocusContent: () {},
            // What stands beside the column: a DOWN out of it reached this.
            child: Align(
              alignment: Alignment.bottomRight,
              child: Focus(focusNode: poster, child: const SizedBox(width: 80, height: 80)),
            ),
          ),
        ),
      ),
    );
    columnKey.currentState!.open();
    await tester.pumpAndSettle();

    String? focusedRow() => FocusManager.instance.primaryFocus?.debugLabel;
    expect(focusedRow(), contains('Filme'));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(focusedRow(), contains('Filme'), reason: 'nothing above the first row');

    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    expect(focusedRow(), contains('TV - TalkShow'), reason: 'DOWN past the last row stays on it');
    expect(poster.hasFocus, isFalse);
    expect(
      OckerLibraryColumnScope.open(tester.element(find.byKey(OckerLibraryColumn.rowKey(libraries.last.globalKey)))),
      isTrue,
    );
  });

  testWidgets('under Glas the pane stands as far from the screen\'s top as from its foot', (tester) async {
    final libraries = [MediaLibrary(id: 'Filme', backend: MediaBackend.plex, title: 'Filme', serverId: 'plex')];
    final columnKey = GlobalKey<OckerLibraryColumnState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true, variant: AppThemeVariant.glas),
        home: Scaffold(
          body: OckerLibraryColumn(
            key: columnKey,
            libraries: libraries,
            selectedKey: libraries.first.globalKey,
            groupByServer: false,
            onSelected: (_) {},
            onFocusContent: () {},
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    columnKey.currentState!.open();
    await tester.pumpAndSettle();

    final pane = tester.getRect(find.byKey(OckerLibraryColumn.paneKey));
    final screen = tester.getSize(find.byType(Scaffold));
    expect(pane.top, closeTo(screen.height - pane.bottom, 0.5));
  });
}
