import 'dart:convert';
import 'dart:typed_data';

import 'google_drive_service.dart';
import 'compression_service.dart';
import '../../sync/models/sync_models.dart';

/// Exception thrown when backup file management operations fail
class BackupFileManagerException implements Exception {
  final String message;
  final String? code;
  final Exception? originalException;

  const BackupFileManagerException(this.message, {this.code, this.originalException});

  @override
  String toString() => 'BackupFileManagerException: $message${code != null ? ' (Code: $code)' : ''}';
}

/// Metadata for backup files stored in Google Drive
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
    return timestamp.year == now.year &&
           timestamp.month == now.month &&
           timestamp.day == now.day;
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
enum BackupType {
  full,
  incremental,
  manual,
}

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
    this.maxAge = const Duration(days: 365 * 2), // 2 years
  });

  /// Default retention policy
  static const RetentionPolicy defaultPolicy = RetentionPolicy();

  /// Conservative retention policy (keeps more backups)
  static const RetentionPolicy conservative = RetentionPolicy(
    maxDailyBackups = 60,
    maxMonthlyBackups = 24,
    maxYearlyBackups = 10,
    maxAge = Duration(days: 365 * 5), // 5 years
  );

  /// Minimal retention policy (keeps fewer backups)
  static const RetentionPolicy minimal = RetentionPolicy(
    maxDailyBackups = 7,
    maxMonthlyBackups = 6,
    maxYearlyBackups = 2,
    maxAge = Duration(days: 365), // 1 year
  );
}

/// Service for managing backup files in Google Drive
class BackupFileManager {
  final GoogleDriveService _driveService;
  final String _clinicId;
  final RetentionPolicy _retentionPolicy;
  final bool _compressionEnabled;

  static const String _metadataFileName = 'backup_metadata.json';

  BackupFileManager({
    required GoogleDriveService driveService,
    required String clinicId,
    RetentionPolicy? retentionPolicy,
    bool compressionEnabled = true,
  }) : _driveService = driveService,
       _clinicId = clinicId,
       _retentionPolicy = retentionPolicy ?? RetentionPolicy.defaultPolicy,
       _compressionEnabled = compressionEnabled;

  /// Organize backup files in Google Drive with proper folder structure
  Future<void> organizeBackupFiles() async {
    try {
      if (!_driveService.isAuthenticated) {
        throw BackupFileManagerException('Google Drive not authenticated');
      }

      // Get all backup files
      final backupFiles = await _driveService.listBackupFiles();
      final metadata = await _loadBackupMetadata();

      // Create metadata for files that don't have it
      final updatedMetadata = <String, BackupFileMetadata>{};
      
      for (final file in backupFiles) {
        if (metadata.containsKey(file.id)) {
          updatedMetadata[file.id] = metadata[file.id]!;
        } else {
          // Create metadata for files without it
          final fileMetadata = await _createMetadataFromFile(file);
          if (fileMetadata != null) {
            updatedMetadata[file.id] = fileMetadata;
          }
        }
      }

      // Save updated metadata
      await _saveBackupMetadata(updatedMetadata);

      // Organize files by date (create year/month folders if needed)
      await _organizeFilesByDate(updatedMetadata.values.toList());

    } catch (e) {
      throw BackupFileManagerException(
        'Failed to organize backup files: ${e.toString()}',
        originalException: e is Exception ? e : Exception(e.toString()),
      );
    }
  }

