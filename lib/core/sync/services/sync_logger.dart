import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Log levels for sync operations
enum LogLevel {
  debug,
  info,
  warning,
  error,
  critical,
}

/// Structured log entry for sync operations
class LogEntry {
  final String id;
  final LogLevel level;
  final DateTime timestamp;
  final String message;
  final String? deviceId;
  final String? operation;
  final Map<String, dynamic> context;
  final String? stackTrace;

  const LogEntry({
    required this.id,
    required this.level,
    required this.timestamp,
    required this.message,
    this.deviceId,
    this.operation,
    this.context = const {},
    this.stackTrace,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'level': level.name,
      'timestamp': timestamp.toIso8601String(),
      'message': message,
      'device_id': deviceId,
      'operation': operation,
      'context': context,
      'stack_trace': stackTrace,
    };
  }

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      id: json['id'],
      level: LogLevel.values.firstWhere((l) => l.name == json['level']),
      timestamp: DateTime.parse(json['timestamp']),
      message: json['message'],
      deviceId: json['device_id'],
      operation: json['operation'],
      context: json['context'] ?? {},
      stackTrace: json['stack_trace'],
    );
  }

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.write('[${timestamp.toIso8601String()}] ');
    buffer.write('[${level.name.toUpperCase()}] ');
    if (deviceId != null) buffer.write('[Device: $deviceId] ');
    if (operation != null) buffer.write('[Op: $operation] ');
    buffer.write(message);
    
    if (context.isNotEmpty) {
      buffer.write(' | Context: ${jsonEncode(context)}');
    }
    
    if (stackTrace != null) {
      buffer.write('\nStack Trace:\n$stackTrace');
    }
    
    return buffer.toString();
  }
}

/// Comprehensive logging system for sync operations
class SyncLogger {
  static const String _logFileName = 'sync_logs.json';
  static const int _maxLogAge = 7; // days
  static const int _maxLogEntries = 5000;
  static const int _rotationThreshold = 10000; // entries

  static SyncLogger? _instance;
  static SyncLogger get instance => _instance ??= SyncLogger._();
  
  SyncLogger._();

  final List<LogEntry> _logs = [];
  File? _logFile;
  LogLevel _minLogLevel = LogLevel.info;

  // Reset instance for testing
  @visibleForTesting
  static void resetInstance() {
    _instance = null;
  }

  // Factory constructor for testing
  @visibleForTesting
  factory SyncLogger.forTesting() => SyncLogger._();

  // Getter for testing purposes
  @visibleForTesting
  List<LogEntry> get logs => List.unmodifiable(_logs);

  /// Initialize the logging system
  Future<void> initialize({LogLevel minLogLevel = LogLevel.info}) async {
    _minLogLevel = minLogLevel;
    final directory = await getApplicationDocumentsDirectory();
    _logFile = File('${directory.path}/$_logFileName');
    await _loadLogs();
  }

  /// Set minimum log level
  void setLogLevel(LogLevel level) {
    _minLogLevel = level;
  }

  /// Log sync operation start
  Future<void> logSyncStart(
    String operation, {
    String? deviceId,
    Map<String, dynamic>? context,
  }) async {
    await _log(
      LogLevel.info,
      'Sync operation started: $operation',
      deviceId: deviceId,
      operation: operation,
      context: context ?? {},
    );
  }

  /// Log sync operation completion
  Future<void> logSyncComplete(
    String operation,
    Duration duration, {
    String? deviceId,
    int? recordCount,
    Map<String, dynamic>? context,
  }) async {
    await _log(
      LogLevel.info,
      'Sync operation completed: $operation in ${duration.inMilliseconds}ms',
      deviceId: deviceId,
      operation: operation,
      context: {
        'duration_ms': duration.inMilliseconds,
        'record_count': recordCount,
        ...?context,
      },
    );
  }

