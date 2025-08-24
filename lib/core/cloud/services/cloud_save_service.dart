import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../models/cloud_save_models.dart';
import '../../data/models/data_models.dart';
import '../../data/services/database_service.dart';
import '../../encryption/services/encryption_service.dart';
import '../../encryption/models/encryption_models.dart';
import 'webdav_backup_service.dart';

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
/// - Automatically saves data changes to cloud storage
/// - Uses simple timestamp-based conflict resolution
/// - Encrypts all data by default
/// - Provides clear status updates to users
class CloudSaveService {
  final DatabaseService _database;
  final WebDavBackupService _backup;
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
  // Subscription to DB changes (used for both auto-save scheduling and sync status refresh)
  StreamSubscription? _changesSubscription;
  
  // Periodic sync
  Timer? _periodicSyncTimer;
  static const Duration _periodicSyncInterval = Duration(hours: 1);
  
  // Sync readiness flag
  bool _shouldEnableSync = false;
  
  // Sync-enabled tables
  static const List<String> _syncTables = ['patients', 'visits', 'payments'];
  
  CloudSaveService({
    required DatabaseService database,
    required WebDavBackupService backupService,
    required EncryptionService encryption,
    required String clinicId,
    required String deviceId,
  }) : _database = database,
       _backup = backupService,
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

  // Public accessor for clinic id
  String get clinicId => _clinicId;

  /// Dispose resources
  void dispose() {
    _autoSaveTimer?.cancel();
  _changesSubscription?.cancel();
    _periodicSyncTimer?.cancel();
    _stateController.close();
  }

  /// Initialize the service and load settings
  Future<void> initialize() async {
    try {
      // Load saved settings
      await _loadSettings();
      _log('initialize: autoSaveEnabled=' + _autoSaveEnabled.toString());
      
      // Set initial state
      final lastSaveTime = await _getLastSaveTime();
      _updateState(CloudSaveState.idle(lastSaveTime: lastSaveTime));
      
  // Start listening for data changes (always). The listener will
  // conditionally schedule auto-save based on _autoSaveEnabled, but will
  // always refresh the sync status so the manual Sync button reflects
  // local changes even when auto-save is OFF.
  _startAutoSaveListener();
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
      if (!await _backup.isReady()) {
        _shouldEnableSync = false;
        _log('refreshSyncStatus: not linked');
  // Notify listeners so UI can reflect disabled sync button
  try { _stateController.add(_currentState); } catch (_) {}
  return;
      }
      // Consider any .enc backup under the clinic folder
      var latest = await _backup.getLatestBackup();
      // Fallback: list all and take most recent if direct latest lookup fails
      if (latest == null) {
        final all = await _backup.listBackups();
        if (all.isNotEmpty) {
          latest = all.first;
        }
      }
      final lastSaveTime = await _getLastSaveTime();
      if (latest == null) {
        _shouldEnableSync = true;
        _log('refreshSyncStatus: no cloud backup found; enabling sync');
  try { _stateController.add(_currentState); } catch (_) {}
  return;
      }
      if (lastSaveTime == null) {
        _shouldEnableSync = true;
        _log('refreshSyncStatus: have cloud backup, local has no lastSaveTime; enabling sync');
  try { _stateController.add(_currentState); } catch (_) {}
  return;
      }
  // Consider minor clock differences equal (avoid flapping after a save)
  final diffSeconds = latest.modifiedTime.difference(lastSaveTime).inSeconds;
  final withinTolerance = diffSeconds.abs() <= 10;
  // Enable when either direction differs. If auto-save is OFF, be more
  // permissive and enable even within tolerance so the user can manually
  // sync right after edits. If auto-save is ON, require difference beyond
  // tolerance to avoid immediate re-sync after a save.
  final anyDifference = diffSeconds != 0;
  _shouldEnableSync = _autoSaveEnabled ? (!withinTolerance && anyDifference) : anyDifference;
      _log('refreshSyncStatus: cloud=' + latest.modifiedTime.toIso8601String() + ' local=' + lastSaveTime.toIso8601String() + ' deltaSec=' + diffSeconds.toString() + ' enable=' + _shouldEnableSync.toString());
  // Emit a benign state to trigger UI rebuild with the new shouldEnableSync value
  try { _stateController.add(_currentState); } catch (_) {}
    } catch (_) {
      _shouldEnableSync = false;
  try { _stateController.add(_currentState); } catch (_) {}
    }
  }

