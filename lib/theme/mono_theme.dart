import 'dart:io' show Platform;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../services/settings_service.dart' show AppThemeVariant, GlasAccent;
import '../utils/platform_detector.dart';
import '../widgets/app_icon.dart';
import 'apple_type.dart';
import 'gapped_track_shape.dart';
import 'glass_backdrop.dart';
import 'mono_tokens.dart';

/// The Inter asset (`assets/fonts/Inter-Variable.ttf`) is the redesign's.
/// Inter sets about 4% wider than Roboto, and the lines that measure
/// themselves before they draw — the detail hero's facts row, the spotlight,
/// the pre-play track summary — spend that difference by dropping a field at
/// 1280x720; that is why the standard theme keeps the platform's face.

/// **The redesign is set in one typeface: Inter** (SF Pro on Apple, below).
/// Both palettes, every line.
///
/// It used to be three, one job each — a serif for content titles, a grotesque
/// for the interface, a monospace for every label, counter and timecode. The
/// serif stopped being drawn first (a bare title read as a placeholder beside
/// a film's own logo); the other two went on the viewer's own call, because a
/// collection of faces is only a system while somebody is enforcing it, and
/// one face with nine weights says the same things by weight.
///
/// Three names remain rather than one, and deliberately:
///
/// - [MonoTokens.displayFontFamily] is the **gate** every branch in
///   `lib/redesign/` asks (`isOcker`). Only the redesign palettes fill it, so
///   what the value *is* never mattered — that it is non-null does.
/// - [MonoTokens.monoFontFamily] still marks the lines that are counters
///   rather than sentences. They no longer change face, but they keep their
///   tabular figures, which is the part that earns its keep: a year or a
///   timecode must not shift the line as it ticks. See `monoFacts`.
/// - The `ocker` prefix is the fork's own marker. Every name this fork adds
///   carries one, so a single grep after an upstream merge proves nothing was
///   lost.
///
/// Inter is a variable font, so a weight is an axis position rather than a
/// separate file: every step from 100 to 900 is available and none of them is
/// synthesised.
///
/// **On Apple's devices the face is the system's own, SF Pro** (the user's
/// call, 2026-10-13): Apple TV, the Mac, and iPhone and iPad once there is a
/// build for them. SF Pro may not be shipped inside an app — that is why Inter
/// came — but there it is already on the device, and the app only names it.
/// Inter came from the same thinking, so the sizes hold; SF Pro runs a touch
/// narrower, which only gives lines room.
///
/// Each style then takes the cut and the spacing Apple gives its size
/// ([appleSystemType]): the redesign's styles in `OckerType`, the theme's own
/// below.
String get ockerDisplayFontFamily => ockerAppleSystemFont ? appleSystemDisplayFamily : 'Inter';
String get ockerUiFontFamily => ockerAppleSystemFont ? appleSystemTextFamily : 'Inter';
String get ockerMonoFontFamily => ockerAppleSystemFont ? appleSystemTextFamily : 'Inter';

/// What one logical pixel is in Apple's points, for sizing type the way Apple
/// does: 2 on the Apple TV, which draws a half-size surface scaled up (see
/// `FormFactorScale`), 1 everywhere else.
double get ockerApplePointsPerPixel => PlatformDetector.isAppleTV() ? 2 : 1;

/// Whether the redesigns are set in the Apple system face (see above). Not
/// under `flutter test`, which runs on a Mac but measures with Inter.
bool get ockerAppleSystemFont => debugOckerAppleSystemFont ?? _appleSystemFontHere;

/// Whether Glas wears what is Apple's alone (Plebz): the system face set by
/// size and Apple's glyphs for Back, More and Share. The rest of what Glas
/// took from Apple's apps it wears on every device (the user's call,
/// 2026-10-13; see `ocker_glas_look.dart`). The Apple builds alone, where
/// SF Pro is; the APK never.
bool get ockerAppleLook => ockerAppleSystemFont;

final bool _appleSystemFontHere =
    !kIsWeb && (Platform.isIOS || Platform.isMacOS) && !Platform.environment.containsKey('FLUTTER_TEST');

@visibleForTesting
bool? debugOckerAppleSystemFont;

/// The redesign's one corner for everything the interface draws — the tokens'
/// radiusSm, and also every shape
/// the theme hands out.
const double _redesignCorner = 14;

/// "Redesign – Glas" in the palette its accent names: a ground and an ink
/// faintly of the accent's own hue, so a choice of accent is a choice of
/// palette and never a red stripe on a blue night.
///
/// The accent keeps the redesign's three jobs and no fourth.
({Color bg, Color text, Color accent}) glasPalette(GlasAccent accent) => switch (accent) {
  GlasAccent.eisblau => (bg: const Color(0xFF0F131A), text: const Color(0xFFE8EEF5), accent: const Color(0xFF8DB9DE)),
  GlasAccent.mint => (bg: const Color(0xFF0C1716), text: const Color(0xFFE4F0EC), accent: const Color(0xFF5CC2A5)),
  GlasAccent.flieder => (bg: const Color(0xFF16111B), text: const Color(0xFFF0E9F4), accent: const Color(0xFFC39BDB)),
  // No hue anywhere: the dark grey Apple TV stands its menus on, a white ink,
  // and Apple's own system grey where the others put a colour.
  GlasAccent.grau => (bg: const Color(0xFF1A1A1C), text: const Color(0xFFF2F2F4), accent: const Color(0xFF98989D)),
  // After Netflix: its black, a plain white, and its red. The one palette
  // whose ground and ink stay out of the accent's hue — black, white and red
  // is the whole of the look.
  GlasAccent.rot => (bg: const Color(0xFF141414), text: const Color(0xFFFFFFFF), accent: const Color(0xFFE50914)),
  // After the logo (Plebz): a near-black with the faintest violet, a
  // lavender-white ink, the logo's middle violet as the accent — and its whole
  // gradient on the play buttons, see [plebzGradient].
  GlasAccent.plebz => (bg: const Color(0xFF08070C), text: const Color(0xFFF3EFFA), accent: const Color(0xFFA866EE)),
};

