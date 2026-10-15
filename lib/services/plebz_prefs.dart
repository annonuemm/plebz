import 'dart:async';

import '../focus/remote_keys.dart';
import '../media/library_copy_quality.dart';
import '../media/watchlist_filter.dart';
import '../media/year_filter.dart';
import '../profiles/profile.dart';
import '../utils/platform_detector.dart';
import '../utils/plebz_device.dart';
import 'base_shared_preferences_service.dart';
import 'plebz_update_service.dart' show PlebzUpdateOffer;
import 'recommendations_service.dart';
import 'sensitive_prefs.dart';
import 'settings_service.dart';

/// Which visual language the app wears. Same screens, same paths, same
/// functions — only the surface differs.
enum AppThemeVariant {
  /// What the app has always looked like: filled bold symbols, the platform's
  /// own typeface, tight spacing.
  standard,

  /// The redesign: three typefaces with one job each, generous corners taken
  /// from the posters, no shadows, the navigation overhead — and its floating
  /// surfaces made of glass: the sheets, the bands, the up-next card and the
  /// player's control bar let the picture behind them through, with a sheen
  /// and a lit edge, and a firmer ground behind their words so a pale poster
  /// cannot wash them out.
  ///
  /// More than a palette — it also changes where navigation lives and how
  /// focus moves. Everything it adds sits in `lib/redesign/`; the other
  /// variants keep the screens they have.
  ///
  /// It had two siblings, "Ocker" and "Schwarz", the same redesign filled
  /// instead of glass. They were retired; a stored one reads
  /// back as this ([PlebzPrefs.appThemeVariant]).
  ///
  /// Its colours are the viewer's to pick — see [GlasAccent].
  glas,

  /// "Redesign – Flach" (Plebz): the redesign's structure and focus as Glas
  /// has them, painted flat — no panes of glass, no sheen, no lit edges, no
  /// shadows. Rows are separated by space and type alone, focus is a solid
  /// white fill with the words on it turned dark, a poster's focus a white
  /// frame. One accent, any colour the viewer picks
  /// ([PlebzPrefs.flachAccent]).
  flach,
}

/// The accent "Redesign – Glas" is drawn in, chosen in the settings.
///
/// Each brings its own ground and ink, faintly of the same hue, so they read
/// as whole palettes rather than one palette with its accent swapped. [grau]
/// is the neutral one: no hue at all, the nearest to Apple's own glass.
/// [rot] keeps the neutral ground and ink and puts one red on them, after
/// Netflix: black, white and red. [plebz] is the fork's own, after its logo:
/// a near-black, violet, and the logo's gradient on the play buttons.
///
/// New ones go at the end: the stored value is the name, and an old one must
/// still read back as what it was.
enum GlasAccent { eisblau, mint, flieder, grau, rot, plebz }

/// The player IPTV channels use (Plebz): the main choice, or one of their own.
enum IptvPlayerChoice { sameAsFilms, exoPlayer, mpv }

/// [PlebzPrefs.liveTvSeamlessFullscreen] (Plebz): on unless the viewer
/// turned the live frame-rate match or live tunnelling on — either stops the
/// picture carrying on, and the settings never claim both.
class _SeamlessLivePicturePref extends BoolPref {
  const _SeamlessLivePicturePref() : super('live_tv_seamless_fullscreen', defaultValue: true);

  @override
  bool readFrom(BaseSharedPreferencesService svc) {
    if (svc.prefs.containsKey(key)) return super.readFrom(svc);
    final framesOn = svc.readNullableBool('match_content_frame_rate_live_tv') ?? false;
    final tunnelsOn = svc.readNullableBool('tunneled_playback_live_tv') ?? false;
    return !framesOn && !tunnelsOn;
  }
}

/// Plebz's own settings, kept out of [SettingsService] (an upstream file) so
/// a Plezy release merges without them in the way. `settings_service.dart`
/// exports this file: wherever [SettingsService] is in scope, so is this.
abstract final class PlebzPrefs {
  // The app and its look

  /// Which layout the app takes: its own guess, or the one the viewer forced.
  static const layoutMode = EnumPref<LayoutMode>(
    'layout_mode',
    values: LayoutMode.values,
    defaultValue: LayoutMode.auto,
  );

