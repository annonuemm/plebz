import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/shader_preset.dart';
import '../i18n/strings.g.dart';
import '../utils/app_logger.dart';
import '../utils/formatters.dart';
import '../utils/platform_detector.dart';
import '../models/seerr/seerr_session.dart';
import 'backup_crypto.dart';
import 'credential_fields.dart';
import 'credential_vault.dart';
import 'file_picker_service.dart';
import 'iptv/iptv_source.dart' show iptvSealedFields;
import '../connection/connection.dart';
import '../media/media_backend.dart';
import 'sensitive_prefs.dart';
import 'settings_service.dart';
import 'storage_service.dart';

class ImportResult {
  final int keysImported;
  final int keysSkipped;

  /// Servers restored from a full backup. Zero for a settings-only file,
  /// which carries none.
  final int connectionsImported;
  const ImportResult({required this.keysImported, required this.keysSkipped, this.connectionsImported = 0});
}

class SettingsExportException implements Exception {
  final String message;
  const SettingsExportException(this.message);
  @override
  String toString() => 'SettingsExportException: $message';
}

/// Thrown when an import is attempted without an active Plex user, since the
/// user prefix needed to re-scope library preferences is unavailable.
class NoUserSignedInException extends SettingsExportException {
  const NoUserSignedInException() : super('No user is signed in');
}

/// Thrown when the chosen file isn't a valid Plezy settings export.
class InvalidExportFileException extends SettingsExportException {
  const InvalidExportFileException(super.message);
}

/// Thrown when a protected backup could not be opened with the password
/// given. Indistinguishable from a file that was altered — GCM reports both
/// the same way — and the message says so.
class WrongBackupPasswordException extends SettingsExportException {
  const WrongBackupPasswordException() : super('Wrong password, or the file was altered');
}

class _PreferencePolicy {
  final String type;
  final bool userScoped;

  const _PreferencePolicy(this.type, {this.userScoped = false});
}

class _PendingImport {
  final String targetKey;
  final String type;
  final Object? value;
  final String? obsoleteKey;

  const _PendingImport({required this.targetKey, required this.type, required this.value, this.obsoleteKey});
}

class _StoredPreferenceValue {
  final bool existed;
  final Object? value;

  const _StoredPreferenceValue({required this.existed, required this.value});
}

/// Serializes / restores user-facing SharedPreferences to a JSON file.
///
/// Only preferences in the closed portable registry are exported. User-scoped
/// keys (prefixed with `user_{uuid}_`) have that prefix stripped on export and
/// re-applied with the current user's prefix on import, so preferences follow
/// whichever account is signed in on the target device.
class SettingsExportService {
  static const int formatVersion = 1;
  static const String fileExtension = 'json';

  // Type markers written into the export JSON. One per SharedPreferences setter.
  static const String _typeBool = 'bool';
  static const String _typeInt = 'int';
  static const String _typeDouble = 'double';
  static const String _typeString = 'string';
  static const String _typeStringList = 'stringList';
  static const String _userPrefixRoot = 'user_';
  // Device-local storage state must never cross installations. Keep these as
  // exact keys so portable download behavior settings remain transferable.
  static const Set<String> _nonPortableDeviceStorageKeys = {'custom_download_path', 'custom_download_path_type'};
  static const String _tvosDatabaseRecoveryPrefix = 'tvos_db_recovery_';

  /// Closed registry of portable, user-facing settings, keyed by preference
  /// key. [SettingsService.portablePrefs] is the source of truth for membership
  /// and the [Pref] declarations for the stored types; credentials, runtime
  /// state, device paths, history, endpoints, and user-authored player
  /// configuration are intentionally absent.
  static final Map<String, _PreferencePolicy> _portablePreferences = {
    for (final pref in SettingsService.portablePrefs) pref.key: _PreferencePolicy(_storageTypeFor(pref)),
  };

  static final Map<String, Pref<Object?>> _portablePrefsByKey = {
    for (final pref in SettingsService.portablePrefs) pref.key: pref,
  };

  static final Map<String, String> _obsoleteLegacyBoolKeys = {
    for (final entry in SettingsService.legacyBoolPrefs.entries) entry.value.key: entry.key,
  };

  static const Set<String> _jsonStringListPreferenceKeys = {'hidden_libraries', 'library_order'};

  static const Map<String, _PreferencePolicy> _userScopedPreferences = {
    'hidden_libraries': _PreferencePolicy(_typeString, userScoped: true),
    'library_filters': _PreferencePolicy(_typeString, userScoped: true),
    'library_order': _PreferencePolicy(_typeString, userScoped: true),
  };