/// The logo's gradient, violet to pink (Plebz). Under the Plebz palette the
/// play buttons wear it; nothing else does, so it keeps meaning "play".
const plebzGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF7356F5), Color(0xFFA866EE), Color(0xFFEE8BD2)],
  stops: [0, 0.55, 1],
);

/// The redesign's ground with the OLED choice on: black, and nothing on it —
/// no lift, no glow — so an OLED panel's pixels stay off. No palette's own
/// ground is this, which is how the backdrop tells the two apart.
const glasOledGround = Color(0xFF000000);

/// The redesigns' ground with the off-black choice on
/// ([PlebzPrefs.redesignOffBlack]): the dark grey Material calls its
/// dark surface, softer than black, and as plain — no lift, no glow. No
/// palette's own ground is this either.
const redesignOffBlackGround = Color(0xFF121212);

/// How light a ground of the viewer's own colour may be, as an HSV value: the
/// redesigns' ink stays light, and over a lighter ground it stops reading.
const redesignGroundMaxValue = 0.35;

/// A ground of the viewer's own colour ([PlebzPrefs.redesignGroundColour]),
/// taken down to [redesignGroundMaxValue] where it is lighter; off-black for
/// anything that does not read as `#RRGGBB`.
Color redesignGroundFromHex(String hex) {
  final digits = hex.replaceFirst('#', '');
  final value = digits.length == 6 ? int.tryParse(digits, radix: 16) : null;
  if (value == null) return redesignOffBlackGround;
  final hsv = HSVColor.fromColor(Color(0xFF000000 | value));
  return hsv.value <= redesignGroundMaxValue ? hsv.toColor() : hsv.withValue(redesignGroundMaxValue).toColor();
}

/// How much of its accent a palette spends on the chosen capsule.
///
/// Only red differs. The faint wash that marks it in the others reads as
/// maroon over black, so red spends most of its red there — not all of it:
/// the pane stays glass, the ground a little through it.
double glasAccentWash(GlasAccent accent) => accent == GlasAccent.rot ? 0.7 : 0.22;

/// Whether this variant is the redesign, in either of its palettes.
///
/// The distinction the whole fork turns on: **structure** is shared and
/// **colour** is not. Squareness, the three typefaces, the header navigation,
/// the hairline focus ring, the absence of shadows — all of that belongs to
/// the redesign and answers here. Which ground and which accent is a separate
/// question with a separate switch.
bool isRedesignVariant(AppThemeVariant variant) => variant == AppThemeVariant.glas || variant == AppThemeVariant.flach;

/// "Redesign – Flach"'s ground and ink (Plebz): the design's near-black with a
/// trace of violet, an all but neutral white the viewer chose, the accent the
/// viewer's own.
const flachGround = Color(0xFF08070C);
const flachInk = Color(0xFFF9FAFB);
const flachDefaultAccent = Color(0xFFA866EE);

/// [PlebzPrefs.flachAccent]'s `#RRGGBB` as a colour; the default violet
/// for anything that does not read as one.
Color flachAccentFromHex(String hex) {
  final digits = hex.replaceFirst('#', '');
  final value = digits.length == 6 ? int.tryParse(digits, radix: 16) : null;
  return value == null ? flachDefaultAccent : Color(0xFF000000 | value);
}

/// A ready-made "Flach" look (Plebz): an accent and the ground it was picked
/// for, chosen together in one step — the viewer's wish, for those who would
/// rather not mix their own. Every ground is an off-black tinted towards its
/// accent, never black (OLED stays its own choice and wins over a ground).
class FlachPreset {
  const FlachPreset(this.id, {required this.accent, required this.ground});

  /// What [PlebzPrefs.flachPreset] stores.
  final String id;
  final Color accent;
  final Color ground;
}

/// The looks on offer, the design's own first.
const flachPresets = <FlachPreset>[
  FlachPreset('standard', accent: flachDefaultAccent, ground: flachGround),
  FlachPreset('nordlicht', accent: Color(0xFF2DD4BF), ground: Color(0xFF0A1417)),
  FlachPreset('glut', accent: Color(0xFFFF7A45), ground: Color(0xFF15100D)),
  FlachPreset('mitternacht', accent: Color(0xFF6E8BFF), ground: Color(0xFF0A0D18)),
  FlachPreset('kirschbluete', accent: Color(0xFFFF5C8A), ground: Color(0xFF150A10)),
  FlachPreset('amethyst', accent: Color(0xFFA78BFA), ground: Color(0xFF120D1C)),
  FlachPreset('bernstein', accent: Color(0xFFF2B544), ground: Color(0xFF12100B)),
  FlachPreset('safran', accent: Color(0xFFE5A00D), ground: Color(0xFF1F2326)),
  FlachPreset('kino', accent: Color(0xFFE50914), ground: Color(0xFF141414)),
];

