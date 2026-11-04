import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../focus/focusable_wrapper.dart';
import '../../i18n/strings.g.dart';
import '../../redesign/ocker_skin.dart';
import '../../redesign/ocker_type.dart';
import '../../services/sport/club_colours.dart';
import '../../services/sport/sport_board.dart';
import '../../services/sport/sport_models.dart';
import '../../theme/mono_tokens.dart';
import 'club_colour_ground.dart';
import 'sport_league_view.dart'
    show SportCrest, SportTap, sportScoreNote, sportTableZone, sportZoneColour, sportZoneLabel;
import 'sport_look.dart';

/// "Glas – v2" (Plebz): a game tile's width over its height, as the "Jetzt
/// live" row's.
const double sportTileAspect = 2.6;

/// One game of a Sport row on the television (Plebz): both clubs' crests and
/// short names on their colours, and between them the kickoff — or the
/// score, with how it was decided, once there is one. The winner's name in
/// bold.
class SportGameTile extends StatelessWidget {
  const SportGameTile({
    super.key,
    required this.match,
    required this.width,
    required this.look,
    this.homePlace,
    this.awayPlace,
    this.date,
    this.touchHeight,
  });

  final SportMatch match;
  final double width;
  final SportLook look;

  /// On a phone or a tablet (Plebz): the tile this tall rather than the
  /// television's 2.6 : 1, its words at least at the handhelds' reading
  /// sizes, which a short tile's own proportions would take below them.
  final double? touchHeight;

  /// The clubs' places in the table, "12." under each name (Plebz); null
  /// where the competition has none.
  final int? homePlace;
  final int? awayPlace;

  /// The day under the kickoff, for a row whose games are on more than one
  /// ("Di., 3. Nov."); null where the row's name says the day.
  final String? date;

  double get height => touchHeight ?? width / sportTileAspect;

