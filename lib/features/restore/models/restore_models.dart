import 'package:flutter/foundation.dart';

/// Represents the state of a restoration operation
enum RestoreStatus {
  notStarted,
  selectingBackup,
  validatingBackup,
  downloading,
  decrypting,
  importing,
  completed,
  error,
  cancelled,
}

/// Information about an available backup for restoration
class RestoreBackupInfo {
  final String id;
  final String name;
  final int size;
  final DateTime createdTime;
  final DateTime modifiedTime;
  final String? description;
  final bool isValid;
  final String? validationError;

  const RestoreBackupInfo({
    required this.id,
    required this.name,
    required this.size,
    required this.createdTime,
    required this.modifiedTime,
    this.description,
    this.isValid = true,
    this.validationError,
  });

  /// Create a copy with updated validation status
  RestoreBackupInfo copyWith({
    String? id,
    String? name,
    int? size,
    DateTime? createdTime,
    DateTime? modifiedTime,
    String? description,
    bool? isValid,
    String? validationError,
  }) {
    return RestoreBackupInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      size: size ?? this.size,
      createdTime: createdTime ?? this.createdTime,
      modifiedTime: modifiedTime ?? this.modifiedTime,
      description: description ?? this.description,
      isValid: isValid ?? this.isValid,
      validationError: validationError ?? this.validationError,
    );
  }

  /// Format file size for display
  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  String toString() {
    return 'RestoreBackupInfo(id: $id, name: $name, size: $formattedSize, created: $createdTime, valid: $isValid)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RestoreBackupInfo &&
        other.id == id &&
        other.name == name &&
        other.size == size &&
        other.createdTime == createdTime &&
        other.modifiedTime == modifiedTime &&
        other.description == description &&
        other.isValid == isValid &&
        other.validationError == validationError;
  }

  @override
  int get hashCode {
    return Object.hash(id, name, size, createdTime, modifiedTime, description, isValid, validationError);
  }
}

/// Current state of the restoration process
class RestoreState {
  final RestoreStatus status;
  final double? progress;
  final String? currentOperation;
  final String? errorMessage;
  final List<RestoreBackupInfo> availableBackups;
  final RestoreBackupInfo? selectedBackup;
  final RestoreResult? result;

  const RestoreState({
    required this.status,
    this.progress,
    this.currentOperation,
    this.errorMessage,
    this.availableBackups = const [],
    this.selectedBackup,
    this.result,
  });

  /// Create initial state
  factory RestoreState.initial() {
    return const RestoreState(status: RestoreStatus.notStarted);
  }

  /// Create state for backup selection
  factory RestoreState.selectingBackup(List<RestoreBackupInfo> backups) {
    return RestoreState(
      status: RestoreStatus.selectingBackup,
      availableBackups: backups,
    );
  }

  /// Create state for restoration in progress
  factory RestoreState.restoring({
    required String operation,
    double? progress,
    RestoreBackupInfo? selectedBackup,
  }) {
    return RestoreState(
      status: _getStatusFromOperation(operation),
      currentOperation: operation,
      progress: progress,
      selectedBackup: selectedBackup,
    );
  }

  /// Create state for completed restoration
  factory RestoreState.completed(RestoreResult result) {
    return RestoreState(
      status: RestoreStatus.completed,
      result: result,
    );
  }

  /// Create state for error
  factory RestoreState.error(String errorMessage) {
    return RestoreState(
      status: RestoreStatus.error,
      errorMessage: errorMessage,
    );
  }

  /// Create state for cancelled restoration
  factory RestoreState.cancelled() {
    return const RestoreState(status: RestoreStatus.cancelled);
  }