/// The look [id] names, or null for the viewer's own colours.
FlachPreset? flachPresetById(String id) {
  for (final preset in flachPresets) {
    if (preset.id == id) return preset;
  }
  return null;
}

/// Whether [ground] is one of the looks' own grounds, which carry the
/// accent's lights as the design's own ground does.
bool isFlachPresetGround(Color ground) => flachPresets.any((preset) => preset.ground == ground);

/// One of the six colours a [MonoPalette] holds. [id] is the key the custom
/// theme persists the colour under.
enum MonoPaletteSlot {
  bg('bg'),
  surface('surface'),
  outline('outline'),
  text('text'),
  textMuted('textMuted'),
  accent('accent');

  const MonoPaletteSlot(this.id);

  final String id;
}

/// [color] as `#AARRGGBB`, upper case.
String colorToArgbHex(Color color) => '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

final _hexColorPattern = RegExp(r'^#?([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$');

/// Parses `#RRGGBB` (opaque) or `#AARRGGBB`, with or without the `#`. Null
/// for anything else.
Color? tryParseHexColor(String input) {
  final match = _hexColorPattern.firstMatch(input.trim());
  if (match == null) return null;
  final digits = match.group(1)!;
  final value = int.parse(digits, radix: 16);
  return Color(digits.length == 6 ? 0xFF000000 | value : value);
}

/// The six colours a theme is built from.
///
/// [accent] carries interactive and selected state; body text stays [text].
/// Brightness follows [bg] and the colour drawn on [accent] is derived, so a
/// palette states nothing else.
@immutable
class MonoPalette {
  const MonoPalette({
    required this.bg,
    required this.surface,
    required this.outline,
    required this.text,
    required this.textMuted,
    required this.accent,
  });

  final Color bg;
  final Color surface;
  final Color outline;
  final Color text;
  final Color textMuted;

  /// Primary, filled buttons, switches, sliders, progress, selection and the
  /// focus ring. The built-ins set it to [text], which keeps them monochrome.
  final Color accent;

  // Neutral greys tuned for crisp contrast.
  static const light = MonoPalette(
    bg: Color(0xFFF7F7F8),
    surface: Color(0xFFFFFFFF),
    outline: Color(0x19000000),
    text: Color(0xFF111111),
    textMuted: Color(0x99111111),
    accent: Color(0xFF111111),
  );
  static const dark = MonoPalette(
    bg: Color(0xFF0E0F12),
    surface: Color(0xFF15171C),
    outline: Color(0x1FFFFFFF),
    text: Color(0xFFEDEDED),
    textMuted: Color(0x99EDEDED),
    accent: Color(0xFFEDEDED),
  );
  static const oled = MonoPalette(
    bg: Color(0xFF000000), // Pure black for OLED
    surface: Color(0xFF0A0A0A),
    outline: Color(0x1FFFFFFF),
    text: Color(0xFFEDEDED),
    textMuted: Color(0x99EDEDED),
    accent: Color(0xFFEDEDED),
  );

  // Presets keep bg/surface low-chroma so artwork stays the loudest thing on
  // screen; the character is in the tint and the accent. Every accent clears
  // 4.5:1 against bg and surface, because primary is also used as text.

  /// Warm charcoal with the brand orange.
  static const ember = MonoPalette(
    bg: Color(0xFF14110F),
    surface: Color(0xFF1D1916),
    outline: Color(0x1FF2EBE6),
    text: Color(0xFFF2EBE6),
    textMuted: Color(0xA3F2EBE6),
    accent: Color(0xFFFF7E57),
  );

  /// Cool blue-grey with an ice-blue accent.
  static const glacier = MonoPalette(
    bg: Color(0xFF0E1319),
    surface: Color(0xFF151C25),
    outline: Color(0x1FE6EDF5),
    text: Color(0xFFE6EDF5),
    textMuted: Color(0xA3E6EDF5),
    accent: Color(0xFF7CC4FF),
  );

  /// Green-black with a mint accent.
  static const forest = MonoPalette(
    bg: Color(0xFF0E1411),
    surface: Color(0xFF151D18),
    outline: Color(0x1FE5EFE8),
    text: Color(0xFFE5EFE8),
    textMuted: Color(0xA3E5EFE8),
    accent: Color(0xFF6BD6A0),
  );

  /// Aubergine with an orchid accent.
  static const plum = MonoPalette(
    bg: Color(0xFF151118),
    surface: Color(0xFF1E1823),
    outline: Color(0x1FF0E9F4),
    text: Color(0xFFF0E9F4),
    textMuted: Color(0xA3F0E9F4),
    accent: Color(0xFFE29BF0),
  );

  /// Warm off-white paper with a deep teal accent; the light preset.
  static const paper = MonoPalette(
    bg: Color(0xFFF3F0E9),
    surface: Color(0xFFFBF9F4),
    outline: Color(0x1F1F1C17),
    text: Color(0xFF1F1C17),
    textMuted: Color(0xAD1F1C17),
    accent: Color(0xFF1F6B6B),
  );

  Brightness get brightness => ThemeData.estimateBrightnessForColor(bg);

  /// [bg] or white, whichever contrasts more with [accent]. The pair is never
  /// worse than [accent] against [bg], so an accent that reads on the page
  /// keeps a readable label.
  Color get onAccent {
    const white = Color(0xFFFFFFFF);
    final accentLuminance = accent.computeLuminance();
    return _contrastRatio(accentLuminance, bg.computeLuminance()) >=
            _contrastRatio(accentLuminance, white.computeLuminance())
        ? bg
        : white;
  }

