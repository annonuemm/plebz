/// A stand-in for `package:sentry_flutter`: the names upstream's code calls,
/// answering with nothing. Plebz sends no crash reports — see this package's
/// pubspec for why it exists at all.
///
/// Every call behaves as the real SDK does without an initialised hub, which
/// is how this app always ran it: breadcrumbs go nowhere, and a capture comes
/// back with [SentryId.empty], the SDK's own "nothing was sent".
library;

import 'dart:async';
import 'dart:math';

/// How severe an event is.
enum SentryLevel { debug, info, warning, error, fatal }

/// An event id. [SentryId.empty] is the answer to every capture here.
class SentryId {
  const SentryId.empty() : _id = '00000000000000000000000000000000';

  /// A fresh id, as the SDK hands out for a delivered event. Nothing here
  /// delivers one; tests use it to stand for delivery.
  SentryId.newId() : _id = _randomHex();

  final String _id;

  static final Random _random = Random();

  static String _randomHex() => List.generate(32, (_) => _random.nextInt(16).toRadixString(16)).join();

  @override
  bool operator ==(Object other) => other is SentryId && other._id == _id;

  @override
  int get hashCode => _id.hashCode;

  @override
  String toString() => _id;
}

/// A trail entry leading up to an event.
class Breadcrumb {
  Breadcrumb({this.message, this.category, this.data, this.level, this.type, DateTime? timestamp})
    : timestamp = timestamp ?? DateTime.now().toUtc();

  final String? message;
  final String? category;
  final Map<String, dynamic>? data;
  final SentryLevel? level;
  final String? type;
  final DateTime timestamp;
}

/// Extra material for an event.
class Hint {}

/// The context an event would be sent with.
class Scope {
  void setTag(String key, String value) {}

  void setContexts(String key, dynamic value) {}

  void setExtra(String key, dynamic value) {}
}

typedef ScopeCallback = FutureOr<void> Function(Scope scope);

/// The SDK's entry point, disabled.
class Sentry {
  Sentry._();

  static bool get isEnabled => false;

  static Future<void> addBreadcrumb(Breadcrumb crumb, {Hint? hint}) async {}

  static Future<SentryId> captureMessage(
    String? message, {
    SentryLevel? level,
    String? template,
    List<dynamic>? params,
    Hint? hint,
    ScopeCallback? withScope,
  }) async => const SentryId.empty();

  static Future<SentryId> captureException(
    dynamic throwable, {
    dynamic stackTrace,
    Hint? hint,
    dynamic message,
    ScopeCallback? withScope,
  }) async => const SentryId.empty();

  static FutureOr<void> configureScope(ScopeCallback callback) {}

  static Future<void> close() async {}
}