  /// Enforce retention policy by deleting old backups
  Future<List<String>> enforceRetentionPolicy() async {
    try {
      if (!_driveService.isAuthenticated) {
        throw BackupFileManagerException('Google Drive not authenticated');
      }

      final metadata = await _loadBackupMetadata();
      final backupsByDate = _groupBackupsByDate(metadata.values.toList());
      final filesToDelete = <String>[];

      // Apply daily retention policy
      final dailyFilesToDelete = _applyDailyRetention(backupsByDate);
      filesToDelete.addAll(dailyFilesToDelete);

      // Apply monthly retention policy
      final monthlyFilesToDelete = _applyMonthlyRetention(backupsByDate);
      filesToDelete.addAll(monthlyFilesToDelete);

      // Apply yearly retention policy
      final yearlyFilesToDelete = _applyYearlyRetention(backupsByDate);
      filesToDelete.addAll(yearlyFilesToDelete);

      // Apply age-based retention policy
      final ageFilesToDelete = _applyAgeRetention(metadata.values.toList());
      filesToDelete.addAll(ageFilesToDelete);

      // Remove duplicates
      final uniqueFilesToDelete = filesToDelete.toSet().toList();

      // Delete files
      for (final fileId in uniqueFilesToDelete) {
        try {
          await _driveService.deleteFile(fileId);
          metadata.remove(fileId);
        } catch (e) {
          // Log error but continue with other deletions
          print('Failed to delete backup file $fileId: ${e.toString()}');
        }
      }

      // Update metadata after deletions
      await _saveBackupMetadata(metadata);

      return uniqueFilesToDelete;

    } catch (e) {
      throw BackupFileManagerException(
        'Failed to enforce retention policy: ${e.toString()}',
        originalException: e is Exception ? e : Exception(e.toString()),
      );
    }
  }

  /// Detect and recover from backup file corruption
  Future<List<BackupFileMetadata>> detectCorruptedBackups() async {
    try {
      if (!_driveService.isAuthenticated) {
        throw BackupFileManagerException('Google Drive not authenticated');
      }

      final metadata = await _loadBackupMetadata();
      final corruptedBackups = <BackupFileMetadata>[];

      for (final backupMetadata in metadata.values) {
        try {
          // Validate file integrity
          final isValid = await _validateBackupIntegrity(backupMetadata);
          if (!isValid) {
            corruptedBackups.add(backupMetadata);
          }
        } catch (e) {
          // If validation fails, consider it corrupted
          corruptedBackups.add(backupMetadata);
        }
      }

      return corruptedBackups;

    } catch (e) {
      throw BackupFileManagerException(
        'Failed to detect corrupted backups: ${e.toString()}',
        originalException: e is Exception ? e : Exception(e.toString()),
      );
    }
  }

  /// Recover from corrupted backup by finding the nearest valid backup
  Future<BackupFileMetadata?> findNearestValidBackup(DateTime targetDate) async {
    try {
      final metadata = await _loadBackupMetadata();
      final validBackups = <BackupFileMetadata>[];

      // Filter out corrupted backups
      for (final backupMetadata in metadata.values) {
        try {
          final isValid = await _validateBackupIntegrity(backupMetadata);
          if (isValid) {
            validBackups.add(backupMetadata);
          }
        } catch (e) {
          // Skip corrupted backups
          continue;
        }
      }

      if (validBackups.isEmpty) {
        return null;
      }

      // Sort by proximity to target date
      validBackups.sort((a, b) {
        final aDiff = (a.timestamp.difference(targetDate)).abs();
        final bDiff = (b.timestamp.difference(targetDate)).abs();
        return aDiff.compareTo(bDiff);
      });

      return validBackups.first;

    } catch (e) {
      throw BackupFileManagerException(
        'Failed to find nearest valid backup: ${e.toString()}',
        originalException: e is Exception ? e : Exception(e.toString()),
      );
    }
  }

