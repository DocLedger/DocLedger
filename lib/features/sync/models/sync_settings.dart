/// Model representing sync and backup settings
class SyncSettings {
  final bool autoBackupEnabled;
  final bool wifiOnlySync;
  final int backupFrequencyMinutes;
  final bool showSyncNotifications;
  final int maxBackupRetentionDays;
  final bool enableConflictResolution;
  final String conflictResolutionStrategy;
  final bool encryptBackups; // new

  const SyncSettings({
    this.autoBackupEnabled = true,
    this.wifiOnlySync = true,
    this.backupFrequencyMinutes = 30,
    this.showSyncNotifications = true,
    this.maxBackupRetentionDays = 30,
    this.enableConflictResolution = true,
    this.conflictResolutionStrategy = 'last_write_wins',
    this.encryptBackups = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'auto_backup_enabled': autoBackupEnabled,
      'wifi_only_sync': wifiOnlySync,
      'backup_frequency_minutes': backupFrequencyMinutes,
      'show_sync_notifications': showSyncNotifications,
      'max_backup_retention_days': maxBackupRetentionDays,
      'enable_conflict_resolution': enableConflictResolution,
      'conflict_resolution_strategy': conflictResolutionStrategy,
      'encrypt_backups': encryptBackups,
    };
  }

  static SyncSettings fromJson(Map<String, dynamic> json) {
    return SyncSettings(
      autoBackupEnabled: json['auto_backup_enabled'] as bool? ?? true,
      wifiOnlySync: json['wifi_only_sync'] as bool? ?? true,
      backupFrequencyMinutes: json['backup_frequency_minutes'] as int? ?? 30,
      showSyncNotifications: json['show_sync_notifications'] as bool? ?? true,
      maxBackupRetentionDays: json['max_backup_retention_days'] as int? ?? 30,
      enableConflictResolution: json['enable_conflict_resolution'] as bool? ?? true,
      conflictResolutionStrategy: json['conflict_resolution_strategy'] as String? ?? 'last_write_wins',
      encryptBackups: json['encrypt_backups'] as bool? ?? true,
    );
  }

  /// Default settings factory method
  static SyncSettings defaultSettings() => const SyncSettings();

  SyncSettings copyWith({
    bool? autoBackupEnabled,
    bool? wifiOnlySync,
    int? backupFrequencyMinutes,
    bool? showSyncNotifications,
    int? maxBackupRetentionDays,
    bool? enableConflictResolution,
    String? conflictResolutionStrategy,
    bool? encryptBackups,
  }) {
    return SyncSettings(
      autoBackupEnabled: autoBackupEnabled ?? this.autoBackupEnabled,
      wifiOnlySync: wifiOnlySync ?? this.wifiOnlySync,
      backupFrequencyMinutes: backupFrequencyMinutes ?? this.backupFrequencyMinutes,
      showSyncNotifications: showSyncNotifications ?? this.showSyncNotifications,
      maxBackupRetentionDays: maxBackupRetentionDays ?? this.maxBackupRetentionDays,
      enableConflictResolution: enableConflictResolution ?? this.enableConflictResolution,
      conflictResolutionStrategy: conflictResolutionStrategy ?? this.conflictResolutionStrategy,
      encryptBackups: encryptBackups ?? this.encryptBackups,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SyncSettings &&
        other.autoBackupEnabled == autoBackupEnabled &&
        other.wifiOnlySync == wifiOnlySync &&
        other.backupFrequencyMinutes == backupFrequencyMinutes &&
        other.showSyncNotifications == showSyncNotifications &&
        other.maxBackupRetentionDays == maxBackupRetentionDays &&
        other.enableConflictResolution == enableConflictResolution &&
        other.conflictResolutionStrategy == conflictResolutionStrategy &&
        other.encryptBackups == encryptBackups;
  }

  @override
  int get hashCode {
    return Object.hash(
      autoBackupEnabled,
      wifiOnlySync,
      backupFrequencyMinutes,
      showSyncNotifications,
      maxBackupRetentionDays,
      enableConflictResolution,
      conflictResolutionStrategy,
      encryptBackups,
    );
  }
}

/// Model representing Google Drive storage information
class DriveStorageInfo {
  final int totalBytes;
  final int usedBytes;
  final int docLedgerUsedBytes;
  final int availableBytes;
  final int backupFileCount;
  final DateTime? lastUpdated;

  const DriveStorageInfo({
    required this.totalBytes,
    required this.usedBytes,
    required this.docLedgerUsedBytes,
    required this.availableBytes,
    required this.backupFileCount,
    this.lastUpdated,
  });

  double get usagePercentage => totalBytes > 0 ? (usedBytes / totalBytes) * 100 : 0;
  double get docLedgerUsagePercentage => totalBytes > 0 ? (docLedgerUsedBytes / totalBytes) * 100 : 0;

  String get formattedTotalSize => _formatBytes(totalBytes);
  String get formattedUsedSize => _formatBytes(usedBytes);
  String get formattedDocLedgerSize => _formatBytes(docLedgerUsedBytes);
  String get formattedAvailableSize => _formatBytes(availableBytes);

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Map<String, dynamic> toJson() {
    return {
      'total_bytes': totalBytes,
      'used_bytes': usedBytes,
      'docledger_used_bytes': docLedgerUsedBytes,
      'available_bytes': availableBytes,
      'backup_file_count': backupFileCount,
      'last_updated': lastUpdated?.toIso8601String(),
    };
  }

  static DriveStorageInfo fromJson(Map<String, dynamic> json) {
    return DriveStorageInfo(
      totalBytes: json['total_bytes'] as int,
      usedBytes: json['used_bytes'] as int,
      docLedgerUsedBytes: json['docledger_used_bytes'] as int,
      availableBytes: json['available_bytes'] as int,
      backupFileCount: json['backup_file_count'] as int,
      lastUpdated: json['last_updated'] != null
          ? DateTime.parse(json['last_updated'] as String)
          : null,
    );
  }
}