  /// The app's visual language. Off the shelf on a television (the TV
  /// layout, override included) it is the redesign, [AppThemeVariant.glas];
  /// everywhere else "Original", [AppThemeVariant.standard] — the redesign is
  /// drawn for a remote and a screen across the room, not for a phone.
  static AppThemeVariant _tvAwareAppThemeVariantDefault() =>
      PlatformDetector.isTV() ? AppThemeVariant.glas : AppThemeVariant.standard;
  static const appThemeVariant = EnumPref<AppThemeVariant>(
    'app_theme_variant',
    values: AppThemeVariant.values,
    defaultValueProvider: _tvAwareAppThemeVariantDefault,
    // The retired filled redesigns: whoever had one keeps the redesign.
    // "Klar", retired 2026-10-02, was a variant of the standard look.
    legacy: {'ocker': AppThemeVariant.glas, 'schwarz': AppThemeVariant.glas, 'klar': AppThemeVariant.standard},
  );

  /// Which of its palettes "Redesign – Glas" is drawn in. Asked only while
  /// that theme is the one chosen.
  static const glasAccent = EnumPref<GlasAccent>(
    'glas_accent',
    values: GlasAccent.values,
    defaultValue: GlasAccent.eisblau,
  );

  /// Under "Redesign – Glas": let the focus capsule glide from word to word —
  /// swallowing the mark on show as it passes — and the words' ink fade, even
  /// where the visual effects are reduced. Those two cost little; the rest of
  /// what "full" turns on is what makes a weak box slow, and this keeps them
  /// apart.
  static const glasSmoothFocus = BoolPref('glas_smooth_focus', defaultValue: false);

  /// Under "Redesign – Glas": the focus edge's glint goes slowly round it.
  /// Off by default — a turning edge draws a frame every vsync while it turns,
  /// which a weak box can feel beside scrolling and a playing preview.
  static const glasSpinningFocus = BoolPref('glas_spinning_focus', defaultValue: false);

  /// Under "Redesign – Glas": "Liquid Glass" — the panes and bands blur and
  /// brighten what lies behind them, as Apple's glass does, and their edge
  /// catches the light on both sides. Apple builds only (Apple TV, Mac, later
  /// iPhone and iPad), never the APK. Off by default: a blur is redrawn every
  /// frame for as long as the glass is up, which is the cost the plain glass
  /// was drawn to avoid (see `OckerLiquidGlass`).
  static const glasLiquid = BoolPref('glas_liquid', defaultValue: false);

  /// Under "Redesign – Glas" where there is no Liquid Glass (Android): the
  /// navigation, the menus and the capsules as fake glass — a sheen and a lit
  /// rim, no blur. Off, they are flat, as on Apple's builds with Liquid Glass
  /// switched off (the user's call, 2026-10-14). On by default.
  static const glasFakeGlass = BoolPref('glas_fake_glass', defaultValue: true);

  /// Under "Redesign – Glas" on the television: the rail's strip of symbols
  /// stays on show at the left, as it did before Glas hid its shut rail after
  /// Apple's TV app (the user's call, 2026-10-13: for those who want the
  /// symbols in view). Off by default: the rail hides itself and a capsule at
  /// the page's top left names the place on show.
  static const glasRailSymbolsPinned = BoolPref('glas_rail_symbols_pinned', defaultValue: false);

  /// On the television, in every look: a D-pad step glides the rows and the
  /// posters as the Apple TV does (half a second) rather than in Plezy's
  /// quick Android step (the user's call, 2026-10-13). On by default; off for
  /// a box that stutters. The Apple TV always glides.
  static const smoothScroll = BoolPref('smooth_scroll', defaultValue: true);

  /// Under glass, the ground takes the colours of the Plex title holding focus
  /// — Plex's "UltraBlur". A test, off until switched on.
  static const glasUltraBlur = BoolPref('glas_ultra_blur', defaultValue: false);

  /// The same under "Flach". A switch of its own, so each redesign keeps the
  /// viewer's choice in each. Off to start with: Flach starts on its own
  /// ground, the accent's (the user's call — it was on for a build).
  static const flachUltraBlur = BoolPref('flach_ultra_blur', defaultValue: false);

  /// The poster-colour switch of the redesign [flat] says.
  static BoolPref ultraBlurFor({required bool flat}) => flat ? flachUltraBlur : glasUltraBlur;

  /// The accent of "Redesign – Flach", as `#RRGGBB`: any colour, the viewer's
  /// pick. Starts on the logo's violet.
  static const flachAccent = StringPref('flach_accent', defaultValue: '#A866EE');

  /// A ready-made "Flach" look — accent and ground together ([flachPresets],
  /// by id). Empty for the viewer's own: [flachAccent] and the shared
  /// redesign ground. Flach's alone, so Glas keeps its ground.
  static const flachPreset = StringPref('flach_preset', defaultValue: '');

  /// The redesigns' ground as an off-black (#121212) in place of the design's
  /// own, while [SettingsService.themeMode] is not OLED — which is black, and
  /// wins. Its own switch rather than a fifth [ThemeMode]: the standard
  /// design's light and dark know nothing of it.
  static const redesignOffBlack = BoolPref('redesign_off_black', defaultValue: false);

