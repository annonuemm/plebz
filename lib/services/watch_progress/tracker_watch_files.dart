import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../utils/app_logger.dart';
import '../../utils/external_ids.dart';
import 'tracker_watch_overlay.dart';
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

  File get _patchesFile => File(p.join(directory.path, 'patches.json'));

  /// This device's own marks and positions not yet echoed by the tracker.
  Future<Map<String, LocalWatchPatch>> readPatches() async {
    final json = await _read(_patchesFile);
    if (json is! Map) return {};
    return {
      for (final MapEntry(:key, :value) in json.entries)
        if (key is String) key: ?LocalWatchPatch.fromJson(value),
    };
  }

  Future<void> writePatches(Map<String, LocalWatchPatch> patches) =>
      _write(_patchesFile, {for (final MapEntry(:key, :value) in patches.entries) key: value.toJson()});

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

  File _indexMarksFile(String serverId) => File(p.join(directory.path, 'ids_${_safe(serverId)}_read.json'));

  /// When [serverId]'s id index was last read; null before the first read
  /// that kept it.
  Future<IndexReadMarks?> readIndexMarks(String serverId) async =>
      IndexReadMarks.fromJson(await _read(_indexMarksFile(serverId)));

  Future<void> writeIndexMarks(String serverId, IndexReadMarks marks) =>
      _write(_indexMarksFile(serverId), marks.toJson());

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

/// When a server's id index was last read, at all and whole, and the newest
/// title it held (fork addition) — so a start within the index's lifetime
/// asks the server nothing, and a later one only for what was added since.
class IndexReadMarks {
  const IndexReadMarks({required this.readAt, required this.wholeAt, this.newest});

  final DateTime readAt;
  final DateTime wholeAt;

  /// When that title was added, in the server's own clock (Unix seconds).
  final int? newest;

  Map<String, Object?> toJson() => {
    'readAt': readAt.toIso8601String(),
    'wholeAt': wholeAt.toIso8601String(),
    'newest': newest,
  };

  static IndexReadMarks? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final readAt = raw['readAt'] is String ? DateTime.tryParse(raw['readAt'] as String) : null;
    final wholeAt = raw['wholeAt'] is String ? DateTime.tryParse(raw['wholeAt'] as String) : null;
    if (readAt == null || wholeAt == null) return null;
    return IndexReadMarks(readAt: readAt, wholeAt: wholeAt, newest: (raw['newest'] as num?)?.toInt());
  }
}
