import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';

import 'package:doc_ledger/core/sync/services/sync_service.dart';
import 'package:doc_ledger/core/cloud/services/google_drive_service.dart';
import 'package:doc_ledger/core/data/services/database_service.dart';
import 'package:doc_ledger/core/encryption/services/encryption_service.dart';
import 'package:doc_ledger/core/data/models/data_models.dart';
import 'package:doc_ledger/core/sync/models/sync_models.dart';
import 'package:doc_ledger/core/encryption/models/encryption_models.dart';

import '../core/sync/services/sync_service_test.mocks.dart';
void main() {
  group('Multi-Device Sync Integration Tests', () {
    late SyncService device1SyncService;
    late SyncService device2SyncService;
    late MockGoogleDriveService mockDriveService;
    late MockDatabaseService mockDevice1Database;
    late MockDatabaseService mockDevice2Database;
    late MockEncryptionService mockEncryption;

    const testClinicId = 'test_clinic_123';
    const device1Id = 'device_1';
    const device2Id = 'device_2';

    setUp(() {
      mockDriveService = MockGoogleDriveService();
      mockDevice1Database = MockDatabaseService();
      mockDevice2Database = MockDatabaseService();
      mockEncryption = MockEncryptionService();

      device1SyncService = SyncService(
        database: mockDevice1Database,
        driveService: mockDriveService,
        encryption: mockEncryption,
        clinicId: testClinicId,
        deviceId: device1Id,
      );

      device2SyncService = SyncService(
        database: mockDevice2Database,
        driveService: mockDriveService,
        encryption: mockEncryption,
        clinicId: testClinicId,
        deviceId: device2Id,
      );
    });

    tearDown(() {
      device1SyncService.dispose();
      device2SyncService.dispose();
    });

    group('Two-Device Sync Scenarios', () {
      test('should sync new patient from device 1 to device 2', () async {
        // Arrange
        final testPatient = Patient(
          id: 'patient_1',
          name: 'John Doe',
          phone: '+1234567890',
          dateOfBirth: DateTime(1990, 5, 15),
          lastModified: DateTime.now(),
          deviceId: device1Id,
        );

        final backupData = BackupData.create(
          clinicId: testClinicId,
          deviceId: device1Id,
          tables: {
            'patients': [testPatient.toSyncJson()],
          },
        );

        // Mock device 1 has new patient
        when(mockDevice1Database.getChangedRecords('patients', any))
            .thenAnswer((_) async => [testPatient.toSyncJson()]);
        when(mockDevice1Database.markRecordsSynced('patients', any))
            .thenAnswer((_) async {});

        // Mock device 2 has no changes
        when(mockDevice2Database.getChangedRecords('patients', any))
            .thenAnswer((_) async => <Map<String, dynamic>>[]);
        when(mockDevice2Database.applyRemoteChanges('patients', any))
            .thenAnswer((_) async {});

        // Mock Google Drive operations
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.getLatestBackup())
            .thenAnswer((_) async => BackupFileInfo(
              id: 'backup_1',
              name: 'test_backup.enc',
              size: 1024,
              createdTime: DateTime.now().subtract(const Duration(hours: 1)),
              modifiedTime: DateTime.now().subtract(const Duration(hours: 1)),
            ));
        when(mockDriveService.downloadBackupFile(any))
            .thenAnswer((_) async => utf8.encode(jsonEncode(backupData.toJson())));
        when(mockDriveService.uploadBackupFile(any, any))
            .thenAnswer((_) async => 'new_backup_id');

        // Mock encryption
        when(mockEncryption.deriveEncryptionKey(testClinicId, device1Id))
            .thenAnswer((_) async => 'device1_key');
        when(mockEncryption.deriveEncryptionKey(testClinicId, device2Id))
            .thenAnswer((_) async => 'device2_key');
        when(mockEncryption.encryptData(any, any))
            .thenAnswer((_) async => EncryptedData(
              data: [1, 2, 3, 4, 5],
              iv: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
              tag: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
              algorithm: 'AES-256-GCM',
              checksum: 'test_checksum',
              timestamp: DateTime.now(),
            ));
        when(mockEncryption.decryptData(any, any))
            .thenAnswer((_) async => backupData.toJson());

        // Act - Device 1 syncs (uploads new patient)
        final device1Result = await device1SyncService.performIncrementalSync();

        // Act - Device 2 syncs (downloads new patient)
        final device2Result = await device2SyncService.performIncrementalSync();

        // Assert
        expect(device1Result.status, equals(SyncResultStatus.success));
        expect(device2Result.status, equals(SyncResultStatus.success));

        // Verify device 1 uploaded changes
        verify(mockDevice1Database.getChangedRecords('patients', any)).called(1);
        verify(mockDriveService.uploadBackupFile(any, any)).called(1);

        // Verify device 2 downloaded and applied changes
        verify(mockDevice2Database.applyRemoteChanges('patients', any)).called(1);
        verify(mockEncryption.decryptData(any, any)).called(1);
      });

      test('should handle concurrent modifications with conflict resolution', () async {
        // Arrange - Both devices modify the same patient
        final device1Patient = Patient(
          id: 'patient_1',
          name: 'John Doe Updated',
          phone: '+1234567890',
          dateOfBirth: DateTime(1990, 5, 15),
          lastModified: DateTime.now(),
          deviceId: device1Id,
        );

        final device2Patient = Patient(
          id: 'patient_1',
          name: 'John Smith Updated',
          phone: '+0987654321',
          dateOfBirth: DateTime(1990, 5, 15),
          lastModified: DateTime.now().add(const Duration(minutes: 1)), // Slightly newer
          deviceId: device2Id,
        );

        final device1BackupData = BackupData.create(
          clinicId: testClinicId,
          deviceId: device1Id,
          tables: {'patients': [device1Patient.toSyncJson()]},
        );

        final device2BackupData = BackupData.create(
          clinicId: testClinicId,
          deviceId: device2Id,
          tables: {'patients': [device2Patient.toSyncJson()]},
        );

        // Mock device 1 changes
        when(mockDevice1Database.getChangedRecords('patients', any))
            .thenAnswer((_) async => [device1Patient.toSyncJson()]);
        when(mockDevice1Database.applyRemoteChanges('patients', any))
            .thenAnswer((_) async {});

        // Mock device 2 changes
        when(mockDevice2Database.getChangedRecords('patients', any))
            .thenAnswer((_) async => [device2Patient.toSyncJson()]);
        when(mockDevice2Database.detectConflicts('patients', any))
            .thenAnswer((_) async => [
          SyncConflict(
            id: 'conflict_1',
            tableName: 'patients',
            recordId: 'patient_1',
            localData: device1Patient.toSyncJson(),
            remoteData: device2Patient.toSyncJson(),
            conflictTime: DateTime.now(),
            type: ConflictType.updateConflict,
            description: 'Concurrent modification conflict',
          ),
        ]);
        when(mockDevice2Database.applyRemoteChanges('patients', any))
            .thenAnswer((_) async {});

        // Mock Google Drive operations
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.getLatestBackup())
            .thenAnswer((_) async => BackupFileInfo(
              id: 'backup_1',
              name: 'test_backup.enc',
              size: 1024,
              createdTime: DateTime.now().subtract(const Duration(hours: 1)),
              modifiedTime: DateTime.now().subtract(const Duration(hours: 1)),
            ));

        // First call returns device1 data, second call returns device2 data
        when(mockDriveService.downloadBackupFile(any))
            .thenAnswer((_) async => utf8.encode(jsonEncode(device1BackupData.toJson())));
        when(mockDriveService.uploadBackupFile(any, any))
            .thenAnswer((_) async => 'new_backup_id');

        // Mock encryption
        when(mockEncryption.deriveEncryptionKey(any, any))
            .thenAnswer((_) async => 'test_key');
        when(mockEncryption.encryptData(any, any))
            .thenAnswer((_) async => EncryptedData(
              data: [1, 2, 3, 4, 5],
              iv: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
              tag: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
              algorithm: 'AES-256-GCM',
              checksum: 'test_checksum',
              timestamp: DateTime.now(),
            ));
        when(mockEncryption.decryptData(any, any))
            .thenAnswer((_) async => device1BackupData.toJson());

        // Act - Device 1 syncs first
        final device1Result = await device1SyncService.performIncrementalSync();

        // Update mock to return device2 data for second sync
        when(mockDriveService.downloadBackupFile(any))
            .thenAnswer((_) async => utf8.encode(jsonEncode(device2BackupData.toJson())));
        when(mockEncryption.decryptData(any, any))
            .thenAnswer((_) async => device2BackupData.toJson());

        // Act - Device 2 syncs (should detect conflict)
        final device2Result = await device2SyncService.performIncrementalSync();

        // Assert
        expect(device1Result.status, equals(SyncResultStatus.success));
        expect(device2Result.status, equals(SyncResultStatus.partial));
        expect(device2Result.conflictIds, isNotEmpty);

        // Verify conflict was detected
        verify(mockDevice2Database.detectConflicts('patients', any)).called(1);
        verify(mockDevice2Database.applyRemoteChanges('patients', any)).called(1);
      });

      test('should handle offline device coming back online', () async {
        // Arrange - Device 1 has been offline and accumulated changes
        final offlineChanges = [
          Patient(
            id: 'patient_1',
            name: 'John Doe',
            phone: '+1234567890',
            lastModified: DateTime.now().subtract(const Duration(hours: 2)),
            deviceId: device1Id,
          ),
          Patient(
            id: 'patient_2',
            name: 'Jane Smith',
            phone: '+0987654321',
            lastModified: DateTime.now().subtract(const Duration(hours: 1)),
            deviceId: device1Id,
          ),
        ];

        final remoteChanges = [
          Patient(
            id: 'patient_3',
            name: 'Bob Johnson',
            phone: '+1122334455',
            lastModified: DateTime.now().subtract(const Duration(minutes: 30)),
            deviceId: device2Id,
          ),
        ];

        final localBackupData = BackupData.create(
          clinicId: testClinicId,
          deviceId: device1Id,
          tables: {
            'patients': offlineChanges.map((p) => p.toSyncJson()).toList(),
          },
        );

        final remoteBackupData = BackupData.create(
          clinicId: testClinicId,
          deviceId: device2Id,
          tables: {
            'patients': remoteChanges.map((p) => p.toSyncJson()).toList(),
          },
        );

        // Mock device 1 has accumulated offline changes
        when(mockDevice1Database.getChangedRecords('patients', any))
            .thenAnswer((_) async => offlineChanges.map((p) => p.toSyncJson()).toList());
        when(mockDevice1Database.applyRemoteChanges('patients', any))
            .thenAnswer((_) async {});
        when(mockDevice1Database.markRecordsSynced('patients', any))
            .thenAnswer((_) async {});

        // Mock Google Drive operations
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.getLatestBackup())
            .thenAnswer((_) async => BackupFileInfo(
              id: 'remote_backup',
              name: 'remote_backup.enc',
              size: 1024,
              createdTime: DateTime.now().subtract(const Duration(minutes: 15)),
              modifiedTime: DateTime.now().subtract(const Duration(minutes: 15)),
            ));
        when(mockDriveService.downloadBackupFile(any))
            .thenAnswer((_) async => utf8.encode(jsonEncode(remoteBackupData.toJson())));
        when(mockDriveService.uploadBackupFile(any, any))
            .thenAnswer((_) async => 'merged_backup_id');

        // Mock encryption
        when(mockEncryption.deriveEncryptionKey(any, any))
            .thenAnswer((_) async => 'test_key');
        when(mockEncryption.encryptData(any, any))
            .thenAnswer((_) async => EncryptedData(
              data: [1, 2, 3, 4, 5],
              iv: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
              tag: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
              algorithm: 'AES-256-GCM',
              checksum: 'test_checksum',
              timestamp: DateTime.now(),
            ));
        when(mockEncryption.decryptData(any, any))
            .thenAnswer((_) async => remoteBackupData.toJson());

        // Act - Device 1 comes back online and syncs
        final syncResult = await device1SyncService.performFullSync();

        // Assert
        expect(syncResult.status, equals(SyncResultStatus.success));
        expect(syncResult.syncedCounts!['patients'], equals(2)); // Local changes uploaded

        // Verify device downloaded remote changes and uploaded local changes
        verify(mockDriveService.downloadBackupFile(any)).called(1);
        verify(mockDriveService.uploadBackupFile(any, any)).called(1);
        verify(mockDevice1Database.applyRemoteChanges('patients', any)).called(1);
        verify(mockDevice1Database.markRecordsSynced('patients', any)).called(1);
      });
    });

    group('Three-Device Sync Scenarios', () {
      test('should handle changes propagating through three devices', () async {
        // Arrange - Simulate three devices with different changes
        late SyncService device3SyncService;
        late MockDatabaseService mockDevice3Database;
        const device3Id = 'device_3';

        mockDevice3Database = MockDatabaseService();
        device3SyncService = SyncService(
          database: mockDevice3Database,
          driveService: mockDriveService,
          encryption: mockEncryption,
          clinicId: testClinicId,
          deviceId: device3Id,
        );

        final device1Patient = Patient(
          id: 'patient_1',
          name: 'John Doe',
          phone: '+1234567890',
          lastModified: DateTime.now().subtract(const Duration(hours: 3)),
          deviceId: device1Id,
        );

        final device2Visit = Visit(
          id: 'visit_1',
          patientId: 'patient_1',
          visitDate: DateTime.now().subtract(const Duration(hours: 2)),
          diagnosis: 'Common cold',
          lastModified: DateTime.now().subtract(const Duration(hours: 2)),
          deviceId: device2Id,
        );

        final device3Payment = Payment(
          id: 'payment_1',
          patientId: 'patient_1',
          visitId: 'visit_1',
          amount: 50.0,
          paymentDate: DateTime.now().subtract(const Duration(hours: 1)),
          paymentMethod: 'cash',
          lastModified: DateTime.now().subtract(const Duration(hours: 1)),
          deviceId: device3Id,
        );

        // Mock each device's local changes
        when(mockDevice1Database.getChangedRecords('patients', any))
            .thenAnswer((_) async => [device1Patient.toSyncJson()]);
        when(mockDevice2Database.getChangedRecords('visits', any))
            .thenAnswer((_) async => [device2Visit.toSyncJson()]);
        when(mockDevice3Database.getChangedRecords('payments', any))
            .thenAnswer((_) async => [device3Payment.toSyncJson()]);

        // Mock apply remote changes (no conflicts)
        when(mockDevice1Database.applyRemoteChanges('patients', any))
            .thenAnswer((_) async {});
        when(mockDevice2Database.applyRemoteChanges('visits', any))
            .thenAnswer((_) async {});
        when(mockDevice3Database.applyRemoteChanges('payments', any))
            .thenAnswer((_) async {});

        // Mock mark as synced
        when(mockDevice1Database.markRecordsSynced('patients', any))
            .thenAnswer((_) async {});
        when(mockDevice2Database.markRecordsSynced('visits', any))
            .thenAnswer((_) async {});
        when(mockDevice3Database.markRecordsSynced('payments', any))
            .thenAnswer((_) async {});

        // Mock Google Drive operations
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.getLatestBackup())
            .thenAnswer((_) async => BackupFileInfo(
              id: 'latest_backup',
              name: 'latest_backup.enc',
              size: 1024,
              createdTime: DateTime.now().subtract(const Duration(hours: 4)),
              modifiedTime: DateTime.now().subtract(const Duration(hours: 4)),
            ));
        when(mockDriveService.uploadBackupFile(any, any))
            .thenAnswer((_) async => 'new_backup_id');

        // Mock encryption
        when(mockEncryption.deriveEncryptionKey(any, any))
            .thenAnswer((_) async => 'test_key');
        when(mockEncryption.encryptData(any, any))
            .thenAnswer((_) async => EncryptedData(
              data: [1, 2, 3, 4, 5],
              iv: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
              tag: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
              algorithm: 'AES-256-GCM',
              checksum: 'test_checksum',
              timestamp: DateTime.now(),
            ));

        // Create progressive backup data for each sync
        var currentBackupData = BackupData.create(
          clinicId: testClinicId,
          deviceId: 'initial',
          tables: <String, List<Map<String, dynamic>>>{},
        );

        when(mockDriveService.downloadBackupFile(any))
            .thenAnswer((_) async => utf8.encode(jsonEncode(currentBackupData.toJson())));
        when(mockEncryption.decryptData(any, any))
            .thenAnswer((_) async => currentBackupData.toJson());

        // Act - Device 1 syncs first (uploads patient)
        final device1Result = await device1SyncService.performIncrementalSync();

        // Update backup data to include device 1's changes
        currentBackupData = BackupData.create(
          clinicId: testClinicId,
          deviceId: device1Id,
          tables: {'patients': [device1Patient.toSyncJson()]},
        );
        when(mockEncryption.decryptData(any, any))
            .thenAnswer((_) async => currentBackupData.toJson());

        // Act - Device 2 syncs (downloads patient, uploads visit)
        final device2Result = await device2SyncService.performIncrementalSync();

        // Update backup data to include both patient and visit
        currentBackupData = BackupData.create(
          clinicId: testClinicId,
          deviceId: device2Id,
          tables: {
            'patients': [device1Patient.toSyncJson()],
            'visits': [device2Visit.toSyncJson()],
          },
        );
        when(mockEncryption.decryptData(any, any))
            .thenAnswer((_) async => currentBackupData.toJson());

        // Act - Device 3 syncs (downloads patient and visit, uploads payment)
        final device3Result = await device3SyncService.performIncrementalSync();

        // Assert
        expect(device1Result.status, equals(SyncResultStatus.success));
        expect(device2Result.status, equals(SyncResultStatus.success));
        expect(device3Result.status, equals(SyncResultStatus.success));

        // Verify each device uploaded their changes
        verify(mockDriveService.uploadBackupFile(any, any)).called(3);

        // Verify devices 2 and 3 downloaded and applied remote changes
        verify(mockDevice2Database.applyRemoteChanges('patients', any)).called(1);
        verify(mockDevice3Database.applyRemoteChanges('patients', any)).called(1);

        // Clean up
        device3SyncService.dispose();
      });
    });

    group('Large Dataset Sync Performance', () {
      test('should handle sync with 1000+ records efficiently', () async {
        // Arrange - Create large dataset
        final largePatientList = List.generate(1000, (index) => Patient(
          id: 'patient_$index',
          name: 'Patient $index',
          phone: '+123456789$index',
          lastModified: DateTime.now().subtract(Duration(minutes: index)),
          deviceId: device1Id,
        ));

        final largeBackupData = BackupData.create(
          clinicId: testClinicId,
          deviceId: device1Id,
          tables: {
            'patients': largePatientList.map((p) => p.toSyncJson()).toList(),
          },
        );

        // Mock device 1 has large dataset
        when(mockDevice1Database.getChangedRecords('patients', any))
            .thenAnswer((_) async => largePatientList.map((p) => p.toSyncJson()).toList());
        when(mockDevice1Database.markRecordsSynced('patients', any))
            .thenAnswer((_) async {});

        // Mock device 2 applies large dataset
        when(mockDevice2Database.getChangedRecords('patients', any))
            .thenAnswer((_) async => <Map<String, dynamic>>[]);
        when(mockDevice2Database.applyRemoteChanges('patients', any))
            .thenAnswer((_) async {});

        // Mock Google Drive operations
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.getLatestBackup())
            .thenAnswer((_) async => BackupFileInfo(
              id: 'large_backup',
              name: 'large_backup.enc',
              size: 1024 * 1024, // 1MB
              createdTime: DateTime.now().subtract(const Duration(hours: 1)),
              modifiedTime: DateTime.now().subtract(const Duration(hours: 1)),
            ));
        when(mockDriveService.downloadBackupFile(any))
            .thenAnswer((_) async => utf8.encode(jsonEncode(largeBackupData.toJson())));
        when(mockDriveService.uploadBackupFile(any, any))
            .thenAnswer((_) async => 'large_backup_id');

        // Mock encryption
        when(mockEncryption.deriveEncryptionKey(any, any))
            .thenAnswer((_) async => 'test_key');
        when(mockEncryption.encryptData(any, any))
            .thenAnswer((_) async => EncryptedData(
              data: List.generate(1024 * 1024, (i) => i % 256),
              iv: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
              tag: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
              algorithm: 'AES-256-GCM',
              checksum: 'test_checksum',
              timestamp: DateTime.now(),
            ));
        when(mockEncryption.decryptData(any, any))
            .thenAnswer((_) async => largeBackupData.toJson());

        // Act - Measure sync performance
        final stopwatch = Stopwatch()..start();
        
        final device1Result = await device1SyncService.performIncrementalSync();
        final device2Result = await device2SyncService.performIncrementalSync();
        
        stopwatch.stop();

        // Assert
        expect(device1Result.status, equals(SyncResultStatus.success));
        expect(device2Result.status, equals(SyncResultStatus.success));
        expect(device1Result.syncedCounts!['patients'], equals(1000));
        
        // Performance assertion - should complete within reasonable time
        expect(stopwatch.elapsedMilliseconds, lessThan(30000)); // 30 seconds

        // Verify operations were called
        verify(mockDriveService.uploadBackupFile(any, any)).called(1);
        verify(mockDevice2Database.applyRemoteChanges('patients', any)).called(1);
      });
    });

    group('Network Failure Recovery', () {
      test('should recover from network failures during sync', () async {
        // Arrange
        final testPatient = Patient(
          id: 'patient_1',
          name: 'John Doe',
          phone: '+1234567890',
          lastModified: DateTime.now(),
          deviceId: device1Id,
        );

        when(mockDevice1Database.getChangedRecords('patients', any))
            .thenAnswer((_) async => [testPatient.toSyncJson()]);
        when(mockDevice1Database.markRecordsSynced('patients', any))
            .thenAnswer((_) async {});

        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockEncryption.deriveEncryptionKey(any, any))
            .thenAnswer((_) async => 'test_key');
        when(mockEncryption.encryptData(any, any))
            .thenAnswer((_) async => EncryptedData(
              data: [1, 2, 3, 4, 5],
              iv: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
              tag: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
              algorithm: 'AES-256-GCM',
              checksum: 'test_checksum',
              timestamp: DateTime.now(),
            ));

        // Mock network failure on first attempt, success on retry
        var networkCallCount = 0;
        when(mockDriveService.uploadBackupFile(any, any)).thenAnswer((_) async {
          networkCallCount++;
          if (networkCallCount == 1) {
            throw Exception('Network error');
          }
          return 'backup_id_after_retry';
        });

        // Act - First sync attempt should fail and retry
        final result = await device1SyncService.performIncrementalSync();

        // Assert - Should eventually succeed after retry
        expect(result.status, equals(SyncResultStatus.success));
        
        // Verify retry was attempted
        verify(mockDriveService.uploadBackupFile(any, any)).called(2);
      });
    });
  });
}