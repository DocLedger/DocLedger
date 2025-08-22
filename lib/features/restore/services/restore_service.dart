import 'dart:async';
import 'dart:convert';

import '../models/restore_models.dart';
import '../../../core/cloud/services/webdav_backup_service.dart';
import '../../../core/data/services/database_service.dart';
import '../../../core/encryption/services/encryption_service.dart';
import '../../../core/encryption/models/encryption_models.dart';

/// Service for handling data restoration from cloud backups (WebDAV)
class RestoreService {
  final WebDavBackupService _backupService;
  final DatabaseService _database;
  final EncryptionService _encryption;
  final String _clinicId;
  final String _deviceId;

  // State management
  final StreamController<RestoreState> _stateController = StreamController<RestoreState>.broadcast();
  RestoreState _currentState = RestoreState.initial();
  
  // Cancellation support
  bool _isCancelled = false;

  RestoreService({
    required WebDavBackupService backupService,
    required DatabaseService database,
    required EncryptionService encryption,
    required String clinicId,
    required String deviceId,
  }) : _backupService = backupService,
       _database = database,
       _encryption = encryption,
       _clinicId = clinicId,
       _deviceId = deviceId;

  /// Stream of restore state changes
  Stream<RestoreState> get stateStream => _stateController.stream;

  /// Current restore state
  RestoreState get currentState => _currentState;

  /// Dispose resources
  void dispose() {
    _stateController.close();
  }

  /// Start the device setup wizard and restoration flow
  Future<RestoreResult> startDeviceSetupWizard() async {
    final stopwatch = Stopwatch()..start();
    
    try {
      _isCancelled = false;
      _updateState(RestoreState.initial());

      // Step 1: Check WebDAV readiness
      if (!await _backupService.isReady()) {
        throw RestoreException(
          'Not linked to cloud storage',
          code: 'AUTH_REQUIRED',
        );
      }

      // Step 2: List available backups
      _updateState(RestoreState.restoring(operation: 'Searching for backups', progress: 0.1));
      
      final availableBackups = await _getAvailableBackups();
      
      if (availableBackups.isEmpty) {
        stopwatch.stop();
        // Strict: show backup not found via state; return failure
        final msg = 'No backups found in cloud storage';
        _updateState(RestoreState.error(msg));
        return RestoreResult.failure(
          duration: stopwatch.elapsed,
          errorMessage: msg,
        );
      }

      // Step 3: Present backup selection to user
      _updateState(RestoreState.selectingBackup(availableBackups));
      
      // Wait for user to select a backup (handled by UI). Default to latest valid backup
      final selectedBackup = availableBackups.firstWhere(
        (backup) => backup.isValid,
        orElse: () => availableBackups.first,
      );

      // Step 4: Perform restoration
      final result = await restoreFromBackup(selectedBackup.id);
      
      stopwatch.stop();
      
      if (result.success) {
        _updateState(RestoreState.completed(result));
      } else {
        _updateState(RestoreState.error(result.errorMessage ?? 'Restoration failed'));
      }
      
      return result;
      
    } catch (e) {
      stopwatch.stop();
      
      final errorMessage = e is RestoreException ? e.message : 'Device setup failed: ${e.toString()}';
      _updateState(RestoreState.error(errorMessage));
      
      return RestoreResult.failure(
        duration: stopwatch.elapsed,
        errorMessage: errorMessage,
      );
    }
  }

  /// Get list of available backups with validation
  Future<List<RestoreBackupInfo>> getAvailableBackups() async {
    return await _getAvailableBackups();
  }

  /// Restore data from a specific backup file (id == WebDAV file path)
  Future<RestoreResult> restoreFromBackup(String backupFilePath) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      _isCancelled = false;
      
      // Step 1: Validate backup file
      _updateState(RestoreState.restoring(
        operation: 'Validating backup file',
        progress: 0.1,
      ));
      
      if (_isCancelled) throw RestoreException('Restoration cancelled by user');
      
      final isValid = await _validateBackupFile(backupFilePath);
      if (!isValid) {
        throw RestoreException(
          'Backup file validation failed',
          code: 'VALIDATION_FAILED',
        );
      }

      // Step 2: Download backup file
      _updateState(RestoreState.restoring(
        operation: 'Downloading backup file',
        progress: 0.2,
      ));
      
      if (_isCancelled) throw RestoreException('Restoration cancelled by user');
      
      final encryptedBytes = await _backupService.downloadBackupFile(
        backupFilePath,
        onProgress: (transferred, total) {
          if (_isCancelled) return;
          final downloadProgress = 0.2 + (0.3 * (total == 0 ? 0 : (transferred / total)));
          _updateState(RestoreState.restoring(
            operation: 'Downloading backup ($transferred/$total bytes)',
            progress: downloadProgress,
          ));
        },
      );

