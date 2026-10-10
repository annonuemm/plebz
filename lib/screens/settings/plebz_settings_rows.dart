import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../profiles/active_profile_provider.dart';
import '../../providers/catalog_sources_provider.dart';
import '../../providers/iptv_sources_provider.dart';
import '../../services/settings_service.dart' hide ThemeMode;
import '../../services/settings_service.dart' as settings show ThemeMode;
import '../../services/settings_mutation_service.dart';
import '../../redesign/ocker_skin.dart' show OckerKeepColours;
import '../../theme/mono_theme.dart'
    show FlachPreset, flachPresetById, flachPresets, isRedesignVariant, redesignOfferedHere, supportedAppThemeVariant;
import '../../utils/platform_detector.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/overlay_sheet.dart';
import '../../widgets/setting_tile.dart';
import '../../widgets/settings_builder.dart';
import '../../widgets/settings_section.dart';
import '../profile/profile_switch_screen.dart';
import 'about_screen.dart';
import 'add_connection_screen.dart';
import 'appearance_settings_screen.dart';
import 'general_settings_screen.dart';
import 'iptv_settings_screen.dart';
import 'live_picture_setting.dart';
import 'playback_settings_screen.dart';
import 'services_settings_screen.dart';
import 'settings_screen.dart';
import 'settings_utils.dart';
import 'shader_preset_setting.dart';
import 'subtitle_styling_screen.dart';
import '../setup_wizard/setup_wizard.dart';
import 'plebz_updates.dart';

/// The row the page falls back to when focus comes in with the remote.
const plebzSettingsFirstKey = 'plebz_add_connection';