  /// The redesigns' ground in a colour of the viewer's own
  /// ([redesignGroundColour]), while [SettingsService.themeMode] is not OLED.
  /// Wins over [redesignOffBlack].
  static const redesignCustomGround = BoolPref('redesign_custom_ground', defaultValue: false);

  /// That colour, as `#RRGGBB`, kept while another ground is chosen so a
  /// return to it starts where it was left.
  static const redesignGroundColour = StringPref('redesign_ground_colour', defaultValue: '#1B1726');

  /// Under Glas on a television, a show's seasons as a row of tabs over the
  /// one row of the chosen season's episodes, instead of a row per season.
  /// Off by default: every season its own row, one under the other.
  static const glasSeasonTabs = BoolPref('glas_season_tabs', defaultValue: false);

  /// The same under "Flach", a switch of its own. Off by default too: the rows
  /// one under the other are the default in both (the user's call; the tabs
  /// were Flach's only arrangement from 686 to 1.11.0).
  static const flachSeasonTabs = BoolPref('flach_season_tabs', defaultValue: false);

  /// The season-tab switch of the redesign [flat] says.
  static BoolPref seasonTabsFor({required bool flat}) => flat ? flachSeasonTabs : glasSeasonTabs;

  /// Under glass on a television, the column down the right of a library and
  /// the watchlist describing the focused title. Off, its width goes to more
  /// posters in each row.
  static const glasDetailPanel = BoolPref('glas_detail_panel', defaultValue: true);

  /// Type with the device's own on-screen keyboard rather than Plebz's.
  ///
  /// On by default: the device's keyboard is what a TV remote's OK button
  /// raises without anyone teaching it to, and remotes differ in which key
  /// they send. Plebz's own keyboard is the fallback for a device whose
  /// keyboard does not appear at all.
  static const useSystemTvKeyboard = BoolPref('use_system_tv_keyboard', defaultValue: true);

  /// The Plebz build this device last started, so the first start of a newer
  /// one can say it was updated. Per device: not exported with the settings.
  static const plebzLastSeenBuild = IntPref('plebz_last_seen_build');

  /// How often the start-up check shows an available update. Exported: a
  /// choice about the viewer's patience, not about this device.
  static const plebzUpdateOffer = EnumPref<PlebzUpdateOffer>(
    'plebz_update_offer',
    values: PlebzUpdateOffer.values,
    defaultValue: PlebzUpdateOffer.whenAvailable,
  );

  /// When an available update was last shown, in milliseconds since the
  /// epoch; 0 for never. Per device, like [plebzLastSeenBuild].
  static const plebzLastUpdateOfferAt = IntPref('plebz_last_update_offer_at');

  /// Plebz: whether the first-run setup (look, sources, services) has been
  /// through once. Device-local on purpose — in no export or reset list: a
  /// restored backup or a settings reset must not send someone back through it.
  static const onboardingCompleted = BoolPref('onboarding_completed');

  // Home and navigation

  /// Whether the Sport destination — the three German leagues' matchdays and
  /// tables — is shown. Off by default: it is the one destination that talks to
  /// a server the viewer did not set up themselves (OpenLigaDB), so it is
  /// something to switch on rather than something to discover.
  static const showSportTab = BoolPref('show_sport_tab');

  /// The viewer's club on the Sport page: its game of the matchday on show
  /// stands on a stage over the others. An OpenLigaDB team id, 0 for none —
  /// and its name, for the settings row while the clubs are not loaded.
  static const sportFavouriteClub = IntPref('sport_favourite_club');
  static const sportFavouriteClubName = StringPref('sport_favourite_club_name', defaultValue: '');

  /// The "because you watched" row under Continue Watching.
  ///
  /// Built out of the user's own libraries: a few titles they marked or
  /// watched, each handed to the server's own "more like this". It costs a
  /// handful of requests after the page is already up, so it is a switch.
  static const showRecommendationsRow = BoolPref('show_recommendations_row', defaultValue: true);

  /// The "Jetzt live" row under Continue Watching: today's games and the
  /// favourite channels with what is on them. Off, the home screen neither
  /// shows it nor loads the guide and fixtures behind it.
  static const showLiveNowRow = BoolPref('show_live_now_row', defaultValue: true);

  /// Which servers the recommendation row draws on. Only meaningful while
  /// [showRecommendationsRow] is on.
  static const recommendationsSource = EnumPref<RecommendationsSource>(
    'recommendations_source',
    values: RecommendationsSource.values,
    defaultValue: RecommendationsSource.all,
  );

