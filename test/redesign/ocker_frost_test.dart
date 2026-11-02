import 'package:flutter/material.dart' hide ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/redesign/ocker_fact_card.dart';
import 'package:plezy/redesign/ocker_filter_glyph.dart';
import 'package:plezy/redesign/ocker_frost.dart';
import 'package:plezy/redesign/ocker_skin.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/platform_detector.dart';

import '../test_helpers/prefs.dart';

void main() {
  setUp(() async {
    resetSharedPreferencesForTest();
    await SettingsService.getInstance();
    TvDetectionService.debugSetAppleTVOverride(true);
  });
  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  group('the switch', () {
    Future<bool> frostUnder(WidgetTester tester, AppThemeVariant variant) async {
      late bool frost;
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(MonoPalette.dark, variant: variant),
          home: Builder(
            builder: (context) {
              frost = ockerFrost(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      // A swap of theme animates.
      await tester.pump(const Duration(seconds: 1));
      return frost;
    }

    testWidgets('is on until switched off', (tester) async {
      expect(await frostUnder(tester, AppThemeVariant.glasV2), isTrue);

      await tester.runAsync(() => SettingsService.instance.write(PlebzPrefs.glasV2Frost, false));

      expect(await frostUnder(tester, AppThemeVariant.glasV2), isFalse);
    });

    testWidgets('holds on a television alone: nowhere else is there a switch for it', (tester) async {
      TvDetectionService.debugSetAppleTVOverride(false);

      expect(await frostUnder(tester, AppThemeVariant.glasV2), isFalse);
    });

    testWidgets('holds under Glas – v2 alone', (tester) async {
      expect(await frostUnder(tester, AppThemeVariant.glasV2), isTrue);
      expect(await frostUnder(tester, AppThemeVariant.glas), isFalse);
      expect(await frostUnder(tester, AppThemeVariant.flach), isFalse);
    });
  });

  group('the glide', () {
    Future<BuildContext> contextUnderV2(WidgetTester tester) async {
      late BuildContext inside;
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(MonoPalette.dark, variant: AppThemeVariant.glasV2),
          home: Builder(
            builder: (context) {
              inside = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      return inside;
    }

    testWidgets('a tier with no glide keeps none without Milchglas', (tester) async {
      await tester.runAsync(() => SettingsService.instance.write(PlebzPrefs.glasV2Frost, false));
      final context = await contextUnderV2(tester);

      expect(ockerFrostGlide(context, Duration.zero), Duration.zero);
    });

    testWidgets('under Milchglas a tier with no glide gets one, the others keep theirs', (tester) async {
      final context = await contextUnderV2(tester);

      expect(ockerFrostGlide(context, Duration.zero), greaterThan(Duration.zero));
      expect(ockerFrostGlide(context, const Duration(milliseconds: 250)), const Duration(milliseconds: 250));
    });
  });

  group('a glyph at a button\'s size', () {
    for (final variant in [AppThemeVariant.glas, AppThemeVariant.glasV2, AppThemeVariant.flach]) {
      testWidgets('stands as tall as the button beside it under ${variant.name}', (tester) async {
        final glyph = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: monoTheme(MonoPalette.dark, variant: variant),
            home: Scaffold(
              body: Center(
                child: OckerFilterGlyph(key: glyph, icon: Icons.bookmark_add, focused: false, diameter: 46),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 1));

        expect(tester.getSize(find.byKey(glyph)).height, 46);
      });
    }
  });

  group('the live blur', () {
    Widget card() => MaterialApp(
      theme: monoTheme(MonoPalette.dark, variant: AppThemeVariant.glasV2),
      home: Scaffold(
        body: OckerFactCard(
          facts: const [(label: 'Land', value: 'Deutschland')],
          labelWidth: 100,
          labelStyle: const TextStyle(),
          valueStyle: const TextStyle(),
          rowGap: 4,
        ),
      ),
    );

    testWidgets('a fact card blurs what lies behind it, unless switched off', (tester) async {
      await tester.runAsync(() => SettingsService.instance.write(PlebzPrefs.glasV2Frost, false));
      await tester.pumpWidget(card());
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byType(OckerGlass), findsOneWidget);

      await tester.runAsync(() => SettingsService.instance.write(PlebzPrefs.glasV2Frost, true));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(card());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.text('Deutschland'), findsOneWidget);
    });
  });

  group('the pane', () {
    testWidgets('stands without a picture, its words on the ground', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: OckerFrostPane(ground: Colors.black, picture: null, child: Text('Filme')),
        ),
      );

      expect(find.text('Filme'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the picture is of the page as last painted, not of what opens after it', (tester) async {
      final shot = OckerFrostShot();
      addTearDown(shot.dispose);
      late BuildContext inside;

      await tester.pumpWidget(
        MaterialApp(
          home: OckerFrostSource(
            child: ColoredBox(
              color: Colors.red,
              child: Builder(
                builder: (context) {
                  inside = context;
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        ),
      );

      shot.take(inside);

      // In hand at once: a pane opened on the same frame is frosted from it.
      expect(shot.image, isNotNull);
      final bytes = await tester.runAsync(() => shot.image!.toByteData());
      expect(bytes!.getUint8(0), greaterThan(200), reason: 'the page was red');
    });

    testWidgets('no source above, no picture', (tester) async {
      final shot = OckerFrostShot();
      addTearDown(shot.dispose);
      late BuildContext outside;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            outside = context;
            return const SizedBox.shrink();
          },
        ),
      );

      shot.take(outside);

      expect(shot.image, isNull);
    });
  });
}