/// The settings page Plebz opens on: what most people change, grouped, and
/// everything else one row away under "All settings" — upstream's own list,
/// untouched, so a merge never has to reconcile the two.
///
/// Each row here writes the same pref as its twin further in, through the same
/// `SettingsMutationService`, so the two can never disagree. Where a setting
/// needs more than a switch or a short list (languages, quality ladders), the
/// row is a way into the screen that already does it rather than a copy of it.
List<Widget> plebzSettingsRows(BuildContext context, {required FocusNode Function(String key) focusNode}) {
  final hasExplore = context.watch<CatalogSourcesProvider?>()?.hasAnySource ?? false;
  final iptvCount = context.watch<IptvSourcesProvider?>()?.sources.length ?? 0;
  // Display switching is for a television on HDMI (see the playback screen).
  final androidTv = Platform.isAndroid && PlatformDetector.isTvDevice();

  return [
    const SizedBox(height: 8),
    SettingsGroup(
      title: t.plebz.sourcesAndAccounts,
      children: [
        SettingNavigationTile(
          focusNode: focusNode(plebzSettingsFirstKey),
          icon: Symbols.add_link_rounded,
          title: t.connections.addConnection,
          subtitle: t.plebz.addConnectionDescription,
          onTap: () {
            final active = context.read<ActiveProfileProvider>().active;
            Navigator.push(context, MaterialPageRoute(builder: (_) => AddConnectionScreen(targetProfile: active)));
          },
        ),
        SettingNavigationTile(
          focusNode: focusNode('plebz_profiles'),
          icon: Symbols.group_rounded,
          title: t.profiles.sectionTitle,
          onTap: () => Navigator.of(
            context,
            rootNavigator: true,
          ).push(MaterialPageRoute(builder: (_) => const ProfileSwitchScreen())),
        ),
        SettingNavigationTile(
          focusNode: focusNode('plebz_iptv'),
          icon: Symbols.live_tv_rounded,
          title: t.iptv.title,
          subtitle: iptvCount == 0 ? t.iptv.addPlaylistDescription : t.iptv.sourceCount(n: iptvCount),
          destinationBuilder: (_) => const IptvSettingsScreen(),
        ),
        SettingNavigationTile(
          focusNode: focusNode('plebz_services'),
          icon: Symbols.sync_rounded,
          title: t.settings.services,
          subtitle: t.settings.servicesDescription,
          destinationBuilder: (_) => const ServicesSettingsScreen(),
        ),
      ],
    ),
    SettingsGroup(
      title: t.settings.appearance,
      children: [
        ...plebzAppearanceRows(),
        SettingNavigationTile(
          focusNode: focusNode('plebz_more_appearance'),
          icon: Symbols.palette_rounded,
          title: t.plebz.moreAppearance,
          subtitle: t.plebz.moreAppearanceDescription,
          destinationBuilder: (_) => const AppearanceSettingsScreen(),
        ),
      ],
    ),
    SettingsGroup(
      title: t.plebz.startAndNavigation,
      children: [
        SettingNavigationTile(
          focusNode: focusNode('plebz_general'),
          icon: Symbols.language_rounded,
          title: t.settings.general,
          subtitle: t.settings.generalDescription,
          destinationBuilder: (_) => const GeneralSettingsScreen(),
        ),
        SettingSwitchTile(
          pref: SettingsService.showSportTab,
          icon: Symbols.sports_soccer_rounded,
          title: t.settings.showSportTab,
          subtitle: t.settings.showSportTabDescription,
        ),
        SettingSwitchTile(
          pref: SettingsService.showLiveNowRow,
          icon: Symbols.live_tv_rounded,
          title: t.settings.showLiveNowRow,
          subtitle: t.settings.showLiveNowRowDescription,
        ),
        if (hasExplore)
          SettingSwitchTile(
            pref: SettingsService.showExploreTab,
            icon: Symbols.explore_rounded,
            title: t.settings.showExploreTab,
            subtitle: t.settings.showExploreTabDescription,
          ),
      ],
    ),
    SettingsGroup(
      title: t.settings.videoPlayback,
      children: [
        SettingSwitchTile(
          pref: SettingsService.autoPlayNextEpisode,
          icon: Symbols.skip_next_rounded,
          title: t.settings.autoPlayNextEpisode,
          subtitle: t.settings.autoPlayNextEpisodeDescription,
        ),
        SettingSelectionTile<SkipMarkerMode>(
          pref: SettingsService.skipIntroMode,
          icon: Symbols.fast_forward_rounded,
          title: t.settings.skipIntroMode,
          subtitleBuilder: (mode) => '${_skipMarkerModeLabel(mode)} · ${_skipIntroModeDescription(mode)}',
          options: SkipMarkerMode.values.map((m) => DialogOption(value: m, title: _skipMarkerModeLabel(m))).toList(),
        ),
        SettingSelectionTile<SkipMarkerMode>(
          pref: SettingsService.skipCreditsMode,
          icon: Symbols.skip_next_rounded,
          title: t.settings.skipCreditsMode,
          subtitleBuilder: (mode) => '${_skipMarkerModeLabel(mode)} · ${_skipCreditsModeDescription(mode)}',
          options: SkipMarkerMode.values.map((m) => DialogOption(value: m, title: _skipMarkerModeLabel(m))).toList(),
        ),
        // The mpv shader, here as well: one too heavy for the device makes the
        // player's own menu hard to reach (the user's case).
        ?shaderPresetSettingTile(context),
        if (androidTv) ...[
          SettingSwitchTile(
            pref: SettingsService.matchContentFrameRate,
            icon: Symbols.display_settings_rounded,
            title: t.settings.matchContentFrameRate,
            subtitle: t.settings.matchContentFrameRateDescription,
          ),
          SettingSwitchTile(
            pref: SettingsService.matchDisplayResolution,
            icon: Symbols.aspect_ratio_rounded,
            title: t.settings.matchDisplayResolution,
            subtitle: t.settings.matchDisplayResolutionDescription,
          ),
        ],
        SettingNavigationTile(
          focusNode: focusNode('plebz_subtitles'),
          icon: Symbols.subtitles_rounded,
          title: t.settings.subtitleStyling,
          subtitle: t.settings.subtitleStylingDescription,
          destinationBuilder: (_) => const SubtitleStylingScreen(),
        ),
        SettingNavigationTile(
          focusNode: focusNode('plebz_more_playback'),
          icon: Symbols.play_circle_rounded,
          title: t.plebz.morePlayback,
          subtitle: t.plebz.morePlaybackDescription,
          destinationBuilder: (_) => const PlaybackSettingsScreen(),
        ),
      ],
    ),
    SettingsBuilder(
      prefs: livePictureSettingPrefs,
      builder: (context) => SettingsGroup(
        title: t.settings.liveTv,
        children: [
          SettingSwitchTile(
            pref: SettingsService.liveTvDefaultFavorites,
            icon: Symbols.star_rounded,
            title: t.settings.liveTvDefaultFavorites,
            subtitle: t.settings.liveTvDefaultFavoritesDescription,
          ),
          ...livePictureSettingTiles(),
        ],
      ),
    ),
    SettingsGroup(
      title: t.plebz.appAndUpdates,
      children: [
        ...plebzUpdateRows(context),
        SettingNavigationTile(
          focusNode: focusNode('plebz_setup_again'),
          icon: Symbols.auto_fix_high_rounded,
          title: t.plebz.setupAgain,
          subtitle: t.plebz.setupAgainDescription,
          destinationBuilder: (_) => const SetupLookScreen(firstRun: false),
        ),
        SettingNavigationTile(
          focusNode: focusNode('plebz_about'),
          icon: Symbols.info_rounded,
          title: t.settings.about,
          subtitle: t.settings.aboutDescription,
          destinationBuilder: (_) => const AboutScreen(),
        ),
      ],
    ),
    // Set apart, as the full list ends on "About": the way on, not one more
    // setting of the group above.
    const SizedBox(height: 24),
    SettingsGroup(
      children: [
        SettingNavigationTile(
          focusNode: focusNode('plebz_all_settings'),
          icon: Symbols.tune_rounded,
          title: t.plebz.allSettings,
          subtitle: t.plebz.allSettingsDescription,
          // Upstream's full list, as a page of its own: a list with nothing
          // behind it, like the tab it used to be.
          destinationBuilder: (_) => const OverlaySheetNoGlass(child: SettingsScreen(focusOnOpen: true)),
        ),
      ],
    ),
    const SizedBox(height: 24),
  ];
}

