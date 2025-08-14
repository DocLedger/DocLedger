import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import '../../../../lib/core/sync/services/sync_metrics.dart';

class MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return '/tmp/test_docs';
  }
}

void main() {
  group('SyncMetric', () {
    test('should serialize to and from JSON correctly', () {
      final metric = SyncMetric(
        id: 'test_id',
        type: 'sync_duration',
        timestamp: DateTime(2024, 1, 15, 10, 30),
        duration: const Duration(seconds: 5),
        dataSize: 1024,
        recordCount: 10,
        deviceId: 'device_123',
        metadata: {'sync_type': 'full'},
      );

      final json = metric.toJson();
      final restored = SyncMetric.fromJson(json);

      expect(restored.id, equals(metric.id));
      expect(restored.type, equals(metric.type));
      expect(restored.timestamp, equals(metric.timestamp));
      expect(restored.duration, equals(metric.duration));
      expect(restored.dataSize, equals(metric.dataSize));
      expect(restored.recordCount, equals(metric.recordCount));
      expect(restored.deviceId, equals(metric.deviceId));
      expect(restored.metadata, equals(metric.metadata));
    });

    test('should handle null values in JSON serialization', () {
      final metric = SyncMetric(
        id: 'test_id',
        type: 'error',
        timestamp: DateTime(2024, 1, 15),
      );

      final json = metric.toJson();
      final restored = SyncMetric.fromJson(json);

      expect(restored.duration, isNull);
      expect(restored.dataSize, isNull);
      expect(restored.recordCount, isNull);
      expect(restored.deviceId, isNull);
      expect(restored.metadata, isEmpty);
    });
  });

  group('SyncMetricsSummary', () {
    test('should serialize to JSON correctly', () {
      final summary = SyncMetricsSummary(
        totalSyncs: 100,
        successfulSyncs: 95,
        failedSyncs: 5,
        averageSyncDuration: const Duration(seconds: 3),
        totalDataSynced: 1048576,
        totalConflicts: 2,
        errorRate: 0.05,
        periodStart: DateTime(2024, 1, 1),
        periodEnd: DateTime(2024, 1, 31),
      );

      final json = summary.toJson();

      expect(json['total_syncs'], equals(100));
      expect(json['successful_syncs'], equals(95));
      expect(json['failed_syncs'], equals(5));
      expect(json['average_sync_duration_ms'], equals(3000));
      expect(json['total_data_synced_bytes'], equals(1048576));
      expect(json['total_conflicts'], equals(2));
      expect(json['error_rate'], equals(0.05));
    });
  });

  group('SyncMetrics', () {
    late SyncMetrics syncMetrics;
    late Directory tempDir;

    setUp(() async {
      PathProviderPlatform.instance = MockPathProviderPlatform();
      
      // Create temp directory for testing
      tempDir = Directory('/tmp/test_docs');
      if (!tempDir.existsSync()) {
        tempDir.createSync(recursive: true);
      }

      // Use a fresh instance for each test
      syncMetrics = SyncMetrics.forTesting();
      await syncMetrics.initialize();
    });

    tearDown(() async {
      // Clean up temp files
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
      
      // Reset singleton instance
      SyncMetrics.resetInstance();
    });

    test('should record sync duration metric', () async {
      await syncMetrics.recordSyncDuration(
        'full_sync',
        const Duration(seconds: 5),
        deviceId: 'device_123',
        recordCount: 100,
        metadata: {'test': 'data'},
      );

      final metrics = syncMetrics.getMetricsByType('sync_duration');
      expect(metrics.length, equals(1));
      
      final metric = metrics.first;
      expect(metric.type, equals('sync_duration'));
      expect(metric.duration, equals(const Duration(seconds: 5)));
      expect(metric.deviceId, equals('device_123'));
      expect(metric.recordCount, equals(100));
      expect(metric.metadata['sync_type'], equals('full_sync'));
      expect(metric.metadata['test'], equals('data'));
    });

    test('should record backup size metric', () async {
      await syncMetrics.recordBackupSize(
        1048576,
        deviceId: 'device_123',
        recordCount: 500,
        metadata: {'compression': 'gzip'},
      );

      final metrics = syncMetrics.getMetricsByType('backup_size');
      expect(metrics.length, equals(1));
      
      final metric = metrics.first;
      expect(metric.type, equals('backup_size'));
      expect(metric.dataSize, equals(1048576));
      expect(metric.deviceId, equals('device_123'));
      expect(metric.recordCount, equals(500));
      expect(metric.metadata['compression'], equals('gzip'));
    });

    test('should record conflict resolution metric', () async {
      await syncMetrics.recordConflictResolution(
        3,
        resolutionStrategy: 'last_write_wins',
        deviceId: 'device_123',
        metadata: {'table': 'patients'},
      );

      final metrics = syncMetrics.getMetricsByType('conflict_resolution');
      expect(metrics.length, equals(1));
      
      final metric = metrics.first;
      expect(metric.type, equals('conflict_resolution'));
      expect(metric.recordCount, equals(3));
      expect(metric.metadata['resolution_strategy'], equals('last_write_wins'));
      expect(metric.metadata['table'], equals('patients'));
    });

    test('should record network usage metric', () async {
      await syncMetrics.recordNetworkUsage(
        2048576,
        operation: 'upload',
        deviceId: 'device_123',
        metadata: {'endpoint': 'google_drive'},
      );

      final metrics = syncMetrics.getMetricsByType('network_usage');
      expect(metrics.length, equals(1));
      
      final metric = metrics.first;
      expect(metric.type, equals('network_usage'));
      expect(metric.dataSize, equals(2048576));
      expect(metric.metadata['operation'], equals('upload'));
      expect(metric.metadata['endpoint'], equals('google_drive'));
    });

    test('should record error metric', () async {
      await syncMetrics.recordError(
        'network_error',
        errorMessage: 'Connection timeout',
        deviceId: 'device_123',
        metadata: {'retry_count': 3},
      );

      final metrics = syncMetrics.getMetricsByType('error');
      expect(metrics.length, equals(1));
      
      final metric = metrics.first;
      expect(metric.type, equals('error'));
      expect(metric.metadata['error_type'], equals('network_error'));
      expect(metric.metadata['error_message'], equals('Connection timeout'));
      expect(metric.metadata['retry_count'], equals(3));
    });

    test('should generate metrics summary correctly', () async {
      final now = DateTime.now();
      
      // Add some test metrics
      await syncMetrics.recordSyncDuration('full_sync', const Duration(seconds: 5));
      await syncMetrics.recordSyncDuration('incremental_sync', const Duration(seconds: 2));
      await syncMetrics.recordError('sync_error', errorMessage: 'Test error');
      await syncMetrics.recordConflictResolution(2);
      await syncMetrics.recordNetworkUsage(1024);

      final summary = syncMetrics.getMetricsSummary(
        startDate: now.subtract(const Duration(hours: 1)),
        endDate: now.add(const Duration(hours: 1)),
      );

      expect(summary.totalSyncs, equals(2));
      expect(summary.successfulSyncs, equals(1)); // 2 syncs - 1 error
      expect(summary.failedSyncs, equals(1));
      expect(summary.averageSyncDuration, equals(const Duration(milliseconds: 3500)));
      expect(summary.totalDataSynced, equals(1024));
      expect(summary.totalConflicts, equals(2));
      expect(summary.errorRate, equals(0.5));
    });

    test('should filter metrics by device', () async {
      await syncMetrics.recordSyncDuration('sync', const Duration(seconds: 1), deviceId: 'device_1');
      await syncMetrics.recordSyncDuration('sync', const Duration(seconds: 2), deviceId: 'device_2');
      await syncMetrics.recordSyncDuration('sync', const Duration(seconds: 3), deviceId: 'device_1');

      final device1Metrics = syncMetrics.getMetricsByDevice('device_1');
      final device2Metrics = syncMetrics.getMetricsByDevice('device_2');

      expect(device1Metrics.length, equals(2));
      expect(device2Metrics.length, equals(1));
      expect(device1Metrics.every((m) => m.deviceId == 'device_1'), isTrue);
      expect(device2Metrics.every((m) => m.deviceId == 'device_2'), isTrue);
    });

    test('should cleanup old metrics', () async {
      // Add old metrics by directly adding to the internal list
      final oldMetric = SyncMetric(
        id: 'old_metric',
        type: 'sync_duration',
        timestamp: DateTime.now().subtract(const Duration(days: 35)),
        duration: const Duration(seconds: 1),
      );
      
      // Access metrics through the testing getter
      syncMetrics.metrics; // This will be empty initially
      
      // Add recent metric first
      await syncMetrics.recordSyncDuration('sync', const Duration(seconds: 1));
      
      // Manually add old metric for testing cleanup
      await syncMetrics.addMetricForTesting(oldMetric);

      expect(syncMetrics.metrics.length, equals(2));

      await syncMetrics.cleanupOldMetrics();

      expect(syncMetrics.metrics.length, equals(1));
      expect(syncMetrics.metrics.first.id, isNot(equals('old_metric')));
    });

    test('should export metrics as JSON', () async {
      await syncMetrics.recordSyncDuration('sync', const Duration(seconds: 1));
      await syncMetrics.recordBackupSize(1024);

      final exported = syncMetrics.exportMetrics();

      expect(exported['total_count'], equals(2));
      expect(exported['metrics'], isA<List>());
      expect(exported['exported_at'], isA<String>());
      
      final metrics = exported['metrics'] as List;
      expect(metrics.length, equals(2));
    });

    test('should persist and load metrics from storage', () async {
      // Add some metrics
      await syncMetrics.recordSyncDuration('sync', const Duration(seconds: 1));
      await syncMetrics.recordBackupSize(1024);

      expect(syncMetrics.metrics.length, equals(2));

      // Create new instance to test loading
      final newSyncMetrics = SyncMetrics.forTesting();
      await newSyncMetrics.initialize();

      expect(newSyncMetrics.metrics.length, equals(2));
      expect(newSyncMetrics.metrics.first.type, equals('sync_duration'));
      expect(newSyncMetrics.metrics.last.type, equals('backup_size'));
    });

    test('should handle corrupted metrics file gracefully', () async {
      // Write invalid JSON to metrics file
      final metricsFile = File('/tmp/test_docs/sync_metrics.json');
      await metricsFile.writeAsString('invalid json');

      // Should not throw and start with empty metrics
      final newSyncMetrics = SyncMetrics.forTesting();
      await newSyncMetrics.initialize();

      expect(newSyncMetrics.metrics, isEmpty);
    });
  });
}