  /// Chrome in the Home screen's action bar. Each is a whole feature's entry
  /// point, so they are switched independently rather than as one group.
  static const showWatchTogetherAction = BoolPref('show_watch_together_action', defaultValue: true);
  static const showCompanionRemoteAction = BoolPref('show_companion_remote_action', defaultValue: true);
  static const showServerActivitiesAction = BoolPref('show_server_activities_action', defaultValue: true);

  /// Whether the home screen's toolbar stays invisible until the remote goes
  /// up to it.
  ///
  /// The buttons keep their place and stay reachable — they are simply not
  /// painted while focus is in the content, which is nearly always. Has no
  /// effect where there is no focus to speak of: on touch the row is drawn as
  /// before, or it could never be tapped.
  static const hideHomeActionsUntilFocus = BoolPref('hide_home_actions_until_focus');

  /// Whether the home screen and Explore show a title's logo in the spotlight
  /// at the top. Off, it sets the title as type; a title's own page keeps its
  /// logo either way.
  static const showHomeTitleLogos = BoolPref('show_home_title_logos', defaultValue: true);

  // Libraries and detail pages

  /// The download button on a detail page. Its own switch because a library
  /// watched only at home never needs it, and it sits in the action row where
  /// space is scarce. Downloads stay reachable from the item's ⋮ menu.
  static const showDownloadAction = BoolPref('show_download_action', defaultValue: true);

  /// Whether a library shows its Playlists tab.
  ///
  /// On by default, because a library that has playlists should say so. Off is
  /// for the setups where it never will: an empty tab is a destination that
  /// always disappoints, and it sits on the same row as the ones that do not.
  static const showLibraryPlaylistsTab = BoolPref('show_library_playlists_tab', defaultValue: true);

  /// Whether the detail page names the audio track and subtitles Play would
  /// start with.
  ///
  /// It answers "what will I hear" before you press anything, which is worth a
  /// line on a multi-language library and worth nothing at all on a library
  /// with one. Off, the corner it sits in is simply empty; nothing about
  /// playback changes.
  static const showPlaybackTracksStatus = BoolPref('show_playback_tracks_status', defaultValue: true);

  /// Show the rest of an actor's filmography on their page, greyed out.
  ///
  /// Off by default and needs the TMDB key: a media server only knows which of
  /// *your* titles a person appears in, so everything beyond that is an
  /// outside lookup the viewer should opt into.
  static const showActorFilmography = BoolPref('show_actor_filmography');

  /// Release-year range for films, and the same for series. Zero means the
  /// field is empty, which is an open end rather than the year zero.
  ///
  /// Always in force while browsing a library — that is where a year filter
  /// is expected to sit. Everywhere else it applies only with
  /// [yearFilterBeyondLibraries], because a home screen quietly missing half
  /// its rows reads as a broken app, not as a filter.
  static const yearFilterMovieFrom = IntPref('year_filter_movie_from');
  static const yearFilterMovieTo = IntPref('year_filter_movie_to');
  static const yearFilterShowFrom = IntPref('year_filter_show_from');
  static const yearFilterShowTo = IntPref('year_filter_show_to');
  static const yearFilterBeyondLibraries = BoolPref('year_filter_beyond_libraries');

  /// Carry a watched mark over to every other copy of the same movie: another
  /// library on the same server (a 4K and an HD section hold the film twice)
  /// and every other connected server. Copies are matched by external id, so
  /// a title that only looks similar is never touched.
  ///
  /// Off by default, and deliberately so: it writes to servers the viewer did
  /// not just watch on, which nobody should get without asking for it.
  static const mirrorWatchedAcrossServers = BoolPref('mirror_watched_across_servers');

  /// Fill in missing clear logos from TMDB.
  ///
  /// Plex only carries a logo when its agent or a poster tool supplied one, so
  /// most libraries show the plain title text where a logo belongs. Off by
  /// default: it needs the user's own TMDB key, and an unconfigured switch that
  /// silently does nothing is worse than one that has to be turned on.
  static const tmdbLogosEnabled = BoolPref('tmdb_logos_enabled');

  /// The user's own TMDB v3 API key. Reset but not exported: it belongs to
  /// one person's TMDB account, so it must not travel inside a settings
  /// export. Sealed at rest like the other keys the
  /// user types in.
  static const tmdbApiKey = SealedStringPref('tmdb_api_key');

  // Explore and the watchlist

  /// Which provider the Watchlist tab reads, independent of the source the
  /// Explore tab is switched to. Empty means "not chosen yet"; the tab then
  /// falls back to the first connected provider that has a watchlist.
  static const watchlistSource = StringPref('watchlist_source', defaultValue: '');

