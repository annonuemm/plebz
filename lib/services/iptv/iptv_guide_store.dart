import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../../models/livetv_program.dart';
import '../../utils/app_logger.dart';
import 'iptv_guide_database.dart';

/// Where an IPTV source's guide stands (Plebz): the generation readers ask
/// for, when it was read, for which channels, and when its last programme
/// begins.
class IptvGuideState {
  const IptvGuideState({required this.generation, required this.fetchedAt, this.coverage, this.lastStart});

  final int generation;
  final DateTime fetchedAt;

  /// The channel keys the guide was read for; null for all.
  final Set<String>? coverage;

  /// Epoch seconds; null when the guide has no programme.
  final int? lastStart;
}

/// Where IPTV guides are kept (Plebz): asked for one window of time at a
/// time, so nobody holds a whole guide — a week of a few hundred channels is
/// tens of thousands of programmes, which a TV stick with 2 GB had to keep in
/// memory and read whole on every start.
abstract class IptvGuideStore {
  /// The guide kept for [sourceId], or null when there is none.
  Future<IptvGuideState?> state(String sourceId);

  /// The programmes of [sourceId]'s [generation] that run into [from]..[to]
  /// (epoch seconds; either open), on [channels] when given, by start.
  Future<List<LiveTvProgram>> window(String sourceId, int generation, {int? from, int? to, Set<String>? channels});

  /// A new guide for [sourceId], written beside the one in place until
  /// [IptvGuideWriter.commit].
  Future<IptvGuideWriter> begin(String sourceId);

  /// Forget [sourceId]'s guide.
  Future<void> clear(String sourceId);
}

/// A guide being written. Rows go in as they are read; nothing is seen until
/// [commit], and [abandon] takes them away again.
abstract class IptvGuideWriter {
  /// How many programmes went in so far.
  int get count;

  Future<void> add(List<LiveTvProgram> programs);

  /// Put this guide in place of the one before, in one step.
  Future<IptvGuideState> commit({required DateTime fetchedAt, Set<String>? coverage});

  Future<void> abandon();
}

/// The longest a programme is taken to run, for the window's lower bound:
/// one that began earlier than this before the window is not looked for.
const int _longestProgrammeSeconds = 2 * 24 * 60 * 60;

const String _genreSeparator = '\u001f';

/// Up to how many channels a window names them to the database.
const int _channelsAskedDirectly = 64;

/// Kept in a database of its own — see [IptvGuideDatabase].
class DriftIptvGuideStore implements IptvGuideStore {
  DriftIptvGuideStore(this._db);

  final IptvGuideDatabase _db;

  /// The one the app uses, opened on first use.
  static final DriftIptvGuideStore shared = DriftIptvGuideStore(IptvGuideDatabase.onDisk());

  @override
  Future<IptvGuideState?> state(String sourceId) async {
    final row = await (_db.select(_db.guideSources)..where((t) => t.sourceId.equals(sourceId))).getSingleOrNull();
    if (row == null) return null;
    return IptvGuideState(
      generation: row.generation,
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(row.fetchedAt),
      coverage: _coverageFrom(row.coverage),
      lastStart: row.lastStart,
    );
  }

  @override
  Future<List<LiveTvProgram>> window(
    String sourceId,
    int generation, {
    int? from,
    int? to,
    Set<String>? channels,
  }) async {
    final query = _db.select(_db.guidePrograms)
      ..where((t) {
        var condition = t.sourceId.equals(sourceId) & t.generation.equals(generation);
        // Overlap, not containment: a programme that began before the window
        // is still what is on at its start — as the in-memory guide filtered.
        if (to != null) condition = condition & t.beginsAt.isSmallerOrEqualValue(to);
        if (from != null) {
          condition =
              condition &
              t.beginsAt.isBiggerOrEqualValue(from - _longestProgrammeSeconds) &
              t.endsAt.isBiggerOrEqualValue(from);
        }
        // A few channels — the player's one — are asked of the channel index
        // rather than read out of every channel's window.
        if (channels != null && channels.length <= _channelsAskedDirectly) {
          condition = condition & (t.channel.isIn(channels) | t.channel.equals(''));
        }
        return condition;
      })
      ..orderBy([(t) => OrderingTerm.asc(t.beginsAt)]);
    final rows = await query.get();
    return [
      for (final row in rows)
        // A programme filed under no channel (an Xtream channel without an
        // EPG id) is not one a shown channel could be told from; it stays, as
        // it did in the guide held whole.
        if (channels == null || row.channel.isEmpty || channels.contains(row.channel)) _programFrom(row),
    ];
  }

  @override
  Future<IptvGuideWriter> begin(String sourceId) async {
    final current = await state(sourceId);
    final generation = (current?.generation ?? 0) + 1;
    // What an earlier write cut short left under this generation.
    await (_db.delete(
      _db.guidePrograms,
    )..where((t) => t.sourceId.equals(sourceId) & t.generation.equals(generation))).go();
    return _DriftGuideWriter(_db, sourceId, generation);
  }

  @override
  Future<void> clear(String sourceId) => _db.transaction(() async {
    await (_db.delete(_db.guidePrograms)..where((t) => t.sourceId.equals(sourceId))).go();
    await (_db.delete(_db.guideSources)..where((t) => t.sourceId.equals(sourceId))).go();
  });

  static Set<String>? _coverageFrom(String? raw) {
    if (raw == null) return null;
    try {
      return {for (final key in jsonDecode(raw) as List) key as String};
    } catch (error) {
      appLogger.w('IPTV guide store: unreadable coverage', error: error);
      return const {};
    }
  }

