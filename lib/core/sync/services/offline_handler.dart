import 'dart:async';
import '../models/sync_models.dart';
import '../models/sync_exceptions.dart';
import '../../connectivity/services/connectivity_service.dart';

/// Handles graceful degradation for offline scenarios
class OfflineHandler {
  final ConnectivityService _connectivityService;
  final List<PendingOperation> _pendingOperations = [];
  final StreamController<OfflineStatus> _statusController = StreamController<OfflineStatus>.broadcast();

  OfflineHandler(this._connectivityService) {
    _connectivityService.connectivityStream.listen(_onConnectivityChanged);
  }

  Stream<OfflineStatus> get statusStream => _statusController.stream;

  /// Queues an operation for execution when connectivity is restored
  Future<void> queueOperation(PendingOperation operation) async {
    _pendingOperations.add(operation);
    _statusController.add(OfflineStatus(
      isOnline: await _connectivityService.isConnected(),
      pendingOperations: _pendingOperations.length,
      lastAttempt: DateTime.now(),
    ));
  }

  /// Executes all pending operations when connectivity is restored
  Future<List<OperationResult>> executePendingOperations() async {
    if (_pendingOperations.isEmpty) {
      return [];
    }

    final results = <OperationResult>[];
    final operationsToExecute = List<PendingOperation>.from(_pendingOperations);
    _pendingOperations.clear();

    for (final operation in operationsToExecute) {
      try {
        final result = await _executeOperation(operation);
        results.add(result);
      } catch (e) {
        results.add(OperationResult.failure(
          operation.id,
          'Failed to execute pending operation: ${e.toString()}',
        ));
        
        // Re-queue if it's a retryable error
        if (_isRetryableError(e)) {
          _pendingOperations.add(operation);
        }
      }
    }

    _statusController.add(OfflineStatus(
      isOnline: true,
      pendingOperations: _pendingOperations.length,
      lastAttempt: DateTime.now(),
      executedOperations: results.length,
    ));

    return results;
  }

  /// Handles offline mode by providing cached data and queuing operations
  Future<T> handleOfflineOperation<T>(
    String operationId,
    Future<T> Function() onlineOperation,
    T Function() offlineFallback,
  ) async {
    final isConnected = await _connectivityService.isConnected();
    
    if (isConnected) {
      try {
        return await onlineOperation();
      } catch (e) {
        // If online operation fails, fall back to offline mode
        if (_isNetworkError(e)) {
          await queueOperation(PendingOperation(
            id: operationId,
            type: OperationType.sync,
            operation: onlineOperation,
            timestamp: DateTime.now(),
          ));
          return offlineFallback();
        }
        rethrow;
      }
    } else {
      // Queue operation for later execution
      await queueOperation(PendingOperation(
        id: operationId,
        type: OperationType.sync,
        operation: onlineOperation,
        timestamp: DateTime.now(),
      ));
      return offlineFallback();
    }
  }

  /// Provides offline-friendly error messages
  String getOfflineErrorMessage(dynamic error) {
    if (error is NetworkException) {
      switch (error.type) {
        case NetworkErrorType.noInternet:
          return 'No internet connection. Changes will be synced when connection is restored.';
        case NetworkErrorType.timeout:
          return 'Connection timeout. Your changes are saved locally and will be synced later.';
        case NetworkErrorType.serverError:
          return 'Server temporarily unavailable. Working in offline mode.';
        case NetworkErrorType.rateLimited:
          return 'Rate limited. Your changes are queued and will be synced shortly.';
        default:
          return 'Network issue detected. Working in offline mode.';
      }
    }

    if (error is AuthenticationException) {
      return 'Authentication required. Your changes are saved locally.';
    }

    return 'Working in offline mode. Changes will be synced when possible.';
  }

  /// Checks if the app can continue functioning offline
  bool canContinueOffline(String operation) {
    // Define operations that can work offline
    const offlineCapableOperations = {
      'create_patient',
      'update_patient',
      'create_visit',
      'update_visit',
      'create_payment',
      'update_payment',
      'view_data',
      'search_data',
    };

    return offlineCapableOperations.contains(operation);
  }

  /// Gets offline capabilities status
  OfflineCapabilities getOfflineCapabilities() {
    return OfflineCapabilities(
      canCreateRecords: true,
      canUpdateRecords: true,
      canViewRecords: true,
      canSearchRecords: true,
      canBackupData: false,
      canSyncData: false,
      canRestoreData: false,
      estimatedOfflineDays: 30,
    );
  }

  /// Clears all pending operations (use with caution)
  void clearPendingOperations() {
    _pendingOperations.clear();
    _statusController.add(OfflineStatus(
      isOnline: false,
      pendingOperations: 0,
      lastAttempt: DateTime.now(),
    ));
  }

  /// Gets the count of pending operations
  int get pendingOperationsCount => _pendingOperations.length;

