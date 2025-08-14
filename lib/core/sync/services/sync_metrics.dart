import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Metrics data structure for sync operations
class SyncMetric {
  final String id;
  final String type;
  final DateTime timestamp;
  final Duration? duration;
  final int? dataSize;
  final int? recordCount;
  final String? deviceId;
  final Map<String, dynamic> metadata;

  const SyncMetric({
    required this.id,
    required this.type,
    required this.timestamp,
    this.duration,
    this.dataSize,
    this.recordCount,
    this.deviceId,
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'timestamp': timestamp.toIso8601String(),
      'duration_ms': duration?.inMilliseconds,
      'data_size_bytes': dataSize,
      'record_count': recordCount,
      'device_id': deviceId,
      'metadata': metadata,
    };
  }

  factory SyncMetric.fromJson(Map<String, dynamic> json) {
    return SyncMetric(
      id: json['id'],
      type: json['type'],
      timestamp: DateTime.parse(json['timestamp']),
      duration: json['duration_ms'] != null 
          ? Duration(milliseconds: json['duration_ms']) 
          : null,
      dataSize: json['data_size_bytes'],
      recordCount: json['record_count'],
      deviceId: json['device_id'],
      metadata: json['metadata'] ?? {},
    );
  }
}

/// Aggregated metrics for reporting
class SyncMetricsSummary {
  final int totalSyncs;
  final int successfulSyncs;
  final int failedSyncs;
  final Duration averageSyncDuration;
  final int totalDataSynced;
  final int totalConflicts;
  final double errorRate;
  final DateTime periodStart;
  final DateTime periodEnd;

  const SyncMetricsSummary({
    required this.totalSyncs,
    required this.successfulSyncs,
    required this.failedSyncs,
    required this.averageSyncDuration,
    required this.totalDataSynced,
    required this.totalConflicts,
    required this.errorRate,
    required this.periodStart,
    required this.periodEnd,
  });

  Map<String, dynamic> toJson() {
    return {
      'total_syncs': totalSyncs,
      'successful_syncs': successfulSyncs,
      'failed_syncs': failedSyncs,
      'average_sync_duration_ms': averageSyncDuration.inMilliseconds,
      'total_data_synced_bytes': totalDataSynced,
      'total_conflicts': totalConflicts,
      'error_rate': errorRate,
      'period_start': periodStart.toIso8601String(),
      'period_end': periodEnd.toIso8601String(),
    };
  }
}

/// Service for collecting and managing sync performance metrics
class SyncMetrics {
  static const String _metricsFileName = 'sync_metrics.json';
  static const int _maxMetricsAge = 30; // days
  static const int _maxMetricsCount = 1000;

  static SyncMetrics? _instance;
  static SyncMetrics get instance => _instance ??= SyncMetrics._();

  // Reset instance for testing
  @visibleForTesting
  static void resetInstance() {
    _instance = null;
  }
  
  SyncMetrics._();

  // Factory constructor for testing
  @visibleForTesting
  factory SyncMetrics.forTesting() => SyncMetrics._();

  final List<SyncMetric> _metrics = [];
  File? _metricsFile;

  // Getter for testing purposes
  @visibleForTesting
  List<SyncMetric> get metrics => List.unmodifiable(_metrics);

  // Method for testing purposes
  @visibleForTesting
  Future<void> addMetricForTesting(SyncMetric metric) async {
    await _addMetric(metric);
  }

  /// Initialize the metrics service
  Future<void> initialize() async {
    final directory = await getApplicationDocumentsDirectory();
    _metricsFile = File('${directory.path}/$_metricsFileName');
    await _loadMetrics();
  }

  /// Record sync operation duration
  Future<void> recordSyncDuration(
    String syncType,
    Duration duration, {
    String? deviceId,
    int? recordCount,
    Map<String, dynamic>? metadata,
  }) async {
    final metric = SyncMetric(
      id: _generateMetricId(),
      type: 'sync_duration',
      timestamp: DateTime.now(),
      duration: duration,
      recordCount: recordCount,
      deviceId: deviceId,
      metadata: {
        'sync_type': syncType,
        ...?metadata,
      },
    );

    await _addMetric(metric);
  }

  /// Record backup file size
  Future<void> recordBackupSize(
    int sizeBytes, {
    String? deviceId,
    int? recordCount,
    Map<String, dynamic>? metadata,
  }) async {
    final metric = SyncMetric(
      id: _generateMetricId(),
      type: 'backup_size',
      timestamp: DateTime.now(),
      dataSize: sizeBytes,
      recordCount: recordCount,
      deviceId: deviceId,
      metadata: metadata ?? {},
    );

    await _addMetric(metric);
  }

  /// Record conflict resolution
  Future<void> recordConflictResolution(
    int conflictCount, {
    String? resolutionStrategy,
    String? deviceId,
    Map<String, dynamic>? metadata,
  }) async {
    final metric = SyncMetric(
      id: _generateMetricId(),
      type: 'conflict_resolution',
      timestamp: DateTime.now(),
      recordCount: conflictCount,
      deviceId: deviceId,
      metadata: {
        'resolution_strategy': resolutionStrategy,
        ...?metadata,
      },
    );

    await _addMetric(metric);
  }

