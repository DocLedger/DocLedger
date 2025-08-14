import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../models/encryption_models.dart';

/// Service for handling encryption and decryption operations using AES-256-GCM
/// 
/// This service provides secure encryption for DocLedger data with the following features:
/// - AES-256-GCM encryption for authenticated encryption
/// - Key derivation using clinic ID and device-specific salt
/// - Data integrity validation with checksums
/// - Unique device ID generation for tracking
class EncryptionService {
  static const String _algorithm = 'AES-256-GCM';
  static const int _keyLength = 32; // 256 bits
  static const int _ivLength = 12; // 96 bits for GCM
  static const int _saltLength = 32; // 256 bits
  
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  final Random _random = Random.secure();

  /// Encrypts data using AES-256-GCM with the provided password
  /// 
  /// [data] - The data to encrypt as a Map
  /// [password] - The password/key for encryption
  /// 
  /// Returns [EncryptedData] containing the encrypted data and metadata
  /// 
  /// Throws [EncryptionException] if encryption fails
  Future<EncryptedData> encryptData(
    Map<String, dynamic> data, 
    String password,
  ) async {
    try {
      // Convert data to JSON bytes
      final jsonString = jsonEncode(data);
      final plainBytes = utf8.encode(jsonString);
      
      // Generate random IV for GCM
      final iv = _generateRandomBytes(_ivLength);
      
      // Derive key from password
      final key = _deriveKeyFromPassword(password);
      
      // Create encrypter with AES-GCM
      final encrypter = Encrypter(AES(Key(key), mode: AESMode.gcm));
      final ivObj = IV(iv);
      
      // Encrypt the data
      final encrypted = encrypter.encrypt(jsonString, iv: ivObj);
      
      // Calculate checksum of original data
      final checksum = _calculateChecksum(plainBytes);
      
      return EncryptedData(
        data: encrypted.bytes.toList(),
        iv: iv.toList(),
        tag: encrypted.bytes.sublist(encrypted.bytes.length - 16).toList(), // GCM tag is last 16 bytes
        algorithm: _algorithm,
        checksum: checksum,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      throw EncryptionException(
        'Failed to encrypt data: ${e.toString()}',
        code: 'ENCRYPTION_FAILED',
        originalError: e,
      );
    }
  }

  /// Decrypts data using AES-256-GCM with the provided password
  /// 
  /// [encryptedData] - The encrypted data container
  /// [password] - The password/key for decryption
  /// 
  /// Returns the decrypted data as a Map
  /// 
  /// Throws [EncryptionException] if decryption fails
  /// Throws [DataIntegrityException] if checksum validation fails
  Future<Map<String, dynamic>> decryptData(
    EncryptedData encryptedData, 
    String password,
  ) async {
    try {
      // Validate algorithm
      if (encryptedData.algorithm != _algorithm) {
        throw EncryptionException(
          'Unsupported encryption algorithm: ${encryptedData.algorithm}',
          code: 'UNSUPPORTED_ALGORITHM',
        );
      }
      
      // Derive key from password
      final key = _deriveKeyFromPassword(password);
      
      // Create encrypter with AES-GCM
      final encrypter = Encrypter(AES(Key(key), mode: AESMode.gcm));
      final ivObj = IV(Uint8List.fromList(encryptedData.iv));
      
      // Create encrypted object for decryption
      final encrypted = Encrypted(Uint8List.fromList(encryptedData.data));
      
      // Decrypt the data
      final decryptedString = encrypter.decrypt(encrypted, iv: ivObj);
      final decryptedBytes = utf8.encode(decryptedString);
      
      // Validate data integrity
      final actualChecksum = _calculateChecksum(decryptedBytes);
      if (actualChecksum != encryptedData.checksum) {
        throw DataIntegrityException(
          'Data integrity check failed',
          expectedChecksum: encryptedData.checksum,
          actualChecksum: actualChecksum,
        );
      }
      
      // Parse JSON and return
      return jsonDecode(decryptedString) as Map<String, dynamic>;
    } catch (e) {
      if (e is EncryptionException || e is DataIntegrityException) {
        rethrow;
      }
      throw EncryptionException(
        'Failed to decrypt data: ${e.toString()}',
        code: 'DECRYPTION_FAILED',
        originalError: e,
      );
    }
  }

  /// Generates a unique device ID for tracking
  /// 
  /// Returns a unique device identifier string
  Future<String> generateDeviceId() async {
    try {
      final deviceInfo = await _getDeviceInfo();
      
      // Create a unique identifier based on device characteristics
      final identifier = '${deviceInfo.platform}_${deviceInfo.model}_${deviceInfo.osVersion}';
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final randomSuffix = _generateRandomString(8);
      
      // Hash the combination to create a consistent but unique ID
      final combined = '$identifier$timestamp$randomSuffix';
      final bytes = utf8.encode(combined);
      final digest = sha256.convert(bytes);
      
      return digest.toString().substring(0, 32); // Use first 32 characters
    } catch (e) {
      // Fallback to random ID if device info fails
      return _generateRandomString(32);
    }
  }

  /// Derives an encryption key using clinic ID and device salt
  /// 
  /// [clinicId] - The clinic identifier
  /// [deviceSalt] - Device-specific salt for key derivation
  /// 
  /// Returns the derived encryption key as a base64 string
  Future<String> deriveEncryptionKey(String clinicId, String deviceSalt) async {
    try {
      // Combine clinic ID and device salt
      final combined = '$clinicId:$deviceSalt';
      final combinedBytes = utf8.encode(combined);
      
      // Use PBKDF2 for key derivation with multiple iterations
      final key = _pbkdf2(combinedBytes, utf8.encode(deviceSalt), 10000, _keyLength);
      
      return base64.encode(key);
    } catch (e) {
      throw EncryptionException(
        'Failed to derive encryption key: ${e.toString()}',
        code: 'KEY_DERIVATION_FAILED',
        originalError: e,
      );
    }
  }

  /// Validates data integrity using checksums
  /// 
  /// [data] - The data to validate
  /// [expectedChecksum] - The expected checksum
  /// 
  /// Returns true if the checksum matches, false otherwise
  Future<bool> validateDataIntegrity(List<int> data, String expectedChecksum) async {
    try {
      final actualChecksum = _calculateChecksum(data);
      return actualChecksum == expectedChecksum;
    } catch (e) {
      return false;
    }
  }

  /// Generates a random salt for key derivation
  /// 
  /// Returns a base64-encoded random salt
  String generateSalt() {
    final saltBytes = _generateRandomBytes(_saltLength);
    return base64.encode(saltBytes);
  }

  /// Gets device information for encryption key derivation
  Future<DeviceInfo> getDeviceInfo() async {
    final deviceInfo = await _getDeviceInfo();
    return deviceInfo;
  }

  // Private helper methods

  /// Derives a key from password using SHA-256
  Uint8List _deriveKeyFromPassword(String password) {
    final passwordBytes = utf8.encode(password);
    final digest = sha256.convert(passwordBytes);
    return Uint8List.fromList(digest.bytes);
  }

  /// Calculates SHA-256 checksum of data
  String _calculateChecksum(List<int> data) {
    final digest = sha256.convert(data);
    return digest.toString();
  }

  /// Generates random bytes of specified length
  Uint8List _generateRandomBytes(int length) {
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
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

  /// Gets device information using device_info_plus
  Future<DeviceInfo> _getDeviceInfo() async {
    try {
      final deviceInfo = await _deviceInfo.deviceInfo;
      
      if (deviceInfo is AndroidDeviceInfo) {
        return DeviceInfo(
          deviceId: deviceInfo.id,
          platform: 'Android',
          model: deviceInfo.model,
          osVersion: deviceInfo.version.release,
          registeredAt: DateTime.now(),
        );
      } else if (deviceInfo is IosDeviceInfo) {
        return DeviceInfo(
          deviceId: deviceInfo.identifierForVendor ?? 'unknown',
          platform: 'iOS',
          model: deviceInfo.model,
          osVersion: deviceInfo.systemVersion,
          registeredAt: DateTime.now(),
        );
      } else if (deviceInfo is WindowsDeviceInfo) {
        return DeviceInfo(
          deviceId: deviceInfo.deviceId,
          platform: 'Windows',
          model: deviceInfo.productName,
          osVersion: deviceInfo.displayVersion,
          registeredAt: DateTime.now(),
        );
      } else if (deviceInfo is LinuxDeviceInfo) {
        return DeviceInfo(
          deviceId: deviceInfo.machineId ?? 'unknown',
          platform: 'Linux',
          model: deviceInfo.prettyName,
          osVersion: deviceInfo.version ?? 'unknown',
          registeredAt: DateTime.now(),
        );
      } else {
        // Fallback for unknown platforms
        return DeviceInfo(
          deviceId: _generateRandomString(16),
          platform: 'Unknown',
          model: 'Unknown',
          osVersion: 'Unknown',
          registeredAt: DateTime.now(),
        );
      }
    } catch (e) {
      // Fallback device info if detection fails
      return DeviceInfo(
        deviceId: _generateRandomString(16),
        platform: 'Unknown',
        model: 'Unknown',
        osVersion: 'Unknown',
        registeredAt: DateTime.now(),
      );
    }
  }

  /// PBKDF2 key derivation function
  Uint8List _pbkdf2(List<int> password, List<int> salt, int iterations, int keyLength) {
    final hmac = Hmac(sha256, password);
    final result = Uint8List(keyLength);
    var resultOffset = 0;
    var blockIndex = 1;

    while (resultOffset < keyLength) {
      // Calculate U1 = PRF(password, salt + blockIndex)
      final block = Uint8List.fromList([...salt, ...[(blockIndex >> 24) & 0xff, (blockIndex >> 16) & 0xff, (blockIndex >> 8) & 0xff, blockIndex & 0xff]]);
      var u = hmac.convert(block).bytes;
      final t = Uint8List.fromList(u);

      // Calculate U2, U3, ... Ui and XOR them
      for (int i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (int j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }

      // Copy the result
      final bytesToCopy = (keyLength - resultOffset < t.length) ? keyLength - resultOffset : t.length;
      result.setRange(resultOffset, resultOffset + bytesToCopy, t);
      resultOffset += bytesToCopy;
      blockIndex++;
    }

    return result;
  }
}