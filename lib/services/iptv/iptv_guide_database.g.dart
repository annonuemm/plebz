// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'iptv_guide_database.dart';

// ignore_for_file: type=lint
class $GuideProgramsTable extends GuidePrograms
    with TableInfo<$GuideProgramsTable, GuideProgram> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GuideProgramsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _generationMeta = const VerificationMeta(
    'generation',
  );
  @override
  late final GeneratedColumn<int> generation = GeneratedColumn<int>(
    'generation',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _channelMeta = const VerificationMeta(
    'channel',
  );
  @override
  late final GeneratedColumn<String> channel = GeneratedColumn<String>(
    'channel',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _beginsAtMeta = const VerificationMeta(
    'beginsAt',
  );
  @override
  late final GeneratedColumn<int> beginsAt = GeneratedColumn<int>(
    'begins_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endsAtMeta = const VerificationMeta('endsAt');
  @override
  late final GeneratedColumn<int> endsAt = GeneratedColumn<int>(
    'ends_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _programKeyMeta = const VerificationMeta(
    'programKey',
  );
  @override
  late final GeneratedColumn<String> programKey = GeneratedColumn<String>(
    'program_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _subtitleMeta = const VerificationMeta(
    'subtitle',
  );
  @override
  late final GeneratedColumn<String> subtitle = GeneratedColumn<String>(
    'subtitle',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _summaryMeta = const VerificationMeta(
    'summary',
  );
  @override
  late final GeneratedColumn<String> summary = GeneratedColumn<String>(
    'summary',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _genresMeta = const VerificationMeta('genres');
  @override
  late final GeneratedColumn<String> genres = GeneratedColumn<String>(
    'genres',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _countryMeta = const VerificationMeta(
    'country',
  );
  @override
  late final GeneratedColumn<String> country = GeneratedColumn<String>(
    'country',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _yearMeta = const VerificationMeta('year');
  @override
  late final GeneratedColumn<int> year = GeneratedColumn<int>(
    'year',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _episodeMeta = const VerificationMeta(
    'episode',
  );
  @override
  late final GeneratedColumn<int> episode = GeneratedColumn<int>(
    'episode',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _seasonMeta = const VerificationMeta('season');
  @override
  late final GeneratedColumn<int> season = GeneratedColumn<int>(
    'season',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _thumbMeta = const VerificationMeta('thumb');
  @override
  late final GeneratedColumn<String> thumb = GeneratedColumn<String>(
    'thumb',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _callSignMeta = const VerificationMeta(
    'callSign',
  );
  @override
  late final GeneratedColumn<String> callSign = GeneratedColumn<String>(
    'call_sign',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  @override
  late final GeneratedColumn<String> serverId = GeneratedColumn<String>(
    'server_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serverNameMeta = const VerificationMeta(
    'serverName',
  );
  @override
  late final GeneratedColumn<String> serverName = GeneratedColumn<String>(
    'server_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sourceId,
    generation,
    channel,
    beginsAt,
    endsAt,
    programKey,
    title,
    subtitle,
    summary,
    genres,
    country,
    year,
    episode,
    season,
    thumb,
    callSign,
    serverId,
    serverName,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'guide_programs';
  @override
  VerificationContext validateIntegrity(
    Insertable<GuideProgram> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('generation')) {
      context.handle(
        _generationMeta,
        generation.isAcceptableOrUnknown(data['generation']!, _generationMeta),
      );
    } else if (isInserting) {
      context.missing(_generationMeta);
    }
    if (data.containsKey('channel')) {
      context.handle(
        _channelMeta,
        channel.isAcceptableOrUnknown(data['channel']!, _channelMeta),
      );
    } else if (isInserting) {
      context.missing(_channelMeta);
    }
    if (data.containsKey('begins_at')) {
      context.handle(
        _beginsAtMeta,
        beginsAt.isAcceptableOrUnknown(data['begins_at']!, _beginsAtMeta),
      );
    }
    if (data.containsKey('ends_at')) {
      context.handle(
        _endsAtMeta,
        endsAt.isAcceptableOrUnknown(data['ends_at']!, _endsAtMeta),
      );
    }
    if (data.containsKey('program_key')) {
      context.handle(
        _programKeyMeta,
        programKey.isAcceptableOrUnknown(data['program_key']!, _programKeyMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('subtitle')) {
      context.handle(
        _subtitleMeta,
        subtitle.isAcceptableOrUnknown(data['subtitle']!, _subtitleMeta),
      );
    }
    if (data.containsKey('summary')) {
      context.handle(
        _summaryMeta,
        summary.isAcceptableOrUnknown(data['summary']!, _summaryMeta),
      );
    }
    if (data.containsKey('genres')) {
      context.handle(
        _genresMeta,
        genres.isAcceptableOrUnknown(data['genres']!, _genresMeta),
      );
    }
    if (data.containsKey('country')) {
      context.handle(
        _countryMeta,
        country.isAcceptableOrUnknown(data['country']!, _countryMeta),
      );
    }
    if (data.containsKey('year')) {
      context.handle(
        _yearMeta,
        year.isAcceptableOrUnknown(data['year']!, _yearMeta),
      );
    }
    if (data.containsKey('episode')) {
      context.handle(
        _episodeMeta,
        episode.isAcceptableOrUnknown(data['episode']!, _episodeMeta),
      );
    }
    if (data.containsKey('season')) {
      context.handle(
        _seasonMeta,
        season.isAcceptableOrUnknown(data['season']!, _seasonMeta),
      );
    }
    if (data.containsKey('thumb')) {
      context.handle(
        _thumbMeta,
        thumb.isAcceptableOrUnknown(data['thumb']!, _thumbMeta),
      );
    }
    if (data.containsKey('call_sign')) {
      context.handle(
        _callSignMeta,
        callSign.isAcceptableOrUnknown(data['call_sign']!, _callSignMeta),
      );
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    }
    if (data.containsKey('server_name')) {
      context.handle(
        _serverNameMeta,
        serverName.isAcceptableOrUnknown(data['server_name']!, _serverNameMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => const {};
  @override
  GuideProgram map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GuideProgram(
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      )!,
      generation: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}generation'],
      )!,
      channel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}channel'],
      )!,
      beginsAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}begins_at'],
      ),
      endsAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ends_at'],
      ),
      programKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}program_key'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      subtitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subtitle'],
      ),
      summary: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}summary'],
      ),
      genres: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}genres'],
      ),
      country: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}country'],
      ),
      year: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}year'],
      ),
      episode: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}episode'],
      ),
      season: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}season'],
      ),
      thumb: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumb'],
      ),
      callSign: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}call_sign'],
      ),
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_id'],
      ),
      serverName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_name'],
      ),
    );
  }

  @override
  $GuideProgramsTable createAlias(String alias) {
    return $GuideProgramsTable(attachedDatabase, alias);
  }
}