  /// Gets the oldest pending operation timestamp
  DateTime? get oldestPendingOperation {
    if (_pendingOperations.isEmpty) return null;
    return _pendingOperations
        .map((op) => op.timestamp)
        .reduce((a, b) => a.isBefore(b) ? a : b);
  }

  void _onConnectivityChanged(bool isConnected) {
    if (isConnected && _pendingOperations.isNotEmpty) {
      // Execute pending operations when connectivity is restored
      executePendingOperations();
    }
    
    _statusController.add(OfflineStatus(
      isOnline: isConnected,
      pendingOperations: _pendingOperations.length,
      lastAttempt: DateTime.now(),
    ));
  }

  Future<OperationResult> _executeOperation(PendingOperation operation) async {
    try {
      await operation.operation();
      return OperationResult.success(operation.id, 'Operation executed successfully');
    } catch (e) {
      return OperationResult.failure(operation.id, e.toString());
    }
  }

  bool _isRetryableError(dynamic error) {
    if (error is NetworkException) {
      switch (error.type) {
        case NetworkErrorType.noInternet:
        case NetworkErrorType.timeout:
        case NetworkErrorType.serverError:
        case NetworkErrorType.connectionRefused:
        case NetworkErrorType.dnsResolutionFailed:
          return true;
        case NetworkErrorType.authenticationFailed:
        case NetworkErrorType.insufficientStorage:
        case NetworkErrorType.rateLimited:
          return false;
      }
    }
    return false;
  }

  bool _isNetworkError(dynamic error) {
    return error is NetworkException || 
           error is AuthenticationException ||
           error.toString().contains('network') ||
           error.toString().contains('connection');
  }

  void dispose() {
    _statusController.close();
  }
}

/// Represents a pending operation to be executed when online
class PendingOperation {
  final String id;
  final OperationType type;
  final Future<dynamic> Function() operation;
  final DateTime timestamp;
  final int retryCount;
  final Map<String, dynamic>? metadata;

  const PendingOperation({
    required this.id,
    required this.type,
    required this.operation,
    required this.timestamp,
    this.retryCount = 0,
    this.metadata,
  });

  PendingOperation copyWith({
    String? id,
    OperationType? type,
    Future<dynamic> Function()? operation,
    DateTime? timestamp,
    int? retryCount,
    Map<String, dynamic>? metadata,
  }) {
    return PendingOperation(
      id: id ?? this.id,
      type: type ?? this.type,
      operation: operation ?? this.operation,
      timestamp: timestamp ?? this.timestamp,
      retryCount: retryCount ?? this.retryCount,
      metadata: metadata ?? this.metadata,
    );
  }
}

enum OperationType {
  sync,
  backup,
  restore,
  upload,
  download,
}

/// Represents the result of executing a pending operation
class OperationResult {
  final String operationId;
  final bool success;
  final String message;
  final DateTime timestamp;
  final dynamic error;

  const OperationResult({
    required this.operationId,
    required this.success,
    required this.message,
    required this.timestamp,
    this.error,
  });

  static OperationResult success(String operationId, String message) {
    return OperationResult(
      operationId: operationId,
      success: true,
      message: message,
      timestamp: DateTime.now(),
    );
  }

  static OperationResult failure(String operationId, String message, {dynamic error}) {
    return OperationResult(
      operationId: operationId,
      success: false,
      message: message,
      timestamp: DateTime.now(),
      error: error,
    );
  }
}

/// Represents the current offline status
class OfflineStatus {
  final bool isOnline;
  final int pendingOperations;
  final DateTime lastAttempt;
  final int? executedOperations;
  final String? lastError;

  const OfflineStatus({
    required this.isOnline,
    required this.pendingOperations,
    required this.lastAttempt,
    this.executedOperations,
    this.lastError,
  });

  Map<String, dynamic> toJson() {
    return {
      'is_online': isOnline,
      'pending_operations': pendingOperations,
      'last_attempt': lastAttempt.toIso8601String(),
      'executed_operations': executedOperations,
      'last_error': lastError,
    };
  }
}

/// Represents offline capabilities of the application
class OfflineCapabilities {
  final bool canCreateRecords;
  final bool canUpdateRecords;
  final bool canViewRecords;
  final bool canSearchRecords;
  final bool canBackupData;
  final bool canSyncData;
  final bool canRestoreData;
  final int estimatedOfflineDays;

  const OfflineCapabilities({
    required this.canCreateRecords,
    required this.canUpdateRecords,
    required this.canViewRecords,
    required this.canSearchRecords,
    required this.canBackupData,
    required this.canSyncData,
    required this.canRestoreData,
    required this.estimatedOfflineDays,
  });

  Map<String, dynamic> toJson() {
    return {
      'can_create_records': canCreateRecords,
      'can_update_records': canUpdateRecords,
      'can_view_records': canViewRecords,
      'can_search_records': canSearchRecords,
      'can_backup_data': canBackupData,
      'can_sync_data': canSyncData,
      'can_restore_data': canRestoreData,
      'estimated_offline_days': estimatedOfflineDays,
    };
  }
}