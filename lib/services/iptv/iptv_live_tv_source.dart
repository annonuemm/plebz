import 'dart:async';
// The injected fields below are private but their parameters are not — an
// initializing formal would force callers to write `_favorites:`.
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:archive/archive.dart' show InputMemoryStream, InputStream, OutputMemoryStream, XZDecoder;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../media/live_tv_support.dart';
import '../../models/transcode_quality_preset.dart';
import '../../media/media_source_info.dart';
import '../../models/live_tv_channel_layout.dart';
import '../../models/livetv_capture_buffer.dart';
import '../../models/livetv_channel.dart';
import '../../models/livetv_program.dart';
import '../../utils/app_logger.dart';
import '../favorite_channels_repository.dart';
import 'iptv_catchup.dart';
import 'iptv_disk_cache.dart';
import 'iptv_local_files.dart';
import 'iptv_source.dart';
import 'm3u_parser.dart';
import 'xmltv_parser.dart';
import 'iptv_guide_store.dart';
import 'xmltv_stream_reader.dart';
import 'xtream_api.dart';

/// Live TV backed by an IPTV playlist or an Xtream panel.
///
/// Implements the same [LiveTvSupport] contract as the Plex and Jellyfin
/// clients, so the channel list, guide, favorites and player work unchanged —
/// there is simply no media server behind it.
///
/// What it deliberately does not implement: [dvr] is null (nothing here can
/// record), and its sessions cannot time-shift. Both are server capabilities,
/// and a playlist is just a list of URLs.
class IptvLiveTvSource implements LiveTvSupport {
  IptvLiveTvSource(
    this.source, {
    http.Client? httpClient,
    FavoriteChannelsRepository favorites = const SharedPreferencesFavoriteChannelsRepository(),
    Duration channelCacheTtl = const Duration(minutes: 30),
    Duration guideCacheTtl = const Duration(hours: 2),
    IptvDiskCache? diskCache,
    IptvGuideStore? guideStore,
    Duration Function()? diskCacheMaxAge,
    bool Function()? mergeDuplicates,
    Future<LiveTvChannelLayout> Function()? channelLayout,
    void Function()? onLogosLearned,
    DateTime Function() now = DateTime.now,
    int maxResponseBytes = defaultMaxResponseBytes,
  }) : _mergeDuplicates = mergeDuplicates,
       _channelLayout = channelLayout,
       _onLogosLearned = onLogosLearned,
       _http = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null,
       _favorites = favorites,
       _channelCacheTtl = channelCacheTtl,
       _guideCacheTtl = guideCacheTtl,
       _diskCache = diskCache,
       _guide = guideStore ?? MemoryIptvGuideStore(),
       _diskCacheMaxAge = diskCacheMaxAge,
       _now = now,
       _maxResponseBytes = maxResponseBytes;

  /// The most a playlist, guide or panel answer may take, as it arrives and
  /// again once unpacked. Far above any real guide — one that size would not
  /// fit in a TV box's memory anyway — but it stops a gzip bomb, or a stream
  /// address entered as a playlist, from growing until the app is killed.
  static const defaultMaxResponseBytes = 256 * 1024 * 1024;

  final IptvSource source;
  final http.Client _http;
  final bool _ownsHttpClient;
  final int _maxResponseBytes;
  final FavoriteChannelsRepository _favorites;
  final Duration _channelCacheTtl;
  final Duration _guideCacheTtl;

  /// Where the playlist and guide survive a restart. Null leaves the source
  /// memory-only, which is what a test wants unless it says otherwise.
  final IptvDiskCache? _diskCache;

  /// Where the guide is kept and read from, one window at a time (Plebz). In
  /// memory unless told otherwise, which is what a test wants.
  final IptvGuideStore _guide;

  /// The guide in hand: its generation in [_guide], when it was read, for
  /// which channels. Null while there is none.
  IptvGuideState? _guideState;

  /// How old the stored copy may be, read at use rather than held: the
  /// interval is a setting and can change between two reads.
  final Duration Function()? _diskCacheMaxAge;

  /// Whether repeats of the same channel are shown as one. Read at use for
  /// the same reason: flipping the setting must take effect on the next read.
  final bool Function()? _mergeDuplicates;

  /// How the viewer arranged the channel list, read at use: a guide is read
  /// only for the channels it leaves showing. Null reads it for all of them.
  final Future<LiveTvChannelLayout> Function()? _channelLayout;

  /// Channel key → the logo the guide names for a channel. Stands in where
  /// the playlist entry names none, and is the next one tried where the
  /// playlist's does not load. Learned with the guide and stored with it, so
  /// a restart draws them from the first frame.
  Map<String, String> _epgLogos = const {};

  /// Told when the guide brought logos the channels did not have: the guide
  /// arrives after the channels, which are on screen by then.
  final void Function()? _onLogosLearned;

  /// Merged channel key → its variants in playlist order, first one first.
  /// Rebuilt with every channel read; empty for a channel with no siblings.
  final Map<String, List<String>> _variantsByChannelKey = {};

  /// For a merged channel, the copy whose archive the station is reached
  /// through — which need not be the copy that plays.
  final Map<String, String> _archiveVariantByChannelKey = {};
  final DateTime Function() _now;

  /// The one read of the stored copy this session, shared by every caller.
  ///
  /// Reading it is worth one attempt: after that the memory copy is the
  /// answer. A flag was not enough: a guide takes seconds to read back, and
  /// every call that arrived meanwhile — the guide, "Jetzt im TV" and Sport
  /// all ask at once when Live TV opens — saw it set, found nothing in memory
  /// yet, and downloaded the playlist and the guide again.
  Future<void>? _diskRestore;

  /// Downloads in flight, shared the same way: callers arriving together get
  /// one playlist and one guide between them, not one each.
  Future<List<LiveTvChannel>>? _channelsLoading;
  Future<void>? _scheduleLoading;

  /// The write in flight, if any. Callers never wait for it — a fetch is done
  /// when the data is in hand — but a test has to know when the store settled
  /// rather than sleeping and hoping.
  Future<void> _diskWrite = Future<void>.value();

  @visibleForTesting
  Future<void> get pendingDiskWrite => _diskWrite;

  // Playlists run to tens of thousands of lines and a guide to tens of
  // megabytes; both are re-read on a timer rather than per screen visit.
  List<LiveTvChannel>? _channels;
  DateTime? _channelsFetchedAt;

  XtreamApi get _xtream => XtreamApi(
    baseUrl: source.baseUrl ?? '',
    username: source.username ?? '',
    password: source.password ?? '',
    streamFormat: source.streamFormat,
  );

  void close() {
    if (_ownsHttpClient) _http.close();
  }

  /// Drop the cached playlist and guide, for a pull-to-refresh.
  void invalidate() {
    // The stored copy goes with it: a refresh the user asked for must not be
    // answered from disk on the next call.
    _diskRestore = Future<void>.value();
    _channelsLoading = null;
    _scheduleLoading = null;
    unawaited(_diskCache?.clear(source.id) ?? Future<void>.value());
    _m3uUrlByChannelKey.clear();
    _m3uHeadersByChannelKey.clear();
    _channels = null;
    _channelsFetchedAt = null;
    _guideState = null;
    unawaited(_forgetGuide());
  }