  /// How the Watchlist tab narrows what it shows: by kind of title, and by
  /// whether it has been watched. Kept like [watchlistSource] — the tab is a
  /// destination the viewer returns to, and a list they left showing films
  /// should still be showing films. Both choices are named in the app bar,
  /// so neither can hide a list without saying so.
  static const watchlistTypeFilter = EnumPref<WatchlistTypeFilter>(
    'watchlist_type_filter',
    values: WatchlistTypeFilter.values,
    defaultValue: WatchlistTypeFilter.all,
  );
  static const watchlistStatusFilter = EnumPref<WatchlistStatusFilter>(
    'watchlist_status_filter',
    values: WatchlistStatusFilter.values,
    defaultValue: WatchlistStatusFilter.any,
  );

  /// Collapse an item's attributed scores (IMDb, TMDB, both Rotten Tomatoes
  /// panels, ...) into a single mean instead of a badge per source.
  ///
  /// On by default (fork): one score leaves the first row of facts the room
  /// its genres need.
  static const averageRatings = BoolPref('average_ratings', defaultValue: true);

  /// The catalog detail page's crew grid (director, writer, producer). On by
  /// default; a long-running series lists dozens of names across three rows.
  static const showCatalogDetailCrew = BoolPref('show_catalog_detail_crew', defaultValue: true);

  /// The catalog detail page's fact grid (original title, alternative titles,
  /// country, studios, budget, ...). On by default; the alternative-title list
  /// alone can run to dozens of localized titles.
  static const showCatalogDetailFacts = BoolPref('show_catalog_detail_facts', defaultValue: true);

  /// Which library copy the Explore detail page ranks first and opens from
  /// the button beside the poster (fork addition).
  static const bestCopyPreference = EnumPref<BestCopyPreference>(
    'best_copy_preference',
    values: BestCopyPreference.values,
    defaultValue: BestCopyPreference.best,
  );

  /// Fetch each Seerr show's episode count and next air date so the poster
  /// badges can carry them.
  ///
  /// Off by default because it is not free: Seerr's discover response carries
  /// neither value — Plex ships both inline with its hubs, TMDB's discover
  /// endpoint ships neither — so every show on a row costs one detail request.
  /// Answers are cached for the session, and movies are never asked about
  /// since no badge here applies to them.
  static const seerrCardEpisodeFacts = BoolPref('seerr_card_episode_facts');

  /// The profiles whose watch state Simkl keeps rather than the server (fork
  /// addition; see `watch_progress/tracker_progress_controller.dart`).
  static const simklLedProfiles = StringListPref('simkl_led_profiles');

  // Playback

  /// The "up next" panel that appears over the last minutes of an episode.
  ///
  /// Separate from [autoPlayNextEpisode]: that one decides what happens when
  /// an episode ends, this one whether anything is offered before it does.
  static const showUpNextPanel = BoolPref('show_up_next_panel', defaultValue: true);

  /// What closes an episode that has a next one (Plebz, the user's call
  /// 2026-10-14): the "up next" panel, the full-screen end card, or Plezy's own
  /// prompt. Until chosen it follows [showUpNextPanel], the switch it grew
  /// out of, so nobody's choice changes with the update.
  static final endOfEpisodeStyle = EnumPref<EndOfEpisodeStyle>(
    'end_of_episode_style',
    values: EndOfEpisodeStyle.values,
    defaultValueProvider: () => (SettingsService.instanceOrNull?.read(showUpNextPanel) ?? true)
        ? EndOfEpisodeStyle.upNextPanel
        : EndOfEpisodeStyle.plezyPrompt,
  );

  /// From how far into an episode Back opens the end card instead of leaving
  /// the player, in percent of its runtime. Offered at [endCardBackFromChoices].
  static const endCardBackFrom = IntPref('end_card_back_from', defaultValue: 95);

  static const endCardBackFromChoices = [90, 93, 95, 97];

  /// Refuse Dolby Vision output and play the base layer instead.
  ///
  /// media3 already falls back on its own when the *display* reports no Dolby
  /// Vision support, which is the ordinary case behind a set that cannot show
  /// it. This is for the chain that claims support and handles it badly — a
  /// receiver in the middle, or a set whose Dolby Vision mode looks worse than
  /// its HDR10 one. Profile 5 carries no base layer and is left alone.
  static const disableDolbyVision = BoolPref('disable_dolby_vision');

  /// mpv on Android: the subtitle plane covers the picture only and the bars
  /// stay empty, as on ExoPlayer, so they show the box's own black. mpv
  /// otherwise paints them black, which an Amlogic box shows dark gray in
  /// Dolby Vision for some titles, so it is on there by default (the user's
  /// call, 2026-10-15). Subtitles then never sit in the bars.
  static const mpvOsdPictureOnly = BoolPref('mpv_osd_picture_only', defaultValueProvider: PlebzDevice.isAmlogic);