/// The look, as the settings page and the first-run setup both offer it:
/// design, then the redesign's accent and navigation while it is on, then
/// light or dark. Applied live — the page redraws as a choice is made.
List<Widget> plebzAppearanceRows() => [
  _themeVariantSelector(),
  SettingValueBuilder<AppThemeVariant>(
    pref: SettingsService.appThemeVariant,
    builder: (context, variant, _) => switch (supportedAppThemeVariant(variant)) {
      AppThemeVariant.glas => _glasAccentSelector(),
      AppThemeVariant.flach => flachColourTiles(),
      AppThemeVariant.standard => const SizedBox.shrink(),
    },
  ),
  plebzThemeModeRow(),
];

/// Light or dark — or, under the redesign, which has no light half, the
/// ground it stands on: its palette's own, an off-black, black for an OLED
/// screen, or a colour of the viewer's own.
///
/// OLED is [SettingsService.themeMode] either way, so a viewer who has it
/// keeps it across designs; the others are the redesigns' own switches
/// ([SettingsService.redesignOffBlack], [SettingsService.redesignCustomGround]).
Widget plebzThemeModeRow({IconData icon = Symbols.dark_mode_rounded}) => SettingValueBuilder<AppThemeVariant>(
  pref: SettingsService.appThemeVariant,
  builder: (context, variant, _) => isRedesignVariant(supportedAppThemeVariant(variant))
      ? const _GlasGroundTile()
      : SettingSelectionTile<settings.ThemeMode>(
          pref: SettingsService.themeMode,
          icon: icon,
          title: t.settings.theme,
          subtitleBuilder: themeModeLabel,
          options: settings.ThemeMode.values.map((m) => DialogOption(value: m, title: themeModeLabel(m))).toList(),
        ),
);

/// The grounds the redesigns can stand on.
enum RedesignGround { design, offBlack, oled, custom }

/// Which of them the stored choices amount to: OLED wins, then the viewer's
/// own colour, then off-black.
RedesignGround redesignGroundOf(settings.ThemeMode mode, {required bool offBlack, bool custom = false}) =>
    mode == settings.ThemeMode.oled
    ? RedesignGround.oled
    : custom
    ? RedesignGround.custom
    : offBlack
    ? RedesignGround.offBlack
    : RedesignGround.design;