  /// Log sync error with stack trace
  Future<void> logSyncError(
    String operation,
    String error, {
    String? deviceId,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) async {
    await _log(
      LogLevel.error,
      'Sync operation failed: $operation - $error',
      deviceId: deviceId,
      operation: operation,
      context: context ?? {},
      stackTrace: stackTrace?.toString(),
    );
  }

  /// Log conflict resolution
  Future<void> logConflictResolution(
    String tableName,
    String recordId,
    String resolutionStrategy, {
    String? deviceId,
    Map<String, dynamic>? conflictData,
  }) async {
    await _log(
      LogLevel.warning,
      'Conflict resolved for $tableName:$recordId using $resolutionStrategy',
      deviceId: deviceId,
      operation: 'conflict_resolution',
      context: {
        'table_name': tableName,
        'record_id': recordId,
        'resolution_strategy': resolutionStrategy,
        'conflict_data': conflictData,
      },
    );
  }

  /// Log authentication events
  Future<void> logAuthentication(
    String event, {
    String? deviceId,
    bool success = true,
    String? errorMessage,
  }) async {
    await _log(
      success ? LogLevel.info : LogLevel.error,
      'Authentication $event: ${success ? 'success' : 'failed'}',
      deviceId: deviceId,
      operation: 'authentication',
      context: {
        'event': event,
        'success': success,
        'error_message': errorMessage,
      },
    );
  }

  /// Log network operations
  Future<void> logNetworkOperation(
    String operation,
    String endpoint, {
    String? deviceId,
    int? dataSize,
    Duration? duration,
    bool success = true,
    String? errorMessage,
  }) async {
    await _log(
      success ? LogLevel.info : LogLevel.error,
      'Network $operation to $endpoint: ${success ? 'success' : 'failed'}',
      deviceId: deviceId,
      operation: 'network',
      context: {
        'network_operation': operation,
        'endpoint': endpoint,
        'data_size_bytes': dataSize,
        'duration_ms': duration?.inMilliseconds,
        'success': success,
        'error_message': errorMessage,
      },
    );
  }

  /// Log database operations
  Future<void> logDatabaseOperation(
    String operation,
    String tableName, {
    String? deviceId,
    int? recordCount,
    Duration? duration,
    bool success = true,
    String? errorMessage,
  }) async {
    await _log(
      success ? LogLevel.debug : LogLevel.error,
      'Database $operation on $tableName: ${success ? 'success' : 'failed'}',
      deviceId: deviceId,
      operation: 'database',
      context: {
        'db_operation': operation,
        'table_name': tableName,
        'record_count': recordCount,
        'duration_ms': duration?.inMilliseconds,
        'success': success,
        'error_message': errorMessage,
      },
    );
  }

  /// Log encryption operations
  Future<void> logEncryption(
    String operation, {
    String? deviceId,
    int? dataSize,
    bool success = true,
    String? errorMessage,
  }) async {
    await _log(
      success ? LogLevel.debug : LogLevel.error,
      'Encryption $operation: ${success ? 'success' : 'failed'}',
      deviceId: deviceId,
      operation: 'encryption',
      context: {
        'encryption_operation': operation,
        'data_size_bytes': dataSize,
        'success': success,
        'error_message': errorMessage,
      },
    );
  }

  /// Log general debug information
  Future<void> logDebug(
    String message, {
    String? deviceId,
    String? operation,
    Map<String, dynamic>? context,
  }) async {
    await _log(
      LogLevel.debug,
      message,
      deviceId: deviceId,
      operation: operation,
      context: context ?? {},
    );
  }

  /// Log general information
  Future<void> logInfo(
    String message, {
    String? deviceId,
    String? operation,
    Map<String, dynamic>? context,
  }) async {
    await _log(
      LogLevel.info,
      message,
      deviceId: deviceId,
      operation: operation,
      context: context ?? {},
    );
  }

  /// Log warnings
  Future<void> logWarning(
    String message, {
    String? deviceId,
    String? operation,
    Map<String, dynamic>? context,
  }) async {
    await _log(
      LogLevel.warning,
      message,
      deviceId: deviceId,
      operation: operation,
      context: context ?? {},
    );
  }

  /// Log errors
  Future<void> logError(
    String message, {
    String? deviceId,
    String? operation,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) async {
    await _log(
      LogLevel.error,
      message,
      deviceId: deviceId,
      operation: operation,
      context: context ?? {},
      stackTrace: stackTrace?.toString(),
    );
  }

  /// Log critical errors
  Future<void> logCritical(
    String message, {
    String? deviceId,
    String? operation,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) async {
    await _log(
      LogLevel.critical,
      message,
      deviceId: deviceId,
      operation: operation,
      context: context ?? {},
      stackTrace: stackTrace?.toString(),
    );
  }

  /// Get logs filtered by level
  List<LogEntry> getLogsByLevel(LogLevel level) {
    return _logs.where((log) => log.level == level).toList();
  }

  /// Get logs filtered by operation
  List<LogEntry> getLogsByOperation(String operation) {
    return _logs.where((log) => log.operation == operation).toList();
  }

  /// Get logs filtered by device
  List<LogEntry> getLogsByDevice(String deviceId) {
    return _logs.where((log) => log.deviceId == deviceId).toList();
  }

  /// Get logs within time range
  List<LogEntry> getLogsByTimeRange(DateTime start, DateTime end) {
    return _logs.where((log) =>
        log.timestamp.isAfter(start) && log.timestamp.isBefore(end)).toList();
  }

  /// Get recent logs
  List<LogEntry> getRecentLogs({int count = 100}) {
    final sortedLogs = List<LogEntry>.from(_logs)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return sortedLogs.take(count).toList();
  }

  /// Export logs as JSON
  Map<String, dynamic> exportLogs({
    DateTime? startDate,
    DateTime? endDate,
    LogLevel? minLevel,
  }) {
    var logsToExport = _logs.asMap().values;

    if (startDate != null) {
      logsToExport = logsToExport.where((log) => log.timestamp.isAfter(startDate));
    }

    if (endDate != null) {
      logsToExport = logsToExport.where((log) => log.timestamp.isBefore(endDate));
    }

    if (minLevel != null) {
      logsToExport = logsToExport.where((log) => log.level.index >= minLevel.index);
    }

    return {
      'logs': logsToExport.map((log) => log.toJson()).toList(),
      'exported_at': DateTime.now().toIso8601String(),
      'total_count': logsToExport.length,
      'filters': {
        'start_date': startDate?.toIso8601String(),
        'end_date': endDate?.toIso8601String(),
        'min_level': minLevel?.name,
      },
    };
  }

  /// Clear all logs
  Future<void> clearLogs() async {
    _logs.clear();
    await _saveLogs();
  }

  /// Perform log rotation and cleanup
  Future<void> rotateLogs() async {
    // Remove old logs
    final cutoffDate = DateTime.now().subtract(Duration(days: _maxLogAge));
    _logs.removeWhere((log) => log.timestamp.isBefore(cutoffDate));

    // Limit total log count
    if (_logs.length > _maxLogEntries) {
      _logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _logs.removeRange(_maxLogEntries, _logs.length);
    }

    await _saveLogs();
  }

  /// Check if rotation is needed
  bool shouldRotate() {
    return _logs.length > _rotationThreshold;
  }

  /// Internal logging method
  Future<void> _log(
    LogLevel level,
    String message, {
    String? deviceId,
    String? operation,
    Map<String, dynamic> context = const {},
    String? stackTrace,
  }) async {
    // Check if log level meets minimum threshold
    if (level.index < _minLogLevel.index) {
      return;
    }

    final logEntry = LogEntry(
      id: _generateLogId(),
      level: level,
      timestamp: DateTime.now(),
      message: message,
      deviceId: deviceId,
      operation: operation,
      context: context,
      stackTrace: stackTrace,
    );

    _logs.add(logEntry);

    // Also log to console in debug mode
    if (kDebugMode) {
      print(logEntry.toString());
    }

    // Check if rotation is needed
    if (shouldRotate()) {
      await rotateLogs();
    } else {
      await _saveLogs();
    }
  }

  /// Load logs from persistent storage
  Future<void> _loadLogs() async {
    if (_logFile?.existsSync() == true) {
      try {
        final content = await _logFile!.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        final logsList = data['logs'] as List<dynamic>;
        
        _logs.clear();
        _logs.addAll(
          logsList.map((json) => LogEntry.fromJson(json))
        );
      } catch (e) {
        // If loading fails, start with empty logs
        _logs.clear();
      }
    }
  }

  /// Save logs to persistent storage
  Future<void> _saveLogs() async {
    if (_logFile != null) {
      final data = {
        'logs': _logs.map((log) => log.toJson()).toList(),
        'last_updated': DateTime.now().toIso8601String(),
        'total_count': _logs.length,
      };
      
      await _logFile!.writeAsString(jsonEncode(data));
    }
  }

  /// Generate unique log ID
  String _generateLogId() {
    return '${DateTime.now().millisecondsSinceEpoch}_${_logs.length}';
  }
}