  /// Keys a full backup carries and an ordinary export must not: the IPTV
  /// sources hold a panel password and the playlist address, which is the
  /// subscription itself. The channel arrangement travels with them — a
  /// restored source with someone else's order is half a restore.
  static const Map<String, _PreferencePolicy> _credentialUserScopedPreferences = {
    iptvSourcesBaseKey: _PreferencePolicy(_typeString, userScoped: true),
    liveTvChannelLayoutBaseKey: _PreferencePolicy(_typeString, userScoped: true),
    seerrSessionBaseKey: _PreferencePolicy(_typeString, userScoped: true),
  };

  /// Credential keys that belong to the installation rather than to a profile.
  static const Map<String, _PreferencePolicy> _credentialPreferences = {'tmdb_api_key': _PreferencePolicy(_typeString)};

  /// Favorite channels are filed per IPTV source under its own id, so there is
  /// no fixed key to register — and they are not user-scoped.
  static final List<(RegExp, _PreferencePolicy)> _credentialDynamicPreferences = [
    (RegExp(r'^iptv:.+$'), const _PreferencePolicy(_typeString)),
  ];

  static final List<(RegExp, _PreferencePolicy)> _dynamicUserScopedPreferences = [
    (RegExp(r'^library_(?:filters|sort|grouping|tab)_.+$'), const _PreferencePolicy(_typeString, userScoped: true)),
  ];

  @visibleForTesting
  static FutureOr<void> Function(String key)? debugBeforeImportWrite;

  static String _storageTypeFor(Pref<Object?> pref) {
    if (pref is BoolPref) return _typeBool;
    if (pref is IntPref) return _typeInt;
    if (pref is DoublePref) return _typeDouble;
    if (pref is StringPref ||
        pref is NullableStringPref ||
        pref is EnumPref ||
        pref is NullableEnumPref ||
        pref is JsonPref) {
      return _typeString;
    }
    if (pref is StringListPref) return _typeStringList;

    if (pref.key == SettingsService.appLocale.key) return _typeString;
    if (pref.key == SettingsService.libraryDensity.key) return _typeInt;
    if (pref.key == SettingsService.automotiveUiScale.key) return _typeDouble;
    if (pref.key == SettingsService.autoPip.key ||
        pref.key == SettingsService.useExternalPlayer.key ||
        pref.key == SettingsService.audioPassthrough.key) {
      return _typeBool;
    }
    throw StateError('Portable preference ${pref.key} has no storage type');
  }

  static _PreferencePolicy? _policyFor(String baseKey, {required bool withCredentials}) {
    if (baseKey.startsWith(_tvosDatabaseRecoveryPrefix)) return null;
    if (_nonPortableDeviceStorageKeys.contains(baseKey)) return null;
    final exact = _portablePreferences[baseKey] ?? _userScopedPreferences[baseKey];
    if (exact != null) return exact;
    for (final (pattern, policy) in _dynamicUserScopedPreferences) {
      if (pattern.hasMatch(baseKey)) return policy;
    }
    if (!withCredentials) return null;
    final credential = _credentialPreferences[baseKey] ?? _credentialUserScopedPreferences[baseKey];
    if (credential != null) return credential;
    for (final (pattern, policy) in _credentialDynamicPreferences) {
      if (pattern.hasMatch(baseKey)) return policy;
    }
    return null;
  }

  /// Builds the export map from the given prefs. Pure and testable.
  ///
  /// [currentUserUuid] — if set, keys prefixed with `user_{uuid}_` have that
  /// prefix stripped so they can be re-scoped on import. Keys belonging to any
  /// OTHER user are skipped (we only export the active user's prefs).
  static Map<String, dynamic> buildExportMap(
    SharedPreferencesWithCache prefs, {
    String? currentUserUuid,
    String appVersion = '',
    bool withCredentials = false,
  }) {
    final prefsOut = <String, Map<String, dynamic>>{};
    final currentUserPrefix = (currentUserUuid != null && currentUserUuid.isNotEmpty)
        ? '$_userPrefixRoot${currentUserUuid}_'
        : null;

    for (final fullKey in prefs.keys) {
      final bool sourceIsUserScoped;
      final String baseKey;
      if (currentUserPrefix != null && fullKey.startsWith(currentUserPrefix)) {
        sourceIsUserScoped = true;
        baseKey = fullKey.substring(currentUserPrefix.length);
      } else if (fullKey.startsWith(_userPrefixRoot)) {
        continue;
      } else {
        sourceIsUserScoped = false;
        baseKey = fullKey;
      }

      final policy = _policyFor(baseKey, withCredentials: withCredentials);
      if (policy == null || policy.userScoped != sourceIsUserScoped) continue;

      final entry = _encodeValue(_portableExportValue(baseKey, prefs.get(fullKey)), policy.type);
      if (entry != null) prefsOut[baseKey] = entry;
    }

    // A snapshot must preserve cold-upgrade choices without mutating storage
    // or depending on which typed preferences have been read by the UI.
    for (final entry in SettingsService.legacyBoolPrefs.entries) {
      final pref = entry.value;
      if (prefs.containsKey(pref.key)) continue;
      final legacyValue = prefs.get(entry.key);
      if (legacyValue is bool) {
        prefsOut[pref.key] = {'type': _typeString, 'value': pref.fromLegacy(legacyValue).name};
      }
    }

    return {
      'formatVersion': formatVersion,
      'appVersion': appVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'platform': Platform.operatingSystem,
      'prefs': prefsOut,
    };
  }