/// The same, read from the settings.
RedesignGround storedRedesignGround(SettingsService service) => redesignGroundOf(
  service.read(SettingsService.themeMode),
  offBlack: service.read(SettingsService.redesignOffBlack),
  custom: service.read(SettingsService.redesignCustomGround),
);

String redesignGroundLabel(RedesignGround ground) => switch (ground) {
  RedesignGround.design => t.settings.glasGroundAccent,
  RedesignGround.offBlack => t.settings.glasGroundOffBlack,
  RedesignGround.oled => t.settings.glasGroundOled,
  RedesignGround.custom => t.settings.glasGroundCustom,
};

/// The redesign's ground: the palette's own, off-black, black, or a colour of
/// the viewer's own, picked with the accent's picker.
class _GlasGroundTile extends StatelessWidget {
  const _GlasGroundTile();

  Future<void> _store(BuildContext context, RedesignGround ground, {String? colour}) async {
    final service = SettingsService.instance;
    final wasOled = service.read(SettingsService.themeMode) == settings.ThemeMode.oled;
    const mutation = SettingsMutationService();
    // Flach (Plebz): a ground of the viewer's leaves the look — its accent
    // stays, already stored when the look was chosen.
    final leavesLook = _flachLookActive(service);
    // The colour and the plain grounds first: leaving OLED for one of them
    // then lands on it in one step, not on the design's ground in between.
    final writes = <Future<SettingsEffectFailure?> Function()>[
      if (leavesLook) () => mutation.write(context, SettingsService.flachPreset, ''),
      if (colour != null) () => mutation.write(context, SettingsService.redesignGroundColour, colour),
      () => mutation.write(context, SettingsService.redesignCustomGround, ground == RedesignGround.custom),
      () => mutation.write(context, SettingsService.redesignOffBlack, ground == RedesignGround.offBlack),
      // Leaving OLED settles on dark, the redesign's own side; a stored light
      // or system choice is left alone for the other designs.
      if ((ground == RedesignGround.oled) != wasOled)
        () => mutation.write(
          context,
          SettingsService.themeMode,
          ground == RedesignGround.oled ? settings.ThemeMode.oled : settings.ThemeMode.dark,
        ),
    ];
    for (final write in writes) {
      if (!context.mounted) return;
      final failure = await write();
      if (failure != null) {
        if (context.mounted) showErrorSnackBar(context, failure.display);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsBuilder(
      prefs: const [
        SettingsService.themeMode,
        SettingsService.redesignOffBlack,
        SettingsService.redesignCustomGround,
        SettingsService.redesignGroundColour,
        SettingsService.flachPreset,
        SettingsService.appThemeVariant,
      ],
      builder: (context) {
        final service = SettingsService.instance;
        final ground = storedRedesignGround(service);
        final colourHex = service.read(SettingsService.redesignGroundColour);
        // Under a Flach look its ground is the look's, unless OLED wins.
        final fromLook = _flachLookActive(service) && ground != RedesignGround.oled;
        return SettingNavigationTile(
          icon: Symbols.contrast_rounded,
          title: t.settings.glasGround,
          subtitle: fromLook ? t.settings.flachPresetGround : redesignGroundLabel(ground),
          onTap: () async {
            final picked = await showSelectionDialog<RedesignGround>(
              context: context,
              title: t.settings.glasGround,
              options: [
                DialogOption(
                  value: RedesignGround.design,
                  title: t.settings.glasGroundAccent,
                  subtitle: t.settings.glasGroundAccentDescription,
                ),
                DialogOption(
                  value: RedesignGround.offBlack,
                  title: t.settings.glasGroundOffBlack,
                  subtitle: t.settings.glasGroundOffBlackDescription,
                ),
                DialogOption(
                  value: RedesignGround.oled,
                  title: t.settings.glasGroundOled,
                  subtitle: t.settings.glasGroundOledDescription,
                ),
                DialogOption(
                  value: RedesignGround.custom,
                  title: t.settings.glasGroundCustom,
                  subtitle: t.settings.glasGroundCustomDescription,
                ),
              ],
              currentValue: ground,
            );
            if (picked == null || !context.mounted) return;
            // The viewer's own colour is picked every time it is chosen —
            // chosen again, it is the way to change it.
            if (picked.value == RedesignGround.custom) {
              showColorInputDialog(
                context: context,
                title: t.settings.glasGroundCustom,
                currentHex: colourHex,
                onSave: (hex) => _store(context, RedesignGround.custom, colour: hex),
              );
              return;
            }
            if (picked.value == ground && !fromLook) return;
            await _store(context, picked.value);
          },
        );
      },
    );
  }
}

Widget _themeVariantSelector() => SettingSelectionTile<AppThemeVariant>(
  pref: SettingsService.appThemeVariant,
  icon: Symbols.palette_rounded,
  title: t.settings.appThemeVariant,
  subtitleBuilder: (value) => switch (supportedAppThemeVariant(value)) {
    AppThemeVariant.standard => t.settings.appThemeVariantStandard,
    AppThemeVariant.glas => t.settings.appThemeVariantGlas,
    AppThemeVariant.flach => t.settings.appThemeVariantFlach,
  },
  options: [
    DialogOption(
      value: AppThemeVariant.standard,
      title: t.settings.appThemeVariantStandard,
      subtitle: t.settings.appThemeVariantStandardDescription,
    ),
    if (redesignOfferedHere)
      DialogOption(
        value: AppThemeVariant.glas,
        title: t.settings.appThemeVariantGlas,
        subtitle: t.settings.appThemeVariantGlasDescription,
      ),
    if (redesignOfferedHere)
      DialogOption(
        value: AppThemeVariant.flach,
        title: t.settings.appThemeVariantFlach,
        subtitle: t.settings.appThemeVariantFlachDescription,
      ),
  ],
);

/// Whether a ready-made look ([SettingsService.flachPreset]) is on and
/// Flach the design on show.
bool _flachLookActive(SettingsService service) =>
    supportedAppThemeVariant(service.read(SettingsService.appThemeVariant)) == AppThemeVariant.flach &&
    flachPresetById(service.read(SettingsService.flachPreset)) != null;

/// "Redesign – Flach"'s colours (Plebz): a ready-made look, then the accent.
Widget flachColourTiles() => Column(mainAxisSize: .min, children: [const _FlachLookTile(), flachAccentTile()]);

/// "Redesign – Flach"'s accent (Plebz): any colour, picked on the colour
/// picker the subtitle colours use. A colour of the viewer's leaves the look
/// ([SettingsService.flachPreset]); its ground goes back to the settings'.
Widget flachAccentTile() => SettingColorTile(
  pref: SettingsService.flachAccent,
  icon: Symbols.colors_rounded,
  title: t.settings.flachAccent,
  subtitle: t.settings.flachAccentDescription,
  onAfterWrite: (_) => SettingsService.instance.write(SettingsService.flachPreset, ''),
);

/// The looks' names.
String flachPresetLabel(FlachPreset preset) => switch (preset.id) {
  'nordlicht' => t.settings.flachPresetNordlicht,
  'glut' => t.settings.flachPresetGlut,
  'mitternacht' => t.settings.flachPresetMitternacht,
  'kirschbluete' => t.settings.flachPresetKirschbluete,
  'amethyst' => t.settings.flachPresetAmethyst,
  'bernstein' => t.settings.flachPresetBernstein,
  'safran' => t.settings.flachPresetSafran,
  'kino' => t.settings.flachPresetKino,
  _ => t.settings.flachPresetStandard,
};

/// A look as a swatch: its ground, its accent as a dot. Kept in its colours
/// under the flat focus fill.
Widget _flachLookSwatch(BuildContext context, FlachPreset preset) => OckerKeepColours(
  child: Container(
    width: 44,
    height: 28,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: preset.ground,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: preset.accent, shape: BoxShape.circle),
    ),
  ),
);

