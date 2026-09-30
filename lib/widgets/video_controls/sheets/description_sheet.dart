import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../i18n/strings.g.dart';
import 'base_video_control_sheet.dart';

/// What is playing, in words: the film's or episode's own description.
///
/// A sheet rather than the detail page's dialog, although the content is the
/// same. The player's Back chain, its focus and its auto-hide are all built
/// around [OverlaySheetController]; a dialog route over the video would answer
/// Back on its own terms and leave the chrome up behind it.
class DescriptionSheet extends StatefulWidget {
  const DescriptionSheet({super.key, required this.text});

  final String text;

  @override
  State<DescriptionSheet> createState() => _DescriptionSheetState();
}

class _DescriptionSheetState extends State<DescriptionSheet> {
  final ScrollController _controller = ScrollController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'PlayerDescription');

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// UP/DOWN scroll the text, the way the detail page's full-text dialog does
  /// it: a remote has no other way to reach the rest of a long summary, and
  /// the sheet holds nothing else that wants those keys.
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final down = key == LogicalKeyboardKey.arrowDown;
    if (!down && key != LogicalKeyboardKey.arrowUp) return KeyEventResult.ignored;
    if (!_controller.hasClients) return KeyEventResult.ignored;

    final position = _controller.position;
    // At the end of the travel the key belongs to whoever is next, or the
    // sheet would be a trap with no way back to the chrome behind it.
    const edge = 1.0;
    if (down && position.pixels >= position.maxScrollExtent - edge) return KeyEventResult.ignored;
    if (!down && position.pixels <= position.minScrollExtent + edge) return KeyEventResult.ignored;

    final target = (position.pixels + (down ? 120 : -120)).clamp(position.minScrollExtent, position.maxScrollExtent);
    _controller.animateTo(target, duration: const Duration(milliseconds: 120), curve: Curves.easeOut);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return BaseVideoControlSheet(
      title: t.discover.overview,
      icon: Symbols.info_rounded,
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKey,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: SingleChildScrollView(
            controller: _controller,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Text(widget.text, style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5)),
          ),
        ),
      ),
    );
  }
}
