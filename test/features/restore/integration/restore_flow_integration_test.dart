import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';

import 'package:doc_ledger/features/restore/services/restore_service.dart';
import 'package:doc_ledger/features/restore/models/restore_models.dart';
import 'package:doc_ledger/core/sync/services/sync_service.dart';
import 'package:doc_ledger/core/cloud/services/google_drive_service.dart';
import 'package:doc_ledger/core/data/services/database_service.dart';
import 'package:doc_ledger/core/encryption/services/encryption_service.dart';
import 'package:doc_ledger/core/encryption/models/encryption_models.dart';
import 'package:doc_ledger/core/sync/models/sync_models.dart';

import 'restore_flow_integration_test.mocks.dart';

@GenerateMocks([
  SyncService,
  GoogleDriveService,
  DatabaseService,
  EncryptionService,
])
void main() {
  group('Restore Flow Integration Tests', () {
    late RestoreService restoreService;
    late MockSyncService mockSyncService;
    late MockGoogleDriveService mockDriveService;
    late MockDatabaseService mockDatabase;
    late MockEncryptionService mockEncryption;

    const testClinicId = 'test_clinic_123';
    const testDeviceId = 'test_device_456';

    setUp(() {
      mockSyncService = MockSyncService();
      mockDriveService = MockGoogleDriveService();
      mockDatabase = MockDatabaseService();
      mockEncryption = MockEncryptionService();

      restoreService = RestoreService(
        syncService: mockSyncService,
        driveService: mockDriveService,
        database: mockDatabase,
        encryption: mockEncryption,
        clinicId: testClinicId,
        deviceId: testDeviceId,
      );
    });

    tearDown(() {
      restoreService.dispose();
    });

    group('Device Setup Wizard Flow', () {
      test('should complete full setup wizard flow successfully', () async {
        // Arrange
        final testBackupFiles = [
          BackupFileInfo(
            id: 'backup_1',
            name: 'docledger_backup_${testClinicId}_2024-01-15T10-30-00.enc',
            size: 1024 * 1024, // 1MB
            createdTime: DateTime(2024, 1, 15, 10, 30),
            modifiedTime: DateTime(2024, 1, 15, 10, 30),
            description: 'Test backup',
          ),
          BackupFileInfo(
            id: 'backup_2',
            name: 'docledger_backup_${testClinicId}_2024-01-14T09-15-00.enc',
            size: 512 * 1024, // 512KB
            createdTime: DateTime(2024, 1, 14, 9, 15),
            modifiedTime: DateTime(2024, 1, 14, 9, 15),
            description: 'Older backup',
          ),
        ];

        final testBackupData = BackupData.create(
          clinicId: testClinicId,
          deviceId: 'source_device',
          tables: {
            'patients': [
              {'id': '1', 'name': 'John Doe', 'last_modified': 1642248600000},
              {'id': '2', 'name': 'Jane Smith', 'last_modified': 1642248700000},
            ],
            'visits': [
              {'id': '1', 'patient_id': '1', 'visit_date': '2024-01-15', 'last_modified': 1642248800000},
            ],
            'payments': [
              {'id': '1', 'patient_id': '1', 'amount': 100.0, 'last_modified': 1642248900000},
            ],
          },
          metadata: {'test': true},
        );

        final encryptedData = EncryptedData(
          data: [1, 2, 3, 4, 5], // Mock encrypted bytes
          iv: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
          tag: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
          algorithm: 'AES-256-GCM',
          checksum: 'test_checksum',
          timestamp: DateTime.now(),
        );

        // Mock Google Drive authentication
        when(mockDriveService.isAuthenticated).thenReturn(true);

        // Mock backup file listing
        when(mockDriveService.listBackupFiles()).thenAnswer((_) async => testBackupFiles);

        // Mock backup file download
        when(mockDriveService.downloadBackupFile('backup_1', onProgress: anyNamed('onProgress')))
            .thenAnswer((_) async => encryptedData.data);

        // Mock encryption key derivation
        when(mockEncryption.deriveEncryptionKey(testClinicId, testDeviceId))
            .thenAnswer((_) async => 'test_encryption_key');

        // Mock data decryption
        when(mockEncryption.decryptData(any, 'test_encryption_key'))
            .thenAnswer((_) async => testBackupData.toJson());

        // Mock database import
        when(mockDatabase.importDatabaseSnapshot(any)).thenAnswer((_) async {});

        // Mock sync metadata update
        when(mockDatabase.updateSyncMetadata(
          any,
          lastSyncTimestamp: anyNamed('lastSyncTimestamp'),
          lastBackupTimestamp: anyNamed('lastBackupTimestamp'),
          pendingChangesCount: anyNamed('pendingChangesCount'),
          conflictCount: anyNamed('conflictCount'),
        )).thenAnswer((_) async {});

        // Act
        final states = <RestoreState>[];
        restoreService.stateStream.listen(states.add);

        final result = await restoreService.startDeviceSetupWizard();

        // Assert
        expect(result.success, isTrue);
        expect(result.totalRestored, equals(4)); // 2 patients + 1 visit + 1 payment
        expect(result.restoredCounts, isNotNull);
        expect(result.restoredCounts!['patients'], equals(2));
        expect(result.restoredCounts!['visits'], equals(1));
        expect(result.restoredCounts!['payments'], equals(1));

        // Verify state progression
        expect(states.any((s) => s.status == RestoreStatus.selectingBackup), isTrue);
        expect(states.any((s) => s.status == RestoreStatus.validatingBackup), isTrue);
        expect(states.any((s) => s.status == RestoreStatus.downloading), isTrue);
        expect(states.any((s) => s.status == RestoreStatus.decrypting), isTrue);
        expect(states.any((s) => s.status == RestoreStatus.importing), isTrue);
        expect(states.any((s) => s.status == RestoreStatus.completed), isTrue);

        // Verify service calls
        verify(mockDriveService.listBackupFiles()).called(1);
        verify(mockDriveService.downloadBackupFile('backup_1', onProgress: anyNamed('onProgress'))).called(1);
        verify(mockEncryption.deriveEncryptionKey(testClinicId, testDeviceId)).called(1);
        verify(mockEncryption.decryptData(any, 'test_encryption_key')).called(1);
        verify(mockDatabase.importDatabaseSnapshot(any)).called(1);
        verify(mockDatabase.updateSyncMetadata(
          'patients',
          lastSyncTimestamp: anyNamed('lastSyncTimestamp'),
          lastBackupTimestamp: anyNamed('lastBackupTimestamp'),
          pendingChangesCount: 0,
          conflictCount: 0,
        )).called(1);
      });

      test('should handle authentication failure gracefully', () async {
        // Arrange
        when(mockDriveService.isAuthenticated).thenReturn(false);
        when(mockDriveService.authenticate()).thenAnswer((_) async => false);

        // Act
        final states = <RestoreState>[];
        restoreService.stateStream.listen(states.add);

        final result = await restoreService.startDeviceSetupWizard();

        // Assert
        expect(result.success, isFalse);
        expect(result.errorMessage, contains('authentication failed'));
        expect(states.any((s) => s.status == RestoreStatus.error), isTrue);
      });

      test('should handle no backups found scenario', () async {
        // Arrange
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.listBackupFiles()).thenAnswer((_) async => []);

        // Act
        final result = await restoreService.startDeviceSetupWizard();

        // Assert
        expect(result.success, isFalse);
        expect(result.errorMessage, contains('No backups found'));
      });

      test('should handle backup validation failure', () async {
        // Arrange
        final invalidBackupFiles = [
          BackupFileInfo(
            id: 'invalid_backup',
            name: 'invalid_backup.enc',
            size: 0, // Empty file
            createdTime: DateTime.now(),
            modifiedTime: DateTime.now(),
          ),
        ];

        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.listBackupFiles()).thenAnswer((_) async => invalidBackupFiles);

        // Act
        final result = await restoreService.startDeviceSetupWizard();

        // Assert
        expect(result.success, isFalse);
        expect(result.errorMessage, contains('validation failed'));
      });
    });

    group('Backup Selection and Validation', () {
      test('should correctly identify valid and invalid backups', () async {
        // Arrange
        final mixedBackupFiles = [
          BackupFileInfo(
            id: 'valid_backup',
            name: 'docledger_backup_${testClinicId}_2024-01-15T10-30-00.enc',
            size: 1024,
            createdTime: DateTime.now(),
            modifiedTime: DateTime.now(),
          ),
          BackupFileInfo(
            id: 'wrong_clinic',
            name: 'docledger_backup_other_clinic_2024-01-15T10-30-00.enc',
            size: 1024,
            createdTime: DateTime.now(),
            modifiedTime: DateTime.now(),
          ),
          BackupFileInfo(
            id: 'empty_backup',
            name: 'docledger_backup_${testClinicId}_2024-01-15T10-30-00.enc',
            size: 0,
            createdTime: DateTime.now(),
            modifiedTime: DateTime.now(),
          ),
        ];

        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.listBackupFiles()).thenAnswer((_) async => mixedBackupFiles);

        // Act
        final availableBackups = await restoreService.getAvailableBackups();

        // Assert
        expect(availableBackups.length, equals(3));
        
        final validBackup = availableBackups.firstWhere((b) => b.id == 'valid_backup');
        expect(validBackup.isValid, isTrue);
        expect(validBackup.validationError, isNull);

        final wrongClinicBackup = availableBackups.firstWhere((b) => b.id == 'wrong_clinic');
        expect(wrongClinicBackup.isValid, isFalse);
        expect(wrongClinicBackup.validationError, contains('does not belong to this clinic'));

        final emptyBackup = availableBackups.firstWhere((b) => b.id == 'empty_backup');
        expect(emptyBackup.isValid, isFalse);
        expect(emptyBackup.validationError, contains('empty'));
      });

      test('should sort backups by creation time (newest first)', () async {
        // Arrange
        final backupFiles = [
          BackupFileInfo(
            id: 'old_backup',
            name: 'docledger_backup_${testClinicId}_2024-01-10T10-30-00.enc',
            size: 1024,
            createdTime: DateTime(2024, 1, 10),
            modifiedTime: DateTime(2024, 1, 10),
          ),
          BackupFileInfo(
            id: 'new_backup',
            name: 'docledger_backup_${testClinicId}_2024-01-15T10-30-00.enc',
            size: 1024,
            createdTime: DateTime(2024, 1, 15),
            modifiedTime: DateTime(2024, 1, 15),
          ),
          BackupFileInfo(
            id: 'middle_backup',
            name: 'docledger_backup_${testClinicId}_2024-01-12T10-30-00.enc',
            size: 1024,
            createdTime: DateTime(2024, 1, 12),
            modifiedTime: DateTime(2024, 1, 12),
          ),
        ];

        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.listBackupFiles()).thenAnswer((_) async => backupFiles);

        // Act
        final availableBackups = await restoreService.getAvailableBackups();

        // Assert
        expect(availableBackups[0].id, equals('new_backup'));
        expect(availableBackups[1].id, equals('middle_backup'));
        expect(availableBackups[2].id, equals('old_backup'));
      });
    });

    group('Partial Restoration Scenarios', () {
      test('should handle partial restoration with specific tables', () async {
        // Arrange
        final testBackupData = BackupData.create(
          clinicId: testClinicId,
          deviceId: 'source_device',
          tables: {
            'patients': [
              {'id': '1', 'name': 'John Doe', 'last_modified': 1642248600000},
            ],
            'visits': [
              {'id': '1', 'patient_id': '1', 'visit_date': '2024-01-15', 'last_modified': 1642248800000},
            ],
            'payments': [
              {'id': '1', 'patient_id': '1', 'amount': 100.0, 'last_modified': 1642248900000},
            ],
          },
          metadata: {'test': true},
        );

        final encryptedData = EncryptedData(
          data: [1, 2, 3, 4, 5],
          iv: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
          tag: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
          algorithm: 'AES-256-GCM',
          checksum: 'test_checksum',
          timestamp: DateTime.now(),
        );

        when(mockDriveService.downloadBackupFile('backup_1', onProgress: anyNamed('onProgress')))
            .thenAnswer((_) async => encryptedData.data);
        when(mockEncryption.deriveEncryptionKey(testClinicId, testDeviceId))
            .thenAnswer((_) async => 'test_key');
        when(mockEncryption.decryptData(any, 'test_key'))
            .thenAnswer((_) async => testBackupData.toJson());
        when(mockDatabase.applyRemoteChanges(any, any)).thenAnswer((_) async {});
        when(mockDatabase.updateSyncMetadata(
          any,
          lastSyncTimestamp: anyNamed('lastSyncTimestamp'),
          lastBackupTimestamp: anyNamed('lastBackupTimestamp'),
          pendingChangesCount: anyNamed('pendingChangesCount'),
          conflictCount: anyNamed('conflictCount'),
        )).thenAnswer((_) async {});

        // Act - restore only patients and visits
        final result = await restoreService.handlePartialRestore(
          'backup_1',
          tablesToRestore: ['patients', 'visits'],
        );

        // Assert
        expect(result.success, isTrue);
        expect(result.restoredCounts!['patients'], equals(1));
        expect(result.restoredCounts!['visits'], equals(1));
        expect(result.restoredCounts!.containsKey('payments'), isFalse);
        expect(result.metadata!['partial_restore'], isTrue);
        expect(result.metadata!['tables_requested'], equals(2));
        expect(result.metadata!['tables_restored'], equals(2));

        // Verify only specified tables were restored
        verify(mockDatabase.applyRemoteChanges('patients', any)).called(1);
        verify(mockDatabase.applyRemoteChanges('visits', any)).called(1);
        verifyNever(mockDatabase.applyRemoteChanges('payments', any));
      });

      test('should handle corrupted table gracefully when skipCorruptedTables is true', () async {
        // Arrange
        final testBackupData = BackupData.create(
          clinicId: testClinicId,
          deviceId: 'source_device',
          tables: {
            'patients': [
              {'id': '1', 'name': 'John Doe', 'last_modified': 1642248600000},
            ],
            'visits': [
              {'id': '1', 'patient_id': '1', 'visit_date': '2024-01-15', 'last_modified': 1642248800000},
            ],
          },
          metadata: {'test': true},
        );

        final encryptedData = EncryptedData(
          data: [1, 2, 3, 4, 5],
          iv: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
          tag: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
          algorithm: 'AES-256-GCM',
          checksum: 'test_checksum',
          timestamp: DateTime.now(),
        );

        when(mockDriveService.downloadBackupFile('backup_1', onProgress: anyNamed('onProgress')))
            .thenAnswer((_) async => encryptedData.data);
        when(mockEncryption.deriveEncryptionKey(testClinicId, testDeviceId))
            .thenAnswer((_) async => 'test_key');
        when(mockEncryption.decryptData(any, 'test_key'))
            .thenAnswer((_) async => testBackupData.toJson());
        
        // Mock patients table to succeed
        when(mockDatabase.applyRemoteChanges('patients', any)).thenAnswer((_) async {});
        
        // Mock visits table to fail
        when(mockDatabase.applyRemoteChanges('visits', any))
            .thenThrow(Exception('Corrupted table data'));
        
        when(mockDatabase.updateSyncMetadata(
          any,
          lastSyncTimestamp: anyNamed('lastSyncTimestamp'),
          lastBackupTimestamp: anyNamed('lastBackupTimestamp'),
          pendingChangesCount: anyNamed('pendingChangesCount'),
          conflictCount: anyNamed('conflictCount'),
        )).thenAnswer((_) async {});

        // Act
        final result = await restoreService.handlePartialRestore(
          'backup_1',
          skipCorruptedTables: true,
        );

        // Assert
        expect(result.success, isTrue);
        expect(result.restoredCounts!['patients'], equals(1));
        expect(result.restoredCounts!.containsKey('visits'), isFalse);
        expect(result.metadata!['failed_tables'], contains('visits'));
        expect(result.metadata!['tables_restored'], equals(1));
      });
    });

    group('Cancellation Support', () {
      test('should handle cancellation during restoration', () async {
        // Arrange
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.listBackupFiles()).thenAnswer((_) async => [
          BackupFileInfo(
            id: 'backup_1',
            name: 'docledger_backup_${testClinicId}_2024-01-15T10-30-00.enc',
            size: 1024,
            createdTime: DateTime.now(),
            modifiedTime: DateTime.now(),
          ),
        ]);

        // Mock a slow download that we can cancel
        when(mockDriveService.downloadBackupFile('backup_1', onProgress: anyNamed('onProgress')))
            .thenAnswer((_) async {
          await Future.delayed(const Duration(milliseconds: 100));
          return [1, 2, 3, 4, 5];
        });

        // Act
        final states = <RestoreState>[];
        restoreService.stateStream.listen(states.add);

        // Start restoration and cancel it quickly
        final resultFuture = restoreService.restoreFromBackup('backup_1');
        await Future.delayed(const Duration(milliseconds: 50));
        restoreService.cancelRestore();
        
        final result = await resultFuture;

        // Assert
        expect(result.success, isFalse);
        expect(result.errorMessage, contains('cancelled'));
        expect(states.any((s) => s.status == RestoreStatus.cancelled), isTrue);
      });
    });

    group('Error Handling', () {
      test('should handle network errors during download', () async {
        // Arrange
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.downloadBackupFile('backup_1', onProgress: anyNamed('onProgress')))
            .thenThrow(Exception('Network error'));

        // Act
        final result = await restoreService.restoreFromBackup('backup_1');

        // Assert
        expect(result.success, isFalse);
        expect(result.errorMessage, contains('Network error'));
      });

      test('should handle decryption errors', () async {
        // Arrange
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.downloadBackupFile('backup_1', onProgress: anyNamed('onProgress')))
            .thenAnswer((_) async => [1, 2, 3, 4, 5]);
        when(mockEncryption.deriveEncryptionKey(testClinicId, testDeviceId))
            .thenAnswer((_) async => 'test_key');
        when(mockEncryption.decryptData(any, 'test_key'))
            .thenThrow(Exception('Decryption failed'));

        // Act
        final result = await restoreService.restoreFromBackup('backup_1');

        // Assert
        expect(result.success, isFalse);
        expect(result.errorMessage, contains('decrypt'));
      });

      test('should handle database import errors', () async {
        // Arrange
        final testBackupData = BackupData.create(
          clinicId: testClinicId,
          deviceId: 'source_device',
          tables: {'patients': []},
          metadata: {},
        );

        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.downloadBackupFile('backup_1', onProgress: anyNamed('onProgress')))
            .thenAnswer((_) async => [1, 2, 3, 4, 5]);
        when(mockEncryption.deriveEncryptionKey(testClinicId, testDeviceId))
            .thenAnswer((_) async => 'test_key');
        when(mockEncryption.decryptData(any, 'test_key'))
            .thenAnswer((_) async => testBackupData.toJson());
        when(mockDatabase.importDatabaseSnapshot(any))
            .thenThrow(Exception('Database import failed'));

        // Act
        final result = await restoreService.restoreFromBackup('backup_1');

        // Assert
        expect(result.success, isFalse);
        expect(result.errorMessage, contains('import'));
      });
    });
  });
}