      // Step 3: Decrypt backup data
      _updateState(RestoreState.restoring(
        operation: 'Decrypting backup data',
        progress: 0.5,
      ));
      
      if (_isCancelled) throw RestoreException('Restoration cancelled by user');
      
      final decryptedData = await _decryptBackupData(encryptedBytes);

      // Step 4: Validate decrypted data integrity
      _updateState(RestoreState.restoring(
        operation: 'Validating data integrity',
        progress: 0.6,
      ));
      
      if (_isCancelled) throw RestoreException('Restoration cancelled by user');
      
      final backupData = BackupData.fromJson(decryptedData);
      if (!backupData.validateIntegrity()) {
        throw RestoreException(
          'Backup data integrity validation failed',
          code: 'INTEGRITY_FAILED',
        );
      }

      // Step 5: Import data into database
      _updateState(RestoreState.restoring(
        operation: 'Importing data into database',
        progress: 0.7,
      ));
      
      if (_isCancelled) throw RestoreException('Restoration cancelled by user');
      
      final restoredCounts = await _importBackupData(backupData);

      // Step 6: Update sync metadata
      _updateState(RestoreState.restoring(
        operation: 'Updating sync metadata',
        progress: 0.9,
      ));
      
      if (_isCancelled) throw RestoreException('Restoration cancelled by user');
      
      await _updateSyncMetadataAfterRestore();

      stopwatch.stop();

      final result = RestoreResult.success(
        duration: stopwatch.elapsed,
        restoredCounts: restoredCounts,
        metadata: {
          'backup_file_path': backupFilePath,
          'backup_timestamp': backupData.timestamp.toIso8601String(),
          'backup_device_id': backupData.deviceId,
          'tables_restored': backupData.tables.length,
        },
      );

