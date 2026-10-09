import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_role.dart';
import 'package:plezy/redesign/ocker_detail_panel.dart';
import 'package:plezy/redesign/ocker_focus_bus.dart';
import 'package:plezy/services/settings_service.dart' show AppThemeVariant;
import 'package:plezy/redesign/ocker_skin.dart';
import 'package:plezy/redesign/ocker_type.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/content_utils.dart';
import 'package:plezy/utils/formatters.dart';
import 'package:plezy/widgets/optimized_media_image.dart';
import 'package:plezy/widgets/tv_spotlight_background.dart' show SpotlightSummary;

import '../test_helpers/media_items.dart';
import '../test_helpers/prefs.dart';

/// The panel replaces a hero banner, and the whole argument for it is that it
/// describes *whatever holds focus* rather than one chosen title. So the things
/// worth pinning are: it is never focusable, it says where in the section you
/// are, and it settles instead of strobing when a row is run through fast.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(resetSharedPreferencesForTest);

  final bus = OckerFocusBus();
  tearDownAll(bus.dispose);

  final hub = MediaHub(
    id: 'weiter',
    title: 'Weiter ansehen',
    type: 'mixed',
    items: [
      for (var i = 0; i < 7; i++)
        testMediaItem(
          id: 'i$i',
          title: 'Titel $i',
          summary: 'Beschreibung $i',
          durationMs: 3600000,
          viewOffsetMs: 900000,
        ),
    ],
  );

  Future<void> pumpPanel(WidgetTester tester, {AppThemeVariant variant = AppThemeVariant.glas}) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true, variant: variant),
        home: Scaffold(
          body: OckerFocusScope(
            bus: bus,
            child: OckerDetailPanel(resolveClient: (_) => null),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('is not a focus target — nothing in it can be reached', (tester) async {
    bus.report(OckerFocused(item: hub.items.first, hub: hub, index: 0));
    await pumpPanel(tester);

    // Scoped to the panel itself: MaterialApp and Scaffold put Focus widgets
    // above it, and those are not what this is about.
    expect(
      find.descendant(of: find.byType(OckerDetailPanel), matching: find.byType(Focus)),
      findsNothing,
      reason: 'the panel describes; it is never somewhere focus can go',
    );
    expect(
      find.descendant(of: find.byType(OckerDetailPanel), matching: find.byType(FocusableActionDetector)),
      findsNothing,
    );
  });

  testWidgets('describes whatever was reported, title and synopsis together', (tester) async {
    bus.report(OckerFocused(item: hub.items[2], hub: hub, index: 2));
    await pumpPanel(tester);

    expect(find.text('Titel 2'), findsOneWidget);
    expect(find.text('Beschreibung 2'), findsOneWidget);
  });

  for (final variant in [AppThemeVariant.glas, AppThemeVariant.glas]) {
    testWidgets(
      '${variant.name}: ${variant == AppThemeVariant.glas ? 'the words stand on a pane of glass, without the tagline' : 'the words stand bare, the tagline under the title'}',
      (tester) async {
        final film = testMediaItem(
          id: 'film',
          title: 'Die Camino-Therapie',
          summary: 'Wenn zwei sich auf den Weg machen.',
          tagline: 'Walking means Saving.',
        );
        final films = MediaHub(id: 'filme', title: 'Filme', type: 'movie', items: [film]);
        bus.report(OckerFocused(item: film, hub: films, index: 0));
        await pumpPanel(tester, variant: variant);

        final onGlass = find.ancestor(
          of: find.text('Wenn zwei sich auf den Weg machen.'),
          matching: find.byType(OckerGlass),
        );
        if (variant == AppThemeVariant.glas) {
          expect(onGlass, findsOneWidget);
          expect(find.text('Walking means Saving.'), findsNothing);
        } else {
          expect(onGlass, findsNothing);
          expect(find.text('Walking means Saving.'), findsOneWidget);
        }
      },
    );
  }

  testWidgets('glas and flach set the description at the same size', (tester) async {
    final item = testMediaItem(id: 'gleich', title: 'Gleich', summary: 'Ein Satz.');
    final films = MediaHub(id: 'filme', title: 'Filme', type: 'movie', items: [item]);
    bus.report(OckerFocused(item: item, hub: films, index: 0));
    double size() => tester.widget<Text>(find.text('Ein Satz.')).style!.fontSize!;

    await pumpPanel(tester, variant: AppThemeVariant.glas);
    final glas = size();
    await pumpPanel(tester, variant: AppThemeVariant.flach);
    expect(glas, size());
  });

  testWidgets('glas: the name is type, smaller than the panel\'s own, and the card stands still down to the foot', (
    tester,
  ) async {
    final short = testMediaItem(id: 'kurz', title: 'Kurz', summary: 'Ein Satz.');
    final long = testMediaItem(id: 'lang', title: 'Lang', summary: List.filled(40, 'Viele Worte.').join(' '));
    final films = MediaHub(id: 'filme', title: 'Filme', type: 'movie', items: [short, long]);
    bus.report(OckerFocused(item: short, hub: films, index: 0));
    await pumpPanel(tester, variant: AppThemeVariant.glas);

    expect(find.byType(ClearLogoImage), findsNothing, reason: 'no wordmarks on glass');
    final title = tester.widget<Text>(find.text('Kurz'));
    final full = OckerType.of(tester.element(find.text('Kurz'))).detailTitle().fontSize!;
    expect(title.style!.fontSize, moreOrLessEquals(full * OckerDetailPanel.glassTitleScale, epsilon: 0.01));

    Rect card() => tester.getRect(find.byType(OckerGlass));
    final before = card();
    expect(
      before.bottom,
      moreOrLessEquals(
        1080 - OckerDetailPanel.glassCardFoot * ockerScale(tester.element(find.byType(OckerGlass))),
        epsilon: 1,
      ),
    );

    bus.report(OckerFocused(item: long, hub: films, index: 1));
    await tester.pumpAndSettle();
    expect(card(), before, reason: 'a longer synopsis does not change the card');
    expect(
      tester.widget<SpotlightSummary>(find.byType(SpotlightSummary)).maxLines,
      greaterThan(8),
      reason: 'the synopsis has every whole line the card has room for, not a fixed eight',
    );
  });

  testWidgets('glas: the credits the row carries stand at the foot of the card', (tester) async {
    final film = testMediaItem(
      id: 'credits',
      title: 'Mit Credits',
      summary: 'Kurz.',
      directors: ['Regine Regie'],
      roles: const [
        MediaRole(tag: 'Anna Eins'),
        MediaRole(tag: 'Bert Zwei'),
        MediaRole(tag: 'Cora Drei'),
        MediaRole(tag: 'Dirk Vier'),
      ],
    );
    final films = MediaHub(id: 'filme', title: 'Filme', type: 'movie', items: [film]);
    bus.report(OckerFocused(item: film, hub: films, index: 0));
    await pumpPanel(tester, variant: AppThemeVariant.glas);

    final director = find.textContaining('Regine Regie', findRichText: true);
    final cast = find.textContaining('Anna Eins, Bert Zwei, Cora Drei', findRichText: true);
    expect(director, findsOneWidget);
    expect(cast, findsOneWidget);
    expect(find.textContaining('Dirk Vier', findRichText: true), findsNothing, reason: 'three of the cast');

    final card = tester.getRect(find.byType(OckerGlass));
    expect(card.bottom - tester.getRect(cast).bottom, lessThan(40), reason: 'at the foot of the card');

    // A hairline over them, across the card inside its inset.
    final rule = tester.getRect(find.byKey(glassCreditsRuleKey));
    expect(rule.height, 1);
    expect(rule.bottom, lessThanOrEqualTo(tester.getRect(director).top));
    final inset = 18 * ockerScale(tester.element(find.byType(OckerGlass)));
    expect(rule.left, moreOrLessEquals(card.left + inset, epsilon: 1));
    expect(rule.right, moreOrLessEquals(card.right - inset, epsilon: 1));
    expect(
      tester.getRect(director).top,
      greaterThan(tester.getRect(find.text('Kurz.')).bottom + 100),
      reason: 'below the room the synopsis leaves, not straight under it',
    );
  });

  testWidgets('glas: a row without credits ends with its synopsis', (tester) async {
    final bare = testMediaItem(id: 'bare', title: 'Ohne', summary: 'Nur das.');
    final films = MediaHub(id: 'filme', title: 'Filme', type: 'movie', items: [bare]);
    bus.report(OckerFocused(item: bare, hub: films, index: 0));
    await pumpPanel(tester, variant: AppThemeVariant.glas);

    expect(
      find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains(t.discover.cast)),
      findsNothing,
    );
    expect(find.byKey(glassCreditsRuleKey), findsNothing, reason: 'no rule over nothing');
  });

  testWidgets('glas: the facts lie on capsules of glass, without bullets between', (tester) async {
    final film = testMediaItem(id: 'fakten', title: 'Fakten', summary: 'Kurz.', year: 2002, durationMs: 7740000);
    final films = MediaHub(id: 'filme', title: 'Filme', type: 'movie', items: [film]);
    bus.report(OckerFocused(item: film, hub: films, index: 0));
    await pumpPanel(tester, variant: AppThemeVariant.glas);

    expect(find.ancestor(of: find.text('2002'), matching: find.byType(OckerGlassPlate)), findsOneWidget);
    expect(
      tester.widget<OckerGlassPlate>(find.ancestor(of: find.text('2002'), matching: find.byType(OckerGlassPlate))).firm,
      isFalse,
      reason: 'the band\'s glass, not a button\'s firmer one',
    );
    expect(find.textContaining('•'), findsNothing);
  });

  testWidgets('glas: the facts follow the detail page\'s order', (tester) async {
    const film = MediaItem.plex(
      id: 'folge',
      kind: MediaKind.movie,
      title: 'Folge',
      summary: 'Kurz.',
      year: 2002,
      contentRating: 'PG-13',
      durationMs: 7740000,
      editionTitle: 'Extended',
    );
    final films = MediaHub(id: 'filme', title: 'Filme', type: 'movie', items: const [film]);
    bus.report(OckerFocused(item: film, hub: films, index: 0));
    await pumpPanel(tester, variant: AppThemeVariant.glas);

    // The card is narrow and sheds its least important facts first; whatever
    // it keeps stands in this order.
    final order = ['2002', t.discover.movie, formatContentRating('PG-13'), formatDurationTextual(7740000), 'Extended'];
    final shown = [
      for (final text in order)
        if (find.text(text).evaluate().isNotEmpty) text,
    ];
    expect(shown, containsAllInOrder(['2002', formatContentRating('PG-13'), formatDurationTextual(7740000)]));
    final lefts = [for (final text in shown) tester.getRect(find.text(text)).left];
    expect(lefts, [...lefts]..sort(), reason: 'year, kind, age, length, edition');
  });

  testWidgets('glas: the genres each stand on a chip of their own', (tester) async {
    const film = MediaItem.plex(
      id: 'genres',
      kind: MediaKind.movie,
      title: 'Genres',
      summary: 'Kurz.',
      genres: ['Drama', 'Krimi'],
    );
    final films = MediaHub(id: 'filme', title: 'Filme', type: 'movie', items: const [film]);
    bus.report(OckerFocused(item: film, hub: films, index: 0));
    await pumpPanel(tester, variant: AppThemeVariant.glas);

    expect(find.ancestor(of: find.text('Drama'), matching: find.byType(OckerGlassPlate)), findsOneWidget);
    expect(find.ancestor(of: find.text('Krimi'), matching: find.byType(OckerGlassPlate)), findsOneWidget);
    expect(find.text('Drama, Krimi'), findsNothing);
  });

  testWidgets('draws nothing that looks like a control', (tester) async {
    bus.report(OckerFocused(item: hub.items.first, hub: hub, index: 0));
    await pumpPanel(tester);

    // The panel described the two keys at its foot for as long as it had them:
    // OK to open, held OK for the options. They went because they are the two
    // gestures every other screen in the app already uses, printed under every
    // title on three pages — a caption that told a returning viewer nothing
    // and spent the room the description needed.
    expect(find.text('OK'), findsNothing);
    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
  });

  group('the settle delay', () {
    test('publishes the first report at once — there is nothing to fade from', () {
      final fresh = OckerFocusBus();
      addTearDown(fresh.dispose);

      fresh.report(OckerFocused(item: hub.items.first, hub: hub, index: 0));

      expect(fresh.value?.index, 0);
    });

    testWidgets('swallows a fast run and publishes only where it stopped', (tester) async {
      final fresh = OckerFocusBus();
      addTearDown(fresh.dispose);
      fresh.report(OckerFocused(item: hub.items[0], hub: hub, index: 0));

      // Holding RIGHT walks the row at the key-repeat rate. The panel must not
      // swap its still, title and background at every step on the way.
      for (var i = 1; i < 6; i++) {
        fresh.report(OckerFocused(item: hub.items[i], hub: hub, index: i));
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(fresh.value?.index, 0, reason: 'still showing where the run started');

      await tester.pump(OckerFocusBus.settleDelay);
      expect(fresh.value?.index, 5, reason: 'and now where it stopped, in one step');
    });
  });
}