  static double _contrastRatio(double a, double b) => (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);

  /// WCAG 2 contrast ratio between two colours, ignoring alpha: composite a
  /// translucent colour over its background first.
  static double contrastRatio(Color a, Color b) => _contrastRatio(a.computeLuminance(), b.computeLuminance());

  Color operator [](MonoPaletteSlot slot) => switch (slot) {
    MonoPaletteSlot.bg => bg,
    MonoPaletteSlot.surface => surface,
    MonoPaletteSlot.outline => outline,
    MonoPaletteSlot.text => text,
    MonoPaletteSlot.textMuted => textMuted,
    MonoPaletteSlot.accent => accent,
  };

  /// This palette with [slot] replaced by [color].
  MonoPalette withColor(MonoPaletteSlot slot, Color color) => MonoPalette(
    bg: slot == MonoPaletteSlot.bg ? color : bg,
    surface: slot == MonoPaletteSlot.surface ? color : surface,
    outline: slot == MonoPaletteSlot.outline ? color : outline,
    text: slot == MonoPaletteSlot.text ? color : text,
    textMuted: slot == MonoPaletteSlot.textMuted ? color : textMuted,
    accent: slot == MonoPaletteSlot.accent ? color : accent,
  );

  /// `{"bg": "#AARRGGBB", …}`, keyed by [MonoPaletteSlot.id].
  Map<String, String> toJson() => {for (final slot in MonoPaletteSlot.values) slot.id: colorToArgbHex(this[slot])};

  /// Reads the [toJson] shape. Throws [FormatException] unless every slot
  /// holds a hex colour, so a partial or corrupt value never yields a palette
  /// mixing stored and made-up colours. Unknown keys are ignored.
  factory MonoPalette.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('Expected a palette object');
    Color read(MonoPaletteSlot slot) {
      final value = json[slot.id];
      final color = value is String ? tryParseHexColor(value) : null;
      if (color == null) throw FormatException('Missing or invalid "${slot.id}" colour');
      return color;
    }

