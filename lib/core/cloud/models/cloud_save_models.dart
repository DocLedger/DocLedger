import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Enum for cloud save status values
enum CloudSaveStatus {
  idle,
  saving,
  restoring,
  error,
}

/// Enum for cloud save result status
enum CloudSaveResultStatus {
  success,
  failure,
  cancelled,
}

/// Model representing the simplified cloud save data structure
class CloudSaveData {
  final String clinicId;
  final String deviceId;
  final DateTime timestamp;
  final int version;
  final Map<String, List<Map<String, dynamic>>> tables;
  final String checksum;
  final Map<String, dynamic>? metadata;

  const CloudSaveData({
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

  static CloudSaveData fromJson(Map<String, dynamic> json) {
    return CloudSaveData(
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

  /// Validates the integrity of the save data
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

  /// Generates a checksum for the save data
  static String generateChecksum(Map<String, dynamic> data) {
    final jsonString = jsonEncode(data);
    final bytes = utf8.encode(jsonString);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Creates a cloud save data instance with calculated checksum
  static CloudSaveData create({
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
    
    return CloudSaveData(
      clinicId: clinicId,
      deviceId: deviceId,
      timestamp: timestamp,
      version: version,
      tables: tables,
      checksum: checksum,
      metadata: metadata,
    );
  }

  CloudSaveData copyWith({
    String? clinicId,
    String? deviceId,
    DateTime? timestamp,
    int? version,
    Map<String, List<Map<String, dynamic>>>? tables,
    String? checksum,
    Map<String, dynamic>? metadata,
  }) {
    return CloudSaveData(
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
    return other is CloudSaveData &&
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

/// Model representing the current cloud save state
class CloudSaveState {
  final CloudSaveStatus status;
  final DateTime? lastSaveTime;
  final String? errorMessage;
  final double? progress;
  final String? currentOperation;

  const CloudSaveState({
    required this.status,
    this.lastSaveTime,
    this.errorMessage,
    this.progress,
    this.currentOperation,
  });

  Map<String, dynamic> toJson() {
    return {
      'status': status.name,
      'last_save_time': lastSaveTime?.toIso8601String(),
      'error_message': errorMessage,
      'progress': progress,
      'current_operation': currentOperation,
    };
  }

  static CloudSaveState fromJson(Map<String, dynamic> json) {
    return CloudSaveState(
      status: CloudSaveStatus.values.firstWhere((e) => e.name == json['status']),
      lastSaveTime: json['last_save_time'] != null
          ? DateTime.parse(json['last_save_time'] as String)
          : null,
      errorMessage: json['error_message'] as String?,
      progress: json['progress'] as double?,
      currentOperation: json['current_operation'] as String?,
    );
  }

  /// Creates an idle state
  static CloudSaveState idle({DateTime? lastSaveTime}) {
    return CloudSaveState(
      status: CloudSaveStatus.idle,
      lastSaveTime: lastSaveTime,
    );
  }

  /// Creates a saving state with optional progress
  static CloudSaveState saving({
    double? progress,
    String? currentOperation,
  }) {
    return CloudSaveState(
      status: CloudSaveStatus.saving,
      progress: progress,
      currentOperation: currentOperation,
    );
  }

  /// Creates a restoring state with optional progress
  static CloudSaveState restoring({
    double? progress,
    String? currentOperation,
  }) {
    return CloudSaveState(
      status: CloudSaveStatus.restoring,
      progress: progress,
      currentOperation: currentOperation,
    );
  }

  /// Creates an error state with error message
  static CloudSaveState error(String errorMessage) {
    return CloudSaveState(
      status: CloudSaveStatus.error,
      errorMessage: errorMessage,
    );
  }

  /// Gets a user-friendly status message
  String get statusMessage {
    switch (status) {
      case CloudSaveStatus.idle:
        if (lastSaveTime != null) {
          final now = DateTime.now();
          final difference = now.difference(lastSaveTime!);
          
          if (difference.inMinutes < 1) {
            return 'Saved just now';
          } else if (difference.inMinutes < 60) {
            return 'Saved ${difference.inMinutes} minutes ago';
          } else if (difference.inHours < 24) {
            return 'Saved ${difference.inHours} hours ago';
          } else {
            return 'Saved ${difference.inDays} days ago';
          }
        } else {
          return 'Not saved yet';
        }
      case CloudSaveStatus.saving:
        return currentOperation ?? 'Saving to cloud...';
      case CloudSaveStatus.restoring:
        return currentOperation ?? 'Restoring from cloud...';
      case CloudSaveStatus.error:
        return errorMessage ?? 'Save failed';
    }
  }

  /// Gets the appropriate status icon
  String get statusIcon {
    switch (status) {
      case CloudSaveStatus.idle:
        return lastSaveTime != null ? '✓' : '○';
      case CloudSaveStatus.saving:
      case CloudSaveStatus.restoring:
        return '⟳';
      case CloudSaveStatus.error:
        return '⚠';
    }
  }

  CloudSaveState copyWith({
    CloudSaveStatus? status,
    DateTime? lastSaveTime,
    String? errorMessage,
    double? progress,
    String? currentOperation,
  }) {
    return CloudSaveState(
      status: status ?? this.status,
      lastSaveTime: lastSaveTime ?? this.lastSaveTime,
      errorMessage: errorMessage ?? this.errorMessage,
      progress: progress ?? this.progress,
      currentOperation: currentOperation ?? this.currentOperation,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CloudSaveState &&
        other.status == status &&
        other.lastSaveTime == lastSaveTime &&
        other.errorMessage == errorMessage;
  }

  @override
  int get hashCode {
    return Object.hash(status, lastSaveTime, errorMessage);
  }
}

/// Model representing the result of a cloud save operation
class CloudSaveResult {
  final CloudSaveResultStatus status;
  final DateTime timestamp;
  final String? errorMessage;
  final Duration? duration;
  final Map<String, dynamic>? metadata;
  final dynamic error;

  const CloudSaveResult({
    required this.status,
    required this.timestamp,
    this.errorMessage,
    this.duration,
    this.metadata,
    this.error,
  });

  Map<String, dynamic> toJson() {
    return {
      'status': status.name,
      'timestamp': timestamp.toIso8601String(),
      'error_message': errorMessage,
      'duration_ms': duration?.inMilliseconds,
      'metadata': metadata,
    };
  }

  static CloudSaveResult fromJson(Map<String, dynamic> json) {
    return CloudSaveResult(
      status: CloudSaveResultStatus.values.firstWhere((e) => e.name == json['status']),
      timestamp: DateTime.parse(json['timestamp'] as String),
      errorMessage: json['error_message'] as String?,
      duration: json['duration_ms'] != null
          ? Duration(milliseconds: json['duration_ms'] as int)
          : null,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  /// Creates a successful result
  static CloudSaveResult success({
    Duration? duration,
    Map<String, dynamic>? metadata,
  }) {
    return CloudSaveResult(
      status: CloudSaveResultStatus.success,
      timestamp: DateTime.now(),
      duration: duration,
      metadata: metadata,
    );
  }

  /// Creates a failed result
  static CloudSaveResult failure(String errorMessage, {Duration? duration}) {
    return CloudSaveResult(
      status: CloudSaveResultStatus.failure,
      timestamp: DateTime.now(),
      errorMessage: errorMessage,
      duration: duration,
    );
  }

  /// Creates a cancelled result
  static CloudSaveResult cancelled() {
    return CloudSaveResult(
      status: CloudSaveResultStatus.cancelled,
      timestamp: DateTime.now(),
      errorMessage: 'Operation cancelled',
    );
  }

  bool get isSuccess => status == CloudSaveResultStatus.success;
  bool get isFailure => status == CloudSaveResultStatus.failure;
  bool get isCancelled => status == CloudSaveResultStatus.cancelled;

  CloudSaveResult copyWith({
    CloudSaveResultStatus? status,
    DateTime? timestamp,
    String? errorMessage,
    Duration? duration,
    Map<String, dynamic>? metadata,
  }) {
    return CloudSaveResult(
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
      errorMessage: errorMessage ?? this.errorMessage,
      duration: duration ?? this.duration,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CloudSaveResult &&
        other.status == status &&
        other.timestamp == timestamp &&
        other.errorMessage == errorMessage;
  }

  @override
  int get hashCode {
    return Object.hash(status, timestamp, errorMessage);
  }
}

/// Simple settings model for cloud save
class CloudSaveSettings {
  final bool autoSaveEnabled;
  final bool wifiOnlyMode;
  final bool showNotifications;

  const CloudSaveSettings({
    this.autoSaveEnabled = true,
    this.wifiOnlyMode = true,
    this.showNotifications = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'auto_save_enabled': autoSaveEnabled,
      'wifi_only_mode': wifiOnlyMode,
      'show_notifications': showNotifications,
    };
  }

  static CloudSaveSettings fromJson(Map<String, dynamic> json) {
    return CloudSaveSettings(
      autoSaveEnabled: json['auto_save_enabled'] as bool? ?? true,
      wifiOnlyMode: json['wifi_only_mode'] as bool? ?? true,
      showNotifications: json['show_notifications'] as bool? ?? true,
    );
  }

  /// Default settings factory method
  static CloudSaveSettings defaultSettings() => const CloudSaveSettings();

  CloudSaveSettings copyWith({
    bool? autoSaveEnabled,
    bool? wifiOnlyMode,
    bool? showNotifications,
  }) {
    return CloudSaveSettings(
      autoSaveEnabled: autoSaveEnabled ?? this.autoSaveEnabled,
      wifiOnlyMode: wifiOnlyMode ?? this.wifiOnlyMode,
      showNotifications: showNotifications ?? this.showNotifications,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CloudSaveSettings &&
        other.autoSaveEnabled == autoSaveEnabled &&
        other.wifiOnlyMode == wifiOnlyMode &&
        other.showNotifications == showNotifications;
  }

  @override
  int get hashCode {
    return Object.hash(autoSaveEnabled, wifiOnlyMode, showNotifications);
  }
}