import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../i18n/strings.g.dart';
import '../../services/plebz_update_service.dart';
import '../../services/plebz_whats_new.dart';
import '../../services/settings_service.dart';
import '../../utils/app_logger.dart';
import '../../utils/dialogs.dart';
import '../../utils/fork_identity.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/setting_tile.dart';

/// At start, once after an update: which Plebz is now installed. The update
/// is approved twice — here and in Android's installer — and then the app
/// restarts into the new build with no word that anything happened; this is
/// that word.
///
/// Silent on a first install, and on the first start of the build that
/// introduced this notice unless the app had been set up before (then it was
/// an update).
///
/// Under the sentence, what is new: every section of [plebzWhatsNewAsset]
/// since the build last started, so a skipped release is told of too.
Future<void> maybeShowPlebzUpdatedNotice(
  BuildContext context, {
  Future<({String version, int build})?> Function()? installed,
  Future<List<PlebzWhatsNewEntry>> Function()? whatsNew,
}) async {
  final settings = SettingsService.instance;
  final current = await (installed ?? _installedVersion)();
  if (current == null) return;
  final lastSeen = settings.read(SettingsService.plebzLastSeenBuild);
  if (lastSeen == current.build) return;
  await settings.write(SettingsService.plebzLastSeenBuild, current.build);
  if (lastSeen > current.build) return;
  if (lastSeen == 0 && !settings.read(SettingsService.onboardingCompleted)) return;
  if (!context.mounted) return;
  appLogger.i('Plebz: first start of build ${current.build} (last seen $lastSeen)');
  final notes = plebzWhatsNewSince(await (whatsNew ?? loadPlebzWhatsNew)(), lastSeen: lastSeen, current: current.build);
  if (!context.mounted) return;
  await showFullTextDialog(
    context,
    title: t.plebz.updatedTitle,
    span: plebzWhatsNewSpan(
      notes,
      lead: t.plebz.updatedBody(version: current.version, build: current.build),
    ),
  );
}

/// Settings' "Was ist neu": every version's notes, newest first.
Future<void> showPlebzWhatsNew(BuildContext context, {Future<List<PlebzWhatsNewEntry>> Function()? whatsNew}) async {
  final notes = await (whatsNew ?? loadPlebzWhatsNew)();
  if (!context.mounted) return;
  if (notes.isEmpty) {
    showAppSnackBar(context, t.plebz.whatsNewEmpty);
    return;
  }
  await showFullTextDialog(context, title: t.plebz.whatsNew, span: plebzWhatsNewSpan(notes));
}

Future<({String version, int build})?> _installedVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    final code = int.tryParse(info.buildNumber);
    if (code == null) return null;
    return (version: info.version, build: PlebzUpdateService.buildFromVersionCode(code));
  } catch (error) {
    appLogger.d('Plebz: installed version not readable', error: error);
    return null;
  }
}

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
  // Asking GitHub can take a few seconds, and a press that shows nothing for
  // that long reads as a press that did nothing.
  if (userInitiated) showAppSnackBar(context, t.plebz.checking);
  try {
    // The answer replaces "Checking…" rather than queueing behind it.
    void clearChecking() {
      if (userInitiated && context.mounted) ScaffoldMessenger.maybeOf(context)?.removeCurrentSnackBar();
    }

    final PlebzRelease? release;
    try {
      release = await updates.latestRelease();
      clearChecking();
    } catch (error, stackTrace) {
      clearChecking();
      // Not "up to date": nothing is known about what is newer.
      appLogger.w('Plebz update check: GitHub could not be asked', error: error, stackTrace: stackTrace);
      if (userInitiated && context.mounted) showErrorSnackBar(context, t.plebz.checkFailed);
      return;
    }
    final build = await (currentBuild ?? _installedBuild)();
    appLogger.i('Plebz update check: installed build $build, latest release ${release?.tag ?? 'none'}');
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
    // What the release brings, as written for it — the text that ships in
    // the new build's own notes.
    final wanted = await showFullTextConfirmDialog(
      context,
      title: t.plebz.updateAvailableTitle,
      span: plebzNotesSpan(release.notes, lead: t.plebz.updateAvailableBody(release: release.title)),
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

/// The update rows for the settings page: "Was ist neu" everywhere, the
/// update check only where [plebzUpdatesAvailable].
List<Widget> plebzUpdateRows(BuildContext context) {
  final whatsNew = SettingNavigationTile(
    icon: Symbols.new_releases_rounded,
    title: t.plebz.whatsNew,
    subtitle: t.plebz.whatsNewDescription,
    onTap: () => unawaited(showPlebzWhatsNew(context)),
  );
  if (!plebzUpdatesAvailable) return [whatsNew];
  return [
    whatsNew,
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