  /// One-click sync: decides to upload or restore based on timestamps
  Future<CloudSaveResult> syncNow() async {
    try {
      // Emit an early determinate state so the UI shows progress immediately
      _updateState(CloudSaveState.saving(
        progress: 0.01,
        currentOperation: 'Checking cloud...',
      ));

      await refreshSyncStatus();
      if (!await _backup.isReady()) {
        _log('syncNow: not linked');
        // Reset UI state to idle to avoid a stuck progress indicator
        try {
          final last = await _getLastSaveTime();
          _updateState(CloudSaveState.idle(lastSaveTime: last));
        } catch (_) {
          _updateState(CloudSaveState.idle(lastSaveTime: null));
        }
        return CloudSaveResult.failure('Not linked to cloud storage');
      }
      // Consider any .enc backup under the clinic folder
      var latest = await _backup.getLatestBackup();
      if (latest == null) {
        final all = await _backup.listBackups();
        if (all.isNotEmpty) {
          latest = all.first;
        }
      }
      final lastSaveTime = await _getLastSaveTime();
      if (latest == null) {
        // No cloud backup detected: avoid creating an empty backup if local DB is empty
        if (!await _hasAnyLocalData()) {
          _log('syncNow: no cloud backup and local empty -> failure');
          // Reset UI state to idle to avoid a stuck progress indicator
          try {
            final last = await _getLastSaveTime();
            _updateState(CloudSaveState.idle(lastSaveTime: last));
          } catch (_) {
            _updateState(CloudSaveState.idle(lastSaveTime: null));
          }
          return CloudSaveResult.failure('No cloud backup found to restore');
        }
        _log('syncNow: no cloud backup but local has data -> save');
        return await saveNow();
      }
      if (lastSaveTime == null || latest.modifiedTime.isAfter(lastSaveTime)) {
        _log('syncNow: restoring (cloud newer or no local timestamp). cloud=' + latest.modifiedTime.toIso8601String() + ' local=' + (lastSaveTime?.toIso8601String() ?? 'null'));
        return await restoreFromCloud();
      }
      _log('syncNow: saving (local up-to-date). cloud=' + latest.modifiedTime.toIso8601String() + ' local=' + lastSaveTime.toIso8601String());
      return await saveNow();
    } catch (e) {
      // Reset UI state to idle to avoid a stuck progress indicator
      try {
        final last = await _getLastSaveTime();
        _updateState(CloudSaveState.idle(lastSaveTime: last));
      } catch (_) {
        _updateState(CloudSaveState.idle(lastSaveTime: null));
      }
      return CloudSaveResult.failure(e.toString());
    }
  }