  static LiveTvProgram _programFrom(GuideProgram row) => LiveTvProgram(
    key: row.programKey,
    title: row.title,
    subtitle: row.subtitle,
    summary: row.summary,
    genres: row.genres?.split(_genreSeparator),
    country: row.country,
    year: row.year,
    beginsAt: row.beginsAt,
    endsAt: row.endsAt,
    index: row.episode,
    parentIndex: row.season,
    thumb: row.thumb,
    channelIdentifier: row.channel.isEmpty ? null : row.channel,
    channelCallSign: row.callSign,
    serverId: row.serverId,
    serverName: row.serverName,
  );
}

class _DriftGuideWriter implements IptvGuideWriter {
  _DriftGuideWriter(this._db, this._sourceId, this._generation);

  final IptvGuideDatabase _db;
  final String _sourceId;
  final int _generation;
  int _count = 0;
  int? _lastStart;

  @override
  int get count => _count;

  @override
  Future<void> add(List<LiveTvProgram> programs) async {
    if (programs.isEmpty) return;
    for (final program in programs) {
      final begins = program.beginsAt;
      if (begins != null) _lastStart = math.max(_lastStart ?? begins, begins);
    }
    _count += programs.length;
    await _db.batch((batch) {
      batch.insertAll(_db.guidePrograms, [
        for (final program in programs)
          GuideProgramsCompanion.insert(
            sourceId: _sourceId,
            generation: _generation,
            channel: program.channelIdentifier ?? '',
            beginsAt: Value(program.beginsAt),
            endsAt: Value(program.endsAt),
            programKey: Value(program.key),
            title: program.title,
            subtitle: Value(program.subtitle),
            summary: Value(program.summary),
            genres: Value(program.genres?.join(_genreSeparator)),
            country: Value(program.country),
            year: Value(program.year),
            episode: Value(program.index),
            season: Value(program.parentIndex),
            thumb: Value(program.thumb),
            callSign: Value(program.channelCallSign),
            serverId: Value(program.serverId),
            serverName: Value(program.serverName),
          ),
      ]);
    });
  }

  @override
  Future<IptvGuideState> commit({required DateTime fetchedAt, Set<String>? coverage}) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.guidePrograms,
      )..where((t) => t.sourceId.equals(_sourceId) & t.generation.equals(_generation).not())).go();
      await _db
          .into(_db.guideSources)
          .insertOnConflictUpdate(
            GuideSourcesCompanion.insert(
              sourceId: _sourceId,
              generation: _generation,
              fetchedAt: fetchedAt.millisecondsSinceEpoch,
              coverage: Value(coverage == null ? null : jsonEncode(coverage.toList())),
              lastStart: Value(_lastStart),
            ),
          );
    });
    return IptvGuideState(generation: _generation, fetchedAt: fetchedAt, coverage: coverage, lastStart: _lastStart);
  }

  @override
  Future<void> abandon() => (_db.delete(
    _db.guidePrograms,
  )..where((t) => t.sourceId.equals(_sourceId) & t.generation.equals(_generation))).go();
}

/// Kept in memory — for tests, and wherever no database is wanted.
class MemoryIptvGuideStore implements IptvGuideStore {
  final Map<String, (IptvGuideState, List<LiveTvProgram>)> _guides = {};

  @override
  Future<IptvGuideState?> state(String sourceId) async => _guides[sourceId]?.$1;

  @override
  Future<List<LiveTvProgram>> window(
    String sourceId,
    int generation, {
    int? from,
    int? to,
    Set<String>? channels,
  }) async {
    final held = _guides[sourceId];
    if (held == null || held.$1.generation != generation) return const [];
    return [
      for (final program in held.$2)
        if ((to == null || (program.beginsAt ?? 0) <= to) &&
            (from == null || (program.endsAt ?? 0) >= from) &&
            (channels == null || program.channelIdentifier == null || channels.contains(program.channelIdentifier)))
          program,
    ];
  }

  @override
  Future<IptvGuideWriter> begin(String sourceId) async =>
      _MemoryGuideWriter(this, sourceId, (_guides[sourceId]?.$1.generation ?? 0) + 1);

  @override
  Future<void> clear(String sourceId) async => _guides.remove(sourceId);
}

class _MemoryGuideWriter implements IptvGuideWriter {
  _MemoryGuideWriter(this._store, this._sourceId, this._generation);

  final MemoryIptvGuideStore _store;
  final String _sourceId;
  final int _generation;
  final List<LiveTvProgram> _rows = [];

  @override
  int get count => _rows.length;

  @override
  Future<void> add(List<LiveTvProgram> programs) async => _rows.addAll(programs);

  @override
  Future<IptvGuideState> commit({required DateTime fetchedAt, Set<String>? coverage}) async {
    _rows.sort((a, b) => (a.beginsAt ?? 0).compareTo(b.beginsAt ?? 0));
    int? lastStart;
    for (final program in _rows) {
      final begins = program.beginsAt;
      if (begins != null) lastStart = math.max(lastStart ?? begins, begins);
    }
    final state = IptvGuideState(
      generation: _generation,
      fetchedAt: fetchedAt,
      coverage: coverage,
      lastStart: lastStart,
    );
    _store._guides[_sourceId] = (state, List.unmodifiable(_rows));
    return state;
  }

  @override
  Future<void> abandon() async => _rows.clear();
}
