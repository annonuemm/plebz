import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/mpv/mpv.dart';
import 'package:plezy/services/replay_captions.dart';

const _german = SubtitleTrack(id: '3', title: 'Deutsch', language: 'ger');
const _english = SubtitleTrack(id: '4', title: 'English', language: 'eng');

bool _sameLanguage(String? a, String? b) => a != null && b != null && a == b;

class _Rig {
  _Rig({this.on = true, this.canBorrow = true, this.hidden = false, this.showing, this.pick = _german}) {
    captions = ReplayCaptions(
      enabled: () => on,
      eligible: () => canBorrow,
      subtitlesHiddenByViewer: () => hidden,
      currentSubtitleId: () => showing,
      pickTrack: () => pick,
      selectTrack: (track) async => calls.add('select:${track.id}'),
      setVisibility: (visible) async => calls.add('visible:$visible'),
    );
  }

  bool on;
  bool canBorrow;
  bool hidden;
  String? showing;
  SubtitleTrack? pick;
  final calls = <String>[];
  late final ReplayCaptions captions;
}

Duration _s(int seconds) => Duration(seconds: seconds);

void main() {
  group('isReplayStep', () {
    test('counts skips back from two to thirty seconds', () {
      expect(ReplayCaptions.isReplayStep(_s(100), _s(90)), isTrue);
      expect(ReplayCaptions.isReplayStep(_s(100), _s(70)), isTrue);
      expect(ReplayCaptions.isReplayStep(_s(100), _s(98)), isTrue);
    });

    test('ignores nudges, long jumps and forward skips', () {
      expect(ReplayCaptions.isReplayStep(_s(100), _s(99)), isFalse);
      expect(ReplayCaptions.isReplayStep(_s(100), _s(69)), isFalse);
      expect(ReplayCaptions.isReplayStep(_s(100), _s(110)), isFalse);
    });
  });

  group('window', () {
    test('turns a track on after a skip back and off once the start is passed', () async {
      final rig = _Rig();
      await rig.captions.onSeek(_s(100), _s(90));
      expect(rig.calls, ['select:3']);
      expect(rig.captions.isOpen, isTrue);

      rig.captions.onPosition(_s(101));
      await Future<void>.delayed(Duration.zero);
      expect(rig.captions.isOpen, isTrue);

      rig.captions.onPosition(_s(102));
      await Future<void>.delayed(Duration.zero);
      expect(rig.calls, ['select:3', 'select:no']);
      expect(rig.captions.isOpen, isFalse);
    });

    test('does nothing when the setting is off', () async {
      final rig = _Rig(on: false);
      await rig.captions.onSeek(_s(100), _s(90));
      expect(rig.calls, isEmpty);
    });

    test('does nothing where no track can be borrowed', () async {
      final rig = _Rig(canBorrow: false);
      await rig.captions.onSeek(_s(100), _s(90));
      expect(rig.calls, isEmpty);
    });

    test('leaves subtitles that are already showing alone', () async {
      final rig = _Rig(showing: '4');
      await rig.captions.onSeek(_s(100), _s(90));
      expect(rig.calls, isEmpty);
      expect(rig.captions.isOpen, isFalse);
    });

    test('does nothing without a matching track', () async {
      final rig = _Rig(pick: null);
      await rig.captions.onSeek(_s(100), _s(90));
      expect(rig.calls, isEmpty);
    });

    test('reveals subtitles the viewer hid and hides them again', () async {
      final rig = _Rig(hidden: true);
      await rig.captions.onSeek(_s(100), _s(90));
      rig.captions.onPosition(_s(103));
      await Future<void>.delayed(Duration.zero);
      expect(rig.calls, ['visible:true', 'visible:false']);
    });

    test('a second skip back keeps the first start', () async {
      final rig = _Rig();
      await rig.captions.onSeek(_s(100), _s(90));
      await rig.captions.onSeek(_s(91), _s(81));
      expect(rig.calls, ['select:3']);

      rig.captions.onPosition(_s(101));
      await Future<void>.delayed(Duration.zero);
      expect(rig.captions.isOpen, isTrue);
      rig.captions.onPosition(_s(102));
      await Future<void>.delayed(Duration.zero);
      expect(rig.calls, ['select:3', 'select:no']);
    });

    test('a skip forward past the start closes it', () async {
      final rig = _Rig();
      await rig.captions.onSeek(_s(100), _s(90));
      await rig.captions.onSeek(_s(91), _s(130));
      expect(rig.calls, ['select:3', 'select:no']);
    });

    test('a jump far back closes it and opens a fresh one', () async {
      final rig = _Rig();
      await rig.captions.onSeek(_s(100), _s(90));
      await rig.captions.onSeek(_s(91), _s(40)); // 51 s before the start, not a replay step
      expect(rig.calls, ['select:3', 'select:no']);
      expect(rig.captions.isOpen, isFalse);
    });

    test('a choice by the viewer wins and nothing is restored', () async {
      final rig = _Rig();
      await rig.captions.onSeek(_s(100), _s(90));
      rig.captions.onViewerChoice();
      rig.captions.onPosition(_s(110));
      await Future<void>.delayed(Duration.zero);
      expect(rig.calls, ['select:3']);
    });

    test('a track change that is not ours closes it without restoring', () async {
      final rig = _Rig();
      await rig.captions.onSeek(_s(100), _s(90));
      rig.captions.onEngineSubtitleChanged('3'); // our own echo
      expect(rig.captions.isOpen, isTrue);
      rig.captions.onEngineSubtitleChanged('4');
      expect(rig.captions.isOpen, isFalse);
      rig.captions.onPosition(_s(110));
      await Future<void>.delayed(Duration.zero);
      expect(rig.calls, ['select:3']);
    });

    test('switching the setting off mid-window restores', () async {
      final rig = _Rig();
      await rig.captions.onSeek(_s(100), _s(90));
      rig.on = false;
      await rig.captions.onSeek(_s(91), _s(81));
      expect(rig.calls, ['select:3', 'select:no']);
    });

    test('a playhead far before the skip (another item) hides a revealed track again', () async {
      final rig = _Rig(hidden: true);
      await rig.captions.onSeek(_s(1000), _s(990));
      rig.captions.onPosition(_s(3));
      await Future<void>.delayed(Duration.zero);
      expect(rig.calls, ['visible:true', 'visible:false']);
      expect(rig.captions.isOpen, isFalse);
    });

    test('a playhead far before the skip leaves a borrowed track to the track change', () async {
      final rig = _Rig();
      await rig.captions.onSeek(_s(1000), _s(990));
      rig.captions.onPosition(_s(3));
      await Future<void>.delayed(Duration.zero);
      expect(rig.calls, ['select:3']);
      expect(rig.captions.isOpen, isFalse);
    });

    test('dispose leaves the player alone', () async {
      final rig = _Rig();
      await rig.captions.onSeek(_s(100), _s(90));
      await rig.captions.dispose();
      expect(rig.calls, ['select:3']);
      expect(rig.captions.isOpen, isFalse);
    });
  });

  group('pickReplayCaptionTrack', () {
    test('takes the first language that has a track', () {
      final picked = pickReplayCaptionTrack([_english, _german], ['ger', 'eng'], _sameLanguage);
      expect(picked, _german);
      final second = pickReplayCaptionTrack([_english], ['ger', 'eng'], _sameLanguage);
      expect(second, _english);
    });

    test('never borrows another language', () {
      expect(pickReplayCaptionTrack([_english], ['ger'], _sameLanguage), isNull);
      expect(pickReplayCaptionTrack([_german], const [null, ''], _sameLanguage), isNull);
    });

    test('skips forced and commentary tracks', () {
      const forced = SubtitleTrack(id: '5', title: 'Deutsch (Forced)', language: 'ger', isForced: true);
      const commentary = SubtitleTrack(id: '6', title: 'Kommentar', language: 'ger');
      expect(pickReplayCaptionTrack([forced, commentary], ['ger'], _sameLanguage), isNull);
      expect(pickReplayCaptionTrack([forced, commentary, _german], ['ger'], _sameLanguage), _german);
    });

    test('prefers the default track of that language', () {
      const sdh = SubtitleTrack(id: '7', title: 'Deutsch SDH', language: 'ger');
      const plain = SubtitleTrack(id: '8', title: 'Deutsch', language: 'ger', isDefault: true);
      expect(pickReplayCaptionTrack([sdh, plain], ['ger'], _sameLanguage), plain);
    });

    test('ignores the auto and off entries', () {
      expect(pickReplayCaptionTrack([SubtitleTrack.auto, SubtitleTrack.off], ['ger'], _sameLanguage), isNull);
    });
  });
}
