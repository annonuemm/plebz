import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:plezy/navigation/navigation_tabs.dart';
import 'package:plezy/focus/focus_theme.dart';
import 'package:plezy/theme/flat_focus_ring.dart';
import 'package:plezy/widgets/fitted_metadata_line.dart';
import 'package:plezy/redesign/ocker_rail_shell.dart';
import 'package:plezy/redesign/ocker_side_rail.dart';
import 'package:plezy/services/settings_service.dart';
import '../test_helpers/prefs.dart';
import 'package:plezy/redesign/ocker_skin.dart';
import 'package:plezy/theme/mono_tokens.dart';
import 'package:plezy/widgets/desktop_app_bar.dart';
import 'package:plezy/widgets/mobile_navigation_rail.dart';
import 'package:plezy/redesign/ocker_glas_look.dart';
import 'package:plezy/redesign/ocker_floating_tab_bar.dart';
import 'package:plezy/redesign/ocker_type.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/theme/apple_type.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/app_icon.dart';
import 'package:plezy/widgets/focusable_list_tile.dart';
import 'package:plezy/widgets/settings_section.dart';

/// The Apple builds' own conventions (Plebz, the user's picks from Apple's
/// guidelines, 2026-10-13): SF Pro set by size, icons as heavy as the words,
/// Apple's glyphs, the floating tab bar, iOS-sized settings rows.
void main() {
  tearDown(() {
    debugOckerAppleSystemFont = null;
    TvDetectionService.debugSetAppleTVOverride(null);
    applyIconDefaultsFor(AppThemeVariant.standard);
  });

  group('SF Pro by size', () {
    test('takes the display cut from 20 points and Apple\'s tracking', () {
      const body = TextStyle(fontFamily: appleSystemTextFamily, fontSize: 17, letterSpacing: 0);
      final setBody = appleSystemType(body);
      expect(setBody.fontFamily, appleSystemTextFamily);
      expect(setBody.letterSpacing, closeTo(-0.026 * 17, 1e-9));

      const title = TextStyle(fontFamily: appleSystemTextFamily, fontSize: 28, letterSpacing: -1);
      final setTitle = appleSystemType(title);
      expect(setTitle.fontFamily, appleSystemDisplayFamily);
      expect(setTitle.letterSpacing, closeTo(0.014 * 28, 1e-9), reason: 'Inter\'s tightening gives way');
    });

    test('keeps letters spaced out on purpose, and leaves other faces alone', () {
      const caps = TextStyle(fontFamily: appleSystemTextFamily, fontSize: 19, letterSpacing: 2.4);
      expect(appleSystemType(caps).letterSpacing, 2.4);

      const inter = TextStyle(fontFamily: 'Inter', fontSize: 28, letterSpacing: -1);
      expect(appleSystemType(inter), same(inter));
    });

    test('measures the Apple TV in its own points', () {
      // 12 logical pixels are 24 points on the Apple TV's half-size surface.
      const label = TextStyle(fontFamily: appleSystemTextFamily, fontSize: 12);
      expect(appleSystemType(label).fontFamily, appleSystemTextFamily);
      final tv = appleSystemType(label, pointsPerPixel: 2);
      expect(tv.fontFamily, appleSystemDisplayFamily);
      expect(tv.letterSpacing, closeTo(appleTrackingEm(24) * 12, 1e-9));
    });

    test('the redesign\'s styles follow on Apple\'s builds, Inter elsewhere', () {
      expect(const OckerType(1).detailTitle().fontFamily, 'Inter');

      debugOckerAppleSystemFont = true;
      final title = const OckerType(1).detailTitle();
      expect(title.fontFamily, appleSystemDisplayFamily);
      expect(title.letterSpacing, greaterThan(0), reason: 'Apple opens a 50-point title up, Inter closed it');
      expect(const OckerType(1).sectionHeading.letterSpacing, 2.4, reason: 'tracked capitals stay tracked');
    });

    test('Glas on Apple\'s builds writes headings as Apple does; elsewhere the tracked capitals stay', () {
      const glas = OckerType(1);
      expect(glas.headingCase('Weiterschauen'), 'WEITERSCHAUEN');
      expect(glas.sectionHeading.letterSpacing, 2.4);

      const apple = OckerType(1, glasHeadings: true);
      expect(apple.headingCase('Weiterschauen'), 'Weiterschauen');
      expect(apple.sectionHeading.fontWeight, FontWeight.w700);

      const flach = OckerType(1, flat: true);
      expect(flach.headingCase('Weiterschauen'), 'Weiterschauen', reason: 'Flach as it was');
      expect(flach.sectionHeading.fontWeight, FontWeight.w600, reason: 'Flach as it was');
    });

    test('the theme\'s styles too, and only under the redesigns', () {
      debugOckerAppleSystemFont = true;
      final glas = monoTheme(MonoPalette.dark, variant: AppThemeVariant.glas).textTheme;
      expect(glas.titleLarge?.fontFamily, appleSystemDisplayFamily);
      expect(glas.bodyLarge?.fontFamily, appleSystemTextFamily);
      expect(glas.bodyLarge?.letterSpacing, closeTo(appleTrackingEm(16) * 16, 1e-9));

      final standard = monoTheme(MonoPalette.dark, variant: AppThemeVariant.standard).textTheme;
      expect(standard.titleLarge?.fontFamily, isNot(appleSystemDisplayFamily));
    });
  });

  group('icons', () {
    test('as heavy as the words under Glas everywhere; Apple\'s glyphs on Apple\'s builds only', () {
      applyIconDefaultsFor(AppThemeVariant.glas);
      expect(AppIconDefaults.weight, 400);
      expect(AppIconDefaults.opticalSizeFollowsSize, isTrue);
      expect(AppIconDefaults.substitutes, isEmpty, reason: 'Apple\'s glyphs only where SF Pro is');

      applyIconDefaultsFor(AppThemeVariant.flach);
      expect(AppIconDefaults.weight, 300, reason: 'Flach as it was');
      expect(AppIconDefaults.opticalSizeFollowsSize, isFalse);

      debugOckerAppleSystemFont = true;
      applyIconDefaultsFor(AppThemeVariant.glas);
      expect(AppIconDefaults.weight, 400);
      expect(AppIconDefaults.opticalSizeFollowsSize, isTrue);
      expect(AppIconDefaults.substitutes[Symbols.arrow_back_rounded], Symbols.arrow_back_ios_new_rounded);

      applyIconDefaultsFor(AppThemeVariant.standard);
      expect(AppIconDefaults.weight, 700, reason: 'Original keeps its icons');
      expect(AppIconDefaults.substitutes, isEmpty);
    });

    testWidgets('AppIcon draws the substitute, at an optical size that follows its size', (tester) async {
      debugOckerAppleSystemFont = true;
      applyIconDefaultsFor(AppThemeVariant.glas);
      await tester.pumpWidget(
        const Directionality(textDirection: TextDirection.ltr, child: AppIcon(Symbols.share_rounded, size: 30)),
      );
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.icon, Symbols.ios_share_rounded);
      expect(icon.opticalSize, 30);
      expect(icon.weight, 400);
    });
  });

  group('iPhone and iPad', () {
    Widget host(Widget child, {AppThemeVariant variant = AppThemeVariant.glas}) => MaterialApp(
      theme: monoTheme(MonoPalette.dark, variant: variant),
      home: Scaffold(body: child),
    );

    setUp(() {
      debugOckerAppleSystemFont = true;
      TvDetectionService.debugSetAppleTVOverride(false);
    });

    for (final (variant, expected) in [
      (AppThemeVariant.glas, true),
      (AppThemeVariant.flach, false),
      (AppThemeVariant.standard, false),
    ]) {
      testWidgets('the gate holds on a phone under Glas only (${variant.name})', (tester) async {
        bool? touch;
        await tester.pumpWidget(
          host(Builder(builder: (context) => Text('${touch = ockerGlasTouch(context)}')), variant: variant),
        );
        expect(touch, expected);
      });
    }

    for (final variant in [AppThemeVariant.glas, AppThemeVariant.flach]) {
      testWidgets('the floating tab bar answers taps and the hold (${variant.name})', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.reset);
        final picked = <int>[];
        var held = 0;
        await tester.pumpWidget(
          host(
            Align(
              alignment: Alignment.bottomCenter,
              child: OckerFloatingTabBar(
                selectedIndex: 1,
                onSelected: picked.add,
                items: [
                  const OckerFloatingTabBarItem(icon: Symbols.home_rounded, label: 'Start'),
                  OckerFloatingTabBarItem(
                    icon: Symbols.video_library_rounded,
                    label: 'Mediatheken',
                    onLongPress: () => held++,
                  ),
                  const OckerFloatingTabBarItem(icon: Symbols.more_horiz_rounded, label: 'Mehr'),
                ],
              ),
            ),
            variant: variant,
          ),
        );
        await tester.pump(const Duration(seconds: 1));

        await tester.tap(find.text('Mehr'));
        await tester.longPress(find.text('Mediatheken'));
        expect(picked, [2]);
        expect(held, 1);
        expect(
          tester.getSemantics(find.bySemanticsLabel('Mediatheken')),
          matchesSemantics(label: 'Mediatheken', isButton: true, isSelected: true, hasSelectedState: true),
        );
        final bar = tester.getRect(find.byType(OckerFloatingTabBar));
        final capsule = tester.getRect(find.byType(LayoutBuilder).first);
        expect(capsule.left - bar.left, OckerFloatingTabBar.sideMargin, reason: 'it floats clear of the edges');
        expect(tester.takeException(), isNull);
      });

      final apple = variant == AppThemeVariant.glas;
      testWidgets('settings rows: iOS\'s size in one card under Glas, dense under Flach (${variant.name})', (
        tester,
      ) async {
        await tester.pumpWidget(
          host(
            SingleChildScrollView(
              child: SettingsGroup(
                title: 'Darstellung',
                children: [
                  FocusableListTile(title: const Text('Akzentfarbe'), onTap: () {}),
                  // A row hidden on this device.
                  const SizedBox.shrink(),
                  FocusableListTile(title: const Text('Liquid Glass'), onTap: () {}),
                ],
              ),
            ),
            variant: variant,
          ),
        );
        await tester.pump(const Duration(seconds: 1));

        final title = tester.widget<RichText>(
          find.descendant(of: find.text('Akzentfarbe'), matching: find.byType(RichText)),
        );
        if (apple) {
          expect(tester.getSize(find.byType(ListTile).first).height, greaterThanOrEqualTo(appleMinTouchTarget));
          expect(title.text.style?.fontSize, appleListTitleSize);
          final gap = tester.getTopLeft(find.text('Liquid Glass')).dy - tester.getTopLeft(find.text('Akzentfarbe')).dy;
          expect(
            gap - tester.getSize(find.byType(ListTile).first).height,
            AppleSeparatedRows.hairline,
            reason: 'one hairline between the two rows, none for the hidden one',
          );
        } else {
          expect(title.text.style?.fontSize, 13, reason: 'Flach stays as it was');
          expect(find.byType(Divider), findsNothing);
        }
      });
    }

    testWidgets('the rail floats as glass and shows where one is', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1180, 820);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        host(
          Row(
            children: [
              MobileNavigationRail(
                tabs: [
                  for (final id in [NavigationTabId.discover, NavigationTabId.libraries])
                    allNavigationTabs.firstWhere((tab) => tab.id == id),
                ],
                selectedTab: NavigationTabId.libraries,
                showLabels: true,
                onDestinationSelected: (_) {},
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(OckerGlass), findsOneWidget);
      final context = tester.element(find.byType(NavigationRail));
      final tk = tokens(context);
      final theme = NavigationRailTheme.of(context);
      expect(theme.selectedLabelTextStyle?.color, tk.accent);
      expect(theme.indicatorColor, isNot(Colors.transparent));
      expect(theme.unselectedLabelTextStyle?.color, isNot(tk.accent));
      expect(tester.getTopLeft(find.byType(OckerGlass)).dx, MobileNavigationRail.appleMargin);
    });

    testWidgets('page bars fade softly instead of turning solid', (tester) async {
      await tester.pumpWidget(
        host(const CustomScrollView(slivers: [DesktopSliverAppBar(title: Text('Filme'), pinned: true)])),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(OckerScrollEdge), findsOneWidget);
      expect(tester.widget<SliverAppBar>(find.byType(SliverAppBar)).backgroundColor, Colors.transparent);
    });

    testWidgets('Glas tints the play button with any accent; Flach keeps its own', (tester) async {
      bool? glas;
      bool? flach;
      await tester.pumpWidget(host(Builder(builder: (context) => Text('${glas = ockerGlasTintedPlay(context)}'))));
      await tester.pumpWidget(
        host(
          Builder(builder: (context) => Text('${flach = ockerGlasTintedPlay(context)}')),
          variant: AppThemeVariant.flach,
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(glas, isTrue);
      expect(flach, isFalse);
    });

    for (final (variant, room) in [(AppThemeVariant.glas, true), (AppThemeVariant.flach, false)]) {
      testWidgets('the page makes room for the floating bar and rail under Glas only (${variant.name})', (
        tester,
      ) async {
        double? bottom;
        double? start;
        double? inner;
        await tester.pumpWidget(
          host(
            MediaQuery(
              data: const MediaQueryData(padding: EdgeInsets.only(left: 96, bottom: 70)),
              child: Builder(
                builder: (context) {
                  bottom = ockerFloatingBottomInset(context);
                  start = ockerFloatingStartInset(context);
                  return OckerClearOfRail(
                    child: Builder(
                      builder: (context) {
                        inner = MediaQuery.paddingOf(context).left;
                        return const SizedBox.expand(key: ValueKey('page'));
                      },
                    ),
                  );
                },
              ),
            ),
            variant: variant,
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(bottom, room ? 70 : 0);
        expect(start, room ? 96 : 0);
        expect(tester.getRect(find.byKey(const ValueKey('page'))).left, room ? 96 : 0);
        expect(inner, room ? 0 : 96, reason: 'under Glas nothing inside adds the room again');
      });
    }

    testWidgets('the rail covers its margin, its width and a gap as much again', (tester) async {
      double? flush;
      double? notched;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              MediaQuery(
                data: const MediaQueryData(),
                child: Builder(builder: (context) => Text('${flush = MobileNavigationRail.appleExtent(context)}')),
              ),
              MediaQuery(
                data: const MediaQueryData(padding: EdgeInsets.only(left: 59)),
                child: Builder(builder: (context) => Text('${notched = MobileNavigationRail.appleExtent(context)}')),
              ),
            ],
          ),
        ),
      );
      expect(flush, 8 + 88 + 8);
      expect(notched, 59 + 88 + 8, reason: 'past the notch, not the notch plus a margin');
    });

    testWidgets('under Flach the settings rows stay dense', (tester) async {
      await tester.pumpWidget(
        host(
          SettingsGroup(
            children: [FocusableListTile(title: const Text('Akzentfarbe'), onTap: () {})],
          ),
          variant: AppThemeVariant.flach,
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      final title = tester.widget<RichText>(
        find.descendant(of: find.text('Akzentfarbe'), matching: find.byType(RichText)),
      );
      expect(title.text.style?.fontSize, 13);
      expect(find.byType(Divider), findsNothing);
    });
  });

  group('Glas on the Apple TV', () {
    setUp(() async {
      resetSharedPreferencesForTest();
      SettingsService.resetForTesting();
      await SettingsService.getInstance();
      debugOckerAppleSystemFont = true;
      TvDetectionService.debugSetAppleTVOverride(true);
    });

    Future<BuildContext> pumpTv(
      WidgetTester tester,
      Widget child, {
      AppThemeVariant variant = AppThemeVariant.glas,
    }) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late BuildContext captured;
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(MonoPalette.dark, variant: variant),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                captured = context;
                return child;
              },
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      return captured;
    }

    testWidgets('only the page on show hides the place capsule, not a tab kept alive behind it', (tester) async {
      Widget page({required bool onShow}) => TickerMode(
        enabled: onShow,
        child: const OckerHidesPlace(hide: true, child: SizedBox()),
      );
      expect(OckerHidesPlace.hiding.value, 0);

      await tester.pumpWidget(page(onShow: false));
      await tester.pump();
      expect(OckerHidesPlace.hiding.value, 0, reason: 'the settings, left open behind the start page');

      await tester.pumpWidget(page(onShow: true));
      await tester.pump();
      expect(OckerHidesPlace.hiding.value, 1);

      await tester.pumpWidget(page(onShow: false));
      await tester.pump();
      expect(OckerHidesPlace.hiding.value, 0, reason: 'another tab chosen');

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(OckerHidesPlace.hiding.value, 0);
    });

    testWidgets('is Glas alone, not Flach', (tester) async {
      expect(ockerGlasTv(await pumpTv(tester, const SizedBox())), isTrue);
    });

    testWidgets('is not Flach', (tester) async {
      expect(ockerGlasTv(await pumpTv(tester, const SizedBox(), variant: AppThemeVariant.flach)), isFalse);
    });

    testWidgets('writes a line of facts as words with dots between them', (tester) async {
      await pumpTv(
        tester,
        const FittedMetadataLine(
          textStyle: TextStyle(fontSize: 20),
          chipped: true,
          parts: [MetadataLineText('Serie', dropPriority: 0), MetadataLineText('2026', dropPriority: 1)],
        ),
      );
      expect(find.text(FittedMetadataLine.flatSeparator), findsOneWidget);
    });

    testWidgets('rings a picture in white and lifts it as Flach does', (tester) async {
      final context = await pumpTv(tester, const SizedBox());
      final ring = FocusTheme.focusDecoration(
        context,
        isFocused: true,
        borderStrokeAlign: BorderSide.strokeAlignOutside,
      );
      expect(ring, isA<FlatFocusRingDecoration>());
      expect(FocusTheme.posterFocusScaleFor(context), FocusTheme.flatPosterFocusScale);
      expect(OckerLiquidFocusRim.showsInsteadOfRing(context), isFalse);
    });

    testWidgets('hides the shut rail and says at the top left where one is', (tester) async {
      final tabs = NavigationTab.getVisibleTabs(isOffline: false);
      final selected = tabs.firstWhere((tab) => tab.id == NavigationTabId.libraries);
      final railFocus = FocusScopeNode();
      final contentFocus = FocusScopeNode();
      addTearDown(railFocus.dispose);
      addTearDown(contentFocus.dispose);
      await pumpTv(
        tester,
        OckerRailShell(
          tabs: tabs,
          selectedTab: selected.id,
          onDestinationSelected: (_) {},
          onNavigateToContent: () {},
          expanded: false,
          railKey: GlobalKey<OckerSideRailState>(),
          railFocusScope: railFocus,
          contentFocusScope: contentFocus,
          content: const SizedBox.expand(key: ValueKey('page')),
        ),
      );
      expect(tester.getTopLeft(find.byKey(const ValueKey('page'))).dx, 0, reason: 'the page has the whole width');
      expect(find.text(selected.getLabel()), findsOneWidget, reason: 'the capsule names the place on show');
      final rail = tester.widget<Opacity>(
        find.descendant(of: find.byType(OckerSideRail), matching: find.byType(Opacity)).first,
      );
      expect(rail.opacity, 0, reason: 'no strip of symbols while shut');
    });
  });
}
