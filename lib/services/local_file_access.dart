import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
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

/// What became of [LocalFileAccess.saveFile].
enum LocalSaveOutcome {
  /// Written where the viewer chose; the path says where.
  saved,

  /// The viewer turned back without choosing.
  cancelled,

  /// No way to choose here — no picker and no file access. The caller saves
  /// wherever it can without asking.
  unavailable,
}

typedef LocalSave = ({LocalSaveOutcome outcome, String? path});

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

  /// Whether a local file can be chosen at all. Not on Apple TV: it has no
  /// picker, no shared storage and no USB, so the offer is not made there.
  static bool get available => debugChannel != null || !PlatformDetector.isAppleTV();

  /// Whether the system's picker is there to use.
  static Future<bool> hasSystemPicker() async {
    if (!available) return false;
    // Phones, tablets and desktops always have one; only TV boxes need asking.
    if (debugChannel == null && (!Platform.isAndroid || !PlatformDetector.isTV())) return true;
    return await _call<bool>('hasDocumentPicker') ?? false;
  }

  /// Whether the system's picker can also save a new file.
  static Future<bool> hasSystemSaver() async {
    if (!available) return false;
    if (debugChannel == null && (!Platform.isAndroid || !PlatformDetector.isTV())) return true;
    return await _call<bool>('hasDocumentSaver') ?? false;
  }

  static Future<bool> hasFileAccess() async => await _call<bool>('hasFileAccess') ?? false;

  /// Whether files may be written as well as read — the same as
  /// [hasFileAccess] from Android 11 on; before that a permission of its own.
  static Future<bool> hasWriteAccess() async => await _call<bool>('hasWriteAccess') ?? false;

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
    if (!available) return null;
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

  /// Saves [bytes] as [fileName] in a folder the user chooses: the system's
  /// picker where the box can save with it, otherwise the app's own browser,
  /// which starts in the Download folder of a USB stick if one is in, else of
  /// the device. [extension] (lower case, no dot) is the file's type.
  static Future<LocalSave> saveFile(
    BuildContext context, {
    required String fileName,
    required Uint8List bytes,
    required String extension,
    required String title,
  }) async {
    const cancelled = (outcome: LocalSaveOutcome.cancelled, path: null);
    const unavailable = (outcome: LocalSaveOutcome.unavailable, path: null);
    if (!available) return unavailable;
    if (await hasSystemSaver()) {
      final path = await FilePickerService.instance.saveFile(
        dialogTitle: title,
        fileName: fileName,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: [extension],
      );
      return path == null ? cancelled : (outcome: LocalSaveOutcome.saved, path: path);
    }
    if (!context.mounted || !await _ensureFileAccess(context, write: true) || !context.mounted) return unavailable;
    final roots = await storageRoots();
    if (!context.mounted) return cancelled;
    final path = await Navigator.of(context).push<String>(
      LocalFileBrowserScreen.route(
        roots: roots,
        extensions: {extension},
        title: title,
        initialDirectory: startFolder(roots),
        saveName: fileName,
        save: (directory) async {
          final file = File(p.join(directory, fileName));
          await file.writeAsBytes(bytes, flush: true);
          return file.path;
        },
      ),
    );
    return path == null ? cancelled : (outcome: LocalSaveOutcome.saved, path: path);
  }

  /// Where saving starts: a removable volume first — a stick is how a file
  /// leaves a television — and on it the Download folder where there is one.
  @visibleForTesting
  static String? startFolder(List<StorageRoot> roots) {
    if (roots.isEmpty) return null;
    final root = roots.firstWhere((root) => root.removable, orElse: () => roots.first);
    final download = p.join(root.path, 'Download');
    return Directory(download).existsSync() ? download : root.path;
  }

  static bool _matches(String path, Set<String> extensions) {
    final ext = p.extension(path).toLowerCase();
    return ext.isNotEmpty && extensions.contains(ext.substring(1));
  }

  /// Asks for the access the browser needs, once; true when it is there.
  /// [write]: to save a file, not only to read one.
  static Future<bool> _ensureFileAccess(BuildContext context, {bool write = false}) async {
    Future<bool> granted() => write ? hasWriteAccess() : hasFileAccess();
    if (await granted()) return true;
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
    final now = await granted();
    if (!now && context.mounted) {
      await showFullTextDialog(context, title: t.localFiles.accessTitle, text: t.localFiles.accessDenied);
    }
    return now;
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