  /// Get backup file statistics
  Future<BackupStatistics> getBackupStatistics() async {
    try {
      final metadata = await _loadBackupMetadata();
      final backups = metadata.values.toList();

      if (backups.isEmpty) {
        return BackupStatistics.empty();
      }

      // Calculate statistics
      final totalSize = backups.fold<int>(0, (sum, backup) => sum + backup.size);
      final oldestBackup = backups.reduce((a, b) => a.timestamp.isBefore(b.timestamp) ? a : b);
      final newestBackup = backups.reduce((a, b) => a.timestamp.isAfter(b.timestamp) ? a : b);

      final backupsByType = <BackupType, int>{};
      final backupsByDevice = <String, int>{};
      
      for (final backup in backups) {
        backupsByType[backup.type] = (backupsByType[backup.type] ?? 0) + 1;
        backupsByDevice[backup.deviceId] = (backupsByDevice[backup.deviceId] ?? 0) + 1;
      }

      return BackupStatistics(
        totalBackups: backups.length,
        totalSize: totalSize,
        oldestBackup: oldestBackup.timestamp,
        newestBackup: newestBackup.timestamp,
        backupsByType: backupsByType,
        backupsByDevice: backupsByDevice,
      );

    } catch (e) {
      throw BackupFileManagerException(
        'Failed to get backup statistics: ${e.toString()}',
        originalException: e is Exception ? e : Exception(e.toString()),
      );
    }
  }

  /// Create and upload a compressed backup file
  Future<String> createCompressedBackup(
    Map<String, dynamic> backupData,
    String deviceId,
    BackupType type, {
    CompressionService.CompressionAlgorithm? algorithm,
  }) async {
    try {
      if (!_driveService.isAuthenticated) {
        throw BackupFileManagerException('Google Drive not authenticated');
      }

      // Compress the backup data if compression is enabled
      Uint8List finalData;
      Map<String, dynamic> compressionMetadata = {};
      
      if (_compressionEnabled) {
        // Get optimal compression algorithm if not specified
        final compressionAlgorithm = algorithm ?? await CompressionService.getOptimalAlgorithm(backupData);
        
        // Compress the data
        final compressedData = await CompressionService.compressLargeData(
          backupData,
          algorithm: compressionAlgorithm,
        );
        
        finalData = compressedData.data;
        compressionMetadata = {
          'compressed': true,
          'compression_algorithm': compressedData.algorithm,
          'compression_level': compressedData.compressionLevel,
          'original_size': compressedData.originalSize,
          'compressed_size': compressedData.compressedSize,
          'compression_ratio': compressedData.compressionRatio,
          'space_saved': compressedData.spaceSaved,
        };
      } else {
        // No compression, use raw JSON
        final jsonString = jsonEncode(backupData);
        finalData = Uint8List.fromList(utf8.encode(jsonString));
        compressionMetadata = {
          'compressed': false,
          'original_size': finalData.length,
        };
      }

      // Generate filename with compression indicator
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final compressionSuffix = _compressionEnabled ? '.compressed' : '';
      final fileName = 'backup_${_clinicId}_${deviceId}_${timestamp}${compressionSuffix}.enc';

      // Upload to Google Drive
      final fileId = await _driveService.uploadBackupFile(fileName, finalData);

      // Register the backup with metadata
      await registerBackupFile(
        fileId,
        fileName,
        deviceId,
        type,
        finalData.length,
        '', // Checksum will be calculated by encryption service
        additionalData: {
          ...compressionMetadata,
          'backup_type': type.name,
          'clinic_id': _clinicId,
        },
      );

      return fileId;

    } catch (e) {
      throw BackupFileManagerException(
        'Failed to create compressed backup: ${e.toString()}',
        originalException: e is Exception ? e : Exception(e.toString()),
      );
    }
  }