  /// Live channels this device's hardware decoder showed no picture for, which
  /// therefore open in software here (see `live_software_decode.dart`).
  ///
  /// About this device's decoder, not the viewer's taste: deliberately in
  /// neither export list, so a backup restored on a box that decodes them fine
  /// does not carry a phone's answer over.
  static const liveSoftwareDecodeChannels = StringListPref('live_software_decode_channels');

  /// Whether the HDMI output follows the video's resolution.
  ///
  /// Off by default. On, the player asks for the smallest display mode the
  /// video fits into untouched, so the television scales instead of the box —
  /// most sets scale better than a streaming stick does. Restored when
  /// playback ends. Only devices that publish more than one display mode can
  /// do anything with it.
  static const matchDisplayResolution = BoolPref('match_display_resolution');

  /// Whether [matchContentFrameRate] also applies to live TV.
  ///
  /// Off by default (Plebz): switching the panel's mode costs a black screen
  /// of a second or two, which on a film happens once and on a channel
  /// happens at every zap, and it would stop the guide's preview growing into
  /// full screen ([liveTvSeamlessFullscreen], on by default). Providers also
  /// declare frame rates loosely, so the rate the app switches to is not
  /// always the one that arrives.
  ///
  /// Ignored while [matchContentFrameRate] is off, which turns it off
  /// everywhere.
  static const matchContentFrameRateLiveTv = BoolPref('match_content_frame_rate_live_tv');

  /// Whether this route should negotiate the display's frame rate.
  ///
  /// The master switch decides at all; [matchContentFrameRateLiveTv] decides
  /// whether it reaches a live route. A function rather than a check at each
  /// call site, so the rule is stated once — the player asks in two places and
  /// they must not drift.
  static bool matchContentFrameRateFor({required bool isLive, required bool enabled, required bool enabledForLiveTv}) =>
      enabled && (!isLive || enabledForLiveTv);

  /// Whether [tunneledPlayback] also applies to live TV.
  ///
  /// Off by default, and the two are separate because they are different
  /// workloads. Tunneling earns its keep on 4K high-frame-rate files, where
  /// the hardware meets frame deadlines a software release path can miss. A
  /// live stream is the opposite case: the picture is ordinary, and the
  /// transport streams IPTV providers send carry timestamp discontinuities
  /// that can wedge a tunneled pipeline — where the app cannot even observe
  /// the wedge, because a tunneled session reports no rendered frames.
  ///
  /// Ignored while [tunneledPlayback] is off, which turns it off everywhere.
  static const tunneledPlaybackLiveTv = BoolPref('tunneled_playback_live_tv');

  /// Whether a session on this route should run tunnelled.
  ///
  /// The master switch decides at all; [tunneledPlaybackLiveTv] decides whether
  /// it reaches a live route. Kept as a function rather than a read at the call
  /// site so the rule is stated once and can be checked without a player.
  static bool tunneledPlaybackFor({required bool isLive, required bool enabled, required bool enabledForLiveTv}) =>
      enabled && (!isLive || enabledForLiveTv);

  /// The player for IPTV channels, in the guide's preview and full screen
  /// (Plebz). Off its default, [useExoPlayer] keeps films, shows and a media
  /// server's live TV while IPTV plays on the other backend — on the user's
  /// box the two do better at different things.
  static const iptvPlayerBackend = EnumPref<IptvPlayerChoice>(
    'iptv_player_backend',
    values: IptvPlayerChoice.values,
    defaultValue: IptvPlayerChoice.sameAsFilms,
  );

  /// What the remote's colour keys do in the player (fork addition). Red,
  /// green, yellow, blue: by default the order most remotes print beside them.
  static const remoteRedButton = EnumPref<RemoteButtonFunction>(
    'remote_red_button',
    values: RemoteButtonFunction.values,
    defaultValue: RemoteButtonFunction.subtitles,
  );
  static const remoteGreenButton = EnumPref<RemoteButtonFunction>(
    'remote_green_button',
    values: RemoteButtonFunction.values,
    defaultValue: RemoteButtonFunction.audioTrack,
  );
  static const remoteYellowButton = EnumPref<RemoteButtonFunction>(
    'remote_yellow_button',
    values: RemoteButtonFunction.values,
    defaultValue: RemoteButtonFunction.skipMarker,
  );
  static const remoteBlueButton = EnumPref<RemoteButtonFunction>(
    'remote_blue_button',
    values: RemoteButtonFunction.values,
    defaultValue: RemoteButtonFunction.controls,
  );
  static EnumPref<RemoteButtonFunction> remoteButtonPref(RemoteColourKey key) => switch (key) {
    RemoteColourKey.red => remoteRedButton,
    RemoteColourKey.green => remoteGreenButton,
    RemoteColourKey.yellow => remoteYellowButton,
    RemoteColourKey.blue => remoteBlueButton,
  };

