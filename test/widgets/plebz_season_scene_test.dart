import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/utils/plebz_season.dart';
import 'package:plezy/widgets/plebz_season_scene.dart';

Widget _host(PlebzSeason season, {required Size size, bool still = false, Key? key}) => MediaQuery(
  data: MediaQueryData(size: size, disableAnimations: still),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: SizedBox.fromSize(
        size: size,
        child: ColoredBox(
          color: Colors.black,
          child: PlebzSeasonScene(key: key, season: season),
        ),
      ),
    ),
  ),
);

void main() {
  // A television, a 1280x720 box, a phone upright and a tablet on its side.
  const sizes = [Size(960, 540), Size(640, 360), Size(390, 844), Size(1180, 820)];

  for (final season in PlebzSeason.values) {
    testWidgets('the ${season.name} scene paints on every screen and keeps moving', (tester) async {
      for (final size in sizes) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(_host(season, size: size));
        // Through a whole loop, lightning strikes included.
        for (var i = 0; i < 50; i++) {
          await tester.pump(const Duration(milliseconds: 997));
        }
        expect(tester.takeException(), isNull, reason: '$size');
        expect(tester.hasRunningAnimations, isTrue, reason: '$size');
        await tester.pumpWidget(const SizedBox());
      }
      addTearDown(tester.view.reset);
    });

    testWidgets('the ${season.name} scene stands still with animations switched off', (tester) async {
      await tester.pumpWidget(_host(season, size: const Size(960, 540), still: true));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.hasRunningAnimations, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the scene lets touches through to the start screen', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            Positioned.fill(child: GestureDetector(onTap: () => tapped = true)),
            const Positioned.fill(child: PlebzSeasonScene(season: PlebzSeason.halloween)),
          ],
        ),
      ),
    );
    await tester.tapAt(const Offset(100, 100));
    expect(tapped, isTrue);
  });

  testWidgets('at Halloween the farewell strike lights first, then lets the logo go', (tester) async {
    final key = GlobalKey<PlebzSeasonSceneState>();
    await tester.pumpWidget(_host(PlebzSeason.halloween, size: const Size(960, 540), key: key));
    await tester.pump(const Duration(seconds: 2));

    var struck = false;
    unawaited(key.currentState!.strike().then((_) => struck = true));
    await tester.pump(const Duration(milliseconds: 60));
    expect(struck, isFalse, reason: 'the first flash is still coming');
    await tester.pump(PlebzSeasonSceneState.farewellLead);
    expect(struck, isTrue);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });

  for (final (name, season, still) in [
    ('at Christmas', PlebzSeason.christmas, false),
    ('with animations switched off', PlebzSeason.halloween, true),
  ]) {
    testWidgets('$name there is no farewell strike to wait for', (tester) async {
      final key = GlobalKey<PlebzSeasonSceneState>();
      await tester.pumpWidget(_host(season, size: const Size(960, 540), still: still, key: key));
      var struck = false;
      unawaited(key.currentState!.strike().then((_) => struck = true));
      await tester.pump();
      expect(struck, isTrue);
    });
  }
}
