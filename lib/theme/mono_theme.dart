import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/settings_service.dart' show AppThemeVariant, GlasAccent;
import '../widgets/app_icon.dart';
import 'gapped_track_shape.dart';
import 'glass_backdrop.dart';
import 'mono_tokens.dart';

/// The Inter asset (`assets/fonts/Inter-Variable.ttf`) is the redesign's.
/// Inter sets about 4% wider than Roboto, and the lines that measure
/// themselves before they draw — the detail hero's facts row, the spotlight,
/// the pre-play track summary — spend that difference by dropping a field at
/// 1280x720; that is why the standard theme keeps the platform's face.

/// **The redesign is set in one typeface: Inter.** Both palettes, every line.
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
const ockerDisplayFontFamily = 'Inter';
const ockerUiFontFamily = 'Inter';
const ockerMonoFontFamily = 'Inter';

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
/// ([SettingsService.redesignOffBlack]): the dark grey Material calls its
/// dark surface, softer than black, and as plain — no lift, no glow. No
/// palette's own ground is this either.
const redesignOffBlackGround = Color(0xFF121212);

/// How light a ground of the viewer's own colour may be, as an HSV value: the
/// redesigns' ink stays light, and over a lighter ground it stops reading.
const redesignGroundMaxValue = 0.35;

/// A ground of the viewer's own colour ([SettingsService.redesignGroundColour]),
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

/// [SettingsService.flachAccent]'s `#RRGGBB` as a colour; the default violet
/// for anything that does not read as one.
Color flachAccentFromHex(String hex) {
  final digits = hex.replaceFirst('#', '');
  final value = digits.length == 6 ? int.tryParse(digits, radix: 16) : null;
  return value == null ? flachDefaultAccent : Color(0xFF000000 | value);
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
    bool dark,
    bool oled,
    Color? plainGround,
    TargetPlatform platform,
    AppThemeVariant variant,
    GlasAccent? glasAccent,
    Color? flachAccent,
  }),
  ThemeData
>
_monoThemeCache = {};

ThemeData monoTheme({
  required bool dark,
  bool oled = false,
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
    dark: dark || oled,
    oled: oled,
    // Only where it paints anything: the redesigns, and not over OLED's black.
    plainGround: oled || !isRedesignVariant(variant) ? null : plainGround,
    platform: defaultTargetPlatform,
    variant: variant,
    glasAccent: variant == AppThemeVariant.glas ? glasAccent : null,
    flachAccent: variant == AppThemeVariant.flach ? flachAccent : null,
  );
  final cached = _monoThemeCache[key];
  if (cached != null) return cached;

  final theme = _buildMonoTheme(
    dark: key.dark,
    oled: key.oled,
    plainGround: key.plainGround,
    platform: key.platform,
    variant: key.variant,
    glasAccent: glasAccent,
    flachAccent: flachAccent,
  );
  _monoThemeCache[key] = theme;
  return theme;
}

ThemeData _buildMonoTheme({
  required bool dark,
  required bool oled,
  required Color? plainGround,
  required TargetPlatform platform,
  required AppThemeVariant variant,
  required GlasAccent glasAccent,
  required Color flachAccent,
}) {
  // Which structure to build, and which of its two palettes to paint it in.
  // Its corner, its typeface and its want of shadows follow from the first;
  // only colour follows from the second.
  final redesign = isRedesignVariant(variant);
  final flat = variant == AppThemeVariant.flach;
  final glas = flat ? (bg: flachGround, text: flachInk, accent: flachAccent) : glasPalette(glasAccent);

  // neutral greys tuned for crisp contrast
  final ({Color bg, Color surface, Color outline, Color text, Color textMuted}) c;
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
    final ground = oled ? glasOledGround : plainGround ?? glas.bg;
    c = (
      bg: ground,
      // The block fill composited over the ground.
      surface: Color.alphaBlend(glas.text.withValues(alpha: 0.06), ground),
      outline: glas.text.withValues(alpha: 0.12),
      text: glas.text,
      textMuted: glas.text.withValues(alpha: 0.72),
    );
  } else if (oled) {
    c = (
      bg: const Color(0xFF000000), // Pure black for OLED
      surface: const Color(0xFF0A0A0A), // Very dark gray
      outline: const Color(0x1FFFFFFF),
      text: const Color(0xFFEDEDED),
      textMuted: const Color(0x99EDEDED),
    );
  } else if (dark) {
    c = (
      bg: const Color(0xFF0E0F12),
      surface: const Color(0xFF15171C),
      outline: const Color(0x1FFFFFFF),
      text: const Color(0xFFEDEDED),
      textMuted: const Color(0x99EDEDED),
    );
  } else {
    c = (
      bg: const Color(0xFFF7F7F8),
      surface: const Color(0xFFFFFFFF),
      outline: const Color(0x19000000),
      text: const Color(0xFF111111),
      textMuted: const Color(0x99111111),
    );
  }

  // The redesign has no light half — see the palette above — so it reports
  // dark whatever the light/dark switch says, and every Material default that
  // branches on brightness lands on the side its colours were drawn for.
  final isDark = redesign || dark || oled;
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
      (states) => states.contains(WidgetState.disabled) ? c.text.withValues(alpha: 0.12) : c.text,
    ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) =>
          states.contains(WidgetState.disabled) ? c.text.withValues(alpha: 0.38) : (isDark ? c.bg : Colors.white),
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
    brightness: isDark ? Brightness.dark : Brightness.light,
    // Linux resolves UI text through fontconfig, which on a minimal desktop
    // may have no CJK font at all; the bundled subtitle fonts (pubspec
    // `fonts:`) cover it. Other platforms keep their native CJK fonts.
    fontFamilyFallback: platform == TargetPlatform.linux ? const ['Go Noto Current', 'Go Noto Current Hangul'] : null,
    colorScheme: ColorScheme(
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: c.text,
      onPrimary: isDark ? c.bg : Colors.white,
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
      backgroundColor: redesign ? c.bg.withValues(alpha: 0) : c.bg,
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
        return IconThemeData(opacity: active ? 1 : 0.6, size: 22, color: c.text);
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

  return base.copyWith(
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
        accent: redesign ? glas.accent : c.text,
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

/// Points [AppIconDefaults] at the look [variant] asks for.
///
/// Icons do not come from [ThemeData] — [AppIcon] reads a set of statics, which
/// is why one call here reaches every symbol drawn through it. Standard is what
/// the app has always shown: filled and bold.
void applyIconDefaultsFor(AppThemeVariant variant) {
  AppIconDefaults.update(
    fill: switch (variant) {
      AppThemeVariant.standard => 1,
      // Ocker fills exactly two glyphs, and neither of them goes through here:
      // the play triangle and the LIVE marker draw their own.
      AppThemeVariant.glas || AppThemeVariant.flach => 0,
    },
    weight: switch (variant) {
      AppThemeVariant.standard => 700,
      // Lighter still: at 200 an icon carries about as much ink as the text
      // beside it, which is the whole argument for letting words do the
      // naming and leaving the symbol as a hint.
      AppThemeVariant.glas => 200,
      // Flat leans on words and a few plain glyphs; a little more ink keeps
      // the glyphs from vanishing without glass to sit on.
      AppThemeVariant.flach => 300,
    },
  );
}

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
