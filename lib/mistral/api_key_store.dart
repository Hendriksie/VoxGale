import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Storage for the user's Mistral API key.
///
/// Implementations must keep the key in the device's secure storage
/// (Android Keystore-backed) — never in plaintext files, shared preferences,
/// logs, or source code.
abstract interface class ApiKeyStore {
  /// Returns the stored key, or null when no key is saved.
  Future<String?> readKey();

  /// Stores [key].
  Future<void> saveKey(String key);

  /// Deletes the stored key.
  Future<void> deleteKey();
}

/// [ApiKeyStore] backed by [FlutterSecureStorage] (Android Keystore).
class SecureStorageApiKeyStore implements ApiKeyStore {
  SecureStorageApiKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String keyName = 'mistral_api_key';

  /// Standard secure configuration: AES-GCM with RSA-OAEP key wrapping,
  /// API 23+, no biometric prompt required.
  static const AndroidOptions _androidOptions = AndroidOptions();

  @override
  Future<String?> readKey() =>
      _storage.read(key: keyName, aOptions: _androidOptions);

  @override
  Future<void> saveKey(String key) =>
      _storage.write(key: keyName, value: key, aOptions: _androidOptions);

  @override
  Future<void> deleteKey() =>
      _storage.delete(key: keyName, aOptions: _androidOptions);
}
