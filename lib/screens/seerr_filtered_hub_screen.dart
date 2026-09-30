import 'package:flutter/material.dart';

import '../media/library_query.dart';
import '../media/media_hub.dart';
import '../media/media_item.dart';
import '../services/catalog/seerr_shelves.dart';
import '../widgets/focusable_tab_chip.dart';
import 'hub_detail_screen.dart';

/// One tab of a filtered Seerr list: a label and the titles behind it.
///
/// [load] serves one page at a time — a genre or a network runs to thousands
/// of titles, far past what is worth pulling down before the page can be
/// shown.
class SeerrFilterTab {
  final String id;
  final String label;
  final Future<LibraryPage<MediaItem>> Function(int start, int size) load;

  const SeerrFilterTab({required this.id, required this.label, required this.load});
}

/// Everything a studio, network or genre has, as one grid with a tab per kind.
///
/// This is what the top row of a shelf page opens: the shelves below it each
/// answer one question ("popular", "new"), and this answers none — it is the
/// whole list, which is the thing to reach for when the shelves did not have
/// it.
///
/// The tabs sit where the title does, the way the watchlist puts its source
/// switcher there — on TV that is the one spot the D-pad can reach from the
/// app bar.
class SeerrFilteredHubScreen extends StatefulWidget {
  final String title;

  /// Identifies the list, so the two tabs of one genre do not share a grid.
  final String hubKey;
  final List<SeerrFilterTab> tabs;

  const SeerrFilteredHubScreen({super.key, required this.title, required this.hubKey, required this.tabs});

  @override
  State<SeerrFilteredHubScreen> createState() => _SeerrFilteredHubScreenState();
}

class _SeerrFilteredHubScreenState extends State<SeerrFilteredHubScreen> {
  /// One key per tab: switching tabs builds a new grid, which loads the titles
  /// of the tab it was built for.
  final Map<String, GlobalKey<HubDetailScreenState>> _gridKeys = {};
  final List<FocusNode> _chipNodes = [];
  int _index = 0;

  @override
  void dispose() {
    for (final node in _chipNodes) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _chipNode(int index) {
    while (_chipNodes.length <= index) {
      _chipNodes.add(FocusNode(debugLabel: 'seerr_filter_chip_${_chipNodes.length}'));
    }
    return _chipNodes[index];
  }

  void _select(int index) {
    if (index == _index) return;
    setState(() => _index = index);
  }

  Widget? _buildTabStrip() {
    if (widget.tabs.length < 2) return null;
    return TabChipStrip(
      children: [
        for (var i = 0; i < widget.tabs.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          FocusableTabChip(
            label: widget.tabs[i].label,
            isSelected: i == _index,
            focusNode: _chipNode(i),
            onSelect: () => _select(i),
            onNavigateLeft: i > 0 ? () => _chipNode(i - 1).requestFocus() : null,
            // Past the last tab lie the page's own actions.
            onNavigateRight: i < widget.tabs.length - 1
                ? () => _chipNode(i + 1).requestFocus()
                : () => _gridKeys[widget.tabs[_index].id]?.currentState?.focusAppBarFromHost(),
            onNavigateDown: () => _gridKeys[widget.tabs[i].id]?.currentState?.focusFromHostTab(),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tab = widget.tabs[_index];
    final key = _gridKeys.putIfAbsent(tab.id, GlobalKey<HubDetailScreenState>.new);
    final strip = _buildTabStrip();

    return HubDetailScreen(
      key: key,
      // `more` is what makes the grid fetch its first page: it starts from the
      // hub's own items, and this hub deliberately carries none — everything
      // comes from the paged loader.
      hub: MediaHub(
        id: '${widget.hubKey}:${tab.id}',
        title: widget.title,
        type: tab.id,
        items: const [],
        size: 0,
        more: true,
      ),
      loadPage: tab.load,
      pageSize: seerrPageSize,
      // Not embedded: this screen *is* the route. The flag means "hosted
      // inside another screen", and setting it because there are tabs took the
      // pop away — back then tried to reach a sidebar that is not above a
      // pushed route, and the page could not be left at all.
      titleOverride: strip,
      onAppBarNavigateLeft: strip == null ? null : () => _chipNode(_index).requestFocus(),
    );
  }
}