    return MonoPalette(
      bg: read(MonoPaletteSlot.bg),
      surface: read(MonoPaletteSlot.surface),
      outline: read(MonoPaletteSlot.outline),
      text: read(MonoPaletteSlot.text),
      textMuted: read(MonoPaletteSlot.textMuted),
      accent: read(MonoPaletteSlot.accent),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MonoPalette &&
      other.bg == bg &&
      other.surface == surface &&
      other.outline == outline &&
      other.text == text &&
      other.textMuted == textMuted &&
      other.accent == accent;

  @override
  int get hashCode => Object.hash(bg, surface, outline, text, textMuted, accent);
}

bool? _debugRedesignOffered;

/// Whether this host offers the redesign at all.
///
/// Every host does. Where the rearranged screens would be the wrong
/// instrument — a phone or tablet held in the hand, a Mac window driven by a
/// mouse — it is the look alone: the glass, the chips, the sheets and menus,
/// but none of the rearranging, which is laid out for a television and gated
/// separately — see `isOckerLayout` and `ockerLookOnly`.
///
/// The gate stays so a host can be left out again without hunting for every
/// place that reads the variant — see [offeredAppThemeVariants] and
/// [supportedAppThemeVariant].
bool get redesignOfferedHere => _debugRedesignOffered ?? true;

/// Pretend the host does or does not offer the redesign.
///
/// For the suites that check what a host without it would do. Pass null to
/// restore the real answer; suites that set it must reset it.
@visibleForTesting
set debugRedesignOfferedHere(bool? offered) => _debugRedesignOffered = offered;

/// The variants that can be chosen here, in the order they are shown.
List<AppThemeVariant> get offeredAppThemeVariants => [
  for (final variant in AppThemeVariant.values)
    if (redesignOfferedHere || !isRedesignVariant(variant)) variant,
];

/// [variant] as this host can actually draw it.
///
/// A redesign palette can reach a Mac without ever having been chosen there —
/// a restored backup, a copied preference file — and would otherwise paint a
/// television interface into a window. It reads back as
/// [AppThemeVariant.standard]. The *stored* value is left alone on purpose:
/// the same profile still opens in the redesign on the television it was set
/// from.
AppThemeVariant supportedAppThemeVariant(AppThemeVariant variant) =>
    isRedesignVariant(variant) && !redesignOfferedHere ? AppThemeVariant.standard : variant;

final Map<
  ({
    MonoPalette palette,
    Color? plainGround,
    TargetPlatform platform,
    AppThemeVariant variant,
    GlasAccent? glasAccent,
    Color? flachAccent,
    bool appleSystemFont,
  }),
  ThemeData
>
_monoThemeCache = {};

ThemeData monoTheme(
  MonoPalette palette, {
  Color? plainGround,
  AppThemeVariant variant = AppThemeVariant.standard,
  GlasAccent glasAccent = GlasAccent.eisblau,
  Color flachAccent = flachDefaultAccent,
}) {
  // ThemeData derives several defaults from defaultTargetPlatform. The variant
  // is part of the key too: the redesign is a different theme, not a tint of
  // one. The glass accent only where it paints anything, so the other variants are
  // built once rather than once per accent.
  final key = (
    palette: palette,
    // Only where it paints anything: the redesigns, and not over OLED's black.
    plainGround: palette == MonoPalette.oled || !isRedesignVariant(variant) ? null : plainGround,
    platform: defaultTargetPlatform,
    variant: variant,
    glasAccent: variant == AppThemeVariant.glas ? glasAccent : null,
    flachAccent: variant == AppThemeVariant.flach ? flachAccent : null,
    // Fixed for a host; a key only so a test can switch it.
    appleSystemFont: isRedesignVariant(variant) && ockerAppleSystemFont,
  );
  final cached = _monoThemeCache[key];
  if (cached != null) return cached;

  final theme = _buildMonoTheme(
    palette,
    platform: key.platform,
    plainGround: key.plainGround,
    variant: key.variant,
    glasAccent: glasAccent,
    flachAccent: flachAccent,
  );
  _monoThemeCache[key] = theme;
  return theme;
}

/// [monoTheme] without the cache, for a palette that changes every frame: the
/// custom theme editor's live preview would otherwise keep every intermediate
/// palette's theme alive.
ThemeData monoThemeUncached(MonoPalette palette) => _buildMonoTheme(palette, platform: defaultTargetPlatform);

ThemeData _buildMonoTheme(
  MonoPalette palette, {
  required TargetPlatform platform,
  Color? plainGround,
  AppThemeVariant variant = AppThemeVariant.standard,
  GlasAccent glasAccent = GlasAccent.eisblau,
  Color flachAccent = flachDefaultAccent,
}) {
  // Which structure to build, and which of its two palettes to paint it in.
  // Its corner, its typeface and its want of shadows follow from the first;
  // only colour follows from the second.
  final redesign = isRedesignVariant(variant);
  final flat = variant == AppThemeVariant.flach;
  final glas = flat ? (bg: flachGround, text: flachInk, accent: flachAccent) : glasPalette(glasAccent);

  final MonoPalette c;
  if (redesign) {
    // **The redesign is a dark design and stays dark.** Its styleguide gives
    // one ground and one ink per palette and says outright that a value not in
    // it should not appear in the UI; a light counterpart would have to be
    // invented rather than read off. So the light/dark switch does not reach
    // it. OLED does, as one other ground: black in place of the palette's
    // own, the ink and the accent untouched — and a plain colour, off-black or
    // the viewer's own (see [ThemeProvider]).
    //
    // `surface` is the design's block fill (ink at 6%) already composited over
    // the ground, because Flutter surfaces are painted opaque.
    final ground = palette == MonoPalette.oled ? glasOledGround : plainGround ?? glas.bg;
    c = MonoPalette(
      bg: ground,
      // The block fill composited over the ground.
      surface: Color.alphaBlend(glas.text.withValues(alpha: 0.06), ground),
      outline: glas.text.withValues(alpha: 0.12),
      text: glas.text,
      textMuted: glas.text.withValues(alpha: 0.72),
      // Material's primary stays the ink; the loud accent is the tokens' own.
      accent: glas.text,
    );
  } else {
    c = palette;
  }

  // The redesign has no light half — see the palette above — so it reports
  // dark whatever the light/dark switch says, and every Material default that
  // branches on brightness lands on the side its colours were drawn for.
  final brightness = redesign ? Brightness.dark : c.brightness;
  final isDark = brightness == Brightness.dark;
  final onAccent = redesign ? c.bg : c.onAccent;
  final clickableCursor = WidgetStateProperty.resolveWith<MouseCursor>(
    (states) => states.contains(WidgetState.disabled) ? MouseCursor.defer : SystemMouseCursors.click,
  );

  // Corner radius for every shape the theme itself hands out.
  //
  // The redesign started square throughout and handed out 0 here. Its own
  // boxes have carried a small corner since ([_redesignCorner], the tokens'
  // radiusSm below): panels, cards, the detail page's buttons. What the theme
  // handed out stayed square — every FilledButton, Card, text field and
  // snackbar — and what it handed out nothing for fell to Material's 28:
  // every dialog. Three corners on one screen, a round dialog holding square
  // buttons. They are one corner now.
  final themeRadius = redesign ? _redesignCorner : 12.0;
  final themeShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(themeRadius));

