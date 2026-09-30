import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../focus/focusable_wrapper.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/ids.dart';
import '../../../models/livetv_channel.dart';
import '../../../models/livetv_program.dart';
import '../../../utils/provider_extensions.dart';
import '../../../redesign/ocker_skin.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/scroll_utils.dart';
import '../../../utils/tone_mapped_logo_image.dart';
import '../../live_tv_channel_logo.dart';

/// The channel list, as a strip over the picture.
///
/// The live counterpart of the chapter/queue strip: same panel, same
/// LEFT/RIGHT-then-SELECT handling, but built for a list that runs to
/// thousands of entries — cells and their focus nodes are created as they
/// scroll into view rather than up front.
class LiveChannelStrip extends StatefulWidget {
  const LiveChannelStrip({
    super.key,
    required this.channels,
    required this.currentIndex,
    required this.onChannelSelected,
    this.programFor,
    this.onNavigateUp,
    this.onFocusActivity,
    this.nextProgramFor,
  });

  final List<LiveTvChannel> channels;

  /// Index of the channel playing now, or -1 when it is not in the list.
  final int currentIndex;

  final ValueChanged<int> onChannelSelected;

  /// What is on [channel] right now. Null — no guide for it — leaves the
  /// info line at the channel's own name, which is what an M3U without an
  /// XMLTV list looks like.
  final LiveTvProgram? Function(LiveTvChannel channel)? programFor;

  /// What follows [programFor] on the same channel. Optional: without a guide
  /// the line is simply not drawn.
  final LiveTvProgram? Function(LiveTvChannel channel)? nextProgramFor;

  /// Called when navigating UP off the strip (back to the buttons).
  final VoidCallback? onNavigateUp;

  /// Called on any focus activity, so the chrome's auto-hide timer resets.
  final VoidCallback? onFocusActivity;

  @override
  State<LiveChannelStrip> createState() => LiveChannelStripState();
}

class LiveChannelStripState extends State<LiveChannelStrip> {
  final _scrollController = ScrollController();

  /// Focus nodes by channel index. Lazily filled: a playlist of 5,000
  /// channels must not cost 5,000 focus nodes to open the strip.
  final Map<int, FocusNode> _focusNodes = {};

  int _focusedIndex = 0;

  static const _cellWidth = 148.0;
  static const _cellHeight = 96.0;

  @override
  void initState() {
    super.initState();
    _focusedIndex = widget.currentIndex < 0 ? 0 : widget.currentIndex;
  }