  /// Update auto-save setting
  Future<void> setAutoSaveEnabled(bool enabled) async {
    _autoSaveEnabled = enabled;
    await _saveSettings();
    
    // Keep the change listener always running; it conditionally queues
    // auto-saves. When disabling auto-save, just cancel any pending timer so
    // no background uploads happen, but still refresh sync status on new
    // changes so the manual Sync button reflects them.
    if (!enabled) {
      _stopAutoSaveListener();
    }
    // Recompute sync status immediately to reflect new policy
    try { await refreshSyncStatus(); } catch (_) {}
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
      _log('saveNow: start');
      _updateState(CloudSaveState.saving(currentOperation: 'Starting save'));
      
      // Check authentication
      if (!await _backup.isReady()) {
        throw CloudSaveException('Not linked to cloud storage', code: 'AUTH_REQUIRED');
      }
      
      // Check WiFi requirement
      if (_wifiOnlyMode && !await _isOnWiFi()) {
        throw CloudSaveException('WiFi required for cloud save', code: 'WIFI_REQUIRED');
      }
      
      // Step 1: Export current data
      _updateState(CloudSaveState.saving(
        progress: 0.2,
        currentOperation: 'Preparing data',
      ));
      
      final snapshot = await _database.exportDatabaseSnapshot();
      try {
        final tables = snapshot['tables'] as Map<String, dynamic>?;
        int total = 0;
        if (tables != null) {
          for (final name in _syncTables) {
            total += (tables[name] as List?)?.length ?? 0;
          }
        }
        _log('saveNow: exported snapshot with ' + total.toString() + ' records');
      } catch (_) {}
      
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
  // Use clinic-based shared key so any authorized clinic user can decrypt
  final clinicKeyId = await _backup.getCurrentClinicId();
  final encryptionKey = await _encryption.deriveEncryptionKey(clinicKeyId, clinicKeyId);
      final encryptedData = await _encryption.encryptData(saveData.toJson(), encryptionKey);
      final payloadBytes = utf8.encode(jsonEncode(encryptedData.toJson()));
      
      // Step 4: Upload to cloud
      _updateState(CloudSaveState.saving(
        progress: 0.6,
        currentOperation: 'Uploading to cloud',
      ));
      
  final fileName = _generateSaveFileName(clinicKeyId);
      _log('saveNow: uploading file ' + fileName + ' to clinic folder ' + clinicKeyId);
  // Ensure folder exists to prevent 409/404 on PUT
  await _backup.ensureClinicFolder(clinicKeyId);
      await _backup.uploadBackupFile(
        clinicId: clinicKeyId,
        fileName: fileName,
        bytes: Uint8List.fromList(payloadBytes),
        onProgress: (sent, total) {
          final uploadProgress = 0.6 + (0.3 * (sent / total));
          _updateState(CloudSaveState.saving(
            progress: uploadProgress,
            currentOperation: 'Uploading ($sent/$total bytes)',
          ));
          if (sent == total) {
            _log('saveNow: upload completed, size=' + total.toString());
          }
        },
      );
      
      // Step 5: Clean up old saves (keep last 10)
      _updateState(CloudSaveState.saving(
        progress: 0.9,
        currentOperation: 'Cleaning up old saves',
      ));
      
  // Keep-by-count within clinic folder
  await _backup.cleanupOldBackups(clinicKeyId, keep: 10);
      
      // Step 6: Update metadata
      await _updateSaveMetadata();
      _log('saveNow: completed successfully');
      
      stopwatch.stop();
      
      final result = CloudSaveResult.success(
        duration: stopwatch.elapsed,
        metadata: {
          'file_name': fileName,
          'file_size': payloadBytes.length,
          'tables_saved': _syncTables.length,
        },
      );
      
      final now = DateTime.now();
      _updateState(CloudSaveState.idle(lastSaveTime: now));

      // Notify that data-related metadata changed (e.g., last saved time)
      try {
        _database.notifyDataChanged();
      } catch (_) {}
      
      // Show notification if enabled
      if (_showNotifications) {
        _showSaveNotification('Data saved to cloud successfully');
      }
  // Immediately recompute sync enable state for the UI
  try { await refreshSyncStatus(); } catch (_) {}

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
      _log('restoreFromCloud: start');
      _updateState(CloudSaveState.restoring(currentOperation: 'Starting restore'));
      
      // Check authentication
      if (!await _backup.isReady()) {
        throw CloudSaveException('Not linked to cloud storage', code: 'AUTH_REQUIRED');
      }
      
      // Step 1: Get latest save file
      _updateState(CloudSaveState.restoring(
        progress: 0.1,
        currentOperation: 'Finding latest save',
      ));
      
      // Search latest backup within the clinic folder
      var latest = await _backup.getLatestBackup();
      if (latest == null) {
        final all = await _backup.listBackups();
        if (all.isNotEmpty) {
          latest = all.first;
        }
      }
      if (latest == null) {
        // Strict behavior: no legacy creation; notify via state and return failure
        final msg = 'No cloud saves found';
        _log('restoreFromCloud: ' + msg);
        _updateState(CloudSaveState.error(msg));
        if (_showNotifications) {
          _showSaveNotification('Backup not found', isError: true);
        }
        return CloudSaveResult.failure(msg);
      }
      _log('restoreFromCloud: using file ' + latest.path + ' modified=' + latest.modifiedTime.toIso8601String());
      
      // Step 2: Download save file
      _updateState(CloudSaveState.restoring(
        progress: 0.2,
        currentOperation: 'Downloading from cloud',
      ));
      
      final encryptedBytes = await _backup.downloadBackupFile(latest.path, onProgress: (r, t) {
        final downloadProgress = 0.2 + (0.4 * (r / t));
        _updateState(CloudSaveState.restoring(
          progress: downloadProgress,
          currentOperation: 'Downloading ($r/$t bytes)',
        ));
        if (r == t) {
          _log('restoreFromCloud: download completed, size=' + t.toString());
        }
      });
      
      // Step 3: Decrypt data
      _updateState(CloudSaveState.restoring(
        progress: 0.6,
        currentOperation: 'Decrypting data',
      ));
      
      final parsed = jsonDecode(utf8.decode(encryptedBytes)) as Map<String, dynamic>;
  // Decrypt with clinic-based shared key
  final clinicKeyId = await _backup.getCurrentClinicId();
  final encryptionKey = await _encryption.deriveEncryptionKey(clinicKeyId, clinicKeyId);
      final decryptedData = await _encryption.decryptData(EncryptedData.fromJson(parsed), encryptionKey);
      _log('restoreFromCloud: decryption succeeded');
      
      // Step 4: Validate and parse save data
      _updateState(CloudSaveState.restoring(
        progress: 0.7,
        currentOperation: 'Validating data',
      ));
      
      final cloudData = CloudSaveData.fromJson(decryptedData);
      
      if (!cloudData.validateIntegrity()) {
        throw CloudSaveException(
          'Cloud save data is corrupted',
          code: 'INTEGRITY_FAILED',
        );
      }
      
      // Step 5: Import data using merge (no deletions). Remote newer wins per row; local ties kept.
      _updateState(CloudSaveState.restoring(
        progress: 0.8,
        currentOperation: 'Merging data',
      ));
      await _importDataWithConflictResolution(cloudData);
      _log('restoreFromCloud: merge completed');
      
      // Step 6: Update metadata
      _updateState(CloudSaveState.restoring(
        progress: 0.9,
        currentOperation: 'Updating metadata',
      ));
      
      await _updateSaveMetadata();
      _log('restoreFromCloud: metadata updated; success');
      
      stopwatch.stop();
      
      final result = CloudSaveResult.success(
        duration: stopwatch.elapsed,
        metadata: {
          'save_timestamp': cloudData.timestamp.toIso8601String(),
          'clinic_id': await _backup.getCurrentClinicId(),
          'tables_restored': cloudData.tables.length,
        },
      );
      
      final now = DateTime.now();
      _updateState(CloudSaveState.idle(lastSaveTime: now));

      // Notify app that data has changed so UI can refresh immediately
      try {
        _database.notifyDataChanged();
      } catch (_) {}
      
      // Show notification if enabled
      if (_showNotifications) {
        _showSaveNotification('Data restored from cloud successfully');
      }
  // Immediately recompute sync enable state for the UI
  try { await refreshSyncStatus(); } catch (_) {}

      return result;
      
    } catch (e) {
      stopwatch.stop();
      
      final errorMessage = e is CloudSaveException ? e.message : 'Restore failed: ${e.toString()}';
      _log('restoreFromCloud: ERROR ' + errorMessage);
      
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

  /// Check if any backup exists in cloud for this clinic
  Future<bool> hasAnyCloudBackup() async {
    try {
  // Consider any .enc backup under the clinic folder as eligible
  final latest = await _backup.getLatestBackup();
      return latest != null;
    } catch (_) {
      return false;
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
    // Ensure only one subscription is active
    _changesSubscription?.cancel();
    _changesSubscription = _database.changesStream.listen((_) async {
      if (_autoSaveEnabled) {
        _scheduleAutoSave();
      }
      // Always refresh sync status so manual Sync button updates when there
      // are local edits, regardless of auto-save setting
      try { await refreshSyncStatus(); } catch (_) {}
    });
    // Initial refresh
    // ignore: discarded_futures
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
        // Skip quietly if not linked yet
        if (await _backup.isReady()) {
          await saveNow();
        }
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
      if (metadata != null) {
        // Preferred key written by _updateSaveMetadata via DatabaseService.updateSyncMetadata
        final ts = (metadata['last_sync_timestamp'] ?? metadata['last_save_timestamp']);
        if (ts is int) {
          return DateTime.fromMillisecondsSinceEpoch(ts);
        }
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

  /// Generates a clinic-scoped save file name with timestamp
  String _generateSaveFileName(String clinicId) {
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    return 'docledger_save_${clinicId}_$timestamp.enc';
  }

  /// Heuristic: consider DB empty if exported snapshot has no rows in sync tables
  Future<bool> _hasAnyLocalData() async {
    try {
      final snapshot = await _database.exportDatabaseSnapshot();
      final tables = snapshot['tables'] as Map<String, dynamic>?;
      if (tables == null) return false;
      for (final name in _syncTables) {
        final list = tables[name] as List?;
        if (list != null && list.isNotEmpty) return true;
      }
      return false;
    } catch (_) {
      // If unsure, assume there is data to avoid blocking saves in normal flows
      return true;
    }
  }

  /// Cleans up old save files (keeps last 10)
  Future<void> _cleanupOldSaves() async {
    try {
  await _backup.cleanupOldBackups(await _backup.getCurrentClinicId(), keep: 10);
    } catch (e) {
      // Non-critical error, log but don't fail the save operation
      print('Warning: Failed to cleanup old saves: $e');
    }
  }

  /// Checks if device is connected to WiFi
  Future<bool> _isOnWiFi() async {
    try {
      final connectivity = Connectivity();
      final dynamic res = await connectivity.checkConnectivity();
      Iterable<ConnectivityResult> results;
      if (res is List<ConnectivityResult>) {
        results = res;
      } else if (res is Set<ConnectivityResult>) {
        results = res;
      } else if (res is ConnectivityResult) {
        results = [res];
      } else {
        results = const [];
      }
      // Accept WiFi; also accept Ethernet to avoid blocking desktop users
      if (results.contains(ConnectivityResult.wifi)) return true;
      if (results.contains(ConnectivityResult.ethernet)) return true;
      return false;
    } catch (_) {
      // Fail-open to avoid blocking saves due to platform errors
      return true;
    }
  }

  /// Shows a save notification to the user
  void _showSaveNotification(String message, {bool isError = false}) {
    // TODO: Implement notification system
    // This could use local notifications or in-app notifications
    print('CloudSave Notification: $message');
  }

  // Lightweight internal logger for debugging backup/restore flows
  void _log(String message) {
    // Prefix to make grepping logs easier
    // Avoid throwing if print is unavailable in some contexts
    try {
      // Include a short timestamp for sequencing
      final ts = DateTime.now().toIso8601String();
      // ignore: avoid_print
      print('[CloudSave] ' + ts + ' ' + message);
    } catch (_) {}
  }
}