  /// Takes the Seerr password out of this device's vault and puts it in the
  /// backup as itself.
  ///
  /// The stored form is sealed with the vault key of *this* installation, and
  /// that key stays here — copied verbatim it would be unreadable on the new
  /// device, which would silently cost the password while the session limped
  /// on until its cookie expired. The file is encrypted either way.
  ///
  /// The same goes for the Seerr session cookie and for an IPTV source's
  /// password and playlist and guide addresses, all sealed at rest.
  static Future<void> revealSecretsForExport(Map<String, dynamic> exportedPrefs) async {
    await _mapSeerrSecret(exportedPrefs, CredentialVault.reveal);
    await _mapIptvSecrets(exportedPrefs, reveal: true);
    await _mapSealedPref(exportedPrefs, SettingsService.tmdbApiKey.key, CredentialVault.reveal);
  }

  /// The other direction: seal it with the vault of the device restoring it.
  static Future<void> protectSecretsForImport(Map<String, dynamic> exportedPrefs) async {
    await _mapSeerrSecret(exportedPrefs, (secret) async => CredentialVault.protect(secret));
    await _mapIptvSecrets(exportedPrefs, reveal: false);
    await _mapSealedPref(
      exportedPrefs,
      SettingsService.tmdbApiKey.key,
      (secret) async => CredentialVault.protect(secret),
    );
  }

  /// A [SealedStringPref]'s value, opened for the file or sealed again from
  /// it. One the vault cannot open is left out and asked for again.
  static Future<void> _mapSealedPref(
    Map<String, dynamic> exportedPrefs,
    String key,
    Future<String?> Function(String secret) transform,
  ) async {
    final entry = exportedPrefs[key];
    if (entry is! Map) return;
    final raw = entry['value'];
    if (raw is! String || raw.isEmpty) return;
    try {
      final mapped = await transform(raw);
      if (mapped == null || mapped.isEmpty) {
        exportedPrefs.remove(key);
      } else {
        entry['value'] = mapped;
      }
    } catch (error) {
      appLogger.w('Backup: $key could not be re-keyed', error: error);
      exportedPrefs.remove(key);
    }
  }