  Future<void> _forgetGuide() async {
    try {
      await _guide.clear(source.id);
    } catch (error, stackTrace) {
      appLogger.w('IPTV ${source.name}: the stored guide could not be cleared', error: error, stackTrace: stackTrace);
    }
  }

  @override
  LiveTvDvrSupport? get dvr => null;

  @override
  String get favoriteStoreKey => 'iptv:${source.id}';

  @override
  FavoriteChannelPersistenceMode get favoritePersistenceMode => FavoriteChannelPersistenceMode.serverSlice;

  @override
  Future<String> buildFavoriteChannelSource({String? lineup}) async => 'iptv://${source.id}';

  @override
  Future<bool> isAvailable() async => source.isComplete;

  /// Fill the memory copy from disk, once per session.
  ///
  /// The stored copy stands in for a download, so its age is measured against
  /// the interval the user chose rather than against the short in-memory TTLs:
  /// those exist to keep one session from re-reading, this exists to keep a
  /// restart from re-downloading.
  Future<void> _restoreFromDisk() => _diskRestore ??= _readDisk();

  Future<void> _readDisk() async {
    await _readGuideState();
    final cache = _diskCache;
    if (cache == null) return;

    final reading = Stopwatch()..start();
    final entry = await cache.read(source.id);
    if (entry != null) {
      _timing('stored copy read', reading, '${entry.channels.length} channels, ${entry.programs.length} programmes');
    }
    if (entry == null) {
      appLogger.i('IPTV ${source.name}: nothing stored, the playlist and guide will be fetched');
      return;
    }
    final maxAge = _diskCacheMaxAge?.call() ?? const Duration(days: 1);
    final age = _now().difference(entry.savedAt);
    if (age >= maxAge) {
      appLogger.i(
        'IPTV ${source.name}: the stored copy is ${_ageLabel(age)} old, past the ${maxAge.inDays}-day interval — fetching',
      );
      return;
    }
    appLogger.i(
      'IPTV ${source.name}: restored ${entry.channels.length} channels and ${entry.programs.length} '
      'programmes stored ${_ageLabel(age)} ago',
    );

    if (entry.epgLogos case final logos?) _epgLogos = logos;
    if (entry.channels.isNotEmpty && _channels == null) {
      _channels = entry.channels;
      _channelsFetchedAt = entry.savedAt;
      _m3uUrlByChannelKey
        ..clear()
        ..addAll(entry.streamUrls);
      _m3uHeadersByChannelKey
        ..clear()
        ..addAll(entry.streamHeaders);
    }
    // The guide is no longer kept in this copy (Plebz): it lives in [_guide].
    // One stored before is not taken over; it is read again once.
  }

  /// What the guide store holds for this source. Whether it is still fresh
  /// is [fetchSchedule]'s question.
  Future<void> _readGuideState() async {
    try {
      final reading = Stopwatch()..start();
      final state = await _guide.state(source.id);
      if (state == null || _guideState != null) return;
      _guideState = state;
      _timing('stored guide found', reading, 'read ${_ageLabel(_now().difference(state.fetchedAt))} ago');
    } catch (error, stackTrace) {
      appLogger.w('IPTV ${source.name}: the stored guide could not be read', error: error, stackTrace: stackTrace);
    }
  }

  /// How old a stored copy is, for a log line somebody reads to find out
  /// whether the cache did its job.
  static String _ageLabel(Duration age) => age.inHours >= 1 ? '${age.inHours}h' : '${age.inMinutes}min';

  /// Store what is held now. Best-effort: a cache that cannot be written is
  /// a slower next start, nothing more.
  ///
  /// One write after another, each taking what is held when its turn comes:
  /// the playlist's write and the guide's used to run side by side into the
  /// same file, and a torn file reads as nothing stored — the next start then
  /// downloaded everything again.
  Future<void> _saveToDisk() {
    final cache = _diskCache;
    if (cache == null) return Future<void>.value();
    return _diskWrite = _diskWrite.then(
      (_) => cache.write(
        source.id,
        IptvCacheEntry(
          savedAt: _now(),
          channels: _channels ?? const [],
          programs: const [],
          streamUrls: Map.of(_m3uUrlByChannelKey),
          streamHeaders: {for (final entry in _m3uHeadersByChannelKey.entries) entry.key: Map.of(entry.value)},
          epgLogos: _epgLogos,
        ),
      ),
    );
  }

  @override
  Future<List<LiveTvChannel>> fetchChannels({String? lineup}) async {
    await _restoreFromDisk();
    final cached = _channels;
    final fetchedAt = _channelsFetchedAt;
    final maxAge = _diskCacheMaxAge?.call();
    // Once a stored copy is in play the interval is what decides, not the
    // short session TTL: a user who asked for weekly refreshes did not ask to
    // re-download every half hour.
    final ttl = maxAge == null || maxAge < _channelCacheTtl ? _channelCacheTtl : maxAge;
    if (cached != null && fetchedAt != null && _now().difference(fetchedAt) < ttl) {
      return _withEpgLogos(_merged(cached));
    }

    return _withEpgLogos(
      _merged(await (_channelsLoading ??= _downloadChannels().whenComplete(() => _channelsLoading = null))),
    );
  }

  /// [channel] with the guide's logo: as its logo where its own entry names
  /// none, and as the one to fall back on where it does — a playlist's logo
  /// can be dead, and to the viewer that is no logo either.
  LiveTvChannel withEpgLogo(LiveTvChannel channel) {
    final logo = _epgLogos[channel.key];
    if (logo == null) return channel;
    final own = channel.thumb?.trim();
    if (own == null || own.isEmpty) return channel.copyWith(thumb: logo);
    if (own == logo || channel.guideLogo == logo) return channel;
    return channel.copyWith(guideLogo: logo);
  }

  List<LiveTvChannel> _withEpgLogos(List<LiveTvChannel> channels) =>
      _epgLogos.isEmpty ? channels : [for (final channel in channels) withEpgLogo(channel)];

  Future<List<LiveTvChannel>> _downloadChannels() async {
    final channels = switch (source.kind) {
      IptvSourceKind.m3u => await _fetchM3uChannels(),
      IptvSourceKind.xtream => await _fetchXtreamChannels(),
    };
    _channels = channels;
    _channelsFetchedAt = _now();
    unawaited(_saveToDisk());
    return channels;
  }

