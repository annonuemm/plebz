import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/livetv_channel.dart';
import '../../models/livetv_program.dart';
import '../../utils/app_logger.dart';

/// One source's channels and guide, as they were last read.
class IptvCacheEntry {
  final DateTime savedAt;
  final List<LiveTvChannel> channels;
  final List<LiveTvProgram> programs;

  /// The stream address per channel key, for playlist sources. Channel keys
  /// are derived from the entry rather than from its URL, so without this a
  /// restored channel list would name channels nothing could play.
  final Map<String, String> streamUrls;
  final Map<String, Map<String, String>> streamHeaders;

  /// The keys of the channels [programs] was read for — the ones not hidden
  /// at the time. Null for a guide read for every channel, which is what a
  /// copy stored before hidden channels were left out holds.
  final Set<String>? guideCoverage;

  /// Channel key → the logo the guide names for a channel. Null for a copy
  /// stored before guides were read for logos: its guide has to be read
  /// once more to learn them.
  final Map<String, String>? epgLogos;

  const IptvCacheEntry({
    required this.savedAt,
    required this.channels,
    required this.programs,
    this.streamUrls = const {},
    this.streamHeaders = const {},
    this.guideCoverage,
    this.epgLogos,
  });

  bool get isEmpty => channels.isEmpty && programs.isEmpty;
}

/// Keeps a source's channels and guide across restarts.
///
/// A playlist runs to tens of thousands of lines and a guide to tens of
/// megabytes, and both were re-downloaded and re-parsed on the first visit to
/// Live TV of every app session. Neither changes by the hour, so they are kept
/// on disk and re-read only when the user's chosen interval has passed — or
/// when they ask for it.
///
/// Files rather than the database: these are large blobs read whole and
/// written whole, which is what a file is for, and it keeps a schema
/// migration out of the picture.
class IptvDiskCache {
  IptvDiskCache({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directoryProvider;

  /// Per source, the write in flight: the next one waits for it, so the last
  /// call is the last word.
  final Map<String, Future<void>> _writes = {};

  /// Numbers each temporary file, so two writes never share one.
  static int _writeCount = 0;

  Future<File> _fileFor(String sourceId) async {
    final root = await _directoryProvider();
    final dir = Directory(p.join(root.path, 'iptv_cache'));
    if (!await dir.exists()) await dir.create(recursive: true);
    // Source ids are generated UUIDs, but a stored id is still outside data
    // this code produced; keep it to characters that cannot walk the path.
    final safe = sourceId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File(p.join(dir.path, '$safe.json'));
  }

  /// What was stored for [sourceId], or null when there is nothing readable.
  ///
  /// A damaged file is a miss, not an error: the source refetches, and the
  /// next write replaces it.
  Future<IptvCacheEntry?> read(String sourceId) async {
    try {
      final file = await _fileFor(sourceId);
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      // A real guide is megabytes and would drop frames parsed here; a short
      // one costs less to parse than an isolate costs to start.
      return raw.length < _isolateThresholdBytes ? _decodeEntry(raw) : await compute(_decodeEntry, raw);
    } catch (e) {
      appLogger.w('IPTV cache: could not read $sourceId', error: e);
      return null;
    }
  }

  Future<void> write(String sourceId, IptvCacheEntry entry) {
    final next = (_writes[sourceId] ?? Future<void>.value()).then((_) => _write(sourceId, entry));
    _writes[sourceId] = next;
    return next.whenComplete(() {
      if (identical(_writes[sourceId], next)) _writes.remove(sourceId);
    });
  }

  Future<void> _write(String sourceId, IptvCacheEntry entry) async {
    if (entry.isEmpty) return;
    File? temp;
    final writing = Stopwatch()..start();
    try {
      final raw = entry.channels.length + entry.programs.length < _isolateThresholdEntries
          ? _encodeEntry(entry)
          : await compute(_encodeEntry, entry);
      final file = await _fileFor(sourceId);
      // Through a temporary file: a write cut short by the app going away
      // would otherwise leave a half-written guide behind. One of its own per
      // write — a shared name let two writers (another instance over the same
      // source) truncate each other's half-written file.
      temp = File('${file.path}.${pid}_${++_writeCount}.tmp');
      await temp.writeAsString(raw, flush: true);
      await temp.rename(file.path);
      temp = null;
      appLogger.i(
        'IPTV cache timing: stored ${entry.channels.length} channels and ${entry.programs.length} programmes, '
        '${(raw.length / (1 << 20)).toStringAsFixed(1)} MB in ${writing.elapsedMilliseconds} ms',
      );
    } catch (e) {
      appLogger.w('IPTV cache: could not write $sourceId', error: e);
    } finally {
      // A guide is tens of megabytes; a failed write must not leave one lying.
      try {
        if (temp != null && await temp.exists()) await temp.delete();
      } catch (e) {
        appLogger.d('IPTV cache: could not remove a leftover temporary file', error: e);
      }
    }
  }

  Future<void> clear(String sourceId) async {
    try {
      final file = await _fileFor(sourceId);
      if (await file.exists()) await file.delete();
    } catch (e) {
      appLogger.d('IPTV cache: could not clear $sourceId', error: e);
    }
  }
}

/// Where an isolate starts paying for itself.
///
/// Starting one costs milliseconds and, on a loaded machine, sometimes a good
/// deal more; a handful of channels is not worth it. A real playlist and guide
/// are far past both of these.
const int _isolateThresholdEntries = 500;
const int _isolateThresholdBytes = 256 * 1024;

/// Top-level for [compute]: closures cannot cross an isolate boundary.
String _encodeEntry(IptvCacheEntry entry) => jsonEncode({
  'savedAt': entry.savedAt.millisecondsSinceEpoch,
  'channels': [for (final channel in entry.channels) channel.toJson()],
  'programs': [for (final program in entry.programs) program.toJson()],
  'streamUrls': entry.streamUrls,
  'streamHeaders': entry.streamHeaders,
  if (entry.guideCoverage case final coverage?) 'guideCoverage': coverage.toList(),
  'epgLogos': ?entry.epgLogos,
});

IptvCacheEntry? _decodeEntry(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic>) return null;
  final savedAt = decoded['savedAt'];
  if (savedAt is! int) return null;

  List<T> list<T>(Object? value, T Function(Map<String, dynamic>) build) => [
    if (value is List)
      for (final entry in value)
        if (entry is Map<String, dynamic>) build(entry),
  ];

  return IptvCacheEntry(
    savedAt: DateTime.fromMillisecondsSinceEpoch(savedAt),
    channels: list(decoded['channels'], LiveTvChannel.fromJson),
    programs: list(decoded['programs'], LiveTvProgram.fromJson),
    streamUrls: {
      if (decoded['streamUrls'] case final Map<String, dynamic> urls)
        for (final entry in urls.entries)
          if (entry.value is String) entry.key: entry.value as String,
    },
    streamHeaders: {
      if (decoded['streamHeaders'] case final Map<String, dynamic> headers)
        for (final entry in headers.entries)
          if (entry.value case final Map<String, dynamic> values)
            entry.key: {
              for (final header in values.entries)
                if (header.value is String) header.key: header.value as String,
            },
    },
    epgLogos: switch (decoded['epgLogos']) {
      final Map<String, dynamic> logos => {
        for (final entry in logos.entries)
          if (entry.value is String) entry.key: entry.value as String,
      },
      _ => null,
    },
    guideCoverage: switch (decoded['guideCoverage']) {
      final List<dynamic> keys => {
        for (final key in keys)
          if (key is String) key,
      },
      _ => null,
    },
  );
}
