import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../utils/app_logger.dart';

/// Playlists taken from a local file (fork addition).
///
/// The chosen file is copied into the app's own storage and the source points
/// at the copy with a `file:` address: the original may sit on a USB stick that
/// is pulled, or in a picker's cache that is cleared, and a source must keep
/// working either way. Changing the original means choosing it again.
///
/// The copy is named `<source id>__<original name>`, so the edit screen can
/// say which file it was.
abstract final class IptvLocalFiles {
  @visibleForTesting
  static Future<Directory> Function() directoryProvider = getApplicationSupportDirectory;

  static Future<Directory> _directory() async => Directory(p.join((await directoryProvider()).path, 'iptv_files'));

  static bool isLocal(String? url) => url != null && url.startsWith('file:');

  /// The name the file had when it was chosen, for a local address.
  static String? originalName(String? url) {
    if (!isLocal(url)) return null;
    final name = p.basename(Uri.parse(url!).toFilePath());
    final split = name.indexOf('__');
    return split < 0 ? name : name.substring(split + 2);
  }

  /// Copies [pickedPath] in for [sourceId], replacing an earlier copy, and
  /// answers with the address the source stores.
  static Future<String> importPlaylist(String sourceId, String pickedPath) async {
    final directory = await _directory();
    await directory.create(recursive: true);
    final target = File(p.join(directory.path, '${sourceId}__${p.basename(pickedPath)}'));
    final temporary = File('${target.path}.tmp');
    await File(pickedPath).copy(temporary.path);
    await _deleteCopies(directory, sourceId);
    await temporary.rename(target.path);
    return Uri.file(target.path).toString();
  }

  /// Forgets [sourceId]'s copy, for a source that is removed.
  static Future<void> deleteFor(String sourceId) async {
    try {
      final directory = await _directory();
      if (await directory.exists()) await _deleteCopies(directory, sourceId);
    } catch (error) {
      appLogger.d('IPTV: local playlist of $sourceId not removed', error: error);
    }
  }

  static Future<void> _deleteCopies(Directory directory, String sourceId) async {
    await for (final entity in directory.list()) {
      final name = p.basename(entity.path);
      if (entity is File && name.startsWith('${sourceId}__') && !name.endsWith('.tmp')) await entity.delete();
    }
  }
}
