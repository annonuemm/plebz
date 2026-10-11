import 'package:flutter/material.dart';

import '../theme/mono_tokens.dart';
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
  });

  final List<({String label, String value})> facts;
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
    return OckerGlass(
      borderRadius: BorderRadius.circular(tokens(context).radiusSm + 8),
      scrimInset: 18 * ockerScale(context),
      child: Padding(
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
          ],
        ),
      ),
    );
  }
}