  // Disabled buttons use the Material disabled opacities over the text colour;
  // a flat colour for every state made them look pressable.
  final buttonStyle = ButtonStyle(
    mouseCursor: clickableCursor,
    padding: WidgetStatePropertyAll(
      // The design's primary button: taller, and heavier on the side away
      // from its leading play triangle.
      redesign ? const EdgeInsets.fromLTRB(24, 15, 30, 15) : const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    ),
    elevation: const WidgetStatePropertyAll(0),
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled) ? c.text.withValues(alpha: 0.12) : c.accent,
    ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled) ? c.text.withValues(alpha: 0.38) : onAccent,
    ),
    shape: WidgetStatePropertyAll(redesign ? themeShape : const StadiumBorder()),
  );
  // The quieter buttons keep Material's shape outside the redesign; inside it
  // they take the one corner, which shows wherever focus fills them.
  final quietButtonStyle = ButtonStyle(
    mouseCursor: clickableCursor,
    shape: redesign ? WidgetStatePropertyAll(themeShape) : null,
  );

  final base = ThemeData(
    platform: platform,
    useMaterial3: true,
    // One line reaches every unstyled piece of text in the app. Titles and
    // labels are lifted out of it deliberately, widget by widget.
    fontFamily: redesign ? ockerUiFontFamily : null,
    brightness: brightness,
    // Linux resolves UI text through fontconfig, which on a minimal desktop
    // may have no CJK font at all; the bundled subtitle fonts (pubspec
    // `fonts:`) cover it. Other platforms keep their native CJK fonts.
    fontFamilyFallback: platform == TargetPlatform.linux ? const ['Go Noto Current', 'Go Noto Current Hangul'] : null,
    colorScheme: ColorScheme(
      brightness: brightness,
      // Accent: everything Material derives from primary (switches, sliders,
      // progress, checkboxes, text selection, text buttons, selected list
      // tiles) plus the widgets that read primary for selection and focus.
      primary: c.accent,
      onPrimary: onAccent,
      // Elevation tint stays on the neutral text colour so dialogs and menus
      // keep the palette's surfaces rather than picking up the accent hue.
      surfaceTint: c.text,
      secondary: c.text,
      onSecondary: c.bg,
      surface: c.surface,
      onSurface: c.text,
      // Outside the palette there is no colour in the redesign — its styleguide
      // says so — and Material's crimson was the one that got through, on
      // every "connection lost". An error there is said in the ink, by its icon
      // and its words; the accent keeps its three jobs.
      error: redesign ? c.text : const Color(0xFFB00020),
      // On the ink the words take the ground, as on every other ink button:
      // white on it was white on white ("Abmelden" under glass).
      onError: redesign ? (isDark ? c.bg : Colors.white) : Colors.white,
      tertiary: c.text,
      onTertiary: c.bg,
      primaryContainer: c.surface,
      onPrimaryContainer: c.text,
      secondaryContainer: c.surface,
      onSecondaryContainer: c.text,
      surfaceContainerHighest: c.surface,
      surfaceContainerLow: c.bg,
      surfaceDim: c.bg,
      surfaceBright: c.surface,
      outline: c.outline,
      shadow: Colors.transparent,
      scrim: Colors.black,
      inverseSurface: c.text,
      onInverseSurface: c.bg,
      inversePrimary: c.bg,
    ),
    // remove "Material feel"
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    // Explicit mono-derived tile highlights: ListTile's native focus/hover
    // fill is the dpad focus visual inside M3E grouped-list cards.
    focusColor: c.text.withValues(alpha: 0.12),
    hoverColor: c.text.withValues(alpha: 0.05),
    dividerColor: c.outline,
    // Under glass the pages carry a gradient ground rather than a colour — see
    // [glassPageTransitionsTheme] — so the scaffold and the app bar let it show.
    //
    // Clear, but clear *ground*, not clear black: the scrims all over the app
    // are this colour given some opacity back — a backdrop fading into the
    // page, a row fading into the foot — and `Colors.transparent` given 0.86
    // of opacity is black. The home screen's hero went to black at the left
    // and the foot, where it should fade into the palette's ground.
    scaffoldBackgroundColor: redesign ? c.bg.withValues(alpha: 0) : c.bg,
    pageTransitionsTheme: redesign ? glassPageTransitionsTheme : null,
    appBarTheme: AppBarTheme(
      backgroundColor: redesign ? redesignBarColor(c.bg) : c.bg,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      foregroundColor: c.text,
      titleTextStyle: TextStyle(color: c.text, fontSize: 18, fontWeight: .w700, letterSpacing: -0.2),
    ),
    // The display sizes are where a *title* is set: the hero on the catalog,
    // the name at the top of a detail page. Under "Ocker" that is the serif's
    // whole job, and putting it in the theme rather than in each screen is
    // what gives the variant on the app's own layout the same titles as the
    // rearranged one, without either knowing about the other.
    //
    // Display only, never headline: a headline in this app belongs to a
    // dialog, a settings page or a sign-in screen, and those are interface —
    // which the serif must not set, or the distinction it exists to draw stops
    // meaning anything.
    //
    // displayLarge is written fresh because it always was, and the entry it
    // replaces carries no size either — changing that would resize it under
    // every variant. The two below are merged onto the scale instead, since
    // nothing replaced them before and a literal would silently drop the size
    // Material gives them.
    textTheme:
        _redesignDisplayFaces(
              Typography.englishLike2021.apply(bodyColor: c.text, displayColor: c.text),
              redesign: redesign,
            )
            .copyWith(
              displayLarge: redesign
                  // Tighter than the other variants: the redesign sets its titles
                  // large, and Inter at that size needs the space taken back.
                  ? const TextStyle(fontWeight: .w700, letterSpacing: -1, height: 1.05)
                  : const TextStyle(fontWeight: .w700, letterSpacing: -0.5),
              titleMedium: const TextStyle(fontWeight: .w600),
              bodyMedium: TextStyle(color: c.text),
              bodySmall: TextStyle(color: c.textMuted),
            )
            // The redesign's face on every style here, not only through
            // [ThemeData.fontFamily]: that is laid onto Material's defaults, which
            // are then merged with these — and the geometry scale's styles do not
            // inherit, so the merge dropped the family and every list title,
            // setting and dialog fell back to the platform's face.
            .apply(fontFamily: redesign ? ockerUiFontFamily : null),
    cardTheme: CardThemeData(
      // Under glass a card is an ink wash over the page's gradient, not an
      // opaque patch of the flat ground (see `MonoTokens.tileFill`).
      color: redesign ? c.text.withValues(alpha: 0.06) : c.surface,
      elevation: 0,
      margin: .zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(redesign ? themeRadius : 14)),
    ),
    // Only the redesign sets these; the other variants keep Material's.
    dialogTheme: redesign ? DialogThemeData(backgroundColor: c.surface, elevation: 0, shape: themeShape) : null,
    popupMenuTheme: redesign ? PopupMenuThemeData(color: c.surface, elevation: 0, shape: themeShape) : null,
    inputDecorationTheme: _inputDecorationTheme(c.text, c.textMuted, themeRadius),
    elevatedButtonTheme: ElevatedButtonThemeData(style: buttonStyle),
    filledButtonTheme: FilledButtonThemeData(style: buttonStyle),
    textButtonTheme: TextButtonThemeData(style: quietButtonStyle),
    outlinedButtonTheme: OutlinedButtonThemeData(style: quietButtonStyle),
    iconButtonTheme: IconButtonThemeData(style: ButtonStyle(mouseCursor: clickableCursor)),
    sliderTheme: SliderThemeData(
      // The mono scheme maps surfaceContainerHighest (the M3 default inactive
      // track) to the same color as surface cards, which makes the inactive
      // track invisible inside grouped-list items.
      inactiveTrackColor: c.text.withValues(alpha: 0.12),
      trackHeight: 16,
      trackGap: 6,
      thumbSize: const WidgetStatePropertyAll(Size(4, 20)),
      thumbShape: const HandleThumbShape(),
      trackShape: const GappedTrackShape(),
      tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 2),
      // ignore: deprecated_member_use — opting into the 2024 slider appearance until the default flips
      year2023: false,
    ),
    dividerTheme: DividerThemeData(space: 0, thickness: 1, color: c.outline),
    listTileTheme: ListTileThemeData(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      iconColor: c.text,
      textColor: c.text,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.bg,
      elevation: 0,
      indicatorColor: Colors.transparent,
      labelTextStyle: WidgetStatePropertyAll(TextStyle(color: c.textMuted, fontSize: 11)),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final active = states.contains(WidgetState.selected);
        return IconThemeData(opacity: active ? 1 : 0.6, size: 22, color: active ? c.accent : c.text);
      }),
    ),
    // Floating snackbars auto-offset above the Scaffold's bottom NavigationBar,
    // so they don't cover it on mobile. Background color tracks the theme to
    // avoid jarring brightness on HDR playback / dark mode.
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.surface,
      contentTextStyle: TextStyle(color: c.text),
      actionTextColor: c.text,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(themeRadius)),
      insetPadding: const EdgeInsets.all(16),
    ),
  );

  // Apple's builds under Glas — the look being fitted to Apple's: every style
  // the theme hands out in SF Pro, cut and spaced for its size, after
  // ThemeData has merged its defaults in, since only then does every style
  // have one. Flach keeps SF Pro as it was.
  final appleType = variant == AppThemeVariant.glas && ockerAppleSystemFont;
  TextStyle? apple(TextStyle? style) =>
      style == null ? null : appleSystemType(style, pointsPerPixel: ockerApplePointsPerPixel);

  return base.copyWith(
    textTheme: appleType ? _appleTextTheme(base.textTheme) : null,
    appBarTheme: appleType
        ? base.appBarTheme.copyWith(
            titleTextStyle: apple(base.appBarTheme.titleTextStyle?.copyWith(fontFamily: ockerUiFontFamily)),
          )
        : null,
    extensions: [
      MonoTokens(
        // The redesign's corners, which were nothing at all until the posters
        // got theirs.
        //
        // §10 asked for square everywhere, and it held for as long as the
        // pictures were square too. Once artwork was rounded — see
        // [artworkRadius] — every box beside it read as the thing that had been
        // forgotten rather than as a decision. So the ladder came back, in the
        // posters' own key: a shade rounder than "Standard", which is what a
        // 6.5 % corner on a poster comes out at.
        radiusSm: redesign ? _redesignCorner : 8,
        radiusMd: redesign ? 18 : 12,
        radiusLg: redesign ? 24 : 20,
        radiusXs: redesign ? 6 : 5,
        groupGap: redesign ? 1 : 2,
        // 18 is the one spacing number the design repeats — the gap between
        // poster tiles — so everything that takes its padding from here lands
        // on the same rhythm as the grid.
        space: redesign ? 18 : 12,
        // Ocker's motion table: focus 120, panel crossfade 180, ambient
        // background 400, menu 140. Short and mechanical; nothing reflows.
        fast: const Duration(milliseconds: 120),
        normal: Duration(milliseconds: redesign ? 180 : 200),
        slow: Duration(milliseconds: redesign ? 400 : 300),
        expressive: Duration(milliseconds: redesign ? 140 : 350),
        bg: c.bg,
        surface: c.surface,
        outline: c.outline,
        text: c.text,
        textMuted: c.textMuted,
        // Standard keeps [text], which is what focus rings and the navigation
        // already drew with.
        // Ocker's one loud colour, and it is loud in exactly three places:
        // progress, the now-line, and the active navigation entry. Focus rings
        // are deliberately *not* one of them — see [focusRing] below.
        accent: redesign ? glas.accent : c.accent,
        // Thirty per cent off the standard 2.5; Ocker goes to a hairline,
        // which is all a ring needs when it also has room around it.
        focusBorderWidth: redesign ? 1 : 2.5,
        itemAccentFocusRing: !redesign,
        sectionIcons: !redesign,
        profileAvatar: !redesign,
        displayFontFamily: redesign ? ockerDisplayFontFamily : null,
        uiFontFamily: redesign ? ockerUiFontFamily : null,
        monoFontFamily: redesign ? ockerMonoFontFamily : null,
        focusRing: redesign ? c.text : null,
        focusRingOffset: redesign ? 5 : 0,
        shadowsEnabled: !redesign,
        redesignLayout: redesign,
        glass: redesign,
        flat: flat,
        accentWash: redesign && !flat ? glasAccentWash(glasAccent) : 0.22,
      ),
    ],
  );
}

