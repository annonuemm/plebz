import 'package:flutter/material.dart';

/// A place for the tab on show to put its own narrowing controls, on the same
/// line as the tabs themselves.
///
/// The grouping, filter and sort chips belong to one tab — only Browse has
/// them — but they are drawn by the screen, because a row of chrome under a
/// row of chrome is two rows where the design allows one. The tab publishes,
/// the screen renders, and neither has to know about the other's layout.
///
/// A builder rather than a list, so the chips stay live: a filter badge lights
/// up without the tab having to push a fresh list every time.
class OckerFilterSlot extends InheritedNotifier<ValueNotifier<WidgetBuilder?>> {
  const OckerFilterSlot({super.key, required ValueNotifier<WidgetBuilder?> slot, required super.child})
    : super(notifier: slot);

  static ValueNotifier<WidgetBuilder?>? read(BuildContext context) {
    final element = context.getElementForInheritedWidgetOfExactType<OckerFilterSlot>();
    return (element?.widget as OckerFilterSlot?)?.notifier;
  }

  /// Register [builder] as the current tab's controls, or take them down.
  ///
  /// Deferred to after the frame: publishing during build would rebuild the
  /// row that is already being built.
  static void publish(BuildContext context, WidgetBuilder? builder) {
    final slot = read(context);
    if (slot == null || slot.value == builder) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (slot.value != builder) slot.value = builder;
    });
  }
}
