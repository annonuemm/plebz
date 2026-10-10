import 'package:flutter/material.dart' hide ThemeMode;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/focus_theme.dart';
import 'package:plezy/navigation/navigation_tabs.dart';
import 'package:plezy/redesign/ocker_side_rail.dart';
import 'package:plezy/redesign/ocker_skin.dart';
import 'package:plezy/redesign/ocker_type.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/flat_focus_ring.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/theme/mono_tokens.dart';
import 'package:plezy/redesign/ocker_filter_glyph.dart';
import 'package:plezy/screens/settings/plebz_settings_rows.dart' show RedesignGround, redesignGroundOf;
import 'package:plezy/theme/glass_backdrop.dart' show flachGroundGlows;
import 'package:plezy/widgets/app_icon.dart';
import 'package:plezy/widgets/fitted_metadata_line.dart';
import 'package:plezy/widgets/focusable_list_tile.dart';
import 'package:plezy/widgets/focusable_tab_chip.dart';
import 'package:plezy/widgets/plebz_start_animation.dart';
import 'package:plezy/widgets/unwatched_count_badge.dart';

ThemeData _flach({Color accent = const Color(0xFF00C2A8)}) =>
    monoTheme(dark: true, variant: AppThemeVariant.flach, flachAccent: accent);
ThemeData _glas() => monoTheme(dark: true, variant: AppThemeVariant.glas);

