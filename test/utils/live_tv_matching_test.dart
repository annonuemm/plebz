import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/models/livetv_channel.dart';
import 'package:plezy/models/livetv_program.dart';
import 'package:plezy/utils/live_tv_matching.dart';

void main() {
  test('matches channel by id and server', () {
    final program = LiveTvProgram(title: 'News', channelIdentifier: '101', serverId: 'server-a');

    expect(liveTvProgramMatchesChannel(program, LiveTvChannel(key: '101', serverId: 'server-a')), isTrue);
    expect(liveTvProgramMatchesChannel(program, LiveTvChannel(key: '101', serverId: 'server-b')), isFalse);
  });

  test('matches channel identifier fallback', () {
    final program = LiveTvProgram(title: 'News', channelIdentifier: 'station-101', serverId: 'server-a');
    final channel = LiveTvChannel(key: '101', identifier: 'station-101', serverId: 'server-a');

    expect(liveTvProgramMatchesChannel(program, channel), isTrue);
  });

  test('uses provider identifier when duplicate channels exist on one server', () {
    final program = LiveTvProgram(
      title: 'News',
      channelIdentifier: '101',
      serverId: 'server-a',
      providerIdentifier: 'provider-a',
    );

    final matching = LiveTvChannel(key: '101', serverId: 'server-a', favoriteSource: 'server://machine/provider-a');
    final otherProvider = LiveTvChannel(
      key: '101',
      serverId: 'server-a',
      favoriteSource: 'server://machine/provider-b',
    );

    expect(liveTvProgramMatchesChannel(program, matching), isTrue);
    expect(liveTvProgramMatchesChannel(program, otherProvider), isFalse);
  });

  group('liveTvProgramIsArchived', () {
    final now = DateTime(2026, 8, 30, 22, 0);

    LiveTvChannel channel({int? days}) => LiveTvChannel(key: 'c', identifier: 'ard', catchupDays: days);

    LiveTvProgram program({required DateTime begins, Duration length = const Duration(minutes: 45)}) => LiveTvProgram(
      title: 'Tatort',
      channelIdentifier: 'ard',
      beginsAt: begins.millisecondsSinceEpoch ~/ 1000,
      endsAt: begins.add(length).millisecondsSinceEpoch ~/ 1000,
    );

    test('a finished programme inside the window is still there', () {
      final yesterday = program(begins: now.subtract(const Duration(days: 1)));

      expect(liveTvProgramIsArchived(channel(days: 7), yesterday, now: now), isTrue);
    });

    test('one older than the window is gone', () {
      final lastMonth = program(begins: now.subtract(const Duration(days: 30)));

      expect(liveTvProgramIsArchived(channel(days: 7), lastMonth, now: now), isFalse);
    });

    test('a channel without an archive keeps nothing', () {
      final yesterday = program(begins: now.subtract(const Duration(days: 1)));

      expect(liveTvProgramIsArchived(channel(), yesterday, now: now), isFalse);
    });

    test('what is on now counts, because its start has already been broadcast', () {
      // This is what makes "start it from the beginning" possible on a
      // programme that is still running.
      final airing = program(begins: now.subtract(const Duration(minutes: 10)));

      expect(liveTvProgramIsArchived(channel(days: 7), airing, now: now), isTrue);
    });

    test('nor is what comes later', () {
      final tonight = program(begins: now.add(const Duration(hours: 2)));

      expect(liveTvProgramIsArchived(channel(days: 7), tonight, now: now), isFalse);
    });
  });
}
