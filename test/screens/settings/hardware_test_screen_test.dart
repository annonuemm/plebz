import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/screens/settings/hardware_test_screen.dart';
import 'package:plezy/widgets/focusable_list_tile.dart';

void main() {
  testWidgets('a row with nothing to tap can still be reached, but only in directional mode', (tester) async {
    // The mechanism the report page depends on, stated once. Flutter's
    // traditional navigation refuses focus to a ListTile without a callback,
    // which is what left a page of pure facts unreachable by a remote.
    Future<bool> canFocus({required NavigationMode mode}) async {
      final node = FocusNode(debugLabel: 'info_row');
      addTearDown(node.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(navigationMode: mode),
            child: child!,
          ),
          home: Scaffold(
            body: FocusableListTile(title: const Text('a fact'), focusNode: node),
          ),
        ),
      );
      await tester.pump();
      node.requestFocus();
      await tester.pump();
      return node.hasFocus;
    }

    expect(await canFocus(mode: NavigationMode.traditional), isFalse);
    expect(await canFocus(mode: NavigationMode.directional), isTrue);
  });

  testWidgets('the hardware report page puts its rows in directional navigation', (tester) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: Builder(
            builder: (context) =>
                Navigator(onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => const HardwareTestScreen())),
          ),
        ),
      ),
    );
    await tester.pump();

    // Read below the screen, where its rows are built.
    expect(
      MediaQuery.of(tester.element(find.byType(Scaffold))).navigationMode,
      NavigationMode.directional,
      reason: 'without it the D-pad has nothing to move to and the report stops at the fold',
    );
  });
}
