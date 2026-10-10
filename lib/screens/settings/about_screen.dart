import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:plezy/widgets/app_icon.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import '../../widgets/focusable_list_tile.dart';
import '../../widgets/setting_tile.dart' show settingSubtitle;
import '../../widgets/settings_section.dart';
import '../../i18n/strings.g.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/fork_identity.dart';
import 'licenses_screen.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static final Future<PackageInfo> _packageInfoFuture = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    // The fork's own name here, not Plezy's: this is where the app says
    // whose it is. Plezy's logo stays off the page for the same reason.
    const appName = forkAppName;

    return FutureBuilder<PackageInfo>(
      future: _packageInfoFuture,
      builder: (context, snapshot) {
        final appVersion = snapshot.data?.version ?? '';
        return FocusedScrollScaffold(
          title: Text(t.about.title),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Center(
                    child: Column(
                      children: [
                        const SizedBox(height: 24),
                        Text(appName, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: .bold)),
                        const SizedBox(height: 8),
                        Text(
                          t.about.versionLabel(version: appVersion),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: tokens(context).textMuted),
                        ),
                        Text(
                          t.about.basedOnUpstream(version: upstreamBaseVersion),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: tokens(context).textMuted),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          t.about.appDescription,
                          style: Theme.of(context).textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                        // TMDB's terms ask for its logo and this sentence in
                        // any app that shows its data. Up here rather than at
                        // the foot: a remote can only scroll as far as the
                        // last tile it can focus.
                        const SizedBox(height: 24),
                        SvgPicture.asset('assets/tmdb/tmdb_logo.svg', height: 12, semanticsLabel: 'TMDB'),
                        const SizedBox(height: 8),
                        Text(
                          tmdbAttributionNotice,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: tokens(context).textMuted),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  SettingsGroup(
                    margin: EdgeInsets.zero,
                    children: [
                      FocusableListTile(
                        leading: const AppIcon(Symbols.balance_rounded, fill: 1),
                        title: Text(t.about.appLicense),
                        subtitle: Text(t.about.appLicenseNotice(app: appName)),
                        trailing: const AppIcon(Symbols.chevron_right_rounded, fill: 1),
                        onTap: () => LicensesScreen.showPackage(context, forkAppName),
                      ),
                      FocusableListTile(
                        leading: const AppIcon(Symbols.description_rounded, fill: 1),
                        title: Text(t.about.openSourceLicenses),
                        subtitle: settingSubtitle(t.about.viewLicensesDescription),
                        trailing: const AppIcon(Symbols.chevron_right_rounded, fill: 1),
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const LicensesScreen()));
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                ]),
              ),
            ),
          ],
        );
      },
    );
  }
}
