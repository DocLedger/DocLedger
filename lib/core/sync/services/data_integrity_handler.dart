import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

import '../models/sync_exceptions.dart';
import '../models/sync_models.dart';
import '../../cloud/services/google_drive_service.dart';
import '../../encryption/services/encryption_service.dart';

/// Handles data integrity issues and corruption scenarios
class DataIntegrityHandler {
  final GoogleDriveService _driveService;
  final EncryptionService _encryptionService;

  DataIntegrityHandler(this._driveService, this._encryptionService);

  /// Handles corrupted backup files by attempting recovery
  Future<RestoreResult> handleCorruptedBackup(String backupFileId, String clinicId) async {
    try {
      // Try to download and validate the backup file
      final backupData = await _driveService.downloadBackupFile(backupFileId);
      
      // Attempt to decrypt and validate
      final decryptedData = await _attemptDecryption(backupData, clinicId);
      if (decryptedData != null) {
        final isValid = await _validateBackupIntegrity(decryptedData);
        if (isValid) {
          return RestoreResult.withSuccess(
            message: 'Backup recovered successfully',
            restoredRecords: _countRecords(decryptedData),
          );
        }
      }

      // If current backup is corrupted, try previous backups
      return await _tryPreviousBackups(clinicId);
    } catch (e) {
      return RestoreResult.withError(
        DataIntegrityException(
          'Failed to handle corrupted backup: ${e.toString()}',
          DataIntegrityErrorType.corruptedData,
          originalError: e,
        ),
      );
    }
  }

  /// Validates data integrity using checksums
  Future<bool> validateDataIntegrity(Map<String, dynamic> data) async {
    try {
      final expectedChecksum = data['checksum'] as String?;
      if (expectedChecksum == null) {
        throw DataIntegrityException(
          'Missing checksum in backup data',
          DataIntegrityErrorType.checksumMismatch,
        );
      }

      // Calculate checksum of the data (excluding the checksum field itself)
      final dataWithoutChecksum = Map<String, dynamic>.from(data);
      dataWithoutChecksum.remove('checksum');
      
      final calculatedChecksum = _calculateChecksum(dataWithoutChecksum);
      
      return expectedChecksum == calculatedChecksum;
    } catch (e) {
      throw DataIntegrityException(
        'Failed to validate data integrity: ${e.toString()}',
        DataIntegrityErrorType.checksumMismatch,
        originalError: e,
      );
    }
  }

  /// Handles version mismatch issues
  Future<SyncResult> handleVersionMismatch(
    Map<String, dynamic> localData,
    Map<String, dynamic> remoteData,
  ) async {
    try {
      final localVersion = localData['version'] as int? ?? 1;
      final remoteVersion = remoteData['version'] as int? ?? 1;

      if (localVersion > remoteVersion) {
        // Local data is newer, upload it
        return SyncResult.success(
          message: 'Local version is newer, will upload changes',
        );
      } else if (remoteVersion > localVersion) {
        // Remote data is newer, check if we can migrate
        final canMigrate = await _canMigrateVersion(localVersion, remoteVersion);
        if (canMigrate) {
          return SyncResult.success(
            message: 'Version migration available',
          );
        } else {
          return SyncResult.error(
            DataIntegrityException(
              'Incompatible version: local=$localVersion, remote=$remoteVersion',
              DataIntegrityErrorType.versionMismatch,
            ),
          );
        }
      }

      return SyncResult.success(message: 'Versions match');
    } catch (e) {
      return SyncResult.error(
        DataIntegrityException(
          'Failed to handle version mismatch: ${e.toString()}',
          DataIntegrityErrorType.versionMismatch,
          originalError: e,
        ),
      );
    }
  }

  /// Handles encryption/decryption failures
  Future<SyncResult> handleEncryptionFailure(dynamic error, String operation) async {
    final errorType = operation == 'encrypt' 
        ? DataIntegrityErrorType.encryptionFailed
        : DataIntegrityErrorType.decryptionFailed;

    if (error.toString().contains('Invalid key') || 
        error.toString().contains('Authentication failed')) {
      return SyncResult.requiresReauth(
        message: 'Encryption key validation failed',
        error: DataIntegrityException(
          'Invalid encryption key for $operation',
          errorType,
          originalError: error,
        ),
      );
    }

    if (error.toString().contains('Corrupted data') ||
        error.toString().contains('Invalid format')) {
      return SyncResult.error(
        DataIntegrityException(
          'Data corruption detected during $operation',
          DataIntegrityErrorType.corruptedData,
          originalError: error,
        ),
      );
    }

    return SyncResult.error(
      DataIntegrityException(
        '$operation failed: ${error.toString()}',
        errorType,
        originalError: error,
      ),
    );
  }

