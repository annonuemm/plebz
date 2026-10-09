import 'package:flutter/material.dart';

import '../i18n/strings.g.dart';
import '../models/livetv_channel.dart';
import '../models/livetv_program.dart';
import '../screens/livetv/guide_preview_player.dart';
import '../theme/mono_tokens.dart';
import '../utils/codec_utils.dart';
import '../utils/formatters.dart';
import '../utils/resolution_label.dart';
import '../widgets/fitted_metadata_line.dart';
import 'ocker_detail_panel.dart' show ockerFactsLineFactor;
import 'ocker_skin.dart';
import 'ocker_type.dart';

/// What is on the channel the cursor is standing on: the live picture, and
/// beside it everything the guide knows about the programme under the cursor.
///
/// A band across the top, the way every other variant arranges this — picture
/// left, words right, schedule underneath. It was a column down the left for a
/// while, on the argument that a guide of broadcast hours needs its height more
/// than its width. That turned out to be the wrong trade: the hours are what a
/// guide is *for*, and a column down the left took a quarter of the width away
/// from them, leaving an hour and a half on screen. Across the top it costs
/// [bandHeight] of height, and the schedule gets the whole width — five hours
/// instead of one and a half, and eight channels instead of five.
///
/// The picture itself stays what it was — a live preview, not a still. That is
/// a feature the handoff's drawing could not show, and dropping it for a
/// screenshot would have been a worse trade than keeping it.
class OckerGuidePanel extends StatelessWidget {
  /// How tall the band is, in the 1920 x 1080 frame — multiply by
  /// [ockerScale]. It is the still's own height, so the picture beside it is
  /// exactly the 480 x 270 the detail panel draws everywhere else.
  static const bandHeight = OckerLayout.panelStillHeight;

  /// "Flach"'s band: taller, for its larger facts and description and a third
  /// line of the description — the schedule under it gives up the height (the
  /// viewer's call). The picture grows with it and stays 16:9. Glas too while
  /// [ockerFlatSizes] holds.
  static const flatBandHeight = 280.0;

  /// The channel the preview is actually tuned to, which is not necessarily
  /// the one under the cursor — the picture stays put while the guide is read.
  final LiveTvChannel? previewChannel;

  /// The channel the cursor is standing on.
  final LiveTvChannel? focusedChannel;

  /// The programme under the cursor, or the one currently airing on it.
  final LiveTvProgram? focusedProgram;

  /// What follows it on the same channel, when the grid knows.
  final LiveTvProgram? nextProgram;

  /// The source this channel comes from, for the eyebrow: `PRISMA IPTV`.
  final String? sourceLabel;

  final GlobalKey<GuidePreviewPlayerState>? playerKey;

  /// What the preview says it is receiving, for the capsules beside the
  /// eyebrow — see [GuideStreamInfo]. The preview writes it; this reads it.
  final ValueNotifier<GuideStreamInfo?>? streamInfo;

