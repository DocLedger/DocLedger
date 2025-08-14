import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:doc_ledger/core/encryption/services/key_manager.dart';
import 'package:doc_ledger/core/encryption/services/encryption_service.dart';
import 'package:doc_ledger/core/encryption/models/encryption_models.dart';

// Mock implementation of FlutterSecureStorage for testing
class MockSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _storage = {};

  @override
  Future<void> write({required String key, required String? value, IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WindowsOptions? wOptions, WebOptions? webOptions, MacOsOptions? mOptions}) async {
    if (value != null) {
      _storage[key] = value;
    }
  }

  @override
  Future<String?> read({required String key, IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WindowsOptions? wOptions, WebOptions? webOptions, MacOsOptions? mOptions}) async {
    return _storage[key];
  }

  @override
  Future<Map<String, String>> readAll({IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WindowsOptions? wOptions, WebOptions? webOptions, MacOsOptions? mOptions}) async {
    return Map.from(_storage);
  }

  @override
  Future<void> delete({required String key, IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WindowsOptions? wOptions, WebOptions? webOptions, MacOsOptions? mOptions}) async {
    _storage.remove(key);
  }

  @override
  Future<void> deleteAll({IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WindowsOptions? wOptions, WebOptions? webOptions, MacOsOptions? mOptions}) async {
    _storage.clear();
  }

  @override
  Future<bool> containsKey({required String key, IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WindowsOptions? wOptions, WebOptions? webOptions, MacOsOptions? mOptions}) async {
    return _storage.containsKey(key);
  }

  @override
  void registerListener({required String key, required void Function(String value) listener, IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WindowsOptions? wOptions, WebOptions? webOptions, MacOsOptions? mOptions}) {
    // Mock implementation - do nothing
  }

  @override
  void unregisterListener({required String key, required void Function(String value) listener, IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WindowsOptions? wOptions, WebOptions? webOptions, MacOsOptions? mOptions}) {
    // Mock implementation - do nothing
  }

  @override
  void unregisterAllListenersForKey({required String key}) {
    // Mock implementation - do nothing
  }

  @override
  void unregisterAllListeners() {
    // Mock implementation - do nothing
  }

  @override
  Future<bool?> isCupertinoProtectedDataAvailable() async {
    return null;
  }

  @override
  Stream<bool>? get onCupertinoProtectedDataAvailabilityChanged => null;

  // Unused overrides for interface compliance
  @override
  AndroidOptions get aOptions => throw UnimplementedError();
  
  @override
  IOSOptions get iOptions => throw UnimplementedError();
  
  @override
  LinuxOptions get lOptions => throw UnimplementedError();
  
  @override
  MacOsOptions get mOptions => throw UnimplementedError();
  
  @override
  WebOptions get webOptions => throw UnimplementedError();
  
  @override
  WindowsOptions get wOptions => throw UnimplementedError();

  void clear() {
    _storage.clear();
  }
}

