import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Service for monitoring network connectivity and managing network-aware operations
class AppConnectivityService {
  final Connectivity _connectivity = Connectivity();
  
  StreamController<bool>? _connectivityController;
  StreamController<ConnectivityType>? _connectivityTypeController;
  StreamController<bool>? _wifiController;
  
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  
  ConnectivityResult _currentConnectivity = ConnectivityResult.none;
  bool _isConnected = false;
  bool _isWifiConnected = false;
  bool _wifiPreferredSync = true;
  
  final List<NetworkOperation> _queuedOperations = [];
  bool _isProcessingQueue = false;

  /// Stream that emits connectivity status changes (true = connected, false = disconnected)
  Stream<bool> get connectivityStream {
    _connectivityController ??= StreamController<bool>.broadcast();
    return _connectivityController!.stream;
  }

  /// Stream that emits detailed connectivity type changes
  Stream<ConnectivityType> get connectivityTypeStream {
    _connectivityTypeController ??= StreamController<ConnectivityType>.broadcast();
    return _connectivityTypeController!.stream;
  }

  /// Stream that emits WiFi connectivity status changes
  Stream<bool> get wifiStream {
    _wifiController ??= StreamController<bool>.broadcast();
    return _wifiController!.stream;
  }

  /// Current connectivity status
  bool get isConnected => _isConnected;

  /// Current connectivity type
  ConnectivityResult get currentConnectivity => _currentConnectivity;

  /// Whether currently connected to WiFi
  bool get isWifiConnected => _isWifiConnected;

  /// Whether WiFi-preferred sync is enabled
  bool get wifiPreferredSync => _wifiPreferredSync;

  /// Set WiFi-preferred sync preference
  set wifiPreferredSync(bool enabled) {
    _wifiPreferredSync = enabled;
    if (kDebugMode) {
      print('WiFi-preferred sync ${enabled ? 'enabled' : 'disabled'}');
    }
  }

  /// Number of queued operations waiting for connectivity
  int get queuedOperationsCount => _queuedOperations.length;