  const OckerGuidePanel({
    super.key,
    required this.previewChannel,
    required this.focusedChannel,
    required this.focusedProgram,
    this.nextProgram,
    this.sourceLabel,
    this.playerKey,
    this.streamInfo,
  });

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final type = OckerType.of(context);
    final scale = ockerScale(context);
    final flat = ockerFlatSizes(context);
    final height = (flat ? flatBandHeight : bandHeight) * scale;
    final program = focusedProgram;
    final is24Hour = MediaQuery.alwaysUse24HourFormatOf(context);

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: .start,
        children: [
          _Picture(
            width: height * 16 / 9,
            height: height,
            previewChannel: previewChannel,
            playerKey: playerKey,
            streamInfo: streamInfo,
          ),
          SizedBox(width: OckerLayout.rowGutter * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              children: [
                // Room for the capsules whether or not they show, so the
                // title under them never moves as the cursor walks on and off
                // the channel in the picture.
                SizedBox(
                  height: MediaQuery.textScalerOf(context).scale(type.eyebrow.fontSize ?? 19) * ockerFactsLineFactor,
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          _eyebrow(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: type.eyebrow.copyWith(color: tk.ink(0.45)),
                        ),
                      ),
                      if (streamInfo case final info?)
                        ValueListenableBuilder<GuideStreamInfo?>(
                          valueListenable: info,
                          builder: (context, value, _) {
                            final parts = _streamParts(value);
                            if (parts.isEmpty) return const SizedBox.shrink();
                            return Flexible(
                              child: Padding(
                                padding: EdgeInsets.only(left: 18 * scale),
                                child: FittedMetadataLine(
                                  textStyle: type.eyebrow.copyWith(color: tk.ink(0.72)),
                                  parts: parts,
                                  chipped: true,
                                  chipSpacing: 8 * scale,
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
                SizedBox(height: 8 * scale),
                Text(
                  program?.displayTitle ?? focusedChannel?.displayName ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: type.detailTitle(withGroupBar: true).copyWith(color: tk.ink(1)),
                ),
                if (program != null) ...[
                  SizedBox(height: 16 * scale),
                  // The whole of the schedule this channel is keeping, on one
                  // line: when this started and ended, how much of it is left,
                  // and what follows it. Three stacked lines said the same and
                  // took three times the height of a band that has a third of
                  // the height the column it replaced had.
                  Row(
                    crossAxisAlignment: .center,
                    children: [
                      _Window(program: program, is24Hour: is24Hour),
                      if (program.isCurrentlyAiring) ...[SizedBox(width: 24 * scale), _Progress(program: program)],
                      if (nextProgram case final next?) ...[
                        SizedBox(width: 24 * scale),
                        Flexible(
                          child: Text(
                            _afterLabel(next, is24Hour),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: type.guideFacts.copyWith(color: tk.ink(0.7)),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (program.summary case final summary? when summary.trim().isNotEmpty) ...[
                    SizedBox(height: 18 * scale),
                    Flexible(
                      child: Text(
                        summary.trim(),
                        maxLines: flat ? 3 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: type.guideSummary.copyWith(color: tk.ink(0.78)),
                      ),
                    ),
                  ] else
                    const Spacer(),
                ] else
                  const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// `PRISMA IPTV · VOLLPROGRAMM · KANAL 07` — where this channel comes from
  /// and which one it is, in the row above its name.
  String _eyebrow() {
    final parts = <String>[
      if (sourceLabel case final label? when label.isNotEmpty) label.toUpperCase(),
      if (focusedChannel?.displayName case final name? when name.isNotEmpty) name.toUpperCase(),
    ];
    return parts.join(' · ');
  }

  /// `1080p · 50 fps · AAC Stereo` — what the picture beside it is actually
  /// receiving, each on a capsule of glass. Only while the cursor stands on
  /// the channel in the picture: beside another channel's name they would
  /// describe the wrong stream.
  List<MetadataLinePart> _streamParts(GuideStreamInfo? info) {
    final channel = focusedChannel;
    if (info == null || channel == null) return const [];
    if (previewChannel?.key != channel.key || info.channelKey != channel.key) return const [];
    final resolution = info.hasDimensions ? resolutionLabelFromDimensions(info.width, info.height) : null;
    final fps = info.fps;
    final codec = info.audioCodec;
    return [
      if (resolution != null) MetadataLineText(resolutionDisplayLabel(resolution), dropPriority: 1),
      if (fps != null) MetadataLineText(streamFpsLabel(fps), dropPriority: 3),
      if (codec != null && codec.isNotEmpty)
        MetadataLineText(
          [CodecUtils.formatAudioCodec(codec), ?CodecUtils.formatAudioChannels(info.audioChannels)].join(' '),
          dropPriority: 2,
        ),
    ];
  }

  /// `50 fps`, `29.97 fps`: whole where the rate is whole — within a
  /// hundredth, so NTSC's 29.97 and 59.94 keep their decimals.
  @visibleForTesting
  static String streamFpsLabel(double fps) {
    final whole = fps.roundToDouble();
    final number = (fps - whole).abs() < 0.01 ? whole.toInt().toString() : fps.toStringAsFixed(2);
    return '$number fps';
  }

  static String _afterLabel(LiveTvProgram next, bool is24Hour) {
    final start = next.startTime;
    if (start == null) return t.liveTv.upNext(title: next.displayTitle);
    return t.liveTv.upNextAt(
      time: formatClockTime(start, is24Hour: is24Hour),
      title: next.displayTitle,
    );
  }
}

/// The live picture, with the badge that says it is live.
class _Picture extends StatelessWidget {
  final double width;
  final double height;
  final LiveTvChannel? previewChannel;
  final GlobalKey<GuidePreviewPlayerState>? playerKey;
  final ValueNotifier<GuideStreamInfo?>? streamInfo;

  const _Picture({
    required this.width,
    required this.height,
    required this.previewChannel,
    this.playerKey,
    this.streamInfo,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      // No LIVE plaque over the corner of it. It sat on a moving picture on
      // the Live-TV page, beside a guide whose now-line and running-programme
      // progress already say what is on air — three marks for one fact, and
      // the only one of them that covered part of the picture.
      child: GuidePreviewPlayer(key: playerKey, channel: previewChannel, streamInfo: streamInfo),
    );
  }
}

/// `18:45 – 19:15` `30 Min` — the broadcast window on one line of chips.
class _Window extends StatelessWidget {
  final LiveTvProgram program;
  final bool is24Hour;

  const _Window({required this.program, required this.is24Hour});

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final type = OckerType.of(context);
    final parts = <MetadataLinePart>[
      if (program.startTime case final start? when program.endTime != null)
        MetadataLineText(
          '${formatClockTime(start, is24Hour: is24Hour)} – ${formatClockTime(program.endTime!, is24Hour: is24Hour)}',
          dropPriority: 0,
        ),
      if (program.durationMinutes > 0) MetadataLineText('${program.durationMinutes} Min', dropPriority: 1),
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    // On chips, as every line of facts on glass is — the stream's own facts
    // in the eyebrow above already are.
    return FittedMetadataLine(
      textStyle: type.guideFacts.copyWith(color: tk.ink(0.78)),
      parts: parts,
      chipped: true,
      chipSpacing: 8 * ockerScale(context),
    );
  }
}

class _Progress extends StatelessWidget {
  final LiveTvProgram program;

  const _Progress({required this.program});

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final type = OckerType.of(context);
    final scale = ockerScale(context);
    final end = program.endTime;
    final minutesLeft = end == null ? 0 : end.difference(DateTime.now()).inMinutes.clamp(0, 1 << 30);

    return Row(
      children: [
        SizedBox(
          width: 210 * scale,
          child: Stack(
            children: [
              Container(height: 3 * scale, color: tk.ink(0.20)),
              FractionallySizedBox(
                widthFactor: program.progress.clamp(0.0, 1.0),
                child: Container(height: 3 * scale, color: tk.accent),
              ),
            ],
          ),
        ),
        SizedBox(width: 14 * scale),
        Text(
          t.discover.minutesLeft(minutes: minutesLeft),
          style: type.guideFacts.copyWith(color: tk.ink(0.78)),
        ),
      ],
    );
  }
}
