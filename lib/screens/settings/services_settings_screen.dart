import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../models/catalog/catalog_item.dart';
import '../../providers/seerr_account_provider.dart';
import '../../services/discord_rpc_service.dart';
import '../../services/settings_service.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/catalog_source_logo.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import '../../widgets/focusable_list_tile.dart';
import '../../widgets/setting_tile.dart';
import '../../widgets/settings_section.dart';
import 'seerr_connect_screen.dart';
import 'tmdb_settings_screen.dart';
import 'seerr_settings_screen.dart';
import 'tracker_service_info.dart';

/// Unified hub for all connected services: the watch-progress trackers
/// (Trakt, MyAnimeList, AniList, Simkl) and the Seerr request server. Each
/// row opens its service-specific settings screen.
class ServicesSettingsScreen extends StatelessWidget {
  const ServicesSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FocusedScrollScaffold(
      title: Text(t.services.title),
      slivers: [
        SliverList(
          delegate: SliverChildListDelegate([
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Text(
                t.services.hubSubtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
            SettingsGroup(
              children: [
                for (final info in TrackerServiceInfo.all) _TrackerHubRow(info),
                _seerr(),
                const _TmdbHubRow(),
              ],
            ),
            if (DiscordRPCService.isAvailable)
              SettingsGroup(
                title: t.services.integrations,
                children: [
                  SettingSwitchTile(
                    pref: SettingsService.enableDiscordRPC,
                    icon: Symbols.chat_rounded,
                    title: t.settings.discordRichPresence,
                    subtitle: t.settings.discordRichPresenceDescription,
                  ),
                ],
              ),
            const SizedBox(height: 24),
          ]),
        ),
      ],
    );
  }

  Widget _seerr() => Consumer<SeerrAccountProvider>(
    builder: (context, account, _) => _ServiceHubRow(
      leading: const CatalogSourceLogo(CatalogSourceId.seerr, size: 24),
      title: t.services.names.seerr,
      username: account.isConnected ? account.displayName : null,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => account.isConnected ? const SeerrSettingsScreen() : const SeerrConnectScreen(),
          ),
        );
      },
    ),
  );
}

/// Hub row for a watch tracker. Owns the `watch` on that service's account
/// provider so only this row rebuilds when the connection state changes.
class _TrackerHubRow extends StatelessWidget {
  final TrackerServiceInfo info;

  const _TrackerHubRow(this.info);

  @override
  Widget build(BuildContext context) {
    final connected = info.isConnected(context);
    return _ServiceHubRow(
      leading: CatalogSourceLogo(info.logoSource, size: 24),
      title: info.displayName,
      username: connected ? info.username(context) : null,
      onTap: () {
        if (connected) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => info.buildSettingsScreen()));
        } else {
          info.startConnection(context);
        }
      },
    );
  }
}

/// Hub row for the TMDB artwork fill-in. Not a tracker and not an account, so
/// it carries its own row: what matters here is whether a key is stored, not
/// who is signed in.
class _TmdbHubRow extends StatelessWidget {
  const _TmdbHubRow();

  @override
  Widget build(BuildContext context) {
    final key = SettingsService.instance.read(SettingsService.tmdbApiKey);
    final hasKey = (key ?? '').trim().isNotEmpty;
    return FocusableListTile(
      leading: const AppIcon(Symbols.imagesmode_rounded, fill: 1),
      title: Text(t.services.names.tmdb),
      subtitle: Text(hasKey ? t.services.tmdb.hubSubtitle : t.services.tmdb.apiKeyMissing),
      trailing: const AppIcon(Symbols.chevron_right_rounded, fill: 1),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TmdbSettingsScreen())),
    );
  }
}

class _ServiceHubRow extends StatelessWidget {
  final Widget leading;
  final String title;

  /// Non-null when connected. When null, the subtitle shows "Not connected".
  final String? username;

  final VoidCallback onTap;

  const _ServiceHubRow({required this.leading, required this.title, required this.username, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FocusableListTile(
      leading: leading,
      title: Text(title),
      subtitle: Text(username != null ? t.services.connectedAs(username: username!) : t.services.notConnected),
      trailing: const AppIcon(Symbols.chevron_right_rounded, fill: 1),
      onTap: onTap,
    );
  }
}