  @override
  Widget build(BuildContext context) {
    final now = clock.now();
    final live = match.isLive(now);
    final score = match.scoreAt(now);
    final decider = match.penalties ?? score;
    final homeWon = decider != null && match.isFinished && decider.home > decider.away;
    final awayWon = decider != null && match.isFinished && decider.away > decider.home;
    final home = clubColourFor(match.home);
    final away = clubColourFor(match.away);
    final ink = home != null || away != null ? Colors.white : look.ink(1);
    final h = height;
    final touch = touchHeight != null;
    // A share of the tile's height, on a handheld no smaller than [least].
    double size(double share, double least) => touch ? math.max(h * share, least) : h * share;
    final note = live ? null : (match.isFinished ? sportScoreNote(match) : null);
    final middle = score == null ? DateFormat.Hm().format(match.kickoff.toLocal()) : '${score.home} : ${score.away}';

    Widget club(SportTeam team, {required bool won, required bool lost, int? place}) => SizedBox(
      width: touch ? math.max(h * 0.95, width * 0.3) : h * 0.95,
      child: Column(
        mainAxisAlignment: .center,
        children: [
          SportCrest(team: team, size: size(0.32, 30)),
          SizedBox(height: h * 0.06),
          Text(
            team.shortName,
            maxLines: 1,
            overflow: .ellipsis,
            textAlign: .center,
            style: TextStyle(
              fontFamily: look.teamName().fontFamily,
              fontSize: size(0.09, 13),
              height: 1.1,
              fontWeight: won ? .w700 : .w500,
              color: ink.withValues(alpha: lost ? 0.62 : 0.95),
            ),
          ),
          if (place != null) ...[
            SizedBox(height: h * 0.02),
            Text(
              '$place.',
              style: look.time.copyWith(fontSize: size(0.075, 11), height: 1.1, color: ink.withValues(alpha: 0.62)),
            ),
          ],
        ],
      ),
    );

    return SizedBox(
      width: width,
      height: h,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(artworkRadius(context)),
        child: ClubColourGround(
          home: home,
          away: away,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: h * 0.1),
                child: Row(
                  children: [
                    club(match.home, won: homeWon, lost: awayWon, place: homePlace),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: .min,
                          children: [
                            Text(
                              middle,
                              style: look.score().copyWith(fontSize: size(0.18, 22), color: ink),
                            ),
                            if (date case final date?) ...[
                              SizedBox(height: h * 0.03),
                              Text(
                                date,
                                style: look.time.copyWith(
                                  fontSize: size(0.075, 11),
                                  color: ink.withValues(alpha: 0.75),
                                ),
                              ),
                            ],
                            if (note != null) ...[
                              SizedBox(height: h * 0.03),
                              Text(
                                note,
                                style: look.time.copyWith(fontSize: size(0.075, 11), color: ink.withValues(alpha: 0.7)),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    club(match.away, won: awayWon, lost: homeWon, place: awayPlace),
                  ],
                ),
              ),
              if (live)
                Positioned(
                  top: h * 0.08,
                  right: h * 0.08,
                  child: SportLiveMark(look: look, height: size(0.15, 18)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "LIVE" on the accent, white or the ground on it, whichever reads.
class SportLiveMark extends StatelessWidget {
  const SportLiveMark({super.key, required this.look, required this.height});

  final SportLook look;
  final double height;

  @override
  Widget build(BuildContext context) {
    final accent = look.live;
    return OckerKeepColours(
      child: Container(
        height: height,
        padding: EdgeInsets.symmetric(horizontal: height * 0.45),
        decoration: ShapeDecoration(color: accent, shape: const StadiumBorder()),
        // As wide as its word wherever it stands: a container's own alignment
        // would stretch it across a loose width, the stage's line.
        child: Center(
          widthFactor: 1,
          child: Text(
            t.sport.live,
            style: OckerType.of(context).nowChip.copyWith(
              fontSize: height * 0.56,
              fontWeight: .w700,
              height: 1,
              color: ThemeData.estimateBrightnessForColor(accent) == Brightness.dark ? Colors.white : look.tk.bg,
            ),
          ),
        ),
      ),
    );
  }
}

/// The clubs behind the television's stage (Plebz): their colours, and how
/// much of them shows — the page scrolled down, they fade.
@immutable
class SportStageGround {
  const SportStageGround({this.home, this.away, this.opacity = 1});

  final Color? home;
  final Color? away;
  final double opacity;

  @override
  bool operator ==(Object other) =>
      other is SportStageGround && other.home == home && other.away == away && other.opacity == opacity;

  @override
  int get hashCode => Object.hash(home, away, opacity);
}

/// The stage's ground at the screen's top right (Plebz): the home club's
/// colour running into the away club's, fading into the page to the left and
/// downwards — a backdrop, as the start page's picture is, not a box.
///
/// Drawn once, as the start page's grounds are: the clubs' colours under
/// their round fade are rendered into a picture for each pair of clubs
/// ([SportStageGrounds]) and shown as that picture, and as the page scrolls only
/// the picture's alpha changes. Left live, the fade was an offscreen pass
/// over the whole screen on every frame anything moved — the cost that held
/// the start page on a 32-bit box at 20 frames a second (2026-10-15).
class SportStageBackdrop extends StatelessWidget {
  const SportStageBackdrop({super.key, required this.ground});

  final SportStageGround? ground;

  /// A club's colour at the depth a backdrop wants: still its own, dark
  /// enough for white over it.
  static Color _deep(Color colour) {
    final hsl = HSLColor.fromColor(colour);
    return hsl.withSaturation(hsl.saturation.clamp(0.0, 0.85)).withLightness(hsl.lightness.clamp(0.0, 0.34)).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final ground = this.ground;
    final opacity = ground == null || (ground.home == null && ground.away == null) ? 0.0 : ground.opacity;
    final plain = tokens(context).ink(0.10);
    final home = ground?.home == null ? plain : _deep(ground!.home!);
    final away = ground?.away == null ? plain : _deep(ground!.away!);
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    return RepaintBoundary(
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: opacity * 0.9),
        duration: const Duration(milliseconds: 300),
        builder: (context, alpha, _) => CustomPaint(
          painter: _StageGroundPainter(home: home, away: away, alpha: alpha, devicePixelRatio: devicePixelRatio),
        ),
      ),
    );
  }
}

/// Shows the stage's prepared ground at [alpha]: one plain image draw, no
/// layer of its own.
class _StageGroundPainter extends CustomPainter {
  const _StageGroundPainter({
    required this.home,
    required this.away,
    required this.alpha,
    required this.devicePixelRatio,
  });

  final Color home;
  final Color away;
  final double alpha;
  final double devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    if (alpha <= 0 || size.isEmpty) return;
    final picture = SportStageGrounds.pictureFor(home, away, size, devicePixelRatio);
    canvas.drawImageRect(
      picture,
      Rect.fromLTWH(0, 0, picture.width.toDouble(), picture.height.toDouble()),
      Offset.zero & size,
      Paint()
        ..filterQuality = FilterQuality.low
        ..color = Color.fromRGBO(0, 0, 0, alpha.clamp(0.0, 1.0)),
    );
  }

  @override
  bool shouldRepaint(_StageGroundPainter oldDelegate) =>
      oldDelegate.home != home ||
      oldDelegate.away != away ||
      oldDelegate.alpha != alpha ||
      oldDelegate.devicePixelRatio != devicePixelRatio;
}

/// The stage's grounds, prepared at the device's pixels — at most half a
/// 1080p screen across: colours this soft look the same drawn up from it —
/// and kept for the last two pairs of clubs, the stage stepping between them.
@visibleForTesting
abstract final class SportStageGrounds {
  static const int _kept = 2;
  static const double _largestSide = 960;

  // Insertion order is use order: the first is the one used longest ago.
  static final Map<(Color, Color, int, int), ui.Image> _pictures = {};

  /// How many pictures were prepared, for tests.
  static int debugPrepared = 0;

  static ui.Image pictureFor(Color home, Color away, Size size, double devicePixelRatio) {
    final physical = size * devicePixelRatio;
    final shrink = math.min(1.0, _largestSide / math.max(physical.width, physical.height));
    final width = math.max(1, (physical.width * shrink).round());
    final height = math.max(1, (physical.height * shrink).round());
    final key = (home, away, width, height);
    final kept = _pictures.remove(key);
    if (kept != null) return _pictures[key] = kept;
    final picture = _render(home, away, width, height);
    debugPrepared++;
    _pictures[key] = picture;
    while (_pictures.length > _kept) {
      _pictures.remove(_pictures.keys.first)!.dispose();
    }
    return picture;
  }

  static ui.Image _render(Color home, Color away, int width, int height) {
    final rect = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, rect);
    canvas.saveLayer(rect, Paint());
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: const Alignment(-1, -0.2),
          end: const Alignment(1, 0.2),
          colors: [home, home, away],
          stops: const [0, 0.35, 1],
        ).createShader(rect),
    );
    // An ellipse out of the corner, not two straight fades: their product
    // drew a box's edges into the page (the user's word, "kastig").
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = const RadialGradient(
          center: Alignment.topRight,
          radius: 1,
          colors: [Color(0xFF000000), Color(0xFF000000), Color(0x99000000), Color(0x00000000)],
          stops: [0, 0.34, 0.68, 1],
          transform: _StretchFromCorner(),
        ).createShader(rect),
    );
    canvas.restore();
    final recording = recorder.endRecording();
    final picture = recording.toImageSync(width, height);
    recording.dispose();
    return picture;
  }
}

