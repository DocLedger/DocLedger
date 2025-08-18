import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../models/cloud_save_models.dart';
import '../../data/models/data_models.dart';
import '../../data/services/database_service.dart';
import 'google_drive_service.dart';
import '../../encryption/services/encryption_service.dart';
import '../../encryption/models/encryption_models.dart';

/// Exception thrown when cloud save operations fail
class CloudSaveException implements Exception {
  final String message;
  final String? code;
  final Exception? originalException;

  const CloudSaveException(this.message, {this.code, this.originalException});

  @override
  String toString() => 'CloudSaveException: $message${code != null ? ' (Code: $code)' : ''}';
}

/// Simplified cloud save service that replaces complex sync/backup system
/// 
/// This service provides a single "auto-save to cloud" functionality that:
/// - Automatically saves data changes to Google Drive
/// - Uses simple timestamp-based conflict resolution
/// - Encrypts all data by default
/// - Provides clear status updates to users
class CloudSaveService {
  final DatabaseService _database;
  final GoogleDriveService _driveService;
  final EncryptionService _encryption;
  
  // Configuration
  final String _clinicId;
  final String _deviceId;
  
  // State management
  final StreamController<CloudSaveState> _stateController = StreamController<CloudSaveState>.broadcast();
  CloudSaveState _currentState = CloudSaveState.idle();
  
  // Auto-save configuration
  bool _autoSaveEnabled = true;
  bool _wifiOnlyMode = true;
  bool _showNotifications = true;
  
  // Debouncing for auto-save
  Timer? _autoSaveTimer;
  static const Duration _autoSaveDelay = Duration(seconds: 30);
  
  // Periodic sync
  Timer? _periodicSyncTimer;
  static const Duration _periodicSyncInterval = Duration(hours: 1);
  
  // Sync readiness flag
  bool _shouldEnableSync = false;
  
  // Sync-enabled tables
  static const List<String> _syncTables = ['patients', 'visits', 'payments'];
  