  /// Download and decompress a backup file
  Future<Map<String, dynamic>> downloadAndDecompressBackup(String fileId) async {
    try {
      if (!_driveService.isAuthenticated) {
        throw BackupFileManagerException('Google Drive not authenticated');
      }

      // Get backup metadata
      final metadata = await _loadBackupMetadata();
      final backupMetadata = metadata[fileId];
      
      if (backupMetadata == null) {
        throw BackupFileManagerException('Backup metadata not found for file: $fileId');
      }

      // Download the backup file
      final compressedData = await _driveService.downloadBackupFile(fileId);

      // Check if the backup is compressed
      final isCompressed = backupMetadata.additionalData['compressed'] as bool? ?? false;
      
      if (isCompressed) {
        // Decompress the data
        final algorithm = backupMetadata.additionalData['compression_algorithm'] as String;
        final originalSize = backupMetadata.additionalData['original_size'] as int;
        final compressionLevel = backupMetadata.additionalData['compression_level'] as int;
        
        final compressedDataObj = CompressedData(
          data: Uint8List.fromList(compressedData),
          originalSize: originalSize,
          compressedSize: compressedData.length,
          compressionRatio: compressedData.length / originalSize,
          algorithm: algorithm,
          compressionLevel: compressionLevel,
          timestamp: backupMetadata.timestamp,
        );

        return await CompressionService.decompressData(compressedDataObj);
      } else {
        // No compression, decode directly
        final jsonString = utf8.decode(compressedData);
        return jsonDecode(jsonString) as Map<String, dynamic>;
      }

    } catch (e) {
      throw BackupFileManagerException(
        'Failed to download and decompress backup: ${e.toString()}',
        originalException: e is Exception ? e : Exception(e.toString()),
      );
    }
  }

  /// Get compression statistics for all backups
  Future<CompressionStats> getCompressionStatistics() async {
    try {
      final metadata = await _loadBackupMetadata();
      final compressedDataList = <CompressedData>[];

      for (final backupMetadata in metadata.values) {
        final isCompressed = backupMetadata.additionalData['compressed'] as bool? ?? false;
        
        if (isCompressed) {
          final algorithm = backupMetadata.additionalData['compression_algorithm'] as String;
          final originalSize = backupMetadata.additionalData['original_size'] as int;
          final compressionLevel = backupMetadata.additionalData['compression_level'] as int;
          final compressionRatio = backupMetadata.additionalData['compression_ratio'] as double;

          compressedDataList.add(CompressedData(
            data: Uint8List(0), // We don't need the actual data for stats
            originalSize: originalSize,
            compressedSize: backupMetadata.size,
            compressionRatio: compressionRatio,
            algorithm: algorithm,
            compressionLevel: compressionLevel,
            timestamp: backupMetadata.timestamp,
          ));
        }
      }

      return CompressionService.getCompressionStats(compressedDataList);

    } catch (e) {
      throw BackupFileManagerException(
        'Failed to get compression statistics: ${e.toString()}',
        originalException: e is Exception ? e : Exception(e.toString()),
      );
    }
  }

  /// Register a new backup file with metadata
  Future<void> registerBackupFile(
    String fileId,
    String fileName,
    String deviceId,
    BackupType type,
    int size,
    String checksum, {
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      final metadata = await _loadBackupMetadata();
      
      final backupMetadata = BackupFileMetadata(
        fileId: fileId,
        fileName: fileName,
        clinicId: _clinicId,
        deviceId: deviceId,
        timestamp: DateTime.now(),
        type: type,
        version: 1,
        size: size,
        checksum: checksum,
        additionalData: additionalData ?? {},
      );

      metadata[fileId] = backupMetadata;
      await _saveBackupMetadata(metadata);

    } catch (e) {
      throw BackupFileManagerException(
        'Failed to register backup file: ${e.toString()}',
        originalException: e is Exception ? e : Exception(e.toString()),
      );
    }
  }

  // Private helper methods

  /// Load backup metadata from Google Drive
  Future<Map<String, BackupFileMetadata>> _loadBackupMetadata() async {
    try {
      final backupFiles = await _driveService.listBackupFiles();
      final metadataFile = backupFiles.firstWhere(
        (file) => file.name == _metadataFileName,
        orElse: () => throw BackupFileManagerException('Metadata file not found'),
      );

      final metadataBytes = await _driveService.downloadBackupFile(metadataFile.id);
      final metadataJson = utf8.decode(metadataBytes);
      final metadataMap = jsonDecode(metadataJson) as Map<String, dynamic>;

      final metadata = <String, BackupFileMetadata>{};
      for (final entry in metadataMap.entries) {
        metadata[entry.key] = BackupFileMetadata.fromJson(entry.value as Map<String, dynamic>);
      }

      return metadata;
    } catch (e) {
      // If metadata file doesn't exist or is corrupted, return empty map
      return <String, BackupFileMetadata>{};
    }
  }

