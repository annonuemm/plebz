import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/app_logger.dart';

/// Why the Keystore could not open a wrapped vault key.
enum VaultKeyWrapFailure {
  /// It failed for now (some boxes refuse the Keystore shortly after boot):
  /// nothing may be overwritten, and the next access tries again.
  unavailable,

  /// The wrapping key is gone, or the wrapped value is not its own: what it
  /// held cannot be recovered.
  lost,
}

class VaultKeyWrapException implements Exception {
  const VaultKeyWrapException(this.failure, [this.detail]);

  final VaultKeyWrapFailure failure;
  final String? detail;

  @override
  String toString() => 'VaultKeyWrapException(${failure.name}${detail == null ? '' : ': $detail'})';
}

/// The Android Keystore wrapping of the credential vault's key
/// (`VaultKeyChannel.kt`): the key stays in the preferences only encrypted
/// under a key that never leaves the Keystore. Android only — elsewhere the
/// vault keeps its key as it always did.
abstract final class VaultKeyWrap {
  @visibleForTesting
  static const MethodChannel channel = MethodChannel('com.plebz/vault_key');

  @visibleForTesting
  static bool? debugSupported;

  static bool get supported => debugSupported ?? (!kIsWeb && Platform.isAndroid);

  /// [key] wrapped, but only once this device's Keystore has proved it can
  /// give it back: wrapped and unwrapped again, byte for byte. Null where
  /// there is no Keystore, or it failed that test — the key then stays as it
  /// is rather than be locked away in something that cannot open it.
  static Future<Uint8List?> wrapVerified(List<int> key) async {
    if (!supported) return null;
    try {
      final wrapped = await channel.invokeMethod<Uint8List>('wrap', Uint8List.fromList(key));
      if (wrapped == null) return null;
      final back = await unwrap(wrapped);
      if (!listEquals(back, key)) {
        appLogger.w('VaultKeyWrap: the Keystore gave back something else; not wrapping');
        return null;
      }
      return wrapped;
    } catch (error) {
      appLogger.w('VaultKeyWrap: the Keystore cannot wrap on this device; not wrapping', error: error);
      return null;
    }
  }

  /// The key inside [wrapped]. Throws [VaultKeyWrapException].
  static Future<Uint8List> unwrap(List<int> wrapped) async {
    try {
      final key = await channel.invokeMethod<Uint8List>('unwrap', Uint8List.fromList(wrapped));
      if (key == null) throw const VaultKeyWrapException(VaultKeyWrapFailure.unavailable, 'no answer');
      return key;
    } on PlatformException catch (error) {
      final failure = switch (error.code) {
        'KEY_GONE' || 'CORRUPT' => VaultKeyWrapFailure.lost,
        _ => VaultKeyWrapFailure.unavailable,
      };
      throw VaultKeyWrapException(failure, '${error.code}: ${error.message}');
    } on MissingPluginException catch (error) {
      throw VaultKeyWrapException(VaultKeyWrapFailure.unavailable, error.message);
    }
  }
}
