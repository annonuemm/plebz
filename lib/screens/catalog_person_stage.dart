import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../focus/focusable_action_bar.dart';
import '../focus/key_event_utils.dart';
import '../redesign/ocker_fact_card.dart';
import '../redesign/ocker_skin.dart';
import '../redesign/ocker_type.dart';
import '../theme/mono_theme.dart';
import '../theme/mono_tokens.dart';
import '../utils/media_image_helper.dart';
import '../widgets/app_icon.dart';
import '../widgets/detail_home_button.dart';
import '../widgets/optimized_media_image.dart';

/// The person page as the redesign's stage on a television (Plebz) — Glas
/// and Flach alike, the primitives paint either.
///
/// Laid out at the redesign's 1920 reference and scaled by [ockerScale]:
/// portrait and name top left, the fact card level with the name on the
/// right, three lines of biography, the biography button under the card, and
/// the filters ([filters]) over the poster grids ([grids], slivers the page
/// builds). Focus starts on the filters, so one DOWN reaches the titles;
/// there the grids rise and the header shrinks to a line, and UP from their
/// first row brings the stage back.
class CatalogPersonStage extends StatefulWidget {
  const CatalogPersonStage({
    super.key,
    required this.name,
    required this.portraitUrl,
    required this.departmentsLine,
    required this.lifeLine,
    required this.roleLine,
    required this.summary,
    required this.facts,
    required this.filters,
    required this.grids,
    required this.scrollController,
    required this.loading,
    required this.emptyMessage,
    required this.biographyLabel,
    required this.onOpenBiography,
    required this.onFocusFilters,
  });

  final String name;
  final String? portraitUrl;
  final String? departmentsLine;
  final String? lifeLine;
  final String? roleLine;
  final String? summary;
  final List<({String label, String value})> facts;

  /// The filter strips; UP out of them calls [CatalogPersonStageState.focusAboveFilters].
  final Widget filters;

  /// The poster grids under the filters, as slivers; empty for "no titles".
  final List<Widget> grids;
  final ScrollController scrollController;
  final bool loading;
  final String emptyMessage;
  final String biographyLabel;
  final VoidCallback onOpenBiography;

  /// Puts focus on the selected filter.
  final VoidCallback onFocusFilters;

  @override
  State<CatalogPersonStage> createState() => CatalogPersonStageState();
}

/// Moves focus and leaves the scrolling to the focused poster
/// ([FocusableWrapper] scrolls it into its comfortable place).
void _focusWithoutScrolling(
  FocusNode node, {
  ScrollPositionAlignmentPolicy? alignmentPolicy,
  double? alignment,
  Duration? duration,
  Curve? curve,
}) => node.requestFocus();

