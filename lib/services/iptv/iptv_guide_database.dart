import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'iptv_guide_database.g.dart';

/// One programme of an IPTV source's guide (Plebz).
///
/// Rows of one source carry the [generation] they were read in: a guide read
/// again goes in under the next one, and only its last step switches the
/// source over — so the old guide is what every reader sees until the new
/// one is whole.
@TableIndex(name: 'guide_programs_window', columns: {#sourceId, #generation, #beginsAt})
class GuidePrograms extends Table {
  TextColumn get sourceId => text()();
  IntColumn get generation => integer()();

  /// The app's channel the programme is on — `LiveTvProgram.channelIdentifier`.
  TextColumn get channel => text()();
  IntColumn get beginsAt => integer().nullable()();
  IntColumn get endsAt => integer().nullable()();
  TextColumn get programKey => text().nullable()();
  TextColumn get title => text()();
  TextColumn get subtitle => text().nullable()();
  TextColumn get summary => text().nullable()();

  /// The genres joined by U+001F, a separator no guide writes.
  TextColumn get genres => text().nullable()();
  TextColumn get country => text().nullable()();
  IntColumn get year => integer().nullable()();
  IntColumn get episode => integer().nullable()();
  IntColumn get season => integer().nullable()();
  TextColumn get thumb => text().nullable()();
  TextColumn get callSign => text().nullable()();
  TextColumn get serverId => text().nullable()();
  TextColumn get serverName => text().nullable()();
}

/// Where each source's guide stands: which generation is current, when it was
/// read, for which channels, and when its last programme begins.
class GuideSources extends Table {
  TextColumn get sourceId => text()();
  IntColumn get generation => integer()();

  /// Milliseconds since the epoch.
  IntColumn get fetchedAt => integer()();

  /// The channel keys the guide was read for, as a JSON list; null for all.
  TextColumn get coverage => text().nullable()();
  IntColumn get lastStart => integer().nullable()();

  @override
  Set<Column> get primaryKey => {sourceId};
}

/// The IPTV guides, apart from the app's own database: it is a cache — lost,
/// it is read again — and a big one, rewritten whole on every guide reload.
@DriftDatabase(tables: [GuidePrograms, GuideSources])
class IptvGuideDatabase extends _$IptvGuideDatabase {
  IptvGuideDatabase(super.executor);

  /// The database file in the app's support folder, opened off the UI
  /// isolate.
  factory IptvGuideDatabase.onDisk() => IptvGuideDatabase(
    LazyDatabase(() async {
      final dir = await getApplicationSupportDirectory();
      return NativeDatabase.createInBackground(
        File(p.join(dir.path, 'iptv_guide.sqlite')),
        setup: (db) {
          db.execute('PRAGMA journal_mode=WAL');
          // A cache: a write lost to a power cut is read again, not mourned.
          db.execute('PRAGMA synchronous=OFF');
        },
      );
    }),
  );

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      // A cache has nothing worth migrating: start over.
      for (final table in allTables) {
        await m.deleteTable(table.actualTableName);
        await m.createTable(table);
      }
    },
  );
}
