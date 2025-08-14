import 'package:flutter_test/flutter_test.dart';
import 'package:doc_ledger/core/encryption/models/encryption_models.dart';

void main() {
  group('EncryptionKey Tests', () {
    late EncryptionKey testKey;
    late DateTime testCreatedAt;
    late DateTime testExpiresAt;

    setUp(() {
      testCreatedAt = DateTime(2024, 1, 15, 10, 0);
      testExpiresAt = DateTime(2024, 12, 31, 23, 59);
      testKey = EncryptionKey(
        keyId: 'key_123',
        derivationMethod: 'PBKDF2',
        salt: 'test_salt_value',
        createdAt: testCreatedAt,
        expiresAt: testExpiresAt,
        isActive: true,
      );
    });

    test('should create EncryptionKey with all properties', () {
      expect(testKey.keyId, equals('key_123'));
      expect(testKey.derivationMethod, equals('PBKDF2'));
      expect(testKey.salt, equals('test_salt_value'));
      expect(testKey.createdAt, equals(testCreatedAt));
      expect(testKey.expiresAt, equals(testExpiresAt));
      expect(testKey.isActive, isTrue);
    });

    test('should serialize to JSON correctly', () {
      final json = testKey.toJson();

      expect(json['key_id'], equals('key_123'));
      expect(json['derivation_method'], equals('PBKDF2'));
      expect(json['salt'], equals('test_salt_value'));
      expect(json['created_at'], equals('2024-01-15T10:00:00.000'));
      expect(json['expires_at'], equals('2024-12-31T23:59:00.000'));
      expect(json['is_active'], isTrue);
    });

    test('should deserialize from JSON correctly', () {
      final json = testKey.toJson();
      final deserializedKey = EncryptionKey.fromJson(json);

      expect(deserializedKey.keyId, equals(testKey.keyId));
      expect(deserializedKey.derivationMethod, equals(testKey.derivationMethod));
      expect(deserializedKey.salt, equals(testKey.salt));
      expect(deserializedKey.createdAt, equals(testKey.createdAt));
      expect(deserializedKey.expiresAt, equals(testKey.expiresAt));
      expect(deserializedKey.isActive, equals(testKey.isActive));
    });

    test('should handle null expiration in JSON', () {
      final keyWithoutExpiration = EncryptionKey(
        keyId: 'key_456',
        derivationMethod: 'PBKDF2',
        salt: 'test_salt',
        createdAt: testCreatedAt,
        expiresAt: null,
        isActive: true,
      );

      final json = keyWithoutExpiration.toJson();
      expect(json['expires_at'], isNull);

      final deserialized = EncryptionKey.fromJson(json);
      expect(deserialized.expiresAt, isNull);
    });

    test('should handle missing is_active in JSON with default', () {
      final json = {
        'key_id': 'key_789',
        'derivation_method': 'PBKDF2',
        'salt': 'test_salt',
        'created_at': testCreatedAt.toIso8601String(),
        'expires_at': null,
        // is_active is missing
      };

      final key = EncryptionKey.fromJson(json);
      expect(key.isActive, isTrue); // Should default to true
    });

    test('should implement equality correctly', () {
      final sameKey = EncryptionKey(
        keyId: 'key_123',
        derivationMethod: 'PBKDF2',
        salt: 'test_salt_value',
        createdAt: testCreatedAt,
        expiresAt: testExpiresAt,
        isActive: true,
      );

      expect(testKey == sameKey, isTrue);
      expect(testKey.hashCode, equals(sameKey.hashCode));

      final differentKey = EncryptionKey(
        keyId: 'different_key',
        derivationMethod: 'PBKDF2',
        salt: 'test_salt_value',
        createdAt: testCreatedAt,
        expiresAt: testExpiresAt,
        isActive: true,
      );
      expect(testKey == differentKey, isFalse);
    });
  });

  group('EncryptedData Tests', () {
    late EncryptedData testEncryptedData;
    late List<int> testData;
    late List<int> testIv;
    late List<int> testTag;
    late DateTime testTimestamp;

    setUp(() {
      testData = List.generate(100, (i) => i);
      testIv = List.generate(16, (i) => i);
      testTag = List.generate(16, (i) => i + 100);
      testTimestamp = DateTime(2024, 1, 15, 12, 0);
      testEncryptedData = EncryptedData(
        data: testData,
        iv: testIv,
        tag: testTag,
        algorithm: 'AES-256-GCM',
        checksum: 'test_checksum',
        timestamp: testTimestamp,
      );
    });

    test('should create EncryptedData with all properties', () {
      expect(testEncryptedData.data, equals(testData));
      expect(testEncryptedData.iv, equals(testIv));
      expect(testEncryptedData.tag, equals(testTag));
      expect(testEncryptedData.algorithm, equals('AES-256-GCM'));
      expect(testEncryptedData.checksum, equals('test_checksum'));
      expect(testEncryptedData.timestamp, equals(testTimestamp));
    });

    test('should serialize to JSON correctly', () {
      final json = testEncryptedData.toJson();

      expect(json['data'], equals(testData));
      expect(json['iv'], equals(testIv));
      expect(json['tag'], equals(testTag));
      expect(json['algorithm'], equals('AES-256-GCM'));
      expect(json['checksum'], equals('test_checksum'));
      expect(json['timestamp'], equals('2024-01-15T12:00:00.000'));
    });

    test('should deserialize from JSON correctly', () {
      final json = testEncryptedData.toJson();
      final deserialized = EncryptedData.fromJson(json);

      expect(deserialized.data, equals(testEncryptedData.data));
      expect(deserialized.iv, equals(testEncryptedData.iv));
      expect(deserialized.tag, equals(testEncryptedData.tag));
      expect(deserialized.algorithm, equals(testEncryptedData.algorithm));
      expect(deserialized.checksum, equals(testEncryptedData.checksum));
      expect(deserialized.timestamp, equals(testEncryptedData.timestamp));
    });

    test('should implement equality correctly', () {
      final sameData = EncryptedData(
        data: testData,
        iv: testIv,
        tag: testTag,
        algorithm: 'AES-256-GCM',
        checksum: 'test_checksum',
        timestamp: testTimestamp,
      );

      expect(testEncryptedData == sameData, isTrue);
      expect(testEncryptedData.hashCode, equals(sameData.hashCode));

      final differentData = EncryptedData(
        data: [1, 2, 3], // Different data
        iv: testIv,
        tag: testTag,
        algorithm: 'AES-256-GCM',
        checksum: 'test_checksum',
        timestamp: testTimestamp,
      );
      expect(testEncryptedData == differentData, isFalse);
    });
  });

  group('DeviceInfo Tests', () {
    late DeviceInfo testDeviceInfo;
    late DateTime testRegisteredAt;

    setUp(() {
      testRegisteredAt = DateTime(2024, 1, 15, 14, 0);
      testDeviceInfo = DeviceInfo(
        deviceId: 'device_123',
        platform: 'Android',
        model: 'Pixel 7',
        osVersion: '14.0',
        registeredAt: testRegisteredAt,
      );
    });

    test('should create DeviceInfo with all properties', () {
      expect(testDeviceInfo.deviceId, equals('device_123'));
      expect(testDeviceInfo.platform, equals('Android'));
      expect(testDeviceInfo.model, equals('Pixel 7'));
      expect(testDeviceInfo.osVersion, equals('14.0'));
      expect(testDeviceInfo.registeredAt, equals(testRegisteredAt));
    });

    test('should serialize to JSON correctly', () {
      final json = testDeviceInfo.toJson();

      expect(json['device_id'], equals('device_123'));
      expect(json['platform'], equals('Android'));
      expect(json['model'], equals('Pixel 7'));
      expect(json['os_version'], equals('14.0'));
      expect(json['registered_at'], equals('2024-01-15T14:00:00.000'));
    });

    test('should deserialize from JSON correctly', () {
      final json = testDeviceInfo.toJson();
      final deserialized = DeviceInfo.fromJson(json);

      expect(deserialized.deviceId, equals(testDeviceInfo.deviceId));
      expect(deserialized.platform, equals(testDeviceInfo.platform));
      expect(deserialized.model, equals(testDeviceInfo.model));
      expect(deserialized.osVersion, equals(testDeviceInfo.osVersion));
      expect(deserialized.registeredAt, equals(testDeviceInfo.registeredAt));
    });

    test('should implement equality correctly', () {
      final sameDeviceInfo = DeviceInfo(
        deviceId: 'device_123',
        platform: 'Android',
        model: 'Pixel 7',
        osVersion: '14.0',
        registeredAt: testRegisteredAt,
      );

      expect(testDeviceInfo == sameDeviceInfo, isTrue);
      expect(testDeviceInfo.hashCode, equals(sameDeviceInfo.hashCode));

      final differentDeviceInfo = DeviceInfo(
        deviceId: 'device_456', // Different device ID
        platform: 'Android',
        model: 'Pixel 7',
        osVersion: '14.0',
        registeredAt: testRegisteredAt,
      );
      expect(testDeviceInfo == differentDeviceInfo, isFalse);
    });
  });

  group('EncryptionException Tests', () {
    test('should create EncryptionException with message', () {
      const message = 'Encryption failed';
      final exception = EncryptionException(message);

      expect(exception.message, equals(message));
      expect(exception.code, isNull);
      expect(exception.originalError, isNull);
      expect(exception.toString(), contains(message));
    });

    test('should create EncryptionException with code and original error', () {
      const message = 'Key derivation failed';
      const code = 'ENC_001';
      final originalError = Exception('Key too short');
      final exception = EncryptionException(
        message,
        code: code,
        originalError: originalError,
      );

      expect(exception.message, equals(message));
      expect(exception.code, equals(code));
      expect(exception.originalError, equals(originalError));
      expect(exception.toString(), contains(message));
      expect(exception.toString(), contains(code));
    });
  });

  group('DataIntegrityException Tests', () {
    test('should create DataIntegrityException with message', () {
      const message = 'Data integrity check failed';
      final exception = DataIntegrityException(message);

      expect(exception.message, equals(message));
      expect(exception.expectedChecksum, isNull);
      expect(exception.actualChecksum, isNull);
      expect(exception.toString(), contains(message));
    });

    test('should create DataIntegrityException with checksums', () {
      const message = 'Checksum mismatch';
      const expectedChecksum = 'abc123';
      const actualChecksum = 'def456';
      final exception = DataIntegrityException(
        message,
        expectedChecksum: expectedChecksum,
        actualChecksum: actualChecksum,
      );

      expect(exception.message, equals(message));
      expect(exception.expectedChecksum, equals(expectedChecksum));
      expect(exception.actualChecksum, equals(actualChecksum));
      expect(exception.toString(), contains(message));
      expect(exception.toString(), contains(expectedChecksum));
      expect(exception.toString(), contains(actualChecksum));
    });
  });

  group('Integration Tests', () {
    test('should work together in encryption workflow', () {
      // Create encryption key
      final encryptionKey = EncryptionKey(
        keyId: 'test_key',
        derivationMethod: 'PBKDF2',
        salt: 'test_salt',
        createdAt: DateTime.now(),
      );

      // Create device info
      final deviceInfo = DeviceInfo(
        deviceId: 'device_123',
        platform: 'Android',
        model: 'Test Device',
        osVersion: '14.0',
        registeredAt: DateTime.now(),
      );

      // Create encrypted data
      final encryptedData = EncryptedData(
        data: [1, 2, 3, 4, 5],
        iv: List.generate(16, (i) => i),
        tag: List.generate(16, (i) => i + 100),
        algorithm: 'AES-256-GCM',
        checksum: 'test_checksum',
        timestamp: DateTime.now(),
      );

      expect(encryptionKey.keyId, equals('test_key'));
      expect(deviceInfo.deviceId, equals('device_123'));
      expect(encryptedData.algorithm, equals('AES-256-GCM'));
    });

    test('should handle serialization roundtrip correctly', () {
      final key = EncryptionKey(
        keyId: 'test_key',
        derivationMethod: 'PBKDF2',
        salt: 'test_salt',
        createdAt: DateTime.now(),
      );

      final deviceInfo = DeviceInfo(
        deviceId: 'device_123',
        platform: 'Android',
        model: 'Test Device',
        osVersion: '14.0',
        registeredAt: DateTime.now(),
      );

      final data = EncryptedData(
        data: [1, 2, 3],
        iv: List.generate(16, (i) => i),
        tag: List.generate(16, (i) => i + 100),
        algorithm: 'AES-256-GCM',
        checksum: 'test_checksum',
        timestamp: DateTime.now(),
      );

      // Serialize all objects
      final keyJson = key.toJson();
      final deviceJson = deviceInfo.toJson();
      final dataJson = data.toJson();

      // Deserialize all objects
      final deserializedKey = EncryptionKey.fromJson(keyJson);
      final deserializedDevice = DeviceInfo.fromJson(deviceJson);
      final deserializedData = EncryptedData.fromJson(dataJson);

      // Verify they're equal
      expect(deserializedKey, equals(key));
      expect(deserializedDevice, equals(deviceInfo));
      expect(deserializedData, equals(data));
    });
  });
}