  // Live TV and IPTV

  /// Whether the guide keeps its day-and-time strip. Off, the guide opens on
  /// now and is travelled with the D-pad alone.
  static const liveTvGuideTimeNavigation = BoolPref('live_tv_guide_time_navigation', defaultValue: true);

  /// Whether the guide's channel column sets each channel's name under a
  /// smaller logo (a viewer's wish, 2026-10-14). The cells keep their size;
  /// off by default, the logo alone as before.
  static const liveTvGuideChannelNames = BoolPref('live_tv_guide_channel_names');

  /// Whether the guide's playing preview grows into the full-screen player —
  /// and back into its box on Back — as the very same picture, instead of
  /// being stopped and opened again (Plebz). IPTV on Android only; see
  /// `LivePictureHandover`.
  ///
  /// The preview plays on the television's video surface, behind a hole the
  /// guide leaves for it, and the growth moves that surface with the page —
  /// nothing moves between surfaces, and the box's own deinterlacer serves
  /// interlaced channels in the preview too.
  ///
  /// On by default. What would switch the display under the picture goes
  /// off for live TV with it: turning this on turns off
  /// [matchContentFrameRateLiveTv] and [tunneledPlaybackLiveTv] (turning
  /// either back on turns this off), and live TV skips
  /// [matchDisplayResolution] while it is on.
  static const liveTvSeamlessFullscreen = _SeamlessLivePicturePref();

  /// Whether the sidebar's Live TV section is unfolded, showing what used to
  /// be the screen's own app-bar actions.
  static const liveTvSectionExpanded = BoolPref('live_tv_section_expanded');

  /// How many days a stored IPTV playlist and guide stay good for.
  ///
  /// Neither changes by the hour, and both are expensive: a playlist runs to
  /// tens of thousands of lines and a guide into the megabytes. A manual
  /// refresh ignores this and refetches at once.
  static const iptvRefreshIntervalDays = IntPref('iptv_refresh_interval_days', defaultValue: 1);

  /// Whether an IPTV playlist's repeats of the same channel are shown as one.
  ///
  /// Off by default: it changes which channels exist, and a guide that
  /// silently loses rows on an update would be worse than a busy one.
  static const iptvMergeDuplicateChannels = BoolPref('iptv_merge_duplicate_channels');

  /// Whether the country code a provider puts in front of every group name is
  /// left off the group bar. Display only — the raw name stays the key.
  static const iptvHideGroupCountryPrefix = BoolPref('iptv_hide_group_country_prefix');

  /// Whether a channel whose own logo and whose guide's both fail to load is
  /// looked up in the public "tv-logos" collection on GitHub
  /// ([PublicLogoIndex]). Off by default: GitHub learns which logos are asked
  /// for.
  static const iptvPublicLogoFallback = BoolPref('iptv_public_logo_fallback');

  /// Whether a dark channel logo — a black or navy mark on transparency — is
  /// drawn light on a dark tile ([channelLogoToneTargetFor]). Off by default:
  /// it recolours the provider's artwork, which is a matter of taste.
  static const iptvBrightenDarkLogos = BoolPref('iptv_brighten_dark_logos');

  /// The profile's configured IPTV sources, encoded by [IptvSource.encodeList].
  /// Not in [portablePrefs]: an Xtream source carries a panel password.
  static NullableStringPref iptvSourcesForProfile(String profileId) {
    if (profileId.trim().isEmpty) {
      throw ArgumentError.value(profileId, 'profileId', 'Must not be empty');
    }
    return NullableStringPref(profileScopedPrefsKey(profileId, iptvSourcesBaseKey));
  }

  /// The profile's Live TV arrangement — hidden groups and channels plus
  /// their order, encoded by [LiveTvChannelLayout.encode]. Profile-scoped, so
  /// it cannot sit in [portablePrefs] (that list is built without a profile).
  static NullableStringPref liveTvChannelLayoutForProfile(String profileId) {
    if (profileId.trim().isEmpty) {
      throw ArgumentError.value(profileId, 'profileId', 'Must not be empty');
    }
    return NullableStringPref(profileScopedPrefsKey(profileId, liveTvChannelLayoutBaseKey));
  }