  /// The IPTV sources' sealed fields, opened for the file or sealed again
  /// from it. A value the vault cannot open is left out: that source then asks
  /// for it again, the others travel whole.
  static Future<void> _mapIptvSecrets(Map<String, dynamic> exportedPrefs, {required bool reveal}) async {
    final entry = exportedPrefs[iptvSourcesBaseKey];
    if (entry is! Map) return;
    final raw = entry['value'];
    if (raw is! String || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw);
      if (list is! List) return;
      entry['value'] = jsonEncode([
        for (final source in list)
          if (source is Map)
            reveal
                ? (await CredentialFields.reveal(Map<String, Object?>.from(source), iptvSealedFields)).json
                : await CredentialFields.protect(Map<String, Object?>.from(source), iptvSealedFields)
          else
            source,
      ]);
    } catch (error) {
      appLogger.w('Backup: the IPTV sources could not be re-keyed', error: error);
      exportedPrefs.remove(iptvSourcesBaseKey);
    }
  }

  static Future<void> _mapSeerrSecret(
    Map<String, dynamic> exportedPrefs,
    Future<String?> Function(String secret) transform,
  ) async {
    final entry = exportedPrefs[seerrSessionBaseKey];
    if (entry is! Map) return;
    final raw = entry['value'];
    if (raw is! String || raw.isEmpty) return;
    try {
      final session = SeerrSession.decode(raw);
      // An unreadable secret costs the password, not the session: the cookie
      // still signs in until it expires (and an unreadable cookie, the other
      // way round).
      final secret = session.secret.isEmpty ? '' : await transform(session.secret) ?? '';
      final cookie = session.cookie.isEmpty ? '' : await transform(session.cookie) ?? '';
      entry['value'] = session.copyWith(secret: secret, cookie: cookie).encode();
    } catch (error) {
      appLogger.w('Backup: the Seerr session could not be re-keyed', error: error);
      exportedPrefs.remove(seerrSessionBaseKey);
    }
  }

  static Object? _portableExportValue(String baseKey, Object? value) {
    if (baseKey != SettingsService.globalShaderPreset.key) return value;
    return value is String && ShaderPreset.fromId(value) != null ? value : ShaderPreset.none.id;
  }

  static Map<String, dynamic>? _encodeValue(Object? value, String expectedType) {
    return switch (expectedType) {
      _typeBool when value is bool => {'type': _typeBool, 'value': value},
      _typeInt when value is int => {'type': _typeInt, 'value': value},
      _typeDouble when value is double => {'type': _typeDouble, 'value': value},
      _typeString when value is String => {'type': _typeString, 'value': value},
      _typeStringList when _isValidValue(_typeStringList, value) => {
        'type': _typeStringList,
        'value': (value! as List).cast<String>().toList(),
      },
      _ => null,
    };
  }

  /// Applies a parsed export map to [prefs]. Pure and testable.
  ///
  /// Each logical preference in the import replaces its target value, retiring
  /// any obsolete representation. Omitted preferences are left alone. If both
  /// representations occur, the canonical entry wins regardless of entry order;
  /// an invalid canonical entry is skipped rather than replaced by a legacy one.
  ///
  /// Throws [SettingsExportException] for structural problems.
  static Future<ImportResult> applyImportMap(
    Map<String, dynamic> data,
    SharedPreferencesWithCache prefs, {
    required String currentUserUuid,
    bool withCredentials = false,
  }) async {
    final version = data['formatVersion'];
    if (version is! int) {
      throw const InvalidExportFileException('Missing formatVersion');
    }
    if (version > formatVersion) {
      throw InvalidExportFileException('Unsupported formatVersion: $version');
    }

    final rawPrefs = data['prefs'];
    if (rawPrefs is! Map) {
      throw const InvalidExportFileException('Missing prefs object');
    }

    final userPrefix = 'user_${currentUserUuid}_';
    final pending = <_PendingImport>[];
    int skipped = 0;

    for (final entry in rawPrefs.entries) {
      var baseKey = entry.key.toString();
      final rawEntry = entry.value;
      if (rawEntry is! Map) {
        skipped++;
        continue;
      }

      var type = rawEntry['type'];
      var value = rawEntry['value'];
      final legacyPref = SettingsService.legacyBoolPrefs[baseKey];
      if (version == 1 && legacyPref != null) {
        if (rawPrefs.containsKey(legacyPref.key)) {
          skipped++;
          continue;
        }
        if (type == _typeBool && value is bool) {
          baseKey = legacyPref.key;
          type = _typeString;
          value = legacyPref.fromLegacy(value).name;
        }
      }

      final policy = _policyFor(baseKey, withCredentials: withCredentials);
      if (policy == null) {
        skipped++;
        continue;
      }
      // Early format-v1 exports described these JSON-backed values as native
      // string lists. Normalize that narrowly admitted legacy shape to the
      // String representation consumed by StorageService.
      if (version == 1 &&
          _jsonStringListPreferenceKeys.contains(baseKey) &&
          type == _typeStringList &&
          _isValidValue(_typeStringList, value)) {
        type = _typeString;
        value = jsonEncode((value as List).cast<String>());
      }
      if (type is! String || type != policy.type || !_isValidValue(type, value)) {
        skipped++;
        continue;
      }
      if (baseKey == SettingsService.globalShaderPreset.key && value is String && ShaderPreset.fromId(value) == null) {
        skipped++;
        continue;
      }
      if (_portablePrefsByKey[baseKey] case final pref? when !_isAcceptedValue(pref, value)) {
        skipped++;
        continue;
      }

      pending.add(
        _PendingImport(
          targetKey: policy.userScoped ? '$userPrefix$baseKey' : baseKey,
          type: type,
          value: value,
          obsoleteKey: _obsoleteLegacyBoolKeys[baseKey],
        ),
      );
    }

    final snapshots = <String, _StoredPreferenceValue>{};
    for (final mutation in pending) {
      snapshots[mutation.targetKey] = _StoredPreferenceValue(
        existed: prefs.containsKey(mutation.targetKey),
        value: prefs.get(mutation.targetKey),
      );
      if (mutation.obsoleteKey case final obsoleteKey?) {
        snapshots[obsoleteKey] = _StoredPreferenceValue(
          existed: prefs.containsKey(obsoleteKey),
          value: prefs.get(obsoleteKey),
        );
      }
    }

    try {
      for (final mutation in pending) {
        await debugBeforeImportWrite?.call(mutation.targetKey);
        await _writeTyped(prefs, mutation.targetKey, mutation.type, mutation.value);
        if (mutation.obsoleteKey case final obsoleteKey?) {
          await debugBeforeImportWrite?.call(obsoleteKey);
          await prefs.remove(obsoleteKey);
        }
      }
    } catch (error, stackTrace) {
      try {
        await _restoreSnapshots(prefs, snapshots);
      } catch (rollbackError, rollbackStackTrace) {
        appLogger.e('Settings import rollback failed', error: rollbackError, stackTrace: rollbackStackTrace);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }

    return ImportResult(keysImported: pending.length, keysSkipped: skipped);
  }

  /// Whether [stored], already checked against the storage type, is a value
  /// the settings screens could have saved for [pref]: an enum name this build
  /// knows, JSON its codec reads, a number in range, and so on — the checks
  /// every typed write runs. A value that fails them would otherwise be stored
  /// as is and either read back as the default or reach the feature unchecked.
  static bool _isAcceptedValue(Pref<Object?> pref, Object? stored) {
    try {
      final value = switch (pref) {
        EnumPref() || NullableEnumPref() || StringListPref() || DoublePref() => pref.fromJson(stored),
        JsonPref() => pref.fromJson(jsonDecode(stored! as String)),
        _ => stored,
      };
      SettingsService.validateEditableValue(pref, value);
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool _isValidValue(String type, Object? value) {
    return switch (type) {
      _typeBool => value is bool,
      _typeInt => value is int,
      _typeDouble => value is num,
      _typeString => value is String,
      _typeStringList => value is List && value.every((element) => element is String),
      _ => false,
    };
  }

  static Future<void> _writeTyped(SharedPreferencesWithCache prefs, String key, String type, Object? value) async {
    switch (type) {
      case _typeBool:
        await prefs.setBool(key, value! as bool);
      case _typeInt:
        await prefs.setInt(key, value! as int);
      case _typeDouble:
        await prefs.setDouble(key, (value! as num).toDouble());
      case _typeString:
        await prefs.setString(key, value! as String);
      case _typeStringList:
        await prefs.setStringList(key, (value! as List).cast<String>());
      default:
        throw StateError('Unsupported portable preference type');
    }
  }

  static Future<void> _restoreSnapshots(
    SharedPreferencesWithCache prefs,
    Map<String, _StoredPreferenceValue> snapshots,
  ) async {
    for (final entry in snapshots.entries) {
      final snapshot = entry.value;
      if (!snapshot.existed) {
        await prefs.remove(entry.key);
        continue;
      }
      switch (snapshot.value) {
        case final bool value:
          await prefs.setBool(entry.key, value);
        case final int value:
          await prefs.setInt(entry.key, value);
        case final double value:
          await prefs.setDouble(entry.key, value);
        case final String value:
          await prefs.setString(entry.key, value);
        case final List<Object?> value:
          await prefs.setStringList(entry.key, value.cast<String>());
        default:
          throw StateError('Unsupported stored preference type');
      }
    }
  }

  /// The servers a full backup carries, as plain JSON.
  ///
  /// Read through the registry, which hands them over already decrypted: the
  /// tokens sit in the database under the *device's* vault key, and that key
  /// stays where it is. On the other device [applyConnections] puts them back
  /// through the same door, so they end up under that device's key.
  static List<Map<String, Object?>> buildConnectionEntries(List<Connection> connections) => [
    for (final connection in connections)
      {
        'id': connection.id,
        'kind': connection.kind.id,
        'createdAt': connection.createdAt.millisecondsSinceEpoch,
        'lastAuthenticatedAt': connection.lastAuthenticatedAt?.millisecondsSinceEpoch,
        'config': connection.toConfigJson(),
      },
  ];

  /// Rebuilds the servers from [entries] and hands each to [write].
  ///
  /// An entry that cannot be read is skipped rather than failing the restore:
  /// one server of an unknown kind must not cost the user the other four.
  /// Returns how many were restored.
  static Future<int> applyConnections(List<Object?> entries, Future<void> Function(Connection connection) write) async {
    var restored = 0;
    for (final entry in entries) {
      if (entry is! Map) continue;
      final id = entry['id'];
      final kindId = entry['kind'];
      final config = entry['config'];
      if (id is! String || kindId is! String || config is! Map) continue;
      final createdAt = entry['createdAt'];
      final lastAuth = entry['lastAuthenticatedAt'];
      final connection = _connectionFrom(
        id: id,
        kindId: kindId,
        config: config.cast<String, dynamic>(),
        createdAt: createdAt is int ? DateTime.fromMillisecondsSinceEpoch(createdAt) : DateTime.now(),
        lastAuthenticatedAt: lastAuth is int ? DateTime.fromMillisecondsSinceEpoch(lastAuth) : null,
      );
      if (connection == null) continue;
      try {
        await write(connection);
        restored++;
      } catch (error, stackTrace) {
        appLogger.w('Backup: restoring connection $id failed', error: error, stackTrace: stackTrace);
      }
    }
    return restored;
  }

  static Connection? _connectionFrom({
    required String id,
    required String kindId,
    required Map<String, dynamic> config,
    required DateTime createdAt,
    DateTime? lastAuthenticatedAt,
  }) {
    try {
      return switch (MediaBackend.fromId(kindId)) {
        MediaBackend.plex => PlexAccountConnection.fromConfigJson(
          id: id,
          json: config,
          createdAt: createdAt,
          lastAuthenticatedAt: lastAuthenticatedAt,
        ),
        MediaBackend.jellyfin || MediaBackend.emby => JellyfinConnection.fromConfigJson(
          id: id,
          json: config,
          createdAt: createdAt,
          lastAuthenticatedAt: lastAuthenticatedAt,
        ),
      };
    } catch (error) {
      appLogger.w('Backup: connection $id could not be read', error: error);
      return null;
    }
  }

  static Future<String> _defaultFileName({bool backup = false}) async {
    final now = DateTime.now();
    final y = padNumber(now.year, 4);
    final m = padNumber(now.month, 2);
    final d = padNumber(now.day, 2);
    return '${backup ? 'plesy-backup' : 'plezy-settings'}-$y$m$d.$fileExtension';
  }

  /// Serializes the current user's settings and writes them to a location of
  /// the user's choosing. Returns the saved path, or `null` if the user
  /// cancelled the picker.
  ///
  /// Platform and filesystem failures retain their original exception types.
  static Future<String?> exportToFile() async {
    final prefs = (await SettingsService.getInstance()).prefs;
    final storage = await StorageService.getInstance();
    String appVersion = '';
    try {
      final info = await PackageInfo.fromPlatform();
      appVersion = info.version;
    } on PlatformException {
      // Best-effort metadata; platforms without PackageInfo still export.
    }

    final exportMap = buildExportMap(prefs, currentUserUuid: storage.activeUserScope(), appVersion: appVersion);
    final jsonString = const JsonEncoder.withIndent('  ').convert(exportMap);
    final bytes = Uint8List.fromList(utf8.encode(jsonString));
    final fileName = await _defaultFileName();

    // Android TV has no document picker — write to the app docs dir and let
    // the caller surface the path.
    if (Platform.isAndroid && PlatformDetector.isTV()) {
      return _writeToAppDocuments(fileName, bytes);
    }

    return FilePickerService.instance.saveFile(
      dialogTitle: t.settings.exportDialogTitle,
      fileName: fileName,
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: const [fileExtension],
    );
  }

  /// Everything a new installation needs: the portable settings, the IPTV
  /// sources with their arrangement, and the servers with their tokens —
  /// encrypted with [password].
  ///
  /// Returns the saved path, or null if the user cancelled the picker.
  static Future<String?> exportBackupToFile({
    required String password,
    required Future<List<Connection>> Function() readConnections,
  }) async {
    if (password.isEmpty) {
      throw const SettingsExportException('A backup needs a password');
    }
    final prefs = (await SettingsService.getInstance()).prefs;
    final storage = await StorageService.getInstance();
    String appVersion = '';
    try {
      appVersion = (await PackageInfo.fromPlatform()).version;
    } on PlatformException {
      // Best-effort metadata; platforms without PackageInfo still export.
    }

    final payload = buildExportMap(
      prefs,
      currentUserUuid: storage.activeUserScope(),
      appVersion: appVersion,
      withCredentials: true,
    );
    await revealSecretsForExport(payload['prefs']! as Map<String, dynamic>);
    payload['connections'] = buildConnectionEntries(await readConnections());

    // The envelope stays readable so the import can tell a backup from a
    // settings file, and say "wrong password" instead of "broken file".
    final envelope = <String, Object?>{
      'formatVersion': formatVersion,
      'appVersion': appVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'platform': Platform.operatingSystem,
      'contains': const ['settings', 'servers', 'iptv'],
      ...await BackupCrypto.encrypt(jsonEncode(payload), password),
    };

    final bytes = Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(envelope)));
    final fileName = await _defaultFileName(backup: true);

    if (Platform.isAndroid && PlatformDetector.isTV()) {
      return _writeToAppDocuments(fileName, bytes);
    }
    return FilePickerService.instance.saveFile(
      dialogTitle: t.settings.exportBackupDialogTitle,
      fileName: fileName,
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: const [fileExtension],
    );
  }

  /// Where a backup can be written and looked for on a television.
  ///
  /// Android TV has no document picker, so the file has to land somewhere a
  /// person can reach from outside the app. In order of usefulness: a mounted
  /// USB stick or second volume, then the app's own folder on internal
  /// storage — which a file manager or `adb pull` can read — and only then
  /// the private documents directory, which nothing outside the app can.
  static Future<List<Directory>> backupDirectories() async {
    final dirs = <Directory>[];
    if (Platform.isAndroid) {
      try {
        // The shared Download folder of every mounted volume, removable
        // first. Whether an app may write there without the storage
        // permission — which this app deliberately does not declare —
        // depends on the Android version, so it is tried rather than
        // assumed: the write itself is the test, and the next candidate
        // catches the fall.
        dirs.addAll(await _publicDownloadDirectories());
        final scoped = await getExternalStorageDirectories(type: StorageDirectory.downloads);
        if (scoped != null) dirs.addAll(scoped.reversed);
        final external = await getExternalStorageDirectories();
        if (external != null) dirs.addAll(external.reversed);
      } catch (error) {
        appLogger.d('Backup: external storage unavailable', error: error);
      }
    }
    try {
      dirs.add(await getApplicationDocumentsDirectory());
    } catch (error) {
      appLogger.d('Backup: documents directory unavailable', error: error);
    }
    final seen = <String>{};
    return [
      for (final dir in dirs)
        if (seen.add(dir.path)) dir,
    ];
  }

  /// `Download` at the root of each mounted volume.
  ///
  /// Derived from the app's own folder on that volume rather than hardcoded:
  /// `/storage/emulated/0/Android/data/<pkg>/files` names the volume it sits
  /// on, and a USB stick answers with its own path in the same shape.
  static Future<List<Directory>> _publicDownloadDirectories() async => publicDownloadPathsFrom([
    for (final dir in await getExternalStorageDirectories() ?? const <Directory>[]) dir.path,
  ]).map(Directory.new).toList();

  /// The volume-root `Download` folders behind a set of app-scoped paths.
  @visibleForTesting
  static List<String> publicDownloadPathsFrom(List<String> appScopedPaths) {
    const marker = '/Android/data/';
    final roots = <String>{};
    for (final path in appScopedPaths) {
      final index = path.indexOf(marker);
      if (index > 0) roots.add(path.substring(0, index));
    }
    return [for (final root in roots.toList().reversed) p.join(root, 'Download')];
  }

  /// Backups lying in [backupDirectories], newest first.
  static Future<List<File>> findBackups() async {
    final found = <File>[];
    final seen = <String>{};
    for (final dir in await backupDirectories()) {
      try {
        if (!dir.existsSync()) continue;
        for (final entity in dir.listSync()) {
          final name = p.basename(entity.path);
          if (entity is! File || !name.endsWith('.$fileExtension')) continue;
          if (!name.startsWith('plesy-backup') && !name.startsWith('plezy-settings')) continue;
          if (seen.add(entity.path)) found.add(entity);
        }
      } catch (error) {
        appLogger.d('Backup: ${dir.path} could not be listed', error: error);
      }
    }
    found.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return found;
  }

  static Future<String> _writeToAppDocuments(String fileName, Uint8List bytes) async =>
      writeToFirstWritable(await backupDirectories(), fileName, bytes);

  /// Writes to the first of [dirs] that accepts the file, and answers with
  /// where it went.
  ///
  /// Trying is the only honest test: whether the shared Download folder takes
  /// a file depends on the Android version and on permissions this app does
  /// not ask for, and a directory that exists is not a directory one may
  /// write to.
  @visibleForTesting
  static Future<String> writeToFirstWritable(List<Directory> dirs, String fileName, Uint8List bytes) async {
    Object? firstError;
    for (final dir in dirs) {
      try {
        await dir.create(recursive: true);
        final file = File(p.join(dir.path, fileName));
        await file.writeAsBytes(bytes, flush: true);
        return file.path;
      } catch (error) {
        firstError ??= error;
        appLogger.d('Backup: ${dir.path} did not take the file', error: error);
      }
    }
    throw SettingsExportException('No writable location for the backup: $firstError');
  }

  /// Prompts the user to pick a settings JSON and writes its contents into
  /// SharedPreferences. Requires a signed-in user.
  ///
  /// Returns `null` if the user cancelled. Malformed files throw
  /// [InvalidExportFileException]; platform and filesystem failures retain
  /// their original exception types.
  /// [askPassword] is consulted only for a protected backup, and [writeConnection]
  /// only for the servers inside one — a settings file needs neither, which is
  /// why both stay optional.
  /// Restores from [file] without a picker — the way a television has to do
  /// it, where the file was put in place by hand.
  static Future<ImportResult?> importFromPath(
    String path, {
    Future<String?> Function()? askPassword,
    Future<void> Function(Connection connection)? writeConnection,
  }) async {
    final String contents;
    try {
      contents = await File(path).readAsString();
    } on FileSystemException {
      throw const InvalidExportFileException('Could not read the selected file');
    }
    return _applyContents(contents, askPassword: askPassword, writeConnection: writeConnection);
  }

  static Future<ImportResult?> importFromFile({
    Future<String?> Function()? askPassword,
    Future<void> Function(Connection connection)? writeConnection,
  }) async {
    final storage = await StorageService.getInstance();
    final uuid = storage.activeUserScope();
    if (uuid == null || uuid.isEmpty) {
      throw const NoUserSignedInException();
    }

    final picked = await FilePickerService.instance.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [fileExtension],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return null;

    final file = picked.files.first;
    String contents;
    final bytes = file.bytes;
    if (bytes != null) {
      try {
        contents = utf8.decode(bytes);
      } on FormatException {
        throw const InvalidExportFileException('Could not read the selected file');
      }
    } else if (file.path != null) {
      contents = await File(file.path!).readAsString();
    } else {
      throw const InvalidExportFileException('Could not read the selected file');
    }

    return _applyContents(contents, askPassword: askPassword, writeConnection: writeConnection);
  }

  /// The half of an import that does not care where the bytes came from.
  static Future<ImportResult?> _applyContents(
    String contents, {
    Future<String?> Function()? askPassword,
    Future<void> Function(Connection connection)? writeConnection,
  }) async {
    final storage = await StorageService.getInstance();
    final uuid = storage.activeUserScope();
    if (uuid == null || uuid.isEmpty) {
      throw const NoUserSignedInException();
    }
    final Object? decoded;
    try {
      decoded = json.decode(contents);
    } on FormatException {
      throw const InvalidExportFileException('Invalid export file');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const InvalidExportFileException('Invalid export file');
    }
    var data = decoded;

    // A protected backup carries its settings inside the envelope. Opening it
    // is the only place a password is asked for; a settings file has none and
    // is applied as before.
    var withCredentials = false;
    List<Object?> connections = const [];
    if (data['encryption'] != null) {
      final password = await askPassword?.call();
      if (password == null) return null;
      final String? payload;
      try {
        payload = await BackupCrypto.decrypt(data, password);
      } on FormatException catch (error) {
        throw InvalidExportFileException(error.message);
      }
      if (payload == null) throw const WrongBackupPasswordException();
      final inner = json.decode(payload);
      if (inner is! Map<String, dynamic>) {
        throw const InvalidExportFileException('Invalid backup contents');
      }
      data = inner;
      withCredentials = true;
      if (data['prefs'] case final Map<String, dynamic> restored) await protectSecretsForImport(restored);
      final raw = data['connections'];
      if (raw is List) connections = raw;
    }

    final settings = await SettingsService.getInstance();
    final result = await applyImportMap(data, settings.prefs, currentUserUuid: uuid, withCredentials: withCredentials);
    // A sealed value read back from the file is opened into memory again.
    await SettingsService.tmdbApiKey.load(settings);
    if (connections.isEmpty || writeConnection == null) return result;

    // Servers last: the settings are in place by the time the app reloads its
    // connections, so a restore never leaves it reading half of each.
    final restored = await applyConnections(connections, writeConnection);
    return ImportResult(
      keysImported: result.keysImported,
      keysSkipped: result.keysSkipped,
      connectionsImported: restored,
    );
  }
}