/// A radial gradient's circle drawn out from the top right corner (Plebz).
/// Across, it is as tall as the box and stretched as wide. Upright — a phone,
/// a tablet held so — wider than the box, so the clubs' colours cross its
/// whole width at the top (the user's call), and down over the stage: the
/// gradient's radius is a share of the shorter side, and a circle as wide as
/// an upright screen left its left corner dark.
class _StretchFromCorner extends GradientTransform {
  const _StretchFromCorner();

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    if (bounds.width == 0 || bounds.height == 0) return null;
    final across = bounds.width >= bounds.height;
    final sx = across ? bounds.width / bounds.height : 1.6;
    final sy = across ? 1.0 : 0.6 * bounds.height / bounds.width;
    return Matrix4.identity()
      ..translateByDouble(bounds.right, bounds.top, 0, 1)
      ..scaleByDouble(sx, sy, 1, 1)
      ..translateByDouble(-bounds.right, -bounds.top, 0, 1);
  }
}

/// Why a game stands on the stage, over its clubs' names (Plebz): none for a
/// game on now, which says so under its score.
String? sportStageEyebrow(SportStageReason reason) => switch (reason) {
  SportStageReason.live => null,
  SportStageReason.favourite => t.sport.yourClub,
  SportStageReason.germanClub => t.sport.germanClub,
  SportStageReason.next => t.sport.nextMatch,
  SportStageReason.finished => t.sport.finalScore,
};

