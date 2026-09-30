import 'package:flutter/material.dart';

/// A place for the screen on show to put its own chrome, beside the clock.
///
/// Under the rail, every screen drew its own toolbar over its own content. The
/// header takes that band of the screen for navigation, so a screen that still
/// drew its toolbar there would either collide with it or sit in a second row
/// underneath — two rows of chrome, which is the thing this design spends most
/// of its effort removing.
///
/// A builder rather than a list of widgets: it is registered once, when the
/// screen appears, and called on every header build — so the actions stay live
/// (a refresh spinner, a participant count) without the screen having to push
/// a new list each time something changes.
class OckerHeaderSlot extends InheritedNotifier<ValueNotifier<WidgetBuilder?>> {
  const OckerHeaderSlot({super.key, required ValueNotifier<WidgetBuilder?> slot, required super.child})
    : super(notifier: slot);

  /// The slot, without subscribing — for the screen that fills it.
  static ValueNotifier<WidgetBuilder?>? read(BuildContext context) {
    final element = context.getElementForInheritedWidgetOfExactType<OckerHeaderSlot>();
    return (element?.widget as OckerHeaderSlot?)?.notifier;
  }

  /// Register [builder] as the current screen's header chrome, and take it
  /// down again when the screen goes.
  ///
  /// Deferred to after the frame: registering during build would rebuild the
  /// header while it is already being built.
  static void publish(BuildContext context, WidgetBuilder? builder) {
    final slot = read(context);
    if (slot == null || slot.value == builder) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (slot.value != builder) slot.value = builder;
    });
  }
}