  /// One channel per station, where a playlist carries the same one more than
  /// once.
  ///
  /// Grouped on the `tvg-id`, never on the name: a name match folds SPORT1
  /// into SPORT1+ sooner or later, and the guide is matched by that same id
  /// anyway — so a merged channel keeps its programmes for free.
  ///
  /// The merged channel *is* the first variant: same key, same name, same
  /// logo. That keeps favourites, which are stored by key, pointing at
  /// something real whether the setting is on or off.
  List<LiveTvChannel> _merged(List<LiveTvChannel> channels) {
    _variantsByChannelKey.clear();
    _archiveVariantByChannelKey.clear();
    if (!(_mergeDuplicates?.call() ?? false)) return channels;

    final groups = <String, List<LiveTvChannel>>{};
    for (final channel in channels) {
      final identifier = channel.identifier?.trim();
      // Nothing to group on without an id; such a channel stands alone.
      final groupKey = identifier == null || identifier.isEmpty ? 'key:${channel.key}' : 'id:$identifier';
      (groups[groupKey] ??= <LiveTvChannel>[]).add(channel);
    }

    final merged = <LiveTvChannel>[];
    for (final group in groups.values) {
      var primary = group.first;
      if (group.length > 1) {
        _variantsByChannelKey[primary.key] = [for (final channel in group) channel.key];

        // The archive of the whole station, wherever it sits. A playlist
        // usually orders its copies by quality and keeps the archive on only
        // one of them — often not the best one. Without this the station
        // would look archive-less because the copy that plays first has none,
        // and the guide would offer nothing to scroll back to.
        final archived = [
          for (final channel in group)
            if ((channel.catchupDays ?? 0) > 0) channel,
        ]..sort((a, b) => b.catchupDays!.compareTo(a.catchupDays!));
        if (archived.isNotEmpty) {
          _archiveVariantByChannelKey[primary.key] = archived.first.key;
          if ((primary.catchupDays ?? 0) < archived.first.catchupDays!) {
            primary = primary.copyWith(catchupDays: archived.first.catchupDays);
          }
        }
      }
      merged.add(primary);
    }
    return merged;
  }

  Future<List<LiveTvChannel>> _fetchM3uChannels() async {
    final url = source.playlistUrl;
    if (url == null || url.isEmpty) return const [];
    final body = await _get(url);
    if (body == null) return const [];

    // Only the chosen groups: the rest is never kept (see [IptvSource.groups]).
    final parsing = Stopwatch()..start();
    final entries = parseM3u(body, keepGroup: source.groups == null ? null : source.loadsGroup);
    _timing('playlist read', parsing, '${entries.length} channels');
    final channels = channelsFromM3u(
      entries,
      sourceId: source.id,
      sourceName: source.name,
      catchupMode: source.catchupMode,
      sourceCatchupDays: source.catchupDays,
    );
    // The channel key is derived from the entry, not from its URL, so the
    // stream address has to be remembered here — it is the only thing that can
    // be played later.
    _m3uUrlByChannelKey
      ..clear()
      ..addEntries([for (var i = 0; i < channels.length; i++) MapEntry(channels[i].key, entries[i].url)]);
    _m3uHeadersByChannelKey
      ..clear()
      ..addEntries([
        for (var i = 0; i < channels.length; i++)
          if (entries[i].headers.isNotEmpty) MapEntry(channels[i].key, entries[i].headers),
      ]);
    // The archive template is per entry — one playlist can mix conventions —
    // so it is kept beside the URL rather than on the channel, which only
    // carries how far back the window goes.
    _catchupByChannelKey
      ..clear()
      ..addEntries([
        for (var i = 0; i < channels.length; i++)
          if (!entries[i].catchup.isEmpty) MapEntry(channels[i].key, entries[i].catchup),
      ]);
    return channels;
  }

  Future<List<LiveTvChannel>> _fetchXtreamChannels() async {
    final categories = await _getJsonList(_xtream.liveCategories());
    final streams = await _xtreamStreamsOfChosenGroups();
    if (streams == null) return const [];
    return channelsFromXtream(
      streams,
      sourceId: source.id,
      sourceName: source.name,
      categoryNames: categories == null ? const {} : categoriesFromXtream(categories),
      catchupMode: source.catchupMode,
      sourceCatchupDays: source.catchupDays,
    );
  }

  /// When the last programme of the guide in hand begins, in epoch seconds,
  /// or null while no guide is loaded. Read as it stands and never loading:
  /// the guide's day picker asks it on a key press.
  int? get lastProgrammeStart => _guideState?.lastStart;

  @override
  Future<List<LiveTvProgram>> fetchSchedule({DateTime? from, DateTime? to}) => _schedule(
    from: from == null ? null : from.millisecondsSinceEpoch ~/ 1000,
    to: to == null ? null : to.millisecondsSinceEpoch ~/ 1000,
  );

  /// The programme [channel]'s guide has running at [at] (epoch seconds), or
  /// null. One channel at one moment, asked of the store as such: reading the
  /// whole guide to find it cost seconds on every channel change once the
  /// guide no longer sat in memory (Plebz).
  Future<LiveTvProgram?> _programAt(LiveTvChannel channel, int at) async {
    // Programmes are filed under the channel's EPG id, or its key where it
    // was matched by name.
    final identifier = channel.identifier ?? channel.key;
    final programs = await _schedule(from: at, to: at, only: {identifier});
    for (final program in programs) {
      if (program.channelIdentifier != identifier) continue;
      final begins = program.beginsAt;
      final ends = program.endsAt;
      if (begins == null || ends == null || begins > at || ends <= at) continue;
      return program;
    }
    return null;
  }

  /// [from]..[to] in epoch seconds, on the channels showing — or on [only].
  Future<List<LiveTvProgram>> _schedule({int? from, int? to, Set<String>? only}) async {
    await _restoreFromDisk();
    final shown = await _shownChannels();
    final wanted = {for (final channel in shown) channel.key};
    final held = _guideState;
    final maxAge = _diskCacheMaxAge?.call();
    final ttl = maxAge == null || maxAge < _guideCacheTtl ? _guideCacheTtl : maxAge;
    // A channel shown again since the guide was read has nothing in it.
    final covered = held?.coverage?.containsAll(wanted) ?? true;
    final isFresh = held != null && _now().difference(held.fetchedAt) < ttl && covered;
    if (!isFresh) {
      await (_scheduleLoading ??= _readGuides(
        shown,
        wanted,
        keepHeldOnFailure: false,
      ).whenComplete(() => _scheduleLoading = null));
    }

    final state = _guideState;
    if (state == null) return const [];
    // Only what the channels showing have: a guide read for more keeps the
    // rest, unseen, until it is read again.
    final identifiers =
        only ??
        {
          for (final channel in shown) ...[channel.key, ?channel.identifier],
        };
    try {
      return await _guide.window(source.id, state.generation, from: from, to: to, channels: identifiers);
    } catch (error, stackTrace) {
      appLogger.w('IPTV ${source.name}: the stored guide could not be read', error: error, stackTrace: stackTrace);
      return const [];
    }
  }

  /// The channels a guide is read for: the ones the viewer's arrangement
  /// leaves showing. A hidden group of a thousand channels is a thousand
  /// channels' programmes nobody looks at, kept and read back for nothing.
  Future<List<LiveTvChannel>> _shownChannels() async {
    final channels = await fetchChannels();
    final layout = await _channelLayout?.call();
    if (layout == null || layout.isEmpty) return channels;
    return [
      for (final channel in channels)
        if (!layout.hides(channel)) channel,
    ];
  }

