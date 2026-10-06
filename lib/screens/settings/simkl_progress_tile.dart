import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../profiles/active_profile_provider.dart';
import '../../services/settings_service.dart';
import '../../services/trackers/tracker_constants.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/focusable_list_tile.dart';

/// The active profile's choice to keep its watch state in Simkl rather than
/// on the server (fork addition), with what that means for a shared account.
class SimklProgressTile extends StatelessWidget {
  const SimklProgressTile({super.key});

  @override
  Widget build(BuildContext context) {
    final profileId = context.watch<ActiveProfileProvider?>()?.activeId;
    final settings = SettingsService.instance;
    return ValueListenableBuilder<List<String>>(
      valueListenable: settings.listenable(SettingsService.simklLedProfiles),
      builder: (context, profiles, _) {
        final on = profileId != null && profiles.contains(profileId);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FocusableSwitchListTile(
              secondary: const AppIcon(Symbols.switch_account_rounded, fill: 1),
              title: Text(t.services.ownProgress),
              subtitle: Text(t.services.ownProgressDescription),
              value: on,
              onChanged: profileId == null ? null : (value) => _set(profileId, value, profiles),
            ),
            if (on)
              ListTile(
                leading: const AppIcon(Symbols.info_rounded, fill: 1),
                subtitle: Text(t.services.ownProgressNote),
              ),
          ],
        );
      },
    );
  }

  static Future<void> _set(String profileId, bool on, List<String> profiles) async {
    final settings = SettingsService.instance;
    await settings.write(SettingsService.simklLedProfiles, [
      for (final id in profiles)
        if (id != profileId) id,
      if (on) profileId,
    ]);
    // The profile's progress reaches Simkl only through its scrobbles.
    if (on) await settings.write(SettingsService.scrobblePref(TrackerService.simkl), true);
  }
}
