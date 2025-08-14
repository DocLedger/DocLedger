import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/encryption_models.dart';
import 'encryption_service.dart';

/// Service for managing encryption keys with secure storage and rotation
/// 
/// This service provides secure key management for DocLedger with the following features:
/// - Key derivation using clinic ID and device-specific salt
/// - Secure storage using device keystore
/// - Key rotation mechanism for enhanced security
/// - Key validation and integrity checking
class KeyManager {
  static const String _keyPrefix = 'docledger_key_';
  static const String _saltPrefix = 'docledger_salt_';
  static const String _metadataPrefix = 'docledger_metadata_';
  static const String _activeKeyId = 'docledger_active_key_id';
  static const int _keyRotationDays = 90; // Rotate keys every 90 days
  static const int _maxKeyHistory = 5; // Keep last 5 keys for decryption
  
  final FlutterSecureStorage _secureStorage;
  final EncryptionService _encryptionService;
  final Random _random = Random.secure();

  KeyManager({
    FlutterSecureStorage? secureStorage,
    EncryptionService? encryptionService,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage(
          aOptions: AndroidOptions(
            encryptedSharedPreferences: true,
          ),
          iOptions: IOSOptions(
            accessibility: KeychainAccessibility.first_unlock_this_device,
          ),
          lOptions: LinuxOptions(),
          wOptions: WindowsOptions(
            useBackwardCompatibility: false,
          ),
        ),
        _encryptionService = encryptionService ?? EncryptionService();

  /// Derives and stores an encryption key for the given clinic
  /// 
  /// [clinicId] - The clinic identifier
  /// [forceRotation] - Whether to force key rotation even if current key is valid
  /// 
  /// Returns the key ID of the derived key
  /// 
  /// Throws [EncryptionException] if key derivation fails
  Future<String> deriveAndStoreKey(String clinicId, {bool forceRotation = false}) async {
    try {
      // Check if we need to rotate the key
      final currentKeyId = await getActiveKeyId(clinicId);
      if (currentKeyId != null && !forceRotation) {
        final keyMetadata = await _getKeyMetadata(currentKeyId);
        if (keyMetadata != null && !_shouldRotateKey(keyMetadata)) {
          return currentKeyId;
        }
      }

      // Generate new key ID
      final keyId = _generateKeyId(clinicId);
      
      // Generate or retrieve device salt
      final deviceSalt = await _getOrCreateDeviceSalt(clinicId);
      
      // Derive the encryption key
      final derivedKey = await _encryptionService.deriveEncryptionKey(clinicId, deviceSalt);
      
      // Create key metadata
      final keyMetadata = EncryptionKey(
        keyId: keyId,
        derivationMethod: 'PBKDF2-SHA256',
        salt: deviceSalt,
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(Duration(days: _keyRotationDays)),
        isActive: true,
      );
      
      // Store the key and metadata securely
      await _secureStorage.write(key: '$_keyPrefix$keyId', value: derivedKey);
      await _secureStorage.write(key: '$_metadataPrefix$keyId', value: jsonEncode(keyMetadata.toJson()));
      
      // Update active key ID
      await _secureStorage.write(key: '$_activeKeyId$clinicId', value: keyId);
      
      // Deactivate old keys but keep them for decryption
      if (currentKeyId != null && currentKeyId != keyId) {
        await _deactivateKey(currentKeyId);
      }
      
      // Clean up old keys beyond retention limit
      await _cleanupOldKeys(clinicId);
      
      return keyId;
    } catch (e) {
      throw EncryptionException(
        'Failed to derive and store key: ${e.toString()}',
        code: 'KEY_DERIVATION_FAILED',
        originalError: e,
      );
    }
  }

  /// Retrieves an encryption key by key ID
  /// 
  /// [keyId] - The key identifier
  /// 
  /// Returns the encryption key or null if not found
  Future<String?> getKey(String keyId) async {
    try {
      return await _secureStorage.read(key: '$_keyPrefix$keyId');
    } catch (e) {
      return null;
    }
  }

  /// Gets the active key ID for a clinic
  /// 
  /// [clinicId] - The clinic identifier
  /// 
  /// Returns the active key ID or null if none exists
  Future<String?> getActiveKeyId(String clinicId) async {
    try {
      return await _secureStorage.read(key: '$_activeKeyId$clinicId');
    } catch (e) {
      return null;
    }
  }

  /// Gets the active encryption key for a clinic
  /// 
  /// [clinicId] - The clinic identifier
  /// 
  /// Returns the active encryption key or null if none exists
  Future<String?> getActiveKey(String clinicId) async {
    final keyId = await getActiveKeyId(clinicId);
    if (keyId == null) return null;
    return await getKey(keyId);
  }

  /// Gets key metadata by key ID
  /// 
  /// [keyId] - The key identifier
  /// 
  /// Returns the key metadata or null if not found
  Future<EncryptionKey?> getKeyMetadata(String keyId) async {
    return await _getKeyMetadata(keyId);
  }

  /// Lists all available keys for a clinic
  /// 
  /// [clinicId] - The clinic identifier
  /// 
  /// Returns a list of key metadata for the clinic
  Future<List<EncryptionKey>> listKeys(String clinicId) async {
    try {
      final allKeys = await _secureStorage.readAll();
      final keys = <EncryptionKey>[];
      
      for (final entry in allKeys.entries) {
        if (entry.key.startsWith(_metadataPrefix)) {
          try {
            final metadata = EncryptionKey.fromJson(jsonDecode(entry.value));
            if (metadata.keyId.contains(clinicId)) {
              keys.add(metadata);
            }
          } catch (e) {
            // Skip invalid metadata entries
            continue;
          }
        }
      }
      
      // Sort by creation date, newest first
      keys.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return keys;
    } catch (e) {
      return [];
    }
  }

  /// Rotates the encryption key for a clinic
  /// 
  /// [clinicId] - The clinic identifier
  /// 
  /// Returns the new key ID
  Future<String> rotateKey(String clinicId) async {
    return await deriveAndStoreKey(clinicId, forceRotation: true);
  }

  /// Validates a key and its metadata
  /// 
  /// [keyId] - The key identifier
  /// 
  /// Returns true if the key is valid, false otherwise
  Future<bool> validateKey(String keyId) async {
    try {
      final key = await getKey(keyId);
      final metadata = await _getKeyMetadata(keyId);
      
      if (key == null || metadata == null) {
        return false;
      }
      
      // Check if key has expired
      if (metadata.expiresAt != null && DateTime.now().isAfter(metadata.expiresAt!)) {
        return false;
      }
      
      // Validate key format (should be base64)
      try {
        base64.decode(key);
      } catch (e) {
        return false;
      }
      
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Deletes a key and its metadata
  /// 
  /// [keyId] - The key identifier
  /// 
  /// Returns true if the key was deleted, false if it didn't exist
  Future<bool> deleteKey(String keyId) async {
    try {
      final keyExists = await getKey(keyId) != null;
      if (!keyExists) return false;
      
      await _secureStorage.delete(key: '$_keyPrefix$keyId');
      await _secureStorage.delete(key: '$_metadataPrefix$keyId');
      
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Deletes all keys for a clinic
  /// 
  /// [clinicId] - The clinic identifier
  /// 
  /// Returns the number of keys deleted
  Future<int> deleteAllKeys(String clinicId) async {
    try {
      final keys = await listKeys(clinicId);
      int deletedCount = 0;
      
      for (final key in keys) {
        if (await deleteKey(key.keyId)) {
          deletedCount++;
        }
      }
      
      // Delete active key ID reference
      await _secureStorage.delete(key: '$_activeKeyId$clinicId');
      
      return deletedCount;
    } catch (e) {
      return 0;
    }
  }

  /// Checks if key rotation is needed for a clinic
  /// 
  /// [clinicId] - The clinic identifier
  /// 
  /// Returns true if key rotation is needed
  Future<bool> needsKeyRotation(String clinicId) async {
    try {
      final keyId = await getActiveKeyId(clinicId);
      if (keyId == null) return true;
      
      final metadata = await _getKeyMetadata(keyId);
      if (metadata == null) return true;
      
      return _shouldRotateKey(metadata);
    } catch (e) {
      return true;
    }
  }

  /// Exports key metadata for backup (without the actual keys)
  /// 
  /// [clinicId] - The clinic identifier
  /// 
  /// Returns a map of key metadata for backup
  Future<Map<String, dynamic>> exportKeyMetadata(String clinicId) async {
    try {
      final keys = await listKeys(clinicId);
      final activeKeyId = await getActiveKeyId(clinicId);
      
      return {
        'clinic_id': clinicId,
        'active_key_id': activeKeyId,
        'keys': keys.map((k) => k.toJson()).toList(),
        'exported_at': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      throw EncryptionException(
        'Failed to export key metadata: ${e.toString()}',
        code: 'EXPORT_FAILED',
        originalError: e,
      );
    }
  }

  // Private helper methods

  /// Generates a unique key ID
  String _generateKeyId(String clinicId) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomSuffix = _generateRandomString(8);
    return '${clinicId}_${timestamp}_$randomSuffix';
  }

  /// Gets or creates a device salt for key derivation
  Future<String> _getOrCreateDeviceSalt(String clinicId) async {
    final saltKey = '$_saltPrefix$clinicId';
    String? salt = await _secureStorage.read(key: saltKey);
    
    if (salt == null) {
      salt = _encryptionService.generateSalt();
      await _secureStorage.write(key: saltKey, value: salt);
    }
    
    return salt;
  }

  /// Gets key metadata from secure storage
  Future<EncryptionKey?> _getKeyMetadata(String keyId) async {
    try {
      final metadataJson = await _secureStorage.read(key: '$_metadataPrefix$keyId');
      if (metadataJson == null) return null;
      
      return EncryptionKey.fromJson(jsonDecode(metadataJson));
    } catch (e) {
      return null;
    }
  }

  /// Checks if a key should be rotated based on its metadata
  bool _shouldRotateKey(EncryptionKey metadata) {
    if (metadata.expiresAt == null) return false;
    
    // Rotate if expired or within 7 days of expiration
    final rotationThreshold = DateTime.now().add(const Duration(days: 7));
    return metadata.expiresAt!.isBefore(rotationThreshold);
  }

  /// Deactivates a key by updating its metadata
  Future<void> _deactivateKey(String keyId) async {
    try {
      final metadata = await _getKeyMetadata(keyId);
      if (metadata == null) return;
      
      final updatedMetadata = EncryptionKey(
        keyId: metadata.keyId,
        derivationMethod: metadata.derivationMethod,
        salt: metadata.salt,
        createdAt: metadata.createdAt,
        expiresAt: metadata.expiresAt,
        isActive: false,
      );
      
      await _secureStorage.write(
        key: '$_metadataPrefix$keyId',
        value: jsonEncode(updatedMetadata.toJson()),
      );
    } catch (e) {
      // Ignore errors when deactivating keys
    }
  }

  /// Cleans up old keys beyond the retention limit
  Future<void> _cleanupOldKeys(String clinicId) async {
    try {
      final keys = await listKeys(clinicId);
      
      // Keep only the most recent keys up to the limit
      if (keys.length > _maxKeyHistory) {
        final keysToDelete = keys.skip(_maxKeyHistory);
        
        for (final key in keysToDelete) {
          await deleteKey(key.keyId);
        }
      }
    } catch (e) {
      // Ignore cleanup errors
    }
  }

  /// Generates a random string of specified length
  String _generateRandomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return String.fromCharCodes(
      Iterable.generate(
        length,
        (_) => chars.codeUnitAt(_random.nextInt(chars.length)),
      ),
    );
  }
}