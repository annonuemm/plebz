import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../utils/app_logger.dart';
import '../../utils/external_ids.dart';
import 'tracker_watch_state.dart';

/// A tracker-led profile's watch state and server id indexes on disk (fork
/// addition), so the app starts with what it knew instead of a blank slate
/// while the tracker is asked again.
///
/// One folder per profile. A file that cannot be read counts as missing: it
/// is only a head start, and the next sync writes it anew.
class TrackerWatchFiles {
  TrackerWatchFiles(this.directory);

  final Directory directory;

  File get _stateFile => File(p.join(directory.path, 'state.json'));

  File _indexFile(String serverId) => File(p.join(directory.path, 'ids_${_safe(serverId)}.json'));

  static String _safe(String name) => name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  Future<TrackerWatchState> readState() async {
    final json = await _read(_stateFile);
    return json is Map<String, Object?> ? TrackerWatchState.fromJson(json) : TrackerWatchState.empty;
  }

  Future<void> writeState(TrackerWatchState state) => _write(_stateFile, state.toJson());

  Future<Map<String, ExternalIds>> readIndex(String serverId) async {
    final json = await _read(_indexFile(serverId));
    if (json is! Map) return const {};
    return {
      for (final MapEntry(:key, :value) in json.entries)
        if (key is String && value is Map) key: ExternalIds.fromJson(value.cast<String, Object?>()),
    };
  }

  Future<void> writeIndex(String serverId, Map<String, ExternalIds> index) =>
      _write(_indexFile(serverId), {for (final MapEntry(:key, :value) in index.entries) key: value.toJson()});

  /// Everything of this profile's gone — for a profile handed back to its
  /// server.
  Future<void> clear() async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (error) {
      appLogger.w('Tracker watch files: could not clear ${directory.path}', error: error);
    }
  }

  static Future<Object?> _read(File file) async {
    try {
      if (!await file.exists()) return null;
      return jsonDecode(await file.readAsString());
    } catch (error) {
      appLogger.w('Tracker watch files: ${file.path} unreadable, starting without it', error: error);
      return null;
    }
  }

  /// Writes run one after another, so two never race for the same file.
  Future<void> _writes = Future.value();

  /// Done once every write asked for so far is on disk.
  Future<void> get idle => _writes;

  Future<void> _write(File file, Object json) => _writes = _writes.then((_) => _writeNow(file, json));

  Future<void> _writeNow(File file, Object json) async {
    try {
      await directory.create(recursive: true);
      // Written beside and moved over, so a crash mid-write leaves the old
      // file rather than half a new one.
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(jsonEncode(json), flush: true);
      await temporary.rename(file.path);
    } catch (error) {
      appLogger.w('Tracker watch files: could not write ${file.path}', error: error);
    }
  }
}
