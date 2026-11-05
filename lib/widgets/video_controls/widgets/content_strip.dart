import 'dart:async' show Stream, unawaited;
import '../../../media/ids.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../focus/card_focus_scope.dart';
import '../../../focus/dpad_navigator.dart';
import '../../../focus/focusable_wrapper.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/media_item.dart';
import '../../../media/media_item_labels.dart';
import '../../../media/media_item_types.dart';
import '../../../media/media_server_client.dart';
import '../../../mpv/mpv.dart';
import '../../../media/media_source_info.dart';
import '../../../providers/playback_state_provider.dart';
import '../../../redesign/ocker_skin.dart';
import '../../../redesign/ocker_type.dart';
import '../../../focus/focus_theme.dart';
import '../../detail_resume_progress.dart';
import '../../../services/settings_service.dart';
import '../../../services/download_storage_service.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/formatters.dart';
import '../../../utils/player_utils.dart';
import '../../../utils/provider_extensions.dart';
import '../../../utils/scroll_utils.dart';
import '../../app_icon.dart';
import '../../clickable_cursor.dart';
import '../../optimized_media_image.dart';
import '../../settings_builder.dart';
import 'media_selector_thumbnail.dart';

/// Horizontal scrollable strip of chapter/queue items shown on swipe-up.
class ContentStrip extends StatefulWidget {
  final Player player;
  final List<MediaChapter> chapters;
  final bool canControl;
  final String? serverId;
  final bool showQueueTab;
  final Function(MediaItem)? onQueueItemSelected;
  final Future<void> Function(Duration position)? onSeekRequested;
  final Function(Duration position)? onSeekCompleted;

  /// Whether to use dpad/focus-based navigation (TV mode).
  /// When true, no tab bar is shown — pages are navigated via UP/DOWN.
  final bool useFocusNavigation;

  /// Called when navigating UP from the top-most strip page (back to buttons).
  final VoidCallback? onNavigateUp;

  /// Called on any focus activity (to reset auto-hide timer).
  final VoidCallback? onFocusActivity;

  /// Plebz: the strip as a row of the start page — on the television's
  /// player under the redesign. No pane: a heading at the left naming the
  /// page (and the other one, dimmed, where there are both), 16:9 pictures
  /// at the size of the start page's wide tiles, focus as a poster's (ring
  /// and growth), the one playing marked on its picture with its progress.
  final bool rowLook;

  const ContentStrip({
    super.key,
    required this.player,
    required this.chapters,
    required this.canControl,
    this.serverId,
    this.showQueueTab = false,
    this.onQueueItemSelected,
    this.onSeekRequested,
    this.onSeekCompleted,
    this.useFocusNavigation = false,
    this.onNavigateUp,
    this.onFocusActivity,
    this.rowLook = false,
  });

  /// [rowLook]'s picture width and the gap after it, at the 1920 reference.
  static const double rowThumbWidth = 336;
  static const double rowGap = 24;

  @override
  State<ContentStrip> createState() => ContentStripState();
}

enum _StripTab { chapters, queue }

class ContentStripState extends State<ContentStrip> {
  late _StripTab _activeTab;
  final ScrollController _chapterScrollController = ScrollController();
  final ScrollController _queueScrollController = ScrollController();
  final Map<_StripTab, Object?> _lastAutoScrolled = {};
  final Map<int, GlobalKey> _chapterItemKeys = {};
  final Map<int, GlobalKey> _queueItemKeys = {};
  late Stream<int?> _chapterIndexStream;

  // Focus nodes for focus navigation mode
  final List<FocusNode> _chapterFocusNodes = [];
  final List<FocusNode> _queueFocusNodes = [];

  bool get _hasChapters => widget.chapters.isNotEmpty;
  bool get _hasQueue => widget.showQueueTab && widget.onQueueItemSelected != null;
  bool get _hasBothTabs => _hasChapters && _hasQueue;

  @override
  void initState() {
    super.initState();
    _activeTab = _hasChapters ? _StripTab.chapters : _StripTab.queue;
    _bindChapterIndexStream();
  }