/// The game a matchday puts first, on the television (Plebz): why it stands
/// here — "Dein Verein", LIVE — over its two clubs' names and when it is
/// played, with the page's one main action under them; at the right its
/// crests on the clubs' ground with the kickoff or the score between them.
/// No panel of its own: the ground is [SportStageBackdrop], at the screen's
/// corner.
class SportStageHero extends StatelessWidget {
  const SportStageHero({
    super.key,
    required this.match,
    required this.reason,
    required this.look,
    required this.locale,
    required this.action,
    this.position,
  });

  final SportMatch match;
  final SportStageReason reason;
  final SportLook look;
  final String locale;

  /// The row of the stage's buttons.
  final Widget action;

  /// "Spiel 3 von 9" once the viewer has stepped through the games, in place
  /// of why the game stands here.
  final String? position;

  @override
  Widget build(BuildContext context) {
    final s = look.scale;
    final type = OckerType.of(context);
    final now = clock.now();
    final live = match.isLive(now);
    final score = match.scoreAt(now);
    final kickoff = match.kickoff.toLocal();
    final quiet = type.spotlightFacts.copyWith(color: look.ink(0.62));
    final eyebrow = sportStageEyebrow(reason);
    final note = sportScoreNote(match);
    final facts = [
      DateFormat.MMMMEEEEd(locale).format(kickoff),
      DateFormat.Hm(locale).format(kickoff),
      if (match.stadium case final stadium? when stadium.isNotEmpty) stadium,
      ?note,
    ].join(' · ');
    final crest = 200 * s;

    return Row(
      crossAxisAlignment: .center,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 860 * s),
          child: Column(
            crossAxisAlignment: .start,
            mainAxisSize: .min,
            children: [
              SizedBox(
                height: 34 * s,
                // A game on now says so once, under its score (the user's
                // call): no mark of its own up here.
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(position ?? eyebrow ?? '', style: quiet),
                ),
              ),
              SizedBox(height: 16 * s),
              Text(
                '${match.home.name}\n${match.away.name}',
                maxLines: 2,
                overflow: .ellipsis,
                style: type.spotlightTitle().copyWith(color: look.ink(1)),
              ),
              SizedBox(height: 20 * s),
              Text(
                facts,
                maxLines: 1,
                overflow: .ellipsis,
                style: quiet.copyWith(color: look.ink(0.72)),
              ),
              SizedBox(height: 32 * s),
              action,
            ],
          ),
        ),
        const Spacer(),
        Row(
          mainAxisSize: .min,
          children: [
            SportCrest(team: match.home, size: crest),
            SizedBox(width: 64 * s),
            Column(
              mainAxisSize: .min,
              children: [
                Text(
                  score == null ? DateFormat.Hm(locale).format(kickoff) : '${score.home} : ${score.away}',
                  style: look.score().copyWith(fontSize: 56 * s, color: Colors.white),
                ),
                SizedBox(height: 8 * s),
                live
                    ? SportLiveMark(look: look, height: 28 * s)
                    : Text(
                        match.isFinished ? (note ?? t.sport.finalScore) : DateFormat.EEEE(locale).format(kickoff),
                        style: look.time.copyWith(fontSize: 18 * s, color: Colors.white.withValues(alpha: 0.72)),
                      ),
              ],
            ),
            SizedBox(width: 64 * s),
            SportCrest(team: match.away, size: crest),
          ],
        ),
        SizedBox(width: 80 * s),
      ],
    );
  }
}