/// [theme] with every style cut and spaced for its size ([appleSystemType]).
TextTheme _appleTextTheme(TextTheme theme) {
  TextStyle? apple(TextStyle? style) =>
      style == null ? null : appleSystemType(style, pointsPerPixel: ockerApplePointsPerPixel, keepSpacedOut: false);
  return TextTheme(
    displayLarge: apple(theme.displayLarge),
    displayMedium: apple(theme.displayMedium),
    displaySmall: apple(theme.displaySmall),
    headlineLarge: apple(theme.headlineLarge),
    headlineMedium: apple(theme.headlineMedium),
    headlineSmall: apple(theme.headlineSmall),
    titleLarge: apple(theme.titleLarge),
    titleMedium: apple(theme.titleMedium),
    titleSmall: apple(theme.titleSmall),
    bodyLarge: apple(theme.bodyLarge),
    bodyMedium: apple(theme.bodyMedium),
    bodySmall: apple(theme.bodySmall),
    labelLarge: apple(theme.labelLarge),
    labelMedium: apple(theme.labelMedium),
    labelSmall: apple(theme.labelSmall),
  );
}

/// Points [AppIconDefaults] at the look [variant] asks for.
///
/// Icons do not come from [ThemeData] — [AppIcon] reads a set of statics, which
/// is why one call here reaches every symbol drawn through it. Standard is what
/// the app has always shown: filled and bold.
///
/// Glas takes Apple's rule instead of its own (the user's call, 2026-10-13,
/// on every device): an icon as heavy as the words beside it — 400 — and
/// drawn for the size it is shown at, so a small one does not thin out. On
/// Apple's builds ([ockerAppleLook]) the three glyphs that read as Android's
/// own give way to Apple's: Back is a chevron, More a row of dots, Share a box
/// with an arrow.
void applyIconDefaultsFor(AppThemeVariant variant) {
  final glas = variant == AppThemeVariant.glas;
  AppIconDefaults.substitutes = glas && ockerAppleLook ? appleGlyphSubstitutes : {};
  AppIconDefaults.opticalSizeFollowsSize = glas;
  AppIconDefaults.update(
    fill: switch (variant) {
      AppThemeVariant.standard => 1,
      // Ocker fills exactly two glyphs, and neither of them goes through here:
      // the play triangle and the LIVE marker draw their own.
      AppThemeVariant.glas || AppThemeVariant.flach => 0,
    },
    weight: switch (variant) {
      AppThemeVariant.standard => 700,
      AppThemeVariant.glas => 400,
      // Flat leans on words and a few plain glyphs; a little more ink keeps
      // the glyphs from vanishing without glass to sit on.
      AppThemeVariant.flach => 300,
    },
  );
}