  /// Save backup metadata to Google Drive
  Future<void> _saveBackupMetadata(Map<String, BackupFileMetadata> metadata) async {
    try {
      final metadataMap = <String, dynamic>{};
      for (final entry in metadata.entries) {
        metadataMap[entry.key] = entry.value.toJson();
      }

      final metadataJson = jsonEncode(metadataMap);
      final metadataBytes = utf8.encode(metadataJson);

      // Check if metadata file already exists
      final backupFiles = await _driveService.listBackupFiles();
      final existingMetadataFile = backupFiles.where((file) => file.name == _metadataFileName).firstOrNull;

      if (existingMetadataFile != null) {
        // Update existing file
        await _driveService.updateBackupFile(existingMetadataFile.id, _metadataFileName, metadataBytes);
      } else {
        // Create new file
        await _driveService.uploadBackupFile(_metadataFileName, metadataBytes);
      }
    } catch (e) {
      throw BackupFileManagerException(
        'Failed to save backup metadata: ${e.toString()}',
        originalException: e is Exception ? e : Exception(e.toString()),
      );
    }
  }

  /// Create metadata from existing backup file
  Future<BackupFileMetadata?> _createMetadataFromFile(BackupFileInfo file) async {
    try {
      // Parse filename to extract information
      final fileNameParts = file.name.split('_');
      if (fileNameParts.length < 4) {
        return null; // Invalid filename format
      }

      // Extract clinic ID and timestamp from filename
      final clinicId = fileNameParts[2];
      final timestampStr = fileNameParts[3].replaceAll('.enc', '').replaceAll('-', ':');
      
      DateTime timestamp;
      try {
        timestamp = DateTime.parse(timestampStr);
      } catch (e) {
        timestamp = file.createdTime;
      }

      // Determine backup type from filename or default to full
      BackupType type = BackupType.full;
      if (file.name.contains('incremental')) {
        type = BackupType.incremental;
      } else if (file.name.contains('manual')) {
        type = BackupType.manual;
      }

      return BackupFileMetadata(
        fileId: file.id,
        fileName: file.name,
        clinicId: clinicId,
        deviceId: 'unknown', // Cannot determine from filename
        timestamp: timestamp,
        type: type,
        version: 1,
        size: file.size,
        checksum: '', // Cannot determine without downloading
      );
    } catch (e) {
      return null;
    }
  }

  /// Organize files by date into folder structure
  Future<void> _organizeFilesByDate(List<BackupFileMetadata> backups) async {
    // For now, we'll keep files in the main backup folder
    // In a more sophisticated implementation, you could create year/month subfolders
    // This would require additional Google Drive API calls to create folders and move files
  }

  /// Group backups by date for retention policy application
  Map<String, List<BackupFileMetadata>> _groupBackupsByDate(List<BackupFileMetadata> backups) {
    final backupsByDate = <String, List<BackupFileMetadata>>{};
    
    for (final backup in backups) {
      final dateKey = '${backup.timestamp.year}-${backup.timestamp.month.toString().padLeft(2, '0')}-${backup.timestamp.day.toString().padLeft(2, '0')}';
      backupsByDate.putIfAbsent(dateKey, () => []).add(backup);
    }

    return backupsByDate;
  }

  /// Apply daily retention policy
  List<String> _applyDailyRetention(Map<String, List<BackupFileMetadata>> backupsByDate) {
    final filesToDelete = <String>[];
    final sortedDates = backupsByDate.keys.toList()..sort((a, b) => b.compareTo(a));

    // Keep only the specified number of daily backups
    if (sortedDates.length > _retentionPolicy.maxDailyBackups) {
      final datesToDelete = sortedDates.skip(_retentionPolicy.maxDailyBackups);
      
      for (final date in datesToDelete) {
        final backupsForDate = backupsByDate[date]!;
        // Keep the latest backup for each day, delete the rest
        backupsForDate.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        for (int i = 1; i < backupsForDate.length; i++) {
          filesToDelete.add(backupsForDate[i].fileId);
        }
      }
    }

    return filesToDelete;
  }