  /// "TV-Programm neu laden" (Plebz): the guide read again, the playlist left
  /// as it is, and the guide in hand served — to the grid, "Jetzt live", the
  /// player — until the new one is whole. True once a guide was read.
  ///
  /// Dropping both, as [invalidate] does, left the screen empty and the
  /// playlist downloading again for a guide nobody asked to change.
  Future<bool> refreshGuide() async {
    await _restoreFromDisk();
    final shown = await _shownChannels();
    final wanted = {for (final channel in shown) channel.key};
    final before = _guideState;
    await (_scheduleLoading ??= _readGuides(
      shown,
      wanted,
      keepHeldOnFailure: true,
    ).whenComplete(() => _scheduleLoading = null));
    return !identical(_guideState, before);
  }

  /// Read the guides into a new generation of [_guide], programme by
  /// programme as each guide is read, and put it in place in one step — the
  /// one before is what everybody reads until then.
  ///
  /// [keepHeldOnFailure]: when no guide answers at all, the guide in hand
  /// stays rather than an empty one taking its place — a reload by hand must
  /// not empty the screen. An expired guide is replaced either way: its stamp
  /// would otherwise send every caller to the network again.
  Future<void> _readGuides(List<LiveTvChannel> shown, Set<String> wanted, {required bool keepHeldOnFailure}) async {
    IptvGuideWriter? writer;
    try {
      writer = await _guide.begin(source.id);
      await _loadSchedule(shown, writer);
      if (writer.count == 0 && keepHeldOnFailure && _guideState != null) {
        appLogger.w('IPTV ${source.name}: no guide could be read again; keeping the one in hand');
        await writer.abandon();
        return;
      }
      final storing = Stopwatch()..start();
      // Stamp the *new* read. Keeping the first stamp would expire the guide
      // for good, re-downloading it on every call from then on.
      _guideState = await writer.commit(fetchedAt: _now(), coverage: wanted);
      _timing('guide stored', storing, '${writer.count} programmes');
      unawaited(_saveToDisk());
    } catch (error, stackTrace) {
      appLogger.w('IPTV ${source.name}: the guide could not be stored', error: error, stackTrace: stackTrace);
      try {
        await writer?.abandon();
      } catch (_) {
        // Its next begin clears what is left.
      }
    }
  }

  /// Read [channels]' guide into [writer].
  Future<void> _loadSchedule(List<LiveTvChannel> channels, IptvGuideWriter writer) async {
    if (channels.isEmpty) return;
    final loading = Stopwatch()..start();
    switch (source.kind) {
      case IptvSourceKind.m3u:
        await _loadXmltvGuides(channels, source.epgUrls, writer);
      case IptvSourceKind.xtream:
        await _loadXtreamSchedule(channels, writer);
    }
    _timing('guide complete', loading, '${writer.count} programmes for ${channels.length} channels');
  }

  /// One line of the timings the log keeps of loading (Plebz): what it took a
  /// box to fetch, unpack, read and store a source, so a slow one can be told
  /// apart from a slow provider.
  void _timing(String step, Stopwatch watch, String what) =>
      appLogger.i('IPTV ${source.name} timing: $step ${watch.elapsedMilliseconds} ms ($what)');

  /// [url] as a log may name it: host and file, never the query, where a panel
  /// carries the login.
  static String _urlLabel(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return 'local file';
    final file = uri.pathSegments.where((segment) => segment.isNotEmpty).lastOrNull;
    return file == null ? uri.host : '${uri.host}/$file';
  }

  /// Read every configured XMLTV guide and merge them onto [channels].
  ///
  /// Guides are merged in order and the first one to describe a channel owns
  /// its timeline: a later guide only fills the holes it leaves. Within one
  /// guide, a guide channel matched by id goes before one matched by name, and
  /// the same rule holds between them. So a second list adds the channels the
  /// first does not cover without laying a second timetable over the ones it
  /// does — two timetables whose starts differ by a few minutes printed their
  /// titles over each other in the grid.
  ///
  /// Each guide's programmes go into [writer] once it is merged, so only one
  /// guide is ever held whole.
  Future<void> _loadXmltvGuides(List<LiveTvChannel> channels, List<String> urls, IptvGuideWriter writer) async {
    if (urls.isEmpty) return;

    final byXmltvId = <String, LiveTvChannelRef>{};
    final byName = <String, LiveTvChannelRef>{};
    for (final channel in channels) {
      final ref = LiveTvChannelRef(
        key: channel.key,
        identifier: channel.identifier,
        callSign: channel.callSign,
        serverId: channel.serverId,
        serverName: channel.serverName,
      );
      final id = channel.identifier;
      if (id != null && id.isNotEmpty) byXmltvId[id] = ref;

      // The name is the fallback route into a guide: providers routinely ship
      // playlists whose tvg-ids match nothing they also serve as XMLTV.
      final title = channel.title ?? channel.callSign;
      if (title == null) continue;
      for (final variant in xmltvChannelNameVariants(title)) {
        byName.putIfAbsent(variant, () => ref);
      }
    }
    if (byXmltvId.isEmpty && byName.isEmpty) return;

    final seenSlots = <String>{};
    // Per channel, what the guides before this one already cover.
    final taken = <String, List<(int, int)>>{};
    // What the guides name as each channel's logo.
    final logos = <String, String>{};
    var readAGuide = false;
    // All guides download at once (Plebz), each read as it arrives in an
    // isolate of its own and never held whole — see [readXmltvStream]. They
    // are still merged in order, the first one owning its channels.
    final ids = byXmltvId.keys.toSet();
    final names = byName.keys.toSet();
    final reads = [for (final url in urls) url.isEmpty ? Future<XmltvGuide?>.value() : _readGuide(url, ids, names)];
    for (var i = 0; i < urls.length; i++) {
      final guide = await reads[i];
      if (guide == null) continue;
      readAGuide = true;
      final resolved = <String, LiveTvChannelRef>{...byXmltvId};
      for (final entry in guide.matchedChannelNames.entries) {
        final ref = byName[entry.value];
        if (ref != null) resolved.putIfAbsent(entry.key, () => ref);
      }
      // Logos by the same rule as the programmes: the first guide first,
      // and in one guide the channel matched by id before one matched by name.
      for (final byId in const [true, false]) {
        for (final entry in guide.channelIcons.entries) {
          if (byXmltvId.containsKey(entry.key) != byId) continue;
          final ref = resolved[entry.key];
          if (ref != null) logos.putIfAbsent(ref.key, () => entry.value);
        }
      }
      final byGuideChannel = <String, List<XmltvProgram>>{};
      for (final entry in guide.programs) {
        (byGuideChannel[entry.channelId] ??= []).add(entry);
      }
      final guideChannels = [
        ...byGuideChannel.keys.where(byXmltvId.containsKey),
        ...byGuideChannel.keys.where((id) => !byXmltvId.containsKey(id)),
      ];
      final kept = <LiveTvProgram>[];
      for (final guideChannel in guideChannels) {
        final served = <String, List<(int, int)>>{};
        for (final program in programsFromXmltv(byGuideChannel[guideChannel]!, channelsByXmltvId: resolved)) {
          final channel = program.channelIdentifier ?? '';
          final begins = program.beginsAt;
          final ends = program.endsAt;
          if (begins != null && ends != null && _spansOverlap(taken[channel], begins, ends)) continue;
          if (!seenSlots.add('$channel\u0000$begins')) continue;
          kept.add(program);
          if (begins != null && ends != null) (served[channel] ??= []).add((begins, ends));
        }
        served.forEach((channel, spans) => taken[channel] = _unionOfSpans([...?taken[channel], ...spans]));
      }
      await writer.add(kept);
    }

    // Not when every guide failed: that says nothing about the logos known.
    if (readAGuide) _learnLogos(logos);
  }