/// The glyphs Apple's apps draw where these draw Android's (see
/// [applyIconDefaultsFor]).
final appleGlyphSubstitutes = <IconData, IconData>{
  Symbols.arrow_back_rounded: Symbols.arrow_back_ios_new_rounded,
  Symbols.more_vert_rounded: Symbols.more_horiz_rounded,
  Symbols.share_rounded: Symbols.ios_share_rounded,
};

/// [scale] with the two middle display sizes given the redesign's title
/// treatment, or [scale] untouched when this is not a redesign variant.
///
/// These were set in Instrument Serif, which is what the design was drawn with
/// — and what a television undoes: one weight, hairline strokes, read across a
/// room over a photograph. The interface face carries them now, bold and
/// tight. See [OckerType.detailTitle].
TextTheme _redesignDisplayFaces(TextTheme scale, {required bool redesign}) {
  if (!redesign) return scale;
  TextStyle? title(TextStyle? style, double letterSpacing) =>
      style?.copyWith(fontWeight: FontWeight.w700, letterSpacing: letterSpacing, height: 1.05);
  return scale.copyWith(displayMedium: title(scale.displayMedium, -1), displaySmall: title(scale.displaySmall, -0.8));
}

/// Brighter fill on focus so input focus is visible inside TV overscan.
InputDecorationTheme _inputDecorationTheme(Color text, Color textMuted, double radius) {
  final unfocusedFill = text.withValues(alpha: 0.08);
  final focusedFill = text.withValues(alpha: 0.18);
  final border = OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: BorderSide.none);
  return InputDecorationTheme(
    filled: true,
    fillColor: WidgetStateColor.resolveWith(
      (states) => states.contains(WidgetState.focused) ? focusedFill : unfocusedFill,
    ),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: border,
    enabledBorder: border,
    focusedBorder: border,
    hintStyle: TextStyle(color: textMuted),
  );
}

/// Plebz: a bar under the redesign — clear while nothing is under it, so the
/// page's ground shows through as everywhere else, and the ground itself once
/// content scrolls under it. Clear for good, a pinned or floating bar let the
/// rows beneath show through its title and buttons (phones and tablets, which
/// keep the app's own layouts under the look).
Color redesignBarColor(Color ground) => WidgetStateColor.resolveWith(
  (states) => states.contains(WidgetState.scrolledUnder) ? ground.withValues(alpha: 1) : ground.withValues(alpha: 0),
);
