import 'dart:convert';
import 'dart:typed_data';

/// Exception thrown when backup file management operations fail
class BackupFileManagerException implements Exception {
  final String message;
  final String? code;
  final Exception? originalException;

  const BackupFileManagerException(this.message, {this.code, this.originalException});

  @override
  String toString() => 'BackupFileManagerException: $message${code != null ? ' (Code: $code)' : ''}';
}

/// Metadata for backup files (legacy)
class BackupFileMetadata {
  final String fileId;
  final String fileName;
  final String clinicId;
  final String deviceId;
  final DateTime timestamp;
  final BackupType type;
  final int version;
  final int size;
  final String checksum;
  final Map<String, dynamic> additionalData;

  const BackupFileMetadata({
    required this.fileId,
    required this.fileName,
    required this.clinicId,
    required this.deviceId,
    required this.timestamp,
    required this.type,
    required this.version,
    required this.size,
    required this.checksum,
    this.additionalData = const {},
  });

  factory BackupFileMetadata.fromJson(Map<String, dynamic> json) {
    return BackupFileMetadata(
      fileId: json['file_id'] as String,
      fileName: json['file_name'] as String,
      clinicId: json['clinic_id'] as String,
      deviceId: json['device_id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      type: BackupType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => BackupType.full,
      ),
      version: json['version'] as int,
      size: json['size'] as int,
      checksum: json['checksum'] as String,
      additionalData: Map<String, dynamic>.from(json['additional_data'] as Map? ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'file_id': fileId,
      'file_name': fileName,
      'clinic_id': clinicId,
      'device_id': deviceId,
      'timestamp': timestamp.toIso8601String(),
      'type': type.name,
      'version': version,
      'size': size,
      'checksum': checksum,
      'additional_data': additionalData,
    };
  }

  /// Get formatted file size
  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Get age of backup
  Duration get age => DateTime.now().difference(timestamp);

  /// Check if backup is from today
  bool get isToday {
    final now = DateTime.now();
    return timestamp.year == now.year && timestamp.month == now.month && timestamp.day == now.day;
  }

  /// Check if backup is from this month
  bool get isThisMonth {
    final now = DateTime.now();
    return timestamp.year == now.year && timestamp.month == now.month;
  }

  @override
  String toString() {
    return 'BackupFileMetadata(fileId: $fileId, clinicId: $clinicId, timestamp: $timestamp, type: $type, size: $formattedSize)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BackupFileMetadata &&
        other.fileId == fileId &&
        other.fileName == fileName &&
        other.clinicId == clinicId &&
        other.deviceId == deviceId &&
        other.timestamp == timestamp &&
        other.type == type &&
        other.version == version &&
        other.size == size &&
        other.checksum == checksum;
  }

  @override
  int get hashCode {
    return Object.hash(fileId, fileName, clinicId, deviceId, timestamp, type, version, size, checksum);
  }
}

/// Types of backup files
enum BackupType { full, incremental, manual }

/// Retention policy configuration
class RetentionPolicy {
  final int maxDailyBackups;
  final int maxMonthlyBackups;
  final int maxYearlyBackups;
  final Duration maxAge;

  const RetentionPolicy({
    this.maxDailyBackups = 30,
    this.maxMonthlyBackups = 12,
    this.maxYearlyBackups = 5,
    this.maxAge = const Duration(days: 365 * 2),
  });

  /// Default retention policy
  static const RetentionPolicy defaultPolicy = RetentionPolicy();

  /// Conservative retention policy (keeps more backups)
  static const RetentionPolicy conservative = RetentionPolicy(
    maxDailyBackups: 60,
    maxMonthlyBackups: 24,
    maxYearlyBackups: 10,
    maxAge: Duration(days: 365 * 5),
  );

  /// Minimal retention policy (keeps fewer backups)
  static const RetentionPolicy minimal = RetentionPolicy(
    maxDailyBackups: 7,
    maxMonthlyBackups: 6,
    maxYearlyBackups: 2,
    maxAge: Duration(days: 365),
  );
}

/// Legacy BackupFileManager stub (Google Drive removed). No-op methods to keep build green.
class BackupFileManager {
  final String _clinicId;
  final RetentionPolicy _retentionPolicy;
  final bool _compressionEnabled;