  /// Reset and exported, as [SettingsService]'s own group of the same kind.
  static final List<Pref<Object?>> resetAndPortable = [
    mirrorWatchedAcrossServers,
    matchContentFrameRateLiveTv,
    tunneledPlaybackLiveTv,
    disableDolbyVision,
    mpvOsdPictureOnly,
    bestCopyPreference,
    remoteRedButton,
    remoteGreenButton,
    remoteYellowButton,
    remoteBlueButton,
    showUpNextPanel,
    endOfEpisodeStyle,
    endCardBackFrom,
    iptvPlayerBackend,
    showSportTab,
    sportFavouriteClub,
    sportFavouriteClubName,
    tmdbLogosEnabled,
    showRecommendationsRow,
    showLiveNowRow,
    recommendationsSource,
    useSystemTvKeyboard,
    showActorFilmography,
    seerrCardEpisodeFacts,
    appThemeVariant,
    glasAccent,
    flachAccent,
    redesignOffBlack,
    redesignCustomGround,
    redesignGroundColour,
    glasSmoothFocus,
    glasUltraBlur,
    flachUltraBlur,
    glasSeasonTabs,
    flachSeasonTabs,
    flachPreset,
    glasDetailPanel,
    glasSpinningFocus,
    glasLiquid,
    glasFakeGlass,
    glasRailSymbolsPinned,
    smoothScroll,
    showLibraryPlaylistsTab,
    showPlaybackTracksStatus,
    showHomeTitleLogos,
    hideHomeActionsUntilFocus,
    plebzUpdateOffer,
  ];

  /// Exported but left alone by a reset.
  static final List<Pref<Object?>> portableOnly = [
    liveTvGuideTimeNavigation,
    liveTvGuideChannelNames,
    liveTvSeamlessFullscreen,
    iptvRefreshIntervalDays,
    iptvMergeDuplicateChannels,
    iptvHideGroupCountryPrefix,
    iptvPublicLogoFallback,
    iptvBrightenDarkLogos,
    yearFilterMovieFrom,
    yearFilterMovieTo,
    yearFilterShowFrom,
    yearFilterShowTo,
    yearFilterBeyondLibraries,
    liveTvSectionExpanded,
    matchDisplayResolution,
  ];
}

/// The reads that combine Plebz's settings, on [SettingsService] itself.
extension PlebzSettingsReads on SettingsService {
  /// The film range as set, or an empty range when the fields are.
  YearRange get movieYearRange =>
      yearRangeFrom(read(PlebzPrefs.yearFilterMovieFrom), read(PlebzPrefs.yearFilterMovieTo));

  YearRange get showYearRange => yearRangeFrom(read(PlebzPrefs.yearFilterShowFrom), read(PlebzPrefs.yearFilterShowTo));

  /// True when either range would actually leave something out.
  bool get hasYearFilter => !movieYearRange.isEmpty || !showYearRange.isEmpty;

  /// The ranges as they apply outside the libraries: empty unless the switch
  /// is on, so every caller can ask without checking it first.
  YearRange get movieYearRangeBeyondLibraries =>
      read(PlebzPrefs.yearFilterBeyondLibraries) ? movieYearRange : YearRange.none;

  YearRange get showYearRangeBeyondLibraries =>
      read(PlebzPrefs.yearFilterBeyondLibraries) ? showYearRange : YearRange.none;

  /// Whether a session plays on ExoPlayer: an [iptv] one by
  /// [PlebzPrefs.iptvPlayerBackend], everything else by
  /// [SettingsService.useExoPlayer]. The one place the rule is stated, so the
  /// preview, the full-screen player and the hand-over between them can never
  /// pick different backends.
  bool useExoPlayerFor({required bool iptv}) {
    if (iptv) {
      switch (read(PlebzPrefs.iptvPlayerBackend)) {
        case IptvPlayerChoice.exoPlayer:
          return true;
        case IptvPlayerChoice.mpv:
          return false;
        case IptvPlayerChoice.sameAsFilms:
          break;
      }
    }
    return read(SettingsService.useExoPlayer);
  }

  /// Effective [PlebzPrefs.layoutMode], migrating the legacy
  /// [SettingsService.forceTvMode] boolean the first time it is seen so the
  /// settings screen reflects the forced TV layout instead of showing "auto".
  LayoutMode readLayoutMode() {
    var mode = read(PlebzPrefs.layoutMode);
    if (mode == LayoutMode.auto && read(SettingsService.forceTvMode)) {
      mode = LayoutMode.tv;
      unawaited(write(PlebzPrefs.layoutMode, mode));
      unawaited(write(SettingsService.forceTvMode, false));
    }
    return mode;
  }
}

/// What closes an episode that has a next one ([PlebzPrefs.endOfEpisodeStyle]).
enum EndOfEpisodeStyle {
  /// The "up next" panel over the picture, with the countdown on its button.
  upNextPanel,

  /// The full-screen end card: the playing episode shrunk to the left, the
  /// next one beside it.
  endCard,

  /// Plezy's own end-of-episode prompt.
  plezyPrompt,
}
