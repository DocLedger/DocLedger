/// Encryption models for the DocLedger sync system
/// 
/// This file contains data models used for encryption operations,
/// including encrypted data containers and key management structures.

/// Represents encrypted data with metadata for decryption
class EncryptedData {
  final List<int> data;
  final List<int> iv;
  final List<int> tag;
  final String algorithm;
  final String checksum;
  final DateTime timestamp;

  const EncryptedData({
    required this.data,
    required this.iv,
    required this.tag,
    required this.algorithm,
    required this.checksum,
    required this.timestamp,
  });

  /// Convert to JSON for storage or transmission
  Map<String, dynamic> toJson() {
    return {
      'data': data,
      'iv': iv,
      'tag': tag,
      'algorithm': algorithm,
      'checksum': checksum,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  /// Create from JSON
  factory EncryptedData.fromJson(Map<String, dynamic> json) {
    return EncryptedData(
      data: List<int>.from(json['data']),
      iv: List<int>.from(json['iv']),
      tag: List<int>.from(json['tag']),
      algorithm: json['algorithm'],
      checksum: json['checksum'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EncryptedData &&
          runtimeType == other.runtimeType &&
          data.toString() == other.data.toString() &&
          iv.toString() == other.iv.toString() &&
          tag.toString() == other.tag.toString() &&
          algorithm == other.algorithm &&
          checksum == other.checksum &&
          timestamp == other.timestamp;

  @override
  int get hashCode =>
      data.hashCode ^
      iv.hashCode ^
      tag.hashCode ^
      algorithm.hashCode ^
      checksum.hashCode ^
      timestamp.hashCode;
}

/// Represents encryption key metadata
class EncryptionKey {
  final String keyId;
  final String derivationMethod;
  final String salt;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final bool isActive;

  const EncryptionKey({
    required this.keyId,
    required this.derivationMethod,
    required this.salt,
    required this.createdAt,
    this.expiresAt,
    this.isActive = true,
  });

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'key_id': keyId,
      'derivation_method': derivationMethod,
      'salt': salt,
      'created_at': createdAt.toIso8601String(),
      'expires_at': expiresAt?.toIso8601String(),
      'is_active': isActive,
    };
  }

  /// Create from JSON
  factory EncryptionKey.fromJson(Map<String, dynamic> json) {
    return EncryptionKey(
      keyId: json['key_id'],
      derivationMethod: json['derivation_method'],
      salt: json['salt'],
      createdAt: DateTime.parse(json['created_at']),
      expiresAt: json['expires_at'] != null 
          ? DateTime.parse(json['expires_at']) 
          : null,
      isActive: json['is_active'] ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EncryptionKey &&
          runtimeType == other.runtimeType &&
          keyId == other.keyId &&
          derivationMethod == other.derivationMethod &&
          salt == other.salt &&
          createdAt == other.createdAt &&
          expiresAt == other.expiresAt &&
          isActive == other.isActive;

  @override
  int get hashCode =>
      keyId.hashCode ^
      derivationMethod.hashCode ^
      salt.hashCode ^
      createdAt.hashCode ^
      expiresAt.hashCode ^
      isActive.hashCode;
}

/// Device information for encryption key derivation
class DeviceInfo {
  final String deviceId;
  final String platform;
  final String model;
  final String osVersion;
  final DateTime registeredAt;

  const DeviceInfo({
    required this.deviceId,
    required this.platform,
    required this.model,
    required this.osVersion,
    required this.registeredAt,
  });

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'device_id': deviceId,
      'platform': platform,
      'model': model,
      'os_version': osVersion,
      'registered_at': registeredAt.toIso8601String(),
    };
  }

  /// Create from JSON
  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      deviceId: json['device_id'],
      platform: json['platform'],
      model: json['model'],
      osVersion: json['os_version'],
      registeredAt: DateTime.parse(json['registered_at']),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceInfo &&
          runtimeType == other.runtimeType &&
          deviceId == other.deviceId &&
          platform == other.platform &&
          model == other.model &&
          osVersion == other.osVersion &&
          registeredAt == other.registeredAt;

  @override
  int get hashCode =>
      deviceId.hashCode ^
      platform.hashCode ^
      model.hashCode ^
      osVersion.hashCode ^
      registeredAt.hashCode;
}

/// Exception thrown when encryption operations fail
class EncryptionException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;

  const EncryptionException(
    this.message, {
    this.code,
    this.originalError,
  });

  @override
  String toString() {
    if (code != null) {
      return 'EncryptionException($code): $message';
    }
    return 'EncryptionException: $message';
  }
}

/// Exception thrown when data integrity validation fails
class DataIntegrityException implements Exception {
  final String message;
  final String? expectedChecksum;
  final String? actualChecksum;

  const DataIntegrityException(
    this.message, {
    this.expectedChecksum,
    this.actualChecksum,
  });

  @override
  String toString() {
    if (expectedChecksum != null && actualChecksum != null) {
      return 'DataIntegrityException: $message (expected: $expectedChecksum, actual: $actualChecksum)';
    }
    return 'DataIntegrityException: $message';
  }
}