class GuideProgram extends DataClass implements Insertable<GuideProgram> {
  final String sourceId;
  final int generation;

  /// The app's channel the programme is on — `LiveTvProgram.channelIdentifier`.
  final String channel;
  final int? beginsAt;
  final int? endsAt;
  final String? programKey;
  final String title;
  final String? subtitle;
  final String? summary;

  /// The genres joined by U+001F, a separator no guide writes.
  final String? genres;
  final String? country;
  final int? year;
  final int? episode;
  final int? season;
  final String? thumb;
  final String? callSign;
  final String? serverId;
  final String? serverName;
  const GuideProgram({
    required this.sourceId,
    required this.generation,
    required this.channel,
    this.beginsAt,
    this.endsAt,
    this.programKey,
    required this.title,
    this.subtitle,
    this.summary,
    this.genres,
    this.country,
    this.year,
    this.episode,
    this.season,
    this.thumb,
    this.callSign,
    this.serverId,
    this.serverName,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_id'] = Variable<String>(sourceId);
    map['generation'] = Variable<int>(generation);
    map['channel'] = Variable<String>(channel);
    if (!nullToAbsent || beginsAt != null) {
      map['begins_at'] = Variable<int>(beginsAt);
    }
    if (!nullToAbsent || endsAt != null) {
      map['ends_at'] = Variable<int>(endsAt);
    }
    if (!nullToAbsent || programKey != null) {
      map['program_key'] = Variable<String>(programKey);
    }
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || subtitle != null) {
      map['subtitle'] = Variable<String>(subtitle);
    }
    if (!nullToAbsent || summary != null) {
      map['summary'] = Variable<String>(summary);
    }
    if (!nullToAbsent || genres != null) {
      map['genres'] = Variable<String>(genres);
    }
    if (!nullToAbsent || country != null) {
      map['country'] = Variable<String>(country);
    }
    if (!nullToAbsent || year != null) {
      map['year'] = Variable<int>(year);
    }
    if (!nullToAbsent || episode != null) {
      map['episode'] = Variable<int>(episode);
    }
    if (!nullToAbsent || season != null) {
      map['season'] = Variable<int>(season);
    }
    if (!nullToAbsent || thumb != null) {
      map['thumb'] = Variable<String>(thumb);
    }
    if (!nullToAbsent || callSign != null) {
      map['call_sign'] = Variable<String>(callSign);
    }
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<String>(serverId);
    }
    if (!nullToAbsent || serverName != null) {
      map['server_name'] = Variable<String>(serverName);
    }
    return map;
  }

  GuideProgramsCompanion toCompanion(bool nullToAbsent) {
    return GuideProgramsCompanion(
      sourceId: Value(sourceId),
      generation: Value(generation),
      channel: Value(channel),
      beginsAt: beginsAt == null && nullToAbsent
          ? const Value.absent()
          : Value(beginsAt),
      endsAt: endsAt == null && nullToAbsent
          ? const Value.absent()
          : Value(endsAt),
      programKey: programKey == null && nullToAbsent
          ? const Value.absent()
          : Value(programKey),
      title: Value(title),
      subtitle: subtitle == null && nullToAbsent
          ? const Value.absent()
          : Value(subtitle),
      summary: summary == null && nullToAbsent
          ? const Value.absent()
          : Value(summary),
      genres: genres == null && nullToAbsent
          ? const Value.absent()
          : Value(genres),
      country: country == null && nullToAbsent
          ? const Value.absent()
          : Value(country),
      year: year == null && nullToAbsent ? const Value.absent() : Value(year),
      episode: episode == null && nullToAbsent
          ? const Value.absent()
          : Value(episode),
      season: season == null && nullToAbsent
          ? const Value.absent()
          : Value(season),
      thumb: thumb == null && nullToAbsent
          ? const Value.absent()
          : Value(thumb),
      callSign: callSign == null && nullToAbsent
          ? const Value.absent()
          : Value(callSign),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
      serverName: serverName == null && nullToAbsent
          ? const Value.absent()
          : Value(serverName),
    );
  }

  factory GuideProgram.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GuideProgram(
      sourceId: serializer.fromJson<String>(json['sourceId']),
      generation: serializer.fromJson<int>(json['generation']),
      channel: serializer.fromJson<String>(json['channel']),
      beginsAt: serializer.fromJson<int?>(json['beginsAt']),
      endsAt: serializer.fromJson<int?>(json['endsAt']),
      programKey: serializer.fromJson<String?>(json['programKey']),
      title: serializer.fromJson<String>(json['title']),
      subtitle: serializer.fromJson<String?>(json['subtitle']),
      summary: serializer.fromJson<String?>(json['summary']),
      genres: serializer.fromJson<String?>(json['genres']),
      country: serializer.fromJson<String?>(json['country']),
      year: serializer.fromJson<int?>(json['year']),
      episode: serializer.fromJson<int?>(json['episode']),
      season: serializer.fromJson<int?>(json['season']),
      thumb: serializer.fromJson<String?>(json['thumb']),
      callSign: serializer.fromJson<String?>(json['callSign']),
      serverId: serializer.fromJson<String?>(json['serverId']),
      serverName: serializer.fromJson<String?>(json['serverName']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sourceId': serializer.toJson<String>(sourceId),
      'generation': serializer.toJson<int>(generation),
      'channel': serializer.toJson<String>(channel),
      'beginsAt': serializer.toJson<int?>(beginsAt),
      'endsAt': serializer.toJson<int?>(endsAt),
      'programKey': serializer.toJson<String?>(programKey),
      'title': serializer.toJson<String>(title),
      'subtitle': serializer.toJson<String?>(subtitle),
      'summary': serializer.toJson<String?>(summary),
      'genres': serializer.toJson<String?>(genres),
      'country': serializer.toJson<String?>(country),
      'year': serializer.toJson<int?>(year),
      'episode': serializer.toJson<int?>(episode),
      'season': serializer.toJson<int?>(season),
      'thumb': serializer.toJson<String?>(thumb),
      'callSign': serializer.toJson<String?>(callSign),
      'serverId': serializer.toJson<String?>(serverId),
      'serverName': serializer.toJson<String?>(serverName),
    };
  }

  GuideProgram copyWith({
    String? sourceId,
    int? generation,
    String? channel,
    Value<int?> beginsAt = const Value.absent(),
    Value<int?> endsAt = const Value.absent(),
    Value<String?> programKey = const Value.absent(),
    String? title,
    Value<String?> subtitle = const Value.absent(),
    Value<String?> summary = const Value.absent(),
    Value<String?> genres = const Value.absent(),
    Value<String?> country = const Value.absent(),
    Value<int?> year = const Value.absent(),
    Value<int?> episode = const Value.absent(),
    Value<int?> season = const Value.absent(),
    Value<String?> thumb = const Value.absent(),
    Value<String?> callSign = const Value.absent(),
    Value<String?> serverId = const Value.absent(),
    Value<String?> serverName = const Value.absent(),
  }) => GuideProgram(
    sourceId: sourceId ?? this.sourceId,
    generation: generation ?? this.generation,
    channel: channel ?? this.channel,
    beginsAt: beginsAt.present ? beginsAt.value : this.beginsAt,
    endsAt: endsAt.present ? endsAt.value : this.endsAt,
    programKey: programKey.present ? programKey.value : this.programKey,
    title: title ?? this.title,
    subtitle: subtitle.present ? subtitle.value : this.subtitle,
    summary: summary.present ? summary.value : this.summary,
    genres: genres.present ? genres.value : this.genres,
    country: country.present ? country.value : this.country,
    year: year.present ? year.value : this.year,
    episode: episode.present ? episode.value : this.episode,
    season: season.present ? season.value : this.season,
    thumb: thumb.present ? thumb.value : this.thumb,
    callSign: callSign.present ? callSign.value : this.callSign,
    serverId: serverId.present ? serverId.value : this.serverId,
    serverName: serverName.present ? serverName.value : this.serverName,
  );
  GuideProgram copyWithCompanion(GuideProgramsCompanion data) {
    return GuideProgram(
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      generation: data.generation.present
          ? data.generation.value
          : this.generation,
      channel: data.channel.present ? data.channel.value : this.channel,
      beginsAt: data.beginsAt.present ? data.beginsAt.value : this.beginsAt,
      endsAt: data.endsAt.present ? data.endsAt.value : this.endsAt,
      programKey: data.programKey.present
          ? data.programKey.value
          : this.programKey,
      title: data.title.present ? data.title.value : this.title,
      subtitle: data.subtitle.present ? data.subtitle.value : this.subtitle,
      summary: data.summary.present ? data.summary.value : this.summary,
      genres: data.genres.present ? data.genres.value : this.genres,
      country: data.country.present ? data.country.value : this.country,
      year: data.year.present ? data.year.value : this.year,
      episode: data.episode.present ? data.episode.value : this.episode,
      season: data.season.present ? data.season.value : this.season,
      thumb: data.thumb.present ? data.thumb.value : this.thumb,
      callSign: data.callSign.present ? data.callSign.value : this.callSign,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      serverName: data.serverName.present
          ? data.serverName.value
          : this.serverName,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GuideProgram(')
          ..write('sourceId: $sourceId, ')
          ..write('generation: $generation, ')
          ..write('channel: $channel, ')
          ..write('beginsAt: $beginsAt, ')
          ..write('endsAt: $endsAt, ')
          ..write('programKey: $programKey, ')
          ..write('title: $title, ')
          ..write('subtitle: $subtitle, ')
          ..write('summary: $summary, ')
          ..write('genres: $genres, ')
          ..write('country: $country, ')
          ..write('year: $year, ')
          ..write('episode: $episode, ')
          ..write('season: $season, ')
          ..write('thumb: $thumb, ')
          ..write('callSign: $callSign, ')
          ..write('serverId: $serverId, ')
          ..write('serverName: $serverName')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sourceId,
    generation,
    channel,
    beginsAt,
    endsAt,
    programKey,
    title,
    subtitle,
    summary,
    genres,
    country,
    year,
    episode,
    season,
    thumb,
    callSign,
    serverId,
    serverName,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GuideProgram &&
          other.sourceId == this.sourceId &&
          other.generation == this.generation &&
          other.channel == this.channel &&
          other.beginsAt == this.beginsAt &&
          other.endsAt == this.endsAt &&
          other.programKey == this.programKey &&
          other.title == this.title &&
          other.subtitle == this.subtitle &&
          other.summary == this.summary &&
          other.genres == this.genres &&
          other.country == this.country &&
          other.year == this.year &&
          other.episode == this.episode &&
          other.season == this.season &&
          other.thumb == this.thumb &&
          other.callSign == this.callSign &&
          other.serverId == this.serverId &&
          other.serverName == this.serverName);
}

class GuideProgramsCompanion extends UpdateCompanion<GuideProgram> {
  final Value<String> sourceId;
  final Value<int> generation;
  final Value<String> channel;
  final Value<int?> beginsAt;
  final Value<int?> endsAt;
  final Value<String?> programKey;
  final Value<String> title;
  final Value<String?> subtitle;
  final Value<String?> summary;
  final Value<String?> genres;
  final Value<String?> country;
  final Value<int?> year;
  final Value<int?> episode;
  final Value<int?> season;
  final Value<String?> thumb;
  final Value<String?> callSign;
  final Value<String?> serverId;
  final Value<String?> serverName;
  final Value<int> rowid;
  const GuideProgramsCompanion({
    this.sourceId = const Value.absent(),
    this.generation = const Value.absent(),
    this.channel = const Value.absent(),
    this.beginsAt = const Value.absent(),
    this.endsAt = const Value.absent(),
    this.programKey = const Value.absent(),
    this.title = const Value.absent(),
    this.subtitle = const Value.absent(),
    this.summary = const Value.absent(),
    this.genres = const Value.absent(),
    this.country = const Value.absent(),
    this.year = const Value.absent(),
    this.episode = const Value.absent(),
    this.season = const Value.absent(),
    this.thumb = const Value.absent(),
    this.callSign = const Value.absent(),
    this.serverId = const Value.absent(),
    this.serverName = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GuideProgramsCompanion.insert({
    required String sourceId,
    required int generation,
    required String channel,
    this.beginsAt = const Value.absent(),
    this.endsAt = const Value.absent(),
    this.programKey = const Value.absent(),
    required String title,
    this.subtitle = const Value.absent(),
    this.summary = const Value.absent(),
    this.genres = const Value.absent(),
    this.country = const Value.absent(),
    this.year = const Value.absent(),
    this.episode = const Value.absent(),
    this.season = const Value.absent(),
    this.thumb = const Value.absent(),
    this.callSign = const Value.absent(),
    this.serverId = const Value.absent(),
    this.serverName = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : sourceId = Value(sourceId),
       generation = Value(generation),
       channel = Value(channel),
       title = Value(title);
  static Insertable<GuideProgram> custom({
    Expression<String>? sourceId,
    Expression<int>? generation,
    Expression<String>? channel,
    Expression<int>? beginsAt,
    Expression<int>? endsAt,
    Expression<String>? programKey,
    Expression<String>? title,
    Expression<String>? subtitle,
    Expression<String>? summary,
    Expression<String>? genres,
    Expression<String>? country,
    Expression<int>? year,
    Expression<int>? episode,
    Expression<int>? season,
    Expression<String>? thumb,
    Expression<String>? callSign,
    Expression<String>? serverId,
    Expression<String>? serverName,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sourceId != null) 'source_id': sourceId,
      if (generation != null) 'generation': generation,
      if (channel != null) 'channel': channel,
      if (beginsAt != null) 'begins_at': beginsAt,
      if (endsAt != null) 'ends_at': endsAt,
      if (programKey != null) 'program_key': programKey,
      if (title != null) 'title': title,
      if (subtitle != null) 'subtitle': subtitle,
      if (summary != null) 'summary': summary,
      if (genres != null) 'genres': genres,
      if (country != null) 'country': country,
      if (year != null) 'year': year,
      if (episode != null) 'episode': episode,
      if (season != null) 'season': season,
      if (thumb != null) 'thumb': thumb,
      if (callSign != null) 'call_sign': callSign,
      if (serverId != null) 'server_id': serverId,
      if (serverName != null) 'server_name': serverName,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GuideProgramsCompanion copyWith({
    Value<String>? sourceId,
    Value<int>? generation,
    Value<String>? channel,
    Value<int?>? beginsAt,
    Value<int?>? endsAt,
    Value<String?>? programKey,
    Value<String>? title,
    Value<String?>? subtitle,
    Value<String?>? summary,
    Value<String?>? genres,
    Value<String?>? country,
    Value<int?>? year,
    Value<int?>? episode,
    Value<int?>? season,
    Value<String?>? thumb,
    Value<String?>? callSign,
    Value<String?>? serverId,
    Value<String?>? serverName,
    Value<int>? rowid,
  }) {
    return GuideProgramsCompanion(
      sourceId: sourceId ?? this.sourceId,
      generation: generation ?? this.generation,
      channel: channel ?? this.channel,
      beginsAt: beginsAt ?? this.beginsAt,
      endsAt: endsAt ?? this.endsAt,
      programKey: programKey ?? this.programKey,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      summary: summary ?? this.summary,
      genres: genres ?? this.genres,
      country: country ?? this.country,
      year: year ?? this.year,
      episode: episode ?? this.episode,
      season: season ?? this.season,
      thumb: thumb ?? this.thumb,
      callSign: callSign ?? this.callSign,
      serverId: serverId ?? this.serverId,
      serverName: serverName ?? this.serverName,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (generation.present) {
      map['generation'] = Variable<int>(generation.value);
    }
    if (channel.present) {
      map['channel'] = Variable<String>(channel.value);
    }
    if (beginsAt.present) {
      map['begins_at'] = Variable<int>(beginsAt.value);
    }
    if (endsAt.present) {
      map['ends_at'] = Variable<int>(endsAt.value);
    }
    if (programKey.present) {
      map['program_key'] = Variable<String>(programKey.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (subtitle.present) {
      map['subtitle'] = Variable<String>(subtitle.value);
    }
    if (summary.present) {
      map['summary'] = Variable<String>(summary.value);
    }
    if (genres.present) {
      map['genres'] = Variable<String>(genres.value);
    }
    if (country.present) {
      map['country'] = Variable<String>(country.value);
    }
    if (year.present) {
      map['year'] = Variable<int>(year.value);
    }
    if (episode.present) {
      map['episode'] = Variable<int>(episode.value);
    }
    if (season.present) {
      map['season'] = Variable<int>(season.value);
    }
    if (thumb.present) {
      map['thumb'] = Variable<String>(thumb.value);
    }
    if (callSign.present) {
      map['call_sign'] = Variable<String>(callSign.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    if (serverName.present) {
      map['server_name'] = Variable<String>(serverName.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GuideProgramsCompanion(')
          ..write('sourceId: $sourceId, ')
          ..write('generation: $generation, ')
          ..write('channel: $channel, ')
          ..write('beginsAt: $beginsAt, ')
          ..write('endsAt: $endsAt, ')
          ..write('programKey: $programKey, ')
          ..write('title: $title, ')
          ..write('subtitle: $subtitle, ')
          ..write('summary: $summary, ')
          ..write('genres: $genres, ')
          ..write('country: $country, ')
          ..write('year: $year, ')
          ..write('episode: $episode, ')
          ..write('season: $season, ')
          ..write('thumb: $thumb, ')
          ..write('callSign: $callSign, ')
          ..write('serverId: $serverId, ')
          ..write('serverName: $serverName, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GuideSourcesTable extends GuideSources
    with TableInfo<$GuideSourcesTable, GuideSource> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GuideSourcesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _generationMeta = const VerificationMeta(
    'generation',
  );
  @override
  late final GeneratedColumn<int> generation = GeneratedColumn<int>(
    'generation',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<int> fetchedAt = GeneratedColumn<int>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _coverageMeta = const VerificationMeta(
    'coverage',
  );
  @override
  late final GeneratedColumn<String> coverage = GeneratedColumn<String>(
    'coverage',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastStartMeta = const VerificationMeta(
    'lastStart',
  );
  @override
  late final GeneratedColumn<int> lastStart = GeneratedColumn<int>(
    'last_start',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sourceId,
    generation,
    fetchedAt,
    coverage,
    lastStart,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'guide_sources';
  @override
  VerificationContext validateIntegrity(
    Insertable<GuideSource> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('generation')) {
      context.handle(
        _generationMeta,
        generation.isAcceptableOrUnknown(data['generation']!, _generationMeta),
      );
    } else if (isInserting) {
      context.missing(_generationMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    if (data.containsKey('coverage')) {
      context.handle(
        _coverageMeta,
        coverage.isAcceptableOrUnknown(data['coverage']!, _coverageMeta),
      );
    }
    if (data.containsKey('last_start')) {
      context.handle(
        _lastStartMeta,
        lastStart.isAcceptableOrUnknown(data['last_start']!, _lastStartMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sourceId};
  @override
  GuideSource map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GuideSource(
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      )!,
      generation: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}generation'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fetched_at'],
      )!,
      coverage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}coverage'],
      ),
      lastStart: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_start'],
      ),
    );
  }

  @override
  $GuideSourcesTable createAlias(String alias) {
    return $GuideSourcesTable(attachedDatabase, alias);
  }
}

class GuideSource extends DataClass implements Insertable<GuideSource> {
  final String sourceId;
  final int generation;

  /// Milliseconds since the epoch.
  final int fetchedAt;

  /// The channel keys the guide was read for, as a JSON list; null for all.
  final String? coverage;
  final int? lastStart;
  const GuideSource({
    required this.sourceId,
    required this.generation,
    required this.fetchedAt,
    this.coverage,
    this.lastStart,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_id'] = Variable<String>(sourceId);
    map['generation'] = Variable<int>(generation);
    map['fetched_at'] = Variable<int>(fetchedAt);
    if (!nullToAbsent || coverage != null) {
      map['coverage'] = Variable<String>(coverage);
    }
    if (!nullToAbsent || lastStart != null) {
      map['last_start'] = Variable<int>(lastStart);
    }
    return map;
  }

  GuideSourcesCompanion toCompanion(bool nullToAbsent) {
    return GuideSourcesCompanion(
      sourceId: Value(sourceId),
      generation: Value(generation),
      fetchedAt: Value(fetchedAt),
      coverage: coverage == null && nullToAbsent
          ? const Value.absent()
          : Value(coverage),
      lastStart: lastStart == null && nullToAbsent
          ? const Value.absent()
          : Value(lastStart),
    );
  }

  factory GuideSource.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GuideSource(
      sourceId: serializer.fromJson<String>(json['sourceId']),
      generation: serializer.fromJson<int>(json['generation']),
      fetchedAt: serializer.fromJson<int>(json['fetchedAt']),
      coverage: serializer.fromJson<String?>(json['coverage']),
      lastStart: serializer.fromJson<int?>(json['lastStart']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sourceId': serializer.toJson<String>(sourceId),
      'generation': serializer.toJson<int>(generation),
      'fetchedAt': serializer.toJson<int>(fetchedAt),
      'coverage': serializer.toJson<String?>(coverage),
      'lastStart': serializer.toJson<int?>(lastStart),
    };
  }

  GuideSource copyWith({
    String? sourceId,
    int? generation,
    int? fetchedAt,
    Value<String?> coverage = const Value.absent(),
    Value<int?> lastStart = const Value.absent(),
  }) => GuideSource(
    sourceId: sourceId ?? this.sourceId,
    generation: generation ?? this.generation,
    fetchedAt: fetchedAt ?? this.fetchedAt,
    coverage: coverage.present ? coverage.value : this.coverage,
    lastStart: lastStart.present ? lastStart.value : this.lastStart,
  );
  GuideSource copyWithCompanion(GuideSourcesCompanion data) {
    return GuideSource(
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      generation: data.generation.present
          ? data.generation.value
          : this.generation,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
      coverage: data.coverage.present ? data.coverage.value : this.coverage,
      lastStart: data.lastStart.present ? data.lastStart.value : this.lastStart,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GuideSource(')
          ..write('sourceId: $sourceId, ')
          ..write('generation: $generation, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('coverage: $coverage, ')
          ..write('lastStart: $lastStart')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(sourceId, generation, fetchedAt, coverage, lastStart);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GuideSource &&
          other.sourceId == this.sourceId &&
          other.generation == this.generation &&
          other.fetchedAt == this.fetchedAt &&
          other.coverage == this.coverage &&
          other.lastStart == this.lastStart);
}

class GuideSourcesCompanion extends UpdateCompanion<GuideSource> {
  final Value<String> sourceId;
  final Value<int> generation;
  final Value<int> fetchedAt;
  final Value<String?> coverage;
  final Value<int?> lastStart;
  final Value<int> rowid;
  const GuideSourcesCompanion({
    this.sourceId = const Value.absent(),
    this.generation = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.coverage = const Value.absent(),
    this.lastStart = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GuideSourcesCompanion.insert({
    required String sourceId,
    required int generation,
    required int fetchedAt,
    this.coverage = const Value.absent(),
    this.lastStart = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : sourceId = Value(sourceId),
       generation = Value(generation),
       fetchedAt = Value(fetchedAt);
  static Insertable<GuideSource> custom({
    Expression<String>? sourceId,
    Expression<int>? generation,
    Expression<int>? fetchedAt,
    Expression<String>? coverage,
    Expression<int>? lastStart,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sourceId != null) 'source_id': sourceId,
      if (generation != null) 'generation': generation,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (coverage != null) 'coverage': coverage,
      if (lastStart != null) 'last_start': lastStart,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GuideSourcesCompanion copyWith({
    Value<String>? sourceId,
    Value<int>? generation,
    Value<int>? fetchedAt,
    Value<String?>? coverage,
    Value<int?>? lastStart,
    Value<int>? rowid,
  }) {
    return GuideSourcesCompanion(
      sourceId: sourceId ?? this.sourceId,
      generation: generation ?? this.generation,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      coverage: coverage ?? this.coverage,
      lastStart: lastStart ?? this.lastStart,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (generation.present) {
      map['generation'] = Variable<int>(generation.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<int>(fetchedAt.value);
    }
    if (coverage.present) {
      map['coverage'] = Variable<String>(coverage.value);
    }
    if (lastStart.present) {
      map['last_start'] = Variable<int>(lastStart.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GuideSourcesCompanion(')
          ..write('sourceId: $sourceId, ')
          ..write('generation: $generation, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('coverage: $coverage, ')
          ..write('lastStart: $lastStart, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$IptvGuideDatabase extends GeneratedDatabase {
  _$IptvGuideDatabase(QueryExecutor e) : super(e);
  $IptvGuideDatabaseManager get managers => $IptvGuideDatabaseManager(this);
  late final $GuideProgramsTable guidePrograms = $GuideProgramsTable(this);
  late final $GuideSourcesTable guideSources = $GuideSourcesTable(this);
  late final Index guideProgramsWindow = Index(
    'guide_programs_window',
    'CREATE INDEX guide_programs_window ON guide_programs (source_id, generation, begins_at)',
  );
  late final Index guideProgramsChannel = Index(
    'guide_programs_channel',
    'CREATE INDEX guide_programs_channel ON guide_programs (source_id, generation, channel, begins_at)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    guidePrograms,
    guideSources,
    guideProgramsWindow,
    guideProgramsChannel,
  ];
}

typedef $$GuideProgramsTableCreateCompanionBuilder =
    GuideProgramsCompanion Function({
      required String sourceId,
      required int generation,
      required String channel,
      Value<int?> beginsAt,
      Value<int?> endsAt,
      Value<String?> programKey,
      required String title,
      Value<String?> subtitle,
      Value<String?> summary,
      Value<String?> genres,
      Value<String?> country,
      Value<int?> year,
      Value<int?> episode,
      Value<int?> season,
      Value<String?> thumb,
      Value<String?> callSign,
      Value<String?> serverId,
      Value<String?> serverName,
      Value<int> rowid,
    });
typedef $$GuideProgramsTableUpdateCompanionBuilder =
    GuideProgramsCompanion Function({
      Value<String> sourceId,
      Value<int> generation,
      Value<String> channel,
      Value<int?> beginsAt,
      Value<int?> endsAt,
      Value<String?> programKey,
      Value<String> title,
      Value<String?> subtitle,
      Value<String?> summary,
      Value<String?> genres,
      Value<String?> country,
      Value<int?> year,
      Value<int?> episode,
      Value<int?> season,
      Value<String?> thumb,
      Value<String?> callSign,
      Value<String?> serverId,
      Value<String?> serverName,
      Value<int> rowid,
    });

class $$GuideProgramsTableFilterComposer
    extends Composer<_$IptvGuideDatabase, $GuideProgramsTable> {
  $$GuideProgramsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get generation => $composableBuilder(
    column: $table.generation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get channel => $composableBuilder(
    column: $table.channel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get beginsAt => $composableBuilder(
    column: $table.beginsAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endsAt => $composableBuilder(
    column: $table.endsAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get programKey => $composableBuilder(
    column: $table.programKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subtitle => $composableBuilder(
    column: $table.subtitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get genres => $composableBuilder(
    column: $table.genres,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get country => $composableBuilder(
    column: $table.country,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get episode => $composableBuilder(
    column: $table.episode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get season => $composableBuilder(
    column: $table.season,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumb => $composableBuilder(
    column: $table.thumb,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get callSign => $composableBuilder(
    column: $table.callSign,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverName => $composableBuilder(
    column: $table.serverName,
    builder: (column) => ColumnFilters(column),
  );
}

class $$GuideProgramsTableOrderingComposer
    extends Composer<_$IptvGuideDatabase, $GuideProgramsTable> {
  $$GuideProgramsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get generation => $composableBuilder(
    column: $table.generation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get channel => $composableBuilder(
    column: $table.channel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get beginsAt => $composableBuilder(
    column: $table.beginsAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endsAt => $composableBuilder(
    column: $table.endsAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get programKey => $composableBuilder(
    column: $table.programKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subtitle => $composableBuilder(
    column: $table.subtitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get genres => $composableBuilder(
    column: $table.genres,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get country => $composableBuilder(
    column: $table.country,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get episode => $composableBuilder(
    column: $table.episode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get season => $composableBuilder(
    column: $table.season,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumb => $composableBuilder(
    column: $table.thumb,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get callSign => $composableBuilder(
    column: $table.callSign,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverName => $composableBuilder(
    column: $table.serverName,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GuideProgramsTableAnnotationComposer
    extends Composer<_$IptvGuideDatabase, $GuideProgramsTable> {
  $$GuideProgramsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<int> get generation => $composableBuilder(
    column: $table.generation,
    builder: (column) => column,
  );

  GeneratedColumn<String> get channel =>
      $composableBuilder(column: $table.channel, builder: (column) => column);

  GeneratedColumn<int> get beginsAt =>
      $composableBuilder(column: $table.beginsAt, builder: (column) => column);

  GeneratedColumn<int> get endsAt =>
      $composableBuilder(column: $table.endsAt, builder: (column) => column);

  GeneratedColumn<String> get programKey => $composableBuilder(
    column: $table.programKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get subtitle =>
      $composableBuilder(column: $table.subtitle, builder: (column) => column);

  GeneratedColumn<String> get summary =>
      $composableBuilder(column: $table.summary, builder: (column) => column);

  GeneratedColumn<String> get genres =>
      $composableBuilder(column: $table.genres, builder: (column) => column);

  GeneratedColumn<String> get country =>
      $composableBuilder(column: $table.country, builder: (column) => column);

  GeneratedColumn<int> get year =>
      $composableBuilder(column: $table.year, builder: (column) => column);

  GeneratedColumn<int> get episode =>
      $composableBuilder(column: $table.episode, builder: (column) => column);

  GeneratedColumn<int> get season =>
      $composableBuilder(column: $table.season, builder: (column) => column);

  GeneratedColumn<String> get thumb =>
      $composableBuilder(column: $table.thumb, builder: (column) => column);

  GeneratedColumn<String> get callSign =>
      $composableBuilder(column: $table.callSign, builder: (column) => column);

  GeneratedColumn<String> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get serverName => $composableBuilder(
    column: $table.serverName,
    builder: (column) => column,
  );
}

class $$GuideProgramsTableTableManager
    extends
        RootTableManager<
          _$IptvGuideDatabase,
          $GuideProgramsTable,
          GuideProgram,
          $$GuideProgramsTableFilterComposer,
          $$GuideProgramsTableOrderingComposer,
          $$GuideProgramsTableAnnotationComposer,
          $$GuideProgramsTableCreateCompanionBuilder,
          $$GuideProgramsTableUpdateCompanionBuilder,
          (
            GuideProgram,
            BaseReferences<
              _$IptvGuideDatabase,
              $GuideProgramsTable,
              GuideProgram
            >,
          ),
          GuideProgram,
          PrefetchHooks Function()
        > {
  $$GuideProgramsTableTableManager(
    _$IptvGuideDatabase db,
    $GuideProgramsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GuideProgramsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GuideProgramsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GuideProgramsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sourceId = const Value.absent(),
                Value<int> generation = const Value.absent(),
                Value<String> channel = const Value.absent(),
                Value<int?> beginsAt = const Value.absent(),
                Value<int?> endsAt = const Value.absent(),
                Value<String?> programKey = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> subtitle = const Value.absent(),
                Value<String?> summary = const Value.absent(),
                Value<String?> genres = const Value.absent(),
                Value<String?> country = const Value.absent(),
                Value<int?> year = const Value.absent(),
                Value<int?> episode = const Value.absent(),
                Value<int?> season = const Value.absent(),
                Value<String?> thumb = const Value.absent(),
                Value<String?> callSign = const Value.absent(),
                Value<String?> serverId = const Value.absent(),
                Value<String?> serverName = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GuideProgramsCompanion(
                sourceId: sourceId,
                generation: generation,
                channel: channel,
                beginsAt: beginsAt,
                endsAt: endsAt,
                programKey: programKey,
                title: title,
                subtitle: subtitle,
                summary: summary,
                genres: genres,
                country: country,
                year: year,
                episode: episode,
                season: season,
                thumb: thumb,
                callSign: callSign,
                serverId: serverId,
                serverName: serverName,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sourceId,
                required int generation,
                required String channel,
                Value<int?> beginsAt = const Value.absent(),
                Value<int?> endsAt = const Value.absent(),
                Value<String?> programKey = const Value.absent(),
                required String title,
                Value<String?> subtitle = const Value.absent(),
                Value<String?> summary = const Value.absent(),
                Value<String?> genres = const Value.absent(),
                Value<String?> country = const Value.absent(),
                Value<int?> year = const Value.absent(),
                Value<int?> episode = const Value.absent(),
                Value<int?> season = const Value.absent(),
                Value<String?> thumb = const Value.absent(),
                Value<String?> callSign = const Value.absent(),
                Value<String?> serverId = const Value.absent(),
                Value<String?> serverName = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GuideProgramsCompanion.insert(
                sourceId: sourceId,
                generation: generation,
                channel: channel,
                beginsAt: beginsAt,
                endsAt: endsAt,
                programKey: programKey,
                title: title,
                subtitle: subtitle,
                summary: summary,
                genres: genres,
                country: country,
                year: year,
                episode: episode,
                season: season,
                thumb: thumb,
                callSign: callSign,
                serverId: serverId,
                serverName: serverName,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$GuideProgramsTableProcessedTableManager =
    ProcessedTableManager<
      _$IptvGuideDatabase,
      $GuideProgramsTable,
      GuideProgram,
      $$GuideProgramsTableFilterComposer,
      $$GuideProgramsTableOrderingComposer,
      $$GuideProgramsTableAnnotationComposer,
      $$GuideProgramsTableCreateCompanionBuilder,
      $$GuideProgramsTableUpdateCompanionBuilder,
      (
        GuideProgram,
        BaseReferences<_$IptvGuideDatabase, $GuideProgramsTable, GuideProgram>,
      ),
      GuideProgram,
      PrefetchHooks Function()
    >;
typedef $$GuideSourcesTableCreateCompanionBuilder =
    GuideSourcesCompanion Function({
      required String sourceId,
      required int generation,
      required int fetchedAt,
      Value<String?> coverage,
      Value<int?> lastStart,
      Value<int> rowid,
    });
typedef $$GuideSourcesTableUpdateCompanionBuilder =
    GuideSourcesCompanion Function({
      Value<String> sourceId,
      Value<int> generation,
      Value<int> fetchedAt,
      Value<String?> coverage,
      Value<int?> lastStart,
      Value<int> rowid,
    });

class $$GuideSourcesTableFilterComposer
    extends Composer<_$IptvGuideDatabase, $GuideSourcesTable> {
  $$GuideSourcesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get generation => $composableBuilder(
    column: $table.generation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverage => $composableBuilder(
    column: $table.coverage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastStart => $composableBuilder(
    column: $table.lastStart,
    builder: (column) => ColumnFilters(column),
  );
}

class $$GuideSourcesTableOrderingComposer
    extends Composer<_$IptvGuideDatabase, $GuideSourcesTable> {
  $$GuideSourcesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get generation => $composableBuilder(
    column: $table.generation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverage => $composableBuilder(
    column: $table.coverage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastStart => $composableBuilder(
    column: $table.lastStart,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GuideSourcesTableAnnotationComposer
    extends Composer<_$IptvGuideDatabase, $GuideSourcesTable> {
  $$GuideSourcesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<int> get generation => $composableBuilder(
    column: $table.generation,
    builder: (column) => column,
  );

  GeneratedColumn<int> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);

  GeneratedColumn<String> get coverage =>
      $composableBuilder(column: $table.coverage, builder: (column) => column);

  GeneratedColumn<int> get lastStart =>
      $composableBuilder(column: $table.lastStart, builder: (column) => column);
}

class $$GuideSourcesTableTableManager
    extends
        RootTableManager<
          _$IptvGuideDatabase,
          $GuideSourcesTable,
          GuideSource,
          $$GuideSourcesTableFilterComposer,
          $$GuideSourcesTableOrderingComposer,
          $$GuideSourcesTableAnnotationComposer,
          $$GuideSourcesTableCreateCompanionBuilder,
          $$GuideSourcesTableUpdateCompanionBuilder,
          (
            GuideSource,
            BaseReferences<
              _$IptvGuideDatabase,
              $GuideSourcesTable,
              GuideSource
            >,
          ),
          GuideSource,
          PrefetchHooks Function()
        > {
  $$GuideSourcesTableTableManager(
    _$IptvGuideDatabase db,
    $GuideSourcesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GuideSourcesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GuideSourcesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GuideSourcesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sourceId = const Value.absent(),
                Value<int> generation = const Value.absent(),
                Value<int> fetchedAt = const Value.absent(),
                Value<String?> coverage = const Value.absent(),
                Value<int?> lastStart = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GuideSourcesCompanion(
                sourceId: sourceId,
                generation: generation,
                fetchedAt: fetchedAt,
                coverage: coverage,
                lastStart: lastStart,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sourceId,
                required int generation,
                required int fetchedAt,
                Value<String?> coverage = const Value.absent(),
                Value<int?> lastStart = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GuideSourcesCompanion.insert(
                sourceId: sourceId,
                generation: generation,
                fetchedAt: fetchedAt,
                coverage: coverage,
                lastStart: lastStart,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$GuideSourcesTableProcessedTableManager =
    ProcessedTableManager<
      _$IptvGuideDatabase,
      $GuideSourcesTable,
      GuideSource,
      $$GuideSourcesTableFilterComposer,
      $$GuideSourcesTableOrderingComposer,
      $$GuideSourcesTableAnnotationComposer,
      $$GuideSourcesTableCreateCompanionBuilder,
      $$GuideSourcesTableUpdateCompanionBuilder,
      (
        GuideSource,
        BaseReferences<_$IptvGuideDatabase, $GuideSourcesTable, GuideSource>,
      ),
      GuideSource,
      PrefetchHooks Function()
    >;

class $IptvGuideDatabaseManager {
  final _$IptvGuideDatabase _db;
  $IptvGuideDatabaseManager(this._db);
  $$GuideProgramsTableTableManager get guidePrograms =>
      $$GuideProgramsTableTableManager(_db, _db.guidePrograms);
  $$GuideSourcesTableTableManager get guideSources =>
      $$GuideSourcesTableTableManager(_db, _db.guideSources);
}