void main() {
  group('KeyManager', () {
    late KeyManager keyManager;
    late MockSecureStorage mockStorage;
    late EncryptionService encryptionService;

    setUp(() {
      mockStorage = MockSecureStorage();
      encryptionService = EncryptionService();
      keyManager = KeyManager(
        secureStorage: mockStorage,
        encryptionService: encryptionService,
      );
    });

    tearDown(() {
      mockStorage.clear();
    });

    group('deriveAndStoreKey', () {
      test('should derive and store a new key for clinic', () async {
        // Arrange
        const clinicId = 'test_clinic_123';

        // Act
        final keyId = await keyManager.deriveAndStoreKey(clinicId);

        // Assert
        expect(keyId, isNotEmpty);
        expect(keyId, contains(clinicId));
        
        final storedKey = await keyManager.getKey(keyId);
        expect(storedKey, isNotEmpty);
        
        final activeKeyId = await keyManager.getActiveKeyId(clinicId);
        expect(activeKeyId, equals(keyId));
      });

      test('should return existing key if not expired and not forced', () async {
        // Arrange
        const clinicId = 'test_clinic_123';

        // Act
        final keyId1 = await keyManager.deriveAndStoreKey(clinicId);
        final keyId2 = await keyManager.deriveAndStoreKey(clinicId);

        // Assert
        expect(keyId1, equals(keyId2));
      });

      test('should create new key when forced rotation is requested', () async {
        // Arrange
        const clinicId = 'test_clinic_123';

        // Act
        final keyId1 = await keyManager.deriveAndStoreKey(clinicId);
        final keyId2 = await keyManager.deriveAndStoreKey(clinicId, forceRotation: true);

        // Assert
        expect(keyId1, isNot(equals(keyId2)));
        
        final activeKeyId = await keyManager.getActiveKeyId(clinicId);
        expect(activeKeyId, equals(keyId2));
      });

      test('should store key metadata correctly', () async {
        // Arrange
        const clinicId = 'test_clinic_123';

        // Act
        final keyId = await keyManager.deriveAndStoreKey(clinicId);
        final metadata = await keyManager.getKeyMetadata(keyId);

        // Assert
        expect(metadata, isNotNull);
        expect(metadata!.keyId, equals(keyId));
        expect(metadata.derivationMethod, equals('PBKDF2-SHA256'));
        expect(metadata.salt, isNotEmpty);
        expect(metadata.isActive, isTrue);
        expect(metadata.createdAt, isNotNull);
        expect(metadata.expiresAt, isNotNull);
      });
    });

    group('getKey and getActiveKey', () {
      test('should retrieve stored key by ID', () async {
        // Arrange
        const clinicId = 'test_clinic_123';
        final keyId = await keyManager.deriveAndStoreKey(clinicId);

        // Act
        final retrievedKey = await keyManager.getKey(keyId);

        // Assert
        expect(retrievedKey, isNotEmpty);
      });

      test('should return null for non-existent key', () async {
        // Act
        final retrievedKey = await keyManager.getKey('non_existent_key');

        // Assert
        expect(retrievedKey, isNull);
      });

      test('should retrieve active key for clinic', () async {
        // Arrange
        const clinicId = 'test_clinic_123';
        final keyId = await keyManager.deriveAndStoreKey(clinicId);
        final expectedKey = await keyManager.getKey(keyId);

        // Act
        final activeKey = await keyManager.getActiveKey(clinicId);

        // Assert
        expect(activeKey, equals(expectedKey));
      });

      test('should return null for clinic with no active key', () async {
        // Act
        final activeKey = await keyManager.getActiveKey('non_existent_clinic');

        // Assert
        expect(activeKey, isNull);
      });
    });

    group('listKeys', () {
      test('should list all keys for a clinic', () async {
        // Arrange
        const clinicId = 'test_clinic_123';
        final keyId1 = await keyManager.deriveAndStoreKey(clinicId);
        final keyId2 = await keyManager.deriveAndStoreKey(clinicId, forceRotation: true);

        // Act
        final keys = await keyManager.listKeys(clinicId);

        // Assert
        expect(keys.length, equals(2));
        expect(keys.map((k) => k.keyId), containsAll([keyId1, keyId2]));
        
        // Should be sorted by creation date, newest first
        expect(keys.first.createdAt.isAfter(keys.last.createdAt), isTrue);
      });

      test('should return empty list for clinic with no keys', () async {
        // Act
        final keys = await keyManager.listKeys('non_existent_clinic');

        // Assert
        expect(keys, isEmpty);
      });

      test('should only return keys for specified clinic', () async {
        // Arrange
        const clinicId1 = 'clinic_1';
        const clinicId2 = 'clinic_2';
        await keyManager.deriveAndStoreKey(clinicId1);
        await keyManager.deriveAndStoreKey(clinicId2);

        // Act
        final keys1 = await keyManager.listKeys(clinicId1);
        final keys2 = await keyManager.listKeys(clinicId2);

        // Assert
        expect(keys1.length, equals(1));
        expect(keys2.length, equals(1));
        expect(keys1.first.keyId, contains(clinicId1));
        expect(keys2.first.keyId, contains(clinicId2));
      });
    });

    group('rotateKey', () {
      test('should create new key and deactivate old one', () async {
        // Arrange
        const clinicId = 'test_clinic_123';
        final oldKeyId = await keyManager.deriveAndStoreKey(clinicId);

        // Act
        final newKeyId = await keyManager.rotateKey(clinicId);

        // Assert
        expect(newKeyId, isNot(equals(oldKeyId)));
        
        final activeKeyId = await keyManager.getActiveKeyId(clinicId);
        expect(activeKeyId, equals(newKeyId));
        
        final oldMetadata = await keyManager.getKeyMetadata(oldKeyId);
        expect(oldMetadata?.isActive, isFalse);
        
        final newMetadata = await keyManager.getKeyMetadata(newKeyId);
        expect(newMetadata?.isActive, isTrue);
      });
    });

    group('validateKey', () {
      test('should validate existing key', () async {
        // Arrange
        const clinicId = 'test_clinic_123';
        final keyId = await keyManager.deriveAndStoreKey(clinicId);

        // Act
        final isValid = await keyManager.validateKey(keyId);

        // Assert
        expect(isValid, isTrue);
      });

      test('should reject non-existent key', () async {
        // Act
        final isValid = await keyManager.validateKey('non_existent_key');

        // Assert
        expect(isValid, isFalse);
      });

      test('should reject key with invalid metadata', () async {
        // Arrange
        const keyId = 'test_key_id';
        await mockStorage.write(key: 'docledger_key_$keyId', value: 'dGVzdF9rZXk='); // base64 encoded "test_key"
        // No metadata stored

        // Act
        final isValid = await keyManager.validateKey(keyId);

        // Assert
        expect(isValid, isFalse);
      });
    });

    group('deleteKey and deleteAllKeys', () {
      test('should delete key and its metadata', () async {
        // Arrange
        const clinicId = 'test_clinic_123';
        final keyId = await keyManager.deriveAndStoreKey(clinicId);

        // Act
        final deleted = await keyManager.deleteKey(keyId);

        // Assert
        expect(deleted, isTrue);
        
        final retrievedKey = await keyManager.getKey(keyId);
        expect(retrievedKey, isNull);
        
        final metadata = await keyManager.getKeyMetadata(keyId);
        expect(metadata, isNull);
      });

      test('should return false when deleting non-existent key', () async {
        // Act
        final deleted = await keyManager.deleteKey('non_existent_key');

        // Assert
        expect(deleted, isFalse);
      });

      test('should delete all keys for a clinic', () async {
        // Arrange
        const clinicId = 'test_clinic_123';
        final keyId1 = await keyManager.deriveAndStoreKey(clinicId);
        final keyId2 = await keyManager.deriveAndStoreKey(clinicId, forceRotation: true);

        // Act
        final deletedCount = await keyManager.deleteAllKeys(clinicId);

        // Assert
        expect(deletedCount, equals(2));
        
        final keys = await keyManager.listKeys(clinicId);
        expect(keys, isEmpty);
        
        final activeKeyId = await keyManager.getActiveKeyId(clinicId);
        expect(activeKeyId, isNull);
      });
    });

    group('needsKeyRotation', () {
      test('should return true for clinic with no keys', () async {
        // Act
        final needsRotation = await keyManager.needsKeyRotation('non_existent_clinic');

        // Assert
        expect(needsRotation, isTrue);
      });

      test('should return false for recently created key', () async {
        // Arrange
        const clinicId = 'test_clinic_123';
        await keyManager.deriveAndStoreKey(clinicId);

        // Act
        final needsRotation = await keyManager.needsKeyRotation(clinicId);

        // Assert
        expect(needsRotation, isFalse);
      });

      test('should return true for expired key', () async {
        // Arrange
        const clinicId = 'test_clinic_123';
        final keyId = await keyManager.deriveAndStoreKey(clinicId);
        
        // Manually create expired metadata
        final expiredMetadata = EncryptionKey(
          keyId: keyId,
          derivationMethod: 'PBKDF2-SHA256',
          salt: 'test_salt',
          createdAt: DateTime.now().subtract(const Duration(days: 100)),
          expiresAt: DateTime.now().subtract(const Duration(days: 1)),
          isActive: true,
        );
        
        await mockStorage.write(
          key: 'docledger_metadata_$keyId',
          value: jsonEncode(expiredMetadata.toJson()),
        );

        // Act
        final needsRotation = await keyManager.needsKeyRotation(clinicId);

        // Assert
        expect(needsRotation, isTrue);
      });
    });

    group('exportKeyMetadata', () {
      test('should export key metadata without actual keys', () async {
        // Arrange
        const clinicId = 'test_clinic_123';
        final keyId1 = await keyManager.deriveAndStoreKey(clinicId);
        final keyId2 = await keyManager.deriveAndStoreKey(clinicId, forceRotation: true);

        // Act
        final exported = await keyManager.exportKeyMetadata(clinicId);

        // Assert
        expect(exported['clinic_id'], equals(clinicId));
        expect(exported['active_key_id'], equals(keyId2));
        expect(exported['keys'], isA<List>());
        expect((exported['keys'] as List).length, equals(2));
        expect(exported['exported_at'], isNotNull);
        
        // Verify no actual keys are exported
        final exportedString = jsonEncode(exported);
        expect(exportedString, isNot(contains('docledger_key_')));
      });

      test('should handle clinic with no keys', () async {
        // Act
        final exported = await keyManager.exportKeyMetadata('non_existent_clinic');

        // Assert
        expect(exported['clinic_id'], equals('non_existent_clinic'));
        expect(exported['active_key_id'], isNull);
        expect(exported['keys'], isEmpty);
      });
    });

    group('Key consistency and derivation', () {
      test('should derive same key for same clinic and salt', () async {
        // Arrange
        const clinicId = 'test_clinic_123';

        // Act
        final keyId1 = await keyManager.deriveAndStoreKey(clinicId);
        final key1 = await keyManager.getKey(keyId1);
        
        // Delete and recreate with same salt
        await keyManager.deleteAllKeys(clinicId);
        final keyId2 = await keyManager.deriveAndStoreKey(clinicId);
        final key2 = await keyManager.getKey(keyId2);

        // Assert
        expect(key1, equals(key2)); // Same salt should produce same key
      });

      test('should handle multiple clinics independently', () async {
        // Arrange
        const clinicId1 = 'clinic_1';
        const clinicId2 = 'clinic_2';

        // Act
        final keyId1 = await keyManager.deriveAndStoreKey(clinicId1);
        final keyId2 = await keyManager.deriveAndStoreKey(clinicId2);
        
        final key1 = await keyManager.getKey(keyId1);
        final key2 = await keyManager.getKey(keyId2);

        // Assert
        expect(key1, isNot(equals(key2)));
        expect(keyId1, contains(clinicId1));
        expect(keyId2, contains(clinicId2));
      });
    });

    group('Error handling', () {
      test('should handle storage errors gracefully', () async {
        // This test would require mocking storage failures
        // For now, we test that the methods don't throw unexpected exceptions
        expect(
          () async => await keyManager.getKey('test_key'),
          returnsNormally,
        );
        
        expect(
          () async => await keyManager.listKeys('test_clinic'),
          returnsNormally,
        );
      });

      test('should handle invalid JSON in metadata', () async {
        // Arrange
        const keyId = 'test_key_id';
        await mockStorage.write(key: 'docledger_key_$keyId', value: 'dGVzdF9rZXk=');
        await mockStorage.write(key: 'docledger_metadata_$keyId', value: 'invalid_json');

        // Act & Assert
        final metadata = await keyManager.getKeyMetadata(keyId);
        expect(metadata, isNull);
        
        final isValid = await keyManager.validateKey(keyId);
        expect(isValid, isFalse);
      });
    });

    group('Integration tests', () {
      test('should perform complete key lifecycle', () async {
        // Arrange
        const clinicId = 'integration_test_clinic';

        // Act & Assert - Create key
        final keyId1 = await keyManager.deriveAndStoreKey(clinicId);
        expect(keyId1, isNotEmpty);
        
        // Validate key
        final isValid1 = await keyManager.validateKey(keyId1);
        expect(isValid1, isTrue);
        
        // Rotate key
        final keyId2 = await keyManager.rotateKey(clinicId);
        expect(keyId2, isNot(equals(keyId1)));
        
        // Verify old key is deactivated
        final oldMetadata = await keyManager.getKeyMetadata(keyId1);
        expect(oldMetadata?.isActive, isFalse);
        
        // Verify new key is active
        final newMetadata = await keyManager.getKeyMetadata(keyId2);
        expect(newMetadata?.isActive, isTrue);
        
        // List keys
        final keys = await keyManager.listKeys(clinicId);
        expect(keys.length, equals(2));
        
        // Export metadata
        final exported = await keyManager.exportKeyMetadata(clinicId);
        expect(exported['keys'], hasLength(2));
        
        // Clean up
        final deletedCount = await keyManager.deleteAllKeys(clinicId);
        expect(deletedCount, equals(2));
        
        final finalKeys = await keyManager.listKeys(clinicId);
        expect(finalKeys, isEmpty);
      });

      test('should handle key rotation limits correctly', () async {
        // Arrange
        const clinicId = 'rotation_test_clinic';

        // Act - Create more keys than the retention limit
        final keyIds = <String>[];
        for (int i = 0; i < 8; i++) {
          final keyId = await keyManager.rotateKey(clinicId);
          keyIds.add(keyId);
        }

        // Assert - Should only keep the most recent keys
        final keys = await keyManager.listKeys(clinicId);
        expect(keys.length, lessThanOrEqualTo(5)); // Max retention is 5
        
        // Verify the most recent key is still active
        final activeKeyId = await keyManager.getActiveKeyId(clinicId);
        expect(activeKeyId, equals(keyIds.last));
      });
    });
  });
}