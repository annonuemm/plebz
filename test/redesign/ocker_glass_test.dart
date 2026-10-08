import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/focus/focus_theme.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/focus/focusable_wrapper.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/providers/theme_provider.dart';
import 'package:plezy/navigation/navigation_tabs.dart';
import 'package:plezy/redesign/ocker_rail_shell.dart';
import 'package:plezy/redesign/ocker_skin.dart';
import 'package:plezy/services/device_performance.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/glass_backdrop.dart';
import 'package:plezy/theme/glass_focus_decoration.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/navigation_transitions.dart';
import 'package:plezy/theme/mono_tokens.dart';
import 'package:plezy/widgets/focusable_tab_chip.dart';
import 'package:plezy/widgets/library_copy_jump_button.dart';
import 'package:plezy/widgets/app_menu.dart';
import 'package:plezy/widgets/focusable_list_tile.dart';
import 'package:plezy/widgets/overlay_sheet.dart';

import '../test_helpers/prefs.dart';

/// "Redesign – Glas": the redesign with its floating surfaces made of glass,
/// in a palette its accent names.
void main() {
  MonoTokens tokensOf(ThemeData theme) => theme.extension<MonoTokens>()!;

  group('the theme', () {
    test('is the redesign, with glass', () {
      final tk = tokensOf(monoTheme(dark: true, variant: AppThemeVariant.glas));

      expect(isRedesignVariant(AppThemeVariant.glas), isTrue);
      expect(tk.redesignLayout, isTrue);
      expect(tk.displayFontFamily, ockerDisplayFontFamily, reason: 'every branch in lib/redesign/ asks this');
      expect(tk.glass, isTrue);
    });

    test('glass is its own: the other variants stay filled', () {
      for (final variant in AppThemeVariant.values.where((v) => !isRedesignVariant(v))) {
        expect(tokensOf(monoTheme(dark: true, variant: variant)).glass, isFalse, reason: variant.name);
      }
      // "Flach" keeps glass's structure and paints it flat (Plebz).
      final flat = tokensOf(monoTheme(dark: true, variant: AppThemeVariant.flach));
      expect((flat.glass, flat.flat), (true, true));
      expect(tokensOf(monoTheme(dark: true, variant: AppThemeVariant.glas)).flat, isFalse);
    });

    test('each accent brings its whole palette', () {
      for (final accent in GlasAccent.values) {
        final palette = glasPalette(accent);
        final tk = tokensOf(monoTheme(dark: true, variant: AppThemeVariant.glas, glasAccent: accent));
        expect(tk.accent, palette.accent, reason: accent.name);
        expect(tk.bg, palette.bg, reason: accent.name);
        expect(tk.text, palette.text, reason: accent.name);
      }
      final accents = {for (final a in GlasAccent.values) glasPalette(a).accent};
      expect(accents, hasLength(GlasAccent.values.length));
    });

    test('grey is the neutral one: no hue in its ground, ink or accent', () {
      final grey = glasPalette(GlasAccent.grau);
      // Apple's system grey is a breath cool; no more than that.
      for (final c in [grey.bg, grey.text, grey.accent]) {
        expect((c.r - c.b).abs(), lessThan(0.025));
        expect((c.r - c.g).abs(), lessThan(0.01));
      }
    });

    test('red is black, white and red: no hue in its ground or ink', () {
      final red = glasPalette(GlasAccent.rot);
      for (final c in [red.bg, red.text]) {
        expect(c.r, c.g);
        expect(c.g, c.b);
      }
      expect(red.bg.computeLuminance(), lessThan(0.01), reason: 'a black ground');
      expect(red.text, const Color(0xFFFFFFFF));
      expect(red.accent.r, greaterThan(0.85));
      expect(red.accent.g + red.accent.b, lessThan(0.15), reason: 'a red with nothing else in it');
    });

    test('red stands on flat black, lit from below by red itself, never a reddish grey', () {
      final red = glasPalette(GlasAccent.rot);
      final tk = tokensOf(monoTheme(dark: true, variant: AppThemeVariant.glas, glasAccent: GlasAccent.rot));
      expect(glassBackdropGradient(tk).colors.toSet(), {red.bg}, reason: 'flat black');
      final glow = glassBackdropGlow(tk);
      expect((glow.center as Alignment).y, greaterThan(1), reason: 'rising from below the foot');
      for (final c in glow.colors) {
        expect(c.withValues(alpha: 1), red.accent, reason: 'the pure red, unmixed: $c');
      }
      expect(glow.colors.first.a, greaterThan(glow.colors.last.a));
      // The tinted palettes keep their wash.
      final ice = tokensOf(monoTheme(dark: true, variant: AppThemeVariant.glas, glasAccent: GlasAccent.eisblau));
      expect(glassBackdropGradient(ice).colors[2].b, greaterThan(glassBackdropGradient(ice).colors[2].r));
    });

    test('every palette rings a poster in white, with a little of its accent at the bottom right', () {
      for (final accent in GlasAccent.values) {
        final palette = glasPalette(accent);
        final edge = tokensOf(monoTheme(dark: true, variant: AppThemeVariant.glas, glasAccent: accent)).glassFocusEdge;
        expect(edge.lit, palette.text, reason: '${accent.name}: its white ink where the light falls');
        expect(edge.mid.withValues(alpha: 1), palette.text, reason: '${accent.name}: white round the most of it');
        expect(edge.mid.a, greaterThan(0.8), reason: '${accent.name}: not thinned to grey');
        expect(
          edge.midTo,
          greaterThanOrEqualTo(0.75),
          reason: '${accent.name}: the accent a small share, in the corner',
        );
        expect(edge.end, palette.accent, reason: '${accent.name}: the accent at the bottom right');
      }
    });

    testWidgets('red marks the chosen in its red; the others as faintly as ever', (tester) async {
      Future<Color> chosenFill(GlasAccent accent, {bool bright = false}) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: monoTheme(dark: true, variant: AppThemeVariant.glas, glasAccent: accent),
            home: Center(
              child: SizedBox(
                width: 120,
                height: 48,
                child: OckerGlassFocusFill(shape: const StadiumBorder(), bright: bright, tint: 1),
              ),
            ),
          ),
        );
        // A theme swap cross-fades; the fill is read once it has settled.
        await tester.pumpAndSettle();
        final boxes = tester.widgetList<DecoratedBox>(
          find.descendant(of: find.byType(OckerGlassFocusFill), matching: find.byType(DecoratedBox)),
        );
        return (boxes.first.decoration as ShapeDecoration).color!;
      }

      final red = glasPalette(GlasAccent.rot);
      final fill = await chosenFill(GlasAccent.rot);
      expect(fill, Color.alphaBlend(red.accent.withValues(alpha: 0.7), red.bg.withValues(alpha: 0.30)));
      expect(fill.a, lessThan(0.85), reason: 'still glass: the ground shows a little through it');

      final ice = glasPalette(GlasAccent.eisblau);
      expect(
        await chosenFill(GlasAccent.eisblau),
        Color.alphaBlend(ice.accent.withValues(alpha: 0.22), ice.bg.withValues(alpha: 0.30)),
      );

      List<Color> sheenOf() {
        final boxes = tester.widgetList<DecoratedBox>(
          find.descendant(of: find.byType(OckerGlassFocusFill), matching: find.byType(DecoratedBox)),
        );
        return ((boxes.elementAt(1).decoration as ShapeDecoration).gradient! as LinearGradient).colors;
      }

      // Over solid red the focus sheen gives way, so a focused chosen row stays
      // red rather than pink; over a faint wash it stands whole.
      await chosenFill(GlasAccent.rot, bright: true);
      expect(sheenOf().first.a, lessThan(0.34 * 0.8));
      await chosenFill(GlasAccent.eisblau, bright: true);
      expect(sheenOf().first.a, closeTo(0.34, 0.002));
    });

    test('the accent does not reach the other variants', () {
      expect(
        monoTheme(dark: true, variant: AppThemeVariant.standard, glasAccent: GlasAccent.mint),
        same(monoTheme(dark: true, variant: AppThemeVariant.standard, glasAccent: GlasAccent.flieder)),
      );
    });

    test('stays dark whatever the light/dark switch says, as the redesign does', () {
      final light = tokensOf(monoTheme(dark: false, variant: AppThemeVariant.glas, glasAccent: GlasAccent.mint));
      expect(light.bg, glasPalette(GlasAccent.mint).bg);
    });
  });

  group('the provider', () {
    setUp(() async {
      resetSharedPreferencesForTest();
      SettingsService.resetForTesting();
    });

    test('draws the accent the settings name, and follows a change', () async {
      final service = await SettingsService.getInstance();
      await service.write(SettingsService.appThemeVariant, AppThemeVariant.glas);
      debugRedesignOfferedHere = true;
      addTearDown(() => debugRedesignOfferedHere = null);

      final provider = ThemeProvider();
      addTearDown(provider.dispose);
      await Future<void>.delayed(Duration.zero);
      expect(tokensOf(provider.darkTheme).accent, glasPalette(GlasAccent.eisblau).accent);

      var notified = 0;
      provider.addListener(() => notified++);
      await service.write(SettingsService.glasAccent, GlasAccent.flieder);
      await Future<void>.delayed(Duration.zero);

      expect(notified, greaterThan(0));
      expect(tokensOf(provider.darkTheme).accent, glasPalette(GlasAccent.flieder).accent);
    });
  });

  group('sheets', () {
    Future<void> openSheet(
      WidgetTester tester, {
      required AppThemeVariant variant,
      bool noGlass = false,
      Widget? row,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: true, variant: variant),
          home: OverlaySheetHost(
            child: Scaffold(
              body: Builder(
                builder: (hostContext) {
                  Widget opener = Builder(
                    builder: (context) => TextButton(
                      onPressed: () => OverlaySheetController.showAdaptive<void>(
                        context,
                        builder: (_) =>
                            Column(mainAxisSize: MainAxisSize.min, children: [const Text('Im Sheet'), ?row]),
                      ),
                      child: const Text('Open'),
                    ),
                  );
                  if (noGlass) opener = OverlaySheetNoGlass(child: opener);
                  return Center(child: opener);
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Im Sheet'), findsOneWidget);
    }

    testWidgets('are glass under glass', (tester) async {
      await openSheet(tester, variant: AppThemeVariant.glas);

      expect(find.ancestor(of: find.text('Im Sheet'), matching: find.byType(OckerGlass)), findsOneWidget);
    });

    testWidgets('hold more of the ground than a band, so their words read', (tester) async {
      await openSheet(tester, variant: AppThemeVariant.glas);

      final pane = tester.widget<OckerGlass>(
        find.ancestor(of: find.text('Im Sheet'), matching: find.byType(OckerGlass)),
      );
      // The reading strength — the same as a card's, one of the glass's two.
      expect(pane.groundOpacity, ockerReadingGroundOpacity);
      expect(
        const OckerGlass(borderRadius: BorderRadius.zero, child: SizedBox()).groundOpacity,
        ockerReadingGroundOpacity,
      );
      expect(ockerReadingGroundOpacity, greaterThan(ockerBandGroundOpacity));
    });

    testWidgets('mark their chosen row with a pane of glass, without the list asking', (tester) async {
      await openSheet(
        tester,
        variant: AppThemeVariant.glas,
        row: FocusableListTile(title: const Text('Filme - 4K'), selected: true, onTap: () {}),
      );

      expect(
        find.descendant(of: find.byType(FocusableListTile), matching: find.byType(OckerGlassFocusFill)),
        findsOneWidget,
      );
    });

    testWidgets('stay filled where the screen has nothing behind them', (tester) async {
      await openSheet(tester, variant: AppThemeVariant.glas, noGlass: true);

      expect(find.byType(OckerGlass), findsNothing);
    });
  });

  testWidgets('the glass holds its words in from the edge, on one darker pane', (tester) async {
    const corner = BorderRadius.all(Radius.circular(18));
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true, variant: AppThemeVariant.glas),
        home: const Center(
          child: SizedBox(
            width: 200,
            height: 100,
            child: OckerGlass(
              borderRadius: corner,
              child: SizedBox.expand(key: Key('words')),
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(const Key('words'))), const Size(184, 84), reason: '8 px of glass all round');
    // One surface: no firmer ground inset behind the words — it read as a
    // dark box inside the pane — but the whole pane darker than a band's.
    final layers = tester
        .widgetList<DecoratedBox>(
          find.ancestor(of: find.byKey(const Key('words')), matching: find.byType(DecoratedBox)),
        )
        .map((box) => box.decoration as BoxDecoration)
        .toList();
    expect(layers.where((d) => d.color != null && d.borderRadius != null && d.gradient == null), hasLength(1));
    final pane = layers.firstWhere((d) => d.color != null);
    expect(pane.color!.a, greaterThan(0.6));
    final ground = tokensOf(monoTheme(dark: true, variant: AppThemeVariant.glas)).bg;
    expect(pane.color!.withValues(alpha: 1), ground);
  });

  group('buttons', () {
    Future<void> pumpJump(WidgetTester tester, {required AppThemeVariant variant, required bool focused}) =>
        tester.pumpWidget(
          MaterialApp(
            theme: monoTheme(dark: true, variant: variant),
            home: Center(
              child: LibraryCopyJumpButton(copy: null, quality: null, showFocus: focused, onPressed: () {}),
            ),
          ),
        );

    testWidgets('lie bare on their row under glass, their ink brighter with focus', (tester) async {
      await pumpJump(tester, variant: AppThemeVariant.glas, focused: false);
      expect(find.byType(OckerGlassPlate), findsNothing);
      final tk = tokensOf(monoTheme(dark: true, variant: AppThemeVariant.glas));
      Color ink() => tester.widget<Text>(find.text(t.explore.comparingCopies)).style!.color!;
      expect(ink(), tk.ink(0.85));

      await pumpJump(tester, variant: AppThemeVariant.glas, focused: true);
      expect(ink(), tk.ink(1));
    });
  });

  group('the focus ring', () {
    Future<BuildContext> contextIn(WidgetTester tester, AppThemeVariant variant) async {
      late BuildContext captured;
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: true, variant: variant),
          home: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox();
            },
          ),
        ),
      );
      // The app animates between themes; wait for this one to arrive.
      await tester.pump(const Duration(seconds: 1));
      return captured;
    }

    testWidgets('is the lit edge under glass, and fades out rather than moving', (tester) async {
      final context = await contextIn(tester, AppThemeVariant.glas);
      BoxDecoration ring(bool focused) =>
          FocusTheme.focusDecoration(context, isFocused: focused, borderStrokeAlign: BorderSide.strokeAlignOutside);

      final on = ring(true), off = ring(false);
      expect(on, isA<GlassFocusDecoration>());
      expect((on as GlassFocusDecoration).opacity, 1);
      expect((off as GlassFocusDecoration).opacity, 0);
      expect(on.padding, off.padding, reason: 'nothing moves when focus arrives');
      final tk = tokensOf(Theme.of(context));
      expect(on.colors, tk.glassFocusEdge);
    });

    testWidgets('keeps a colour the caller names, and stays a line in the other themes', (tester) async {
      final glass = await contextIn(tester, AppThemeVariant.glas);
      expect(
        FocusTheme.focusDecoration(glass, isFocused: true, color: Colors.green),
        isNot(isA<GlassFocusDecoration>()),
      );

      final ocker = await contextIn(tester, AppThemeVariant.standard);
      final line = FocusTheme.focusDecoration(ocker, isFocused: true);
      expect(line, isNot(isA<GlassFocusDecoration>()));
      expect(line.border, isA<Border>());
    });

    testWidgets('animates in every direction a focus ring is animated', (tester) async {
      final glass = await contextIn(tester, AppThemeVariant.glas);
      final on = FocusTheme.focusDecoration(glass, isFocused: true) as GlassFocusDecoration;
      final off = FocusTheme.focusDecoration(glass, isFocused: false) as GlassFocusDecoration;
      final ocker = await contextIn(tester, AppThemeVariant.standard);
      final line = FocusTheme.focusDecoration(ocker, isFocused: true);

      // Focus arriving and leaving: the edge fades.
      expect((Decoration.lerp(off, on, 0.5)! as GlassFocusDecoration).opacity, closeTo(0.5, 0.001));
      // A theme switch under a live animation: Flutter's own border lerp only
      // knows its own borders, and must never be handed anything else.
      expect(() => Decoration.lerp(line, on, 0.5), returnsNormally);
      expect(() => Decoration.lerp(on, line, 0.5), returnsNormally);
    });

    testWidgets('paints round a box and round a disc', (tester) async {
      final edge = GlassFocusDecoration(
        colors: const GlassEdgeColors(lit: Colors.white, mid: Colors.white38, end: Colors.purple),
        opacity: 1,
        ringWidth: 1,
        strokeAlign: BorderSide.strokeAlignOutside,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
      );
      final disc = GlassFocusDecoration(
        colors: const GlassEdgeColors(lit: Colors.white, mid: Colors.white38, end: Colors.purple),
        opacity: 1,
        ringWidth: 1,
        shape: BoxShape.circle,
      );
      await tester.pumpWidget(
        Row(
          textDirection: TextDirection.ltr,
          children: [
            DecoratedBox(decoration: edge, child: const SizedBox(width: 60, height: 90)),
            DecoratedBox(decoration: disc, child: const SizedBox(width: 40, height: 40)),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a focused card animates its edge in without an error', (tester) async {
      Widget card(bool focused) => MaterialApp(
        theme: monoTheme(dark: true, variant: AppThemeVariant.glas),
        home: Center(
          child: Builder(
            builder: (context) => AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 100,
              height: 150,
              foregroundDecoration: FocusTheme.focusDecoration(context, isFocused: focused),
            ),
          ),
        ),
      );
      await tester.pumpWidget(card(false));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(card(true));
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('rows of words', () {
    Future<void> pumpTabs(
      WidgetTester tester,
      AppThemeVariant variant, {
      bool focused = false,
      bool active = false,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: true, variant: variant),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(40),
              child: TabChipStrip(
                children: [
                  OckerWordFocus(focused: focused, active: active, child: const Text('Empfohlen')),
                  const SizedBox(width: 20),
                  const Text('Durchsuchen'),
                ],
              ),
            ),
          ),
        ),
      );
      // The app animates between themes; wait for this one to arrive.
      await tester.pump(const Duration(seconds: 1));
      // A capsule claimed after that frame starts its fade on the next one.
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('lie on a pane under glass', (tester) async {
      Finder pane() =>
          find.descendant(of: find.byType(OckerGlassBand), matching: find.byType(IgnorePointer)).evaluate().isEmpty
          ? find.byKey(const Key('none'))
          : find.descendant(of: find.byType(OckerGlassBand), matching: find.byType(IgnorePointer)).first;
      await pumpTabs(tester, AppThemeVariant.glas);
      expect(pane(), findsOneWidget);
      // Plain glass: no firmer inner ground, which read as a second band.
      expect(find.descendant(of: pane(), matching: find.byType(Padding)), findsNothing);
      expect(find.byType(OckerGlass), findsNothing);
    });

    testWidgets('show focus as a capsule under glass', (tester) async {
      Finder glider() => find.byKey(OckerGlassBand.focusCapsuleKey);
      double shown() => glider().evaluate().isEmpty
          ? 0
          : tester.widget<Opacity>(find.descendant(of: glider(), matching: find.byType(Opacity)).first).opacity;

      await pumpTabs(tester, AppThemeVariant.glas, focused: true);
      expect(glider(), findsOneWidget, reason: 'on a band, focus is the band\'s own capsule');
      expect(shown(), 1);

      // Focused, the capsule rises a little out of the band, top and bottom.
      final band = tester.getRect(
        find.descendant(of: find.byType(OckerGlassBand), matching: find.byType(IgnorePointer)).first,
      );
      final lifted = tester.getRect(glider());
      expect(lifted.top, lessThan(band.top));
      expect(lifted.bottom, greaterThan(band.bottom));

      await pumpTabs(tester, AppThemeVariant.glas);
      expect(shown(), 0, reason: 'no capsule without focus');
    });

    testWidgets('the capsule glides from word to word instead of jumping', (tester) async {
      Future<void> focusOn(int index) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: monoTheme(dark: true, variant: AppThemeVariant.glas),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(40),
                child: TabChipStrip(
                  children: [
                    OckerWordFocus(focused: index == 0, child: const Text('Empfohlen')),
                    const SizedBox(width: 60),
                    OckerWordFocus(focused: index == 1, child: const Text('Durchsuchen')),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      Finder glider() => find.byKey(OckerGlassBand.focusCapsuleKey);
      await focusOn(0);
      await tester.pumpAndSettle();
      final from = tester.getRect(glider());

      await focusOn(1);
      await tester.pump(); // the word claims the capsule after it is laid out
      await tester.pump(const Duration(milliseconds: 90));
      final rightward = tester.getRect(glider());
      await tester.pumpAndSettle();
      final to = tester.getRect(glider());
      expect(to.left, greaterThan(from.right), reason: 'it ends at the second word');
      // Rightward too: the word it leaves lets go in the same frame the next
      // one claims, and that must read as moving along, not as leaving.
      expect(rightward.left, greaterThan(from.left));
      expect(rightward.left, lessThan(to.left), reason: 'on its way right, not already there');

      await focusOn(0);
      await tester.pump(); // the word claims the capsule after it is laid out
      await tester.pump(const Duration(milliseconds: 90));
      final between = tester.getRect(glider());
      expect(between.left, lessThan(to.left));
      expect(between.left, greaterThan(from.left), reason: 'on its way, not already there');
    });
  });

  testWidgets('under glass the one on show is a quiet capsule inside the band, not a rule', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true, variant: AppThemeVariant.glas),
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(40),
            child: TabChipStrip(
              children: [FocusableTabChip(label: 'Empfohlen', isSelected: true, onSelect: _noop)],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    final capsule = find.byKey(OckerGlassBand.activeCapsuleKey);
    expect(capsule, findsOneWidget, reason: 'on show without focus');
    final band = tester.getRect(
      find.descendant(of: find.byType(OckerGlassBand), matching: find.byType(IgnorePointer)).first,
    );
    final resting = tester.getRect(capsule);
    expect(band.top, lessThan(resting.top));
    expect(band.bottom, greaterThan(resting.bottom));
  });

  for (final variant in [AppThemeVariant.glas]) {
    testWidgets(
      '${variant.name}: a tab on show is marked ${variant == AppThemeVariant.glas ? 'by glass, centred' : 'by the rule'}',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: monoTheme(dark: true, variant: variant),
            home: Scaffold(
              body: Center(
                child: FocusableTabChip(label: 'Empfohlen', isSelected: true, onSelect: () {}),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        final accent = tokensOf(monoTheme(dark: true, variant: variant)).accent;
        final rules = tester.widgetList<Container>(find.byType(Container)).where((c) => c.color == accent);
        final word = tester.getRect(find.text('Empfohlen'));
        final chip = tester.getRect(find.byType(FocusableTabChip));
        if (variant == AppThemeVariant.glas) {
          expect(rules, isEmpty);
          expect(word.center.dy, closeTo(chip.center.dy, 0.5), reason: 'the word sits in the middle of the glass');
        } else {
          expect(rules, hasLength(1));
        }
      },
    );
  }

  for (final variant in [AppThemeVariant.glas]) {
    testWidgets('${variant.name}: a control that asks for glass focus gets it only under glass', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: true, variant: variant),
          builder: (context, child) => InputModeTracker(child: child!),
          home: Center(
            child: FocusableWrapper(
              focusNode: node,
              autofocus: true,
              useBackgroundFocus: true,
              glassFocus: true,
              borderRadius: 14,
              onSelect: () {},
              child: const SizedBox(width: 300, height: 60),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Focus shows under a remote, not under a pointer.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      final fill = find.byType(OckerGlassFocusFill);
      if (variant == AppThemeVariant.glas) {
        expect(fill, findsOneWidget);
        final shown = tester.widget<AnimatedOpacity>(find.ancestor(of: fill, matching: find.byType(AnimatedOpacity)));
        expect(shown.opacity, node.hasFocus ? 1 : 0);
      } else {
        expect(fill, findsNothing);
      }
    });
  }

  testWidgets('the band and the capsule at its end are concentric: one margin all round', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true, variant: AppThemeVariant.glas),
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(40),
            child: TabChipStrip(
              children: [
                FocusableTabChip(label: 'Empfohlen', isSelected: true, onSelect: _noop),
                FocusableTabChip(label: 'Durchsuchen', isSelected: false, onSelect: _noop),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    final band = tester.getRect(
      find.descendant(of: find.byType(OckerGlassBand), matching: find.byType(IgnorePointer)).first,
    );
    final capsule = tester.getRect(find.byKey(OckerGlassBand.activeCapsuleKey));
    final left = capsule.left - band.left, top = capsule.top - band.top, bottom = band.bottom - capsule.bottom;
    expect(left, greaterThan(0));
    expect(top, closeTo(left, 0.5));
    expect(bottom, closeTo(left, 0.5));
  });

  for (final variant in [AppThemeVariant.glas]) {
    testWidgets(
      '${variant.name}: a word\'s ink ${variant == AppThemeVariant.glas ? 'fades in step with the capsule' : 'changes at once'}',
      (tester) async {
        Future<void> ink(Color color) => tester.pumpWidget(
          MaterialApp(
            theme: monoTheme(dark: true, variant: variant),
            home: Center(
              child: OckerInk(
                color: color,
                builder: (context, c) => Text('Merkliste', style: TextStyle(color: c)),
              ),
            ),
          ),
        );
        Color shown() => tester.widget<Text>(find.text('Merkliste')).style!.color!;

        await ink(const Color(0xFF777777));
        await tester.pump(const Duration(seconds: 1));
        await ink(const Color(0xFFFFFFFF));
        await tester.pump(const Duration(milliseconds: 80));
        if (variant == AppThemeVariant.glas) {
          expect(shown(), isNot(const Color(0xFFFFFFFF)), reason: 'still on its way to white');
          expect(shown().r, greaterThan(const Color(0xFF777777).r));
          await tester.pump(const Duration(milliseconds: 300));
        }
        expect(shown(), const Color(0xFFFFFFFF));
      },
    );
  }

  testWidgets('the focus capsule swallows the quiet one as it passes over it, and gives it back', (tester) async {
    // Measured at the television's scale; a phone takes a fixed one.
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    Future<void> focusOn(int index) => tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true, variant: AppThemeVariant.glas),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(40),
            child: TabChipStrip(
              children: [
                OckerWordFocus(focused: index == 0, child: const Text('Empfohlen')),
                const SizedBox(width: 60),
                OckerWordFocus(focused: index == 1, active: true, child: const Text('Durchsuchen')),
              ],
            ),
          ),
        ),
      ),
    );
    final quiet = find.byKey(OckerGlassBand.activeCapsuleKey);
    double quietShown() => quiet.evaluate().isEmpty
        ? 0
        : tester.widget<Opacity>(find.descendant(of: quiet, matching: find.byType(Opacity))).opacity;

    await focusOn(0);
    await tester.pumpAndSettle();
    expect(quietShown(), 1, reason: 'the one on show, focus elsewhere');

    await focusOn(1);
    await tester.pump(); // the word claims the capsule after it is laid out
    final seen = <double>[];
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      seen.add(quietShown());
    }
    expect(seen.first, 1, reason: 'still whole while the focus capsule sets off');
    expect(seen.any((v) => v > 0 && v < 1), isTrue, reason: 'swallowed as it is covered, not gone at once');
    await tester.pumpAndSettle();
    expect(quietShown(), 0, reason: 'swallowed');

    await focusOn(0);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(quietShown(), 1, reason: 'given back as the focus capsule moves on');
  });

  group('the ground', () {
    test('under glass the pages carry a gradient; the others keep their colour', () {
      final glass = monoTheme(dark: true, variant: AppThemeVariant.glas);
      expect(glass.scaffoldBackgroundColor.a, 0, reason: 'clear, so the ground shows');
      // Clear ground rather than clear black: a scrim that gives it opacity
      // back fades into the palette, not into black.
      expect(glass.scaffoldBackgroundColor.withValues(alpha: 1), tokensOf(glass).bg);
      expect(
        glass.pageTransitionsTheme.builders.values,
        everyElement(isA<GlassBackdropTransitions>()),
        reason: 'every page travels on the ground',
      );
      // "Flach" travels on the same ground, painted plain (Plebz).
      final flat = monoTheme(dark: true, variant: AppThemeVariant.flach);
      expect(flat.scaffoldBackgroundColor.a, 0);
      expect(flat.pageTransitionsTheme.builders.values, everyElement(isA<GlassBackdropTransitions>()));
      for (final variant in AppThemeVariant.values.where((v) => !isRedesignVariant(v))) {
        final theme = monoTheme(dark: true, variant: variant);
        expect(theme.scaffoldBackgroundColor, tokensOf(theme).bg, reason: variant.name);
        expect(theme.pageTransitionsTheme.builders.values.whereType<GlassBackdropTransitions>(), isEmpty);
      }
    });

    testWidgets('grey stands on Apple TV\'s own ground; the others on their accent\'s', (tester) async {
      Future<Gradient?> groundOf(GlasAccent accent) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: monoTheme(dark: true, variant: AppThemeVariant.glas, glasAccent: accent),
            home: const GlassBackdrop(child: SizedBox.expand()),
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        final box = tester.widget<DecoratedBox>(
          find.descendant(of: find.byType(GlassBackdrop), matching: find.byType(DecoratedBox)).first,
        );
        return (box.decoration as BoxDecoration).gradient;
      }

      expect(await groundOf(GlasAccent.grau), neutralGlassBackdropGradient);
      expect(await groundOf(GlasAccent.eisblau), isNot(neutralGlassBackdropGradient));
    });

    test('every accent stands on the same ground, in its own colour: flat above, light at half height', () {
      for (final accent in GlasAccent.values) {
        final tk = tokensOf(monoTheme(dark: true, variant: AppThemeVariant.glas, glasAccent: accent));
        final ground = glassBackdropGradient(tk);
        expect(ground.colors.first, ground.colors[1], reason: '${accent.name}: flat across the top');
        // Red is black lit from below instead (its own test).
        if (accent == GlasAccent.rot) continue;
        expect(
          ground.colors[2].computeLuminance(),
          greaterThan(ground.colors.first.computeLuminance()),
          reason: '${accent.name}: lighter at half height',
        );
        final glow = glassBackdropGlow(tk);
        expect(glow.center, const Alignment(-0.78, 0), reason: '${accent.name}: the light to the left');
      }
    });

    testWidgets('with OLED on the ground is black and flat, with no light on it, whatever the accent', (tester) async {
      for (final accent in GlasAccent.values) {
        final theme = monoTheme(dark: true, oled: true, variant: AppThemeVariant.glas, glasAccent: accent);
        final tk = tokensOf(theme);
        expect(glassBackdropGradient(tk).colors.toSet(), {const Color(0xFF000000)}, reason: accent.name);
        expect(glassBackdropGlow(tk).colors.every((c) => c.a == 0), isTrue, reason: '${accent.name}: no glow');

        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: const GlassBackdrop(child: SizedBox.expand(key: Key('page'))),
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        final ground = find.ancestor(of: find.byKey(const Key('page')), matching: find.byType(GlassBackdrop)).first;
        expect(
          find.descendant(of: ground, matching: find.byType(DecoratedBox)),
          findsNothing,
          reason: '${accent.name}: no gradient, no glow',
        );
        expect(
          tester.widget<ColoredBox>(find.descendant(of: ground, matching: find.byType(ColoredBox)).first).color,
          const Color(0xFF000000),
          reason: accent.name,
        );
      }
    });

    testWidgets('the shell stands on the glass ground', (tester) async {
      await initializeDateFormatting('en');
      // The shell reads whether the ground follows the focused title.
      resetSharedPreferencesForTest();
      SettingsService.resetForTesting();
      await SettingsService.getInstance();
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final railScope = FocusScopeNode();
      final contentScope = FocusScopeNode();
      addTearDown(railScope.dispose);
      addTearDown(contentScope.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: true, variant: AppThemeVariant.glas),
          home: OckerRailShell(
            tabs: [
              NavigationTab(id: NavigationTabId.discover, onlineOnly: false, icon: Icons.home, getLabel: () => 'Start'),
            ],
            selectedTab: NavigationTabId.discover,
            expanded: false,
            onDestinationSelected: (_) {},
            onNavigateToContent: () {},
            railKey: GlobalKey(),
            railFocusScope: railScope,
            contentFocusScope: contentScope,
            content: const SizedBox.expand(key: Key('screen')),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      final grounds = find.ancestor(of: find.byKey(const Key('screen')), matching: find.byType(GlassBackdrop));
      final flat = tester
          .widgetList<ColoredBox>(find.ancestor(of: find.byKey(const Key('screen')), matching: find.byType(ColoredBox)))
          .where((box) => box.color.a == 1);
      expect(
        find.descendant(of: grounds.first, matching: find.byType(DecoratedBox)),
        findsWidgets,
        reason: 'the gradient under every destination',
      );
      expect(flat, isEmpty, reason: 'nothing flat over it');
    });

    testWidgets('a page pushed under glass lies on the gradient', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: true, variant: AppThemeVariant.glas),
          home: const Scaffold(body: Text('Seite')),
        ),
      );
      await tester.pumpAndSettle();
      final ground = find.ancestor(of: find.text('Seite'), matching: find.byType(GlassBackdrop));
      expect(ground, findsOneWidget);
      final painted = tester.widget<DecoratedBox>(
        find.descendant(of: ground, matching: find.byType(DecoratedBox)).first,
      );
      expect((painted.decoration as BoxDecoration).gradient, isA<LinearGradient>());
    });
  });

  for (final variant in [AppThemeVariant.glas]) {
    testWidgets(
      '${variant.name}: the chosen menu row is marked ${variant == AppThemeVariant.glas ? 'by glass' : 'by the rule'}',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: monoTheme(dark: true, variant: variant),
            home: Scaffold(
              body: AppMenuList<int>(
                entries: const [
                  AppMenuItem(value: 0, label: 'Empfohlen'),
                  AppMenuItem(value: 1, label: 'Durchsuchen', selected: true),
                ],
                onSelected: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final accent = tokensOf(monoTheme(dark: true, variant: variant)).accent;
        final rules = tester.widgetList<Container>(find.byType(Container)).where((c) => c.color == accent);
        if (variant == AppThemeVariant.glas) {
          expect(rules, isEmpty);
          final panes = tester.widgetList<OckerGlassFocusFill>(find.byType(OckerGlassFocusFill)).toList();
          expect(panes.where((p) => p.tint == 1), hasLength(1), reason: 'the chosen row wears the wash');
        } else {
          expect(rules, hasLength(1));
          expect(find.byType(OckerGlassFocusFill), findsNothing);
        }
      },
    );
  }

  testWidgets('a cell keeps its size when glass focus sits behind it', (tester) async {
    Future<Size> cell(bool focused) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: true, variant: AppThemeVariant.glas),
          home: Center(
            child: SizedBox(
              width: 100,
              height: 60,
              child: OckerGlassFocusBehind.wrap(
                focused,
                const StadiumBorder(),
                const Column(key: Key('cell'), mainAxisSize: MainAxisSize.min, children: [SizedBox(height: 10)]),
              ),
            ),
          ),
        ),
      );
      return tester.getSize(find.byKey(const Key('cell')));
    }

    expect(await cell(false), const Size(100, 60));
    expect(await cell(true), const Size(100, 60), reason: 'a focused logo does not jump to the top');
  });

  group('smooth focus', () {
    setUp(() async {
      resetSharedPreferencesForTest();
      SettingsService.resetForTesting();
      await SettingsService.getInstance();
    });
    tearDown(DevicePerformance.debugReset);

    const glide = Duration(milliseconds: 220);

    test('the full tier glides whatever the switch says', () {
      DevicePerformance.debugReset(override: VisualEffectsSetting.full);
      expect(ockerGlassMotion(glide), glide);
    });

    test('a reduced tier jumps, unless the viewer switched the glide on', () async {
      DevicePerformance.debugReset(override: VisualEffectsSetting.reduced);
      expect(ockerGlassMotion(glide), Duration.zero);

      await SettingsService.instanceOrNull!.write(SettingsService.glasSmoothFocus, true);
      expect(ockerGlassMotion(glide), glide, reason: 'on its own, without the rest of the effects');
    });
  });

  testWidgets('the session\'s route paints no ground of its own: the video lies under it', (tester) async {
    // The player is pushed into the session's navigator and shows a stream
    // composited under the whole Flutter view. A ground on the route that
    // holds that navigator stood between the two, and a playing stream showed
    // only the gradient.
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: monoTheme(dark: true, variant: AppThemeVariant.glas),
        home: const SizedBox.shrink(),
      ),
    );
    navigator.currentState!.push(fadeRoute<void>(const SizedBox.expand(key: Key('session'))));
    await tester.pumpAndSettle();

    expect(find.ancestor(of: find.byKey(const Key('session')), matching: find.byType(GlassBackdrop)), findsNothing);
  });
}

void _noop() {}