class CatalogPersonStageState extends State<CatalogPersonStage> {
  final _biographyBarKey = GlobalKey<FocusableActionBarState>();
  final _homeFocusNode = FocusNode(debugLabel: 'person_home');
  final _gridScope = FocusScopeNode(
    debugLabel: 'person_grids',
    directionalTraversalEdgeBehavior: TraversalEdgeBehavior.stop,
  );
  bool _raised = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onFocusFilters();
    });
  }

  @override
  void dispose() {
    _homeFocusNode.dispose();
    _gridScope.dispose();
    super.dispose();
  }

  bool get _hasBiography => (widget.summary ?? '').isNotEmpty;

  /// Where UP out of the filters goes: the biography button, or the home
  /// button where there is no biography.
  void focusAboveFilters() {
    if (_hasBiography) {
      _biographyBarKey.currentState?.requestFocusOnFirst();
    } else {
      _homeFocusNode.requestFocus();
    }
  }

  void _pop() => unawaited(Navigator.of(context).maybePop());

  void _onGridFocus(bool hasFocus) {
    if (hasFocus == _raised) return;
    setState(() => _raised = hasFocus);
    final controller = widget.scrollController;
    if (!hasFocus && controller.hasClients && controller.offset > 0) {
      unawaited(controller.animateTo(0, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic));
    }
  }

  Widget _portrait(double diameter, double rim) {
    final image = ClipOval(
      child: OptimizedMediaImage(
        client: null,
        imagePath: widget.portraitUrl,
        width: diameter - 2 * rim,
        height: diameter - 2 * rim,
        fit: BoxFit.cover,
        imageType: ImageType.avatar,
        fallbackIcon: Symbols.person_rounded,
      ),
    );
    return SizedBox.square(
      dimension: diameter,
      child: OckerGlass(
        borderRadius: BorderRadius.circular(diameter / 2),
        scrimInset: 0,
        child: Padding(padding: EdgeInsets.all(rim), child: image),
      ),
    );
  }

  Widget _header(double s, MonoTokens tk) {
    final type = OckerType.of(context);
    final line = type.spotlightFacts.copyWith(color: tk.ink(0.78));
    return Row(
      crossAxisAlignment: .start,
      children: [
        _portrait(250 * s, 6 * s),
        SizedBox(width: 48 * s),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: 20 * s),
            child: Column(
              crossAxisAlignment: .start,
              children: [
                Text(
                  widget.name,
                  maxLines: 2,
                  overflow: .ellipsis,
                  style: TextStyle(
                    fontFamily: ockerDisplayFontFamily,
                    fontSize: 84 * s,
                    height: 1,
                    fontWeight: .w800,
                    letterSpacing: -1.5 * s,
                    color: tk.ink(1),
                  ),
                ),
                SizedBox(height: 6 * s),
                for (final text in [widget.departmentsLine, widget.lifeLine])
                  if (text != null) ...[
                    SizedBox(height: 14 * s),
                    Text(text, maxLines: 1, overflow: .ellipsis, style: line),
                  ],
                if (widget.roleLine case final role?) ...[
                  SizedBox(height: 14 * s),
                  Text(
                    role,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: line.copyWith(color: tk.accent, fontWeight: .w600),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _compactHeader(double s, MonoTokens tk) {
    final type = OckerType.of(context);
    final second = [?widget.lifeLine, ?widget.roleLine].join('  ·  ');
    return Row(
      children: [
        _portrait(112 * s, 4 * s),
        SizedBox(width: 28 * s),
        Expanded(
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            children: [
              Text(
                widget.name,
                maxLines: 1,
                overflow: .ellipsis,
                style: TextStyle(
                  fontFamily: ockerDisplayFontFamily,
                  fontSize: 52 * s,
                  height: 1,
                  fontWeight: .w800,
                  letterSpacing: -1 * s,
                  color: tk.ink(1),
                ),
              ),
              if (second.isNotEmpty) ...[
                SizedBox(height: 8 * s),
                Text(
                  second,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: type.spotlightFacts.copyWith(fontSize: 21 * s, color: tk.ink(0.72)),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget? _factCard(double s, MonoTokens tk) {
    if (widget.facts.isEmpty) return null;
    final label = OckerType.of(context).spotlightFacts.copyWith(fontSize: 20 * s, height: 1.3, color: tk.ink(0.58));
    return OckerFactCard(
      facts: widget.facts,
      labelWidth: 250 * s,
      labelStyle: label,
      valueStyle: label.copyWith(color: tk.ink(1), fontWeight: .w500),
      rowGap: 16 * s,
      valueMaxLines: 2,
      padding: EdgeInsets.symmetric(horizontal: 34 * s, vertical: 30 * s),
    );
  }

  Widget _biographyButton(double s, MonoTokens tk) {
    return OckerGlassBand(
      overhang: EdgeInsets.all(ockerBandMargin(context)),
      child: FocusableActionBar(
        key: _biographyBarKey,
        wrapBuiltAction: ockerGlass(context)
            ? (context, state, child) => OckerWordFocus(focused: state.showFocus, outset: EdgeInsets.zero, child: child)
            : null,
        onNavigateDown: widget.onFocusFilters,
        onNavigateUp: _homeFocusNode.requestFocus,
        onBack: _pop,
        actions: [
          FocusableAction(
            debugLabel: 'person_biography',
            onPressed: widget.onOpenBiography,
            builder: (context, state) {
              final color = tk.ink(state.showFocus ? 1 : 0.85);
              final style = TextStyle(fontFamily: ockerUiFontFamily, fontSize: 24 * s, fontWeight: .w600, color: color);
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: 30 * s, vertical: 18 * s),
                child: Row(
                  mainAxisSize: .min,
                  children: [
                    AppIcon(Symbols.info_rounded, size: 28 * s, color: color),
                    SizedBox(width: 14 * s),
                    Text(widget.biographyLabel, style: style),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final s = ockerScale(context);
    final insets = MediaQuery.paddingOf(context);
    final raised = _raised && widget.grids.isNotEmpty;
    final duration = MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 220);
    final left = 120 * s;
    final factCard = _factCard(s, tk);
    final summary = widget.summary;

    // One column, top to bottom, so a name on two lines or a long role
    // pushes what follows instead of running into it.
    final stage = Padding(
      padding: EdgeInsets.only(top: insets.top + 200 * s),
      child: Row(
        crossAxisAlignment: .start,
        children: [
          Expanded(
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .start,
              children: [
                _header(s, tk),
                if (summary != null && summary.isNotEmpty) ...[
                  SizedBox(height: 32 * s),
                  Text(
                    summary,
                    maxLines: 3,
                    overflow: .ellipsis,
                    style: TextStyle(fontFamily: ockerUiFontFamily, fontSize: 25 * s, height: 1.5, color: tk.ink(0.84)),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: 64 * s),
          SizedBox(
            width: 540 * s,
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .start,
              children: [
                ?factCard,
                if (_hasBiography) ...[if (factCard != null) SizedBox(height: 36 * s), _biographyButton(s, tk)],
              ],
            ),
          ),
        ],
      ),
    );
    // Below the home button, not beside it.
    final compact = Padding(
      padding: EdgeInsets.only(top: insets.top + 150 * s),
      child: _compactHeader(s, tk),
    );

    final Widget grids = widget.loading
        // Centred at its own size: in the grids' room a bare box stretches.
        ? const Center(child: CircularProgressIndicator())
        : widget.grids.isEmpty
        ? Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: EdgeInsets.only(left: left, top: 16 * s),
              child: Text(
                widget.emptyMessage,
                style: OckerType.of(context).spotlightFacts.copyWith(color: tk.ink(0.6)),
              ),
            ),
          )
        : Focus(
            skipTraversal: true,
            onFocusChange: _onGridFocus,
            // The posters scroll themselves into view, gently; the framework's
            // own jump on a D-pad move ran first and made the focus flicker
            // back and forth between two rows.
            //
            // A scope of their own: at a row's ends LEFT and RIGHT stop there.
            // Searched across the page, LEFT from the first column found the
            // home button, the stage came back and the grids scrolled to the
            // top. UP from the first row leaves on purpose, to the filters.
            child: FocusScope(
              node: _gridScope,
              child: FocusTraversalGroup(
                policy: ReadingOrderTraversalPolicy(requestFocusCallback: _focusWithoutScrolling),
                child: CustomScrollView(
                  controller: widget.scrollController,
                  slivers: [
                    // Room for a focused poster of the first row to grow.
                    SliverToBoxAdapter(child: SizedBox(height: 20 * s)),
                    ...widget.grids,
                    SliverToBoxAdapter(child: SizedBox(height: 48 * s)),
                  ],
                ),
              ),
            ),
          );

    return Focus(
      onKeyEvent: (_, event) => handleBackKeyNavigation(context, event),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Column(
            crossAxisAlignment: .stretch,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: left),
                child: AnimatedCrossFade(
                  duration: duration,
                  sizeCurve: Curves.easeOutCubic,
                  alignment: Alignment.topLeft,
                  crossFadeState: raised ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                  firstChild: stage,
                  secondChild: compact,
                ),
              ),
              SizedBox(height: (raised ? 24 : 40) * s),
              Padding(
                padding: EdgeInsets.only(left: left - 8 * s, right: left),
                child: Align(alignment: Alignment.centerLeft, child: widget.filters),
              ),
              // The filters' band reaches past its row; the posters start
              // clear of it.
              SizedBox(height: 16 * s),
              Expanded(child: grids),
            ],
          ),
          Positioned(
            top: insets.top + 48 * s,
            left: 56 * s,
            child: DetailHomeButton(
              focusNode: _homeFocusNode,
              onNavigateDown: _hasBiography ? focusAboveFilters : widget.onFocusFilters,
            ),
          ),
        ],
      ),
    );
  }
}
