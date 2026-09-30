import 'dart:async';

import 'package:flutter/widgets.dart';

import '../media/media_hub.dart';
import '../media/media_item.dart';

/// What holds focus right now, as far as the surfaces that only *describe* it
/// are concerned.
@immutable
class OckerFocused {
  final MediaItem item;

  /// The section it sits in, and where in that section — together they are the
  /// eyebrow above the title: `WEITER ANSEHEN · 4 VON 7`.
  final MediaHub hub;
  final int index;

  const OckerFocused({required this.item, required this.hub, required this.index});

  @override
  bool operator ==(Object other) =>
      other is OckerFocused && other.item.id == item.id && other.hub.id == hub.id && other.index == index;

  @override
  int get hashCode => Object.hash(item.id, hub.id, index);
}

/// The one place the detail panel and the ambient background learn what to
/// show, and the reason they can be pure displays rather than focus targets.
///
/// Reports are **settled** before they are published: holding RIGHT down walks
/// a row at the key-repeat rate, and a panel that swapped its still, its title
/// and its whole background on every step would strobe. Sixty milliseconds is
/// long enough to swallow a fast run and short enough that a single deliberate
/// step still feels immediate.
///
/// The first report of a run is published at once — there is nothing on screen
/// yet to strobe against, and delaying it would show an empty panel for no
/// reason.
class OckerFocusBus extends ValueNotifier<OckerFocused?> {
  OckerFocusBus() : super(null);

  static const settleDelay = Duration(milliseconds: 60);

  Timer? _settle;

  void report(OckerFocused? focus) {
    if (focus == value && _settle == null) return;
    _settle?.cancel();
    if (value == null) {
      // Nothing to fade from.
      _settle = null;
      value = focus;
      return;
    }
    _settle = Timer(settleDelay, () {
      _settle = null;
      if (!_disposed) value = focus;
    });
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _settle?.cancel();
    super.dispose();
  }
}

/// Hands the bus down the tree, so a tile deep in a grid can report itself
/// without every layer in between having to carry a callback.
class OckerFocusScope extends InheritedNotifier<OckerFocusBus> {
  const OckerFocusScope({super.key, required OckerFocusBus bus, required super.child}) : super(notifier: bus);

  /// The bus, without subscribing to its changes — for reporters.
  static OckerFocusBus? read(BuildContext context) =>
      context.getElementForInheritedWidgetOfExactType<OckerFocusScope>()?.widget is OckerFocusScope
      ? (context.getElementForInheritedWidgetOfExactType<OckerFocusScope>()!.widget as OckerFocusScope).notifier
      : null;

  /// The bus, subscribing to its changes — for the surfaces that describe it.
  static OckerFocusBus? watch(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OckerFocusScope>()?.notifier;
}