  CloudSaveService({
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

  /// Stream of cloud save state changes
  Stream<CloudSaveState> get stateStream => _stateController.stream;

  /// Current cloud save state
  CloudSaveState get currentState => _currentState;

  /// Whether auto-save is enabled
  bool get autoSaveEnabled => _autoSaveEnabled;

  /// Whether WiFi-only mode is enabled
  bool get wifiOnlyMode => _wifiOnlyMode;

  /// Whether notifications are enabled
  bool get showNotifications => _showNotifications;

  /// Dispose resources
  void dispose() {
    _autoSaveTimer?.cancel();
    _periodicSyncTimer?.cancel();
    _stateController.close();
  }

  /// Initialize the service and load settings
  Future<void> initialize() async {
    try {
      // Load saved settings
      await _loadSettings();
      
      // Set initial state
      final lastSaveTime = await _getLastSaveTime();
      _updateState(CloudSaveState.idle(lastSaveTime: lastSaveTime));
      
      // Start listening for data changes if auto-save is enabled
      if (_autoSaveEnabled) {
        _startAutoSaveListener();
      }
      // Schedule periodic sync check
      _periodicSyncTimer?.cancel();
      _periodicSyncTimer = Timer.periodic(_periodicSyncInterval, (_) async {
        try {
          await refreshSyncStatus();
          if (_autoSaveEnabled && _shouldEnableSync) {
            await syncNow();
          }
        } catch (_) {}
      });
    } catch (e) {
      print('CloudSaveService initialization error: $e');
      _updateState(CloudSaveState.error('Failed to initialize cloud save: $e'));
      // Don't rethrow - allow the service to be registered even if initialization fails
    }
  }

  /// Whether the Sync button should be enabled
  bool get shouldEnableSync => _shouldEnableSync;

  /// Refresh whether local and cloud are out of sync
  Future<void> refreshSyncStatus() async {
    try {
      if (!_driveService.isAuthenticated) {
        _shouldEnableSync = false;
        return;
      }
      final latest = await _driveService.getLatestBackup();
      final lastSaveTime = await _getLastSaveTime();
      if (latest == null) {
        // No cloud backup yet: enable sync if we have data
        _shouldEnableSync = true;
        return;
      }
      if (lastSaveTime == null) {
        _shouldEnableSync = true;
        return;
      }
      // Enable if drive newer than local or local changed since last save
      _shouldEnableSync = latest.modifiedTime.isAfter(lastSaveTime);
    } catch (_) {
      _shouldEnableSync = false;
    }
  }

  /// One-click sync: decides to upload or restore based on timestamps
  Future<CloudSaveResult> syncNow() async {
    try {
      await refreshSyncStatus();
      if (!_driveService.isAuthenticated) {
        return CloudSaveResult.failure('Google account not linked');
      }
      final latest = await _driveService.getLatestBackup();
      final lastSaveTime = await _getLastSaveTime();
      if (latest == null) {
        return await saveNow();
      }
      if (lastSaveTime == null || latest.modifiedTime.isAfter(lastSaveTime)) {
        return await restoreFromCloud();
      }
      return await saveNow();
    } catch (e) {
      return CloudSaveResult.failure(e.toString());
    }
  }

  /// Update auto-save setting
  Future<void> setAutoSaveEnabled(bool enabled) async {
    _autoSaveEnabled = enabled;
    await _saveSettings();
    
    if (enabled) {
      _startAutoSaveListener();
    } else {
      _stopAutoSaveListener();
    }
  }

  /// Update WiFi-only mode setting
  Future<void> setWifiOnlyMode(bool enabled) async {
    _wifiOnlyMode = enabled;
    await _saveSettings();
  }

  /// Update notifications setting
  Future<void> setShowNotifications(bool enabled) async {
    _showNotifications = enabled;
    await _saveSettings();
  }

  /// Manually trigger a save to cloud
  Future<CloudSaveResult> saveNow() async {
    final stopwatch = Stopwatch()..start();
    
    try {
      _updateState(CloudSaveState.saving(currentOperation: 'Starting save'));
      
      // Check authentication
      if (!_driveService.isAuthenticated) {
        throw CloudSaveException(
          'Google account not linked',
          code: 'AUTH_REQUIRED',
        );
      }
      
      // Check WiFi requirement
      if (_wifiOnlyMode && !await _isOnWiFi()) {
        throw CloudSaveException(
          'WiFi required for cloud save',
          code: 'WIFI_REQUIRED',
        );
      }
      
      // Step 1: Export current data
      _updateState(CloudSaveState.saving(
        progress: 0.2,
        currentOperation: 'Preparing data',
      ));
      
      final snapshot = await _database.exportDatabaseSnapshot();
      
      // Step 2: Create save data structure
      _updateState(CloudSaveState.saving(
        progress: 0.4,
        currentOperation: 'Encrypting data',
      ));
      
      final saveData = CloudSaveData.create(
        clinicId: _clinicId,
        deviceId: _deviceId,
        tables: _extractSyncTables(snapshot),
        metadata: {
          'save_type': 'manual',
          'device_info': await _encryption.getDeviceInfo(),
        },
      );
      
      // Step 3: Encrypt data
      // Use clinic-wide key to keep backups restorable across devices of same clinic
      final encryptionKey = await _encryption.deriveEncryptionKey(_clinicId, _clinicId);
      final encryptedData = await _encryption.encryptData(saveData.toJson(), encryptionKey);
      final payloadBytes = utf8.encode(jsonEncode(encryptedData.toJson()));
      
      // Step 4: Upload to Google Drive
      _updateState(CloudSaveState.saving(
        progress: 0.6,
        currentOperation: 'Uploading to cloud',
      ));
      
      final fileName = _generateSaveFileName();
      final fileId = await _driveService.uploadBackupFile(
        fileName,
        payloadBytes,
        onProgress: (transferred, total) {
          final uploadProgress = 0.6 + (0.3 * (transferred / total));
          _updateState(CloudSaveState.saving(
            progress: uploadProgress,
            currentOperation: 'Uploading ($transferred/$total bytes)',
          ));
        },
      );
      
      // Step 5: Clean up old saves (keep last 10)
      _updateState(CloudSaveState.saving(
        progress: 0.9,
        currentOperation: 'Cleaning up old saves',
      ));
      
      await _cleanupOldSaves();
      
      // Step 6: Update metadata
      await _updateSaveMetadata();
      
      stopwatch.stop();
      
      final result = CloudSaveResult.success(
        duration: stopwatch.elapsed,
        metadata: {
          'file_id': fileId,
          'file_name': fileName,
          'file_size': payloadBytes.length,
          'tables_saved': _syncTables.length,
        },
      );
      
      final now = DateTime.now();
      _updateState(CloudSaveState.idle(lastSaveTime: now));
      
      // Show notification if enabled
      if (_showNotifications) {
        _showSaveNotification('Data saved to cloud successfully');
      }
      
      return result;
      
    } catch (e) {
      stopwatch.stop();
      
      final errorMessage = e is CloudSaveException ? e.message : 'Save failed: ${e.toString()}';
      
      _updateState(CloudSaveState.error(errorMessage));
      
      // Show error notification if enabled
      if (_showNotifications) {
        _showSaveNotification('Failed to save to cloud: $errorMessage', isError: true);
      }
      
      return CloudSaveResult.failure(
        errorMessage,
        duration: stopwatch.elapsed,
      );
    }
  }

  /// Restore data from the most recent cloud save
  Future<CloudSaveResult> restoreFromCloud() async {
    final stopwatch = Stopwatch()..start();
    
    try {
      _updateState(CloudSaveState.restoring(currentOperation: 'Starting restore'));
      
      // Check authentication
      if (!_driveService.isAuthenticated) {
        throw CloudSaveException(
          'Google account not linked',
          code: 'AUTH_REQUIRED',
        );
      }
      
      // Step 1: Get latest save file
      _updateState(CloudSaveState.restoring(
        progress: 0.1,
        currentOperation: 'Finding latest save',
      ));
      
      final latestSave = await _driveService.getLatestBackup();
      if (latestSave == null) {
        throw CloudSaveException(
          'No cloud saves found',
          code: 'NO_SAVES_FOUND',
        );
      }
      
      // Step 2: Download save file
      _updateState(CloudSaveState.restoring(
        progress: 0.2,
        currentOperation: 'Downloading from cloud',
      ));
      
      final encryptedBytes = await _driveService.downloadBackupFile(
        latestSave.id,
        onProgress: (transferred, total) {
          final downloadProgress = 0.2 + (0.4 * (transferred / total));
          _updateState(CloudSaveState.restoring(
            progress: downloadProgress,
            currentOperation: 'Downloading ($transferred/$total bytes)',
          ));
        },
      );
      
      // Step 3: Decrypt data
      _updateState(CloudSaveState.restoring(
        progress: 0.6,
        currentOperation: 'Decrypting data',
      ));
      
      final parsed = jsonDecode(utf8.decode(encryptedBytes)) as Map<String, dynamic>;
      // Try clinic-wide key first; fallback to legacy device-based key for compatibility
      String encryptionKey = await _encryption.deriveEncryptionKey(_clinicId, _clinicId);
      Map<String, dynamic> decryptedData;
      try {
        decryptedData = await _encryption.decryptData(
          EncryptedData.fromJson(parsed),
          encryptionKey,
        );
      } catch (_) {
        // Fallback for older backups encrypted with device-based salt
        final legacyKey = await _encryption.deriveEncryptionKey(_clinicId, _deviceId);
        decryptedData = await _encryption.decryptData(
          EncryptedData.fromJson(parsed),
          legacyKey,
        );
      }
      
      // Step 4: Validate and parse save data
      _updateState(CloudSaveState.restoring(
        progress: 0.7,
        currentOperation: 'Validating data',
      ));
      
      final saveData = CloudSaveData.fromJson(decryptedData);
      
      if (!saveData.validateIntegrity()) {
        throw CloudSaveException(
          'Cloud save data is corrupted',
          code: 'INTEGRITY_FAILED',
        );
      }
      
      // Step 5: Import data with conflict resolution
      _updateState(CloudSaveState.restoring(
        progress: 0.8,
        currentOperation: 'Importing data',
      ));
      
      await _importDataWithConflictResolution(saveData);
      
      // Step 6: Update metadata
      _updateState(CloudSaveState.restoring(
        progress: 0.9,
        currentOperation: 'Updating metadata',
      ));
      
      await _updateSaveMetadata();
      
      stopwatch.stop();
      
      final result = CloudSaveResult.success(
        duration: stopwatch.elapsed,
        metadata: {
          'save_timestamp': saveData.timestamp.toIso8601String(),
          'save_device_id': saveData.deviceId,
          'tables_restored': saveData.tables.length,
        },
      );
      
      final now = DateTime.now();
      _updateState(CloudSaveState.idle(lastSaveTime: now));
      
      // Show notification if enabled
      if (_showNotifications) {
        _showSaveNotification('Data restored from cloud successfully');
      }
      
      return result;
      
    } catch (e) {
      stopwatch.stop();
      
      final errorMessage = e is CloudSaveException ? e.message : 'Restore failed: ${e.toString()}';
      
      _updateState(CloudSaveState.error(errorMessage));
      
      // Show error notification if enabled
      if (_showNotifications) {
        _showSaveNotification('Failed to restore from cloud: $errorMessage', isError: true);
      }
      
      return CloudSaveResult.failure(
        errorMessage,
        duration: stopwatch.elapsed,
      );
    }
  }

  // Private helper methods

  /// Updates the current state and notifies listeners
  void _updateState(CloudSaveState newState) {
    _currentState = newState;
    _stateController.add(newState);
  }

  /// Starts listening for data changes to trigger auto-save
  void _startAutoSaveListener() {
    // Listen to database changes and trigger debounced auto-save
    _database.changesStream.listen((_) {
      if (_autoSaveEnabled) {
        _scheduleAutoSave();
      }
    });
    // Also refresh the sync enable flag on any change
    refreshSyncStatus();
  }

  /// Stops the auto-save listener
  void _stopAutoSaveListener() {
    _autoSaveTimer?.cancel();
  }

  /// Schedules an auto-save with debouncing
  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(_autoSaveDelay, () async {
      if (_autoSaveEnabled && _currentState.status != CloudSaveStatus.saving) {
        await saveNow();
      }
    });
  }

  /// Imports data with automatic conflict resolution (most recent wins)
  Future<void> _importDataWithConflictResolution(CloudSaveData saveData) async {
    for (final entry in saveData.tables.entries) {
      final tableName = entry.key;
      final remoteRecords = entry.value;
      
      for (final remoteRecord in remoteRecords) {
        final recordId = remoteRecord['id'] as String;
        final localRecord = await _database.getRecordById(tableName, recordId);
        
        if (localRecord != null) {
          // Conflict detected - use timestamp to resolve
          DateTime _parseTs(dynamic v) {
            if (v is int) {
              return DateTime.fromMillisecondsSinceEpoch(v);
            }
            if (v is String) {
              // Try ISO first, then numeric
              return DateTime.tryParse(v) ??
                  DateTime.fromMillisecondsSinceEpoch(int.tryParse(v) ?? 0);
            }
            return DateTime.fromMillisecondsSinceEpoch(0);
          }
          final localTimestamp = _parseTs(localRecord['last_modified']);
          final remoteTimestamp = _parseTs(remoteRecord['last_modified']);
          
          if (remoteTimestamp.isAfter(localTimestamp)) {
            // Remote is newer, use remote data
            await _database.updateRecord(tableName, recordId, remoteRecord);
          }
          // If local is newer or equal, keep local data (do nothing)
        } else {
          // No conflict, insert remote record
          await _database.insertRecord(tableName, remoteRecord);
        }
      }
    }
  }

  /// Loads settings from database
  Future<void> _loadSettings() async {
    try {
      final settings = await _database.getSettings('cloud_save');
      if (settings != null) {
        _autoSaveEnabled = settings['auto_save_enabled'] as bool? ?? true;
        _wifiOnlyMode = settings['wifi_only_mode'] as bool? ?? true;
        _showNotifications = settings['show_notifications'] as bool? ?? true;
      }
    } catch (e) {
      print('Failed to load cloud save settings: $e');
      // Use defaults if loading fails
      _autoSaveEnabled = true;
      _wifiOnlyMode = true;
      _showNotifications = true;
    }
  }

  /// Saves settings to database
  Future<void> _saveSettings() async {
    try {
      await _database.saveSettings('cloud_save', {
        'auto_save_enabled': _autoSaveEnabled,
        'wifi_only_mode': _wifiOnlyMode,
        'show_notifications': _showNotifications,
      });
    } catch (e) {
      print('Failed to save cloud save settings: $e');
      // Non-critical error, continue without saving
    }
  }

  /// Gets the last save time from metadata
  Future<DateTime?> _getLastSaveTime() async {
    try {
      final metadata = await _database.getSyncMetadata('cloud_save');
      if (metadata != null && metadata['last_save_timestamp'] != null) {
        return DateTime.fromMillisecondsSinceEpoch(
          metadata['last_save_timestamp'] as int,
        );
      }
    } catch (e) {
      print('Failed to get last save time: $e');
    }
    return null;
  }

  /// Updates save metadata
  Future<void> _updateSaveMetadata() async {
    try {
      await _database.updateSyncMetadata(
        'cloud_save',
        lastSyncTimestamp: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      print('Failed to update save metadata: $e');
      // Non-critical error, continue without updating metadata
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

  /// Generates a save file name with timestamp
  String _generateSaveFileName() {
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    return 'docledger_save_${_clinicId}_$timestamp.enc';
  }

  /// Cleans up old save files (keeps last 10)
  Future<void> _cleanupOldSaves() async {
    try {
      await _driveService.deleteOldBackups();
    } catch (e) {
      // Non-critical error, log but don't fail the save operation
      print('Warning: Failed to cleanup old saves: $e');
    }
  }

  /// Checks if device is connected to WiFi
  Future<bool> _isOnWiFi() async {
    // TODO: Implement WiFi check using connectivity_plus package
    // For now, return true to not block saves
    return true;
  }

  /// Shows a save notification to the user
  void _showSaveNotification(String message, {bool isError = false}) {
    // TODO: Implement notification system
    // This could use local notifications or in-app notifications
    print('CloudSave Notification: $message');
  }
}