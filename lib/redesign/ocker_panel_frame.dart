import 'package:flutter/material.dart';

import '../services/settings_service.dart';
import '../widgets/settings_builder.dart';
import 'ocker_detail_panel.dart';
import 'ocker_focus_bus.dart';
import 'ocker_skin.dart';

/// A screen's own content, and the detail panel down the right beside it:
/// the rail holds the left edge, and a panel beside it stacked two columns of
/// chrome against each other before the first poster.
///
/// For screens that already own their scrolling — a library's virtualised grid
/// with its paging, its alphabet bar and its measured geometry. Replacing that
/// with a plain list would cost every one of those; this leaves it alone and
/// only gives it the panel and the ground it sits on.
///
/// The bus lives here, so whatever [child] draws can report the focused title
/// through [OckerFocusScope] without knowing what is showing it.
class OckerPanelFrame extends StatefulWidget {
  final OckerClientResolver resolveClient;
  final Widget child;

  /// Drawn over the content's top left, at its own width, bringing its own
  /// gap below: the views are rows in the rail, and what is left — the
  /// filters — belongs over the posters it narrows. Null when the screen has
  /// none.
  final Widget? header;

  /// Whether the describing panel is drawn at all.
  ///
  /// False on a tab whose content is *rows*: a shelf runs off the right edge
  /// to say there is more, and a column there would cut it short. A grid ends
  /// and keeps the panel.
  final bool showPanel;

  const OckerPanelFrame({
    super.key,
    required this.resolveClient,
    required this.child,
    this.header,
    this.showPanel = true,
  });

  @override
  State<OckerPanelFrame> createState() => _OckerPanelFrameState();
}

class _OckerPanelFrameState extends State<OckerPanelFrame> {
  final _bus = OckerFocusBus();

  @override
  void dispose() {
    _bus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SettingValueBuilder<bool>(
    pref: SettingsService.glasDetailPanel,
    builder: (context, panelWanted, _) => _build(context, showPanel: widget.showPanel && panelWanted),
  );

  /// [showPanel]: whether this screen has a panel and the viewer wants it —
  /// without one the grid takes the width, in more posters
  /// ([ockerGridColumnsFor]).
  Widget _build(BuildContext context, {required bool showPanel}) {
    final scale = ockerScale(context);
    // The watchlist's panel, to the pixel — see [ockerGridPanelWidth] — so the
    // two columns are one width and the grid beside either does not move.
    final columnWidth = ockerGridPanelWidth(context);
    final content = Column(
      crossAxisAlignment: .start,
      children: [
        ?widget.header,
        Expanded(child: widget.child),
      ],
    );
    return OckerFocusScope(
      bus: _bus,
      // No fill of its own: the frame sits on the shell's glass ground, which
      // a flat fill here covered.
      child: Padding(
        // The same margins as the watchlist, down to the pixel: this frame
        // holds a grid too, and a grid handed more width answers with bigger
        // posters. The narrow inset goes where the content meets the rail,
        // the design's margin to the far edge.
        // The panel runs on through the right margin to the screen's edge.
        padding: EdgeInsets.fromLTRB(
          ockerFlushLeftInset(context),
          ockerContentTop(context),
          showPanel ? 0 : OckerLayout.safeMargin * scale,
          0,
        ),
        child: showPanel
            ? Row(
                crossAxisAlignment: .start,
                children: [
                  Expanded(child: content),
                  SizedBox(width: OckerLayout.rowGutter * scale),
                  SizedBox(
                    width: columnWidth + OckerLayout.safeMargin * scale,
                    child: OckerDetailPanel(
                      resolveClient: widget.resolveClient,
                      width: columnWidth,
                      bleedRight: OckerLayout.safeMargin * scale,
                    ),
                  ),
                ],
              )
            : content,
      ),
    );
  }
}
