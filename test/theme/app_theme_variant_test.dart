import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/theme/mono_tokens.dart';
import 'package:plezy/widgets/app_icon.dart';

import '../test_helpers/prefs.dart';

ThemeData _theme(AppThemeVariant variant, {bool dark = true}) => monoTheme(dark: dark, variant: variant);

MonoTokens _tokens(AppThemeVariant variant) => _theme(variant).extension<MonoTokens>()!;

void main() {
  group('the retired filled redesigns', () {
    // "Ocker" and "Schwarz" were the redesign filled instead of glass. Whoever
    // had one keeps the redesign rather than dropping back to Standard.
    testWidgets('read back as Glas where they were stored', (tester) async {
      resetSharedPreferencesForTest();
      final service = await SettingsService.getInstance();
      for (final old in ['ocker', 'schwarz']) {
        await service.writeString(SettingsService.appThemeVariant.key, old);
        expect(service.read(SettingsService.appThemeVariant), AppThemeVariant.glas, reason: old);
      }
    });

    test('and out of an old backup', () {
      expect(SettingsService.appThemeVariant.fromJson('ocker'), AppThemeVariant.glas);
      expect(SettingsService.appThemeVariant.fromJson('schwarz'), AppThemeVariant.glas);
      expect(SettingsService.appThemeVariant.fromJson('klar'), AppThemeVariant.klar);
    });
  });

  // Icon defaults are process-wide statics; leave them as the app expects.
  tearDown(() => applyIconDefaultsFor(AppThemeVariant.standard));

  group('the standard theme is untouched', () {
    test('keeps the platform typeface', () {
      expect(_theme(AppThemeVariant.standard).textTheme.bodyMedium?.fontFamily, isNot('Inter'));
    });

    test('keeps filled, bold symbols', () {
      applyIconDefaultsFor(AppThemeVariant.standard);

      expect(AppIconDefaults.fill, 1);
      expect(AppIconDefaults.weight, 700);
    });

    test('keeps its spacing and radii', () {
      final tokens = _tokens(AppThemeVariant.standard);

      expect(tokens.space, 12);
      expect(tokens.radiusSm, 8);
    });
  });

  group('Klar', () {
    test('wears the platform typeface too, so no line loses a field to it', () {
      // Inter set about 4% wider than Roboto, and every line that measures
      // itself before drawing paid for that by dropping a field — on a
      // 1280x720 television the detail hero's facts row lost the audio format
      // and both rating badges in Klar alone.
      final klar = _theme(AppThemeVariant.klar);

      final standard = _theme(AppThemeVariant.standard);

      expect(klar.textTheme.bodyMedium?.fontFamily, standard.textTheme.bodyMedium?.fontFamily);
      expect(klar.textTheme.titleLarge?.fontFamily, standard.textTheme.titleLarge?.fontFamily);
      expect(klar.textTheme.bodyMedium?.fontFamily, isNot('Inter'));
    });

    test('turns the symbols into thin outlines', () {
      // The one call that reaches every icon drawn through AppIcon.
      applyIconDefaultsFor(AppThemeVariant.klar);

      expect(AppIconDefaults.fill, 0, reason: 'outline, not solid');
      expect(AppIconDefaults.weight, 300, reason: 'thin, not bold');
    });

    test('gives every token-driven surface more air', () {
      expect(_tokens(AppThemeVariant.klar).space, greaterThan(_tokens(AppThemeVariant.standard).space));
    });

    test('draws corners tighter, so a card reads as a crease not a pill', () {
      final klar = _tokens(AppThemeVariant.klar);
      final standard = _tokens(AppThemeVariant.standard);

      expect(klar.radiusSm, lessThan(standard.radiusSm));
      expect(klar.radiusLg, lessThan(standard.radiusLg));
    });

    test('drops the glyph in front of a section heading', () {
      // The heading already says what the row is; the glyph repeated it.
      expect(_tokens(AppThemeVariant.klar).sectionIcons, isFalse);
      expect(_tokens(AppThemeVariant.standard).sectionIcons, isTrue);
    });

    test('puts a plain person in the app bar instead of the profile picture', () {
      expect(_tokens(AppThemeVariant.klar).profileAvatar, isFalse);
      expect(_tokens(AppThemeVariant.standard).profileAvatar, isTrue);
    });

    test('makes focus rings and the active entry red', () {
      final klar = _tokens(AppThemeVariant.klar);
      final standard = _tokens(AppThemeVariant.standard);

      expect(klar.accent, const Color(0xFFD32F2F), reason: 'the red the tab chip already uses');
      expect(standard.accent, standard.text, reason: 'Standard keeps what those surfaces drew with');
    });

    test('draws the focus ring thinner', () {
      final klar = _tokens(AppThemeVariant.klar);
      final standard = _tokens(AppThemeVariant.standard);

      expect(standard.focusBorderWidth, 2.5);
      expect(klar.focusBorderWidth, closeTo(standard.focusBorderWidth * 0.7, 0.001));
    });

    test('lets no poster pick its own ring colour', () {
      // One accent is what a monochrome design has to point with; a ring that
      // changes hue per poster spends it.
      expect(_tokens(AppThemeVariant.klar).itemAccentFocusRing, isFalse);
      expect(_tokens(AppThemeVariant.standard).itemAccentFocusRing, isTrue);
    });

    test('sits on a deeper ground in the dark', () {
      final klar = _tokens(AppThemeVariant.klar);
      final standard = _tokens(AppThemeVariant.standard);

      expect(klar.bg.computeLuminance(), lessThan(standard.bg.computeLuminance()));
    });

    test('has a light side too, and it is not the dark one', () {
      final light = monoTheme(dark: false, variant: AppThemeVariant.klar).extension<MonoTokens>()!;

      expect(light.bg.computeLuminance(), greaterThan(0.5));
      expect(light.text.computeLuminance(), lessThan(0.5));
    });

    test('leaves OLED its pure black', () {
      // OLED exists to switch the panel off, which no variant may override.
      final oled = monoTheme(dark: true, oled: true, variant: AppThemeVariant.klar).extension<MonoTokens>()!;

      expect(oled.bg, const Color(0xFF000000));
    });

    test('leaves the typeface alone in OLED as well', () {
      final oled = monoTheme(dark: true, oled: true, variant: AppThemeVariant.klar);

      expect(oled.textTheme.bodyMedium?.fontFamily, monoTheme(dark: true, oled: true).textTheme.bodyMedium?.fontFamily);
    });
  });

  group('the redesign', () {
    test('rounds a shade more than the others, and in one ladder', () {
      // Square everywhere was the rule until the posters were rounded; a
      // square box beside a rounded picture read as the thing that had been
      // forgotten. See `artworkRadius`.
      final ocker = _tokens(AppThemeVariant.glas);
      final standard = _tokens(AppThemeVariant.standard);

      expect(ocker.radiusXs, greaterThan(standard.radiusXs));
      expect(ocker.radiusSm, greaterThan(standard.radiusSm));
      expect(ocker.radiusMd, greaterThan(standard.radiusMd));
      expect(ocker.radiusLg, greaterThan(standard.radiusLg));

      // A ladder, not four numbers: each step is larger than the one under it.
      expect(ocker.radiusXs, lessThan(ocker.radiusSm));
      expect(ocker.radiusSm, lessThan(ocker.radiusMd));
      expect(ocker.radiusMd, lessThan(ocker.radiusLg));
    });

    test('leaves the other two variants exactly as they were', () {
      expect(_tokens(AppThemeVariant.standard).radiusSm, 8);
      expect(_tokens(AppThemeVariant.klar).radiusSm, 6);
      expect(_tokens(AppThemeVariant.standard).radiusLg, 20);
      expect(_tokens(AppThemeVariant.klar).radiusLg, 16);
    });

    test('forbids shadows, which the others still allow', () {
      expect(_tokens(AppThemeVariant.glas).shadowsEnabled, isFalse);
      expect(_tokens(AppThemeVariant.standard).shadowsEnabled, isTrue);
      expect(_tokens(AppThemeVariant.klar).shadowsEnabled, isTrue);
    });

    test('is drawn in one typeface, whatever the three roles are called', () {
      final ocker = _tokens(AppThemeVariant.glas);

      // Three fields, one face. The fields stay because they are what the
      // branches read — displayFontFamily is the gate `isOcker` asks, and
      // monoFontFamily still marks the lines that get tabular figures.
      expect(ocker.displayFontFamily, 'Inter');
      expect(ocker.uiFontFamily, 'Inter');
      expect(ocker.monoFontFamily, 'Inter');
      expect(monoTheme(dark: true, variant: AppThemeVariant.glas).textTheme.bodyMedium?.fontFamily, 'Inter');
    });

    test('leaves the other two on the platform typeface', () {
      for (final variant in [AppThemeVariant.standard, AppThemeVariant.klar]) {
        final tokens = _tokens(variant);
        expect(tokens.displayFontFamily, isNull, reason: '$variant');
        expect(tokens.uiFontFamily, isNull, reason: '$variant');
        expect(tokens.monoFontFamily, isNull, reason: '$variant');
      }
    });

    test('ships every typeface it names', () {
      // A family name that no asset answers to falls back to the platform font
      // silently — the design would just quietly not be there.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final ocker = _tokens(AppThemeVariant.glas);

      for (final family in [ocker.displayFontFamily, ocker.uiFontFamily, ocker.monoFontFamily]) {
        expect(pubspec, contains('family: $family'), reason: '$family is not declared in pubspec.yaml');
      }
    });

    test('spends its accent on state, and draws focus in ink instead', () {
      // Ocher has three jobs — progress, the now-line, the active nav entry —
      // and a focus ring is not one of them: a white ring survives a bright
      // poster, and one colour used everywhere points at nothing.
      final ocker = _tokens(AppThemeVariant.glas);

      expect(ocker.focusRingColor, ocker.text);
      expect(ocker.focusRingColor, isNot(ocker.accent));
    });

    test('keeps ring and accent the same colour in the other two', () {
      for (final variant in [AppThemeVariant.standard, AppThemeVariant.klar]) {
        final tokens = _tokens(variant);
        expect(tokens.focusRingColor, tokens.accent, reason: '$variant');
        expect(tokens.focusRingOffset, 0, reason: '$variant');
      }
    });

    test('holds the focus ring off the artwork', () {
      // The tiles have no border of their own for a ring to hide behind.
      expect(_tokens(AppThemeVariant.glas).focusRingOffset, 5);
      expect(_tokens(AppThemeVariant.glas).focusBorderWidth, 1);
    });

    test('stays dark when the app is set to light', () {
      // There is no light half to switch to: the styleguide specifies one
      // ground and one ink, and a light counterpart would have to be invented.
      final light = monoTheme(dark: false, variant: AppThemeVariant.glas);

      expect(light.brightness, Brightness.dark);
      expect(light.extension<MonoTokens>()!.bg, glasPalette(GlasAccent.eisblau).bg);
    });

    test('goes pure black for OLED in every palette, and keeps its ink and its accent', () {
      for (final accent in GlasAccent.values) {
        final own = monoTheme(dark: true, variant: AppThemeVariant.glas, glasAccent: accent).extension<MonoTokens>()!;
        final oled = monoTheme(
          dark: true,
          oled: true,
          variant: AppThemeVariant.glas,
          glasAccent: accent,
        ).extension<MonoTokens>()!;

        expect(own.bg, glasPalette(accent).bg, reason: accent.name);
        expect(oled.bg, const Color(0xFF000000), reason: accent.name);
        expect(oled.text, own.text, reason: accent.name);
        expect(oled.accent, own.accent, reason: accent.name);
        expect(oled.redesignLayout, isTrue, reason: 'still the redesign');
      }
    });

    test('draws its symbols as the lightest outlines of the three', () {
      applyIconDefaultsFor(AppThemeVariant.glas);

      expect(AppIconDefaults.fill, 0, reason: 'outline, not solid');
      expect(AppIconDefaults.weight, 200, reason: 'lighter than Klar\'s 300');
    });
  });

  group('the redesign: the rules that are easy to lose', () {
    // These were written while a second variant wore the same paint on the
    // app's own layout. That variant is gone; the rules it made visible are
    // not, and every one of them is a place the design quietly stops being
    // itself if a later change is careless.
    test('sets titles in bold, through the theme rather than per screen', () {
      // Instrument Serif was the drawing and is not the screen: one weight,
      // hairline strokes, read across a room over a photograph. The title is
      // the one line that has to be legible first, so it is the interface
      // face at the one weight that survives the distance.
      final text = monoTheme(dark: true, variant: AppThemeVariant.glas).textTheme;

      for (final style in [text.displayLarge, text.displayMedium, text.displaySmall]) {
        expect(style?.fontWeight, FontWeight.w700);
      }
    });

    test('leaves no line of its type scale in another face', () {
      // The point of one typeface is that nothing escapes it. A style that
      // named a family the bundle no longer carries would fall back to the
      // platform font and read as a different app on that one line.
      //
      // Null is the ordinary case and the right one: the style inherits
      // `ThemeData.fontFamily`, which the test above pins to Inter. What must
      // not appear is a *different* family named here.
      final text = monoTheme(dark: true, variant: AppThemeVariant.glas).textTheme;

      for (final style in [
        text.displayLarge,
        text.displayMedium,
        text.displaySmall,
        text.headlineLarge,
        text.headlineMedium,
        text.titleLarge,
        text.bodyMedium,
      ]) {
        expect(style?.fontFamily, anyOf(isNull, 'Inter'));
      }
    });

    test('leaves the older variants on one family throughout', () {
      for (final variant in [AppThemeVariant.standard, AppThemeVariant.klar]) {
        final text = monoTheme(dark: true, variant: variant).textTheme;
        expect(text.displaySmall?.fontFamily, isNull, reason: '$variant');
        expect(text.displayMedium?.fontFamily, isNull, reason: '$variant');
      }
    });

    test('grows a focused card, like every other variant', () {
      // It did not, on the grounds that one focus mark is enough and a card
      // that changes size nudges its neighbours. The second half turned out
      // not to hold — the growth is paint-only, so nothing is re-laid out —
      // and the television asked for the movement: the ring alone reads as
      // less than a tile that steps forward.
      for (final variant in AppThemeVariant.values) {
        expect(_tokens(variant).focusScaleEnabled, isTrue, reason: '$variant');
      }
    });

    test('keeps the size Material gives the two merged display styles', () {
      // They are merged onto the scale rather than written fresh: a literal
      // would drop the size and leave every title at whatever the enclosing
      // DefaultTextStyle happened to be.
      final ocker = monoTheme(dark: true, variant: AppThemeVariant.glas).textTheme;
      final standard = monoTheme(dark: true).textTheme;

      expect(ocker.displaySmall?.fontSize, standard.displaySmall?.fontSize);
      expect(ocker.displayMedium?.fontSize, standard.displayMedium?.fontSize);
    });

    test('rearranges the screens, and so does its other palette', () {
      for (final variant in [AppThemeVariant.glas, AppThemeVariant.glas]) {
        expect(_tokens(variant).redesignLayout, isTrue, reason: '$variant');
      }
      for (final variant in [AppThemeVariant.standard, AppThemeVariant.klar]) {
        expect(_tokens(variant).redesignLayout, isFalse, reason: '$variant');
      }
    });

    testWidgets('leaves the corner radii written into widgets alone, in every variant', (tester) async {
      // Bare Theme rather than MaterialApp: MaterialApp interpolates one theme
      // into the next through AnimatedTheme, so the first frame after a swap
      // still reads the theme that is on its way out.
      Future<double> radiusUnder(AppThemeVariant variant) async {
        late double seen;
        await tester.pumpWidget(
          Theme(
            data: monoTheme(dark: true, variant: variant),
            child: Builder(
              builder: (context) {
                seen = flatRadius(context, 12);
                return const SizedBox();
              },
            ),
          ),
        );
        return seen;
      }

      // The wrapper stays even though nothing flattens any more — see
      // `flatRadius`. What it must not do is take a corner away from a variant
      // that asked for one.
      expect(await radiusUnder(AppThemeVariant.glas), 12, reason: 'the redesign rounds its boxes now');
      expect(await radiusUnder(AppThemeVariant.glas), 12);
      expect(await radiusUnder(AppThemeVariant.standard), 12, reason: 'Standard keeps the exact number it had');
      expect(await radiusUnder(AppThemeVariant.klar), 12);
    });

    testWidgets('drops the decorative shadows written into widgets', (tester) async {
      const shadow = BoxShadow(color: Color(0x55000000), blurRadius: 16);
      Future<List<BoxShadow>> shadowsUnder(AppThemeVariant variant) async {
        late List<BoxShadow> seen;
        await tester.pumpWidget(
          Theme(
            data: monoTheme(dark: true, variant: variant),
            child: Builder(
              builder: (context) {
                seen = flatShadows(context, const [shadow]);
                return const SizedBox();
              },
            ),
          ),
        );
        return seen;
      }

      expect(await shadowsUnder(AppThemeVariant.glas), isEmpty);
      expect(await shadowsUnder(AppThemeVariant.standard), [shadow]);
    });
  });
}