/// The game a matchday puts first, on a phone or a tablet (Plebz): the
/// television's stage for touch, on the same clubs' ground
/// ([SportStageBackdrop]) behind the page. Narrow, it stands centred — the
/// crests with the kickoff or the score between them over the clubs' names;
/// [wide], the names on the left as on the television and the crests at the
/// right. [action] is "Zum Spiel" and whatever steps through the games.
class SportTouchStage extends StatelessWidget {
  const SportTouchStage({
    super.key,
    required this.match,
    required this.reason,
    required this.look,
    required this.locale,
    required this.action,
    this.position,
    this.wide = false,
  });

  final SportMatch match;
  final SportStageReason reason;
  final SportLook look;
  final String locale;
  final Widget action;

  /// "Spiel 3 von 9" once the viewer has stepped through the games.
  final String? position;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final now = clock.now();
    final live = match.isLive(now);
    final score = match.scoreAt(now);
    final kickoff = match.kickoff.toLocal();
    final family = look.teamName().fontFamily;
    final quiet = TextStyle(fontFamily: family, fontSize: 15, height: 1.3, color: look.ink(0.62));
    final eyebrow = position ?? sportStageEyebrow(reason);
    final note = sportScoreNote(match);
    final facts = [
      DateFormat.MMMMEEEEd(locale).format(kickoff),
      DateFormat.Hm(locale).format(kickoff),
      ?note,
    ].join(' · ');
    final crest = wide ? 88.0 : 60.0;
    final board = Row(
      mainAxisSize: .min,
      children: [
        SportCrest(team: match.home, size: crest),
        SizedBox(width: wide ? 28 : 20),
        Column(
          mainAxisSize: .min,
          children: [
            Text(
              score == null ? DateFormat.Hm(locale).format(kickoff) : '${score.home} : ${score.away}',
              style: look.score().copyWith(fontSize: wide ? 36 : 28, color: look.ink(1)),
            ),
            if (live) ...[const SizedBox(height: 6), SportLiveMark(look: look, height: 20)],
          ],
        ),
        SizedBox(width: wide ? 28 : 20),
        SportCrest(team: match.away, size: crest),
      ],
    );
    final names = TextStyle(fontFamily: family, fontWeight: .w700, color: look.ink(1), height: 1.15);

    if (!wide) {
      return Column(
        mainAxisSize: .min,
        children: [
          SizedBox(height: 22, child: Text(eyebrow ?? '', style: quiet)),
          const SizedBox(height: 8),
          board,
          const SizedBox(height: 12),
          Text(
            '${match.home.name} – ${match.away.name}',
            maxLines: 2,
            overflow: .ellipsis,
            textAlign: .center,
            style: names.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 4),
          Text(facts, maxLines: 1, overflow: .ellipsis, textAlign: .center, style: quiet),
          const SizedBox(height: 16),
          action,
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: .start,
            mainAxisSize: .min,
            children: [
              SizedBox(height: 22, child: Text(eyebrow ?? '', style: quiet)),
              const SizedBox(height: 6),
              Text(
                '${match.home.name}\n${match.away.name}',
                maxLines: 2,
                overflow: .ellipsis,
                style: names.copyWith(fontSize: 28),
              ),
              const SizedBox(height: 6),
              Text(facts, maxLines: 1, overflow: .ellipsis, style: quiet),
              const SizedBox(height: 16),
              action,
            ],
          ),
        ),
        const SizedBox(width: 24),
        board,
      ],
    );
  }
}

