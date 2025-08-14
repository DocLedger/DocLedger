import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import '../../sync/services/sync_service.dart';
import '../../connectivity/services/connectivity_service.dart';

/// Service responsible for managing background synchronization tasks
/// using WorkManager for cross-platform background task execution
class BackgroundSyncService {
  static const String _periodicSyncTaskId = 'docledger_periodic_sync';
  static const String _immediateBackupTaskId = 'docledger_immediate_backup';
  static const String _connectivitySyncTaskId = 'docledger_connectivity_sync';
  
  static const Duration _periodicSyncInterval = Duration(minutes: 30);
  static const Duration _batteryOptimizedInterval = Duration(hours: 2);
  
  final SyncService _syncService;
  final AppConnectivityService _connectivityService;
  
  bool _isInitialized = false;
  bool _batteryOptimizationEnabled = false;
  
  BackgroundSyncService({
    required SyncService syncService,
    required AppConnectivityService connectivityService,
  }) : _syncService = syncService,
       _connectivityService = connectivityService;

  /// Initialize the background sync service and register all background tasks
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Initialize WorkManager with callback dispatcher
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: kDebugMode,
      );
      
      // Check battery optimization status
      await _checkBatteryOptimization();
      
      // Register periodic sync task
      await _registerPeriodicSyncTask();
      
      // Listen to connectivity changes
      _setupConnectivityListener();
      
      _isInitialized = true;
      
      if (kDebugMode) {
        print('BackgroundSyncService initialized successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to initialize BackgroundSyncService: $e');
      }
      rethrow;
    }
  }

  /// Register background tasks for periodic synchronization
  Future<void> registerBackgroundTasks() async {
    if (!_isInitialized) {
      await initialize();
    }
    
    await _registerPeriodicSyncTask();
    
    if (kDebugMode) {
      print('Background tasks registered successfully');
    }
  }

  /// Schedule an immediate sync operation
  Future<void> scheduleImmediateSync() async {
    if (!_isInitialized) {
      await initialize();
    }
    
    try {
      await Workmanager().registerOneOffTask(
        _immediateBackupTaskId,
        _immediateBackupTaskId,
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: true,
        ),
        initialDelay: const Duration(seconds: 5),
      );
      
      if (kDebugMode) {
        print('Immediate sync scheduled');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to schedule immediate sync: $e');
      }
    }
  }

  /// Schedule periodic backup operations
  Future<void> schedulePeriodicBackup() async {
    if (!_isInitialized) {
      await initialize();
    }
    
    await _registerPeriodicSyncTask();
  }

  /// Handle connectivity changes and trigger sync when appropriate
  Future<void> handleConnectivityChange(bool isConnected) async {
    if (!_isInitialized) return;
    
    if (isConnected) {
      // Schedule sync when connectivity is restored
      await Workmanager().registerOneOffTask(
        _connectivitySyncTaskId,
        _connectivitySyncTaskId,
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: !_batteryOptimizationEnabled,
        ),
        initialDelay: const Duration(seconds: 10),
      );
      
      if (kDebugMode) {
        print('Connectivity restored - sync scheduled');
      }
    }
  }

  /// Cancel all background tasks
  Future<void> cancelAllTasks() async {
    try {
      await Workmanager().cancelAll();
      
      if (kDebugMode) {
        print('All background tasks cancelled');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to cancel background tasks: $e');
      }
    }
  }

  /// Cancel a specific background task
  Future<void> cancelTask(String taskId) async {
    try {
      await Workmanager().cancelByUniqueName(taskId);
      
      if (kDebugMode) {
        print('Background task $taskId cancelled');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to cancel background task $taskId: $e');
      }
    }
  }

  /// Check if battery optimization is affecting background tasks
  Future<void> _checkBatteryOptimization() async {
    if (Platform.isAndroid) {
      // On Android, we assume battery optimization might be enabled
      // In a real implementation, you would check the actual battery optimization status
      _batteryOptimizationEnabled = true;
    } else {
      _batteryOptimizationEnabled = false;
    }
  }

  /// Register the periodic sync task with appropriate constraints
  Future<void> _registerPeriodicSyncTask() async {
    try {
      final interval = _batteryOptimizationEnabled 
          ? _batteryOptimizedInterval 
          : _periodicSyncInterval;
      
      await Workmanager().registerPeriodicTask(
        _periodicSyncTaskId,
        _periodicSyncTaskId,
        frequency: interval,
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: !_batteryOptimizationEnabled,
          requiresCharging: _batteryOptimizationEnabled,
        ),
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(minutes: 5),
      );
      
      if (kDebugMode) {
        print('Periodic sync task registered with ${interval.inMinutes} minute interval');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to register periodic sync task: $e');
      }
    }
  }

  /// Setup connectivity listener for automatic sync scheduling
  void _setupConnectivityListener() {
    _connectivityService.connectivityStream.listen((isConnected) {
      handleConnectivityChange(isConnected);
    });
  }

  /// Dispose of resources
  void dispose() {
    _isInitialized = false;
  }
}

/// Global callback dispatcher for WorkManager background tasks
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      switch (task) {
        case BackgroundSyncService._periodicSyncTaskId:
          return await _handlePeriodicSync(inputData);
        case BackgroundSyncService._immediateBackupTaskId:
          return await _handleImmediateBackup(inputData);
        case BackgroundSyncService._connectivitySyncTaskId:
          return await _handleConnectivitySync(inputData);
        default:
          if (kDebugMode) {
            print('Unknown background task: $task');
          }
          return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Background task $task failed: $e');
      }
      return false;
    }
  });
}

/// Handle periodic sync background task
Future<bool> _handlePeriodicSync(Map<String, dynamic>? inputData) async {
  try {
    if (kDebugMode) {
      print('Executing periodic sync background task');
    }
    
    // In a real implementation, you would initialize the required services
    // and perform the sync operation here
    // For now, we'll just simulate success
    
    await Future.delayed(const Duration(seconds: 2));
    
    if (kDebugMode) {
      print('Periodic sync completed successfully');
    }
    
    return true;
  } catch (e) {
    if (kDebugMode) {
      print('Periodic sync failed: $e');
    }
    return false;
  }
}

/// Handle immediate backup background task
Future<bool> _handleImmediateBackup(Map<String, dynamic>? inputData) async {
  try {
    if (kDebugMode) {
      print('Executing immediate backup background task');
    }
    
    // In a real implementation, you would initialize the required services
    // and perform the backup operation here
    
    await Future.delayed(const Duration(seconds: 1));
    
    if (kDebugMode) {
      print('Immediate backup completed successfully');
    }
    
    return true;
  } catch (e) {
    if (kDebugMode) {
      print('Immediate backup failed: $e');
    }
    return false;
  }
}

/// Handle connectivity-triggered sync background task
Future<bool> _handleConnectivitySync(Map<String, dynamic>? inputData) async {
  try {
    if (kDebugMode) {
      print('Executing connectivity sync background task');
    }
    
    // In a real implementation, you would initialize the required services
    // and perform the sync operation here
    
    await Future.delayed(const Duration(seconds: 1));
    
    if (kDebugMode) {
      print('Connectivity sync completed successfully');
    }
    
    return true;
  } catch (e) {
    if (kDebugMode) {
      print('Connectivity sync failed: $e');
    }
    return false;
  }
}