import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../i18n/strings.g.dart';
import '../../services/plebz_update_service.dart';
import '../../services/settings_service.dart';
import '../../utils/app_logger.dart';
import '../../utils/dialogs.dart';
import '../../utils/fork_identity.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/setting_tile.dart';

/// At start, once: asks for a newer Plebz when the viewer has not switched
/// that off, and says nothing unless there is one.
Future<void> maybeCheckPlebzUpdateOnStartup(BuildContext context) async {
  if (!plebzUpdatesAvailable) return;
  // Not over the first-run setup; the next start asks.
  if (!SettingsService.instance.read(SettingsService.onboardingCompleted)) return;
  if (!SettingsService.instance.read(SettingsService.autoCheckUpdatesOnStartup)) return;
  await checkForPlebzUpdate(context, userInitiated: false);
}

/// Asks GitHub for a newer Plebz and offers it. [userInitiated] reports "up to
/// date" and failures too; the start-up check stays silent about both.
Future<void> checkForPlebzUpdate(
  BuildContext context, {
  required bool userInitiated,
  PlebzUpdateService? service,
  Future<int> Function()? currentBuild,
  Future<List<String>> Function()? supportedAbis,
}) async {
  if (!plebzUpdatesAvailable) return;
  final updates = service ?? PlebzUpdateService();
  try {
    final release = await updates.latestRelease();
    final build = await (currentBuild ?? _installedBuild)();
    if (!context.mounted) return;
    if (release == null || !PlebzUpdateService.isNewer(release, build)) {
      if (userInitiated) showAppSnackBar(context, t.plebz.upToDate);
      return;
    }
    final asset = PlebzUpdateService.assetFor(release.assets, await (supportedAbis ?? _supportedAbis)());
    if (!context.mounted) return;
    if (asset == null) {
      if (userInitiated) showErrorSnackBar(context, t.plebz.noMatchingDownload);
      return;
    }
    final wanted = await showConfirmDialog(
      context,
      title: t.plebz.updateAvailableTitle,
      message: t.plebz.updateAvailableBody(release: release.title),
      confirmText: t.plebz.updateNow,
      cancelText: t.plebz.later,
    );
    if (!wanted || !context.mounted) return;

    // Android wants Plebz allowed to install apps before it hands over.
    if (!await updates.canInstall()) {
      if (!context.mounted) return;
      final open = await showConfirmDialog(
        context,
        title: t.plebz.installPermissionTitle,
        message: t.plebz.installPermissionBody,
        confirmText: t.plebz.openSettings,
        cancelText: t.plebz.later,
      );
      if (open) await updates.openInstallPermission();
      return;
    }
    if (!context.mounted) return;

    final file = await _downloadWithProgress(context, updates, asset);
    if (file == null || !context.mounted) return;
    if (!await updates.install(file) && context.mounted) showErrorSnackBar(context, t.plebz.updateFailed);
  } catch (error, stackTrace) {
    appLogger.w('Plebz update check failed', error: error, stackTrace: stackTrace);
    if (userInitiated && context.mounted) showErrorSnackBar(context, t.plebz.updateFailed);
  } finally {
    if (service == null) updates.dispose();
  }
}

Future<int> _installedBuild() async =>
    PlebzUpdateService.buildFromVersionCode(int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0);

Future<List<String>> _supportedAbis() async => (await DeviceInfoPlugin().androidInfo).supportedAbis;

/// A dialog that cannot be dismissed while the file comes in; null when the
/// download failed (the error is shown).
Future<dynamic> _downloadWithProgress(BuildContext context, PlebzUpdateService updates, PlebzReleaseAsset asset) {
  final progress = ValueNotifier<double?>(null);
  final done = Completer<dynamic>();
  unawaited(
    updates
        .download(asset, onProgress: (value) => progress.value = value)
        .then(
          done.complete,
          onError: (Object error, StackTrace stack) {
            appLogger.w('Plebz update download failed', error: error, stackTrace: stack);
            done.complete(null);
          },
        ),
  );
  unawaited(
    showScopedDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        unawaited(
          done.future.then((_) {
            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
          }),
        );
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: Text(t.plebz.downloading),
            content: ValueListenableBuilder<double?>(
              valueListenable: progress,
              builder: (_, value, _) => LinearProgressIndicator(value: value),
            ),
          ),
        );
      },
    ),
  );
  return done.future.then((file) {
    progress.dispose();
    if (file == null && context.mounted) showErrorSnackBar(context, t.plebz.updateFailed);
    return file;
  });
}

/// The update rows for the settings page; nothing until [plebzUpdatesAvailable].
List<Widget> plebzUpdateRows(BuildContext context) {
  if (!plebzUpdatesAvailable) return const [];
  return [
    SettingNavigationTile(
      icon: Symbols.system_update_rounded,
      title: t.plebz.checkForUpdates,
      subtitle: t.plebz.checkForUpdatesDescription,
      onTap: () => unawaited(checkForPlebzUpdate(context, userInitiated: true)),
    ),
    SettingSwitchTile(
      pref: SettingsService.autoCheckUpdatesOnStartup,
      icon: Symbols.update_rounded,
      title: t.plebz.checkOnStartup,
      subtitle: t.plebz.checkOnStartupDescription,
    ),
  ];
}