/// A round of the DFB-Pokal on "Der Weg nach Berlin" (Plebz): its name, and
/// under it whether it is the one being played or behind. The round on show
/// in the chosen wash; OK shows it.
class SportRoundPane extends StatelessWidget {
  const SportRoundPane({
    super.key,
    required this.name,
    required this.note,
    required this.onShow,
    required this.isCurrent,
    required this.look,
    required this.focusNode,
    required this.onSelect,
    required this.onNavigateLeft,
    required this.onNavigateRight,
    required this.onNavigateUp,
    required this.onBack,
  });

  final String name;
  final String? note;
  final bool onShow;
  final bool isCurrent;
  final SportLook look;
  final FocusNode focusNode;
  final VoidCallback onSelect;
  final VoidCallback onNavigateLeft;
  final VoidCallback onNavigateRight;
  final VoidCallback onNavigateUp;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final s = look.scale;
    final radius = 20 * s;
    final tk = look.tk;
    final noteStyle = look.time.copyWith(
      color: isCurrent ? (tk.flat ? look.ink(0.85) : tk.accent) : look.ink(0.5),
      fontWeight: isCurrent ? .w600 : .w400,
    );
    return FocusableWrapper(
      focusNode: focusNode,
      borderRadius: radius,
      useBackgroundFocus: true,
      glassFocus: true,
      useComfortableZone: true,
      semanticLabel: [name, ?note].join(', '),
      onSelect: onSelect,
      onNavigateLeft: onNavigateLeft,
      onNavigateRight: onNavigateRight,
      onNavigateUp: onNavigateUp,
      onNavigateDown: () {},
      onBack: onBack,
      child: SportTap(
        onTap: onSelect,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 22 * s, vertical: 18 * s),
          decoration: BoxDecoration(
            color: onShow ? tk.accent.withValues(alpha: ockerV2ChosenWash) : look.ink(0.05),
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Column(
            crossAxisAlignment: .start,
            mainAxisSize: .min,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: .ellipsis,
                style: look.teamName(strong: true).copyWith(color: look.ink(1)),
              ),
              SizedBox(height: 6 * s),
              Text(note ?? '', maxLines: 1, style: noteStyle),
            ],
          ),
        ),
      ),
    );
  }
}

/// A table cut into panels of at most ten places each (Plebz): a league's 18
/// into two of nine, a European cup's 36 into four of nine, the third
/// division's 20 into two of ten — each on screen whole, and a row of them
/// the cursor walks as it walks a row of games.
List<List<T>> sportTablePanels<T>(List<T> rows) {
  if (rows.isEmpty) return const [];
  final panels = (rows.length / 10).ceil();
  final per = (rows.length / panels).ceil();
  return [for (var i = 0; i < rows.length; i += per) rows.sublist(i, (i + per).clamp(0, rows.length))];
}

/// The height of a panel of [places] places, at the 1920 reference.
double sportTablePanelHeight(int places) => 36 + 36 + places * 52;

/// One panel of the table at the foot of the television's Sport page (Plebz):
/// flat, each place's number in its zone's colour and a hairline where a
/// zone begins, the clubs of [highlight] in the chosen wash. [count] is the
/// whole table's length, which the zones are measured on.
class SportTablePanel extends StatelessWidget {
  const SportTablePanel({
    super.key,
    required this.rows,
    required this.count,
    required this.league,
    required this.highlight,
    required this.look,
  });

  final List<SportTableRow> rows;
  final int count;
  final SportLeague league;
  final Set<int> highlight;
  final SportLook look;

