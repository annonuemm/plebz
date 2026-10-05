import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../models/livetv_channel.dart';
import '../models/livetv_program.dart';
import '../utils/app_logger.dart';
import 'base_shared_preferences_service.dart';

/// A programme the viewer wants to be told about when it starts (fork
/// addition). Enough to name it and to tune the channel it is on.
@immutable
class ProgramReminder {
  const ProgramReminder({
    required this.channelScopeKey,
    required this.channelTitle,
    required this.title,
    required this.beginsAt,
    this.endsAt,
  });

  /// [liveTvChannelScopeKey] of the channel — server, DVR and channel key.
  final String channelScopeKey;
  final String channelTitle;
  final String title;

  /// Epoch seconds, as the guide gives them.
  final int beginsAt;
  final int? endsAt;

  String get key => ProgramReminders.keyOf(channelScopeKey, beginsAt);

  DateTime get startsAt => DateTime.fromMillisecondsSinceEpoch(beginsAt * 1000);

  /// When it is over; an hour after the start where the guide did not say.
  DateTime get endsAtTime => DateTime.fromMillisecondsSinceEpoch((endsAt ?? beginsAt + 3600) * 1000);

  Map<String, Object?> toJson() => {
    'channel': channelScopeKey,
    'channelTitle': channelTitle,
    'title': title,
    'beginsAt': beginsAt,
    'endsAt': endsAt,
  };

  static ProgramReminder? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final channel = raw['channel'];
    final beginsAt = raw['beginsAt'];
    if (channel is! String || beginsAt is! int) return null;
    return ProgramReminder(
      channelScopeKey: channel,
      channelTitle: raw['channelTitle'] as String? ?? '',
      title: raw['title'] as String? ?? '',
      beginsAt: beginsAt,
      endsAt: raw['endsAt'] as int?,
    );
  }
}

/// The reminders set in the guide, on this device (fork addition).
///
/// The app tells the viewer itself, over whatever is on screen
/// ([ProgramReminderHost]): an Android TV box shows other apps' notifications
/// next to never, so a reminder only works while Plebz is open — which is
/// when one watches television.
class ProgramReminders extends ChangeNotifier {
  ProgramReminders._();

  static final ProgramReminders instance = ProgramReminders._();

  static const String prefsKey = 'program_reminders';

  /// How long before the start the reminder comes up.
  static const Duration lead = Duration(minutes: 1);

  static const int maxEntries = 200;

  List<ProgramReminder> _entries = const [];
  Future<void>? _loading;
  bool _loaded = false;

  static String keyOf(String channelScopeKey, int beginsAt) => '$channelScopeKey|$beginsAt';

  Future<void> ensureLoaded() => _loading ??= _load();

  /// Whether the stored reminders have been read — so a caller can go on at
  /// once instead of queueing behind a future that finished long ago.
  bool get isLoaded => _loaded;

  Future<void> _ready() async {
    if (!_loaded) await ensureLoaded();
  }

  Future<void> _load() async {
    try {
      final prefs = await BaseSharedPreferencesService.sharedCache();
      final raw = prefs.getString(prefsKey);
      final decoded = raw == null || raw.isEmpty ? null : jsonDecode(raw);
      _entries = [
        if (decoded is List)
          for (final entry in decoded) ?ProgramReminder.fromJson(entry),
      ];
    } catch (error, stackTrace) {
      appLogger.w('Reminders: load failed', error: error, stackTrace: stackTrace);
      _entries = const [];
    } finally {
      _loaded = true;
    }
    // What ended while the app was closed is gone for good.
    _dropEnded(save: true);
    notifyListeners();
  }

  Future<void> _save() async {
    notifyListeners();
    try {
      final prefs = await BaseSharedPreferencesService.sharedCache();
      if (_entries.isEmpty) {
        await prefs.remove(prefsKey);
      } else {
        await prefs.setString(prefsKey, jsonEncode([for (final entry in _entries) entry.toJson()]));
      }
    } catch (error, stackTrace) {
      appLogger.w('Reminders: save failed', error: error, stackTrace: stackTrace);
    }
  }

  void _dropEnded({required bool save}) {
    final now = clock.now();
    final kept = [
      for (final entry in _entries)
        if (entry.endsAtTime.isAfter(now)) entry,
    ];
    if (kept.length == _entries.length) return;
    _entries = kept;
    if (save) unawaited(_save());
  }

  /// Every reminder still to come or running, soonest first.
  List<ProgramReminder> get entries =>
      List.unmodifiable([..._entries]..sort((a, b) => a.beginsAt.compareTo(b.beginsAt)));

  bool isSet(LiveTvChannel channel, LiveTvProgram program) {
    final beginsAt = program.beginsAt;
    if (beginsAt == null) return false;
    final key = keyOf(liveTvChannelScopeKey(channel), beginsAt);
    return _entries.any((entry) => entry.key == key);
  }

  /// Whether [program] can still be reminded of: it has a start, and that is
  /// still ahead.
  static bool canRemind(LiveTvProgram program) {
    final beginsAt = program.beginsAt;
    return beginsAt != null && DateTime.fromMillisecondsSinceEpoch(beginsAt * 1000).isAfter(clock.now());
  }

  Future<void> add(LiveTvChannel channel, LiveTvProgram program) async {
    final beginsAt = program.beginsAt;
    if (beginsAt == null) return;
    await _ready();
    final reminder = ProgramReminder(
      channelScopeKey: liveTvChannelScopeKey(channel),
      channelTitle: channel.displayName,
      title: program.grandparentTitle ?? program.title,
      beginsAt: beginsAt,
      endsAt: program.endsAt,
    );
    _entries = [
      for (final entry in _entries)
        if (entry.key != reminder.key) entry,
      reminder,
    ];
    _dropEnded(save: false);
    if (_entries.length > maxEntries) _entries = entries.take(maxEntries).toList();
    await _save();
  }

  Future<void> remove(String key) async {
    await _ready();
    final kept = [
      for (final entry in _entries)
        if (entry.key != key) entry,
    ];
    if (kept.length == _entries.length) return;
    _entries = kept;
    await _save();
  }

  /// The reminders whose moment has come: within [lead] of their start, and
  /// not over yet. A start missed while the app was closed still counts, as
  /// long as the programme is running.
  List<ProgramReminder> due() {
    final now = clock.now();
    return [
      for (final entry in entries)
        if (!entry.startsAt.subtract(lead).isAfter(now) && entry.endsAtTime.isAfter(now)) entry,
    ];
  }

  /// When the next reminder is due, or null when none is set.
  DateTime? nextDueAt() {
    final now = clock.now();
    DateTime? next;
    for (final entry in _entries) {
      if (!entry.endsAtTime.isAfter(now)) continue;
      final at = entry.startsAt.subtract(lead);
      if (next == null || at.isBefore(next)) next = at;
    }
    return next;
  }

  @visibleForTesting
  void debugReset() {
    _entries = const [];
    _loading = null;
    _loaded = false;
  }
}