  static const String _metadataFileName = 'backup_metadata.json';

  BackupFileManager({
    required String clinicId,
    RetentionPolicy? retentionPolicy,
    bool compressionEnabled = true,
  })  : _clinicId = clinicId,
        _retentionPolicy = retentionPolicy ?? RetentionPolicy.defaultPolicy,
        _compressionEnabled = compressionEnabled;

  Future<void> organizeBackupFiles() async {
    throw const BackupFileManagerException('Deprecated: BackupFileManager is no longer used');
  }

  Future<List<String>> enforceRetentionPolicy() async {
    throw const BackupFileManagerException('Deprecated: BackupFileManager is no longer used');
  }

  Future<List<BackupFileMetadata>> detectCorruptedBackups() async {
    throw const BackupFileManagerException('Deprecated: BackupFileManager is no longer used');
  }

  Future<BackupFileMetadata?> findNearestValidBackup(DateTime targetDate) async {
    throw const BackupFileManagerException('Deprecated: BackupFileManager is no longer used');
  }

  Future<BackupStatistics> getBackupStatistics() async {
    return BackupStatistics.empty();
  }

  Future<String> createCompressedBackup(
    Map<String, dynamic> backupData,
    String deviceId,
    BackupType type, {
    dynamic algorithm,
  }) async {
    throw const BackupFileManagerException('Deprecated: BackupFileManager is no longer used');
  }

  Future<Map<String, dynamic>> downloadAndDecompressBackup(String fileId) async {
    throw const BackupFileManagerException('Deprecated: BackupFileManager is no longer used');
  }

  Future<CompressionStats> getCompressionStatistics() async {
    return CompressionStats.empty();
  }

  Future<void> registerBackupFile(
    String fileId,
    String fileName,
    String deviceId,
    BackupType type,
    int size,
    String checksum, {
    Map<String, dynamic>? additionalData,
  }) async {
    throw const BackupFileManagerException('Deprecated: BackupFileManager is no longer used');
  }
}

/// Statistics about backup files
class BackupStatistics {
  final int totalBackups;
  final int totalSize;
  final DateTime oldestBackup;
  final DateTime newestBackup;
  final Map<BackupType, int> backupsByType;
  final Map<String, int> backupsByDevice;

  const BackupStatistics({
    required this.totalBackups,
    required this.totalSize,
    required this.oldestBackup,
    required this.newestBackup,
    required this.backupsByType,
    required this.backupsByDevice,
  });

  factory BackupStatistics.empty() {
    final now = DateTime.now();
    return BackupStatistics(
      totalBackups: 0,
      totalSize: 0,
      oldestBackup: now,
      newestBackup: now,
      backupsByType: const {},
      backupsByDevice: const {},
    );
  }

  /// Get formatted total size
  String get formattedTotalSize {
    if (totalSize < 1024) return '$totalSize B';
    if (totalSize < 1024 * 1024) return '${(totalSize / 1024).toStringAsFixed(1)} KB';
    if (totalSize < 1024 * 1024 * 1024) return '${(totalSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(totalSize / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Get age of backup collection
  Duration get backupSpan => newestBackup.difference(oldestBackup);

  @override
  String toString() {
    return 'BackupStatistics(total: $totalBackups, size: $formattedTotalSize, span: ${backupSpan.inDays} days)';
  }
}

/// Compression statistics (legacy placeholder)
class CompressionStats {
  final int totalFiles;
  final int totalOriginalSize;
  final int totalCompressedSize;
  final double averageCompressionRatio;
  final int spaceSaved;
  final Map<String, int> algorithmUsage;

  const CompressionStats({
    required this.totalFiles,
    required this.totalOriginalSize,
    required this.totalCompressedSize,
    required this.averageCompressionRatio,
    required this.spaceSaved,
    required this.algorithmUsage,
  });

  factory CompressionStats.empty() {
    return const CompressionStats(
      totalFiles: 0,
      totalOriginalSize: 0,
      totalCompressedSize: 0,
      averageCompressionRatio: 0.0,
      spaceSaved: 0,
      algorithmUsage: const {},
    );
  }
}