import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/services/settings_service.dart' show AppThemeVariant, GlasAccent;
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/theme/mono_tokens.dart';
import 'package:plezy/widgets/catalog_tile_cards.dart';

/// Under glass the page's ground is a gradient that lifts and glows. A tile
/// painted in the opaque surface colour sat on it as a flat patch, darker than
/// the light around it — the "dark area behind" reported again and again.
void main() {
  MonoTokens tokensOf(AppThemeVariant variant, {GlasAccent accent = GlasAccent.eisblau}) =>
      monoTheme(dark: true, variant: variant, glasAccent: accent).extension<MonoTokens>()!;

  test('under glass a tile is an ink wash, see-through, in every palette', () {
    for (final accent in GlasAccent.values) {
      final tk = tokensOf(AppThemeVariant.glas, accent: accent);
      expect(tk.tileFill, tk.ink(0.06), reason: accent.name);
      expect(tk.tileFill.a, lessThan(1), reason: accent.name);
    }
  });

  test('the original look keeps its opaque surface', () {
    final tk = tokensOf(AppThemeVariant.standard);
    expect(tk.tileFill, tk.surface);
  });

  test('a card under glass is a wash too, and stays opaque elsewhere', () {
    expect(monoTheme(dark: true, variant: AppThemeVariant.glas).cardTheme.color!.a, lessThan(1));
    expect(monoTheme(dark: true).cardTheme.color!.a, 1);
  });

  testWidgets('the genre and studio tiles paint the wash under glass', (tester) async {
    final item = MediaItem(id: 'g', backend: MediaBackend.plex, kind: MediaKind.unknown, title: 'Komödie');
    for (final variant in AppThemeVariant.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: true, variant: variant),
          home: Scaffold(
            body: Column(
              children: [
                ChipTileCard(item: item, width: 200, height: 60),
                BrandTileCard(item: item, width: 200, height: 100),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final tk = tokensOf(variant);
      final fills = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .map((decoration) => decoration.color)
          .toList();
      expect(fills.where((color) => color == tk.tileFill), hasLength(2), reason: variant.name);
    }
  });
}