  /// Record network usage
  Future<void> recordNetworkUsage(
    int bytesTransferred, {
    String? operation,
    String? deviceId,
    Map<String, dynamic>? metadata,
  }) async {
    final metric = SyncMetric(
      id: _generateMetricId(),
      type: 'network_usage',
      timestamp: DateTime.now(),
      dataSize: bytesTransferred,
      deviceId: deviceId,
      metadata: {
        'operation': operation,
        ...?metadata,
      },
    );

    await _addMetric(metric);
  }

  /// Record error occurrence
  Future<void> recordError(
    String errorType, {
    String? errorMessage,
    String? deviceId,
    Map<String, dynamic>? metadata,
  }) async {
    final metric = SyncMetric(
      id: _generateMetricId(),
      type: 'error',
      timestamp: DateTime.now(),
      deviceId: deviceId,
      metadata: {
        'error_type': errorType,
        'error_message': errorMessage,
        ...?metadata,
      },
    );

    await _addMetric(metric);
  }

  /// Get metrics summary for a time period
  SyncMetricsSummary getMetricsSummary({
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final now = DateTime.now();
    final start = startDate ?? now.subtract(const Duration(days: 7));
    final end = endDate ?? now;

    final periodMetrics = _metrics.where((metric) =>
        metric.timestamp.isAfter(start) && metric.timestamp.isBefore(end));

    final syncMetrics = periodMetrics.where((m) => m.type == 'sync_duration');
    final errorMetrics = periodMetrics.where((m) => m.type == 'error');
    final conflictMetrics = periodMetrics.where((m) => m.type == 'conflict_resolution');
    final networkMetrics = periodMetrics.where((m) => m.type == 'network_usage');

    final totalSyncs = syncMetrics.length;
    final failedSyncs = errorMetrics.where((m) => 
        m.metadata['error_type']?.toString().contains('sync') == true).length;
    final successfulSyncs = totalSyncs - failedSyncs;

    final avgDuration = syncMetrics.isNotEmpty
        ? Duration(milliseconds: 
            syncMetrics.map((m) => m.duration?.inMilliseconds ?? 0)
                .reduce((a, b) => a + b) ~/ syncMetrics.length)
        : Duration.zero;

    final totalDataSynced = networkMetrics
        .map((m) => m.dataSize ?? 0)
        .fold(0, (a, b) => a + b);

    final totalConflicts = conflictMetrics
        .map((m) => m.recordCount ?? 0)
        .fold(0, (a, b) => a + b);

    final errorRate = totalSyncs > 0 ? failedSyncs / totalSyncs : 0.0;

    return SyncMetricsSummary(
      totalSyncs: totalSyncs,
      successfulSyncs: successfulSyncs,
      failedSyncs: failedSyncs,
      averageSyncDuration: avgDuration,
      totalDataSynced: totalDataSynced,
      totalConflicts: totalConflicts,
      errorRate: errorRate,
      periodStart: start,
      periodEnd: end,
    );
  }

  /// Get all metrics for a specific type
  List<SyncMetric> getMetricsByType(String type) {
    return _metrics.where((metric) => metric.type == type).toList();
  }

  /// Get metrics for a specific device
  List<SyncMetric> getMetricsByDevice(String deviceId) {
    return _metrics.where((metric) => metric.deviceId == deviceId).toList();
  }

  /// Clear old metrics beyond retention period
  Future<void> cleanupOldMetrics() async {
    final cutoffDate = DateTime.now().subtract(Duration(days: _maxMetricsAge));
    _metrics.removeWhere((metric) => metric.timestamp.isBefore(cutoffDate));
    
    // Also limit total count
    if (_metrics.length > _maxMetricsCount) {
      _metrics.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _metrics.removeRange(_maxMetricsCount, _metrics.length);
    }
    
    await _saveMetrics();
  }

  /// Export metrics as JSON
  Map<String, dynamic> exportMetrics() {
    return {
      'metrics': _metrics.map((m) => m.toJson()).toList(),
      'exported_at': DateTime.now().toIso8601String(),
      'total_count': _metrics.length,
    };
  }

  /// Add a metric and persist to storage
  Future<void> _addMetric(SyncMetric metric) async {
    _metrics.add(metric);
    await _saveMetrics();
  }

  /// Load metrics from persistent storage
  Future<void> _loadMetrics() async {
    if (_metricsFile?.existsSync() == true) {
      try {
        final content = await _metricsFile!.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        final metricsList = data['metrics'] as List<dynamic>;
        
        _metrics.clear();
        _metrics.addAll(
          metricsList.map((json) => SyncMetric.fromJson(json))
        );
      } catch (e) {
        // If loading fails, start with empty metrics
        _metrics.clear();
      }
    }
  }

  /// Save metrics to persistent storage
  Future<void> _saveMetrics() async {
    if (_metricsFile != null) {
      final data = {
        'metrics': _metrics.map((m) => m.toJson()).toList(),
        'last_updated': DateTime.now().toIso8601String(),
      };
      
      await _metricsFile!.writeAsString(jsonEncode(data));
    }
  }

  /// Generate unique metric ID
  String _generateMetricId() {
    return '${DateTime.now().millisecondsSinceEpoch}_${_metrics.length}';
  }
}