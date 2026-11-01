import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/livetv_channel.dart';
import '../../models/livetv_program.dart';
import '../../utils/app_logger.dart';
import 'iptv_source.dart';

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

  /// The guide addresses the playlist names itself, for a source whose own
  /// field is empty.
  final List<String> playlistGuideUrls;

  const IptvCacheEntry({
    required this.savedAt,
    required this.channels,
    required this.programs,
    this.streamUrls = const {},
    this.streamHeaders = const {},
    this.guideCoverage,
    this.epgLogos,
    this.playlistGuideUrls = const [],
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
  /// next write replaces it. So is a file whose [secrets] no longer fill its
  /// placeholders (see [IptvCacheSecrets]); one written before the secrets
  /// were taken out is read, and written again without them.
  Future<IptvCacheEntry?> read(String sourceId, {IptvCacheSecrets secrets = IptvCacheSecrets.none}) async {
    try {
      final file = await _fileFor(sourceId);
      if (!await file.exists()) return null;
      final stored = await file.readAsString();
      final raw = secrets.restore(stored);
      if (raw == null) {
        appLogger.i('IPTV cache: the stored copy of $sourceId names credentials this source no longer has');
        return null;
      }
      // A real guide is megabytes and would drop frames parsed here; a short
      // one costs less to parse than an isolate costs to start.
      final entry = raw.length < _isolateThresholdBytes ? _decodeEntry(raw) : await compute(_decodeEntry, raw);
      if (entry != null && identical(raw, stored) && secrets.occurIn(stored)) {
        unawaited(write(sourceId, entry, secrets: secrets));
      }
      return entry;
    } catch (e) {
      appLogger.w('IPTV cache: could not read $sourceId', error: e);
      return null;
    }
  }

  /// Stores [entry] with every one of [secrets] replaced by a placeholder.
  Future<void> write(String sourceId, IptvCacheEntry entry, {IptvCacheSecrets secrets = IptvCacheSecrets.none}) {
    final next = (_writes[sourceId] ?? Future<void>.value()).then((_) => _write(sourceId, entry, secrets));
    _writes[sourceId] = next;
    return next.whenComplete(() {
      if (identical(_writes[sourceId], next)) _writes.remove(sourceId);
    });
  }

  Future<void> _write(String sourceId, IptvCacheEntry entry, IptvCacheSecrets secrets) async {
    if (entry.isEmpty) return;
    File? temp;
    final writing = Stopwatch()..start();
    try {
      final encoded = entry.channels.length + entry.programs.length < _isolateThresholdEntries
          ? _encodeEntry(entry)
          : await compute(_encodeEntry, entry);
      final raw = secrets.conceal(encoded);
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

/// The credentials a source's stored copy must not hold (Plebz).
///
/// A playlist from an Xtream panel names the login in every stream address
/// (`/live/<user>/<pass>/1.ts`) and in its guide address; the source keeps
/// them sealed in the credential vault, so the copy on disk replaces each by
/// a placeholder and gets it back from the source when read.
///
/// A placeholder is `\x01`, then its slot in [_names] written in `\x02` and
/// `\x03`, then `\x01`. JSON text never holds a raw control character — the
/// encoder escapes them — so no secret can contain one, and no placeholder
/// can be mistaken for text or be matched by a later secret.
@immutable
class IptvCacheSecrets {
  const IptvCacheSecrets._(this._values);

  static const none = IptvCacheSecrets._({});

  /// The query parameters of a playlist or guide address that carry a login.
  static const _queryNames = ['username', 'password', 'user', 'pass', 'token'];

  /// Every slot a secret can fill, in a fixed order: the placeholder names
  /// its slot, so a copy reads back only into the same slots. New names go
  /// at the end; `query.*` names one of [_queryNames] each.
  static const _names = [
    'username',
    'password',
    'query.username',
    'query.password',
    'query.user',
    'query.pass',
    'query.token',
  ];

  /// Shorter values stay as they are: replacing every "tv" in the copy would
  /// not hide anything.
  static const _minLength = 3;

  /// Slot name → value, for the slots this source fills.
  final Map<String, String> _values;

  factory IptvCacheSecrets.of(IptvSource source) {
    final values = <String, String>{'username': ?source.username, 'password': ?source.password};
    for (final address in [?source.playlistUrl, ...source.epgUrls]) {
      final Map<String, String> query;
      try {
        query = Uri.parse(address).queryParameters;
      } on FormatException {
        continue;
      }
      for (final name in _queryNames) {
        if (query[name] case final value?) values.putIfAbsent('query.$name', () => value);
      }
    }
    values.removeWhere((_, value) => value.length < _minLength);
    return IptvCacheSecrets._(values);
  }

  /// The texts to replace, longest first, each with its placeholder: a value
  /// as JSON writes it, plain and in both URL encodings.
  List<(String, String)> get _replacements {
    final seen = <String>{};
    final out = <(String, String)>[];
    for (final (slot, name) in _names.indexed) {
      final value = _values[name];
      if (value == null) continue;
      final forms = [value, Uri.encodeComponent(value), Uri.encodeQueryComponent(value)];
      for (final (form, text) in forms.indexed) {
        final escaped = jsonEncode(text);
        final json = escaped.substring(1, escaped.length - 1);
        if (json.length >= _minLength && seen.add(json)) out.add((json, _placeholder(slot * 3 + form)));
      }
    }
    return out..sort((a, b) => b.$1.length.compareTo(a.$1.length));
  }

  static String _placeholder(int index) =>
      '\x01${index.toRadixString(2).replaceAll('0', '\x02').replaceAll('1', '\x03')}\x01';

  static final _placeholderPattern = RegExp('\x01([\x02\x03]+)\x01');

  /// [json] with every secret replaced by its placeholder.
  String conceal(String json) {
    var out = json;
    for (final (text, placeholder) in _replacements) {
      out = out.replaceAll(text, placeholder);
    }
    return out;
  }

  /// Whether [json] still holds one of the secrets as it stands.
  bool occurIn(String json) => _replacements.any((replacement) => json.contains(replacement.$1));

  /// [stored] with its placeholders filled; [stored] itself when it has none,
  /// null when one names a slot this source does not fill.
  String? restore(String stored) {
    if (!stored.contains('\x01')) return stored;
    final bySlot = {for (final (text, placeholder) in _replacements) placeholder: text};
    var missing = false;
    final out = stored.replaceAllMapped(_placeholderPattern, (match) {
      final text = bySlot[match[0]];
      if (text == null) missing = true;
      return text ?? '';
    });
    return missing ? null : out;
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
  if (entry.playlistGuideUrls.isNotEmpty) 'playlistGuideUrls': entry.playlistGuideUrls,
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
    playlistGuideUrls: [
      if (decoded['playlistGuideUrls'] case final List<dynamic> urls)
        for (final url in urls)
          if (url is String) url,
    ],
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
