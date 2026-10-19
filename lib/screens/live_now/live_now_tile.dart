import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../i18n/strings.g.dart';
import '../../media/ids.dart';
import '../../media/media_backend.dart';
import '../../media/media_hub.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../redesign/ocker_skin.dart';
import '../../redesign/ocker_type.dart';
import '../../services/sport/club_colours.dart';
import '../sport/club_colour_ground.dart';
import '../../services/sport/sport_league_names.dart';
import '../../services/sport/sport_models.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/provider_extensions.dart';
import '../../widgets/live_tv_channel_logo.dart';
import '../sport/sport_league_view.dart' show SportCrest;
import 'live_now_loader.dart';

/// The row's id, and its type: what the rail and the stacked sections ask to
/// draw [LiveNowTileCard] instead of a poster.
const liveNowHubId = 'live_now';
const liveNowHubType = 'live';

bool isLiveNowHub(MediaHub hub) => hub.type == liveNowHubType;

/// The row as a hub: one stand-in item per entry, named for the tile's caption
/// and described for the spotlight and for a screen reader. The tiles look
/// their entry up by the item's id in [LiveNowScope].
MediaHub liveNowHub(LiveNowSnapshot snapshot) => MediaHub(
  id: liveNowHubId,
  identifier: '_live_now_',
  title: t.discover.liveNow,
  type: liveNowHubType,
  size: snapshot.entries.length,
  items: [for (final entry in snapshot.entries) _itemFor(entry)],
);

MediaItem _itemFor(LiveNowEntry entry) => switch (entry) {
  LiveNowGame(:final match, :final league) => MediaItem(
    id: entry.id,
    backend: MediaBackend.plex,
    kind: MediaKind.unknown,
    title: '${match.home.shortName} – ${match.away.shortName}',
    summary: [liveNowLeagueName(league), liveNowGameStatus(match, clock.now())].join(' · '),
  ),
  LiveNowChannel(:final channel, :final program) => MediaItem(
    id: entry.id,
    backend: MediaBackend.plex,
    kind: MediaKind.unknown,
    title: program?.title ?? channel.displayName,
    summary: [
      channel.displayName,
      if (program?.summary case final summary? when summary.isNotEmpty) summary,
    ].join(' · '),
  ),
};

String liveNowLeagueName(SportLeague league) => sportLeagueName(league);

/// "LIVE" for a game on now, "Heute 20:30" for one still to come.
///
/// No score: OpenLigaDB does not keep a game's goals current while it is on,
/// so a running game stood at 0:0 to the end (the viewer's report).
String liveNowGameStatus(SportMatch match, DateTime now) {
  if (match.isLive(now)) return t.sport.live;
  return '${t.sport.today} ${DateFormat.Hm().format(match.kickoff.toLocal())}';
}

/// The row's entries by id, for the tiles under it.
class LiveNowScope extends InheritedWidget {
  const LiveNowScope({super.key, required this.snapshot, required super.child});

  final LiveNowSnapshot snapshot;

  static LiveNowEntry? entryOf(BuildContext context, String id) =>
      context.dependOnInheritedWidgetOfExactType<LiveNowScope>()?.snapshot.byId[id];

  @override
  bool updateShouldNotify(LiveNowScope oldWidget) => !identical(snapshot, oldWidget.snapshot);
}

/// The corner of a tile: the posters' own under the redesigns, so the row reads
/// with the rows around it, and the original look's 8 elsewhere. The rail's
/// focus ring takes the same.
double liveNowTileRadius(BuildContext context, double scale) =>
    ockerGlass(context) ? artworkRadius(context) : flatRadius(context, 8) * scale;

/// One tile of the "Jetzt live" row: a wide card and its caption under it.
///
/// A game shows both crests and, while it is on, the score and a LIVE mark; a
/// channel its logo and how far the programme on it has run. Under the
/// redesigns the card is a picture and nothing else, as a poster is: a game
/// stands on its clubs' colours, and the caption takes two lines — the
/// pairing (or the programme) and the league with the kickoff (or the
/// channel). The original look keeps the league on the card and one line
/// under it. Drawn the same on the television rail and in the stacked
/// sections — only [scale] differs.
class LiveNowTileCard extends StatelessWidget {
  const LiveNowTileCard({
    super.key,
    required this.item,
    required this.width,
    required this.cardHeight,
    required this.captionHeight,
    this.scale = 1,
    this.card,
  });

  final MediaItem item;
  final double width;
  final double cardHeight;
  final double captionHeight;
  final double scale;

  /// Wraps the card alone — the focus border goes round the picture, not
  /// round its caption.
  final Widget Function(Widget card)? card;

