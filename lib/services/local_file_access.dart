import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../i18n/strings.g.dart';
import '../screens/files/local_file_browser_screen.dart';
import '../utils/app_logger.dart';
import '../utils/dialogs.dart';
import '../utils/platform_detector.dart';
import 'file_picker_service.dart';

/// A volume the app's own browser starts from.
@immutable
class StorageRoot {
  const StorageRoot({required this.path, required this.label, required this.removable});

  final String path;
  final String label;
  final bool removable;
}

/// Choosing a local file anywhere the user likes (fork addition).
///
/// The system's own picker first, wherever there is one — phones, tablets,
/// desktops, and the TV boxes that ship it. Many Android TV boxes do not; there
/// the app's own browser walks the shared storage and USB sticks, which needs
/// "all files access", asked for once and only then.
abstract final class LocalFileAccess {
  static const MethodChannel _channel = MethodChannel('com.plebz/storage_access');

  /// Test seam: stands in for the platform channel.
  @visibleForTesting
  static Future<Object?> Function(String method)? debugChannel;

  static Future<T?> _call<T>(String method) async {
    final seam = debugChannel;
    if (seam != null) return await seam(method) as T?;
    try {
      return await _channel.invokeMethod<T>(method);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      appLogger.w('Storage access: $method failed', error: error);
      return null;
    }
  }

  /// Whether the system's picker is there to use.
  static Future<bool> hasSystemPicker() async {
    // Phones, tablets and desktops always have one; only TV boxes need asking.
    if (debugChannel == null && (!Platform.isAndroid || !PlatformDetector.isTV())) return true;
    return await _call<bool>('hasDocumentPicker') ?? false;
  }

  static Future<bool> hasFileAccess() async => await _call<bool>('hasFileAccess') ?? false;

  static Future<List<StorageRoot>> storageRoots() async {
    final raw = await _call<List<Object?>>('storageRoots') ?? const [];
    return [
      for (final entry in raw)
        if (entry is Map && entry['path'] is String)
          StorageRoot(
            path: entry['path'] as String,
            label: (entry['label'] as String?) ?? p.basename(entry['path'] as String),
            removable: entry['removable'] == true,
          ),
    ];
  }

  /// A file ending in one of [extensions] (lower case, no dot), chosen by the
  /// user; its path, or null when nothing was chosen.
  static Future<String?> pickFile(
    BuildContext context, {
    required Set<String> extensions,
    required String title,
  }) async {
    if (await hasSystemPicker()) {
      // Any type: Android has no MIME type for most of these (an M3U is
      // `audio/x-mpegurl` on some boxes, unknown on others), and a filter the
      // picker cannot map greys out the very file being looked for.
      final result = await FilePickerService.instance.pickFiles();
      final path = result?.files.singleOrNull?.path;
      if (path == null || !context.mounted) return null;
      if (!_matches(path, extensions)) {
        await showFullTextDialog(
          context,
          title: t.localFiles.wrongTypeTitle,
          text: t.localFiles.wrongTypeMessage(types: extensions.map((e) => '.$e').join(', ')),
        );
        return null;
      }
      return path;
    }
    if (!context.mounted || !await _ensureFileAccess(context) || !context.mounted) return null;
    final roots = await storageRoots();
    if (!context.mounted) return null;
    return Navigator.of(
      context,
    ).push<String>(LocalFileBrowserScreen.route(roots: roots, extensions: extensions, title: title));
  }

  static bool _matches(String path, Set<String> extensions) {
    final ext = p.extension(path).toLowerCase();
    return ext.isNotEmpty && extensions.contains(ext.substring(1));
  }

  /// Asks for the access the browser needs, once; true when it is there.
  static Future<bool> _ensureFileAccess(BuildContext context) async {
    if (await hasFileAccess()) return true;
    if (!context.mounted) return false;
    final go = await showConfirmDialog(
      context,
      title: t.localFiles.accessTitle,
      message: t.localFiles.accessMessage,
      confirmText: t.localFiles.accessConfirm,
    );
    if (!go || !context.mounted) return false;
    final opened = await _call<bool>('requestFileAccess') ?? false;
    if (!opened) {
      if (context.mounted) {
        await showFullTextDialog(context, title: t.localFiles.accessTitle, text: t.localFiles.accessUnavailable);
      }
      return false;
    }
    // The grant is a screen of the system's, or a dialog: back in the app is
    // when it has been answered.
    await _nextResume();
    final granted = await hasFileAccess();
    if (!granted && context.mounted) {
      await showFullTextDialog(context, title: t.localFiles.accessTitle, text: t.localFiles.accessDenied);
    }
    return granted;
  }

  static Future<void> _nextResume() {
    if (debugChannel != null) return Future.value();
    final done = Completer<void>();
    late final AppLifecycleListener listener;
    listener = AppLifecycleListener(
      onResume: () {
        listener.dispose();
        if (!done.isCompleted) done.complete();
      },
    );
    return done.future;
  }
}
