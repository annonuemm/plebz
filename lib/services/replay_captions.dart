import '../mpv/mpv.dart';
import '../utils/app_logger.dart';
import '../utils/subtitle_forced_semantics.dart';

/// "Captions on replay" (Plebz): after a short skip back, subtitles show until
/// the playhead is back at the point the skip started, then go away again.
///
/// The window only borrows the screen. It never goes through the track
/// manager, so what the viewer saved for this title (track, language, hidden
/// or not) is untouched, and anything the viewer does with subtitles while it
/// is open ends it without restoring: their choice wins.
class ReplayCaptions {
  ReplayCaptions({
    required this.enabled,
    required this.eligible,
    required this.subtitlesHiddenByViewer,
    required this.currentSubtitleId,
    required this.pickTrack,
    required this.selectTrack,
    required this.setVisibility,
  });

  /// The longest skip back that opens a window (three presses of the default
  /// ten seconds).
  static const Duration maxRewind = Duration(seconds: 30);

  /// Shorter steps are a scrub or a nudge, not "what did they say".
  static const Duration minRewind = Duration(seconds: 2);

  /// How far past the start of the skip the subtitles stay, so the line that
  /// was being spoken at that moment is finished.
  static const Duration tail = Duration(seconds: 2);

  final bool Function() enabled;

  /// False where no track can be borrowed: live TV, a transcode (the server
  /// burns its subtitle into the picture), nothing loaded.
  final bool Function() eligible;

  /// The viewer switched subtitles off with the CC key: a track is selected
  /// but hidden.
  final bool Function() subtitlesHiddenByViewer;

  /// The subtitle track the engine shows now (`'no'` or null for none).
  final String? Function() currentSubtitleId;

  final SubtitleTrack? Function() pickTrack;
  final Future<void> Function(SubtitleTrack track) selectTrack;
  final Future<void> Function(bool visible) setVisibility;

  _Window? _window;

  bool get isOpen => _window != null;

  /// Whether a step from [from] to [to] is a skip back worth a window.
  static bool isReplayStep(Duration from, Duration to) {
    final back = from - to;
    return back >= minRewind && back <= maxRewind;
  }

  /// Called with the position before a seek and its target.
  Future<void> onSeek(Duration from, Duration to) async {
    if (!enabled() || !eligible()) {
      await _close(restore: true);
      return;
    }
    final window = _window;
    if (window != null) {
      if (to >= window.origin + tail) {
        await _close(restore: true);
        return;
      }
      if (window.origin - to <= maxRewind) return;
      await _close(restore: true);
    }
    if (!isReplayStep(from, to)) return;
    await _open(from);
  }

  /// Called on every position tick.
  void onPosition(Duration position) {
    final window = _window;
    if (window == null) return;
    if (position >= window.origin + tail) {
      _close(restore: true);
    } else if (position < window.origin - maxRewind - tail) {
      // The playhead is nowhere near the skip any more (another item, a
      // stream rebuilt at a resume point). Only a revealed track is ours to
      // hide again; a borrowed one was already dropped by the track change.
      _close(restore: window.pickedId == null);
    }
  }

  /// The engine's selected subtitle changed. A change we did not make is the
  /// viewer's (or an item change's) and closes the window.
  void onEngineSubtitleChanged(String? id) {
    final window = _window;
    if (window == null) return;
    final expected = window.pickedId;
    if (expected != null && id != expected) _window = null;
  }

  /// The viewer chose something about subtitles: leave it exactly as is.
  void onViewerChoice() => _window = null;

  Future<void> dispose() => _close(restore: false);

  Future<void> _open(Duration origin) async {
    if (subtitlesHiddenByViewer()) {
      _window = _Window(origin);
      await _guard(() => setVisibility(true));
      return;
    }
    final current = currentSubtitleId();
    if (current != null && current != SubtitleTrack.off.id) return; // already showing
    final track = pickTrack();
    if (track == null) return;
    _window = _Window(origin, pickedId: track.id);
    await _guard(() => selectTrack(track));
  }

  Future<void> _close({required bool restore}) async {
    final window = _window;
    _window = null;
    if (window == null || !restore) return;
    if (window.pickedId != null) {
      await _guard(() => selectTrack(SubtitleTrack.off));
    } else {
      await _guard(() => setVisibility(false));
    }
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (error, stackTrace) {
      appLogger.w('Captions on replay: player call failed', error: error, stackTrace: stackTrace);
    }
  }
}

class _Window {
  _Window(this.origin, {this.pickedId});

  /// Where the skip started.
  final Duration origin;

  /// The track this window turned on; null when it only revealed the one the
  /// viewer had hidden.
  final String? pickedId;
}

/// The track to borrow when the viewer has none showing: a dialogue track in
/// the first of [languages] that has one. Forced-only and commentary tracks
/// are never borrowed, and no track in some other language is either — better
/// no captions than the wrong ones.
SubtitleTrack? pickReplayCaptionTrack(
  List<SubtitleTrack> tracks,
  List<String?> languages,
  bool Function(String? trackLanguage, String? wanted) languageMatches,
) {
  final candidates = tracks
      .where((track) => track.id != SubtitleTrack.auto.id && track.id != SubtitleTrack.off.id)
      .where((track) => !track.effectiveForced && !_looksLikeCommentary(track.title))
      .toList();
  for (final wanted in languages) {
    if (wanted == null || wanted.isEmpty) continue;
    final matching = candidates.where((track) => languageMatches(track.language, wanted)).toList();
    if (matching.isEmpty) continue;
    return matching.firstWhere((track) => track.isDefault, orElse: () => matching.first);
  }
  return null;
}

bool _looksLikeCommentary(String? title) {
  if (title == null) return false;
  final lower = title.toLowerCase();
  return lower.contains('commentary') || lower.contains('kommentar');
}
