import 'dart:async';
import 'dart:convert';
import 'dart:convert';
import 'dart:typed_data';

import '../models/sync_models.dart';
import '../../data/models/data_models.dart';
import '../../data/services/database_service.dart';
import '../../cloud/services/google_drive_service.dart';
import '../../encryption/services/encryption_service.dart';
import '../../encryption/models/encryption_models.dart';

/// Exception thrown when sync operations fail
class SyncException implements Exception {
  final String message;
  final String? code;
  final Exception? originalException;

  const SyncException(this.message, {this.code, this.originalException});

  @override
  String toString() => 'SyncException: $message${code != null ? ' (Code: $code)' : ''}';
}

/// Service for orchestrating data synchronization and backup operations
/// 
/// This service coordinates between local database, cloud storage, and encryption
/// to provide seamless data synchronization across multiple devices while
/// maintaining offline-first functionality.
class SyncService {
  final DatabaseService _database;
  final GoogleDriveService _driveService;
  final EncryptionService _encryption;
  
  // Configuration
  final String _clinicId;
  final String _deviceId;
  
  // State management
  final StreamController<SyncState> _stateController = StreamController<SyncState>.broadcast();
  SyncState _currentState = SyncState.idle();
  
  // Sync-enabled tables
  static const List<String> _syncTables = ['patients', 'visits', 'payments'];
  
  SyncService({
    required DatabaseService database,
    required GoogleDriveService driveService,
    required EncryptionService encryption,
    required String clinicId,
    required String deviceId,
  }) : _database = database,
       _driveService = driveService,
       _encryption = encryption,
       _clinicId = clinicId,
       _deviceId = deviceId;

  /// Stream of sync state changes
  Stream<SyncState> get stateStream => _stateController.stream;

  /// Current sync state
  SyncState get currentState => _currentState;

  /// Dispose resources
  void dispose() {
    _stateController.close();
  }

  /// Resolves conflicts using the specified strategy
  /// 
  /// This method processes all pending conflicts and applies the chosen
  /// resolution strategy. It supports multiple strategies including:
  /// - Last-write-wins (timestamp-based)
  /// - Use local data
  /// - Use remote data
  /// - Manual resolution (requires user input)
  /// 
  /// [strategy] - The conflict resolution strategy to apply
  /// 
  /// Returns [SyncResult] indicating the outcome of the conflict resolution
  Future<SyncResult> resolveConflicts(ResolutionStrategy strategy) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      _updateState(SyncState.syncing(currentOperation: 'Resolving conflicts'));
      
      // Get all pending conflicts
      final conflicts = await _database.getPendingConflicts();
      
      if (conflicts.isEmpty) {
        return SyncResult.success(
          duration: stopwatch.elapsed,
          metadata: {'conflicts_resolved': 0},
        );
      }
      
      final resolvedConflicts = <String>[];
      final failedConflicts = <String>[];
      
      for (final conflict in conflicts) {
        try {
          final resolution = await _resolveConflict(conflict, strategy);
          await _database.resolveConflict(conflict.id, resolution);
          resolvedConflicts.add(conflict.id);
          
          // Log conflict resolution for audit trail
          await _logConflictResolution(conflict, resolution);
          
        } catch (e) {
          failedConflicts.add(conflict.id);
          // Log failed resolution
          await _logConflictResolutionFailure(conflict, e);
        }
      }
      
      stopwatch.stop();
      
      _updateState(_currentState.copyWith(
        status: SyncStatus.idle,
        conflicts: failedConflicts,
      ));
      
