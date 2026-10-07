import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../profiles/active_profile_provider.dart';
import '../../services/settings_service.dart';
import '../../services/trackers/tracker_constants.dart';
import '../../services/watch_progress/tracker_progress_controller.dart';
import '../../utils/formatters.dart';
import '../../utils/snackbar_helper.dart';
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
            if (on) const _SimklSyncRows(),
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

/// How the profile's sync with Simkl stands, and the way to run it again by
/// hand — instead of disconnecting and reconnecting Simkl, which is what a
/// viewer did when a first sync had failed (Plebz).
class _SimklSyncRows extends StatefulWidget {
  const _SimklSyncRows();

  @override
  State<_SimklSyncRows> createState() => _SimklSyncRowsState();
}

class _SimklSyncRowsState extends State<_SimklSyncRows> {
  Future<void> _syncNow() async {
    final ok = await TrackerProgressController.instance.syncNow();
    if (!mounted) return;
    if (ok) {
      showSuccessSnackBar(context, t.services.syncNowDone);
    } else {
      showErrorSnackBar(context, t.services.syncNowFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = TrackerProgressController.instance;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final last = controller.lastSyncAt;
        final status = controller.syncing
            ? t.services.syncStatusRunning
            : controller.syncFailed
            ? t.services.syncStatusFailed
            : last == null
            ? t.services.syncStatusNever
            : t.services.syncStatusOk(
                time: formatClockTime(last, is24Hour: MediaQuery.alwaysUse24HourFormatOf(context)),
                shows: controller.state.shows.length,
                movies: controller.state.movies.length,
              );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: AppIcon(
                controller.syncFailed ? Symbols.sync_problem_rounded : Symbols.cloud_sync_rounded,
                fill: 1,
              ),
              title: Text(t.services.syncStatusTitle),
              subtitle: Text(status),
            ),
            FocusableListTile(
              leading: const AppIcon(Symbols.sync_rounded, fill: 1),
              title: Text(t.services.syncNow),
              subtitle: Text(t.services.syncNowDescription),
              enabled: !controller.syncing,
              onTap: controller.syncing ? null : () => unawaited(_syncNow()),
            ),
          ],
        );
      },
    );
  }
}