  @override
  Widget build(BuildContext context) {
    final s = look.scale;
    final radius = BorderRadius.circular(28 * s);
    final head = look.tableCell().copyWith(fontSize: 16 * s, color: look.ink(0.45));
    return Container(
      // The rows' wash reaches 14 past their words, inside the panel's 32.
      padding: EdgeInsets.fromLTRB(18 * s, 18 * s, 18 * s, 18 * s),
      decoration: BoxDecoration(color: look.ink(0.05), borderRadius: radius),
      child: Column(
        children: [
          Container(
            height: 36 * s,
            padding: EdgeInsets.symmetric(horizontal: 14 * s),
            child: Row(
              children: [
                SizedBox(
                  width: 56 * s,
                  child: Text(t.sport.position, style: head),
                ),
                Expanded(child: Text(t.sport.club, style: head)),
                _number(t.sport.played, head),
                _number(t.sport.difference, head),
                _number(t.sport.points, head),
              ],
            ),
          ),
          for (var i = 0; i < rows.length; i++) _row(i),
        ],
      ),
    );
  }

  Widget _number(String text, TextStyle style) => SizedBox(
    width: 80 * look.scale,
    child: Text(text, textAlign: TextAlign.end, style: style),
  );

  Widget _row(int index) {
    final s = look.scale;
    final row = rows[index];
    final zone = sportTableZone(league, row.position, count);
    final previousZone = index == 0 ? zone : sportTableZone(league, rows[index - 1].position, count);
    final lit = highlight.contains(row.team.id);
    final style = look.tableCell(strong: lit).copyWith(fontSize: 21 * s, color: look.ink(lit ? 1 : 0.85));
    final difference = row.goalDifference > 0 ? '+${row.goalDifference}' : '${row.goalDifference}';
    return Container(
      height: 52 * s,
      padding: EdgeInsets.symmetric(horizontal: 14 * s),
      decoration: BoxDecoration(
        color: lit ? look.tk.accent.withValues(alpha: ockerV2ChosenWash * 0.6) : null,
        borderRadius: BorderRadius.circular(14 * s),
        border: index > 0 && zone != previousZone ? Border(top: BorderSide(color: look.ink(0.10))) : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56 * s,
            child: Text(
              '${row.position}',
              style: style.copyWith(
                color: zone == null ? look.ink(0.55) : sportZoneColour(league, zone),
                fontWeight: zone == null ? null : .w600,
              ),
            ),
          ),
          SportCrest(team: row.team, size: 32 * s),
          SizedBox(width: 14 * s),
          Expanded(
            child: Text(row.team.shortName, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
          ),
          _number('${row.played}', style),
          _number(difference, style.copyWith(color: look.ink(lit ? 1 : 0.62))),
          _number('${row.points}', style.copyWith(fontWeight: .w700)),
        ],
      ),
    );
  }
}

/// What the zones' colours stand for, under the table's panels (Plebz): "1–4
/// Champions League", the range in its colour.
class SportTableLegend extends StatelessWidget {
  const SportTableLegend({super.key, required this.rows, required this.league, required this.look});

  final List<SportTableRow> rows;
  final SportLeague league;
  final SportLook look;

  @override
  Widget build(BuildContext context) {
    final s = look.scale;
    final style = look.time.copyWith(fontSize: 16 * s, color: look.ink(0.55));
    return Wrap(
      spacing: 32 * s,
      runSpacing: 8 * s,
      children: [
        for (final zone in const [0, 1, 2])
          if (_range(zone) case final range?)
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$range ',
                    style: TextStyle(color: sportZoneColour(league, zone), fontWeight: .w600),
                  ),
                  TextSpan(text: sportZoneLabel(league, zone)),
                ],
              ),
              style: style,
            ),
      ],
    );
  }

  /// "1–4": the places of [zone], or null where the table has none.
  String? _range(int zone) {
    final places = [
      for (final row in rows)
        if (sportTableZone(league, row.position, rows.length) == zone) row.position,
    ]..sort();
    if (places.isEmpty) return null;
    return places.first == places.last ? '${places.first}' : '${places.first}–${places.last}';
  }
}