/// "Farbprofil": a ready-made Flach look, accent and ground together. Chosen,
/// the accent is stored too, so the colour row and its picker show it and
/// start from it.
class _FlachLookTile extends StatelessWidget {
  const _FlachLookTile();

  @override
  Widget build(BuildContext context) {
    return SettingsBuilder(
      prefs: const [SettingsService.flachPreset],
      builder: (context) {
        final service = SettingsService.instance;
        final current = flachPresetById(service.read(SettingsService.flachPreset));
        return SettingNavigationTile(
          icon: Symbols.palette_rounded,
          title: t.settings.flachPreset,
          subtitle: current == null ? t.settings.flachPresetCustom : flachPresetLabel(current),
          onTap: () async {
            final picked = await showSelectionDialog<String>(
              context: context,
              title: t.settings.flachPreset,
              options: [
                for (final preset in flachPresets)
                  DialogOption(
                    value: preset.id,
                    title: flachPresetLabel(preset),
                    trailing: _flachLookSwatch(context, preset),
                  ),
              ],
              currentValue: current?.id ?? '',
            );
            if (picked == null || !context.mounted) return;
            final preset = flachPresetById(picked.value)!;
            const mutation = SettingsMutationService();
            final argb = preset.accent.toARGB32() & 0xFFFFFF;
            final hex = '#${argb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
            for (final write in <Future<SettingsEffectFailure?> Function()>[
              () => mutation.write(context, SettingsService.flachAccent, hex),
              () => mutation.write(context, SettingsService.flachPreset, preset.id),
            ]) {
              if (!context.mounted) return;
              final failure = await write();
              if (failure != null) {
                if (context.mounted) showErrorSnackBar(context, failure.display);
                return;
              }
            }
          },
        );
      },
    );
  }
}

