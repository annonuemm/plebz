import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../focus/focusable_button.dart';
import '../../i18n/strings.g.dart';
import '../../navigation/profile_session_screen.dart';
import '../../profiles/active_profile_provider.dart';
import '../../profiles/profile.dart';
import '../../profiles/profile_registry.dart';
import '../../providers/iptv_sources_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../providers/seerr_account_provider.dart';
import '../../providers/trackers_provider.dart';
import '../../services/settings_service.dart';
import '../../utils/navigation_transitions.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/catalog_source_logo.dart';
import '../../widgets/focusable_list_tile.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import '../../widgets/setting_tile.dart';
import '../../widgets/settings_section.dart';
import '../../models/catalog/catalog_item.dart' show CatalogSourceId;
import '../auth_screen.dart';
import '../settings/add_connection_screen.dart';
import '../settings/iptv_settings_screen.dart';
import '../settings/plebz_settings_rows.dart';
import '../settings/seerr_connect_screen.dart';
import '../settings/seerr_settings_screen.dart';
import '../settings/simkl_progress_tile.dart';
import '../settings/tmdb_settings_screen.dart';
import '../settings/tracker_service_info.dart';

/// Plebz's first-run setup, in two halves split by what exists when:
///
/// 1. Before any source: [SetupWelcomeScreen], then [SetupLookScreen], then
///    the sign-in screen, which also offers "IPTV only" ([startIptvOnly]).
/// 2. Inside the session, once there is a profile to hang things on:
///    [SetupExtrasScreen] — more sources, services, extras — pushed by the
///    main screen while [SettingsService.onboardingCompleted] is unset.
///
/// From Settings, "Run setup again" walks the look and the extras once more.

/// Where the setup screen sends a start with no server connection at all.
enum EmptyStartRoute { setup, signIn, iptvSession }

/// A start with no server connection: an IPTV-only profile goes into its
/// session, a first run into the setup, anything else to sign-in.
EmptyStartRoute routeForEmptyStart({required bool onboardingCompleted, required bool activeProfileHasIptv}) {
  if (activeProfileHasIptv) return EmptyStartRoute.iptvSession;
  return onboardingCompleted ? EmptyStartRoute.signIn : EmptyStartRoute.setup;
}

/// Whether [profileId] has at least one IPTV source stored.
bool profileHasIptvSources(String? profileId) {
  if (profileId == null || profileId.trim().isEmpty) return false;
  final raw = SettingsService.instance.read(SettingsService.iptvSourcesForProfile(profileId));
  if (raw == null || raw.trim().isEmpty) return false;
  try {
    final decoded = jsonDecode(raw);
    return decoded is List && decoded.isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// "IPTV only": a local profile with no server behind it, made active, and
/// straight into its session — where [SetupExtrasScreen] asks for the playlist.
/// An existing local profile is reused rather than a second one made.
Future<void> startIptvOnly(BuildContext context) async {
  final registry = context.read<ProfileRegistry>();
  final activeProfiles = context.read<ActiveProfileProvider>();
  final navigator = Navigator.of(context);
  await activeProfiles.reloadFromStorage();
  var profile = activeProfiles.profiles.where((p) => p.isLocal && !p.isPinProtected).firstOrNull;
  if (profile == null) {
    final now = DateTime.now();
    await registry.upsert(
      Profile.local(
        id: 'local-${const Uuid().v4()}',
        displayName: t.plebz.defaultProfileName,
        sortOrder: now.millisecondsSinceEpoch,
        createdAt: now,
      ),
    );
    await activeProfiles.reloadFromStorage();
    profile = activeProfiles.profiles.where((p) => p.isLocal && !p.isPinProtected).firstOrNull;
  }
  if (profile == null) return;
  if (!await activeProfiles.activate(profile)) return;
  // Without a playlist yet, the session opens on the page that asks for one —
  // also when the setup was finished long ago and this comes from sign-in.
  if (!profileHasIptvSources(profile.id)) {
    await SettingsService.instance.write(SettingsService.onboardingCompleted, false);
  }
  await navigator.pushAndRemoveUntil(fadeRoute(const ProfileSessionScreen()), (_) => false);
}

/// Pushes the second half of the setup while it has not been finished.
Future<void> maybeContinueSetup(BuildContext context) async {
  if (SettingsService.instance.read(SettingsService.onboardingCompleted)) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SetupExtrasScreen()));
}