  /// Initialize the connectivity service and start monitoring
  Future<void> initialize() async {
    try {
      // Get initial connectivity status
      final connectivityResults = await _connectivity.checkConnectivity();
      final connectivityResult = connectivityResults.isNotEmpty 
          ? connectivityResults.first 
          : ConnectivityResult.none;
      
      _updateConnectivityStatus(connectivityResult);
      
      // Start listening to connectivity changes
      _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
        (List<ConnectivityResult> results) {
          final result = results.isNotEmpty ? results.first : ConnectivityResult.none;
          _updateConnectivityStatus(result);
        },
        onError: (error) {
          if (kDebugMode) {
            print('Connectivity monitoring error: $error');
          }
        },
      );
      
      if (kDebugMode) {
        print('ConnectivityService initialized - Current status: $_currentConnectivity');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to initialize ConnectivityService: $e');
      }
      rethrow;
    }
  }

  /// Check if sync should proceed based on connectivity and preferences
  bool shouldProceedWithSync() {
    if (!_isConnected) {
      return false;
    }
    
    if (_wifiPreferredSync) {
      return _isWifiConnected;
    }
    
    return true;
  }

  /// Queue a network operation to be executed when connectivity is available
  void queueOperation(NetworkOperation operation) {
    _queuedOperations.add(operation);
    
    if (kDebugMode) {
      print('Operation queued: ${operation.id} (${_queuedOperations.length} total)');
    }
    
    // Try to process queue if connected
    if (_isConnected && shouldProceedWithSync()) {
      _processQueuedOperations();
    }
  }

  /// Remove a queued operation
  bool removeQueuedOperation(String operationId) {
    final initialLength = _queuedOperations.length;
    _queuedOperations.removeWhere((op) => op.id == operationId);
    final removed = initialLength - _queuedOperations.length;
    
    if (kDebugMode && removed > 0) {
      print('Operation removed from queue: $operationId');
    }
    
    return removed > 0;
  }

  /// Clear all queued operations
  void clearQueue() {
    final count = _queuedOperations.length;
    _queuedOperations.clear();
    
    if (kDebugMode && count > 0) {
      print('Cleared $count queued operations');
    }
  }

  /// Get connectivity type information
  ConnectivityType getConnectivityType() {
    switch (_currentConnectivity) {
      case ConnectivityResult.wifi:
        return ConnectivityType.wifi;
      case ConnectivityResult.mobile:
        return ConnectivityType.mobile;
      case ConnectivityResult.ethernet:
        return ConnectivityType.ethernet;
      case ConnectivityResult.bluetooth:
        return ConnectivityType.bluetooth;
      case ConnectivityResult.vpn:
        return ConnectivityType.vpn;
      case ConnectivityResult.other:
        return ConnectivityType.other;
      case ConnectivityResult.none:
      default:
        return ConnectivityType.none;
    }
  }

  /// Get network quality estimation based on connectivity type
  NetworkQuality getNetworkQuality() {
    switch (_currentConnectivity) {
      case ConnectivityResult.wifi:
      case ConnectivityResult.ethernet:
        return NetworkQuality.high;
      case ConnectivityResult.mobile:
        return NetworkQuality.medium;
      case ConnectivityResult.bluetooth:
      case ConnectivityResult.vpn:
        return NetworkQuality.low;
      case ConnectivityResult.other:
        return NetworkQuality.unknown;
      case ConnectivityResult.none:
      default:
        return NetworkQuality.none;
    }
  }

  /// Update connectivity status and notify listeners
  void _updateConnectivityStatus(ConnectivityResult result) {
    final wasConnected = _isConnected;
    final wasWifiConnected = _isWifiConnected;
    
    _currentConnectivity = result;
    _isConnected = result != ConnectivityResult.none;
    _isWifiConnected = result == ConnectivityResult.wifi;
    
    // Notify connectivity status changes
    if (wasConnected != _isConnected) {
      _connectivityController?.add(_isConnected);
      
      if (kDebugMode) {
        print('Connectivity changed: ${_isConnected ? 'Connected' : 'Disconnected'} ($_currentConnectivity)');
      }
    }
    
    // Notify WiFi status changes
    if (wasWifiConnected != _isWifiConnected) {
      _wifiController?.add(_isWifiConnected);
      
      if (kDebugMode) {
        print('WiFi status changed: ${_isWifiConnected ? 'Connected' : 'Disconnected'}');
      }
    }
    
    // Notify connectivity type changes
    _connectivityTypeController?.add(getConnectivityType());
    
    // Process queued operations if connectivity is restored
    if (_isConnected && shouldProceedWithSync() && _queuedOperations.isNotEmpty) {
      _processQueuedOperations();
    }
  }

  /// Process queued network operations
  Future<void> _processQueuedOperations() async {
    if (_isProcessingQueue || _queuedOperations.isEmpty) {
      return;
    }
    
    _isProcessingQueue = true;
    
    try {
      if (kDebugMode) {
        print('Processing ${_queuedOperations.length} queued operations');
      }
      
      final operationsToProcess = List<NetworkOperation>.from(_queuedOperations);
      _queuedOperations.clear();
      
      for (final operation in operationsToProcess) {
        try {
          if (_isConnected && shouldProceedWithSync()) {
            await operation.execute();
            
            if (kDebugMode) {
              print('Queued operation completed: ${operation.id}');
            }
          } else {
            // Re-queue if connectivity is lost during processing
            _queuedOperations.add(operation);
            
            if (kDebugMode) {
              print('Operation re-queued due to connectivity loss: ${operation.id}');
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('Queued operation failed: ${operation.id} - $e');
          }
          
          // Re-queue failed operations for retry
          if (operation.retryCount < operation.maxRetries) {
            operation.retryCount++;
            _queuedOperations.add(operation);
          }
        }
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  /// Dispose of resources and stop monitoring
  void dispose() {
    _connectivitySubscription?.cancel();
    _connectivityController?.close();
    _connectivityTypeController?.close();
    _wifiController?.close();
    
    _connectivityController = null;
    _connectivityTypeController = null;
    _wifiController = null;
    
    _queuedOperations.clear();
    
    if (kDebugMode) {
      print('ConnectivityService disposed');
    }
  }
}

/// Represents different types of network connectivity
enum ConnectivityType {
  none,
  wifi,
  mobile,
  ethernet,
  bluetooth,
  vpn,
  other,
}

/// Represents network quality levels
enum NetworkQuality {
  none,
  low,
  medium,
  high,
  unknown,
}

/// Represents a network operation that can be queued for execution
class NetworkOperation {
  final String id;
  final String description;
  final Future<void> Function() execute;
  final int maxRetries;
  int retryCount;
  final DateTime createdAt;

  NetworkOperation({
    required this.id,
    required this.description,
    required this.execute,
    this.maxRetries = 3,
    this.retryCount = 0,
  }) : createdAt = DateTime.now();

  @override
  String toString() {
    return 'NetworkOperation(id: $id, description: $description, retries: $retryCount/$maxRetries)';
  }
}