  void _learnLogos(Map<String, String> logos) {
    if (mapEquals(logos, _epgLogos)) return;
    final learnedNew = logos.entries.any((entry) => _epgLogos[entry.key] != entry.value);
    _epgLogos = logos;
    if (learnedNew) {
      appLogger.i('IPTV ${source.name}: the guide names logos for ${logos.length} channels');
      _onLogosLearned?.call();
    }
  }

  /// [spans] sorted and merged into disjoint ones, so [_spansOverlap] can
  /// search them.
  static List<(int, int)> _unionOfSpans(List<(int, int)> spans) {
    final sorted = [...spans]..sort((a, b) => a.$1.compareTo(b.$1));
    final union = <(int, int)>[];
    for (final span in sorted) {
      final last = union.lastOrNull;
      if (last != null && span.$1 <= last.$2) {
        if (span.$2 > last.$2) union[union.length - 1] = (last.$1, span.$2);
      } else {
        union.add(span);
      }
    }
    return union;
  }

  /// Whether [begins]..[ends] runs into any of [union], disjoint and sorted.
  static bool _spansOverlap(List<(int, int)>? union, int begins, int ends) {
    if (union == null || union.isEmpty) return false;
    // The last span starting before [ends]: disjoint and sorted, it is also
    // the one reaching furthest.
    var low = 0;
    var high = union.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (union[mid].$1 < ends) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low > 0 && union[low - 1].$2 > begins;
  }

  /// A panel serves its whole guide as XMLTV at `xmltv.php`, which is the
  /// only way to fill more than a screenful: `get_short_epg` is one request
  /// per channel. The per-channel route stays as the fallback for panels that
  /// do not answer the XMLTV endpoint, and is capped — a 5,000-channel panel
  /// would otherwise fire 5,000 requests to fill one screen.
  Future<void> _loadXtreamSchedule(List<LiveTvChannel> channels, IptvGuideWriter writer) async {
    await _loadXmltvGuides(channels, [_xtream.xmltv().toString(), ...source.epgUrls], writer);
    if (writer.count > 0) return;

    const maxChannels = 60;
    final programs = <LiveTvProgram>[];

    for (final channel in channels.take(maxChannels)) {
      final streamId = channel.key.split(':').last;
      // `get_short_epg` wraps its rows in an object, unlike the flat arrays
      // the stream and category actions return.
      final rows = await _getJsonList(_xtream.shortEpg(streamId), envelopeKey: 'epg_listings');
      if (rows == null) continue;
      programs.addAll(programsFromXtreamEpg(rows, channel: channel));
    }
    if (channels.length > maxChannels) {
      appLogger.d('IPTV ${source.name}: guide limited to the first $maxChannels of ${channels.length} channels');
    }
    await writer.add(programs);
  }

  @override
  Future<LiveTvPlaybackSession?> startPlayback(
    String channelKey, {
    String? dvrKey,
    TranscodeQualityPreset quality = TranscodeQualityPreset.original,
  }) async {
    final channels = await fetchChannels();
    final channel = channels.where((candidate) => candidate.key == channelKey).firstOrNull;
    if (channel == null) return null;

    // Every address this channel can be reached at, first choice first. One
    // entry for an ordinary channel; several where a playlist repeats the
    // station and those repeats were merged into one. The keys are kept in
    // step with the addresses: a copy whose address cannot be built drops
    // out, and the archive has to keep pointing at the right one.
    final variants = <({String url, Map<String, String> headers, String label})>[];
    final playableKeys = <String>[];
    for (final key in _variantsByChannelKey[channelKey] ?? [channelKey]) {
      final address = _streamAddressFor(key);
      if (address == null) continue;
      variants.add(address);
      playableKeys.add(key);
    }
    if (variants.isEmpty) return null;

    final archiveKey = _archiveVariantByChannelKey[channelKey];
    final archiveIndex = archiveKey == null ? -1 : playableKeys.indexOf(archiveKey);

    return IptvPlaybackSession(
      variants: variants,
      archiveVariantIndex: archiveIndex < 0 ? 0 : archiveIndex,
      program: await _currentProgramFor(channel),
      catchup: _catchupFor(channel, archiveKey: archiveKey ?? channel.key),
      now: _now,
    );
  }

  /// How this channel's archive is reached, or null when it has none.
  ///
  /// The window on the channel is the decision: it was resolved when the
  /// channels were read, from what the entry declared, what the panel
  /// reported, and the source's own fallback.
  IptvCatchupAccess? _catchupFor(LiveTvChannel channel, {required String archiveKey}) {
    final days = channel.catchupDays;
    if (days == null || source.catchupMode == IptvCatchupMode.off) {
      // Said out loud, because the guide decides what to offer from the
      // channel alone and never consults the source's mode: a station can
      // advertise an archive in the guide and have none to play from.
      appLogger.d(
        'IPTV ${source.name}: no archive for ${channel.title} '
        '(days=$days, mode=${source.catchupMode.name})',
      );
      return null;
    }
    // A panel has no `catchup=` attribute to read: its archive flag is the
    // declaration, and its own timeshift path is the only way to address it.
    // So for a panel, "as declared" means the Xtream form.
    final mode = source.catchupMode == IptvCatchupMode.automatic && source.kind == IptvSourceKind.xtream
        ? IptvCatchupMode.xtream
        : source.catchupMode;
    return IptvCatchupAccess(
      mode: mode,
      windowDays: days,
      // The template of the copy that holds the archive, which is where the
      // address has to be built from.
      info: _catchupByChannelKey[archiveKey] ?? _catchupByChannelKey[channel.key],
      durationAt: (start) => _archiveDurationSeconds(channel, start),
      xtreamRoot: source.kind == IptvSourceKind.xtream ? _xtream.root : null,
      xtreamUsername: source.username,
      xtreamPassword: source.password,
    );
  }

  /// How much archive to ask for from [start]: to the end of the programme
  /// that covers it, so the stream stops where the programme does rather than
  /// running on into the next one.
  ///
  /// Falls back to two hours, which is longer than most programmes and short
  /// enough that no panel refuses it.
  Future<int> _archiveDurationSeconds(LiveTvChannel channel, DateTime start) async {
    const fallback = 2 * 60 * 60;
    final at = start.millisecondsSinceEpoch ~/ 1000;

    // Never ask for more than has happened. A programme still running has an
    // end in the future, and its length is what the guide reports — so
    // starting one over used to ask the panel for ninety minutes of which
    // twenty existed, and a panel answers that with an error rather than with
    // the twenty. What exists is everything from the requested moment up to
    // now, and that is the most that can be requested.
    final available = math.max(60, (_now().millisecondsSinceEpoch ~/ 1000) - at);
    int limited(int seconds) => seconds.clamp(60, math.min(6 * 60 * 60, available)).toInt();

    try {
      final program = await _programAt(channel, at);
      if (program?.endsAt case final ends?) return limited(ends - at);
    } catch (error, stackTrace) {
      appLogger.d('IPTV ${source.name}: archive duration lookup failed', error: error, stackTrace: stackTrace);
    }
    return limited(fallback);
  }