class SetupWelcomeScreen extends StatelessWidget {
  const SetupWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FocusedScrollScaffold(
      title: Text(t.plebz.welcomeTitle),
      automaticallyImplyLeading: false,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Center(child: SvgPicture.asset('assets/plezy_adaptive_foreground.svg', width: 160, height: 160)),
              const SizedBox(height: 16),
              Text(t.plebz.welcomeBody, style: theme.textTheme.bodyLarge, textAlign: TextAlign.center),
              const SizedBox(height: 32),
              _PrimaryButton(
                label: t.plebz.getStarted,
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: (_) => const SetupLookScreen(firstRun: true))),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

/// The look, applied as it is chosen. On a first run "Next" leads to signing
/// in; run again from Settings it leads on to the extras.
class SetupLookScreen extends StatelessWidget {
  const SetupLookScreen({super.key, required this.firstRun});

  final bool firstRun;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FocusedScrollScaffold(
      title: Text(t.plebz.lookTitle),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Text(t.plebz.lookBody, style: theme.textTheme.bodyLarge),
              ),
              SettingsGroup(children: plebzAppearanceRows()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: _PrimaryButton(
                  label: t.plebz.next,
                  onPressed: () {
                    final navigator = Navigator.of(context);
                    if (firstRun) {
                      // Signing in replaces itself with the session; nothing of
                      // the setup should wait underneath it.
                      navigator.pushAndRemoveUntil(fadeRoute(const AuthScreen()), (_) => false);
                    } else {
                      navigator.pushReplacement(MaterialPageRoute<void>(builder: (_) => const SetupExtrasScreen()));
                    }
                  },
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

/// More sources, services and extras, inside the session. Finishing needs a
/// source: a server, or for an IPTV-only profile at least one playlist.
class SetupExtrasScreen extends StatefulWidget {
  const SetupExtrasScreen({super.key});

  @override
  State<SetupExtrasScreen> createState() => _SetupExtrasScreenState();
}

class _SetupExtrasScreenState extends State<SetupExtrasScreen> {
  bool _hasSource(BuildContext context) {
    final servers = context.watch<MultiServerProvider?>()?.totalServerCount ?? 0;
    final iptv = context.watch<IptvSourcesProvider?>()?.sources.length ?? 0;
    return servers > 0 || iptv > 0;
  }

  Future<void> _finish() async {
    await SettingsService.instance.write(SettingsService.onboardingCompleted, true);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSource = _hasSource(context);
    final iptvCount = context.watch<IptvSourcesProvider?>()?.sources.length ?? 0;
    final simklConnected = context.watch<TrackersProvider?>()?.isSimklConnected ?? false;
    return PopScope(
      // Leaving with a source in place counts as done, so the page does not
      // come back at every start; without one it will, until there is one.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && hasSource) {
          SettingsService.instance.write(SettingsService.onboardingCompleted, true);
        }
      },
      child: FocusedScrollScaffold(
        title: Text(t.plebz.extrasTitle),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Text(t.plebz.extrasBody, style: theme.textTheme.bodyLarge),
                ),
                SettingsGroup(
                  title: t.plebz.sourcesGroup,
                  children: [
                    SettingNavigationTile(
                      icon: Symbols.live_tv_rounded,
                      title: t.iptv.title,
                      subtitle: iptvCount == 0 ? t.iptv.addPlaylistDescription : t.iptv.sourceCount(n: iptvCount),
                      destinationBuilder: (_) => const IptvSettingsScreen(),
                    ),
                    SettingNavigationTile(
                      icon: Symbols.add_link_rounded,
                      title: t.connections.addConnection,
                      subtitle: t.plebz.addConnectionDescription,
                      onTap: () {
                        final active = context.read<ActiveProfileProvider>().active;
                        Navigator.push(
                          context,
                          MaterialPageRoute<void>(builder: (_) => AddConnectionScreen(targetProfile: active)),
                        );
                      },
                    ),
                  ],
                ),
                // Several viewers on one server account each keep their own
                // progress through a Simkl account per profile (Plebz).
                SettingsGroup(
                  title: t.plebz.profilesGroup,
                  children: [
                    ListTile(
                      leading: const AppIcon(Symbols.group_rounded, fill: 1),
                      title: Text(t.plebz.profilesHint),
                      subtitle: simklConnected ? null : Text(t.plebz.profilesHintConnectFirst),
                    ),
                    if (simklConnected) const SimklProgressTile(),
                  ],
                ),
                SettingsGroup(
                  title: t.settings.services,
                  children: [
                    for (final info in TrackerServiceInfo.all) _TrackerRow(info),
                    const _SeerrRow(),
                    const _TmdbRow(),
                  ],
                ),
                SettingsGroup(
                  title: t.plebz.extrasGroup,
                  children: [
                    SettingSwitchTile(
                      pref: SettingsService.showSportTab,
                      icon: Symbols.sports_soccer_rounded,
                      title: t.settings.showSportTab,
                      subtitle: t.settings.showSportTabDescription,
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!hasSource) ...[
                        Text(t.plebz.addSourceFirst, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                      ],
                      _PrimaryButton(label: t.plebz.finish, onPressed: hasSource ? _finish : null),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FocusableButton(
      onPressed: onPressed,
      useBackgroundFocus: true,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
        child: Text(label),
      ),
    );
  }
}

class _TrackerRow extends StatelessWidget {
  const _TrackerRow(this.info);

  final TrackerServiceInfo info;

  @override
  Widget build(BuildContext context) {
    final connected = info.isConnected(context);
    return FocusableListTile(
      leading: CatalogSourceLogo(info.logoSource, size: 24),
      title: Text(info.displayName),
      subtitle: Text(
        connected ? t.services.connectedAs(username: info.username(context) ?? '') : t.services.notConnected,
      ),
      trailing: const AppIcon(Symbols.chevron_right_rounded, fill: 1),
      onTap: () {
        if (connected) {
          Navigator.push(context, MaterialPageRoute<void>(builder: (_) => info.buildSettingsScreen()));
        } else {
          info.startConnection(context);
        }
      },
    );
  }
}

class _SeerrRow extends StatelessWidget {
  const _SeerrRow();

  @override
  Widget build(BuildContext context) {
    final account = context.watch<SeerrAccountProvider?>();
    if (account == null) return const SizedBox.shrink();
    return FocusableListTile(
      leading: const CatalogSourceLogo(CatalogSourceId.seerr, size: 24),
      title: Text(t.services.names.seerr),
      subtitle: Text(
        account.isConnected ? t.services.connectedAs(username: account.displayName ?? '') : t.services.notConnected,
      ),
      trailing: const AppIcon(Symbols.chevron_right_rounded, fill: 1),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => account.isConnected ? const SeerrSettingsScreen() : const SeerrConnectScreen(),
        ),
      ),
    );
  }
}

class _TmdbRow extends StatelessWidget {
  const _TmdbRow();

  @override
  Widget build(BuildContext context) {
    final key = SettingsService.instance.read(SettingsService.tmdbApiKey);
    final hasKey = (key ?? '').trim().isNotEmpty;
    return FocusableListTile(
      leading: const AppIcon(Symbols.imagesmode_rounded, fill: 1),
      title: Text(t.services.names.tmdb),
      subtitle: Text(hasKey ? t.services.tmdb.hubSubtitle : t.services.tmdb.apiKeyMissing),
      trailing: const AppIcon(Symbols.chevron_right_rounded, fill: 1),
      onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const TmdbSettingsScreen())),
    );
  }
}
