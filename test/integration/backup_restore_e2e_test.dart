import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';

import 'package:doc_ledger/core/sync/services/sync_service.dart';
import 'package:doc_ledger/core/cloud/services/google_drive_service.dart';
import 'package:doc_ledger/core/data/services/database_service.dart';
import 'package:doc_ledger/core/encryption/services/encryption_service.dart';
import 'package:doc_ledger/features/restore/services/restore_service.dart';
import 'package:doc_ledger/core/data/models/data_models.dart';
import 'package:doc_ledger/core/sync/models/sync_models.dart';
import 'package:doc_ledger/core/encryption/models/encryption_models.dart';

import '../core/sync/services/sync_service_test.mocks.dart';
void main() {
  group('Backup and Restore End-to-End Tests', () {
    late SyncService syncService;
    late RestoreService restoreService;
    late MockGoogleDriveService mockDriveService;
    late MockDatabaseService mockSourceDatabase;
    late MockDatabaseService mockTargetDatabase;
    late MockEncryptionService mockEncryption;

    const testClinicId = 'test_clinic_123';
    const sourceDeviceId = 'source_device';
    const targetDeviceId = 'target_device';

    setUp(() {
      mockDriveService = MockGoogleDriveService();
      mockSourceDatabase = MockDatabaseService();
      mockTargetDatabase = MockDatabaseService();
      mockEncryption = MockEncryptionService();

      syncService = SyncService(
        driveService: mockDriveService,
        database: mockSourceDatabase,
        encryption: mockEncryption,
        clinicId: testClinicId,
        deviceId: sourceDeviceId,
      );

      restoreService = RestoreService(
        syncService: syncService,
        driveService: mockDriveService,
        database: mockTargetDatabase,
        encryption: mockEncryption,
        clinicId: testClinicId,
        deviceId: targetDeviceId,
      );
    });

    tearDown(() {
      syncService.dispose();
      restoreService.dispose();
    });

    group('Complete Backup and Restore Workflow', () {
      test('should complete full backup and restore cycle successfully', () async {
        // Arrange - Create comprehensive test data
        final testPatients = [
          Patient(
            id: 'patient_1',
            name: 'John Doe',
            phone: '+1234567890',
            dateOfBirth: DateTime(1990, 5, 15),
            address: '123 Main St',
            emergencyContact: 'Jane Doe - +0987654321',
            lastModified: DateTime.now().subtract(const Duration(hours: 2)),
            deviceId: sourceDeviceId,
          ),
          Patient(
            id: 'patient_2',
            name: 'Jane Smith',
            phone: '+0987654321',
            dateOfBirth: DateTime(1985, 8, 22),
            address: '456 Oak Ave',
            lastModified: DateTime.now().subtract(const Duration(hours: 1)),
            deviceId: sourceDeviceId,
          ),
        ];

        final testVisits = [
          Visit(
            id: 'visit_1',
            patientId: 'patient_1',
            visitDate: DateTime.now().subtract(const Duration(days: 1)),
            diagnosis: 'Common cold',
            treatment: 'Rest and fluids',
            notes: 'Patient feeling better',
            fee: 50.0,
            lastModified: DateTime.now().subtract(const Duration(hours: 1)),
            deviceId: sourceDeviceId,
          ),
          Visit(
            id: 'visit_2',
            patientId: 'patient_2',
            visitDate: DateTime.now().subtract(const Duration(days: 2)),
            diagnosis: 'Headache',
            treatment: 'Pain medication',
            fee: 75.0,
            lastModified: DateTime.now().subtract(const Duration(minutes: 30)),
            deviceId: sourceDeviceId,
          ),
        ];

        final testPayments = [
          Payment(
            id: 'payment_1',
            patientId: 'patient_1',
            visitId: 'visit_1',
            amount: 50.0,
            paymentDate: DateTime.now().subtract(const Duration(days: 1)),
            paymentMethod: 'cash',
            notes: 'Full payment received',
            lastModified: DateTime.now().subtract(const Duration(minutes: 45)),
            deviceId: sourceDeviceId,
          ),
          Payment(
            id: 'payment_2',
            patientId: 'patient_2',
            visitId: 'visit_2',
            amount: 75.0,
            paymentDate: DateTime.now().subtract(const Duration(days: 2)),
            paymentMethod: 'card',
            lastModified: DateTime.now().subtract(const Duration(minutes: 15)),
            deviceId: sourceDeviceId,
          ),
        ];

        final completeBackupData = BackupData.create(
          clinicId: testClinicId,
          deviceId: sourceDeviceId,
          tables: {
            'patients': testPatients.map((p) => p.toSyncJson()).toList(),
            'visits': testVisits.map((v) => v.toSyncJson()).toList(),
            'payments': testPayments.map((p) => p.toSyncJson()).toList(),
          },
          metadata: {
            'backup_type': 'full',
            'total_records': 6,
            'created_by': sourceDeviceId,
          },
        );

        final encryptedData = EncryptedData(
          data: utf8.encode(jsonEncode(completeBackupData.toJson())),
          iv: List.generate(16, (i) => i),
          tag: List.generate(16, (i) => i + 16),
          algorithm: 'AES-256-GCM',
          checksum: 'test_checksum',
          timestamp: DateTime.now(),
        );

        // PHASE 1: BACKUP
        // Mock source database has all the test data
        when(mockSourceDatabase.getChangedRecords('patients', any))
            .thenAnswer((_) async => testPatients.map((p) => p.toSyncJson()).toList());
        when(mockSourceDatabase.getChangedRecords('visits', any))
            .thenAnswer((_) async => testVisits.map((v) => v.toSyncJson()).toList());
        when(mockSourceDatabase.getChangedRecords('payments', any))
            .thenAnswer((_) async => testPayments.map((p) => p.toSyncJson()).toList());
        when(mockSourceDatabase.markRecordsSynced('patients', any))
            .thenAnswer((_) async {});
        when(mockSourceDatabase.markRecordsSynced('visits', any))
            .thenAnswer((_) async {});
        when(mockSourceDatabase.markRecordsSynced('payments', any))
            .thenAnswer((_) async {});

        // Mock Google Drive operations for backup
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.getLatestBackup())
            .thenAnswer((_) async => null); // No previous backup
        when(mockDriveService.uploadBackupFile(any, any))
            .thenAnswer((_) async => 'new_backup_id');

        // Mock encryption for backup
        when(mockEncryption.deriveEncryptionKey(testClinicId, sourceDeviceId))
            .thenAnswer((_) async => 'source_encryption_key');
        when(mockEncryption.encryptData(any, 'source_encryption_key'))
            .thenAnswer((_) async => encryptedData);

        // Act - Perform backup
        final backupResult = await syncService.createBackup();

        // Assert - Backup should succeed
        expect(backupResult.status, equals(SyncResultStatus.success));
        expect(backupResult.syncedCounts!['patients'], equals(2));
        expect(backupResult.syncedCounts!['visits'], equals(2));
        expect(backupResult.syncedCounts!['payments'], equals(2));

        // Verify backup operations
        verify(mockSourceDatabase.getChangedRecords('patients', any)).called(1);
        verify(mockSourceDatabase.getChangedRecords('visits', any)).called(1);
        verify(mockSourceDatabase.getChangedRecords('payments', any)).called(1);
        verify(mockDriveService.uploadBackupFile(any, any)).called(1);
        verify(mockEncryption.encryptData(any, 'source_encryption_key')).called(1);

        // PHASE 2: RESTORE
        // Mock Google Drive operations for restore
        final backupFileInfo = BackupFileInfo(
          id: 'new_backup_id',
          name: 'docledger_backup_${testClinicId}_${DateTime.now().toIso8601String().replaceAll(':', '-')}.enc',
          size: encryptedData.data.length,
          createdTime: DateTime.now(),
          modifiedTime: DateTime.now(),
          description: 'Full clinic backup',
        );

        when(mockDriveService.listBackupFiles())
            .thenAnswer((_) async => [backupFileInfo]);
        when(mockDriveService.downloadBackupFile('new_backup_id', onProgress: anyNamed('onProgress')))
            .thenAnswer((_) async => encryptedData.data);

        // Mock encryption for restore
        when(mockEncryption.deriveEncryptionKey(testClinicId, targetDeviceId))
            .thenAnswer((_) async => 'target_encryption_key');
        when(mockEncryption.decryptData(encryptedData, 'target_encryption_key'))
            .thenAnswer((_) async => completeBackupData.toJson());

        // Mock target database operations
        when(mockTargetDatabase.importDatabaseSnapshot(any))
            .thenAnswer((_) async {});
        when(mockTargetDatabase.updateSyncMetadata(
          any,
          lastSyncTimestamp: anyNamed('lastSyncTimestamp'),
          lastBackupTimestamp: anyNamed('lastBackupTimestamp'),
          pendingChangesCount: anyNamed('pendingChangesCount'),
          conflictCount: anyNamed('conflictCount'),
        )).thenAnswer((_) async {});

        // Act - Perform restore
        final restoreResult = await restoreService.restoreFromBackup('new_backup_id');

        // Assert - Restore should succeed
        expect(restoreResult.success, isTrue);
        expect(restoreResult.totalRestored, equals(6));
        expect(restoreResult.restoredCounts!['patients'], equals(2));
        expect(restoreResult.restoredCounts!['visits'], equals(2));
        expect(restoreResult.restoredCounts!['payments'], equals(2));

        // Verify restore operations
        verify(mockDriveService.downloadBackupFile('new_backup_id', onProgress: anyNamed('onProgress'))).called(1);
        verify(mockEncryption.decryptData(encryptedData, 'target_encryption_key')).called(1);
        verify(mockTargetDatabase.importDatabaseSnapshot(any)).called(1);

        // PHASE 3: VERIFICATION
        // Verify that the restored data matches the original data
        final capturedSnapshot = verify(mockTargetDatabase.importDatabaseSnapshot(captureAny)).captured.single;
        expect(capturedSnapshot['tables']['patients'], hasLength(2));
        expect(capturedSnapshot['tables']['visits'], hasLength(2));
        expect(capturedSnapshot['tables']['payments'], hasLength(2));

        // Verify patient data integrity
        final restoredPatients = capturedSnapshot['tables']['patients'] as List;
        expect(restoredPatients.any((p) => p['name'] == 'John Doe'), isTrue);
        expect(restoredPatients.any((p) => p['name'] == 'Jane Smith'), isTrue);

        // Verify visit data integrity
        final restoredVisits = capturedSnapshot['tables']['visits'] as List;
        expect(restoredVisits.any((v) => v['diagnosis'] == 'Common cold'), isTrue);
        expect(restoredVisits.any((v) => v['diagnosis'] == 'Headache'), isTrue);

        // Verify payment data integrity
        final restoredPayments = capturedSnapshot['tables']['payments'] as List;
        expect(restoredPayments.any((p) => p['amount'] == 50.0), isTrue);
        expect(restoredPayments.any((p) => p['amount'] == 75.0), isTrue);
      });

      test('should handle incremental backup and restore correctly', () async {
        // Arrange - Simulate incremental backup scenario
        final existingBackupData = BackupData.create(
          clinicId: testClinicId,
          deviceId: sourceDeviceId,
          tables: {
            'patients': [
              {
                'id': 'patient_1',
                'name': 'John Doe',
                'phone': '+1234567890',
                'last_modified': DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch,
                'device_id': sourceDeviceId,
              },
            ],
          },
          metadata: {'backup_type': 'full'},
        );

        final newChanges = [
          Patient(
            id: 'patient_2',
            name: 'Jane Smith',
            phone: '+0987654321',
            lastModified: DateTime.now(),
            deviceId: sourceDeviceId,
          ),
        ];

        final incrementalBackupData = BackupData.create(
          clinicId: testClinicId,
          deviceId: sourceDeviceId,
          tables: {
            'patients': [
              // Include existing patient
              {
                'id': 'patient_1',
                'name': 'John Doe',
                'phone': '+1234567890',
                'last_modified': DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch,
                'device_id': sourceDeviceId,
              },
              // Add new patient
              ...newChanges.map((p) => p.toSyncJson()),
            ],
          },
          metadata: {'backup_type': 'incremental'},
        );

        // Mock existing backup
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.getLatestBackup())
            .thenAnswer((_) async => BackupFileInfo(
              id: 'existing_backup',
              name: 'existing_backup.enc',
              size: 1024,
              createdTime: DateTime.now().subtract(const Duration(days: 1)),
              modifiedTime: DateTime.now().subtract(const Duration(days: 1)),
            ));
        when(mockDriveService.downloadBackupFile('existing_backup'))
            .thenAnswer((_) async => utf8.encode(jsonEncode(existingBackupData.toJson())));

        // Mock incremental changes
        when(mockSourceDatabase.getChangedRecords('patients', any))
            .thenAnswer((_) async => newChanges.map((p) => p.toSyncJson()).toList());
        when(mockSourceDatabase.markRecordsSynced('patients', any))
            .thenAnswer((_) async {});

        // Mock encryption
        when(mockEncryption.deriveEncryptionKey(testClinicId, sourceDeviceId))
            .thenAnswer((_) async => 'encryption_key');
        when(mockEncryption.decryptData(any, 'encryption_key'))
            .thenAnswer((_) async => existingBackupData.toJson());
        when(mockEncryption.encryptData(any, 'encryption_key'))
            .thenAnswer((_) async => utf8.encode(jsonEncode(incrementalBackupData.toJson())));

        // Mock upload of merged backup
        when(mockDriveService.uploadBackupFile(any, any))
            .thenAnswer((_) async => 'incremental_backup_id');

        // Act - Perform incremental sync
        final syncResult = await syncService.performIncrementalSync();

        // Assert
        expect(syncResult.status, equals(SyncResultStatus.success));
        expect(syncResult.syncedCounts!['patients'], equals(1)); // Only new changes

        // Verify operations
        verify(mockDriveService.getLatestBackup()).called(1);
        verify(mockDriveService.downloadBackupFile('existing_backup')).called(1);
        verify(mockDriveService.uploadBackupFile(any, any)).called(1);
        verify(mockSourceDatabase.getChangedRecords('patients', any)).called(1);
        verify(mockSourceDatabase.getChangedRecords('visits', any)).called(1);
      });

      test('should handle large dataset backup and restore efficiently', () async {
        // Arrange - Create large dataset
        final largePatientList = List.generate(1000, (index) => Patient(
          id: 'patient_$index',
          name: 'Patient $index',
          phone: '+123456789$index',
          lastModified: DateTime.now().subtract(Duration(minutes: index)),
          deviceId: sourceDeviceId,
        ));

        final largeVisitList = List.generate(2000, (index) => Visit(
          id: 'visit_$index',
          patientId: 'patient_${index % 1000}',
          visitDate: DateTime.now().subtract(Duration(days: index % 30)),
          diagnosis: 'Diagnosis $index',
          lastModified: DateTime.now().subtract(Duration(minutes: index)),
          deviceId: sourceDeviceId,
        ));

        final largeBackupData = BackupData.create(
          clinicId: testClinicId,
          deviceId: sourceDeviceId,
          tables: {
            'patients': largePatientList.map((p) => p.toSyncJson()).toList(),
            'visits': largeVisitList.map((v) => v.toSyncJson()).toList(),
          },
          metadata: {
            'backup_type': 'full',
            'total_records': 3000,
          },
        );

        final largeEncryptedData = List.generate(1024 * 1024, (i) => i % 256); // 1MB

        // Mock source database
        when(mockSourceDatabase.getChangedRecords('patients', any))
            .thenAnswer((_) async => largePatientList.map((p) => p.toSyncJson()).toList());
        when(mockSourceDatabase.getChangedRecords('visits', any))
            .thenAnswer((_) async => largeVisitList.map((v) => v.toSyncJson()).toList());
        when(mockSourceDatabase.markRecordsSynced('patients', any))
            .thenAnswer((_) async {});
        when(mockSourceDatabase.markRecordsSynced('visits', any))
            .thenAnswer((_) async {});

        // Mock Google Drive operations
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.getLatestBackup()).thenAnswer((_) async => null);
        when(mockDriveService.uploadBackupFile(any, any))
            .thenAnswer((_) async => 'large_backup_id');
        when(mockDriveService.listBackupFiles())
            .thenAnswer((_) async => [
          BackupFileInfo(
            id: 'large_backup_id',
            name: 'large_backup.enc',
            size: largeEncryptedData.length,
            createdTime: DateTime.now(),
            modifiedTime: DateTime.now(),
          ),
        ]);
        when(mockDriveService.downloadBackupFile('large_backup_id', onProgress: anyNamed('onProgress')))
            .thenAnswer((_) async => largeEncryptedData);

        // Mock encryption
        when(mockEncryption.deriveEncryptionKey(any, any))
            .thenAnswer((_) async => 'large_key');
        when(mockEncryption.encryptData(any, 'large_key'))
            .thenAnswer((_) async => EncryptedData(
              data: largeEncryptedData,
              iv: List.generate(12, (i) => i),
              tag: List.generate(16, (i) => i),
              algorithm: 'AES-256-GCM',
              checksum: 'test_checksum',
              timestamp: DateTime.now(),
            ));
        when(mockEncryption.decryptData(any, 'large_key'))
            .thenAnswer((_) async => largeBackupData.toJson());

        // Mock target database
        when(mockTargetDatabase.importDatabaseSnapshot(any))
            .thenAnswer((_) async {});
        when(mockTargetDatabase.updateSyncMetadata(
          any,
          lastSyncTimestamp: anyNamed('lastSyncTimestamp'),
          lastBackupTimestamp: anyNamed('lastBackupTimestamp'),
          pendingChangesCount: anyNamed('pendingChangesCount'),
          conflictCount: anyNamed('conflictCount'),
        )).thenAnswer((_) async {});

        // Act - Measure performance
        final stopwatch = Stopwatch()..start();

        // Perform backup
        final backupResult = await syncService.createBackup();
        final backupTime = stopwatch.elapsedMilliseconds;

        // Perform restore
        stopwatch.reset();
        final restoreResult = await restoreService.restoreFromBackup('large_backup_id');
        final restoreTime = stopwatch.elapsedMilliseconds;

        stopwatch.stop();

        // Assert
        expect(backupResult.status, equals(SyncResultStatus.success));
        expect(backupResult.syncedCounts!['patients'], equals(1000));
        expect(backupResult.syncedCounts!['visits'], equals(2000));

        expect(restoreResult.success, isTrue);
        expect(restoreResult.totalRestored, equals(3000));

        // Performance assertions
        expect(backupTime, lessThan(15000)); // 15 seconds for backup
        expect(restoreTime, lessThan(15000)); // 15 seconds for restore

        // Verify operations
        verify(mockDriveService.uploadBackupFile(any, any)).called(1);
        verify(mockDriveService.downloadBackupFile('large_backup_id', onProgress: anyNamed('onProgress'))).called(1);
        verify(mockTargetDatabase.importDatabaseSnapshot(any)).called(1);
      });
    });

    group('Error Recovery Scenarios', () {
      test('should recover from backup corruption during restore', () async {
        // Arrange - Simulate corrupted backup
        final validBackupData = BackupData.create(
          clinicId: testClinicId,
          deviceId: sourceDeviceId,
          tables: {
            'patients': [
              {
                'id': 'patient_1',
                'name': 'John Doe',
                'phone': '+1234567890',
                'last_modified': DateTime.now().millisecondsSinceEpoch,
                'device_id': sourceDeviceId,
              },
            ],
          },
        );

        final corruptedBackupFiles = [
          BackupFileInfo(
            id: 'corrupted_backup',
            name: 'corrupted_backup.enc',
            size: 0, // Empty/corrupted file
            createdTime: DateTime.now(),
            modifiedTime: DateTime.now(),
          ),
          BackupFileInfo(
            id: 'valid_backup',
            name: 'valid_backup.enc',
            size: 1024,
            createdTime: DateTime.now().subtract(const Duration(hours: 1)),
            modifiedTime: DateTime.now().subtract(const Duration(hours: 1)),
          ),
        ];

        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.listBackupFiles())
            .thenAnswer((_) async => corruptedBackupFiles);

        // Mock corrupted backup download fails
        when(mockDriveService.downloadBackupFile('corrupted_backup', onProgress: anyNamed('onProgress')))
            .thenThrow(Exception('Corrupted backup file'));

        // Mock valid backup download succeeds
        when(mockDriveService.downloadBackupFile('valid_backup', onProgress: anyNamed('onProgress')))
            .thenAnswer((_) async => utf8.encode(jsonEncode(validBackupData.toJson())));

        // Mock encryption
        when(mockEncryption.deriveEncryptionKey(testClinicId, targetDeviceId))
            .thenAnswer((_) async => 'recovery_key');
        when(mockEncryption.decryptData(any, 'recovery_key'))
            .thenAnswer((_) async => validBackupData.toJson());

        // Mock target database
        when(mockTargetDatabase.importDatabaseSnapshot(any))
            .thenAnswer((_) async {});
        when(mockTargetDatabase.updateSyncMetadata(
          any,
          lastSyncTimestamp: anyNamed('lastSyncTimestamp'),
          lastBackupTimestamp: anyNamed('lastBackupTimestamp'),
          pendingChangesCount: anyNamed('pendingChangesCount'),
          conflictCount: anyNamed('conflictCount'),
        )).thenAnswer((_) async {});

        // Act - Try to restore from corrupted backup, should fallback to valid backup
        final restoreResult = await restoreService.restoreFromBackup('corrupted_backup');

        // Assert - Should succeed by falling back to valid backup
        expect(restoreResult.success, isTrue);
        expect(restoreResult.totalRestored, equals(1));
        expect(restoreResult.metadata!['fallback_used'], isTrue);

        // Verify fallback was used
        verify(mockDriveService.downloadBackupFile('corrupted_backup', onProgress: anyNamed('onProgress'))).called(1);
        verify(mockDriveService.downloadBackupFile('valid_backup', onProgress: anyNamed('onProgress'))).called(1);
      });

      test('should handle partial restore when some tables fail', () async {
        // Arrange
        final mixedBackupData = BackupData.create(
          clinicId: testClinicId,
          deviceId: sourceDeviceId,
          tables: {
            'patients': [
              {
                'id': 'patient_1',
                'name': 'John Doe',
                'phone': '+1234567890',
                'last_modified': DateTime.now().millisecondsSinceEpoch,
                'device_id': sourceDeviceId,
              },
            ],
            'visits': [
              {
                'id': 'visit_1',
                'patient_id': 'patient_1',
                'visit_date': 'invalid_date', // Corrupted data
                'last_modified': DateTime.now().millisecondsSinceEpoch,
                'device_id': sourceDeviceId,
              },
            ],
          },
        );

        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.downloadBackupFile('mixed_backup', onProgress: anyNamed('onProgress')))
            .thenAnswer((_) async => utf8.encode(jsonEncode(mixedBackupData.toJson())));

        when(mockEncryption.deriveEncryptionKey(testClinicId, targetDeviceId))
            .thenAnswer((_) async => 'mixed_key');
        when(mockEncryption.decryptData(any, 'mixed_key'))
            .thenAnswer((_) async => mixedBackupData.toJson());

        // Mock database operations - patients succeed, visits fail
        when(mockTargetDatabase.applyRemoteChanges('patients', any))
            .thenAnswer((_) async {});
        when(mockTargetDatabase.applyRemoteChanges('visits', any))
            .thenThrow(Exception('Invalid visit data'));
        when(mockTargetDatabase.updateSyncMetadata(
          any,
          lastSyncTimestamp: anyNamed('lastSyncTimestamp'),
          lastBackupTimestamp: anyNamed('lastBackupTimestamp'),
          pendingChangesCount: anyNamed('pendingChangesCount'),
          conflictCount: anyNamed('conflictCount'),
        )).thenAnswer((_) async {});

        // Act
        final restoreResult = await restoreService.handlePartialRestore(
          'mixed_backup',
          skipCorruptedTables: true,
        );

        // Assert - Should succeed with partial data
        expect(restoreResult.success, isTrue);
        expect(restoreResult.restoredCounts!['patients'], equals(1));
        expect(restoreResult.restoredCounts!.containsKey('visits'), isFalse);
        expect(restoreResult.metadata!['failed_tables'], contains('visits'));
        expect(restoreResult.metadata!['partial_restore'], isTrue);

        // Verify operations
        verify(mockTargetDatabase.applyRemoteChanges('patients', any)).called(1);
        verify(mockTargetDatabase.applyRemoteChanges('visits', any)).called(1);
      });
    });
  });
}