      _updateState(RestoreState.completed(result));
      return result;
      
    } catch (e) {
      stopwatch.stop();
      
      final errorMessage = e is RestoreException ? e.message : 'Restoration failed: ${e.toString()}';
      _updateState(RestoreState.error(errorMessage));
      
      return RestoreResult.failure(
        duration: stopwatch.elapsed,
        errorMessage: errorMessage,
      );
    }
  }

  /// Handle partial restoration scenarios gracefully
  Future<RestoreResult> handlePartialRestore(String backupFilePath, {
    List<String>? tablesToRestore,
    bool skipCorruptedTables = true,
  }) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      _isCancelled = false;
      
      // Download and decrypt backup
      _updateState(RestoreState.restoring(
        operation: 'Preparing partial restoration',
        progress: 0.1,
      ));
      
      final encryptedBytes = await _backupService.downloadBackupFile(backupFilePath);
      final decryptedData = await _decryptBackupData(encryptedBytes);
      final backupData = BackupData.fromJson(decryptedData);

      // Filter tables to restore
      final tablesToProcess = tablesToRestore ?? backupData.tables.keys.toList();
      final restoredCounts = <String, int>{};
      final failedTables = <String>[];

      for (int i = 0; i < tablesToProcess.length; i++) {
        if (_isCancelled) throw RestoreException('Restoration cancelled by user');
        
        final tableName = tablesToProcess[i];
        final progress = 0.2 + (0.7 * (i / tablesToProcess.length));
        
        _updateState(RestoreState.restoring(
          operation: 'Restoring $tableName table',
          progress: progress,
        ));

        try {
          if (backupData.tables.containsKey(tableName)) {
            final records = backupData.tables[tableName]!;
            await _database.applyRemoteChanges(tableName, records);
            restoredCounts[tableName] = records.length;
          }
        } catch (e) {
          failedTables.add(tableName);
          if (!skipCorruptedTables) {
            throw RestoreException(
              'Failed to restore table $tableName: ${e.toString()}',
              code: 'TABLE_RESTORE_FAILED',
            );
          }
        }
      }

      await _updateSyncMetadataAfterRestore();
      
      stopwatch.stop();

      final result = RestoreResult.success(
        duration: stopwatch.elapsed,
        restoredCounts: restoredCounts,
        metadata: {
          'backup_file_path': backupFilePath,
          'partial_restore': true,
          'failed_tables': failedTables,
          'tables_requested': tablesToProcess.length,
          'tables_restored': restoredCounts.length,
        },
      );

      _updateState(RestoreState.completed(result));
      return result;
      
    } catch (e) {
      stopwatch.stop();
      
      final errorMessage = e is RestoreException ? e.message : 'Partial restoration failed: ${e.toString()}';
      _updateState(RestoreState.error(errorMessage));
      
      return RestoreResult.failure(
        duration: stopwatch.elapsed,
        errorMessage: errorMessage,
      );
    }
  }

  /// Cancel ongoing restoration
  void cancelRestore() {
    _isCancelled = true;
    _updateState(RestoreState.cancelled());
  }

  /// Select a backup for restoration (called by UI)
  void selectBackup(RestoreBackupInfo backup) {
    if (_currentState.status == RestoreStatus.selectingBackup) {
      _updateState(_currentState.copyWith(selectedBackup: backup));
    }
  }

  // Private helper methods

  /// Get list of available backups with validation
  Future<List<RestoreBackupInfo>> _getAvailableBackups() async {
    try {
      final files = await _backupService.listBackups(_clinicId);
      final restoreBackups = <RestoreBackupInfo>[];

      for (final file in files) {
        // Basic validation - check if file name matches expected pattern
        final name = Uri.decodeComponent(file.path.split('/').last);
        bool isValid = true;
        String? validationError;

        if (!name.contains(_clinicId)) {
          isValid = false;
          validationError = 'Backup does not belong to this clinic';
        } else if (!name.endsWith('.enc')) {
          isValid = false;
          validationError = 'Invalid backup file format';
        }

        restoreBackups.add(RestoreBackupInfo(
          id: file.path,
          name: name,
          size: 0,
          createdTime: file.modifiedTime,
          modifiedTime: file.modifiedTime,
          description: null,
          isValid: isValid,
          validationError: validationError,
        ));
      }

      // Sort by modification time (newest first)
      restoreBackups.sort((a, b) => b.createdTime.compareTo(a.createdTime));

      return restoreBackups;
    } catch (e) {
      throw RestoreException(
        'Failed to get available backups: ${e.toString()}',
        originalException: e is Exception ? e : Exception(e.toString()),
      );
    }
  }

  /// Validate backup file before restoration
  Future<bool> _validateBackupFile(String backupFilePath) async {
    try {
      // Basic validation checks
      final name = backupFilePath.split('/').last;
      if (!name.endsWith('.enc')) {
        throw RestoreException('Invalid backup file format');
      }
      if (!name.contains(_clinicId)) {
        throw RestoreException('Backup does not belong to this clinic');
      }

      // Try to download to verify accessibility
      try {
        await _backupService.downloadBackupFile(backupFilePath);
      } catch (e) {
        throw RestoreException('Backup file is not accessible or corrupted');
      }

      return true;
    } catch (e) {
      if (e is RestoreException) rethrow;
      throw RestoreException(
        'Backup validation failed: ${e.toString()}',
        originalException: e is Exception ? e : Exception(e.toString()),
      );
    }
  }

  /// Decrypt backup data
  Future<Map<String, dynamic>> _decryptBackupData(List<int> encryptedBytes) async {
    try {
      // Stored payload is JSON of EncryptedData
      final parsed = jsonDecode(utf8.decode(encryptedBytes)) as Map<String, dynamic>;
      final encryptedData = EncryptedData.fromJson(parsed);

      // Strict: only username-based shared key
      final usernameForKey = await _backupService.getCurrentUsernameFolder();
      final userKey = await _encryption.deriveEncryptionKey(usernameForKey, usernameForKey);
      return await _encryption.decryptData(encryptedData, userKey);
    } catch (e) {
      throw RestoreException(
        'Failed to decrypt backup data: ${e.toString()}',
        code: 'DECRYPTION_FAILED',
        originalException: e is Exception ? e : Exception(e.toString()),
      );
    }
  }

  /// Import backup data into database
  Future<Map<String, int>> _importBackupData(BackupData backupData) async {
    try {
      final snapshot = {
        'version': backupData.version,
        'timestamp': backupData.timestamp.toIso8601String(),
        'device_id': backupData.deviceId,
        'tables': backupData.tables,
      };

      await _database.importDatabaseSnapshot(snapshot);

      // Count restored records
      final restoredCounts = <String, int>{};
      for (final entry in backupData.tables.entries) {
        restoredCounts[entry.key] = entry.value.length;
      }

      return restoredCounts;
    } catch (e) {
      throw RestoreException(
        'Failed to import backup data: ${e.toString()}',
        code: 'IMPORT_FAILED',
        originalException: e is Exception ? e : Exception(e.toString()),
      );
    }
  }

  /// Update sync metadata after successful restore
  Future<void> _updateSyncMetadataAfterRestore() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // Update sync metadata for all restored tables
    for (final tableName in ['patients', 'visits', 'payments']) {
      await _database.updateSyncMetadata(
        tableName,
        lastSyncTimestamp: now,
      );
    }
  }

  /// Update the current restore state and notify listeners
  void _updateState(RestoreState newState) {
    _currentState = newState;
    _stateController.add(newState);
  }
}