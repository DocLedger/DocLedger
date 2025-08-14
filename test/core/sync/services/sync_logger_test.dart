import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import '../../../../lib/core/sync/services/sync_logger.dart';

class MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return '/tmp/test_logs';
  }
}

void main() {
  group('LogEntry', () {
    test('should serialize to and from JSON correctly', () {
      final logEntry = LogEntry(
        id: 'test_id',
        level: LogLevel.error,
        timestamp: DateTime(2024, 1, 15, 10, 30),
        message: 'Test error message',
        deviceId: 'device_123',
        operation: 'sync',
        context: {'key': 'value'},
        stackTrace: 'Stack trace here',
      );

      final json = logEntry.toJson();
      final restored = LogEntry.fromJson(json);

      expect(restored.id, equals(logEntry.id));
      expect(restored.level, equals(logEntry.level));
      expect(restored.timestamp, equals(logEntry.timestamp));
      expect(restored.message, equals(logEntry.message));
      expect(restored.deviceId, equals(logEntry.deviceId));
      expect(restored.operation, equals(logEntry.operation));
      expect(restored.context, equals(logEntry.context));
      expect(restored.stackTrace, equals(logEntry.stackTrace));
    });

    test('should handle null values in JSON serialization', () {
      final logEntry = LogEntry(
        id: 'test_id',
        level: LogLevel.info,
        timestamp: DateTime(2024, 1, 15),
        message: 'Test message',
      );

      final json = logEntry.toJson();
      final restored = LogEntry.fromJson(json);

      expect(restored.deviceId, isNull);
      expect(restored.operation, isNull);
      expect(restored.context, isEmpty);
      expect(restored.stackTrace, isNull);
    });

    test('should format toString correctly', () {
      final logEntry = LogEntry(
        id: 'test_id',
        level: LogLevel.warning,
        timestamp: DateTime(2024, 1, 15, 10, 30),
        message: 'Test warning',
        deviceId: 'device_123',
        operation: 'sync',
        context: {'key': 'value'},
      );

      final formatted = logEntry.toString();

      expect(formatted, contains('[2024-01-15T10:30:00.000]'));
      expect(formatted, contains('[WARNING]'));
      expect(formatted, contains('[Device: device_123]'));
      expect(formatted, contains('[Op: sync]'));
      expect(formatted, contains('Test warning'));
      expect(formatted, contains('Context: {"key":"value"}'));
    });
  });

  group('SyncLogger', () {
    late SyncLogger syncLogger;
    late Directory tempDir;

    setUp(() async {
      PathProviderPlatform.instance = MockPathProviderPlatform();
      
      // Create temp directory for testing
      tempDir = Directory('/tmp/test_logs');
      if (!tempDir.existsSync()) {
        tempDir.createSync(recursive: true);
      }

      // Use a fresh instance for each test
      syncLogger = SyncLogger.forTesting();
      await syncLogger.initialize();
    });

    tearDown(() async {
      // Clean up temp files
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
      
      // Reset singleton instance
      SyncLogger.resetInstance();
    });

    test('should initialize with correct log level', () async {
      final logger = SyncLogger.forTesting();
      await logger.initialize(minLogLevel: LogLevel.warning);
      
      // Debug and info logs should be filtered out
      await logger.logDebug('Debug message');
      await logger.logInfo('Info message');
      await logger.logWarning('Warning message');
      
      expect(logger.logs.length, equals(1));
      expect(logger.logs.first.level, equals(LogLevel.warning));
    });

    test('should log sync start operation', () async {
      await syncLogger.logSyncStart(
        'full_sync',
        deviceId: 'device_123',
        context: {'table_count': 5},
      );

      expect(syncLogger.logs.length, equals(1));
      
      final log = syncLogger.logs.first;
      expect(log.level, equals(LogLevel.info));
      expect(log.message, contains('Sync operation started: full_sync'));
      expect(log.deviceId, equals('device_123'));
      expect(log.operation, equals('full_sync'));
      expect(log.context['table_count'], equals(5));
    });

    test('should log sync completion with duration', () async {
      await syncLogger.logSyncComplete(
        'incremental_sync',
        const Duration(seconds: 5),
        deviceId: 'device_123',
        recordCount: 100,
        context: {'conflicts': 2},
      );

      expect(syncLogger.logs.length, equals(1));
      
      final log = syncLogger.logs.first;
      expect(log.level, equals(LogLevel.info));
      expect(log.message, contains('Sync operation completed: incremental_sync in 5000ms'));
      expect(log.deviceId, equals('device_123'));
      expect(log.operation, equals('incremental_sync'));
      expect(log.context['duration_ms'], equals(5000));
      expect(log.context['record_count'], equals(100));
      expect(log.context['conflicts'], equals(2));
    });

    test('should log sync errors with stack trace', () async {
      final stackTrace = StackTrace.current;
      
      await syncLogger.logSyncError(
        'backup',
        'Network connection failed',
        deviceId: 'device_123',
        stackTrace: stackTrace,
        context: {'retry_count': 3},
      );

      expect(syncLogger.logs.length, equals(1));
      
      final log = syncLogger.logs.first;
      expect(log.level, equals(LogLevel.error));
      expect(log.message, contains('Sync operation failed: backup - Network connection failed'));
      expect(log.deviceId, equals('device_123'));
      expect(log.operation, equals('backup'));
      expect(log.context['retry_count'], equals(3));
      expect(log.stackTrace, isNotNull);
      expect(log.stackTrace, contains('sync_logger_test.dart'));
    });

    test('should log conflict resolution', () async {
      await syncLogger.logConflictResolution(
        'patients',
        'patient_123',
        'last_write_wins',
        deviceId: 'device_123',
        conflictData: {'local_version': 1, 'remote_version': 2},
      );

      expect(syncLogger.logs.length, equals(1));
      
      final log = syncLogger.logs.first;
      expect(log.level, equals(LogLevel.warning));
      expect(log.message, contains('Conflict resolved for patients:patient_123 using last_write_wins'));
      expect(log.deviceId, equals('device_123'));
      expect(log.operation, equals('conflict_resolution'));
      expect(log.context['table_name'], equals('patients'));
      expect(log.context['record_id'], equals('patient_123'));
      expect(log.context['resolution_strategy'], equals('last_write_wins'));
    });

    test('should log authentication events', () async {
      await syncLogger.logAuthentication(
        'google_drive_login',
        deviceId: 'device_123',
        success: false,
        errorMessage: 'Invalid credentials',
      );

      expect(syncLogger.logs.length, equals(1));
      
      final log = syncLogger.logs.first;
      expect(log.level, equals(LogLevel.error));
      expect(log.message, contains('Authentication google_drive_login: failed'));
      expect(log.deviceId, equals('device_123'));
      expect(log.operation, equals('authentication'));
      expect(log.context['success'], equals(false));
      expect(log.context['error_message'], equals('Invalid credentials'));
    });

    test('should log network operations', () async {
      await syncLogger.logNetworkOperation(
        'upload',
        'https://drive.googleapis.com',
        deviceId: 'device_123',
        dataSize: 1024,
        duration: const Duration(seconds: 2),
        success: true,
      );

      expect(syncLogger.logs.length, equals(1));
      
      final log = syncLogger.logs.first;
      expect(log.level, equals(LogLevel.info));
      expect(log.message, contains('Network upload to https://drive.googleapis.com: success'));
      expect(log.deviceId, equals('device_123'));
      expect(log.operation, equals('network'));
      expect(log.context['network_operation'], equals('upload'));
      expect(log.context['data_size_bytes'], equals(1024));
      expect(log.context['duration_ms'], equals(2000));
    });

    test('should log database operations', () async {
      // Set log level to debug to capture database operations
      syncLogger.setLogLevel(LogLevel.debug);
      
      await syncLogger.logDatabaseOperation(
        'insert',
        'patients',
        deviceId: 'device_123',
        recordCount: 5,
        duration: const Duration(milliseconds: 100),
        success: true,
      );

      expect(syncLogger.logs.length, equals(1));
      
      final log = syncLogger.logs.first;
      expect(log.level, equals(LogLevel.debug));
      expect(log.message, contains('Database insert on patients: success'));
      expect(log.deviceId, equals('device_123'));
      expect(log.operation, equals('database'));
      expect(log.context['db_operation'], equals('insert'));
      expect(log.context['table_name'], equals('patients'));
      expect(log.context['record_count'], equals(5));
    });

    test('should log encryption operations', () async {
      // Set log level to debug to capture encryption operations
      syncLogger.setLogLevel(LogLevel.debug);
      
      await syncLogger.logEncryption(
        'encrypt',
        deviceId: 'device_123',
        dataSize: 2048,
        success: true,
      );

      expect(syncLogger.logs.length, equals(1));
      
      final log = syncLogger.logs.first;
      expect(log.level, equals(LogLevel.debug));
      expect(log.message, contains('Encryption encrypt: success'));
      expect(log.deviceId, equals('device_123'));
      expect(log.operation, equals('encryption'));
      expect(log.context['encryption_operation'], equals('encrypt'));
      expect(log.context['data_size_bytes'], equals(2048));
    });

    test('should filter logs by level', () async {
      await syncLogger.logDebug('Debug message');
      await syncLogger.logInfo('Info message');
      await syncLogger.logWarning('Warning message');
      await syncLogger.logError('Error message');

      final errorLogs = syncLogger.getLogsByLevel(LogLevel.error);
      final infoLogs = syncLogger.getLogsByLevel(LogLevel.info);

      expect(errorLogs.length, equals(1));
      expect(errorLogs.first.message, equals('Error message'));
      expect(infoLogs.length, equals(1));
      expect(infoLogs.first.message, equals('Info message'));
    });

    test('should filter logs by operation', () async {
      await syncLogger.logSyncStart('full_sync');
      await syncLogger.logNetworkOperation('upload', 'endpoint');
      await syncLogger.logSyncComplete('full_sync', const Duration(seconds: 1));

      final syncLogs = syncLogger.getLogsByOperation('full_sync');
      final networkLogs = syncLogger.getLogsByOperation('network');

      expect(syncLogs.length, equals(2));
      expect(networkLogs.length, equals(1));
    });

    test('should filter logs by device', () async {
      await syncLogger.logInfo('Message 1', deviceId: 'device_1');
      await syncLogger.logInfo('Message 2', deviceId: 'device_2');
      await syncLogger.logInfo('Message 3', deviceId: 'device_1');

      final device1Logs = syncLogger.getLogsByDevice('device_1');
      final device2Logs = syncLogger.getLogsByDevice('device_2');

      expect(device1Logs.length, equals(2));
      expect(device2Logs.length, equals(1));
    });

    test('should filter logs by time range', () async {
      final now = DateTime.now();
      final start = now.subtract(const Duration(hours: 1));
      final end = now.add(const Duration(hours: 1));

      await syncLogger.logInfo('Recent message');
      
      final logsInRange = syncLogger.getLogsByTimeRange(start, end);
      expect(logsInRange.length, equals(1));

      final logsOutOfRange = syncLogger.getLogsByTimeRange(
        now.subtract(const Duration(days: 1)),
        now.subtract(const Duration(hours: 2)),
      );
      expect(logsOutOfRange.length, equals(0));
    });

    test('should get recent logs with limit', () async {
      // Add multiple logs
      for (int i = 0; i < 10; i++) {
        await syncLogger.logInfo('Message $i');
      }

      final recentLogs = syncLogger.getRecentLogs(count: 5);
      expect(recentLogs.length, equals(5));
      
      // Should be in reverse chronological order (most recent first)
      expect(recentLogs.first.message, equals('Message 9'));
      expect(recentLogs.last.message, equals('Message 5'));
    });

    test('should export logs with filters', () async {
      await syncLogger.logDebug('Debug message');
      await syncLogger.logInfo('Info message');
      await syncLogger.logError('Error message');

      final exported = syncLogger.exportLogs(minLevel: LogLevel.info);

      expect(exported['total_count'], equals(2)); // info and error
      expect(exported['filters']['min_level'], equals('info'));
      
      final logs = exported['logs'] as List;
      expect(logs.length, equals(2));
      expect(logs.any((log) => log['message'] == 'Debug message'), isFalse);
      expect(logs.any((log) => log['message'] == 'Info message'), isTrue);
      expect(logs.any((log) => log['message'] == 'Error message'), isTrue);
    });

    test('should clear all logs', () async {
      await syncLogger.logInfo('Message 1');
      await syncLogger.logInfo('Message 2');
      
      expect(syncLogger.logs.length, equals(2));
      
      await syncLogger.clearLogs();
      
      expect(syncLogger.logs.length, equals(0));
    });

    test('should rotate logs when threshold is reached', () async {
      // The rotation threshold is 10000, so we need to test the shouldRotate method
      final logger = SyncLogger.forTesting();
      await logger.initialize();

      // Add logs but not enough to trigger rotation
      for (int i = 0; i < 15; i++) {
        await logger.logInfo('Message $i');
      }

      // Should not trigger rotation yet (threshold is 10000)
      expect(logger.logs.length, equals(15));
      expect(logger.shouldRotate(), isFalse);
      
      // Test manual rotation
      await logger.rotateLogs();
      expect(logger.logs.length, equals(15)); // Should still have all logs (within age limit)
    });

    test('should persist and load logs from storage', () async {
      // Add some logs
      await syncLogger.logInfo('Persistent message 1');
      await syncLogger.logError('Persistent error');

      expect(syncLogger.logs.length, equals(2));

      // Create new instance to test loading
      final newLogger = SyncLogger.forTesting();
      await newLogger.initialize();

      expect(newLogger.logs.length, equals(2));
      expect(newLogger.logs.any((log) => log.message == 'Persistent message 1'), isTrue);
      expect(newLogger.logs.any((log) => log.message == 'Persistent error'), isTrue);
    });

    test('should handle corrupted log file gracefully', () async {
      // Write invalid JSON to log file
      final logFile = File('/tmp/test_logs/sync_logs.json');
      await logFile.writeAsString('invalid json');

      // Should not throw and start with empty logs
      final newLogger = SyncLogger.forTesting();
      await newLogger.initialize();

      expect(newLogger.logs, isEmpty);
    });

    test('should respect minimum log level', () async {
      final logger = SyncLogger.forTesting();
      await logger.initialize(minLogLevel: LogLevel.warning);

      await logger.logDebug('Debug message');
      await logger.logInfo('Info message');
      await logger.logWarning('Warning message');
      await logger.logError('Error message');

      expect(logger.logs.length, equals(2)); // Only warning and error
      expect(logger.logs.every((log) => log.level.index >= LogLevel.warning.index), isTrue);
    });

    test('should change log level dynamically', () async {
      syncLogger.setLogLevel(LogLevel.error);

      await syncLogger.logInfo('Info message');
      await syncLogger.logWarning('Warning message');
      await syncLogger.logError('Error message');

      expect(syncLogger.logs.length, equals(1)); // Only error
      expect(syncLogger.logs.first.level, equals(LogLevel.error));
    });
  });
}