  @override
  void didUpdateWidget(ContentStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.player, widget.player) || !identical(oldWidget.chapters, widget.chapters)) {
      _bindChapterIndexStream();
    }
    _normalizeActiveTab();
  }

  void _normalizeActiveTab() {
    if (_activeTab == _StripTab.chapters && !_hasChapters && _hasQueue) {
      _activeTab = _StripTab.queue;
      _lastAutoScrolled.remove(_StripTab.queue);
    } else if (_activeTab == _StripTab.queue && !_hasQueue && _hasChapters) {
      _activeTab = _StripTab.chapters;
      _lastAutoScrolled.remove(_StripTab.chapters);
    }
  }

  void _bindChapterIndexStream() {
    if (!_hasChapters) {
      _chapterIndexStream = const Stream<int?>.empty();
      return;
    }

    _chapterIndexStream = widget.player.streams.position
        .map((position) => MediaChapter.indexAtPosition(position, widget.chapters))
        .distinct();
  }

  @override
  void dispose() {
    _chapterScrollController.dispose();
    _queueScrollController.dispose();
    for (final node in _chapterFocusNodes) {
      node.dispose();
    }
    for (final node in _queueFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  /// Request focus on the current chapter or queue item (called by parent when strip appears).
  void requestInitialFocus() {
    if (_activeTab == _StripTab.chapters && _chapterFocusNodes.isNotEmpty) {
      final currentIndex = MediaChapter.indexAtPosition(widget.player.state.position, widget.chapters);
      final idx = (currentIndex ?? 0).clamp(0, _chapterFocusNodes.length - 1);
      _chapterFocusNodes[idx].requestFocus();
      _scrollToFocusedNode(_chapterFocusNodes[idx]);
    } else if (_activeTab == _StripTab.queue && _queueFocusNodes.isNotEmpty) {
      final currentIndex = _getCurrentQueueIndex();
      final idx = (currentIndex ?? 0).clamp(0, _queueFocusNodes.length - 1);
      _queueFocusNodes[idx].requestFocus();
      _scrollToFocusedNode(_queueFocusNodes[idx]);
    }
  }

  Future<void> _handleChapterTap(Duration position) async {
    if (!widget.canControl) return;
    final clamped = clampSeekPosition(widget.player, position);
    await (widget.onSeekRequested ?? widget.player.seek)(clamped);
    if (mounted) {
      widget.onSeekCompleted?.call(clamped);
    }
  }

  int? _getCurrentQueueIndex() {
    try {
      final playbackState = context.read<PlaybackStateProvider>();
      final items = playbackState.loadedItems;
      final currentItemID = playbackState.currentPlayQueueItemID;
      final idx = items.indexWhere((item) => playbackState.playQueueItemIdFor(item) == currentItemID);
      return idx >= 0 ? idx : null;
    } catch (_) {
      return null;
    }
  }

  void _ensureFocusNodes(List<FocusNode> nodes, int count, String prefix) {
    while (nodes.length < count) {
      nodes.add(FocusNode(debugLabel: '$prefix${nodes.length}'));
    }
    while (nodes.length > count) {
      nodes.removeLast().dispose();
    }
  }

  void _scrollToFocusedNode(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = node.context;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  void _selectTab(_StripTab tab) {
    setState(() {
      _activeTab = tab;
      _lastAutoScrolled.remove(tab);
    });
  }

  KeyEventResult _handleFocusItemKeyEvent(KeyEvent event, int index, int totalItems, _StripTab page) {
    if (!event.isActionable) return KeyEventResult.ignored;

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {
      final nodes = page == _StripTab.chapters ? _chapterFocusNodes : _queueFocusNodes;
      final target = index + (key == LogicalKeyboardKey.arrowLeft ? -1 : 1);
      if (target >= 0 && target < totalItems) {
        nodes[target].requestFocus();
        _scrollToFocusedNode(nodes[target]);
        widget.onFocusActivity?.call();
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      if (page == _StripTab.queue && _hasChapters) {
        // Switch to chapters page and focus current chapter
        setState(() {
          _activeTab = _StripTab.chapters;
          _lastAutoScrolled.remove(_StripTab.chapters);
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _chapterFocusNodes.isNotEmpty) {
            final currentIndex = MediaChapter.indexAtPosition(widget.player.state.position, widget.chapters);
            final idx = (currentIndex ?? 0).clamp(0, _chapterFocusNodes.length - 1);
            _chapterFocusNodes[idx].requestFocus();
            _scrollToFocusedNode(_chapterFocusNodes[idx]);
          }
        });
        widget.onFocusActivity?.call();
      } else {
        // chapters page (or queue without chapters) → go back to buttons
        widget.onNavigateUp?.call();
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      if (page == _StripTab.chapters && _hasQueue) {
        // Switch to queue page and focus current queue item
        setState(() {
          _activeTab = _StripTab.queue;
          _lastAutoScrolled.remove(_StripTab.queue);
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _queueFocusNodes.isNotEmpty) {
            final idx = (_getCurrentQueueIndex() ?? 0).clamp(0, _queueFocusNodes.length - 1);
            _queueFocusNodes[idx].requestFocus();
            _scrollToFocusedNode(_queueFocusNodes[idx]);
          }
        });
        widget.onFocusActivity?.call();
      }
      // On queue page or chapters-only, consume to prevent bubbling
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  MediaServerClient? _tryGetClient(BuildContext context, ServerId? serverId) {
    return context.tryGetMediaClientForServer(serverId);
  }

  double _itemWidth(bool isTablet) => widget.rowLook
      ? (ContentStrip.rowThumbWidth + ContentStrip.rowGap) * ockerScale(context)
      : isTablet
      ? 212.0
      : 132.0; // thumb + 12 padding

  GlobalKey _itemKeyFor(Map<int, GlobalKey> keys, int index) {
    return keys.putIfAbsent(index, GlobalKey.new);
  }

  void _trimItemKeys(Map<int, GlobalKey> keys, int count) {
    keys.removeWhere((index, _) => index >= count);
  }

  void _autoScrollTo(
    ScrollController controller,
    Map<int, GlobalKey> keys,
    int index, {
    required bool isTablet,
    required bool Function() isCurrent,
    int attempt = 0,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !isCurrent()) return;

      if (controller.positions.length != 1 || !controller.position.hasContentDimensions) {
        if (attempt < 3) {
          _autoScrollTo(controller, keys, index, isTablet: isTablet, isCurrent: isCurrent, attempt: attempt + 1);
        }
        return;
      }

      scrollListToIndex(
        controller,
        index,
        itemExtent: _itemWidth(isTablet),
        leadingPadding: widget.rowLook ? 0 : (widget.useFocusNavigation ? 12 : 4),
        animate: false,
      );
      scrollKeyedChildToHorizontalCenter(
        controller,
        _itemKeyFor(keys, index),
        animate: false,
        maxAttempts: 4,
        isCurrent: isCurrent,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasChapters && !_hasQueue) return const SizedBox.shrink();
    if (widget.rowLook) return _buildRowLook(context);

    final isTablet = MediaQuery.sizeOf(context).shortestSide >= 600;
    final stripHeight = isTablet ? 170.0 : 106.0;
    // Add extra height for focus decoration when in focus navigation mode
    final effectiveStripHeight = widget.useFocusNavigation ? stripHeight + 16.0 : stripHeight;

    return SafeArea(
      top: false,
      child: Padding(
        padding: .symmetric(horizontal: widget.useFocusNavigation ? 0 : 16),
        child: Column(
          mainAxisSize: .min,
          children: [
            // Tab bar only shown in touch mode when both tabs exist
            if (_hasBothTabs && !widget.useFocusNavigation) _buildTabBar(),
            // In focus mode, show a small label for the current page
            if (widget.useFocusNavigation)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  _activeTab == _StripTab.chapters ? t.videoControls.chapters : t.videoControls.queue,
                  style: TextStyle(
                    color: ockerGlass(context) ? tokens(context).ink(0.72) : Colors.white70,
                    fontSize: 12,
                    fontWeight: .w500,
                  ),
                ),
              ),
            if (!widget.useFocusNavigation) const SizedBox(height: 8),
            SizedBox(
              height: effectiveStripHeight,
              child: _activeTab == _StripTab.chapters ? _buildChapterStrip(isTablet) : _buildQueueStrip(isTablet),
            ),
          ],
        ),
      ),
    );
  }

  /// [ContentStrip.rowLook]: the heading at the left, the row under it, both
  /// at the left edge the parent gives; the row runs on off the right edge.
  Widget _buildRowLook(BuildContext context) {
    final scale = ockerScale(context);
    final type = OckerType.of(context);
    final heading = type.sectionHeading.copyWith(color: Colors.white);
    final thumbHeight = ContentStrip.rowThumbWidth * scale * 9 / 16;
    // Picture, the words under it, and room above and below for the ring
    // and the growth of a focused tile.
    final rowHeight = thumbHeight + _RowStripItem.wordsHeight(scale) + 2 * _RowStripItem.focusRoom;

    Widget page(_StripTab tab) {
      final label = tab == _StripTab.chapters ? t.videoControls.chapters : t.videoControls.queue;
      final active = _activeTab == tab;
      return Text(
        label,
        key: ValueKey('strip_heading_${tab.name}'),
        style: active ? heading : heading.copyWith(color: Colors.white38),
      );
    }

    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      children: [
        // The page on show first; the other, dimmed, says Up or Down leads
        // there — the remote's way between them.
        Row(
          children: [
            page(_activeTab),
            if (_hasBothTabs) ...[
              SizedBox(width: 24 * scale),
              page(_activeTab == _StripTab.chapters ? _StripTab.queue : _StripTab.chapters),
            ],
          ],
        ),
        SizedBox(height: 12 * scale),
        SizedBox(
          height: rowHeight,
          child: _activeTab == _StripTab.chapters ? _buildChapterStrip(false) : _buildQueueStrip(false),
        ),
      ],
    );
  }

  /// Under a picture of [ContentStrip.rowLook]: season and episode, or the
  /// year, then the length.
  String _rowFacts(MediaItem item) {
    final parts = <String>[
      if (item.parentIndex != null && item.index != null) ...[
        'S${item.parentIndex}',
        'E${item.index}',
      ] else if (item.year != null)
        '${item.year}',
      if (item.durationMs != null && item.durationMs! > 0) formatDurationTextual(item.durationMs!),
    ];
    return parts.isEmpty ? (item.grandparentTitle ?? '') : toBulletedString(parts);
  }

  Widget _buildTabBar() {
    return Row(
      mainAxisAlignment: .center,
      children: [
        _buildTabLabel(t.videoControls.chapters, _StripTab.chapters),
        const SizedBox(width: 24),
        _buildTabLabel(t.videoControls.queue, _StripTab.queue),
      ],
    );
  }

  Widget _buildTabLabel(String label, _StripTab tab) {
    final isActive = _activeTab == tab;
    return ClickableCursor(
      child: GestureDetector(
        onTap: () => _selectTab(tab),
        child: Column(
          mainAxisSize: .min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white54,
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            const SizedBox(height: 4),
            Container(height: 2, width: 40, color: isActive ? Colors.white : Colors.transparent),
          ],
        ),
      ),
    );
  }

  /// Horizontal list of strip items: auto-scrolls to [autoScrollIndex] whenever
  /// [autoScrollToken] changes, and wraps items for focus navigation.
  Widget _buildStrip({
    required _StripTab tab,
    required ScrollController controller,
    required Map<int, GlobalKey> keys,
    required List<FocusNode> nodes,
    required String focusPrefix,
    required int itemCount,
    required bool isTablet,
    required int? autoScrollIndex,
    required Object? autoScrollToken,
    required (Widget, VoidCallback?) Function(BuildContext context, int index, Key key) itemBuilder,
  }) {
    _trimItemKeys(keys, itemCount);

    if (autoScrollIndex != null && _lastAutoScrolled[tab] != autoScrollToken) {
      _lastAutoScrolled[tab] = autoScrollToken;
      _autoScrollTo(
        controller,
        keys,
        autoScrollIndex,
        isTablet: isTablet,
        isCurrent: () => _lastAutoScrolled[tab] == autoScrollToken,
      );
    }

    if (widget.useFocusNavigation) {
      _ensureFocusNodes(nodes, itemCount, focusPrefix);
    }

    return ListView.builder(
      controller: controller,
      scrollDirection: Axis.horizontal,
      clipBehavior: widget.useFocusNavigation ? Clip.none : Clip.hardEdge,
      itemCount: itemCount,
      padding: widget.rowLook ? EdgeInsets.zero : .symmetric(horizontal: widget.useFocusNavigation ? 12 : 4),
      itemBuilder: (context, index) {
        final (item, onTap) = itemBuilder(context, index, _itemKeyFor(keys, index));

        if (!widget.useFocusNavigation) return item;

        return Align(
          alignment: .topCenter,
          child: FocusableWrapper(
            focusNode: nodes[index],
            onSelect: onTap,
            onKeyEvent: (_, event) => _handleFocusItemKeyEvent(event, index, itemCount, tab),
            onFocusChange: (hasFocus) {
              if (hasFocus) widget.onFocusActivity?.call();
            },
            borderRadius: widget.rowLook ? artworkRadius(context) : 6,
            autoScroll: false,
            // Plebz: a row's picture takes focus as a poster does — the ring
            // round the picture, the tile grown — rather than a pane.
            useBackgroundFocus: !widget.rowLook,
            focusScale: widget.rowLook ? FocusTheme.posterFocusScaleFor(context) : FocusTheme.focusScale,
            // Under glass the item draws its own marks, focus and the one
            // playing in one pane ([_GlassStripMarks]), as a menu row does.
            delegateFocusBorder: widget.rowLook || ockerGlass(context),
            child: item,
          ),
        );
      },
    );
  }

  Widget _buildChapterStrip(bool isTablet) {
    return StreamBuilder<int?>(
      stream: _chapterIndexStream,
      initialData: MediaChapter.indexAtPosition(widget.player.state.position, widget.chapters),
      builder: (context, chapterSnapshot) {
        final currentChapterIndex = chapterSnapshot.data;

        return _buildStrip(
          tab: _StripTab.chapters,
          controller: _chapterScrollController,
          keys: _chapterItemKeys,
          nodes: _chapterFocusNodes,
          focusPrefix: 'ChapterFocus',
          itemCount: widget.chapters.length,
          isTablet: isTablet,
          autoScrollIndex: currentChapterIndex,
          autoScrollToken: currentChapterIndex,
          itemBuilder: (context, index, itemKey) {
            final chapter = widget.chapters[index];

            final localThumbPath = widget.serverId != null && chapter.thumb != null
                ? DownloadStorageService.instance.getArtworkPathSync(ServerId(widget.serverId!), chapter.thumb!)
                : null;

            final VoidCallback? onTap = widget.canControl
                ? () => unawaited(_handleChapterTap(chapter.startTime))
                : null;

            return (
              _buildStripItem(
                key: itemKey,
                isCurrent: currentChapterIndex == index,
                isTablet: isTablet,
                thumbnail: chapter.thumb != null
                    ? _buildStripThumbnail(
                        client: _tryGetClient(context, serverIdOrNull(widget.serverId)),
                        imagePath: chapter.thumb,
                        localFilePath: localThumbPath,
                        isTablet: isTablet,
                      )
                    : null,
                title: chapter.label,
                subtitle: formatDurationTimestamp(chapter.startTime),
                onTap: onTap,
              ),
              onTap,
            );
          },
        );
      },
    );
  }

  Widget _buildQueueStrip(bool isTablet) {
    return SettingValueBuilder<bool>(
      pref: SettingsService.hideSpoilers,
      builder: (context, hideSpoilers, _) => Consumer<PlaybackStateProvider>(
        builder: (context, playbackState, _) {
          final items = playbackState.loadedItems;
          final currentItemID = playbackState.currentPlayQueueItemID;
          final currentIndex = currentItemID == null
              ? -1
              : items.indexWhere((item) => playbackState.playQueueItemIdFor(item) == currentItemID);

          return _buildStrip(
            tab: _StripTab.queue,
            controller: _queueScrollController,
            keys: _queueItemKeys,
            nodes: _queueFocusNodes,
            focusPrefix: 'QueueFocus',
            itemCount: items.length,
            isTablet: isTablet,
            autoScrollIndex: currentIndex >= 0 ? currentIndex : null,
            autoScrollToken: (currentItemID, currentIndex),
            itemBuilder: (context, index, itemKey) {
              final item = items[index];

              final client = item.serverId != null
                  ? context.tryGetMediaClientForServer(serverIdOrNull(item.serverId))
                  : null;

              void onTap() => widget.onQueueItemSelected?.call(item);

              return (
                _buildStripItem(
                  key: itemKey,
                  isCurrent: playbackState.playQueueItemIdFor(item) == currentItemID,
                  isTablet: isTablet,
                  thumbnail: item.thumbPath != null
                      ? _buildStripThumbnail(client: client, imagePath: item.thumbPath, isTablet: isTablet)
                      : null,
                  blurThumbnail: hideSpoilers && item.shouldHideSpoiler,
                  title: item.title ?? '',
                  subtitle: widget.rowLook ? _rowFacts(item) : formatQueueItemSubtitle(item),
                  onTap: onTap,
                  progress: item.hasActiveProgress ? DetailResumeProgress.fractionOf(item) : null,
                  livePlayer: widget.player,
                ),
                onTap,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildStripThumbnail({
    required MediaServerClient? client,
    required String? imagePath,
    required bool isTablet,
    String? localFilePath,
  }) {
    final rowWidth = widget.rowLook ? ContentStrip.rowThumbWidth * ockerScale(context) : null;
    return OptimizedMediaImage.thumb(
      client: client,
      imagePath: imagePath,
      localFilePath: localFilePath,
      width: rowWidth ?? (isTablet ? 200.0 : 120.0),
      height: rowWidth != null ? rowWidth * 9 / 16 : (isTablet ? 112.0 : 68.0),
      fit: BoxFit.cover,
      errorWidget: (_, _, _) => const AppIcon(Symbols.image_rounded, fill: 1, color: Colors.white54, size: 34),
    );
  }

  Widget _buildStripItem({
    Key? key,
    required bool isCurrent,
    required Widget? thumbnail,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    bool blurThumbnail = false,
    bool isTablet = false,
    double? progress,
    Player? livePlayer,
  }) {
    if (widget.rowLook) {
      return ClickableCursor(
        child: GestureDetector(
          onTap: onTap,
          child: _RowStripItem(
            key: key,
            current: isCurrent,
            thumbnail: thumbnail,
            blurThumbnail: blurThumbnail,
            title: title,
            subtitle: subtitle,
            progress: progress,
            player: isCurrent ? livePlayer : null,
          ),
        ),
      );
    }
    final itemWidth = isTablet ? 200.0 : 120.0;
    final thumbHeight = isTablet ? 112.0 : 68.0;
    final titleFontSize = isTablet ? 13.0 : 11.0;
    final subtitleFontSize = isTablet ? 12.0 : 10.0;

    final verticalMargin = widget.useFocusNavigation ? 4.0 : 0.0;
    // Under "Redesign – Glas" the item looks as a glass menu row does: the
    // one playing a quiet pane washed with the accent in place of the white
    // frame, focus a pane of bright glass, and the words in the theme's ink.
    // Sizes and places stay what they are.
    final glass = ockerGlass(context);
    final tk = tokens(context);
    const thumbRadius = 6.0;
    const horizontalMargin = 6.0;
    Widget result = Container(
      key: key,
      width: itemWidth,
      margin: .symmetric(horizontal: horizontalMargin, vertical: verticalMargin),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        children: [
          MediaSelectorThumbnail(
            width: itemWidth,
            height: thumbHeight,
            thumbnail: thumbnail,
            isCurrent: isCurrent && !glass,
            borderColor: Colors.white,
            radius: thumbRadius,
            blurThumbnail: blurThumbnail,
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              color: glass ? tk.text : Colors.white,
              fontSize: titleFontSize,
              fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
            ),
            maxLines: 1,
            overflow: .ellipsis,
          ),
          Text(
            subtitle,
            style: TextStyle(
              color: glass ? tk.ink(isCurrent ? 0.72 : 0.6) : (isCurrent ? Colors.white70 : Colors.white60),
              fontSize: subtitleFontSize,
              fontWeight: isCurrent ? FontWeight.w500 : FontWeight.normal,
            ),
            maxLines: 1,
            overflow: .ellipsis,
          ),
        ],
      ),
    );
    if (glass) {
      result = Stack(
        children: [
          Positioned.fill(
            // Round the item's margin, concentric with the thumbnail's corner.
            child: _GlassStripMarks(current: isCurrent, radius: thumbRadius + horizontalMargin),
          ),
          _FlatStripInk(child: result),
        ],
      );
    }
    return ClickableCursor(
      child: GestureDetector(onTap: onTap, child: result),
    );
  }
}

/// Over [_GlassStripMarks]' bright pane under "Flach" (Plebz): the pane is
/// white there, so the item's words go dark while it has focus — they stood
/// white on white in the player's queue (the viewer's report). The picture
/// keeps its colours ([OptimizedMediaImage] does that for itself).
class _FlatStripInk extends StatelessWidget {
  const _FlatStripInk({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      OckerFlatFocusInk(invert: CardFocusScope.maybeOf(context) ?? false, child: child);
}

/// Behind a strip item under glass: one pane that is bright while the item
/// has focus and washed with the accent while it is the one playing, and
/// nothing when it is neither.
class _GlassStripMarks extends StatelessWidget {
  const _GlassStripMarks({required this.current, required this.radius});

  final bool current;
  final double radius;

  @override
  Widget build(BuildContext context) {
    // Null in touch mode, where no focus wrapper stands above the item.
    final focused = CardFocusScope.maybeOf(context) ?? false;
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: focused || current ? 1 : 0,
        duration: ockerInkFade(context),
        curve: Curves.easeOutCubic,
        child: OckerGlassFocusFill(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
          bright: focused,
          tint: current ? 1 : 0,
        ),
      ),
    );
  }
}

/// One tile of [ContentStrip.rowLook] (Plebz): a 16:9 picture with the
/// start page's corner, a ring round it while focused, the one playing
/// marked on it with the accent and its progress, the words under it.
class _RowStripItem extends StatelessWidget {
  const _RowStripItem({
    super.key,
    required this.current,
    required this.thumbnail,
    required this.blurThumbnail,
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.player,
  });

  final bool current;
  final Widget? thumbnail;
  final bool blurThumbnail;
  final String title;
  final String subtitle;

  /// How far in the viewer is, 0 to 1; null for none.
  final double? progress;

  /// The player, for the item playing now: its bar follows the playhead.
  final Player? player;

  /// Room round the picture for the ring and the growth of a focused tile.
  static const double focusRoom = 10;

  static const double _titleSize = 22;
  static const double _factsSize = 18;

  /// The two lines under the picture and the gap above them.
  static double wordsHeight(double scale) => (10 + _titleSize * 1.25 + 2 + _factsSize * 1.25) * scale;

  @override
  Widget build(BuildContext context) {
    final scale = ockerScale(context);
    final type = OckerType.of(context);
    final tk = tokens(context);
    final width = ContentStrip.rowThumbWidth * scale;
    final radius = artworkRadius(context);
    final accent = tk.accent;
    final onAccent = ThemeData.estimateBrightnessForColor(accent) == Brightness.dark ? Colors.white : tk.bg;

    Widget bar(double share) => Positioned(
      left: 10 * scale,
      right: 10 * scale,
      bottom: 10 * scale,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3 * scale),
        child: SizedBox(
          height: 6 * scale,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.white30),
              FractionallySizedBox(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: share.clamp(0.0, 1.0),
                child: const ColoredBox(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );

    final livePlayer = player;
    final picture = Stack(
      fit: StackFit.expand,
      children: [
        MediaSelectorThumbnail(
          width: width,
          height: width * 9 / 16,
          thumbnail: thumbnail,
          isCurrent: false,
          borderColor: Colors.white,
          radius: radius,
          blurThumbnail: blurThumbnail,
        ),
        if (current)
          PositionedDirectional(
            start: 10 * scale,
            top: 10 * scale,
            child: OckerKeepColours(
              child: DecoratedBox(
                key: const ValueKey('strip_playing_chip'),
                decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(6 * scale)),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 4 * scale),
                  child: Text(
                    t.videoControls.playingNow,
                    style: type.nowChip.copyWith(color: onAccent, fontSize: _factsSize * scale),
                  ),
                ),
              ),
            ),
          ),
        if (livePlayer != null)
          StreamBuilder<Duration>(
            stream: livePlayer.streams.position,
            initialData: livePlayer.state.position,
            builder: (context, snapshot) {
              final duration = livePlayer.state.duration.inMilliseconds;
              if (duration <= 0) return const SizedBox.shrink();
              return Stack(fit: StackFit.expand, children: [bar((snapshot.data?.inMilliseconds ?? 0) / duration)]);
            },
          )
        else if (progress != null)
          bar(progress!),
      ],
    );

    return Padding(
      padding: EdgeInsetsDirectional.only(top: focusRoom, end: ContentStrip.rowGap * scale),
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: [
            CardFocusBorder(
              borderRadius: radius,
              child: SizedBox(width: width, height: width * 9 / 16, child: picture),
            ),
            SizedBox(height: 10 * scale),
            Text(
              title,
              maxLines: 1,
              overflow: .ellipsis,
              style: type.metadata.copyWith(
                color: Colors.white,
                fontSize: _titleSize * scale,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
            SizedBox(height: 2 * scale),
            Text(
              subtitle,
              maxLines: 1,
              overflow: .ellipsis,
              style: type.metadata.copyWith(color: Colors.white60, fontSize: _factsSize * scale, height: 1.25),
            ),
          ],
        ),
      ),
    );
  }
}
