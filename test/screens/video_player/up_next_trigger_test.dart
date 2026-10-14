import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/screens/video_player/up_next_trigger.dart';

import '../../test_helpers/media_items.dart';

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

  // Plebz: the end card's own clock (the user's calls, 2026-10-14).
  group('end card', () {
    const runtime = Duration(minutes: 45);

    test('opens at the credits marker where there is one', () {
      const credits = Duration(minutes: 42);
      expect(
        shouldOpenEndCard(position: const Duration(minutes: 41), duration: runtime, creditsStart: credits),
        isFalse,
      );
      expect(shouldOpenEndCard(position: credits, duration: runtime, creditsStart: credits), isTrue);
    });

    test('without a marker only at 98 %: at 97 % a series is often still the story', () {
      expect(shouldOpenEndCard(position: runtime * 0.97, duration: runtime), isFalse);
      expect(shouldOpenEndCard(position: runtime * 0.981, duration: runtime), isTrue);
    });

    test('Back opens it from the chosen share on, never on a short extra', () {
      expect(endCardBackOpens(position: runtime * 0.94, duration: runtime, percent: 95), isFalse);
      expect(endCardBackOpens(position: runtime * 0.95, duration: runtime, percent: 95), isTrue);
      expect(
        endCardBackOpens(
          position: const Duration(minutes: 4, seconds: 50),
          duration: const Duration(minutes: 5),
          percent: 90,
        ),
        isFalse,
      );
    });
  });

  group('end card suggestion', () {
    MediaItem item(String id, MediaKind kind, {int? viewCount}) =>
        testMediaItem(id: id, backend: MediaBackend.plex, kind: kind, title: id, viewCount: viewCount);
    MediaHub hub(String identifier, List<MediaItem> items) => MediaHub(
      id: identifier,
      identifier: identifier,
      title: identifier,
      type: 'mixed',
      items: items,
      size: items.length,
    );

    test('the similar-titles row first, its unwatched title first, nothing of another kind', () {
      final pick = pickEndCardSuggestion([
        hub('movie.director', [item('d1', MediaKind.movie)]),
        hub('movie.similar', [
          item('s0', MediaKind.show),
          item('s1', MediaKind.movie, viewCount: 1),
          item('s2', MediaKind.movie),
        ]),
      ], kind: MediaKind.movie);
      expect(pick?.id, 's2');
    });

    test('never the title itself; watched rather than nothing; null when empty', () {
      expect(
        pickEndCardSuggestion(
          [
            hub('tv.similar', [item('self', MediaKind.show), item('w', MediaKind.show, viewCount: 3)]),
          ],
          kind: MediaKind.show,
          exclude: {'self'},
        )?.id,
        'w',
      );
      expect(pickEndCardSuggestion(const [], kind: MediaKind.movie), isNull);
    });
  });
}
