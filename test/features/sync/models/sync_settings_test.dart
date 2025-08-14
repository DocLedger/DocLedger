import 'package:flutter_test/flutter_test.dart';
import 'package:doc_ledger/features/sync/models/sync_settings.dart';

void main() {
  group('SyncSettings Tests', () {
    late SyncSettings testSettings;

    setUp(() {
      testSettings = SyncSettings(
        autoBackupEnabled: true,
        wifiOnlySync: true,
        backupFrequencyMinutes: 30,
        showSyncNotifications: true,
        maxBackupRetentionDays: 30,
        enableConflictResolution: true,
        conflictResolutionStrategy: 'last_write_wins',
      );
    });

    test('should create SyncSettings with all properties', () {
      expect(testSettings.autoBackupEnabled, isTrue);
      expect(testSettings.wifiOnlySync, isTrue);
      expect(testSettings.backupFrequencyMinutes, equals(30));
      expect(testSettings.showSyncNotifications, isTrue);
      expect(testSettings.maxBackupRetentionDays, equals(30));
      expect(testSettings.enableConflictResolution, isTrue);
      expect(testSettings.conflictResolutionStrategy, equals('last_write_wins'));
    });

    test('should create default settings correctly', () {
      final defaultSettings = SyncSettings.defaultSettings();

      expect(defaultSettings.autoBackupEnabled, isTrue);
      expect(defaultSettings.wifiOnlySync, isTrue);
      expect(defaultSettings.backupFrequencyMinutes, equals(30));
      expect(defaultSettings.showSyncNotifications, isTrue);
      expect(defaultSettings.maxBackupRetentionDays, equals(30));
      expect(defaultSettings.enableConflictResolution, isTrue);
      expect(defaultSettings.conflictResolutionStrategy, equals('last_write_wins'));
    });

    test('should serialize to JSON correctly', () {
      final json = testSettings.toJson();

      expect(json['auto_backup_enabled'], isTrue);
      expect(json['wifi_only_sync'], isTrue);
      expect(json['backup_frequency_minutes'], equals(30));
      expect(json['show_sync_notifications'], isTrue);
      expect(json['max_backup_retention_days'], equals(30));
      expect(json['enable_conflict_resolution'], isTrue);
      expect(json['conflict_resolution_strategy'], equals('last_write_wins'));
    });

    test('should deserialize from JSON correctly', () {
      final json = testSettings.toJson();
      final deserializedSettings = SyncSettings.fromJson(json);

      expect(deserializedSettings.autoBackupEnabled, equals(testSettings.autoBackupEnabled));
      expect(deserializedSettings.wifiOnlySync, equals(testSettings.wifiOnlySync));
      expect(deserializedSettings.backupFrequencyMinutes, equals(testSettings.backupFrequencyMinutes));
      expect(deserializedSettings.showSyncNotifications, equals(testSettings.showSyncNotifications));
      expect(deserializedSettings.maxBackupRetentionDays, equals(testSettings.maxBackupRetentionDays));
      expect(deserializedSettings.enableConflictResolution, equals(testSettings.enableConflictResolution));
      expect(deserializedSettings.conflictResolutionStrategy, equals(testSettings.conflictResolutionStrategy));
    });

    test('should handle missing values in JSON with defaults', () {
      final minimalJson = {
        'auto_backup_enabled': false,
        'wifi_only_sync': false,
      };

      final settings = SyncSettings.fromJson(minimalJson);

      expect(settings.autoBackupEnabled, isFalse);
      expect(settings.wifiOnlySync, isFalse);
      expect(settings.backupFrequencyMinutes, equals(30)); // Default
      expect(settings.showSyncNotifications, isTrue); // Default
      expect(settings.maxBackupRetentionDays, equals(30)); // Default
      expect(settings.enableConflictResolution, isTrue); // Default
      expect(settings.conflictResolutionStrategy, equals('last_write_wins')); // Default
    });

    test('should implement equality correctly', () {
      final sameSettings = SyncSettings(
        autoBackupEnabled: true,
        wifiOnlySync: true,
        backupFrequencyMinutes: 30,
        showSyncNotifications: true,
        maxBackupRetentionDays: 30,
        enableConflictResolution: true,
        conflictResolutionStrategy: 'last_write_wins',
      );

      expect(testSettings == sameSettings, isTrue);
      expect(testSettings.hashCode, equals(sameSettings.hashCode));

      final differentSettings = sameSettings.copyWith(autoBackupEnabled: false);
      expect(testSettings == differentSettings, isFalse);
    });

    test('should copy with modifications', () {
      final copiedSettings = testSettings.copyWith(
        autoBackupEnabled: false,
        backupFrequencyMinutes: 60,
        conflictResolutionStrategy: 'manual',
      );

      expect(copiedSettings.autoBackupEnabled, isFalse);
      expect(copiedSettings.backupFrequencyMinutes, equals(60));
      expect(copiedSettings.conflictResolutionStrategy, equals('manual'));
      
      // Other properties should remain the same
      expect(copiedSettings.wifiOnlySync, equals(testSettings.wifiOnlySync));
      expect(copiedSettings.maxBackupRetentionDays, equals(testSettings.maxBackupRetentionDays));
      expect(copiedSettings.enableConflictResolution, equals(testSettings.enableConflictResolution));
    });
  });

  group('DriveStorageInfo Tests', () {
    late DriveStorageInfo testStorageInfo;
    late DateTime testLastUpdated;

    setUp(() {
      testLastUpdated = DateTime(2024, 1, 15, 12, 0);
      testStorageInfo = DriveStorageInfo(
        totalBytes: 15000000000, // 15 GB
        usedBytes: 5000000000,   // 5 GB
        docLedgerUsedBytes: 100000000, // 100 MB
        availableBytes: 10000000000,   // 10 GB
        backupFileCount: 25,
        lastUpdated: testLastUpdated,
      );
    });

    test('should create DriveStorageInfo with all properties', () {
      expect(testStorageInfo.totalBytes, equals(15000000000));
      expect(testStorageInfo.usedBytes, equals(5000000000));
      expect(testStorageInfo.docLedgerUsedBytes, equals(100000000));
      expect(testStorageInfo.availableBytes, equals(10000000000));
      expect(testStorageInfo.backupFileCount, equals(25));
      expect(testStorageInfo.lastUpdated, equals(testLastUpdated));
    });

    test('should calculate usage percentages correctly', () {
      expect(testStorageInfo.usagePercentage, closeTo(33.33, 0.01));
      expect(testStorageInfo.docLedgerUsagePercentage, closeTo(0.67, 0.01));
    });

    test('should format sizes correctly', () {
      expect(testStorageInfo.formattedTotalSize, equals('14.0 GB'));
      expect(testStorageInfo.formattedUsedSize, equals('4.7 GB'));
      expect(testStorageInfo.formattedDocLedgerSize, equals('95.4 MB'));
      expect(testStorageInfo.formattedAvailableSize, equals('9.3 GB'));
    });

    test('should format bytes correctly for different sizes', () {
      final smallStorage = DriveStorageInfo(
        totalBytes: 512,
        usedBytes: 256,
        docLedgerUsedBytes: 128,
        availableBytes: 256,
        backupFileCount: 1,
      );

      expect(smallStorage.formattedTotalSize, equals('512 B'));
      expect(smallStorage.formattedUsedSize, equals('256 B'));

      final kbStorage = DriveStorageInfo(
        totalBytes: 2048,
        usedBytes: 1024,
        docLedgerUsedBytes: 512,
        availableBytes: 1024,
        backupFileCount: 2,
      );

      expect(kbStorage.formattedTotalSize, equals('2.0 KB'));
      expect(kbStorage.formattedUsedSize, equals('1.0 KB'));
    });

    test('should serialize to JSON correctly', () {
      final json = testStorageInfo.toJson();

      expect(json['total_bytes'], equals(15000000000));
      expect(json['used_bytes'], equals(5000000000));
      expect(json['docledger_used_bytes'], equals(100000000));
      expect(json['available_bytes'], equals(10000000000));
      expect(json['backup_file_count'], equals(25));
      expect(json['last_updated'], equals('2024-01-15T12:00:00.000'));
    });

    test('should deserialize from JSON correctly', () {
      final json = testStorageInfo.toJson();
      final deserialized = DriveStorageInfo.fromJson(json);

      expect(deserialized.totalBytes, equals(testStorageInfo.totalBytes));
      expect(deserialized.usedBytes, equals(testStorageInfo.usedBytes));
      expect(deserialized.docLedgerUsedBytes, equals(testStorageInfo.docLedgerUsedBytes));
      expect(deserialized.availableBytes, equals(testStorageInfo.availableBytes));
      expect(deserialized.backupFileCount, equals(testStorageInfo.backupFileCount));
      expect(deserialized.lastUpdated, equals(testStorageInfo.lastUpdated));
    });

    test('should handle null lastUpdated in JSON', () {
      final storageWithoutUpdate = DriveStorageInfo(
        totalBytes: 1000000000,
        usedBytes: 500000000,
        docLedgerUsedBytes: 50000000,
        availableBytes: 500000000,
        backupFileCount: 10,
        lastUpdated: null,
      );

      final json = storageWithoutUpdate.toJson();
      expect(json['last_updated'], isNull);

      final deserialized = DriveStorageInfo.fromJson(json);
      expect(deserialized.lastUpdated, isNull);
    });

    test('should handle zero total bytes correctly', () {
      final zeroStorage = DriveStorageInfo(
        totalBytes: 0,
        usedBytes: 0,
        docLedgerUsedBytes: 0,
        availableBytes: 0,
        backupFileCount: 0,
      );

      expect(zeroStorage.usagePercentage, equals(0));
      expect(zeroStorage.docLedgerUsagePercentage, equals(0));
    });
  });
}