Widget _glasAccentSelector() => SettingSelectionTile<GlasAccent>(
  pref: SettingsService.glasAccent,
  icon: Symbols.colors_rounded,
  title: t.settings.glasAccent,
  subtitleBuilder: _glasAccentLabel,
  options: [
    for (final accent in GlasAccent.values)
      DialogOption(value: accent, title: _glasAccentLabel(accent), subtitle: _glasAccentDescription(accent)),
  ],
);

String _glasAccentLabel(GlasAccent value) => switch (value) {
  GlasAccent.eisblau => t.settings.glasAccentEisblau,
  GlasAccent.mint => t.settings.glasAccentMint,
  GlasAccent.flieder => t.settings.glasAccentFlieder,
  GlasAccent.grau => t.settings.glasAccentGrau,
  GlasAccent.rot => t.settings.glasAccentRot,
  GlasAccent.plebz => t.settings.glasAccentPlebz,
};

String _glasAccentDescription(GlasAccent value) => switch (value) {
  GlasAccent.eisblau => t.settings.glasAccentEisblauDescription,
  GlasAccent.mint => t.settings.glasAccentMintDescription,
  GlasAccent.flieder => t.settings.glasAccentFliederDescription,
  GlasAccent.grau => t.settings.glasAccentGrauDescription,
  GlasAccent.rot => t.settings.glasAccentRotDescription,
  GlasAccent.plebz => t.settings.glasAccentPlebzDescription,
};

String _skipMarkerModeLabel(SkipMarkerMode mode) => switch (mode) {
  SkipMarkerMode.off => t.settings.skipMarkerModeOff,
  SkipMarkerMode.button => t.settings.skipMarkerModeButton,
  SkipMarkerMode.auto => t.settings.skipMarkerModeAuto,
};

String _skipIntroModeDescription(SkipMarkerMode mode) => switch (mode) {
  SkipMarkerMode.off => t.settings.skipIntroModeOffDescription,
  SkipMarkerMode.button => t.settings.skipIntroModeButtonDescription,
  SkipMarkerMode.auto => t.settings.skipIntroModeAutoDescription,
};

String _skipCreditsModeDescription(SkipMarkerMode mode) => switch (mode) {
  SkipMarkerMode.off => t.settings.skipCreditsModeOffDescription,
  SkipMarkerMode.button => t.settings.skipCreditsModeButtonDescription,
  SkipMarkerMode.auto => t.settings.skipCreditsModeAutoDescription,
};