  @override
  Widget build(BuildContext context) {
    final entry = LiveNowScope.entryOf(context, item.id);
    final tk = tokens(context);
    final redesign = ockerGlass(context);
    final body = SizedBox(
      width: width,
      height: cardHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(liveNowTileRadius(context, scale)),
        child: switch (entry) {
          LiveNowGame() => _GameCard(entry: entry, height: cardHeight, scale: scale),
          LiveNowChannel() => ClubColourGround(
            child: _ChannelCard(entry: entry, width: width, height: cardHeight, scale: scale),
          ),
          null => const SizedBox.shrink(),
        },
      ),
    );
    final score = switch (entry) {
      LiveNowGame(:final match) when match.isLive(clock.now()) => match.scoreAt(clock.now()),
      _ => null,
    };
    final second = !redesign
        ? null
        : switch (entry) {
            LiveNowGame(:final match, :final league) =>
              '${liveNowLeagueName(league)} · ${DateFormat.Hm().format(match.kickoff.toLocal())}',
            LiveNowChannel(:final channel) => channel.displayName,
            null => null,
          };
    return Semantics(
      label: [
        item.displayTitle,
        if (item.summary case final summary? when summary.isNotEmpty) summary,
        if (score != null) '${score.home}:${score.away}',
      ].join(', '),
      child: SizedBox(
        width: width,
        height: cardHeight + captionHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            card?.call(body) ?? body,
            SizedBox(
              height: captionHeight,
              // The words are shares of the box, and the box already grew
              // with the viewer's text size (see HubSection): scaled again
              // here they would outgrow it.
              child: MediaQuery.withNoTextScaling(
                child: second == null
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          item.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tk.ink(0.9),
                            fontSize: captionHeight * 0.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : Padding(
                        padding: EdgeInsets.only(top: captionHeight * 0.12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: tk.ink(0.92),
                                fontSize: captionHeight * 0.36,
                                height: 1.2,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: captionHeight * 0.06),
                            Text(
                              second,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: tk.ink(0.55),
                                fontSize: captionHeight * 0.28,
                                height: 1.2,
                                fontWeight: FontWeight.w500,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.entry, required this.height, required this.scale});

  final LiveNowGame entry;
  final double height;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final match = entry.match;
    final now = clock.now();
    final live = match.isLive(now);
    // OpenLigaDB's matchday asked for by number keeps a game's goals current
    // while it is on (see SportRepository.current), so the score is the
    // score; a game still to come shows the pairing.
    final score = live ? match.scoreAt(now) : null;

    if (!ockerGlass(context)) {
      final small = height * 0.11;
      final crest = height * 0.38;
      final pad = height * 0.09;
      return ColoredBox(
        color: tk.tileFill,
        child: Padding(
          padding: EdgeInsets.all(pad),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      liveNowLeagueName(entry.league),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: tk.ink(0.55), fontSize: small, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (live)
                    DecoratedBox(
                      decoration: BoxDecoration(color: tk.accent, borderRadius: BorderRadius.circular(small * 0.4)),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: small * 0.5, vertical: small * 0.15),
                        child: Text(
                          t.sport.live,
                          style: TextStyle(color: tk.bg, fontSize: small * 0.9, fontWeight: FontWeight.w800),
                        ),
                      ),
                    )
                  else
                    Text(
                      DateFormat.Hm().format(match.kickoff.toLocal()),
                      style: TextStyle(color: tk.ink(0.8), fontSize: small, fontWeight: FontWeight.w700),
                    ),
                ],
              ),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SportCrest(team: match.home, size: crest),
                      SizedBox(width: height * 0.1),
                      Text(
                        score == null ? t.sport.versus : '${score.home} : ${score.away}',
                        style: TextStyle(
                          color: tk.ink(live ? 1 : 0.6),
                          fontSize: height * 0.17,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      SizedBox(width: height * 0.1),
                      SportCrest(team: match.away, size: crest),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final home = clubColourFor(match.home);
    final away = clubColourFor(match.away);
    final ink = home != null || away != null ? Colors.white : tk.ink(1);
    final pad = height * 0.08;
    final crest = height * 0.44;
    return ClubColourGround(
      home: home,
      away: away,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            // Shrunk rather than cut where a tile is narrow for its height.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SportCrest(team: match.home, size: crest),
                  SizedBox(width: height * 0.1),
                  if (score != null)
                    Text(
                      '${score.home} : ${score.away}',
                      style: TextStyle(
                        color: ink,
                        fontSize: height * 0.2,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    )
                  else
                    Text(
                      t.sport.versus,
                      style: TextStyle(color: ink.withValues(alpha: 0.6), fontSize: height * 0.12),
                    ),
                  SizedBox(width: height * 0.1),
                  SportCrest(team: match.away, size: crest),
                ],
              ),
            ),
          ),
          if (live)
            Positioned(
              top: pad,
              right: pad,
              child: DecoratedBox(
                decoration: ShapeDecoration(color: tk.accent, shape: const StadiumBorder()),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: height * 0.065, vertical: height * 0.03),
                  child: Text(
                    t.sport.live,
                    style: OckerType.of(context).nowChip.copyWith(
                      fontSize: height * 0.085,
                      fontWeight: FontWeight.w700,
                      // White or the ground, whichever reads on the accent:
                      // a picked yellow takes the dark, as the guide's pill.
                      color: ThemeData.estimateBrightnessForColor(tk.accent) == Brightness.dark ? Colors.white : tk.bg,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChannelCard extends StatelessWidget {
  const _ChannelCard({required this.entry, required this.width, required this.height, required this.scale});

  final LiveNowChannel entry;
  final double width;
  final double height;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final channel = entry.channel;
    final program = entry.program;
    final serverId = serverIdOrNull(channel.serverId);
    final client = serverId == null ? null : context.tryGetMediaClientForServer(serverId);
    final progress = _progress(program?.beginsAt, program?.endsAt);

    return Stack(
      fit: StackFit.expand,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: width * 0.18, vertical: height * 0.2),
          child: LiveTvChannelLogo(
            channel: channel,
            client: client,
            fit: BoxFit.contain,
            fallback: (context) => Center(
              child: Text(
                channel.displayName,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: tk.ink(0.85), fontSize: height * 0.13, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
        if (progress != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: (3 * scale).clamp(2.0, 6.0),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress,
              child: ColoredBox(color: tk.accent),
            ),
          ),
      ],
    );
  }

  static double? _progress(int? begins, int? ends) {
    if (begins == null || ends == null || ends <= begins) return null;
    final now = clock.now().millisecondsSinceEpoch / 1000;
    return ((now - begins) / (ends - begins)).clamp(0.0, 1.0);
  }
}