  @override
  void dispose() {
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  FocusNode _focusNodeFor(int index) =>
      _focusNodes.putIfAbsent(index, () => FocusNode(debugLabel: 'live_channel_$index'));

  /// Focus the channel that is playing (called when the strip appears).
  void requestInitialFocus() {
    if (widget.channels.isEmpty) return;
    final index = (widget.currentIndex < 0 ? 0 : widget.currentIndex).clamp(0, widget.channels.length - 1);
    setState(() => _focusedIndex = index);
    _scrollToIndex(index, animate: false);
    _claimFocus(index);
  }

  /// Focus the cell for [index] once the viewport has built it.
  ///
  /// A lazily-built list hands out no context for a cell that is still off
  /// screen, and `requestFocus` on a context-less node is silently dropped —
  /// so the claim is retried across the frames the scroll takes to land.
  void _claimFocus(int index, {int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _focusedIndex != index) return;
      final node = _focusNodeFor(index);
      if (node.context != null) {
        node.requestFocus();
        return;
      }
      if (attempt < 4) _claimFocus(index, attempt: attempt + 1);
    });
  }

  void _scrollToIndex(int index, {bool animate = true}) {
    if (!_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToIndex(index, animate: animate);
      });
      return;
    }
    scrollListToIndex(_scrollController, index, itemExtent: _cellWidth, leadingPadding: 12, animate: animate);
  }

  void _moveFocus(int target) {
    if (target < 0 || target >= widget.channels.length) return;
    setState(() => _focusedIndex = target);
    _scrollToIndex(target);
    _claimFocus(target);
    widget.onFocusActivity?.call();
  }

  KeyEventResult _handleKeyEvent(KeyEvent event, int index) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowLeft) {
      _moveFocus(index - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _moveFocus(index + 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      widget.onNavigateUp?.call();
      return KeyEventResult.handled;
    }
    // Consumed rather than ignored: DOWN off the strip would otherwise fall
    // through to the player surface behind it.
    if (key == LogicalKeyboardKey.arrowDown) return KeyEventResult.handled;

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.channels.isEmpty) return const SizedBox.shrink();

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        children: [
          _buildFocusedInfo(context),
          SizedBox(
            height: _cellHeight + 24,
            child: ListView.builder(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: widget.channels.length,
              itemExtent: _cellWidth,
              itemBuilder: (context, index) => _buildCell(context, index),
            ),
          ),
        ],
      ),
    );
  }

  /// Channel, what is on it, and what that is about — for the channel the
  /// cursor sits on, not the one playing. Walking the strip is how you find
  /// out what else is on.
  Widget _buildFocusedInfo(BuildContext context) {
    final index = _focusedIndex.clamp(0, widget.channels.length - 1);
    final channel = widget.channels[index];
    final program = widget.programFor?.call(channel);
    final next = widget.nextProgramFor?.call(channel);
    final theme = Theme.of(context);
    final subdued = theme.colorScheme.onSurface.withValues(alpha: 0.7);
    final faint = theme.colorScheme.onSurface.withValues(alpha: 0.5);

    final slot = program == null ? null : _timeRange(context, program);
    final facts = program == null ? const <String>[] : _programFacts(program);
    final summary = program == null ? null : _summaryWithoutFacts(program);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Column(
        crossAxisAlignment: .start,
        mainAxisSize: .min,
        children: [
          Text(
            channel.number == null ? channel.displayName : '${channel.number}  ${channel.displayName}',
            maxLines: 1,
            overflow: .ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: .w600),
          ),
          if (program != null) ...[
            const SizedBox(height: 3),
            Text(
              slot == null ? program.title : '${program.title}  ·  $slot',
              maxLines: 1,
              overflow: .ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: subdued),
            ),
            // Genre, country and year on their own line, from the guide's own
            // fields — providers also glue them to the front of the summary,
            // where they read as part of the plot.
            if (facts.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                facts.join('  ·  '),
                maxLines: 1,
                overflow: .ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: faint),
              ),
            ],
            ?_buildProgress(context, program),
            ?_buildNextLine(context, next, subdued: faint),
            if (summary != null) ...[
              const SizedBox(height: 6),
              // Half width: a line of text the width of a television is a line
              // nobody's eye returns from, and four is as much as belongs over
              // a moving picture.
              FractionallySizedBox(
                widthFactor: 0.5,
                alignment: .centerLeft,
                child: Text(
                  summary,
                  maxLines: 4,
                  overflow: .ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: subdued),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// How far the programme on air has run. The one thing a zapper wants that
  /// two clock times do not answer without arithmetic.
  Widget? _buildProgress(BuildContext context, LiveTvProgram program) {
    final begins = program.beginsAt;
    final ends = program.endsAt;
    if (begins == null || ends == null || ends <= begins) return null;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (now < begins || now > ends) return null;

    final theme = Theme.of(context);
    final elapsed = (now - begins) / (ends - begins);
    final remaining = Duration(seconds: ends - now).inMinutes;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          SizedBox(
            width: 220,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(flatRadius(context, 2)),
              child: LinearProgressIndicator(
                value: elapsed.clamp(0.0, 1.0),
                minHeight: 3,
                backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.18),
                valueColor: AlwaysStoppedAnimation(tokens(context).accent),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            t.liveTv.minutesRemaining(n: remaining),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
          ),
        ],
      ),
    );
  }

  Widget? _buildNextLine(BuildContext context, LiveTvProgram? next, {required Color subdued}) {
    if (next == null) return null;
    final begins = next.beginsAt;
    final at = begins == null
        ? null
        : TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(begins * 1000)).format(context);
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Text(
        at == null ? t.liveTv.upNext(title: next.title) : t.liveTv.upNextAt(time: at, title: next.title),
        maxLines: 1,
        overflow: .ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: subdued),
      ),
    );
  }

  /// Genre, country and year, as the guide states them in its own fields.
  static List<String> _programFacts(LiveTvProgram program) => [
    ...?program.genres?.take(2),
    ?program.country,
    if (program.year != null) '${program.year}',
  ];

  /// The summary with the facts prefix taken off the front.
  ///
  /// Providers routinely write "Tragikomödie, Deutschland 2019" ahead of the
  /// plot and without a separator, so the two run into one another. Where the
  /// same words already stand on the facts line, they are dropped here.
  static String? _summaryWithoutFacts(LiveTvProgram program) {
    final summary = program.summary?.trim();
    if (summary == null || summary.isEmpty) return null;
    final year = program.year;
    if (year == null) return summary;

    // Only a prefix, and only a short one: a plot that opens with a year of
    // its own must survive untouched.
    final marker = summary.indexOf('$year');
    if (marker < 0 || marker > 60) return summary;
    final rest = summary.substring(marker + 4).trimLeft();
    return rest.isEmpty ? summary : rest;
  }

  String? _timeRange(BuildContext context, LiveTvProgram program) {
    final begins = program.beginsAt;
    final ends = program.endsAt;
    if (begins == null || ends == null) return null;
    String at(int epochSeconds) =>
        TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000)).format(context);
    return '${at(begins)} – ${at(ends)}';
  }

  Widget _buildCell(BuildContext context, int index) {
    final channel = widget.channels[index];
    final theme = Theme.of(context);
    final tk = tokens(context);
    final isPlaying = index == widget.currentIndex;
    final focusNode = _focusNodeFor(index);
    // Under "Redesign – Glas" the tile looks as the guide's channel cells do:
    // a wash of ink rather than a fill, focus a pane of bright glass behind
    // the logo, and the channel on air a quiet pane washed with the accent in
    // place of the bar. Size and place stay what they are.
    final glass = ockerGlass(context);
    final radius = glass ? tk.radiusSm : flatRadius(context, 10);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FocusableWrapper(
        focusNode: focusNode,
        onSelect: () => widget.onChannelSelected(index),
        onKeyEvent: (_, event) => _handleKeyEvent(event, index),
        onFocusChange: (hasFocus) {
          if (!hasFocus) return;
          if (_focusedIndex != index) setState(() => _focusedIndex = index);
          widget.onFocusActivity?.call();
        },
        borderRadius: glass ? radius : 10,
        autoScroll: false,
        useBackgroundFocus: true,
        glassFocus: glass,
        semanticLabel: channel.displayName,
        // No name under the tile: the header above already carries it, and
        // where a channel has no logo [_buildLogo] sets its name in the tile
        // itself. The number stays as a small corner mark — it is how a
        // viewer knows the channel, and it is not in the logo.
        child: Container(
          decoration: BoxDecoration(
            color: glass ? tk.ink(0.06) : theme.colorScheme.surface.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(radius),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              if (glass && isPlaying)
                Positioned.fill(
                  child: IgnorePointer(
                    child: OckerGlassFocusFill(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
                      bright: false,
                      tint: 1,
                    ),
                  ),
                ),
              // Filled, not loose: a Stack leaves an unpositioned child its own
              // size and puts it in the corner, which is where the logos sat.
              Positioned.fill(
                child: Padding(padding: const EdgeInsets.fromLTRB(12, 14, 12, 12), child: _buildLogo(context, channel)),
              ),
              if (channel.number != null)
                Positioned(
                  top: 4,
                  left: 6,
                  child: Text(
                    '${channel.number}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: glass
                          ? tk.ink(isPlaying ? 0.75 : 0.45)
                          : theme.colorScheme.onSurface.withValues(alpha: isPlaying ? 0.75 : 0.45),
                      fontWeight: isPlaying ? FontWeight.w600 : null,
                    ),
                  ),
                ),
              // A bar along the bottom for the channel on air, so it reads
              // apart from the focus ring rather than competing with it.
              if (isPlaying && !glass)
                Positioned(left: 0, right: 0, bottom: 0, child: Container(height: 3, color: tokens(context).accent)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogo(BuildContext context, LiveTvChannel channel) {
    final fallback = Center(
      child: Text(
        channel.displayName,
        maxLines: 2,
        textAlign: .center,
        overflow: .ellipsis,
        style: ockerGlass(context)
            ? Theme.of(context).textTheme.labelSmall?.copyWith(color: tokens(context).ink(0.85))
            : Theme.of(context).textTheme.labelSmall,
      ),
    );

    return LiveTvChannelLogo(
      channel: channel,
      // An IPTV logo is a full address and needs no server; a server-relative
      // one cannot be built without its client.
      client: context.tryGetMediaClientForServer(serverIdOrNull(channel.serverId)),
      logoToneTarget: channelLogoToneTargetFor(
        surface: Theme.of(context).colorScheme.surface,
        foreground: Theme.of(context).colorScheme.onSurface,
      ),
      fallback: (_) => fallback,
    );
  }
}