  /// Where one channel key can be played from, or null when nothing knows.
  ///
  /// The label is the copy's own name from the playlist — that is what tells
  /// two routes to the same station apart in a menu.
  ({String url, Map<String, String> headers, String label})? _streamAddressFor(String channelKey) {
    final url = switch (source.kind) {
      IptvSourceKind.m3u => _m3uUrlByChannelKey[channelKey],
      IptvSourceKind.xtream => _xtream.liveStreamUrl(channelKey.split(':').last).toString(),
    };
    if (url == null || url.isEmpty) return null;
    final named = _channels?.where((channel) => channel.key == channelKey).firstOrNull;
    return (
      url: url,
      headers: _m3uHeadersByChannelKey[channelKey] ?? const {},
      label: named?.displayName ?? channelKey,
    );
  }

  /// Channel key → stream URL, filled when the playlist is read.
  final Map<String, String> _m3uUrlByChannelKey = {};

  /// Channel key → the headers its playlist entry asked for, for the entries
  /// that named any.
  final Map<String, Map<String, String>> _m3uHeadersByChannelKey = {};

  /// Channel key → what its playlist entry said about its archive.
  final Map<String, IptvCatchupInfo> _catchupByChannelKey = {};

  Future<LiveProgramInfo> _currentProgramFor(LiveTvChannel channel) async {
    try {
      final now = _now().millisecondsSinceEpoch ~/ 1000;
      final program = await _programAt(channel, now);
      if (program != null) {
        final begins = program.beginsAt!;
        return LiveProgramInfo(id: program.key, beginsAt: begins, durationMs: (program.endsAt! - begins) * 1000);
      }
    } catch (error, stackTrace) {
      appLogger.d('IPTV ${source.name}: current programme lookup failed', error: error, stackTrace: stackTrace);
    }
    return LiveProgramInfo.none;
  }

  @override
  Future<List<FavoriteChannel>> fetchFavoriteChannels({bool migrate = true, void Function()? checkCurrent}) =>
      _favorites.read(key: favoriteStoreKey, legacyKey: favoriteStoreKey, migrate: migrate, checkCurrent: checkCurrent);

  @override
  Future<void> setFavoriteChannels(List<FavoriteChannel> channels, {void Function()? checkCurrent}) =>
      _favorites.write(favoriteStoreKey, channels, checkCurrent: checkCurrent);

  /// The panel's live streams, of the chosen groups only. A few groups are
  /// asked for one by one, so the panel sends no more than they hold; past
  /// [_perGroupRequestLimit] one whole list is cheaper than that many
  /// requests, and it is narrowed here instead.
  Future<List<dynamic>?> _xtreamStreamsOfChosenGroups() async {
    final chosen = source.groups;
    if (chosen == null) return _getJsonList(_xtream.liveStreams());
    if (chosen.length > _perGroupRequestLimit) {
      final all = await _getJsonList(_xtream.liveStreams());
      return all?.where((row) => row is Map && chosen.contains('${row['category_id']}')).toList();
    }
    final streams = <dynamic>[];
    var answered = false;
    for (final category in chosen) {
      final rows = await _getJsonList(_xtream.liveStreams(categoryId: category));
      if (rows == null) continue;
      answered = true;
      streams.addAll(rows);
    }
    return answered || chosen.isEmpty ? streams : null;
  }

  static const _perGroupRequestLimit = 20;

  /// Every group the provider offers, for choosing a source's groups: the
  /// panel's categories, or the playlist's `group-title`s with how many
  /// channels each holds. Null when the provider cannot be read.
  Future<List<IptvGroupOption>?> fetchGroupOptions() async {
    switch (source.kind) {
      case IptvSourceKind.xtream:
        final rows = await _getJsonList(_xtream.liveCategories());
        if (rows == null) return null;
        return [
          for (final MapEntry(:key, :value) in categoriesFromXtream(rows).entries)
            IptvGroupOption(key: key, label: value),
        ];
      case IptvSourceKind.m3u:
        final url = source.playlistUrl;
        if (url == null || url.isEmpty) return null;
        final body = await _get(url);
        if (body == null) return null;
        return [
          for (final MapEntry(:key, :value) in m3uGroupCounts(body).entries)
            IptvGroupOption(key: key, label: key, channelCount: value),
        ];
    }
  }

