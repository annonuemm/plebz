import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/navigation/profile_navigation_scope.dart';

void main() {
  testWidgets('ProfileNavigationRegistry pops and detaches the active profile navigator', (tester) async {
    final registry = ProfileNavigationRegistry();
    final firstKey = GlobalKey<NavigatorState>();
    final secondKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Navigator(
          key: firstKey,
          onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => const Text('first')),
        ),
      ),
    );

    registry.attachNavigator(firstKey);
    final pushedRoute = firstKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Text('second')));
    await tester.pumpAndSettle();
    expect(find.text('second'), findsOneWidget);

    expect(await registry.maybePopProfileRoute(), isTrue);
    await pushedRoute;
    await tester.pumpAndSettle();
    expect(find.text('second'), findsNothing);

    registry.detachNavigator(secondKey);
    expect(registry.navigator, same(firstKey.currentState));

    registry.detachNavigator(firstKey);
    expect(registry.navigator, isNull);
  });

  group('going home from a run of pages', () {
    testWidgets('closes every page over the root and shows the home tab, with focus where home puts it', (
      tester,
    ) async {
      final registry = ProfileNavigationRegistry();
      final key = GlobalKey<NavigatorState>();
      final homeEntry = FocusNode(debugLabel: 'home entry');
      final opener = FocusNode(debugLabel: 'opener');
      addTearDown(homeEntry.dispose);
      addTearDown(opener.dispose);
      var homeShown = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Navigator(
            key: key,
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => Column(
                children: [
                  Focus(focusNode: homeEntry, child: const Text('home entry')),
                  Focus(focusNode: opener, child: const Text('opener')),
                ],
              ),
            ),
          ),
        ),
      );
      registry.attachNavigator(key);
      void showHome() {
        homeShown++;
        // As the main screen does: after the frame, onto its home entry.
        WidgetsBinding.instance.addPostFrameCallback((_) => homeEntry.requestFocus());
      }

      registry.attachHome(showHome);
      opener.requestFocus();
      await tester.pump();
      for (final name in ['detail', 'actor', 'another detail']) {
        unawaited(key.currentState!.push(MaterialPageRoute<void>(builder: (_) => Text(name))));
        await tester.pumpAndSettle();
      }
      expect(find.text('another detail'), findsOneWidget);

      expect(registry.goHome(), isTrue);
      await tester.pumpAndSettle();

      expect(find.text('detail'), findsNothing);
      expect(find.text('actor'), findsNothing);
      expect(find.text('another detail'), findsNothing);
      expect(find.text('home entry'), findsOneWidget);
      expect(homeShown, 1);
      expect(homeEntry.hasFocus, isTrue, reason: 'the root route restoring its old focus must not win');
    });

    testWidgets('does nothing without a main screen to return to', (tester) async {
      final registry = ProfileNavigationRegistry();
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Navigator(
            key: key,
            onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => const Text('root')),
          ),
        ),
      );
      registry.attachNavigator(key);
      expect(registry.goHome(), isFalse, reason: 'no home registered');

      void showHome() {}
      registry.attachHome(showHome);
      void otherHome() {}
      registry.detachHome(otherHome);
      expect(registry.goHome(), isTrue, reason: 'only its own registration is removed');
      registry.detachHome(showHome);
      expect(registry.goHome(), isFalse);
    });
  });
}
