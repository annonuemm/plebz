import 'package:flutter/material.dart';

import '../theme/mono_tokens.dart';
import 'ocker_frost.dart';
import 'ocker_skin.dart';

/// Facts on a card of their own (Plebz): one line per fact, its label in a
/// column of its own and the value beside it, on glass under Glas and flat
/// under Flach ([OckerGlass] paints either). For the stages whose picture
/// stands behind them: words straight on a photograph do not read.
///
/// The type and the spacing are the stage's: the detail stage's sheet is
/// dense, the person page's card roomy.
class OckerFactCard extends StatelessWidget {
  const OckerFactCard({
    super.key,
    required this.facts,
    required this.labelWidth,
    required this.labelStyle,
    required this.valueStyle,
    required this.rowGap,
    this.valueMaxLines = 1,
    this.padding = EdgeInsets.zero,
    this.widgetFacts = const [],
  });

  final List<({String label, String value})> facts;

  /// Rows whose value is drawn rather than written — the friends who watched
  /// a title, with their pictures (Plebz). Below [facts], set the same way.
  final List<({String label, Widget value})> widgetFacts;
  final double labelWidth;
  final TextStyle labelStyle;
  final TextStyle valueStyle;

  /// The room between two lines.
  final double rowGap;
  final int valueMaxLines;

  /// Inside the glass's own inset.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final radius = BorderRadius.circular(tk.radiusSm + 8);
    final inset = 18 * ockerScale(context);
    final content = Padding(
      padding: padding,
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        children: [
          for (var index = 0; index < facts.length; index++)
            Padding(
              padding: EdgeInsets.only(top: index == 0 ? 0 : rowGap),
              child: Row(
                crossAxisAlignment: .baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  SizedBox(
                    width: labelWidth,
                    child: Text(facts[index].label, maxLines: 1, overflow: .ellipsis, style: labelStyle),
                  ),
                  Expanded(
                    child: Text(facts[index].value, maxLines: valueMaxLines, overflow: .ellipsis, style: valueStyle),
                  ),
                ],
              ),
            ),
          for (var index = 0; index < widgetFacts.length; index++)
            Padding(
              padding: EdgeInsets.only(top: index == 0 && facts.isEmpty ? 0 : rowGap),
              child: Row(
                children: [
                  SizedBox(
                    width: labelWidth,
                    child: Text(widgetFacts[index].label, maxLines: 1, overflow: .ellipsis, style: labelStyle),
                  ),
                  Expanded(
                    child: Align(alignment: AlignmentDirectional.centerStart, child: widgetFacts[index].value),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    // "Glas – v2" (Plebz): frosted over the stage's picture, which holds still.
    if (ockerFrost(context)) {
      return OckerFrostBlur(
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: tk.ink(0.14)),
        ),
        tint: tk.bg.withValues(alpha: 0.3),
        child: Padding(padding: EdgeInsets.all(inset), child: content),
      );
    }
    return OckerGlass(borderRadius: radius, scrimInset: inset, child: content);
  }
}