  /// Apply monthly retention policy
  List<String> _applyMonthlyRetention(Map<String, List<BackupFileMetadata>> backupsByDate) {
    final filesToDelete = <String>[];
    final backupsByMonth = <String, List<BackupFileMetadata>>{};

    // Group by month
    for (final entry in backupsByDate.entries) {
      final date = DateTime.parse('${entry.key}T00:00:00');
      final monthKey = '${date.year}-${date.month.toString().padLeft(2, '0')}';
      
      for (final backup in entry.value) {
        backupsByMonth.putIfAbsent(monthKey, () => []).add(backup);
      }
    }

    final sortedMonths = backupsByMonth.keys.toList()..sort((a, b) => b.compareTo(a));

    // Keep only the specified number of monthly backups
    if (sortedMonths.length > _retentionPolicy.maxMonthlyBackups) {
      final monthsToDelete = sortedMonths.skip(_retentionPolicy.maxMonthlyBackups);
      
      for (final month in monthsToDelete) {
        final backupsForMonth = backupsByMonth[month]!;
        // Keep the latest backup for each month, delete the rest
        backupsForMonth.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        for (int i = 1; i < backupsForMonth.length; i++) {
          filesToDelete.add(backupsForMonth[i].fileId);
        }
      }
    }

    return filesToDelete;
  }

  /// Apply yearly retention policy
  List<String> _applyYearlyRetention(Map<String, List<BackupFileMetadata>> backupsByDate) {
    final filesToDelete = <String>[];
    final backupsByYear = <String, List<BackupFileMetadata>>{};

    // Group by year
    for (final entry in backupsByDate.entries) {
      final date = DateTime.parse('${entry.key}T00:00:00');
      final yearKey = date.year.toString();
      
      for (final backup in entry.value) {
        backupsByYear.putIfAbsent(yearKey, () => []).add(backup);
      }
    }

    final sortedYears = backupsByYear.keys.toList()..sort((a, b) => b.compareTo(a));

    // Keep only the specified number of yearly backups
    if (sortedYears.length > _retentionPolicy.maxYearlyBackups) {
      final yearsToDelete = sortedYears.skip(_retentionPolicy.maxYearlyBackups);
      
      for (final year in yearsToDelete) {
        final backupsForYear = backupsByYear[year]!;
        // Keep the latest backup for each year, delete the rest
        backupsForYear.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        for (int i = 1; i < backupsForYear.length; i++) {
          filesToDelete.add(backupsForYear[i].fileId);
        }
      }
    }

    return filesToDelete;
  }

  /// Apply age-based retention policy
  List<String> _applyAgeRetention(List<BackupFileMetadata> backups) {
    final filesToDelete = <String>[];
    final cutoffDate = DateTime.now().subtract(_retentionPolicy.maxAge);

    for (final backup in backups) {
      if (backup.timestamp.isBefore(cutoffDate)) {
        filesToDelete.add(backup.fileId);
      }
    }

    return filesToDelete;
  }

  /// Validate backup file integrity
  Future<bool> _validateBackupIntegrity(BackupFileMetadata metadata) async {
    try {
      // Basic validation - check if file exists and has expected size
      final backupFiles = await _driveService.listBackupFiles();
      final file = backupFiles.firstWhere(
        (f) => f.id == metadata.fileId,
        orElse: () => throw BackupFileManagerException('Backup file not found'),
      );

      // Check if file size matches metadata
      if (file.size != metadata.size) {
        return false;
      }

      // If checksum is available, validate it
      if (metadata.checksum.isNotEmpty) {
        return await _driveService.validateBackupIntegrity(metadata.fileId, metadata.checksum);
      }

      return true;
    } catch (e) {
      return false;
    }
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
      backupsByType: {},
      backupsByDevice: {},
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