void main() {
  test('Flach is the redesign, built like Glas and painted flat, in the accent the viewer picked', () {
    expect(isRedesignVariant(AppThemeVariant.flach), isTrue);
    final tk = _flach().extension<MonoTokens>()!;
    expect(tk.redesignLayout, isTrue);
    expect(tk.glass, isTrue, reason: 'the structure and behaviour of glass');
    expect(tk.flat, isTrue);
    expect(tk.bg, flachGround);
    expect(tk.accent, const Color(0xFF00C2A8));
    expect(_glas().extension<MonoTokens>()!.flat, isFalse);
  });

  test('a picked accent reads from its hex, and anything else falls back to the violet', () {
    expect(flachAccentFromHex('#00C2A8'), const Color(0xFF00C2A8));
    expect(flachAccentFromHex('00c2a8'), const Color(0xFF00C2A8));
    expect(flachAccentFromHex('nonsense'), flachDefaultAccent);
    expect(SettingsService.flachAccent.defaultValue, '#A866EE');
  });

  testWidgets('flat focus inverts what stands on it, and only while focused', (tester) async {
    Future<void> pump(ThemeData theme, {required bool focused}) => tester.pumpWidget(
      Theme(
        data: theme,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: OckerWordFocus(focused: focused, child: const Text('Start')),
          ),
        ),
      ),
    );
    bool inverted() => tester.layers.whereType<ColorFilterLayer>().isNotEmpty;

    await pump(_flach(), focused: false);
    expect(inverted(), isFalse);
    await pump(_flach(), focused: true);
    expect(inverted(), isTrue);
    await pump(_glas(), focused: true);
    expect(inverted(), isFalse, reason: 'glass lights its words instead');
  });

  testWidgets('a flat focus fill is solid white; the one on show a lighter segment of ink', (tester) async {
    Future<Color?> fillOf({required bool bright, double tint = 0}) async {
      await tester.pumpWidget(
        Theme(
          data: _flach(),
          child: Center(
            child: SizedBox(
              width: 100,
              height: 40,
              child: OckerGlassFocusFill(shape: const StadiumBorder(), bright: bright, tint: tint),
            ),
          ),
        ),
      );
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: find.byType(OckerGlassFocusFill), matching: find.byType(DecoratedBox)).first,
      );
      return (box.decoration as ShapeDecoration).color;
    }

    final tk = _flach().extension<MonoTokens>()!;
    expect(await fillOf(bright: true), tk.ink(1));
    expect(await fillOf(bright: false, tint: 1), tk.ink(0.16));
  });

  testWidgets('a focused row gets a plain white frame, drawn where the caller aligns it', (tester) async {
    late BoxDecoration decoration;
    await tester.pumpWidget(
      Theme(
        data: _flach(),
        child: Builder(
          builder: (context) {
            decoration = FocusTheme.focusDecoration(context, isFocused: true);
            return const SizedBox();
          },
        ),
      ),
    );
    final side = (decoration.border! as Border).top;
    expect(side.color, _flach().extension<MonoTokens>()!.ink(1));
    expect(side.strokeAlign, BorderSide.strokeAlignInside, reason: 'a list row clips anything outside it');
  });

  testWidgets('a focused picture gets a thin ring standing off its edge, and grows by the design\'s 1.06', (
    tester,
  ) async {
    late BoxDecoration ring;
    late double flatScale;
    late double glasScale;
    Widget probe(ThemeData theme, void Function(BuildContext) read) => Theme(
      data: theme,
      child: Builder(
        builder: (context) {
          read(context);
          return const SizedBox();
        },
      ),
    );
    await tester.pumpWidget(
      probe(_flach(), (context) {
        ring = FocusTheme.focusDecoration(context, isFocused: true, borderStrokeAlign: BorderSide.strokeAlignOutside);
        flatScale = FocusTheme.posterFocusScaleFor(context);
      }),
    );
    await tester.pumpWidget(probe(_glas(), (context) => glasScale = FocusTheme.posterFocusScaleFor(context)));

    expect(ring, isA<FlatFocusRingDecoration>());
    final flat = ring as FlatFocusRingDecoration;
    expect(flat.gap, greaterThan(0), reason: 'air between the artwork and the ring');
    expect(flat.opacity, 1);
    expect(flatScale, FocusTheme.flatPosterFocusScale);
    expect(glasScale, FocusTheme.focusScale);
  });

  test('Flach names a row in sentence case and keeps the mono label for eyebrows only', () {
    const flat = OckerType(1, flat: true);
    const glas = OckerType(1);
    expect(flat.headingCase('Empfehlungen für dich'), 'Empfehlungen für dich');
    expect(glas.headingCase('Empfehlungen'), 'EMPFEHLUNGEN');
    expect(flat.sectionHeading.letterSpacing, lessThan(0), reason: 'set tight, not tracked out');
    expect(flat.eyebrow.letterSpacing, greaterThan(0), reason: 'the label keeps its tracking');
    expect(flat.sectionHeading.fontWeight, FontWeight.w600);
    expect(flat.counter.fontFamily, flat.sectionHeading.fontFamily);
    expect(flat.synopsis.height, 1.5);
    expect(flat.spotlightTitle(detail: true).fontSize, greaterThan(flat.spotlightTitle().fontSize!));
    expect(glas.sectionHeading, glas.eyebrow);
  });

  testWidgets('a chipped line of facts is plain words with dots under Flach, the age rating in an outline', (
    tester,
  ) async {
    Future<void> pump(ThemeData theme) => tester.pumpWidget(
      Theme(
        data: theme,
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: FittedMetadataLine(
              textStyle: TextStyle(fontSize: 19),
              chipped: true,
              parts: [
                MetadataLineText('2020', dropPriority: 0),
                MetadataLineText('Serie', dropPriority: 1),
                MetadataLineText('FSK 6', dropPriority: 2, badge: true),
              ],
            ),
          ),
        ),
      ),
    );

    await pump(_flach());
    expect(find.text(FittedMetadataLine.flatSeparator), findsNWidgets(2));
    expect(find.byType(OckerGlassPlate), findsNothing);
    final outline = tester.widget<Container>(
      find.ancestor(of: find.text('FSK 6'), matching: find.byType(Container)).first,
    );
    expect((outline.decoration! as BoxDecoration).border, isNotNull);

    await pump(_glas());
    expect(find.text(FittedMetadataLine.flatSeparator), findsNothing);
    expect(find.byType(OckerGlassPlate), findsNWidgets(3));
  });

  group('the facts line ranks its parts under Flach', () {
    Future<void> pump(WidgetTester tester, ThemeData theme, {bool secondary = false, double? width}) {
      const line = FittedMetadataLine(
        textStyle: TextStyle(fontSize: 19),
        chipped: true,
        parts: [
          MetadataLineText('2020', dropPriority: 0),
          MetadataLineText('FSK 6', dropPriority: 2, badge: true),
          MetadataLineText('Action', dropPriority: 5, quiet: true),
          MetadataLineText('Drama', dropPriority: 5, quiet: true),
        ],
      );
      return tester.pumpWidget(
        Theme(
          data: theme,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: SizedBox(
                width: width,
                child: secondary
                    ? FittedMetadataLine(textStyle: line.textStyle, chipped: true, secondary: true, parts: line.parts)
                    : line,
              ),
            ),
          ),
        ),
      );
    }

    TextStyle styleOf(WidgetTester tester, String text) => tester.widget<Text>(find.text(text)).style!;

    testWidgets('the facts bright, then a step and the genres quieter, joined by commas', (tester) async {
      await pump(tester, _flach());
      final tk = _flach().extension<MonoTokens>()!;
      expect(styleOf(tester, '2020').color, tk.ink(0.92));
      expect(styleOf(tester, '2020').fontWeight, FontWeight.w600);
      expect(styleOf(tester, 'Action').color, tk.ink(0.55));
      expect(styleOf(tester, 'Action').fontWeight, FontWeight.w500);
      // One dot between the two facts, none before the genres.
      expect(find.text(FittedMetadataLine.flatSeparator), findsOneWidget);
      expect(find.text(', '), findsOneWidget);
      final gap = tester.getTopLeft(find.text('Action')).dx - tester.getTopRight(find.text('FSK 6')).dx;
      expect(gap, greaterThan(19 * 0.9), reason: 'the step before the genres is wider than a dot gap');
    });

    testWidgets('the second row is smaller and quieter than the first', (tester) async {
      await pump(tester, _flach(), secondary: true);
      final tk = _flach().extension<MonoTokens>()!;
      expect(styleOf(tester, '2020').color, tk.ink(0.45));
      expect(styleOf(tester, '2020').fontSize, closeTo(19 * 0.82, 0.01));
    });

    testWidgets('a tight line sheds the last genre and its comma first', (tester) async {
      // 1 em per character: 2020 76, a dot gap 31, FSK 6 95 plus its outline
      // 18, the step 19, Action 114 — 353 — then the comma 38 and Drama 95.
      await pump(tester, _flach(), width: 400);
      expect(find.text('Action'), findsOneWidget);
      expect(find.text('Drama'), findsNothing);
      expect(find.text(', '), findsNothing);
    });

    testWidgets('Glas keeps every genre on a capsule of its own', (tester) async {
      await pump(tester, _glas());
      expect(find.text(', '), findsNothing);
      expect(find.byType(OckerGlassPlate), findsNWidgets(4));
    });
  });

  testWidgets('the unwatched count is a dark pill under Flach', (tester) async {
    await tester.pumpWidget(
      Theme(
        data: _flach(),
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: UnwatchedCountBadge(count: 35)),
        ),
      ),
    );
    final pill = tester.widget<Container>(find.byType(Container).first);
    final tk = _flach().extension<MonoTokens>()!;
    expect((pill.decoration! as BoxDecoration).color, tk.bg.withValues(alpha: 0.82));
  });

  testWidgets('a pane is tinted with the accent, a shade darker than the neutral grey it was', (tester) async {
    Future<Color> paneOn(ThemeData theme) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const OckerGlass(borderRadius: BorderRadius.zero, child: SizedBox(width: 100, height: 100)),
        ),
      );
      // The theme eases from the last one.
      await tester.pumpAndSettle();
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: find.byType(OckerGlass), matching: find.byType(DecoratedBox)).first,
      );
      return (box.decoration as BoxDecoration).color!;
    }

    final red = _flach(accent: const Color(0xFFE50914));
    final redPane = await paneOn(red);
    expect(redPane.r, greaterThan(redPane.b), reason: 'warm beside red lights, not bluish');
    final tk = red.extension<MonoTokens>()!;
    final neutral = Color.alphaBlend(tk.ink(0.05), tk.bg);
    expect(redPane.computeLuminance(), lessThan(neutral.computeLuminance()));
    expect(redPane.computeLuminance(), greaterThan(tk.bg.computeLuminance()), reason: 'still a step off the ground');

    final bluePane = await paneOn(_flach(accent: const Color(0xFF2E6BFF)));
    expect(bluePane.b, greaterThan(bluePane.r), reason: 'it follows the accent');
  });

  testWidgets('the rail marks the page on show with a stroke of the accent, under the Plebz mark', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final theme = _flach();
    final tk = theme.extension<MonoTokens>()!;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              height: 720,
              child: OckerSideRail(
                tabs: NavigationTab.getVisibleTabs(isOffline: false),
                selectedTab: NavigationTabId.discover,
                expanded: false,
                onDestinationSelected: (_) {},
                onNavigateToContent: () {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(PlebzMark), findsOneWidget);
    final strokes = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .where((box) => box.decoration is BoxDecoration && (box.decoration as BoxDecoration).color == tk.accent);
    expect(strokes, hasLength(1));
    // Just before its own glyph, not out at the screen's edge.
    final stroke = tester.getRect(find.byWidget(strokes.single));
    final glyph = tester.getRect(
      find.descendant(of: find.byKey(OckerSideRail.itemKey(NavigationTabId.discover)), matching: find.byType(AppIcon)),
    );
    expect(stroke.left, greaterThan(0));
    expect(glyph.left - stroke.right, inInclusiveRange(4, 14));
    expect(stroke.center.dy, closeTo(glyph.center.dy, 0.5));
  });

  testWidgets('the open rail\'s focus fill keeps clear room from both sides of the pane', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: _flach(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              height: 1080,
              child: OckerSideRail(
                tabs: NavigationTab.getVisibleTabs(isOffline: false),
                selectedTab: NavigationTabId.discover,
                expanded: true,
                onDestinationSelected: (_) {},
                onNavigateToContent: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final row = find.byKey(OckerSideRail.itemKey(NavigationTabId.libraries));
    tester.widget<Focus>(find.descendant(of: row, matching: find.byType(Focus)).first).focusNode!.requestFocus();
    await tester.pumpAndSettle();

    final fill = tester.getRect(find.descendant(of: row, matching: find.byType(OckerGlassFocusFill)));
    final pane = tester.getRect(find.byType(OckerSideRail));
    // In the design's units, 24 of room either side of a fill 54 high,
    // whatever the screen scales them by.
    final unit = fill.height / 54;
    expect(fill.left - pane.left, closeTo(24 * unit, 0.5));
    expect(pane.right - fill.right, closeTo(24 * unit, 0.5));
  });

  testWidgets('the row on show in a group column is a stroke of the accent, not a pane', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _flach(),
        home: Scaffold(
          body: FocusableListTile(title: const Text('Filme'), selected: true, glassMarks: true, onTap: () {}),
        ),
      ),
    );
    final stroke = tester.widget<Container>(find.byKey(flatSelectedStrokeKey));
    expect((stroke.decoration! as BoxDecoration).color, _flach().extension<MonoTokens>()!.accent);
    final fill = tester.widget<AnimatedOpacity>(
      find.ancestor(of: find.byType(OckerGlassFocusFill), matching: find.byType(AnimatedOpacity)),
    );
    expect(fill.opacity, 0, reason: 'no pane behind the row on show');
  });

  testWidgets('a row of tabs stands on one faint track; the controls beside it are shapes of their own', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _flach(),
        home: Scaffold(
          body: Row(
            children: [
              TabChipStrip(
                children: [
                  FocusableTabChip(label: 'Alle', isSelected: true, onSelect: () {}),
                  FocusableTabChip(label: 'Filme', isSelected: false, onSelect: () {}),
                ],
              ),
              const OckerFilterGlyph(icon: Icons.sort, focused: true),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final tk = _flach().extension<MonoTokens>()!;
    Iterable<Color?> fills() => tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((box) => box.decoration)
        .whereType<ShapeDecoration>()
        .map((d) => d.color);
    expect(fills(), contains(tk.ink(0.06)), reason: 'the track');
    expect(fills(), contains(tk.ink(0.16)), reason: 'the tab on show');
    expect(fills(), contains(tk.ink(1)), reason: 'the focused control');
  });

  group('the ground', () {
    test('off-black stands in for the design\'s own under both redesigns, and OLED wins over it', () {
      for (final variant in [AppThemeVariant.glas, AppThemeVariant.flach]) {
        MonoTokens tk({bool oled = false, Color? plain}) =>
            monoTheme(dark: true, oled: oled, plainGround: plain, variant: variant).extension<MonoTokens>()!;
        expect(tk(plain: redesignOffBlackGround).bg, redesignOffBlackGround, reason: variant.name);
        expect(tk(oled: true, plain: redesignOffBlackGround).bg, glasOledGround, reason: variant.name);
        expect(tk().bg, isNot(redesignOffBlackGround), reason: variant.name);
      }
      final standard = monoTheme(dark: true, plainGround: redesignOffBlackGround).extension<MonoTokens>()!;
      expect(standard.bg, isNot(redesignOffBlackGround), reason: 'the standard design has its own dark');
    });

    test('Flach\'s own ground carries the accent at the top left and the bottom right; the plain ones nothing', () {
      final own = _flach().extension<MonoTokens>()!;
      final glows = flachGroundGlows(own);
      expect(glows, hasLength(2));
      expect(glows.first.center, isA<Alignment>().having((a) => a.x < 0 && a.y < 0, 'top left', isTrue));
      expect(glows.last.center, isA<Alignment>().having((a) => a.x > 0 && a.y > 0, 'bottom right', isTrue));
      expect(glows.first.colors.first.withValues(alpha: 1), own.accent.withValues(alpha: 1));
      for (final plain in [
        monoTheme(dark: true, plainGround: redesignOffBlackGround, variant: AppThemeVariant.flach),
        monoTheme(dark: true, plainGround: const Color(0xFF1E2A4A), variant: AppThemeVariant.flach),
        monoTheme(dark: true, oled: true, variant: AppThemeVariant.flach),
        _glas(),
      ]) {
        expect(flachGroundGlows(plain.extension<MonoTokens>()!), isEmpty);
      }
    });

    test('every look stands on an off-black of its own — never black — and carries the accent\'s lights', () {
      expect(flachPresets.map((preset) => preset.id).toSet(), hasLength(flachPresets.length));
      expect(flachPresets.first.id, 'standard');
      for (final preset in flachPresets) {
        final ground = HSVColor.fromColor(preset.ground);
        expect(ground.value, inInclusiveRange(0.03, 0.16), reason: preset.id);
        final tk = monoTheme(
          dark: true,
          plainGround: preset.ground,
          variant: AppThemeVariant.flach,
          flachAccent: preset.accent,
        ).extension<MonoTokens>()!;
        expect(tk.bg, preset.ground, reason: preset.id);
        expect(flachGroundGlows(tk), hasLength(2), reason: preset.id);
      }
    });

    test('the stored choices read as one of three grounds', () {
      expect(redesignGroundOf(ThemeMode.dark, offBlack: false), RedesignGround.design);
      expect(redesignGroundOf(ThemeMode.dark, offBlack: true), RedesignGround.offBlack);
      expect(redesignGroundOf(ThemeMode.oled, offBlack: true), RedesignGround.oled);
      expect(redesignGroundOf(ThemeMode.system, offBlack: false), RedesignGround.design);
      expect(redesignGroundOf(ThemeMode.dark, offBlack: true, custom: true), RedesignGround.custom);
      expect(redesignGroundOf(ThemeMode.oled, offBlack: false, custom: true), RedesignGround.oled);
    });

    test('a ground of the viewer\'s own colour is taken down until the light ink reads on it', () {
      final dark = redesignGroundFromHex('#1E2A4A');
      expect(dark, const Color(0xFF1E2A4A), reason: 'dark enough already');
      final light = HSVColor.fromColor(redesignGroundFromHex('#F2C14E'));
      expect(light.value, closeTo(redesignGroundMaxValue, 0.01));
      expect(light.hue, closeTo(HSVColor.fromColor(const Color(0xFFF2C14E)).hue, 1), reason: 'the hue is kept');
      expect(redesignGroundFromHex('nonsense'), redesignOffBlackGround);
    });
  });

  testWidgets('a colour under a flat focus keeps itself where the words around it invert', (tester) async {
    bool? words;
    bool? colour;
    await tester.pumpWidget(
      Theme(
        data: _flach(),
        child: OckerFlatFocusInk(
          invert: true,
          child: Builder(
            builder: (context) {
              words = OckerFlatFocusInk.invertingAt(context);
              return OckerKeepColours(
                child: Builder(
                  builder: (context) {
                    colour = OckerFlatFocusInk.invertingAt(context);
                    return const SizedBox();
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
    expect(words, isTrue);
    expect(colour, isFalse);
  });
}
