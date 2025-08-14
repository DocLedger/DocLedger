import 'package:flutter_test/flutter_test.dart';
import 'package:doc_ledger/core/sync/models/sync_models.dart';

void main() {
  group('BackupData Model Tests', () {
    late BackupData testBackupData;
    late DateTime testTimestamp;
    late Map<String, List<Map<String, dynamic>>> testTables;

    setUp(() {
      testTimestamp = DateTime(2024, 1, 15, 10, 30);
      testTables = {
        'patients': [
          {'id': 'patient_1', 'name': 'John Doe', 'phone': '+1234567890'},
          {'id': 'patient_2', 'name': 'Jane Smith', 'phone': '+0987654321'},
        ],
        'visits': [
          {'id': 'visit_1', 'patient_id': 'patient_1', 'diagnosis': 'Common cold'},
        ],
      };

      testBackupData = BackupData(
        clinicId: 'clinic_123',
        deviceId: 'device_456',
        timestamp: testTimestamp,
        version: 1,
        tables: testTables,
        checksum: 'test_checksum',
        metadata: {'backup_type': 'full'},
      );
    });

    test('should serialize to JSON correctly', () {
      final json = testBackupData.toJson();

      expect(json['clinic_id'], equals('clinic_123'));
      expect(json['device_id'], equals('device_456'));
      expect(json['timestamp'], equals(testTimestamp.toIso8601String()));
      expect(json['version'], equals(1));
      expect(json['tables'], equals(testTables));
      expect(json['checksum'], equals('test_checksum'));
      expect(json['metadata'], equals({'backup_type': 'full'}));
    });

    test('should deserialize from JSON correctly', () {
      final json = testBackupData.toJson();
      final deserializedBackup = BackupData.fromJson(json);

      expect(deserializedBackup.clinicId, equals(testBackupData.clinicId));
      expect(deserializedBackup.deviceId, equals(testBackupData.deviceId));
      expect(deserializedBackup.timestamp, equals(testBackupData.timestamp));
      expect(deserializedBackup.version, equals(testBackupData.version));
      expect(deserializedBackup.tables, equals(testBackupData.tables));
      expect(deserializedBackup.checksum, equals(testBackupData.checksum));
      expect(deserializedBackup.metadata, equals(testBackupData.metadata));
    });

    test('should create backup with calculated checksum', () {
      final backup = BackupData.create(
        clinicId: 'clinic_123',
        deviceId: 'device_456',
        tables: testTables,
        version: 1,
        metadata: {'backup_type': 'full'},
      );

      expect(backup.clinicId, equals('clinic_123'));
      expect(backup.deviceId, equals('device_456'));
      expect(backup.tables, equals(testTables));
      expect(backup.version, equals(1));
      expect(backup.checksum, isNotEmpty);
      expect(backup.validateIntegrity(), isTrue);
    });

    test('should validate integrity correctly', () {
      final validBackup = BackupData.create(
        clinicId: 'clinic_123',
        deviceId: 'device_456',
        tables: testTables,
      );

      expect(validBackup.validateIntegrity(), isTrue);

      // Create backup with invalid checksum
      final invalidBackup = validBackup.copyWith(checksum: 'invalid_checksum');
      expect(invalidBackup.validateIntegrity(), isFalse);
    });

    test('should handle null metadata', () {
      final backupWithoutMetadata = BackupData(
        clinicId: 'clinic_123',
        deviceId: 'device_456',
        timestamp: testTimestamp,
        version: 1,
        tables: testTables,
        checksum: 'test_checksum',
        metadata: null,
      );

      final json = backupWithoutMetadata.toJson();
      expect(json['metadata'], isNull);

      final deserialized = BackupData.fromJson(json);
      expect(deserialized.metadata, isNull);
    });

    test('should implement equality correctly', () {
      final sameBackup = BackupData(
        clinicId: 'clinic_123',
        deviceId: 'device_456',
        timestamp: testTimestamp,
        version: 1,
        tables: {'different': []}, // Different tables
        checksum: 'test_checksum',
        metadata: {'different': 'metadata'}, // Different metadata
      );

      expect(testBackupData == sameBackup, isTrue);
      expect(testBackupData.hashCode, equals(sameBackup.hashCode));
    });
  });

  group('SyncState Model Tests', () {
    test('should create idle state correctly', () {
      final idleState = SyncState.idle();

      expect(idleState.status, equals(SyncStatus.idle));
      expect(idleState.lastSyncTime, isNull);
      expect(idleState.lastBackupTime, isNull);
      expect(idleState.pendingChanges, equals(0));
      expect(idleState.conflicts, isEmpty);
      expect(idleState.errorMessage, isNull);
      expect(idleState.progress, isNull);
    });

    test('should create syncing state correctly', () {
      final syncingState = SyncState.syncing(
        progress: 0.5,
        currentOperation: 'Syncing patients',
      );

      expect(syncingState.status, equals(SyncStatus.syncing));
      expect(syncingState.progress, equals(0.5));
      expect(syncingState.currentOperation, equals('Syncing patients'));
    });

    test('should create backing up state correctly', () {
      final backingUpState = SyncState.backingUp(
        progress: 0.75,
        currentOperation: 'Creating backup',
      );

      expect(backingUpState.status, equals(SyncStatus.backingUp));
      expect(backingUpState.progress, equals(0.75));
      expect(backingUpState.currentOperation, equals('Creating backup'));
    });

    test('should create error state correctly', () {
      final errorState = SyncState.error('Network connection failed');

      expect(errorState.status, equals(SyncStatus.error));
      expect(errorState.errorMessage, equals('Network connection failed'));
    });

    test('should serialize to JSON correctly', () {
      final syncState = SyncState(
        status: SyncStatus.syncing,
        lastSyncTime: DateTime(2024, 1, 15, 10, 0),
        lastBackupTime: DateTime(2024, 1, 15, 9, 0),
        pendingChanges: 5,
        conflicts: ['conflict_1', 'conflict_2'],
        errorMessage: null,
        progress: 0.3,
        currentOperation: 'Syncing data',
      );

      final json = syncState.toJson();

      expect(json['status'], equals('syncing'));
      expect(json['last_sync_time'], equals('2024-01-15T10:00:00.000'));
      expect(json['last_backup_time'], equals('2024-01-15T09:00:00.000'));
      expect(json['pending_changes'], equals(5));
      expect(json['conflicts'], equals(['conflict_1', 'conflict_2']));
      expect(json['error_message'], isNull);
      expect(json['progress'], equals(0.3));
      expect(json['current_operation'], equals('Syncing data'));
    });

    test('should deserialize from JSON correctly', () {
      final json = {
        'status': 'syncing',
        'last_sync_time': '2024-01-15T10:00:00.000',
        'last_backup_time': '2024-01-15T09:00:00.000',
        'pending_changes': 5,
        'conflicts': ['conflict_1', 'conflict_2'],
        'error_message': null,
        'progress': 0.3,
        'current_operation': 'Syncing data',
      };

      final syncState = SyncState.fromJson(json);

      expect(syncState.status, equals(SyncStatus.syncing));
      expect(syncState.lastSyncTime, equals(DateTime(2024, 1, 15, 10, 0)));
      expect(syncState.lastBackupTime, equals(DateTime(2024, 1, 15, 9, 0)));
      expect(syncState.pendingChanges, equals(5));
      expect(syncState.conflicts, equals(['conflict_1', 'conflict_2']));
      expect(syncState.errorMessage, isNull);
      expect(syncState.progress, equals(0.3));
      expect(syncState.currentOperation, equals('Syncing data'));
    });

    test('should handle null values in JSON', () {
      final json = {
        'status': 'idle',
        'last_sync_time': null,
        'last_backup_time': null,
        'pending_changes': null,
        'conflicts': null,
        'error_message': null,
        'progress': null,
        'current_operation': null,
      };

      final syncState = SyncState.fromJson(json);

      expect(syncState.status, equals(SyncStatus.idle));
      expect(syncState.lastSyncTime, isNull);
      expect(syncState.lastBackupTime, isNull);
      expect(syncState.pendingChanges, equals(0));
      expect(syncState.conflicts, isEmpty);
      expect(syncState.errorMessage, isNull);
      expect(syncState.progress, isNull);
      expect(syncState.currentOperation, isNull);
    });
  });

  group('SyncResult Model Tests', () {
    test('should create success result correctly', () {
      final successResult = SyncResult.success(
        syncedCounts: {'patients': 10, 'visits': 5},
        duration: const Duration(seconds: 30),
        metadata: {'sync_type': 'incremental'},
      );

      expect(successResult.status, equals(SyncResultStatus.success));
      expect(successResult.isSuccess, isTrue);
      expect(successResult.isFailure, isFalse);
      expect(successResult.syncedCounts, equals({'patients': 10, 'visits': 5}));
      expect(successResult.duration, equals(const Duration(seconds: 30)));
      expect(successResult.metadata, equals({'sync_type': 'incremental'}));
    });

    test('should create failure result correctly', () {
      final failureResult = SyncResult.failure(
        'Network timeout',
        duration: const Duration(seconds: 10),
      );

      expect(failureResult.status, equals(SyncResultStatus.failure));
      expect(failureResult.isFailure, isTrue);
      expect(failureResult.isSuccess, isFalse);
      expect(failureResult.errorMessage, equals('Network timeout'));
      expect(failureResult.duration, equals(const Duration(seconds: 10)));
    });

    test('should create partial result correctly', () {
      final partialResult = SyncResult.partial(
        syncedCounts: {'patients': 8, 'visits': 3},
        conflictIds: ['conflict_1', 'conflict_2'],
        errorMessage: 'Some conflicts occurred',
        duration: const Duration(seconds: 45),
      );

      expect(partialResult.status, equals(SyncResultStatus.partial));
      expect(partialResult.isPartial, isTrue);
      expect(partialResult.syncedCounts, equals({'patients': 8, 'visits': 3}));
      expect(partialResult.conflictIds, equals(['conflict_1', 'conflict_2']));
      expect(partialResult.errorMessage, equals('Some conflicts occurred'));
    });

    test('should serialize to JSON correctly', () {
      final syncResult = SyncResult(
        status: SyncResultStatus.success,
        timestamp: DateTime(2024, 1, 15, 12, 0),
        syncedCounts: {'patients': 5},
        duration: const Duration(minutes: 2),
        metadata: {'test': 'data'},
      );

      final json = syncResult.toJson();

      expect(json['status'], equals('success'));
      expect(json['timestamp'], equals('2024-01-15T12:00:00.000'));
      expect(json['synced_counts'], equals({'patients': 5}));
      expect(json['duration_ms'], equals(120000));
      expect(json['metadata'], equals({'test': 'data'}));
    });

    test('should deserialize from JSON correctly', () {
      final json = {
        'status': 'success',
        'timestamp': '2024-01-15T12:00:00.000',
        'error_message': null,
        'synced_counts': {'patients': 5},
        'conflict_ids': null,
        'duration_ms': 120000,
        'metadata': {'test': 'data'},
      };

      final syncResult = SyncResult.fromJson(json);

      expect(syncResult.status, equals(SyncResultStatus.success));
      expect(syncResult.timestamp, equals(DateTime(2024, 1, 15, 12, 0)));
      expect(syncResult.syncedCounts, equals({'patients': 5}));
      expect(syncResult.duration, equals(const Duration(minutes: 2)));
      expect(syncResult.metadata, equals({'test': 'data'}));
    });
  });

  group('SyncMetadata Model Tests', () {
    late SyncMetadata testMetadata;
    late DateTime testTimestamp;

    setUp(() {
      testTimestamp = DateTime(2024, 1, 15, 10, 30);
      testMetadata = SyncMetadata(
        tableName: 'patients',
        lastSyncTimestamp: testTimestamp,
        lastBackupTimestamp: testTimestamp.subtract(const Duration(hours: 1)),
        pendingChangesCount: 3,
        conflictCount: 1,
        lastSyncDeviceId: 'device_123',
      );
    });

    test('should serialize to JSON correctly', () {
      final json = testMetadata.toJson();

      expect(json['table_name'], equals('patients'));
      expect(json['last_sync_timestamp'], equals(testTimestamp.millisecondsSinceEpoch));
      expect(json['last_backup_timestamp'], 
          equals(testTimestamp.subtract(const Duration(hours: 1)).millisecondsSinceEpoch));
      expect(json['pending_changes_count'], equals(3));
      expect(json['conflict_count'], equals(1));
      expect(json['last_sync_device_id'], equals('device_123'));
    });

    test('should deserialize from JSON correctly', () {
      final json = testMetadata.toJson();
      final deserializedMetadata = SyncMetadata.fromJson(json);

      expect(deserializedMetadata.tableName, equals(testMetadata.tableName));
      expect(deserializedMetadata.lastSyncTimestamp, equals(testMetadata.lastSyncTimestamp));
      expect(deserializedMetadata.lastBackupTimestamp, equals(testMetadata.lastBackupTimestamp));
      expect(deserializedMetadata.pendingChangesCount, equals(testMetadata.pendingChangesCount));
      expect(deserializedMetadata.conflictCount, equals(testMetadata.conflictCount));
      expect(deserializedMetadata.lastSyncDeviceId, equals(testMetadata.lastSyncDeviceId));
    });

    test('should handle null values correctly', () {
      final metadataWithNulls = SyncMetadata(
        tableName: 'visits',
        lastSyncTimestamp: null,
        lastBackupTimestamp: null,
        pendingChangesCount: 0,
        conflictCount: 0,
        lastSyncDeviceId: null,
      );

      final json = metadataWithNulls.toJson();
      expect(json['last_sync_timestamp'], isNull);
      expect(json['last_backup_timestamp'], isNull);
      expect(json['last_sync_device_id'], isNull);

      final deserialized = SyncMetadata.fromJson(json);
      expect(deserialized.lastSyncTimestamp, isNull);
      expect(deserialized.lastBackupTimestamp, isNull);
      expect(deserialized.lastSyncDeviceId, isNull);
    });

    test('should handle missing values in JSON with defaults', () {
      final json = {
        'table_name': 'payments',
        'last_sync_timestamp': null,
        'last_backup_timestamp': null,
        'pending_changes_count': null,
        'conflict_count': null,
        'last_sync_device_id': null,
      };

      final metadata = SyncMetadata.fromJson(json);

      expect(metadata.tableName, equals('payments'));
      expect(metadata.pendingChangesCount, equals(0));
      expect(metadata.conflictCount, equals(0));
    });

    test('should implement equality correctly', () {
      final sameMetadata = SyncMetadata(
        tableName: 'patients',
        lastSyncTimestamp: testTimestamp,
        lastBackupTimestamp: testTimestamp.subtract(const Duration(hours: 1)),
        pendingChangesCount: 3,
        conflictCount: 1,
        lastSyncDeviceId: 'different_device', // Different device ID
      );

      expect(testMetadata == sameMetadata, isTrue);
      expect(testMetadata.hashCode, equals(sameMetadata.hashCode));
    });
  });

  group('Enum Tests', () {
    test('should handle all SyncStatus values', () {
      for (final status in SyncStatus.values) {
        final state = SyncState(status: status);
        final json = state.toJson();
        final deserialized = SyncState.fromJson(json);
        expect(deserialized.status, equals(status));
      }
    });

    test('should handle all SyncResultStatus values', () {
      for (final status in SyncResultStatus.values) {
        final result = SyncResult(status: status, timestamp: DateTime.now());
        final json = result.toJson();
        final deserialized = SyncResult.fromJson(json);
        expect(deserialized.status, equals(status));
      }
    });
  });
}