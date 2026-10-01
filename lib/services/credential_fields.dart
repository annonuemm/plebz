import 'credential_vault.dart';

/// Seals and opens the credential fields of a stored JSON object, leaving its
/// shape alone — other readers (the preference repair, the first-run check)
/// still parse the object, and only these values become ciphertext.
///
/// A field holds a string or a list of strings (a guide address list).
abstract final class CredentialFields {
  /// Seals [fields] of [json] in place with [CredentialVault]; values already
  /// sealed are left as they are.
  static Future<Map<String, Object?>> protect(Map<String, Object?> json, Iterable<String> fields) async {
    for (final field in fields) {
      final value = json[field];
      if (value is String) {
        json[field] = await CredentialVault.protect(value);
      } else if (value is List) {
        json[field] = [for (final entry in value) entry is String ? await CredentialVault.protect(entry) : entry];
      }
    }
    return json;
  }

  /// Opens [fields] of [json] in place. [hadPlaintext] says a value was found
  /// unsealed — stored before sealing began, and worth sealing now. A value
  /// that cannot be opened (the vault key is gone) is dropped and counted in
  /// [lost]: the credential is gone, the rest of the object is not.
  static Future<({Map<String, Object?> json, bool hadPlaintext, int lost})> reveal(
    Map<String, Object?> json,
    Iterable<String> fields,
  ) async {
    var hadPlaintext = false;
    var lost = 0;
    Future<String?> open(String value) async {
      if (value.isEmpty) return value;
      if (!CredentialVault.isProtected(value)) {
        hadPlaintext = true;
        return value;
      }
      final revealed = await CredentialVault.reveal(value);
      if (revealed == null) lost++;
      return revealed;
    }

    for (final field in fields) {
      final value = json[field];
      if (value is String) {
        final revealed = await open(value);
        if (revealed == null) {
          json.remove(field);
        } else {
          json[field] = revealed;
        }
      } else if (value is List) {
        json[field] = [
          for (final entry in value)
            if (entry is String) ?await open(entry) else entry,
        ];
      }
    }
    return (json: json, hadPlaintext: hadPlaintext, lost: lost);
  }
}
