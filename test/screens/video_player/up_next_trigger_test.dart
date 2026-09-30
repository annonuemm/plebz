import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/screens/video_player/up_next_trigger.dart';

void main() {
  const runtime = Duration(minutes: 45);

  bool due(
    Duration position, {
    Duration? creditsStart,
    bool hasNext = true,
    bool dismissed = false,
    bool enabled = true,
  }) => shouldShowUpNext(
    position: position,
    duration: runtime,
    hasNextEpisode: hasNext,
    dismissed: dismissed,
    enabled: enabled,
    creditsStart: creditsStart,
  );

  test('the credits marker decides where one exists', () {
    // A marker is a statement about this episode; the fraction is a guess
    // about episodes in general.
    const credits = Duration(minutes: 41);

    expect(due(const Duration(minutes: 40), creditsStart: credits), isFalse);
    expect(due(credits, creditsStart: credits), isTrue);
    expect(due(const Duration(minutes: 44), creditsStart: credits), isTrue);
  });

  test('without a marker it waits for the last stretch', () {
    // 97% of 45 minutes is the last minute and twenty seconds.
    expect(due(const Duration(minutes: 43)), isFalse, reason: 'still the episode');
    expect(due(const Duration(minutes: 43, seconds: 30)), isFalse, reason: 'and so is this');
    expect(due(const Duration(minutes: 44)), isTrue);
  });

  test('a marker earlier than the fraction still wins', () {
    // Long credits with a stinger: the panel belongs where the marker says.
    expect(due(const Duration(minutes: 38), creditsStart: const Duration(minutes: 37)), isTrue);
  });

  test('nothing to play next means nothing to announce', () {
    expect(due(const Duration(minutes: 44), hasNext: false), isFalse);
  });

  test('switched off, nothing appears at any point', () {
    expect(due(const Duration(minutes: 44), enabled: false), isFalse);
    expect(due(const Duration(minutes: 41), creditsStart: const Duration(minutes: 41), enabled: false), isFalse);
  });

  test('dismissed stays dismissed', () {
    expect(due(const Duration(minutes: 44), dismissed: true), isFalse);
  });

  test('a short extra never gets a panel', () {
    // Five minutes of behind-the-scenes would otherwise carry one almost from
    // the start.
    expect(
      shouldShowUpNext(
        position: const Duration(minutes: 4),
        duration: const Duration(minutes: 4, seconds: 30),
        hasNextEpisode: true,
        dismissed: false,
      ),
      isFalse,
    );
  });

  test('an unknown position or runtime raises nothing', () {
    expect(due(Duration.zero), isFalse);
    expect(
      shouldShowUpNext(
        position: const Duration(minutes: 5),
        duration: Duration.zero,
        hasNextEpisode: true,
        dismissed: false,
      ),
      isFalse,
    );
  });
}
