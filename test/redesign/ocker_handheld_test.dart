import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:plezy/redesign/ocker_filter_glyph.dart';
import 'package:plezy/redesign/ocker_skin.dart';
import 'package:plezy/services/settings_service.dart' show AppThemeVariant;
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/widgets/focusable_filter_chip.dart';
import 'package:plezy/widgets/focusable_tab_chip.dart';

/// A phone or tablet wears the redesign's look and keeps its own layout. The
/// test binding reports Android, so without the television override every
/// test here is a phone.
void main() {
  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    debugOckerLayoutOnThisHost = null;
  });

  Future<({bool layout, double scale})> probe(WidgetTester tester, Size size, {TargetPlatform? platform}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late bool layout;
    late double scale;
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true, variant: AppThemeVariant.glas).copyWith(platform: platform),
        home: Builder(
          builder: (context) {
            layout = isOckerLayout(context);
            scale = ockerScale(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return (layout: layout, scale: scale);
  }

  testWidgets('a phone gets the look but none of the rearranging', (tester) async {
    final phone = await probe(tester, const Size(390, 844));
    expect(phone.layout, isFalse, reason: 'the screens keep their own headers and navigation');

    TvDetectionService.debugSetAppleTVOverride(true);
    final tv = await probe(tester, const Size(960, 540));
    expect(tv.layout, isTrue);
  });

  testWidgets('a phone and a tablet take a fixed scale, not one read off their width', (tester) async {
    // By width a phone landed at the floor, a menu heading at nine points.
    expect((await probe(tester, const Size(390, 844))).scale, ockerHandheldScale);
    expect((await probe(tester, const Size(1024, 1366))).scale, ockerHandheldScale);

    TvDetectionService.debugSetAppleTVOverride(true);
    expect((await probe(tester, const Size(960, 540))).scale, 0.5, reason: 'the television is unchanged');
  });

  testWidgets('a Mac window gets the look too, and keeps its own layout', (tester) async {
    debugOckerLayoutOnThisHost = false;
    final mac = await probe(tester, const Size(1440, 900), platform: TargetPlatform.macOS);
    expect(mac.layout, isFalse, reason: 'the window keeps its own navigation and headers');
    expect(mac.scale, ockerHandheldScale, reason: 'read from a desk, not across the room');

    // Windows and Linux keep the rearranged screens they had.
    debugOckerLayoutOnThisHost = true;
    final windows = await probe(tester, const Size(1440, 900), platform: TargetPlatform.windows);
    expect(windows.layout, isTrue);
  });

  testWidgets('a Mac forced into the television layout is a television', (tester) async {
    debugOckerLayoutOnThisHost = false;
    TvDetectionService.debugSetAppleTVOverride(true);
    expect((await probe(tester, const Size(960, 540), platform: TargetPlatform.macOS)).layout, isTrue);
  });

  Future<void> pumpChip(WidgetTester tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true, variant: AppThemeVariant.glas),
        home: Scaffold(
          body: Center(
            child: FocusableFilterChip(icon: Symbols.sort_rounded, label: 'Titel', onPressed: () {}, focusNode: node),
          ),
        ),
      ),
    );
  }

  testWidgets('on a phone a filter says what it is, on a capsule of glass', (tester) async {
    // Nothing ever focuses it there, so a glyph alone would never be named.
    await pumpChip(tester);

    expect(find.text('Titel'), findsOneWidget);
    expect(find.ancestor(of: find.text('Titel'), matching: find.byType(OckerGlassPlate)), findsOneWidget);
    expect(find.byType(OckerFilterGlyph), findsNothing);
  });

  testWidgets('on a television it stays the bare glyph beside the tabs', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    await pumpChip(tester);

    expect(find.byType(OckerFilterGlyph), findsOneWidget);
    expect(find.text('Titel'), findsNothing);
  });

  testWidgets('on a phone a tab is set at a reading size, so a library\'s three views fit across', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true, variant: AppThemeVariant.glas),
        home: Scaffold(
          body: FocusableTabChip(label: 'Sammlungen', isSelected: false, onSelect: () {}),
        ),
      ),
    );
    expect(tester.widget<Text>(find.text('Sammlungen')).style?.fontSize, 15);
  });

  test('every text style of the glass theme is set in its own face', () {
    // Through ThemeData.fontFamily alone the geometry scale's styles, which do
    // not inherit, lost the family in the merge: list titles, settings and
    // dialogs fell to the platform's face.
    final glass = monoTheme(dark: true, variant: AppThemeVariant.glas).textTheme;
    for (final style in [glass.bodyLarge, glass.bodyMedium, glass.titleMedium, glass.labelLarge, glass.headlineSmall]) {
      expect(style?.fontFamily, ockerUiFontFamily);
    }
    expect(
      monoTheme(dark: true).textTheme.bodyLarge?.fontFamily,
      isNot(ockerUiFontFamily),
      reason: 'the original look keeps its own',
    );
  });
}
