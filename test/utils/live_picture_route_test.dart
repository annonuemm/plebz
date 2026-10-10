import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/utils/video_player_navigation.dart';

/// The player growing out of the guide's preview box, and shrinking back
/// into it when the picture goes home (Plebz).
void main() {
  const playerKey = Key('player');
  const box = Rect.fromLTWH(40, 40, 320, 180);

  Future<NavigatorState> pumpApp(WidgetTester tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(navigatorKey: navigatorKey, home: const SizedBox.expand()));
    return navigatorKey.currentState!;
  }

  VideoPlayerRoute route({Rect? pictureFrom}) => VideoPlayerRoute(
    pictureFrom: pictureFrom,
    builder: (_) => const ColoredBox(key: playerKey, color: Colors.black),
  );

  Rect playerRect(WidgetTester tester) => tester.getRect(find.byKey(playerKey));

  bool strictlyBetween(Rect inner, Rect outer, Rect rect) =>
      rect.width > inner.width && rect.width < outer.width && rect.height > inner.height && rect.height < outer.height;

  testWidgets('grows out of the box it was handed and shrinks back into it', (tester) async {
    final navigator = await pumpApp(tester);
    final screen = Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
    final player = route(pictureFrom: box);

    unawaited(player.push(navigator));
    // The first frame of a push lays the route out offstage (heroes measure
    // it there); the growth starts on the next one, at the box.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    final start = playerRect(tester);
    expect(start.left, closeTo(box.left, 1));
    expect(start.top, closeTo(box.top, 1));
    expect(start.width, closeTo(box.width, 2));
    expect(start.height, closeTo(box.height, 2));

    await tester.pump(const Duration(milliseconds: 140));
    expect(strictlyBetween(box, screen, playerRect(tester)), isTrue);

    await tester.pumpAndSettle();
    expect(playerRect(tester), screen);

    player.shrinkIntoPictureOnPop();
    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));
    expect(strictlyBetween(box, screen, playerRect(tester)), isTrue);

    await tester.pumpAndSettle();
    expect(find.byKey(playerKey), findsNothing);
  });

  test('the picture on the plane follows the same rectangle as the page', () {
    const screen = Size(960, 540);

    expect(VideoPlayerRoute.pictureRectAt(box, screen, 0), box);
    expect(VideoPlayerRoute.pictureRectAt(box, screen, 1), Offset.zero & screen);
    final halfway = VideoPlayerRoute.pictureRectAt(box, screen, 0.5);
    expect(halfway.width, greaterThan(box.width));
    expect(halfway.width, lessThan(screen.width));
    // Past either end it holds still rather than overshooting.
    expect(VideoPlayerRoute.pictureRectAt(box, screen, 1.2), Offset.zero & screen);
  });

  testWidgets('a picture that is not given back leaves at once', (tester) async {
    final navigator = await pumpApp(tester);
    final player = route(pictureFrom: box);
    unawaited(player.push(navigator));
    await tester.pumpAndSettle();

    navigator.pop();
    await tester.pump();

    expect(find.byKey(playerKey), findsNothing);
  });

  testWidgets('without a picture the player appears and leaves at once, and does not shrink', (tester) async {
    final navigator = await pumpApp(tester);
    final player = route();

    unawaited(player.push(navigator));
    await tester.pump();
    expect(playerRect(tester), Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio);

    player.shrinkIntoPictureOnPop();
    navigator.pop();
    await tester.pump();
    expect(find.byKey(playerKey), findsNothing);
  });
}