  /// One guide, read as it downloads — see [readXmltvStream]. Null when it
  /// could not be read.
  Future<XmltvGuide?> _readGuide(String url, Set<String> channelIds, Set<String> channelNames) async {
    final reading = Stopwatch()..start();
    try {
      final Stream<List<int>> bytes;
      if (IptvLocalFiles.isLocal(url)) {
        final file = File(Uri.parse(url).toFilePath());
        bytes = file.openRead();
      } else {
        final response = await _http.send(http.Request('GET', Uri.parse(url)));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          // Not read: an error page can be as large as anything else.
          await response.stream.listen(null).cancel();
          appLogger.w('IPTV ${source.name}: ${_urlLabel(url)} returned ${response.statusCode}');
          return null;
        }
        bytes = response.stream;
      }
      final result = await readXmltvStream(
        bytes,
        channelIds: channelIds,
        channelNames: channelNames,
        maxBytes: _maxResponseBytes,
      );
      switch (result) {
        case XmltvStreamRead(:final guide, :final packedBytes, :final unpackedBytes):
          _timing(
            'guide read',
            reading,
            '${_urlLabel(url)}, ${(packedBytes / (1 << 20)).toStringAsFixed(1)} MB downloaded, '
                '${(unpackedBytes / (1 << 20)).toStringAsFixed(1)} MB read, ${guide.programs.length} programmes kept',
          );
          return guide;
        case XmltvStreamTooLarge():
          appLogger.w('IPTV ${source.name}: ${_urlLabel(url)} is larger than ${_maxResponseBytes >> 20} MB; not read');
        case XmltvStreamUnreadable(:final error):
          // Not every URL that answers serves XMLTV — a panel without an
          // `xmltv.php` hands back its JSON error object instead.
          appLogger.w('IPTV ${source.name}: ${_urlLabel(url)} is not a readable guide: $error');
      }
    } catch (error, stackTrace) {
      appLogger.w('IPTV ${source.name}: ${_urlLabel(url)} failed', error: error, stackTrace: stackTrace);
    }
    return null;
  }

  Future<String?> _get(String url) async {
    final bytes = await _getBytes(url);
    // Providers serve playlists and guides without a charset; the bytes are
    // UTF-8 in practice, and malformed sequences must not lose the file.
    return bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
  }

  /// What [url] serves, unpacked; null when it could not be read.
  Future<List<int>?> _getBytes(String url) async {
    if (IptvLocalFiles.isLocal(url)) return _readLocal(url);
    try {
      final downloading = Stopwatch()..start();
      final response = await _http.send(http.Request('GET', Uri.parse(url)));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        // Not read: an error page can be as large as anything else.
        await response.stream.listen(null).cancel();
        appLogger.w('IPTV ${source.name}: $url returned ${response.statusCode}');
        return null;
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        bytes.add(chunk);
        if (bytes.length > _maxResponseBytes) {
          appLogger.w('IPTV ${source.name}: $url is larger than ${_maxResponseBytes >> 20} MB; not read');
          return null;
        }
      }
      final packed = bytes.takeBytes();
      _timing('download', downloading, '${_urlLabel(url)}, ${(packed.length / (1 << 20)).toStringAsFixed(1)} MB');
      final unpacking = Stopwatch()..start();
      final unpacked = await _unpack(packed, url);
      if (unpacked != null && !identical(unpacked, packed)) {
        _timing('unpack', unpacking, '${(unpacked.length / (1 << 20)).toStringAsFixed(1)} MB');
      }
      return unpacked;
    } catch (error, stackTrace) {
      appLogger.w('IPTV ${source.name}: $url failed', error: error, stackTrace: stackTrace);
      return null;
    }
  }

  /// A playlist (or guide) taken from a local file — see [IptvLocalFiles].
  Future<List<int>?> _readLocal(String url) async {
    try {
      final file = File(Uri.parse(url).toFilePath());
      if (await file.length() > _maxResponseBytes) {
        appLogger.w('IPTV ${source.name}: local file is larger than ${_maxResponseBytes >> 20} MB; not read');
        return null;
      }
      return await _unpack(await file.readAsBytes(), url);
    } catch (error, stackTrace) {
      appLogger.w('IPTV ${source.name}: local file could not be read', error: error, stackTrace: stackTrace);
      return null;
    }
  }

  /// [bytes] as the text they carry, whichever of the packings guides come in
  /// it arrives in: none, gzip, or xz — the Rytec lists, the one free German
  /// guide reaching a week ahead, are `.xz` only.
  Future<List<int>?> _unpack(Uint8List bytes, String url) async {
    if (!isXzPayload(bytes)) return _maybeGunzip(bytes, url);
    // Off the UI isolate: xz is unpacked in Dart, a few hundred milliseconds
    // for a week of German channels on a desktop, more on a television box.
    final result = await compute(unpackXzPayload, (data: bytes, cap: _maxResponseBytes));
    switch (result) {
      case XzUnpacked(:final bytes):
        return bytes;
      case XzTooLarge():
        appLogger.w('IPTV ${source.name}: $url unpacks to more than ${_maxResponseBytes >> 20} MB; not read');
      case XzUnreadable(:final error):
        appLogger.w('IPTV ${source.name}: $url could not be unpacked as xz', error: error);
    }
    return null;
  }

  /// Guides are routinely published as `.xml.gz`, and a file served as
  /// `application/gzip` reaches us packed — the HTTP layer only unpacks what
  /// the server marks as `Content-Encoding: gzip`. Detected by the gzip magic
  /// number rather than the file extension, because providers name these
  /// files whatever they like. Unpacked piece by piece, so a file that grows
  /// past the size cap is dropped before it is whole in memory; null then.
  List<int>? _maybeGunzip(Uint8List bytes, String url) {
    if (bytes.length < 2 || bytes[0] != 0x1f || bytes[1] != 0x8b) return bytes;
    final unpacked = _CappedBytes(_maxResponseBytes);
    try {
      final input = gzip.decoder.startChunkedConversion(unpacked);
      const step = 64 * 1024;
      for (var start = 0; start < bytes.length; start += step) {
        input.add(Uint8List.sublistView(bytes, start, math.min(start + step, bytes.length)));
      }
      input.close();
      return unpacked.takeBytes();
    } on _TooLarge {
      appLogger.w('IPTV ${source.name}: $url unpacks to more than ${_maxResponseBytes >> 20} MB; not read');
      return null;
    } catch (error) {
      appLogger.w('IPTV ${source.name}: a gzipped response could not be unpacked', error: error);
      return bytes;
    }
  }

  /// Decode a panel response as a list. Some actions answer with a bare array,
  /// others wrap it in an object under [envelopeKey]; both are accepted so a
  /// caller does not have to know which.
  Future<List<dynamic>?> _getJsonList(Uri uri, {String? envelopeKey}) async {
    final body = await _get(uri.toString());
    if (body == null) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is List) return decoded;
      if (envelopeKey != null && decoded is Map) {
        final rows = decoded[envelopeKey];
        if (rows is List) return rows;
      }
      // A panel that rejects the credentials answers with an object too.
      return null;
    } on FormatException catch (error) {
      appLogger.w('IPTV ${source.name}: unexpected response from ${uri.path}', error: error);
      return null;
    }
  }
}

/// Whether [bytes] begin with the xz magic number. Told by content, like
/// gzip, because guides are named whatever their publisher likes.
bool isXzPayload(List<int> bytes) =>
    bytes.length >= 6 &&
    bytes[0] == 0xfd &&
    bytes[1] == 0x37 &&
    bytes[2] == 0x7a &&
    bytes[3] == 0x58 &&
    bytes[4] == 0x5a &&
    bytes[5] == 0x00;

/// What [unpackXzPayload] made of a payload. A result rather than a throw,
/// so it crosses the isolate boundary as it is.
sealed class XzResult {
  const XzResult();
}

final class XzUnpacked extends XzResult {
  const XzUnpacked(this.bytes);
  final Uint8List bytes;
}

final class XzTooLarge extends XzResult {
  const XzTooLarge();
}

final class XzUnreadable extends XzResult {
  const XzUnreadable(this.error);
  final String error;
}

/// Unpack an xz payload, giving up once it grows past `cap` bytes — the cap
/// holds for the unpacked size, so a small file that unpacks to gigabytes
/// stops early instead of filling memory. Top-level for `compute`.
XzResult unpackXzPayload(({Uint8List data, int cap}) input) {
  final output = _CappedOutput(input.cap);
  try {
    XZDecoder().decodeStream(InputMemoryStream(input.data), output);
    return XzUnpacked(output.getBytes());
  } on _TooLarge {
    return const XzTooLarge();
  } catch (error) {
    return XzUnreadable(error.toString());
  }
}

/// [OutputMemoryStream] with the response cap applied to every write.
class _CappedOutput extends OutputMemoryStream {
  _CappedOutput(this.cap);

  final int cap;

  void _check(int more) {
    if (length + more > cap) throw const _TooLarge();
  }

