import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Enum for sync status values
enum SyncStatus {
  idle,
  syncing,
  backingUp,
  restoring,
  error,
}

/// Enum for sync result status
enum SyncResultStatus {
  success,
  failure,
  partial,
  cancelled,
}

/// Model representing the complete backup data structure
class BackupData {
  final String clinicId;
  final String deviceId;
  final DateTime timestamp;
  final int version;
  final Map<String, List<Map<String, dynamic>>> tables;
  final String checksum;
  final Map<String, dynamic>? metadata;

  const BackupData({
    required this.clinicId,
    required this.deviceId,
    required this.timestamp,
    required this.version,
    required this.tables,
    required this.checksum,
    this.metadata,
  });

  Map<String, dynamic> toJson() {
    return {
      'clinic_id': clinicId,
      'device_id': deviceId,
      'timestamp': timestamp.toIso8601String(),
      'version': version,
      'tables': tables,
      'checksum': checksum,
      'metadata': metadata,
    };
  }

  static BackupData fromJson(Map<String, dynamic> json) {
    return BackupData(
      clinicId: json['clinic_id'] as String,
      deviceId: json['device_id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      version: json['version'] as int,
      tables: Map<String, List<Map<String, dynamic>>>.from(
        (json['tables'] as Map<String, dynamic>).map(
          (key, value) => MapEntry(
            key,
            List<Map<String, dynamic>>.from(
              (value as List).map((item) => Map<String, dynamic>.from(item)),
            ),
          ),
        ),
      ),
      checksum: json['checksum'] as String,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  /// Validates the integrity of the backup data
  bool validateIntegrity() {
    try {
      final dataToHash = {
        'clinic_id': clinicId,
        'device_id': deviceId,
        'timestamp': timestamp.toIso8601String(),
        'version': version,
        'tables': tables,
      };
      
      final jsonString = jsonEncode(dataToHash);
      final bytes = utf8.encode(jsonString);
      final digest = sha256.convert(bytes);
      final calculatedChecksum = digest.toString();
      
      return calculatedChecksum == checksum;
    } catch (e) {
      return false;
    }
  }

  /// Generates a checksum for the backup data
  static String generateChecksum(Map<String, dynamic> data) {
    final jsonString = jsonEncode(data);
    final bytes = utf8.encode(jsonString);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Creates a backup data instance with calculated checksum
  static BackupData create({
    required String clinicId,
    required String deviceId,
    required Map<String, List<Map<String, dynamic>>> tables,
    int version = 1,
    Map<String, dynamic>? metadata,
  }) {
    final timestamp = DateTime.now();
    final dataToHash = {
      'clinic_id': clinicId,
      'device_id': deviceId,
      'timestamp': timestamp.toIso8601String(),
      'version': version,
      'tables': tables,
    };
    
    final checksum = generateChecksum(dataToHash);
    
    return BackupData(
      clinicId: clinicId,
      deviceId: deviceId,
      timestamp: timestamp,
      version: version,
      tables: tables,
      checksum: checksum,
      metadata: metadata,
    );
  }

  BackupData copyWith({
    String? clinicId,
    String? deviceId,
    DateTime? timestamp,
    int? version,
    Map<String, List<Map<String, dynamic>>>? tables,
    String? checksum,
    Map<String, dynamic>? metadata,
  }) {
    return BackupData(
      clinicId: clinicId ?? this.clinicId,
      deviceId: deviceId ?? this.deviceId,
      timestamp: timestamp ?? this.timestamp,
      version: version ?? this.version,
      tables: tables ?? this.tables,
      checksum: checksum ?? this.checksum,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BackupData &&
        other.clinicId == clinicId &&
        other.deviceId == deviceId &&
        other.timestamp == timestamp &&
        other.version == version &&
        other.checksum == checksum;
  }

  @override
  int get hashCode {
    return Object.hash(clinicId, deviceId, timestamp, version, checksum);
  }
}

/// Model representing the current sync state
class SyncState {
  final SyncStatus status;
  final DateTime? lastSyncTime;
  final DateTime? lastBackupTime;
  final int pendingChanges;
  final List<String> conflicts;
  final String? errorMessage;
  final double? progress;
  final String? currentOperation;

  const SyncState({
    required this.status,
    this.lastSyncTime,
    this.lastBackupTime,
    this.pendingChanges = 0,
    this.conflicts = const [],
    this.errorMessage,
    this.progress,
    this.currentOperation,
  });

  Map<String, dynamic> toJson() {
    return {
      'status': status.name,
      'last_sync_time': lastSyncTime?.toIso8601String(),
      'last_backup_time': lastBackupTime?.toIso8601String(),
      'pending_changes': pendingChanges,
      'conflicts': conflicts,
      'error_message': errorMessage,
      'progress': progress,
      'current_operation': currentOperation,
    };
  }

  static SyncState fromJson(Map<String, dynamic> json) {
    return SyncState(
      status: SyncStatus.values.firstWhere((e) => e.name == json['status']),
      lastSyncTime: json['last_sync_time'] != null
          ? DateTime.parse(json['last_sync_time'] as String)
          : null,
      lastBackupTime: json['last_backup_time'] != null
          ? DateTime.parse(json['last_backup_time'] as String)
          : null,
      pendingChanges: json['pending_changes'] as int? ?? 0,
      conflicts: List<String>.from(json['conflicts'] as List? ?? []),
      errorMessage: json['error_message'] as String?,
      progress: json['progress'] as double?,
      currentOperation: json['current_operation'] as String?,
    );
  }

  /// Creates an idle sync state
  static SyncState idle() {
    return const SyncState(status: SyncStatus.idle);
  }

  /// Creates a syncing state with optional progress
  static SyncState syncing({
    double? progress,
    String? currentOperation,
  }) {
    return SyncState(
      status: SyncStatus.syncing,
      progress: progress,
      currentOperation: currentOperation,
    );
  }

  /// Creates a backing up state with optional progress
  static SyncState backingUp({
    double? progress,
    String? currentOperation,
  }) {
    return SyncState(
      status: SyncStatus.backingUp,
      progress: progress,
      currentOperation: currentOperation,
    );
  }

  /// Creates a restoring state with optional progress
  static SyncState restoring({
    double? progress,
    String? currentOperation,
  }) {
    return SyncState(
      status: SyncStatus.restoring,
      progress: progress,
      currentOperation: currentOperation,
    );
  }

  /// Creates an error state with error message
  static SyncState error(String errorMessage) {
    return SyncState(
      status: SyncStatus.error,
      errorMessage: errorMessage,
    );
  }

  SyncState copyWith({
    SyncStatus? status,
    DateTime? lastSyncTime,
    DateTime? lastBackupTime,
    int? pendingChanges,
    List<String>? conflicts,
    String? errorMessage,
    double? progress,
    String? currentOperation,
  }) {
    return SyncState(
      status: status ?? this.status,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      lastBackupTime: lastBackupTime ?? this.lastBackupTime,
      pendingChanges: pendingChanges ?? this.pendingChanges,
      conflicts: conflicts ?? this.conflicts,
      errorMessage: errorMessage ?? this.errorMessage,
      progress: progress ?? this.progress,
      currentOperation: currentOperation ?? this.currentOperation,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SyncState &&
        other.status == status &&
        other.lastSyncTime == lastSyncTime &&
        other.lastBackupTime == lastBackupTime &&
        other.pendingChanges == pendingChanges &&
        other.errorMessage == errorMessage;
  }

  @override
  int get hashCode {
    return Object.hash(status, lastSyncTime, lastBackupTime, pendingChanges, errorMessage);
  }
}

/// Model representing the result of a sync operation
class SyncResult {
  final SyncResultStatus status;
  final DateTime timestamp;
  final String? errorMessage;
  final Map<String, int>? syncedCounts;
  final List<String>? conflictIds;
  final Duration? duration;
  final Map<String, dynamic>? metadata;
  final dynamic error;
  final Duration? retryAfter;

  const SyncResult({
    required this.status,
    required this.timestamp,
    this.errorMessage,
    this.syncedCounts,
    this.conflictIds,
    this.duration,
    this.metadata,
    this.error,
    this.retryAfter,
  });

  Map<String, dynamic> toJson() {
    return {
      'status': status.name,
      'timestamp': timestamp.toIso8601String(),
      'error_message': errorMessage,
      'synced_counts': syncedCounts,
      'conflict_ids': conflictIds,
      'duration_ms': duration?.inMilliseconds,
      'metadata': metadata,
    };
  }

  static SyncResult fromJson(Map<String, dynamic> json) {
    return SyncResult(
      status: SyncResultStatus.values.firstWhere((e) => e.name == json['status']),
      timestamp: DateTime.parse(json['timestamp'] as String),
      errorMessage: json['error_message'] as String?,
      syncedCounts: json['synced_counts'] != null
          ? Map<String, int>.from(json['synced_counts'] as Map)
          : null,
      conflictIds: json['conflict_ids'] != null
          ? List<String>.from(json['conflict_ids'] as List)
          : null,
      duration: json['duration_ms'] != null
          ? Duration(milliseconds: json['duration_ms'] as int)
          : null,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  /// Creates a successful sync result
  static SyncResult success({
    Map<String, int>? syncedCounts,
    List<String>? conflictIds,
    Duration? duration,
    Map<String, dynamic>? metadata,
  }) {
    return SyncResult(
      status: SyncResultStatus.success,
      timestamp: DateTime.now(),
      syncedCounts: syncedCounts,
      conflictIds: conflictIds,
      duration: duration,
      metadata: metadata,
    );
  }

  /// Creates a failed sync result
  static SyncResult failure(String errorMessage, {Duration? duration}) {
    return SyncResult(
      status: SyncResultStatus.failure,
      timestamp: DateTime.now(),
      errorMessage: errorMessage,
      duration: duration,
    );
  }

  /// Creates an error sync result with exception
  static SyncResult withError(dynamic error, {String? message}) {
    return SyncResult(
      status: SyncResultStatus.failure,
      timestamp: DateTime.now(),
      errorMessage: message ?? error.toString(),
      error: error,
    );
  }

  /// Creates a retry sync result
  static SyncResult retry({required dynamic error, Duration? retryAfter}) {
    return SyncResult(
      status: SyncResultStatus.failure,
      timestamp: DateTime.now(),
      errorMessage: error.toString(),
      error: error,
      retryAfter: retryAfter,
    );
  }

  /// Creates a deferred sync result (operation postponed)
  static SyncResult deferred(String reason) {
    return SyncResult(
      status: SyncResultStatus.partial,
      timestamp: DateTime.now(),
      errorMessage: reason,
    );
  }

  /// Creates a result requiring re-authentication
  static SyncResult requiresReauth({String? message, dynamic error}) {
    return SyncResult(
      status: SyncResultStatus.failure,
      timestamp: DateTime.now(),
      errorMessage: message ?? 'Authentication required',
      error: error,
      metadata: {'requires_reauth': true},
    );
  }

  /// Creates a cancelled sync result
  static SyncResult cancelled() {
    return SyncResult(
      status: SyncResultStatus.cancelled,
      timestamp: DateTime.now(),
      errorMessage: 'Operation cancelled',
    );
  }

  /// Creates a partial sync result (some operations succeeded, some failed)
  static SyncResult partial({
    required Map<String, int> syncedCounts,
    required List<String> conflictIds,
    String? errorMessage,
    Duration? duration,
  }) {
    return SyncResult(
      status: SyncResultStatus.partial,
      timestamp: DateTime.now(),
      errorMessage: errorMessage,
      syncedCounts: syncedCounts,
      conflictIds: conflictIds,
      duration: duration,
    );
  }

  bool get isSuccess => status == SyncResultStatus.success;
  bool get isFailure => status == SyncResultStatus.failure;
  bool get isPartial => status == SyncResultStatus.partial;
  bool get isCancelled => status == SyncResultStatus.cancelled;

  SyncResult copyWith({
    SyncResultStatus? status,
    DateTime? timestamp,
    String? errorMessage,
    Map<String, int>? syncedCounts,
    List<String>? conflictIds,
    Duration? duration,
    Map<String, dynamic>? metadata,
  }) {
    return SyncResult(
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
      errorMessage: errorMessage ?? this.errorMessage,
      syncedCounts: syncedCounts ?? this.syncedCounts,
      conflictIds: conflictIds ?? this.conflictIds,
      duration: duration ?? this.duration,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SyncResult &&
        other.status == status &&
        other.timestamp == timestamp &&
        other.errorMessage == errorMessage;
  }

  @override
  int get hashCode {
    return Object.hash(status, timestamp, errorMessage);
  }
}

/// Model for tracking sync metadata per table
class SyncMetadata {
  final String tableName;
  final DateTime? lastSyncTimestamp;
  final DateTime? lastBackupTimestamp;
  final int pendingChangesCount;
  final int conflictCount;
  final String? lastSyncDeviceId;

  const SyncMetadata({
    required this.tableName,
    this.lastSyncTimestamp,
    this.lastBackupTimestamp,
    this.pendingChangesCount = 0,
    this.conflictCount = 0,
    this.lastSyncDeviceId,
  });

  Map<String, dynamic> toJson() {
    return {
      'table_name': tableName,
      'last_sync_timestamp': lastSyncTimestamp?.millisecondsSinceEpoch,
      'last_backup_timestamp': lastBackupTimestamp?.millisecondsSinceEpoch,
      'pending_changes_count': pendingChangesCount,
      'conflict_count': conflictCount,
      'last_sync_device_id': lastSyncDeviceId,
    };
  }

  static SyncMetadata fromJson(Map<String, dynamic> json) {
    return SyncMetadata(
      tableName: json['table_name'] as String,
      lastSyncTimestamp: json['last_sync_timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['last_sync_timestamp'] as int)
          : null,
      lastBackupTimestamp: json['last_backup_timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['last_backup_timestamp'] as int)
          : null,
      pendingChangesCount: json['pending_changes_count'] as int? ?? 0,
      conflictCount: json['conflict_count'] as int? ?? 0,
      lastSyncDeviceId: json['last_sync_device_id'] as String?,
    );
  }

  SyncMetadata copyWith({
    String? tableName,
    DateTime? lastSyncTimestamp,
    DateTime? lastBackupTimestamp,
    int? pendingChangesCount,
    int? conflictCount,
    String? lastSyncDeviceId,
  }) {
    return SyncMetadata(
      tableName: tableName ?? this.tableName,
      lastSyncTimestamp: lastSyncTimestamp ?? this.lastSyncTimestamp,
      lastBackupTimestamp: lastBackupTimestamp ?? this.lastBackupTimestamp,
      pendingChangesCount: pendingChangesCount ?? this.pendingChangesCount,
      conflictCount: conflictCount ?? this.conflictCount,
      lastSyncDeviceId: lastSyncDeviceId ?? this.lastSyncDeviceId,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SyncMetadata &&
        other.tableName == tableName &&
        other.lastSyncTimestamp == lastSyncTimestamp &&
        other.lastBackupTimestamp == lastBackupTimestamp &&
        other.pendingChangesCount == pendingChangesCount &&
        other.conflictCount == conflictCount;
  }

  @override
  int get hashCode {
    return Object.hash(
      tableName,
      lastSyncTimestamp,
      lastBackupTimestamp,
      pendingChangesCount,
      conflictCount,
    );
  }
}

/// Model representing the result of a restore operation
class RestoreResult {
  final bool success;
  final String message;
  final int? restoredRecords;
  final dynamic error;
  final DateTime timestamp;

  RestoreResult({
    required this.success,
    required this.message,
    this.restoredRecords,
    this.error,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Creates a successful restore result
  static RestoreResult withSuccess({
    required String message,
    int? restoredRecords,
  }) {
    return RestoreResult(
      success: true,
      message: message,
      restoredRecords: restoredRecords,
    );
  }

  /// Creates a failed restore result
  static RestoreResult withError(dynamic error, {String? message}) {
    return RestoreResult(
      success: false,
      message: message ?? error.toString(),
      error: error,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'message': message,
      'restored_records': restoredRecords,
      'timestamp': timestamp.toIso8601String(),
      'error': error?.toString(),
    };
  }

  static RestoreResult fromJson(Map<String, dynamic> json) {
    return RestoreResult(
      success: json['success'] as bool,
      message: json['message'] as String,
      restoredRecords: json['restored_records'] as int?,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}