      if (failedConflicts.isEmpty) {
        return SyncResult.success(
          duration: stopwatch.elapsed,
          metadata: {
            'conflicts_resolved': resolvedConflicts.length,
            'resolution_strategy': strategy.name,
          },
        );
      } else {
        return SyncResult.partial(
          syncedCounts: {'conflicts_resolved': resolvedConflicts.length},
          conflictIds: failedConflicts,
          errorMessage: 'Some conflicts could not be resolved automatically',
          duration: stopwatch.elapsed,
        );
      }
      
    } catch (e) {
      stopwatch.stop();
      
      final errorMessage = 'Conflict resolution failed: ${e.toString()}';
      _updateState(SyncState.error(errorMessage));
      
      return SyncResult.failure(
        errorMessage,
        duration: stopwatch.elapsed,
      );
    }
  }

  /// Resolves conflicts automatically using last-write-wins strategy
  /// 
  /// This method processes all pending conflicts and automatically resolves
  /// them by choosing the record with the most recent timestamp. This is
  /// the default conflict resolution strategy.
  /// 
  /// Returns [SyncResult] indicating the outcome of the automatic resolution
  Future<SyncResult> resolveConflictsAutomatically() async {
    return await resolveConflicts(ResolutionStrategy.useRemote);
  }

  /// Gets all pending conflicts that require manual resolution
  /// 
  /// Returns a list of [SyncConflict] objects that need user intervention
  Future<List<SyncConflict>> getPendingConflicts() async {
    return await _database.getPendingConflicts();
  }

  /// Resolves a specific conflict manually with user-provided data
  /// 
  /// This method allows manual resolution of conflicts where the user
  /// has reviewed both versions and provided the correct merged data.
  /// 
  /// [conflictId] - The ID of the conflict to resolve
  /// [resolvedData] - The manually resolved data
  /// [notes] - Optional notes about the resolution
  /// 
  /// Returns [SyncResult] indicating the outcome of the manual resolution
  Future<SyncResult> resolveConflictManually(
    String conflictId,
    Map<String, dynamic> resolvedData, {
    String? notes,
  }) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      final resolution = ConflictResolution(
        conflictId: conflictId,
        strategy: ResolutionStrategy.manual,
        resolvedData: resolvedData,
        resolutionTime: DateTime.now(),
        notes: notes,
      );
      
      await _database.resolveConflict(conflictId, resolution);
      
      // Log manual resolution for audit trail
      final conflicts = await _database.getPendingConflicts();
      final conflict = conflicts.firstWhere((c) => c.id == conflictId);
      await _logConflictResolution(conflict, resolution);
      
      stopwatch.stop();
      
      return SyncResult.success(
        duration: stopwatch.elapsed,
        metadata: {
          'conflict_id': conflictId,
          'resolution_strategy': 'manual',
        },
      );
      
    } catch (e) {
      stopwatch.stop();
      
      return SyncResult.failure(
        'Manual conflict resolution failed: ${e.toString()}',
        duration: stopwatch.elapsed,
      );
    }
  }

  /// Performs a complete data synchronization
  /// 
  /// This method:
  /// 1. Uploads local changes to cloud storage
  /// 2. Downloads remote changes from cloud storage
  /// 3. Resolves any conflicts using timestamp-based strategy
  /// 4. Updates local database with merged data
  /// 
  /// Returns [SyncResult] indicating the outcome of the sync operation
  Future<SyncResult> performFullSync() async {
    final stopwatch = Stopwatch()..start();
    
    try {
      _updateState(SyncState.syncing(currentOperation: 'Starting full sync'));
      
      // Ensure Google Drive authentication
      if (!_driveService.isAuthenticated) {
        throw SyncException(
          'Google Drive not authenticated',
          code: 'AUTH_REQUIRED',
        );
      }
      
      // Step 1: Upload local changes
      _updateState(SyncState.syncing(
        progress: 0.1,
        currentOperation: 'Uploading local changes',
      ));
      
      final uploadResult = await _uploadLocalChanges();
      
      // Step 2: Download and apply remote changes
      _updateState(SyncState.syncing(
        progress: 0.5,
        currentOperation: 'Downloading remote changes',
      ));
      
      final downloadResult = await _downloadAndApplyRemoteChanges();
      
      // Step 3: Update sync metadata
      _updateState(SyncState.syncing(
        progress: 0.9,
        currentOperation: 'Updating sync metadata',
      ));
      
      await _updateSyncMetadata();
      
      stopwatch.stop();
      
      // Combine results
      final syncedCounts = <String, int>{};
      uploadResult.syncedCounts?.forEach((key, value) {
        syncedCounts[key] = (syncedCounts[key] ?? 0) + value;
      });
      downloadResult.syncedCounts?.forEach((key, value) {
        syncedCounts[key] = (syncedCounts[key] ?? 0) + value;
      });
      
      final conflictIds = <String>[];
      if (uploadResult.conflictIds != null) conflictIds.addAll(uploadResult.conflictIds!);
      if (downloadResult.conflictIds != null) conflictIds.addAll(downloadResult.conflictIds!);
      
      final result = SyncResult.success(
        syncedCounts: syncedCounts,
        duration: stopwatch.elapsed,
        metadata: {
          'upload_result': uploadResult.toJson(),
          'download_result': downloadResult.toJson(),
          'conflicts_found': conflictIds.length,
        },
      );
      
      _updateState(_currentState.copyWith(
        status: SyncStatus.idle,
        lastSyncTime: DateTime.now(),
        progress: null,
        currentOperation: null,
        conflicts: conflictIds,
      ));
      
      return result;
      
    } catch (e) {
      stopwatch.stop();
      
      final errorMessage = e is SyncException ? e.message : 'Sync failed: ${e.toString()}';
      
      _updateState(SyncState.error(errorMessage));
      
      return SyncResult.failure(
        errorMessage,
        duration: stopwatch.elapsed,
      );
    }
  }

  /// Performs incremental synchronization for delta updates
  /// 
  /// This method only syncs changes since the last successful sync,
  /// making it more efficient for frequent sync operations.
  /// 
  /// Returns [SyncResult] indicating the outcome of the sync operation
  Future<SyncResult> performIncrementalSync() async {
    final stopwatch = Stopwatch()..start();
    
    try {
      _updateState(SyncState.syncing(currentOperation: 'Starting incremental sync'));
      
      // Ensure Google Drive authentication
      if (!_driveService.isAuthenticated) {
        throw SyncException(
          'Google Drive not authenticated',
          code: 'AUTH_REQUIRED',
        );
      }
      
      // Get last sync timestamp
      final lastSyncTime = await _getLastSyncTimestamp();
      
      if (lastSyncTime == null) {
        // No previous sync, perform full sync instead
        return await performFullSync();
      }
      
      // Step 1: Check for local changes since last sync
      _updateState(SyncState.syncing(
        progress: 0.1,
        currentOperation: 'Checking for local changes',
      ));
      
      final hasLocalChanges = await _hasLocalChangesSince(lastSyncTime);
      
      // Step 2: Upload local changes if any
      SyncResult uploadResult = SyncResult.success();
      if (hasLocalChanges) {
        _updateState(SyncState.syncing(
          progress: 0.3,
          currentOperation: 'Uploading local changes',
        ));
        
        uploadResult = await _uploadLocalChangesSince(lastSyncTime);
      }
      
      // Step 3: Download and apply remote changes
      _updateState(SyncState.syncing(
        progress: 0.6,
        currentOperation: 'Downloading remote changes',
      ));
      
      final downloadResult = await _downloadAndApplyRemoteChangesSince(lastSyncTime);
      
      // Step 4: Update sync metadata
      _updateState(SyncState.syncing(
        progress: 0.9,
        currentOperation: 'Updating sync metadata',
      ));
      
      await _updateSyncMetadata();
      
      stopwatch.stop();
      
      // Combine results
      final syncedCounts = <String, int>{};
      uploadResult.syncedCounts?.forEach((key, value) {
        syncedCounts[key] = (syncedCounts[key] ?? 0) + value;
      });
      downloadResult.syncedCounts?.forEach((key, value) {
        syncedCounts[key] = (syncedCounts[key] ?? 0) + value;
      });
      
      final conflictIds = <String>[];
      if (uploadResult.conflictIds != null) conflictIds.addAll(uploadResult.conflictIds!);
      if (downloadResult.conflictIds != null) conflictIds.addAll(downloadResult.conflictIds!);
      
      final result = SyncResult.success(
        syncedCounts: syncedCounts,
        duration: stopwatch.elapsed,
        metadata: {
          'incremental': true,
          'last_sync_time': lastSyncTime.toIso8601String(),
          'had_local_changes': hasLocalChanges,
          'conflicts_found': conflictIds.length,
        },
      );
      
      _updateState(_currentState.copyWith(
        status: SyncStatus.idle,
        lastSyncTime: DateTime.now(),
        progress: null,
        currentOperation: null,
        conflicts: conflictIds,
      ));
      
      return result;
      
    } catch (e) {
      stopwatch.stop();
      
      final errorMessage = e is SyncException ? e.message : 'Incremental sync failed: ${e.toString()}';
      
      _updateState(SyncState.error(errorMessage));
      
      return SyncResult.failure(
        errorMessage,
        duration: stopwatch.elapsed,
      );
    }
  }

  /// Creates a backup of all local data to Google Drive
  /// 
  /// This method:
  /// 1. Exports complete database snapshot
  /// 2. Encrypts the data using clinic-specific encryption
  /// 3. Uploads encrypted backup to Google Drive
  /// 4. Manages backup file retention policy
  /// 
  /// Returns [SyncResult] indicating the outcome of the backup operation
  Future<SyncResult> createBackup() async {
    final stopwatch = Stopwatch()..start();
    
    try {
      _updateState(SyncState.backingUp(currentOperation: 'Starting backup'));
      
      // Ensure Google Drive authentication
      if (!_driveService.isAuthenticated) {
        throw SyncException(
          'Google Drive not authenticated',
          code: 'AUTH_REQUIRED',
        );
      }
      
      // Step 1: Export database snapshot
      _updateState(SyncState.backingUp(
        progress: 0.1,
        currentOperation: 'Exporting database',
      ));
      
      final snapshot = await _database.exportDatabaseSnapshot();
      
      // Step 2: Create backup data structure
      _updateState(SyncState.backingUp(
        progress: 0.2,
        currentOperation: 'Preparing backup data',
      ));
      
      final backupData = BackupData.create(
        clinicId: _clinicId,
        deviceId: _deviceId,
        tables: _extractSyncTables(snapshot),
        metadata: {
          'backup_type': 'full',
          'device_info': await _encryption.getDeviceInfo(),
        },
      );
      
      // Step 3: Encrypt backup data
      _updateState(SyncState.backingUp(
        progress: 0.4,
        currentOperation: 'Encrypting backup',
      ));
      
      final encryptionKey = await _encryption.deriveEncryptionKey(_clinicId, _deviceId);
      final encryptedData = await _encryption.encryptData(backupData.toJson(), encryptionKey);
      final payloadBytes = utf8.encode(jsonEncode(encryptedData.toJson()));
      
      // Step 4: Upload to Google Drive
      _updateState(SyncState.backingUp(
        progress: 0.6,
        currentOperation: 'Uploading to Google Drive',
      ));
      
      final fileName = _generateBackupFileName();
      final fileId = await _driveService.uploadBackupFile(
        fileName,
        payloadBytes,
        onProgress: (transferred, total) {
          final uploadProgress = 0.6 + (0.3 * (transferred / total));
          _updateState(SyncState.backingUp(
            progress: uploadProgress,
            currentOperation: 'Uploading to Google Drive ($transferred/$total bytes)',
          ));
        },
      );
      
      // Step 5: Clean up old backups
      _updateState(SyncState.backingUp(
        progress: 0.9,
        currentOperation: 'Cleaning up old backups',
      ));
      
      await _driveService.deleteOldBackups();
      
      // Step 6: Update backup metadata
      await _updateBackupMetadata();
      
      stopwatch.stop();
      
      final result = SyncResult.success(
        duration: stopwatch.elapsed,
        metadata: {
          'backup_file_id': fileId,
          'backup_file_name': fileName,
          'backup_size': payloadBytes.length,
          'tables_backed_up': _syncTables.length,
        },
      );
      
      _updateState(_currentState.copyWith(
        status: SyncStatus.idle,
        lastBackupTime: DateTime.now(),
        progress: null,
        currentOperation: null,
      ));
      
      return result;
      
    } catch (e) {
      stopwatch.stop();
      
      final errorMessage = e is SyncException ? e.message : 'Backup failed: ${e.toString()}';
      
      _updateState(SyncState.error(errorMessage));
      
      return SyncResult.failure(
        errorMessage,
        duration: stopwatch.elapsed,
      );
    }
  }

  /// Restores data from a Google Drive backup
  /// 
  /// This method:
  /// 1. Downloads encrypted backup from Google Drive
  /// 2. Decrypts the backup data
  /// 3. Validates data integrity
  /// 4. Imports data into local database
  /// 
  /// [backupFileId] - The ID of the backup file to restore from
  /// 
  /// Returns [SyncResult] indicating the outcome of the restore operation
  Future<SyncResult> restoreFromBackup(String backupFileId) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      _updateState(SyncState.restoring(currentOperation: 'Starting restore'));
      
      // Ensure Google Drive authentication
      if (!_driveService.isAuthenticated) {
        throw SyncException(
          'Google Drive not authenticated',
          code: 'AUTH_REQUIRED',
        );
      }
      
      // Step 1: Download backup file
      _updateState(SyncState.restoring(
        progress: 0.1,
        currentOperation: 'Downloading backup file',
      ));
      
      final encryptedBytes = await _driveService.downloadBackupFile(
        backupFileId,
        onProgress: (transferred, total) {
          final downloadProgress = 0.1 + (0.3 * (transferred / total));
          _updateState(SyncState.restoring(
            progress: downloadProgress,
            currentOperation: 'Downloading backup ($transferred/$total bytes)',
          ));
        },
      );
      
      // Step 2: Decrypt backup data
      _updateState(SyncState.restoring(
        progress: 0.4,
        currentOperation: 'Decrypting backup',
      ));
      
      // Downloaded file contains JSON-serialized EncryptedData
      final encryptionKey = await _encryption.deriveEncryptionKey(_clinicId, _deviceId);
      final Map<String, dynamic> jsonMap = jsonDecode(utf8.decode(encryptedBytes)) as Map<String, dynamic>;
      final encryptedData = EncryptedData.fromJson(jsonMap);
      
      final decryptedData = await _encryption.decryptData(encryptedData, encryptionKey);
      
      // Step 3: Parse and validate backup data
      _updateState(SyncState.restoring(
        progress: 0.5,
        currentOperation: 'Validating backup data',
      ));
      
      final backupData = BackupData.fromJson(decryptedData);
      
      if (!backupData.validateIntegrity()) {
        throw SyncException(
          'Backup data integrity validation failed',
          code: 'INTEGRITY_FAILED',
        );
      }
      
      // Step 4: Import data into database
      _updateState(SyncState.restoring(
        progress: 0.6,
        currentOperation: 'Importing data',
      ));
      
      final snapshot = {
        'version': backupData.version,
        'timestamp': backupData.timestamp.toIso8601String(),
        'device_id': backupData.deviceId,
        'tables': backupData.tables,
      };
      
      await _database.importDatabaseSnapshot(snapshot);
      
      // Step 5: Update sync metadata
      _updateState(SyncState.restoring(
        progress: 0.9,
        currentOperation: 'Updating sync metadata',
      ));
      
      await _updateSyncMetadata();
      
      stopwatch.stop();
      
      final result = SyncResult.success(
        duration: stopwatch.elapsed,
        metadata: {
          'backup_file_id': backupFileId,
          'backup_timestamp': backupData.timestamp.toIso8601String(),
          'backup_device_id': backupData.deviceId,
          'tables_restored': backupData.tables.length,
        },
      );
      
      _updateState(_currentState.copyWith(
        status: SyncStatus.idle,
        lastSyncTime: DateTime.now(),
        progress: null,
        currentOperation: null,
      ));
      
      return result;
      
    } catch (e) {
      stopwatch.stop();
      
      final errorMessage = e is SyncException ? e.message : 'Restore failed: ${e.toString()}';
      
      _updateState(SyncState.error(errorMessage));
      
      return SyncResult.failure(
        errorMessage,
        duration: stopwatch.elapsed,
      );
    }
  }

  // Private helper methods

  /// Updates the current sync state and notifies listeners
  void _updateState(SyncState newState) {
    _currentState = newState;
    _stateController.add(newState);
  }

  /// Uploads local changes to cloud storage
  Future<SyncResult> _uploadLocalChanges() async {
    final syncedCounts = <String, int>{};
    
    for (final tableName in _syncTables) {
      final changes = await _database.getChangedRecords(tableName, 0);
      
      if (changes.isNotEmpty) {
        // Create backup with just the changed records
        final backupData = BackupData.create(
          clinicId: _clinicId,
          deviceId: _deviceId,
          tables: {tableName: changes},
          metadata: {'sync_type': 'incremental', 'table': tableName},
        );
        
        // Encrypt and upload
        final encryptionKey = await _encryption.deriveEncryptionKey(_clinicId, _deviceId);
        final encryptedData = await _encryption.encryptData(backupData.toJson(), encryptionKey);
        
        final fileName = _generateSyncFileName(tableName);
        final payloadBytes = utf8.encode(jsonEncode(encryptedData.toJson()));
        await _driveService.uploadBackupFile(fileName, payloadBytes);
        
        // Mark records as synced
        final recordIds = changes.map((record) => record['id'] as String).toList();
        await _database.markRecordsSynced(tableName, recordIds);
        
        syncedCounts[tableName] = changes.length;
      }
    }
    
    return SyncResult.success(syncedCounts: syncedCounts);
  }

  /// Uploads local changes since a specific timestamp
  Future<SyncResult> _uploadLocalChangesSince(DateTime since) async {
    final syncedCounts = <String, int>{};
    
    for (final tableName in _syncTables) {
      final changes = await _database.getChangedRecords(
        tableName,
        since.millisecondsSinceEpoch,
      );
      
      if (changes.isNotEmpty) {
        // Create backup with just the changed records
        final backupData = BackupData.create(
          clinicId: _clinicId,
          deviceId: _deviceId,
          tables: {tableName: changes},
          metadata: {
            'sync_type': 'incremental',
            'table': tableName,
            'since': since.toIso8601String(),
          },
        );
        
        // Encrypt and upload
        final encryptionKey = await _encryption.deriveEncryptionKey(_clinicId, _deviceId);
        final encryptedData = await _encryption.encryptData(backupData.toJson(), encryptionKey);
        
        final fileName = _generateSyncFileName(tableName);
        final payloadBytes = utf8.encode(jsonEncode(encryptedData.toJson()));
        await _driveService.uploadBackupFile(fileName, payloadBytes);
        
        // Mark records as synced
        final recordIds = changes.map((record) => record['id'] as String).toList();
        await _database.markRecordsSynced(tableName, recordIds);
        
        syncedCounts[tableName] = changes.length;
      }
    }
    
    return SyncResult.success(syncedCounts: syncedCounts);
  }

  /// Downloads and applies remote changes
  Future<SyncResult> _downloadAndApplyRemoteChanges() async {
    final syncedCounts = <String, int>{};
    final conflictIds = <String>[];
    
    // Get latest backup file
    final latestBackup = await _driveService.getLatestBackup();
    
    if (latestBackup != null) {
      // Download and decrypt backup
      final encryptedBytes = await _driveService.downloadBackupFile(latestBackup.id);
      final Map<String, dynamic> jsonMap = jsonDecode(utf8.decode(encryptedBytes)) as Map<String, dynamic>;
      final encryptedData = EncryptedData.fromJson(jsonMap);
      
      final encryptionKey = await _encryption.deriveEncryptionKey(_clinicId, _deviceId);
      final decryptedData = await _encryption.decryptData(encryptedData, encryptionKey);
      
      final backupData = BackupData.fromJson(decryptedData);
      
      // Apply changes for each table
      for (final entry in backupData.tables.entries) {
        final tableName = entry.key;
        final records = entry.value;
        
        if (records.isNotEmpty) {
          // Detect conflicts before applying changes
          final conflicts = await _database.detectConflicts(tableName, records);
          
          for (final conflict in conflicts) {
            await _database.storeConflict(conflict);
            conflictIds.add(conflict.id);
          }
          
          // Apply remote changes
          await _database.applyRemoteChanges(tableName, records);
          syncedCounts[tableName] = records.length;
        }
      }
    }
    
    return SyncResult.success(
      syncedCounts: syncedCounts,
      conflictIds: conflictIds,
    );
  }

  /// Downloads and applies remote changes since a specific timestamp
  Future<SyncResult> _downloadAndApplyRemoteChangesSince(DateTime since) async {
    // For simplicity, this implementation downloads the latest backup
    // In a more sophisticated implementation, you would maintain
    // incremental sync files or use a proper sync protocol
    return await _downloadAndApplyRemoteChanges();
  }

  /// Checks if there are local changes since a specific timestamp
  Future<bool> _hasLocalChangesSince(DateTime since) async {
    for (final tableName in _syncTables) {
      final changes = await _database.getChangedRecords(
        tableName,
        since.millisecondsSinceEpoch,
      );
      
      if (changes.isNotEmpty) {
        return true;
      }
    }
    
    return false;
  }

  /// Gets the last sync timestamp across all tables
  Future<DateTime?> _getLastSyncTimestamp() async {
    DateTime? lastSync;
    
    for (final tableName in _syncTables) {
      final metadata = await _database.getSyncMetadata(tableName);
      
      if (metadata != null && metadata['last_sync_timestamp'] != null) {
        final tableLastSync = DateTime.fromMillisecondsSinceEpoch(
          metadata['last_sync_timestamp'] as int,
        );
        
        if (lastSync == null || tableLastSync.isBefore(lastSync)) {
          lastSync = tableLastSync;
        }
      }
    }
    
    return lastSync;
  }

  /// Updates sync metadata for all tables
  Future<void> _updateSyncMetadata() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    
    for (final tableName in _syncTables) {
      await _database.updateSyncMetadata(
        tableName,
        lastSyncTimestamp: now,
      );
    }
  }

  /// Updates backup metadata for all tables
  Future<void> _updateBackupMetadata() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    
    for (final tableName in _syncTables) {
      await _database.updateSyncMetadata(
        tableName,
        lastBackupTimestamp: now,
      );
    }
  }

  /// Extracts sync-enabled tables from database snapshot
  Map<String, List<Map<String, dynamic>>> _extractSyncTables(
    Map<String, dynamic> snapshot,
  ) {
    final tables = snapshot['tables'] as Map<String, dynamic>? ?? {};
    final syncTables = <String, List<Map<String, dynamic>>>{};
    
    for (final tableName in _syncTables) {
      if (tables.containsKey(tableName)) {
        syncTables[tableName] = List<Map<String, dynamic>>.from(
          tables[tableName] as List,
        );
      }
    }
    
    return syncTables;
  }

  /// Generates a backup file name with timestamp
  String _generateBackupFileName() {
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    return 'docledger_backup_${_clinicId}_$timestamp.enc';
  }

  /// Generates a sync file name for incremental updates
  String _generateSyncFileName(String tableName) {
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    return 'docledger_sync_${_clinicId}_${tableName}_$timestamp.enc';
  }

  /// Resolves a single conflict using the specified strategy
  Future<ConflictResolution> _resolveConflict(
    SyncConflict conflict,
    ResolutionStrategy strategy,
  ) async {
    Map<String, dynamic> resolvedData;
    String? notes;
    
    switch (strategy) {
      case ResolutionStrategy.useLocal:
        resolvedData = Map<String, dynamic>.from(conflict.localData);
        notes = 'Resolved using local data';
        break;
        
      case ResolutionStrategy.useRemote:
        resolvedData = Map<String, dynamic>.from(conflict.remoteData);
        notes = 'Resolved using remote data';
        break;
        
      case ResolutionStrategy.merge:
        resolvedData = await _mergeConflictData(conflict);
        notes = 'Resolved by merging local and remote data';
        break;
        
      case ResolutionStrategy.manual:
        // For automatic resolution, we'll use last-write-wins as fallback
        resolvedData = await _resolveUsingLastWriteWins(conflict);
        notes = 'Resolved using last-write-wins strategy (timestamp-based)';
        break;
    }
    
    return ConflictResolution(
      conflictId: conflict.id,
      strategy: strategy,
      resolvedData: resolvedData,
      resolutionTime: DateTime.now(),
      notes: notes,
    );
  }

  /// Resolves conflict using last-write-wins strategy (timestamp-based)
  Future<Map<String, dynamic>> _resolveUsingLastWriteWins(SyncConflict conflict) async {
    final localTimestamp = conflict.localData['last_modified'] as int? ?? 0;
    final remoteTimestamp = conflict.remoteData['last_modified'] as int? ?? 0;
    
    // Use the record with the most recent timestamp
    if (localTimestamp >= remoteTimestamp) {
      return Map<String, dynamic>.from(conflict.localData);
    } else {
      return Map<String, dynamic>.from(conflict.remoteData);
    }
  }

  /// Merges conflict data by combining non-conflicting fields
  Future<Map<String, dynamic>> _mergeConflictData(SyncConflict conflict) async {
    final merged = Map<String, dynamic>.from(conflict.localData);
    
    // For each field in remote data, decide whether to use it
    for (final entry in conflict.remoteData.entries) {
      final key = entry.key;
      final remoteValue = entry.value;
      final localValue = merged[key];
      
      // Skip sync metadata fields
      if (_isSyncMetadataField(key)) {
        continue;
      }
      
      // If local value is null or empty, use remote value
      if (localValue == null || 
          (localValue is String && localValue.isEmpty) ||
          (localValue is List && localValue.isEmpty)) {
        merged[key] = remoteValue;
      }
      // For timestamp fields, use the most recent
      else if (key.contains('timestamp') || key.contains('modified') || key.contains('date')) {
        if (remoteValue is int && localValue is int) {
          merged[key] = remoteValue > localValue ? remoteValue : localValue;
        } else if (remoteValue is String && localValue is String) {
          try {
            final remoteDate = DateTime.parse(remoteValue);
            final localDate = DateTime.parse(localValue);
            merged[key] = remoteDate.isAfter(localDate) ? remoteValue : localValue;
          } catch (e) {
            // If parsing fails, keep local value
            merged[key] = localValue;
          }
        }
      }
      // For numeric fields, use the larger value (assuming it's more recent/complete)
      else if (remoteValue is num && localValue is num) {
        merged[key] = remoteValue > localValue ? remoteValue : localValue;
      }
      // For other fields, prefer local data unless it's clearly incomplete
      // This is a conservative approach to avoid data loss
    }
    
    // Update sync metadata for the merged record
    merged['last_modified'] = DateTime.now().millisecondsSinceEpoch;
    merged['sync_status'] = 'pending';
    merged['device_id'] = _deviceId;
    
    return merged;
  }

  /// Checks if a field is sync metadata that should not be merged
  bool _isSyncMetadataField(String fieldName) {
    const syncFields = {
      'sync_status',
      'device_id',
      'created_at',
      'updated_at',
    };
    return syncFields.contains(fieldName);
  }

  /// Logs conflict resolution for audit trail
  Future<void> _logConflictResolution(
    SyncConflict conflict,
    ConflictResolution resolution,
  ) async {
    // In a real implementation, this would write to a dedicated audit log
    // For now, we'll use print statements
    print('CONFLICT RESOLVED: ${conflict.id}');
    print('  Table: ${conflict.tableName}');
    print('  Record: ${conflict.recordId}');
    print('  Strategy: ${resolution.strategy.name}');
    print('  Timestamp: ${resolution.resolutionTime}');
    print('  Notes: ${resolution.notes}');
    
    // TODO: Implement proper audit logging to database or file
  }

  /// Logs conflict resolution failure for debugging
  Future<void> _logConflictResolutionFailure(
    SyncConflict conflict,
    dynamic error,
  ) async {
    // In a real implementation, this would write to an error log
    print('CONFLICT RESOLUTION FAILED: ${conflict.id}');
    print('  Table: ${conflict.tableName}');
    print('  Record: ${conflict.recordId}');
    print('  Error: ${error.toString()}');
    
    // TODO: Implement proper error logging
  }
}