  @override
  void writeByte(int value) {
    _check(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _check(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _check(stream.length);
    super.writeStream(stream);
  }

  @override
  void writeBackReference(int distance, int count) {
    _check(count);
    super.writeBackReference(distance, count);
  }
}

/// Archive access for one channel: how its provider addresses the past, how
/// far back it goes, and how long a window to ask for at a given point.
class IptvCatchupAccess {
  const IptvCatchupAccess({
    required this.mode,
    required this.windowDays,
    required this.durationAt,
    this.info,
    this.xtreamRoot,
    this.xtreamUsername,
    this.xtreamPassword,
  });

  final IptvCatchupMode mode;

  /// How many days back the provider keeps.
  final int windowDays;

  /// How much to ask for, starting at the given moment. The programme's
  /// remaining length, so the stream ends where the programme does.
  final Future<int> Function(DateTime start) durationAt;

  final IptvCatchupInfo? info;
  final String? xtreamRoot;
  final String? xtreamUsername;
  final String? xtreamPassword;
}

/// A live stream that is simply opened — no tuning, and a seekable window only
/// where the provider keeps an archive.
class IptvPlaybackSession implements LiveTvPlaybackSession {
  IptvPlaybackSession({
    required this.variants,
    this.variantIndex = 0,
    int? archiveVariantIndex,
    LiveProgramInfo? program,
    this.catchup,
    DateTime Function()? now,
  }) : archiveVariantIndex = archiveVariantIndex ?? variantIndex,
       assert(variants.isNotEmpty),
       program = program ?? LiveProgramInfo.none,
       _now = now ?? DateTime.now,
       // Fixed at session start, not read per call: the player turns an
       // absolute time into an offset against this origin, and an origin that
       // slid forward between the two would move every seek with it.
       _openedAt = (now ?? DateTime.now)();

  /// How this channel's archive is reached, or null when it has none.
  final IptvCatchupAccess? catchup;

  final DateTime Function() _now;
  final DateTime _openedAt;

  /// Every address this channel can be reached at, first choice first.
  ///
  /// More than one where a playlist carries the same station repeatedly and
  /// those repeats were merged: if the first refuses to play, the next is
  /// what recovery reaches for.
  final List<({String url, Map<String, String> headers, String label})> variants;

  /// Which of them is playing.
  @override
  final int variantIndex;

  /// Which of them the archive is reached through.
  ///
  /// Usually the same one, but a playlist that orders its copies by quality
  /// often keeps the archive on a lesser one. Playing RAW and watching its
  /// archive is then two different addresses, and asking the panel for the
  /// archive of a copy that has none answers with nothing.
  final int archiveVariantIndex;

  /// True while an archive address is what was last handed out, so the
  /// headers follow the copy actually being played.
  bool _playingArchive = false;

  @override
  List<String> get variantLabels => variants.length > 1 ? [for (final variant in variants) variant.label] : const [];

  @override
  Future<LiveTvPlaybackSession?> switchVariant(int index) async {
    if (index < 0 || index >= variants.length || index == variantIndex) return null;
    return IptvPlaybackSession(
      variants: variants,
      variantIndex: index,
      archiveVariantIndex: archiveVariantIndex,
      program: program,
      catchup: catchup,
      now: _now,
    );
  }

  String get url => variants[variantIndex].url;

  @override
  Map<String, String> get streamHeaders => variants[_playingArchive ? archiveVariantIndex : variantIndex].headers;

  @override
  final LiveProgramInfo program;

  /// Nothing is held server-side, so a backgrounded app has no session worth
  /// keeping alive.
  @override
  LiveTvBackgroundPolicy get backgroundPolicy => LiveTvBackgroundPolicy.stopAndExit;

  /// The archive as a seekable window: from the oldest hour the provider still
  /// keeps up to now. Same shape a recording server reports, so the player's
  /// seek bar, its watch-from-start prompt and its live-edge tracking all work
  /// on it unchanged.
  @override
  CaptureBuffer? get captureBuffer {
    final access = catchup;
    if (access == null) return null;
    final origin = _openedAt.subtract(Duration(days: access.windowDays));
    return CaptureBuffer(
      startedAt: (origin.millisecondsSinceEpoch ~/ 1000).toDouble(),
      seekStartSeconds: 0,
      seekEndSeconds: _now().difference(origin).inSeconds.toDouble(),
    );
  }

  @override
  List<MediaSubtitleTrack> get subtitleTracks => const [];

  /// Only where the provider keeps one. Nothing is recorded locally.
  @override
  bool get canTimeShift => catchup != null;

  /// The archive is always there, so being asked about it on every tune would
  /// be a dialog in front of every channel.
  @override
  bool get promptsWatchFromStart => false;

  @override
  Future<String?> streamUrlAt({int? offsetSeconds, MediaSubtitleTrack? subtitleTrack}) async {
    if (offsetSeconds == null) {
      _playingArchive = false;
      return url;
    }

    final access = catchup;
    final buffer = captureBuffer;
    // A requested offset must fail rather than silently play the live edge,
    // which would look to the viewer like a seek that jumped.
    if (access == null || buffer == null) return null;

    final start = DateTime.fromMillisecondsSinceEpoch((buffer.startedAt.round() + offsetSeconds) * 1000);
    final archiveUrl = buildIptvCatchupUrl(
      mode: access.mode,
      // The archive copy's live address, not the playing one: the stream id
      // and the container are read out of it, and the copy that plays may
      // have no archive to read them from.
      liveUrl: variants[archiveVariantIndex].url,
      start: start,
      durationSeconds: await access.durationAt(start),
      now: _now(),
      info: access.info,
      xtreamRoot: access.xtreamRoot,
      xtreamUsername: access.xtreamUsername,
      xtreamPassword: access.xtreamPassword,
    );
    if (archiveUrl == null) {
      appLogger.d('IPTV: no archive URL for $start (${access.mode.name})');
      return null;
    }
    appLogger.d('IPTV archive: $start (${access.mode.name})');
    _playingArchive = true;
    return archiveUrl;
  }

  @override
  Future<LiveTimelineUpdate?> reportTimeline({
    required String state,
    required int positionMs,
    required int durationMs,
  }) async => null;

  /// Nothing to release: opening the stream tuned nothing on the provider's
  /// side, so a session nobody played leaves nothing behind.
  @override
  Future<void> discard() async {}

  /// Recovery moves to the next address this station has, and re-opens the
  /// current one when there is none.
  ///
  /// The degradation flags mean nothing here — they reconfigure a server-side
  /// session, and a playlist has none. Before merging, that made recovery a
  /// no-op: three attempts at the same failing address. A station carried
  /// several times over is exactly the case where the second one works.
  @override
  Future<LiveTvPlaybackSession?> recover({required bool directStream, required bool directStreamAudio}) async {
    final next = variantIndex + 1;
    if (next >= variants.length) return this;
    appLogger.i('IPTV: falling back to variant ${next + 1} of ${variants.length}');
    return IptvPlaybackSession(variants: variants, variantIndex: next, program: program, catchup: catchup, now: _now);
  }
}

/// Where [IptvLiveTvSource._maybeGunzip] unpacks to: throws [_TooLarge] as
/// soon as the output passes [limit].
final class _CappedBytes implements Sink<List<int>> {
  _CappedBytes(this.limit);

  final int limit;
  final _bytes = BytesBuilder();

  @override
  void add(List<int> chunk) {
    _bytes.add(chunk);
    if (_bytes.length > limit) throw const _TooLarge();
  }

  @override
  void close() {}

  Uint8List takeBytes() => _bytes.takeBytes();
}

final class _TooLarge implements Exception {
  const _TooLarge();
}

/// One group a source's provider offers (fork): a playlist's `group-title`
/// or a panel's category.
@immutable
class IptvGroupOption {
  const IptvGroupOption({required this.key, required this.label, this.channelCount});

  /// What [IptvSource.groups] stores: the title itself, or the category id.
  final String key;
  final String label;

  /// How many channels it holds, where that is known without loading them.
  final int? channelCount;
}