  /// Repairs corrupted local data if possible
  Future<RepairResult> repairCorruptedData(String tableName, List<String> corruptedRecordIds) async {
    try {
      final repairedRecords = <String>[];
      final unrepairedRecords = <String>[];

      for (final recordId in corruptedRecordIds) {
        try {
          // Attempt to repair individual record
          final repaired = await _repairRecord(tableName, recordId);
          if (repaired) {
            repairedRecords.add(recordId);
          } else {
            unrepairedRecords.add(recordId);
          }
        } catch (e) {
          unrepairedRecords.add(recordId);
        }
      }

      return RepairResult(
        repairedCount: repairedRecords.length,
        unrepairedCount: unrepairedRecords.length,
        repairedRecords: repairedRecords,
        unrepairedRecords: unrepairedRecords,
      );
    } catch (e) {
      throw DataIntegrityException(
        'Failed to repair corrupted data: ${e.toString()}',
        DataIntegrityErrorType.corruptedData,
        originalError: e,
      );
    }
  }

  /// Quarantines corrupted records
  Future<void> quarantineCorruptedRecords(String tableName, List<String> recordIds) async {
    // Implementation would mark records as quarantined in the database
    // This is a placeholder for the actual database operation
    for (final recordId in recordIds) {
      // Mark record as quarantined in sync_metadata table
      // This would be implemented with actual database calls
    }
  }

  Future<Map<String, dynamic>?> _attemptDecryption(Uint8List encryptedData, String clinicId) async {
    try {
      return await _encryptionService.decryptBackupData(encryptedData, clinicId);
    } catch (e) {
      // Try with different key derivation methods if available
      return null;
    }
  }

  Future<bool> _validateBackupIntegrity(Map<String, dynamic> data) async {
    try {
      // Check required fields
      final requiredFields = ['clinic_id', 'timestamp', 'version', 'tables'];
      for (final field in requiredFields) {
        if (!data.containsKey(field)) {
          return false;
        }
      }

      // Validate checksum
      return await validateDataIntegrity(data);
    } catch (e) {
      return false;
    }
  }

  Future<RestoreResult> _tryPreviousBackups(String clinicId) async {
    try {
      final backupFiles = await _driveService.listBackupFiles();
      
      // Sort by creation time, newest first
      backupFiles.sort((a, b) => b.createdTime!.compareTo(a.createdTime!));
      
      // Skip the first one (current corrupted backup) and try others
      for (int i = 1; i < backupFiles.length; i++) {
        try {
          final backupData = await _driveService.downloadBackupFile(backupFiles[i].id!);
          final decryptedData = await _attemptDecryption(backupData, clinicId);
          
          if (decryptedData != null) {
            final isValid = await _validateBackupIntegrity(decryptedData);
            if (isValid) {
              return RestoreResult.withSuccess(
                message: 'Restored from backup ${i + 1} (${backupFiles[i].name})',
                restoredRecords: _countRecords(decryptedData),
              );
            }
          }
        } catch (e) {
          // Continue to next backup
          continue;
        }
      }

      return RestoreResult.withError(
        DataIntegrityException(
          'All available backups are corrupted',
          DataIntegrityErrorType.corruptedData,
        ),
      );
    } catch (e) {
      return RestoreResult.withError(
        DataIntegrityException(
          'Failed to access previous backups: ${e.toString()}',
          DataIntegrityErrorType.corruptedData,
          originalError: e,
        ),
      );
    }
  }

  String _calculateChecksum(Map<String, dynamic> data) {
    final jsonString = jsonEncode(data);
    final bytes = utf8.encode(jsonString);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<bool> _canMigrateVersion(int fromVersion, int toVersion) async {
    // Define supported migration paths
    const supportedMigrations = {
      1: [2, 3],
      2: [3, 4],
      3: [4],
    };

    if (!supportedMigrations.containsKey(fromVersion)) {
      return false;
    }

    return supportedMigrations[fromVersion]!.contains(toVersion);
  }

  Future<bool> _repairRecord(String tableName, String recordId) async {
    // Placeholder for record repair logic
    // This would involve checking for partial data, applying defaults, etc.
    return false;
  }

  int _countRecords(Map<String, dynamic> data) {
    final tables = data['tables'] as Map<String, dynamic>? ?? {};
    int count = 0;
    for (final tableData in tables.values) {
      if (tableData is List) {
        count += tableData.length;
      }
    }
    return count;
  }
}

/// Result of data repair operation
class RepairResult {
  final int repairedCount;
  final int unrepairedCount;
  final List<String> repairedRecords;
  final List<String> unrepairedRecords;

  RepairResult({
    required this.repairedCount,
    required this.unrepairedCount,
    required this.repairedRecords,
    required this.unrepairedRecords,
  });

  bool get hasUnrepairedRecords => unrepairedCount > 0;
  bool get allRepaired => unrepairedCount == 0;
}