  /// Create a copy with updated values
  RestoreState copyWith({
    RestoreStatus? status,
    double? progress,
    String? currentOperation,
    String? errorMessage,
    List<RestoreBackupInfo>? availableBackups,
    RestoreBackupInfo? selectedBackup,
    RestoreResult? result,
  }) {
    return RestoreState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      currentOperation: currentOperation ?? this.currentOperation,
      errorMessage: errorMessage ?? this.errorMessage,
      availableBackups: availableBackups ?? this.availableBackups,
      selectedBackup: selectedBackup ?? this.selectedBackup,
      result: result ?? this.result,
    );
  }

  /// Whether the restoration is in progress
  bool get isInProgress {
    return status == RestoreStatus.validatingBackup ||
           status == RestoreStatus.downloading ||
           status == RestoreStatus.decrypting ||
           status == RestoreStatus.importing;
  }

  /// Whether the restoration can be cancelled
  bool get canCancel {
    return isInProgress;
  }

  /// Whether backup selection is available
  bool get canSelectBackup {
    return status == RestoreStatus.selectingBackup && availableBackups.isNotEmpty;
  }

  static RestoreStatus _getStatusFromOperation(String operation) {
    if (operation.toLowerCase().contains('validat')) return RestoreStatus.validatingBackup;
    if (operation.toLowerCase().contains('download')) return RestoreStatus.downloading;
    if (operation.toLowerCase().contains('decrypt')) return RestoreStatus.decrypting;
    if (operation.toLowerCase().contains('import')) return RestoreStatus.importing;
    return RestoreStatus.notStarted;
  }

  @override
  String toString() {
    return 'RestoreState(status: $status, progress: $progress, operation: $currentOperation, error: $errorMessage)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RestoreState &&
        other.status == status &&
        other.progress == progress &&
        other.currentOperation == currentOperation &&
        other.errorMessage == errorMessage &&
        listEquals(other.availableBackups, availableBackups) &&
        other.selectedBackup == selectedBackup &&
        other.result == result;
  }

  @override
  int get hashCode {
    return Object.hash(status, progress, currentOperation, errorMessage, availableBackups, selectedBackup, result);
  }
}

/// Result of a restoration operation
class RestoreResult {
  final bool success;
  final Duration duration;
  final Map<String, int>? restoredCounts;
  final String? errorMessage;
  final Map<String, dynamic>? metadata;

  const RestoreResult({
    required this.success,
    required this.duration,
    this.restoredCounts,
    this.errorMessage,
    this.metadata,
  });

  /// Create successful result
  factory RestoreResult.success({
    required Duration duration,
    Map<String, int>? restoredCounts,
    Map<String, dynamic>? metadata,
  }) {
    return RestoreResult(
      success: true,
      duration: duration,
      restoredCounts: restoredCounts,
      metadata: metadata,
    );
  }

  /// Create failure result
  factory RestoreResult.failure({
    required Duration duration,
    required String errorMessage,
    Map<String, dynamic>? metadata,
  }) {
    return RestoreResult(
      success: false,
      duration: duration,
      errorMessage: errorMessage,
      metadata: metadata,
    );
  }

  /// Total number of records restored
  int get totalRestored {
    if (restoredCounts == null) return 0;
    return restoredCounts!.values.fold(0, (sum, count) => sum + count);
  }

  /// Format duration for display
  String get formattedDuration {
    if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
    }
    return '${duration.inSeconds}s';
  }

  @override
  String toString() {
    return 'RestoreResult(success: $success, duration: $formattedDuration, restored: $totalRestored, error: $errorMessage)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RestoreResult &&
        other.success == success &&
        other.duration == duration &&
        mapEquals(other.restoredCounts, restoredCounts) &&
        other.errorMessage == errorMessage &&
        mapEquals(other.metadata, metadata);
  }

  @override
  int get hashCode {
    return Object.hash(success, duration, restoredCounts, errorMessage, metadata);
  }
}

/// Exception thrown during restoration operations
class RestoreException implements Exception {
  final String message;
  final String? code;
  final Exception? originalException;

  const RestoreException(this.message, {this.code, this.originalException});

  @override
  String toString() => 'RestoreException: $message${code != null ? ' (Code: $code)' : ''}';
}