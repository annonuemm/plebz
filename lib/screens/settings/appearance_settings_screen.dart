import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../providers/catalog_sources_provider.dart';
import '../../providers/discover_provider.dart';
import '../../providers/seerr_account_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/recommendations_service.dart';
import '../../services/settings_service.dart' hide ThemeMode;
import '../../theme/mono_theme.dart' show isRedesignVariant, redesignOfferedHere, supportedAppThemeVariant;
import '../../focus/focusable_slider.dart';
import '../../services/device_performance.dart';
import '../../utils/dialogs.dart';
import '../../utils/platform_detector.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/setting_tile.dart';
import '../../widgets/settings_page.dart';
import '../../widgets/settings_builder.dart';
import '../../widgets/settings_section.dart';
import '../../redesign/ocker_skin.dart' show isOckerLayout;
import 'plebz_settings_rows.dart' show flachColourTiles, plebzThemeModeRow;
import 'settings_utils.dart';
import '../../utils/fork_identity.dart';

class AppearanceSettingsScreen extends StatelessWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Nullable watch: hosts without the profile session scope (tests) simply
    // never show the Explore toggle, mirroring the tab's own visibility.
    final hasExplore = context.watch<CatalogSourcesProvider?>()?.hasAnySource ?? false;
    // Rows that only mean something on some devices or with some services
    // connected are left out elsewhere rather than offered as dead switches.
    final isMobile = PlatformDetector.isMobile(context);
    final hasSeerr = context.watch<SeerrAccountProvider?>()?.isConnected ?? false;
    final hasTmdbKey = SettingsService.instance.read(SettingsService.tmdbApiKey)?.trim().isNotEmpty ?? false;
    // The redesign on a television lays out its own grids and rail: these rows
    // have nothing left to steer there (Plebz). On a phone, tablet or Mac it
    // is a look only, and they keep working.
    final glasLayout = isOckerLayout(context);
    // The catalog detail stage's condition (CatalogItemDetailScreen._usesStage).
    final catalogStage = glasLayout && PlatformDetector.isTV();
    return SettingsPage(
      title: Text(t.settings.appearance),
      children: [
        SettingsGroup(
          title: t.settings.display,
          children: [
            _themeSelector(),
            _themeVariantSelector(context),
            // Only asked while glass is the theme: the accent is a detail of a
            // look that is otherwise not there.
            SettingValueBuilder<AppThemeVariant>(
              pref: SettingsService.appThemeVariant,
              builder: (context, variant, _) => switch (supportedAppThemeVariant(variant)) {
                AppThemeVariant.glas => _glasAccentSelector(),
                AppThemeVariant.flach => flachColourTiles(),
                AppThemeVariant.standard => const SizedBox.shrink(),
              },
            ),
            // The glass focus's own motion, apart from the rest of the effects.
            // Not on a phone or tablet: a finger never puts focus anywhere.
            SettingValueBuilder<AppThemeVariant>(
              pref: SettingsService.appThemeVariant,
              builder: (context, variant, _) => supportedAppThemeVariant(variant) == AppThemeVariant.glas && !isMobile
                  ? SettingSwitchTile(
                      pref: SettingsService.glasSmoothFocus,
                      icon: Symbols.animation_rounded,
                      title: t.settings.glasSmoothFocus,
                      subtitle: t.settings.glasSmoothFocusDescription,
                    )
                  : const SizedBox.shrink(),
            ),
            SettingValueBuilder<AppThemeVariant>(
              pref: SettingsService.appThemeVariant,
              builder: (context, variant, _) => supportedAppThemeVariant(variant) == AppThemeVariant.glas && !isMobile
                  ? SettingSwitchTile(
                      pref: SettingsService.glasSpinningFocus,
                      icon: Symbols.autorenew_rounded,
                      title: t.settings.glasSpinningFocus,
                      subtitle: t.settings.glasSpinningFocusDescription,
                    )
                  : const SizedBox.shrink(),
            ),
            // The colours behind the television layout's screens; there is no
            // such ground on a phone, a tablet or the Mac.
            if (PlatformDetector.isTV())
              SettingValueBuilder<AppThemeVariant>(
                pref: SettingsService.appThemeVariant,
                builder: (context, variant, _) => isRedesignVariant(supportedAppThemeVariant(variant))
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Both redesigns: under "Flach" the colours take
                          // the place of its plain ground (the user's wish).
                          SettingSwitchTile(
                            pref: SettingsService.ultraBlurFor(
                              flat: supportedAppThemeVariant(variant) == AppThemeVariant.flach,
                            ),
                            icon: Symbols.gradient_rounded,
                            title: t.settings.glasUltraBlur,
                            subtitle: t.settings.glasUltraBlurDescription,
                          ),
                          SettingSwitchTile(
                            pref: SettingsService.seasonTabsFor(
                              flat: supportedAppThemeVariant(variant) == AppThemeVariant.flach,
                            ),
                            icon: Symbols.tab_rounded,
                            title: t.settings.redesignSeasonTabs,
                            subtitle: t.settings.redesignSeasonTabsDescription,
                          ),
                          SettingSwitchTile(
                            pref: SettingsService.glasDetailPanel,
                            icon: Symbols.view_sidebar_rounded,
                            title: t.settings.glasDetailPanel,
                            subtitle: t.settings.glasDetailPanelDescription,
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
            if (PlatformDetector.isAutomotive()) _displayScaleSelector(),
            if (Platform.isAndroid) _visualEffectsSelector(context),
          ],
        ),

        SettingsGroup(
          title: t.settings.libraryAndCards,
          children: [
            if (!glasLayout) _viewModeSelector(),
            if (!glasLayout) _densitySelector(),
            if (!glasLayout) _gridSpacingSelector(),
            _episodePosterModeSelector(),
            if (!glasLayout)
              SettingSwitchTile(
                pref: SettingsService.showEpisodeNumberOnCards,
                icon: Symbols.tag_rounded,
                title: t.settings.showEpisodeNumberOnCards,
                subtitle: t.settings.showEpisodeNumberOnCardsDescription,
              ),
            if (!PlatformDetector.isTV())
              SettingSwitchTile(
                pref: SettingsService.showSeasonPostersOnTabs,
                icon: Symbols.image_rounded,
                title: t.settings.showSeasonPostersOnTabs,
                subtitle: t.settings.showSeasonPostersOnTabsDescription,
              ),
            SettingSwitchTile(
              pref: SettingsService.hideSpoilers,
              icon: Symbols.visibility_off_rounded,
              title: t.settings.hideSpoilers,
              subtitle: t.settings.hideSpoilersDescription,
            ),
            SettingSwitchTile(
              pref: SettingsService.showWatchedIndicators,
              icon: Symbols.check_circle_rounded,
              title: t.settings.showWatchedIndicators,
              subtitle: t.settings.showWatchedIndicatorsDescription,
            ),
            if (PlatformDetector.isTV())
              SettingSwitchTile(
                pref: SettingsService.tvFullCardLayout,
                icon: Symbols.image_rounded,
                title: t.settings.tvFullCardLayout,
                subtitle: t.settings.tvFullCardLayoutDescription,
              ),
            // Also on a desktop window, where it has always *done* something
            // and only the switch was missing: a catalog detail page honours
            // it on every host (see `CatalogItemDetailScreen._buildBackdrop`),
            // so on a Mac the artwork treatment was fixed at whatever the
            // stored value happened to be.
            if (PlatformDetector.isTV() || PlatformDetector.isDesktopOS())
              SettingSwitchTile(
                pref: SettingsService.tvCornerSpotlightBackdrop,
                icon: Symbols.picture_in_picture_alt_rounded,
                title: t.settings.tvCornerSpotlightBackdrop,
                subtitle: t.settings.tvCornerSpotlightBackdropDescription,
              ),
            if (PlatformDetector.isTV() && !glasLayout)
              SettingSwitchTile(
                pref: SettingsService.focusGlow,
                icon: Symbols.lightbulb_rounded,
                title: t.settings.focusGlow,
                subtitle: t.settings.focusGlowDescription,
              ),
            SettingSwitchTile(
              pref: SettingsService.showHomeTitleLogos,
              icon: Symbols.title_rounded,
              title: t.settings.homeTitleLogos,
              subtitle: t.settings.homeTitleLogosDescription,
            ),
            if (hasSeerr)
              SettingSwitchTile(
                pref: SettingsService.seerrCardEpisodeFacts,
                icon: Symbols.playlist_add_check_rounded,
                title: t.settings.seerrCardEpisodeFacts,
                subtitle: t.settings.seerrCardEpisodeFactsDescription,
              ),
            SettingSwitchTile(
              pref: SettingsService.showLibraryPlaylistsTab,
              icon: Symbols.queue_music_rounded,
              title: t.settings.showLibraryPlaylistsTab,
              subtitle: t.settings.showLibraryPlaylistsTabDescription,
            ),
          ],
        ),

        // What the detail pages show — the fork's own switches, gathered
        // here rather than among the cards they do not touch.
        SettingsGroup(
          title: t.settings.detailPages,
          children: [
            SettingSwitchTile(
              pref: SettingsService.showDownloadAction,
              icon: Symbols.download_rounded,
              title: t.settings.showDownloadAction,
              subtitle: t.settings.showDownloadActionDescription,
            ),
            SettingSwitchTile(
              pref: SettingsService.showPlaybackTracksStatus,
              icon: Symbols.subtitles_rounded,
              title: t.settings.showPlaybackTracksStatus,
              subtitle: t.settings.showPlaybackTracksStatusDescription,
            ),
            SettingSwitchTile(
              pref: SettingsService.averageRatings,
              icon: Symbols.star_half_rounded,
              title: t.settings.averageRatings,
              subtitle: t.settings.averageRatingsDescription,
            ),
            if (hasTmdbKey)
              SettingSwitchTile(
                pref: SettingsService.showActorFilmography,
                icon: Symbols.theater_comedy_rounded,
                title: t.settings.showActorFilmography,
                subtitle: t.settings.showActorFilmographyDescription,
              ),
            // Not on a television under the redesigns: there an Explore
            // title's page shows its facts on the fact sheet beside the info
            // box, always, and these two switches steer nothing (Plebz).
            if (hasExplore && !catalogStage)
              SettingSwitchTile(
                pref: SettingsService.showCatalogDetailFacts,
                icon: Symbols.list_alt_rounded,
                title: t.settings.showCatalogDetailFacts,
                subtitle: t.settings.showCatalogDetailFactsDescription,
              ),
            if (hasExplore && !catalogStage)
              SettingSwitchTile(
                pref: SettingsService.showCatalogDetailCrew,
                icon: Symbols.movie_edit_rounded,
                title: t.settings.showCatalogDetailCrew,
                subtitle: t.settings.showCatalogDetailCrewDescription,
              ),
          ],
        ),

        SettingsGroup(
          title: t.settings.homeScreen,
          children: [
            if (!PlatformDetector.isTV())
              SettingSwitchTile(
                pref: SettingsService.showHeroSection,
                icon: Symbols.featured_play_list_rounded,
                title: t.settings.showHeroSection,
                subtitle: t.settings.showHeroSectionDescription,
              ),
            _continueWatchingActionSelector(),
            _episodeActionSelector(),
            SettingSwitchTile(
              pref: SettingsService.useGlobalHubs,
              icon: Symbols.home_rounded,
              title: t.settings.useGlobalHubs,
              subtitle: t.settings.useGlobalHubsDescription,
            ),
            SettingSwitchTile(
              pref: SettingsService.showServerNameOnHubs,
              icon: Symbols.dns_rounded,
              title: t.settings.showServerNameOnHubs,
              subtitle: t.settings.showServerNameOnHubsDescription,
            ),
            if (watchTogetherAvailable)
              SettingSwitchTile(
                pref: SettingsService.showWatchTogetherAction,
                icon: Symbols.group_rounded,
                title: t.settings.showWatchTogetherAction,
                subtitle: t.settings.showWatchTogetherActionDescription,
              ),
            SettingSwitchTile(
              pref: SettingsService.showCompanionRemoteAction,
              icon: Symbols.phone_android_rounded,
              title: t.settings.showCompanionRemoteAction,
              subtitle: t.settings.showCompanionRemoteActionDescription,
            ),
            if (!isMobile)
              SettingSwitchTile(
                pref: SettingsService.showServerActivitiesAction,
                icon: Symbols.monitor_heart_rounded,
                title: t.settings.showServerActivitiesAction,
                subtitle: t.settings.showServerActivitiesActionDescription,
              ),
            if (!isMobile)
              SettingSwitchTile(
                pref: SettingsService.hideHomeActionsUntilFocus,
                icon: Symbols.visibility_off_rounded,
                title: t.settings.hideHomeActionsUntilFocus,
                subtitle: t.settings.hideHomeActionsUntilFocusDescription,
              ),
            SettingSwitchTile(
              pref: SettingsService.showLiveNowRow,
              icon: Symbols.live_tv_rounded,
              title: t.settings.showLiveNowRow,
              subtitle: t.settings.showLiveNowRowDescription,
            ),
            SettingSwitchTile(
              pref: SettingsService.showRecommendationsRow,
              icon: Symbols.recommend_rounded,
              title: t.settings.showRecommendationsRow,
              subtitle: t.settings.showRecommendationsRowDescription,
            ),
            // Only asked once the row is on: it is a detail of a thing that is
            // otherwise not there.
            SettingValueBuilder<bool>(
              pref: SettingsService.showRecommendationsRow,
              builder: (context, showRow, _) => showRow ? _recommendationsSourceSelector() : const SizedBox.shrink(),
            ),
            // Forgets the row's "Mehr davon" and "Weniger davon"; only while
            // the row is on, like its source.
            SettingValueBuilder<bool>(
              pref: SettingsService.showRecommendationsRow,
              builder: (context, showRow, _) => showRow
                  ? SettingNavigationTile(
                      icon: Symbols.restart_alt_rounded,
                      title: t.settings.resetRecommendations,
                      subtitle: t.settings.resetRecommendationsDescription,
                      trailingIcon: Symbols.restart_alt_rounded,
                      onTap: () => _resetRecommendations(context),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),

        SettingsGroup(
          title: t.settings.navigation,
          children: [
            if (hasExplore)
              SettingSwitchTile(
                pref: SettingsService.showExploreTab,
                icon: Symbols.explore_rounded,
                title: t.settings.showExploreTab,
                subtitle: t.settings.showExploreTabDescription,
              ),
            // Right under Explore's switch, as the destination sits right after
            // Explore's in the navigation.
            SettingSwitchTile(
              pref: SettingsService.showSportTab,
              icon: Symbols.sports_soccer_rounded,
              title: t.settings.showSportTab,
              subtitle: t.settings.showSportTabDescription,
            ),
            if (Platform.isAndroid || PlatformDetector.isDesktopOS()) _layoutModeSelector(context),
            if (PlatformDetector.shouldUseSideNavigation(context) && !glasLayout)
              SettingSwitchTile(
                pref: SettingsService.alwaysKeepSidebarOpen,
                icon: Symbols.dock_to_left_rounded,
                title: t.settings.alwaysKeepSidebarOpen,
                subtitle: t.settings.alwaysKeepSidebarOpenDescription,
              ),
            if (PlatformDetector.shouldUseSideNavigation(context) && !glasLayout)
              SettingSwitchTile(
                pref: SettingsService.groupLibrariesByServer,
                icon: Symbols.dns_rounded,
                title: t.settings.groupLibrariesByServer,
                subtitle: t.settings.groupLibrariesByServerDescription,
              ),
            if (!PlatformDetector.shouldUseSideNavigation(context))
              SettingSwitchTile(
                pref: SettingsService.showNavBarLabels,
                icon: Symbols.label_rounded,
                title: t.settings.showNavBarLabels,
                subtitle: t.settings.showNavBarLabelsDescription,
              ),
            SettingSwitchTile(
              pref: SettingsService.showUnwatchedCount,
              icon: Symbols.counter_1_rounded,
              title: t.settings.showUnwatchedCount,
              subtitle: t.settings.showUnwatchedCountDescription,
            ),
          ],
        ),

        SettingsGroup(
          title: t.settings.liveTv,
          children: [
            SettingSwitchTile(
              pref: SettingsService.liveTvDefaultFavorites,
              icon: Symbols.star_rounded,
              title: t.settings.liveTvDefaultFavorites,
              subtitle: t.settings.liveTvDefaultFavoritesDescription,
            ),
            SettingSwitchTile(
              pref: SettingsService.liveTvGuideTimeNavigation,
              icon: Symbols.schedule_rounded,
              title: t.settings.liveTvGuideTimeNavigation,
              subtitle: t.settings.liveTvGuideTimeNavigationDescription,
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // Writes the pref directly; ThemeProvider listens to the pref's listenable
  // and applies the change live. The Consumer only feeds the dynamic icon.
  Widget _themeSelector() {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        return plebzThemeModeRow(icon: themeProvider.themeModeIcon);
      },
    );
  }

  // Same label-row-plus-control layout as SegmentedSetting so slider and
  // button-group tiles read as one family inside a SettingsGroup.
  Widget _densitySelector() {
    return SettingValueBuilder<int>(
      pref: SettingsService.libraryDensity,
      builder: (context, density, _) {
        final theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: .start,
            children: [
              Row(
                children: [
                  const AppIcon(Symbols.grid_view_rounded, fill: 1),
                  const SizedBox(width: 16),
                  Text(t.settings.libraryDensity, style: settingsOptionTitleStyle(context)),
                ],
              ),
              const SizedBox(height: 12),
              FocusableSlider(
                value: density.toDouble(),
                min: 1,
                max: 5,
                divisions: 4,
                onChanged: (v) => SettingsService.instance.write(SettingsService.libraryDensity, v.round()),
              ),
              Row(
                mainAxisAlignment: .spaceBetween,
                children: [
                  Text(t.settings.compact, style: theme.textTheme.bodySmall),
                  Text(t.settings.comfortable, style: theme.textTheme.bodySmall),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _displayScaleSelector() {
    return SettingValueBuilder<double>(
      pref: SettingsService.automotiveUiScale,
      builder: (context, scale, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: .start,
            children: [
              Row(
                children: [
                  const AppIcon(Symbols.format_size_rounded, fill: 1),
                  const SizedBox(width: 16),
                  Text(t.settings.displayScale, style: settingsOptionTitleStyle(context)),
                  const Spacer(),
                  Text('${scale.toStringAsFixed(2)}×', style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
              const SizedBox(height: 12),
              FocusableSlider(
                value: scale,
                min: AutomotiveUiScale.min,
                max: AutomotiveUiScale.max,
                divisions: 20,
                onChanged: (value) => SettingsService.instance.write(SettingsService.automotiveUiScale, value),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _viewModeSelector() => SettingSegmentedTile<ViewMode>(
    pref: SettingsService.viewMode,
    icon: Symbols.view_list_rounded,
    title: t.settings.viewMode,
    segments: [
      ButtonSegment(value: ViewMode.grid, label: Text(t.settings.gridView)),
      ButtonSegment(value: ViewMode.list, label: Text(t.settings.listView)),
    ],
  );

  Widget _gridSpacingSelector() => SettingSegmentedTile<GridSpacing>(
    pref: SettingsService.gridSpacing,
    icon: Symbols.padding_rounded,
    title: t.settings.gridSpacing,
    segments: [
      ButtonSegment(value: GridSpacing.tight, label: Text(t.settings.gridSpacingTight)),
      ButtonSegment(value: GridSpacing.normal, label: Text(t.settings.gridSpacingNormal)),
      ButtonSegment(value: GridSpacing.spacious, label: Text(t.settings.gridSpacingSpacious)),
    ],
  );

  Widget _episodePosterModeSelector() => SettingSegmentedTile<EpisodePosterMode>(
    pref: SettingsService.episodePosterMode,
    icon: Symbols.image_rounded,
    title: t.settings.episodePosterMode,
    segments: [
      ButtonSegment(value: EpisodePosterMode.seriesPoster, label: Text(t.settings.seriesPoster)),
      ButtonSegment(value: EpisodePosterMode.seasonPoster, label: Text(t.settings.seasonPoster)),
      ButtonSegment(value: EpisodePosterMode.episodeThumbnail, label: Text(t.settings.episodeThumbnail)),
    ],
  );

  Widget _continueWatchingActionSelector() => SettingSegmentedTile<ContinueWatchingAction>(
    pref: SettingsService.continueWatchingAction,
    icon: Symbols.play_circle_rounded,
    title: t.settings.continueWatchingAction,
    segments: [
      ButtonSegment(value: ContinueWatchingAction.play, label: Text(t.settings.continueWatchingPlay)),
      ButtonSegment(value: ContinueWatchingAction.details, label: Text(t.settings.continueWatchingDetails)),
    ],
  );

  Widget _episodeActionSelector() => SettingSegmentedTile<EpisodeAction>(
    pref: SettingsService.episodeAction,
    icon: Symbols.tv_rounded,
    title: t.settings.episodeAction,
    segments: [
      ButtonSegment(value: EpisodeAction.play, label: Text(t.settings.episodePlay)),
      ButtonSegment(value: EpisodeAction.details, label: Text(t.settings.episodeDetails)),
    ],
  );

  Future<void> _resetRecommendations(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context,
      title: t.settings.resetRecommendations,
      message: t.settings.resetRecommendationsDescription,
      confirmText: t.settings.resetRecommendationsConfirm,
    );
    if (!confirmed || !context.mounted) return;
    await context.read<DiscoverProvider?>()?.resetRecommendationFeedback();
    if (context.mounted) showSuccessSnackBar(context, t.settings.resetRecommendationsDone);
  }

  static String _recommendationsSourceLabel(RecommendationsSource source) => switch (source) {
    RecommendationsSource.all => t.settings.recommendationsSourceAll,
    RecommendationsSource.plex => t.settings.recommendationsSourcePlex,
    RecommendationsSource.jellyfin => t.settings.recommendationsSourceJellyfin,
    RecommendationsSource.emby => t.settings.recommendationsSourceEmby,
  };

  Widget _recommendationsSourceSelector() => SettingSelectionTile<RecommendationsSource>(
    pref: SettingsService.recommendationsSource,
    icon: Symbols.dns_rounded,
    title: t.settings.recommendationsSource,
    subtitleBuilder: _recommendationsSourceLabel,
    options: RecommendationsSource.values
        .map((source) => DialogOption(value: source, title: _recommendationsSourceLabel(source)))
        .toList(),
  );

  String _layoutModeLabel(LayoutMode value) => switch (value) {
    LayoutMode.auto => t.settings.layoutModeAuto,
    LayoutMode.tv => t.settings.layoutModeTv,
    LayoutMode.desktop => t.settings.layoutModeDesktop,
    LayoutMode.tablet => t.settings.layoutModeTablet,
    LayoutMode.phone => t.settings.layoutModePhone,
  };

  Widget _layoutModeSelector(BuildContext context) => SettingSelectionTile<LayoutMode>(
    pref: SettingsService.layoutMode,
    icon: Symbols.devices_rounded,
    title: t.settings.layoutMode,
    subtitleBuilder: _layoutModeLabel,
    options: [
      DialogOption(
        value: LayoutMode.auto,
        title: t.settings.layoutModeAuto,
        subtitle: t.settings.layoutModeAutoDescription,
      ),
      DialogOption(value: LayoutMode.tv, title: t.settings.layoutModeTv, subtitle: t.settings.layoutModeTvDescription),
      DialogOption(
        value: LayoutMode.desktop,
        title: t.settings.layoutModeDesktop,
        subtitle: t.settings.layoutModeDesktopDescription,
      ),
      DialogOption(
        value: LayoutMode.tablet,
        title: t.settings.layoutModeTablet,
        subtitle: t.settings.layoutModeTabletDescription,
      ),
      DialogOption(
        value: LayoutMode.phone,
        title: t.settings.layoutModePhone,
        subtitle: t.settings.layoutModePhoneDescription,
      ),
    ],
    onAfterWrite: (value) {
      PlatformDetector.setLayoutMode(value);
      restartApp(context);
    },
  );

  String _visualEffectsLabel(VisualEffectsSetting value) => switch (value) {
    VisualEffectsSetting.auto => t.settings.visualEffectsAuto,
    VisualEffectsSetting.full => t.settings.visualEffectsFull,
    VisualEffectsSetting.reduced => t.settings.visualEffectsReduced,
  };

  Widget _themeVariantSelector(BuildContext context) => SettingSelectionTile<AppThemeVariant>(
    pref: SettingsService.appThemeVariant,
    icon: Symbols.palette_rounded,
    title: t.settings.appThemeVariant,
    // Through the host gate, so a carried-in redesign value names the theme
    // that is actually drawn rather than one this build cannot show.
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
      // Offered on every host today; the gate is [redesignOfferedHere].
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

  String _glasAccentLabel(GlasAccent value) => switch (value) {
    GlasAccent.eisblau => t.settings.glasAccentEisblau,
    GlasAccent.mint => t.settings.glasAccentMint,
    GlasAccent.flieder => t.settings.glasAccentFlieder,
    GlasAccent.grau => t.settings.glasAccentGrau,
    GlasAccent.rot => t.settings.glasAccentRot,
    GlasAccent.plebz => t.settings.glasAccentPlebz,
  };

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

  String _glasAccentDescription(GlasAccent value) => switch (value) {
    GlasAccent.eisblau => t.settings.glasAccentEisblauDescription,
    GlasAccent.mint => t.settings.glasAccentMintDescription,
    GlasAccent.flieder => t.settings.glasAccentFliederDescription,
    GlasAccent.grau => t.settings.glasAccentGrauDescription,
    GlasAccent.rot => t.settings.glasAccentRotDescription,
    GlasAccent.plebz => t.settings.glasAccentPlebzDescription,
  };

  Widget _visualEffectsSelector(BuildContext context) => SettingSelectionTile<VisualEffectsSetting>(
    pref: SettingsService.visualEffects,
    icon: Symbols.animation_rounded,
    title: t.settings.visualEffects,
    subtitleBuilder: _visualEffectsLabel,
    options: [
      DialogOption(
        value: VisualEffectsSetting.auto,
        title: t.settings.visualEffectsAuto,
        subtitle: t.settings.visualEffectsAutoDescription,
      ),
      DialogOption(value: VisualEffectsSetting.full, title: t.settings.visualEffectsFull),
      DialogOption(
        value: VisualEffectsSetting.reduced,
        title: t.settings.visualEffectsReduced,
        subtitle: t.settings.visualEffectsReducedDescription,
      ),
    ],
  );
}
