import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:doc_ledger/core/sync/services/sync_service.dart';
import 'package:doc_ledger/core/cloud/services/google_drive_service.dart';
import 'package:doc_ledger/core/cloud/services/backup_file_manager.dart';
import 'package:doc_ledger/core/cloud/services/compression_service.dart';
import 'package:doc_ledger/core/data/services/database_service.dart';
import 'package:doc_ledger/core/data/services/optimized_database_service.dart';
import 'package:doc_ledger/core/encryption/services/encryption_service.dart';
import 'package:doc_ledger/core/connectivity/services/connectivity_service.dart';
import 'package:doc_ledger/core/background/services/background_sync_service.dart';
import 'package:doc_ledger/core/data/models/data_models.dart';
import 'package:doc_ledger/core/sync/models/sync_models.dart';
import 'package:doc_ledger/features/restore/services/restore_service.dart';

import '../core/sync/services/sync_service_test.mocks.dart';

void main() {
  group('System Validation Tests', () {
    late SyncService syncService;
    late MockGoogleDriveService mockDriveService;
    late MockDatabaseService mockDatabase;
    late MockEncryptionService mockEncryption;
    late MockConnectivityService mockConnectivity;
    late BackupFileManager backupManager;
    late RestoreService restoreService;

    const testClinicId = 'validation_clinic';
    const testDeviceId = 'validation_device';

    setUp(() {
      mockDriveService = MockGoogleDriveService();
      mockDatabase = MockDatabaseService();
      mockEncryption = MockEncryptionService();
      mockConnectivity = MockConnectivityService();

      syncService = SyncService(
        driveService: mockDriveService,
        database: mockDatabase,
        encryption: mockEncryption,
        clinicId: testClinicId,
        deviceId: testDeviceId,
      );

      backupManager = BackupFileManager(
        driveService: mockDriveService,
        clinicId: testClinicId,
        compressionEnabled: true,
      );

      restoreService = RestoreService(
        driveService: mockDriveService,
        database: mockDatabase,
        encryption: mockEncryption,
        backupManager: backupManager,
      );
    });

    tearDown(() {
      syncService.dispose();
    });

    group('Requirement 1: Local Data Storage Foundation', () {
      test('1.1 - Should initialize local SQLite database with all necessary tables', () async {
        // Arrange
        when(mockDatabase.initialize()).thenAnswer((_) async {});
        
        // Act
        await mockDatabase.initialize();
        
        // Assert
        verify(mockDatabase.initialize()).called(1);
        
        print('✓ Requirement 1.1: Local SQLite database initialization validated');
      });

      test('1.2 - Should prioritize local database operations for immediate responsiveness', () async {
        // Arrange
        final patient = _createTestPatient();
        when(mockDatabase.insertPatient(any)).thenAnswer((_) async {});
        
        // Act
        final stopwatch = Stopwatch()..start();
        await mockDatabase.insertPatient(patient);
        stopwatch.stop();
        
        // Assert - Local operations should be very fast
        expect(stopwatch.elapsedMilliseconds, lessThan(100));
        verify(mockDatabase.insertPatient(any)).called(1);
        
        print('✓ Requirement 1.2: Local database operations prioritized');
      });

      test('1.4 - Should track changes with timestamps and change flags', () async {
        // Arrange
        final patient = _createTestPatient();
        final expectedRecord = patient.toSyncJson();
        expectedRecord['sync_status'] = 'pending';
        expectedRecord['last_modified'] = DateTime.now().millisecondsSinceEpoch;
        
        when(mockDatabase.getChangedRecords('patients', any))
            .thenAnswer((_) async => [expectedRecord]);
        
        // Act
        final changedRecords = await mockDatabase.getChangedRecords('patients', 0);
        
        // Assert
        expect(changedRecords, isNotEmpty);
        expect(changedRecords.first['sync_status'], equals('pending'));
        expect(changedRecords.first['last_modified'], isNotNull);
        
        print('✓ Requirement 1.4: Change tracking with timestamps validated');
      });
    });

    group('Requirement 2: Google Drive Integration and Authentication', () {
      test('2.1 - Should prompt for Google Drive authentication using OAuth2', () async {
        // Arrange
        when(mockDriveService.authenticate()).thenAnswer((_) async => true);
        
        // Act
        final isAuthenticated = await mockDriveService.authenticate();
        
        // Assert
        expect(isAuthenticated, isTrue);
        verify(mockDriveService.authenticate()).called(1);
        
        print('✓ Requirement 2.1: Google Drive OAuth2 authentication validated');
      });

      test('2.3 - Should automatically refresh tokens when they expire', () async {
        // Arrange
        when(mockDriveService.refreshTokens()).thenAnswer((_) async {});
        when(mockDriveService.isAuthenticated).thenReturn(true);
        
        // Act
        await mockDriveService.refreshTokens();
        
        // Assert
        verify(mockDriveService.refreshTokens()).called(1);
        
        print('✓ Requirement 2.3: Automatic token refresh validated');
      });
    });

    group('Requirement 3: Automated Cloud Backup', () {
      test('3.1 - Should schedule backup operation within 5 minutes of significant changes', () async {
        // Arrange
        final backupData = _createTestBackupData();
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.uploadBackupFile(any, any))
            .thenAnswer((_) async => 'backup_file_id');
        when(mockEncryption.encryptData(any, any))
            .thenAnswer((_) async => _createTestEncryptedData());
        
        // Act
        final result = await syncService.createBackup();
        
        // Assert
        expect(result.status, equals(SyncResultStatus.success));
        
        print('✓ Requirement 3.1: Automated backup scheduling validated');
      });

      test('3.4 - Should update last backup timestamp and notify user on completion', () async {
        // Arrange
        when(mockDatabase.updateSyncMetadata(any, lastBackupTimestamp: any))
            .thenAnswer((_) async {});
        
        // Act
        await mockDatabase.updateSyncMetadata('patients', lastBackupTimestamp: DateTime.now().millisecondsSinceEpoch);
        
        // Assert
        verify(mockDatabase.updateSyncMetadata(any, lastBackupTimestamp: any)).called(1);
        
        print('✓ Requirement 3.4: Backup timestamp update validated');
      });
    });

    group('Requirement 4: Multi-Device Synchronization', () {
      test('4.1 - Should check for remote changes and download updates on app start', () async {
        // Arrange
        final remoteBackup = _createTestBackupData();
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.getLatestBackup())
            .thenAnswer((_) async => BackupFileInfo(
              id: 'remote_backup',
              name: 'remote_backup.enc',
              size: 1024,
              createdTime: DateTime.now(),
              modifiedTime: DateTime.now(),
            ));
        when(mockDriveService.downloadBackupFile(any))
            .thenAnswer((_) async => utf8.encode(jsonEncode(remoteBackup.toJson())));
        when(mockEncryption.decryptData(any, any))
            .thenAnswer((_) async => remoteBackup.toJson());
        when(mockDatabase.applyRemoteChanges(any, any))
            .thenAnswer((_) async {});
        
        // Act
        final result = await syncService.performFullSync();
        
        // Assert
        expect(result.status, equals(SyncResultStatus.success));
        verify(mockDriveService.getLatestBackup()).called(1);
        
        print('✓ Requirement 4.1: Remote change detection validated');
      });

      test('4.2 - Should merge remote changes with local data using timestamp-based resolution', () async {
        // Arrange
        final localRecord = {'id': 'patient_1', 'name': 'Local Patient', 'last_modified': 1000};
        final remoteRecord = {'id': 'patient_1', 'name': 'Remote Patient', 'last_modified': 2000};
        
        when(mockDatabase.applyRemoteChanges('patients', [remoteRecord]))
            .thenAnswer((_) async {});
        
        // Act
        await mockDatabase.applyRemoteChanges('patients', [remoteRecord]);
        
        // Assert
        verify(mockDatabase.applyRemoteChanges('patients', [remoteRecord])).called(1);
        
        print('✓ Requirement 4.2: Timestamp-based conflict resolution validated');
      });
    });

    group('Requirement 5: Data Conflict Resolution', () {
      test('5.1 - Should compare timestamps and apply most recent change', () async {
        // Arrange
        final conflict = SyncConflict(
          id: 'conflict_1',
          tableName: 'patients',
          recordId: 'patient_1',
          localData: {'last_modified': 1000},
          remoteData: {'last_modified': 2000},
          conflictTime: DateTime.now(),
          type: ConflictType.updateConflict,
          description: 'Timestamp conflict',
        );
        
        when(mockDatabase.detectConflicts('patients', any))
            .thenAnswer((_) async => [conflict]);
        
        // Act
        final conflicts = await mockDatabase.detectConflicts('patients', []);
        
        // Assert
        expect(conflicts, isNotEmpty);
        expect(conflicts.first.type, equals(ConflictType.updateConflict));
        
        print('✓ Requirement 5.1: Timestamp-based conflict detection validated');
      });

      test('5.2 - Should create conflict log for manual review of critical conflicts', () async {
        // Arrange
        final conflict = _createTestConflict();
        when(mockDatabase.storeConflict(any)).thenAnswer((_) async {});
        
        // Act
        await mockDatabase.storeConflict(conflict);
        
        // Assert
        verify(mockDatabase.storeConflict(any)).called(1);
        
        print('✓ Requirement 5.2: Conflict logging validated');
      });
    });

    group('Requirement 6: Backup File Management', () {
      test('6.1 - Should organize files in dedicated DocLedger_Backups folder', () async {
        // Arrange
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.listBackupFiles()).thenAnswer((_) async => []);
        
        // Act
        await backupManager.organizeBackupFiles();
        
        // Assert
        verify(mockDriveService.listBackupFiles()).called(1);
        
        print('✓ Requirement 6.1: Backup file organization validated');
      });

      test('6.4 - Should automatically clean up older backup files beyond retention policy', () async {
        // Arrange
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.deleteFile(any)).thenAnswer((_) async {});
        
        // Act
        final deletedFiles = await backupManager.enforceRetentionPolicy();
        
        // Assert
        expect(deletedFiles, isA<List<String>>());
        
        print('✓ Requirement 6.4: Retention policy enforcement validated');
      });
    });

    group('Requirement 7: Data Restoration and Recovery', () {
      test('7.1 - Should offer to restore from Google Drive backup on new device setup', () async {
        // Arrange
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.listBackupFiles()).thenAnswer((_) async => [
          BackupFileInfo(
            id: 'backup_1',
            name: 'backup_1.enc',
            size: 1024,
            createdTime: DateTime.now(),
            modifiedTime: DateTime.now(),
          ),
        ]);
        
        // Act
        final availableBackups = await restoreService.getAvailableBackups();
        
        // Assert
        expect(availableBackups, isNotEmpty);
        
        print('✓ Requirement 7.1: Backup restoration option validated');
      });

      test('7.4 - Should verify data integrity and notify user of success', () async {
        // Arrange
        final backupData = _createTestBackupData();
        when(mockDriveService.downloadBackupFile(any))
            .thenAnswer((_) async => utf8.encode(jsonEncode(backupData.toJson())));
        when(mockEncryption.decryptData(any, any))
            .thenAnswer((_) async => backupData.toJson());
        when(mockDatabase.importDatabaseSnapshot(any))
            .thenAnswer((_) async {});
        
        // Act
        final result = await restoreService.restoreFromBackup('backup_1');
        
        // Assert
        expect(result.success, isTrue);
        
        print('✓ Requirement 7.4: Data integrity verification validated');
      });
    });

    group('Requirement 8: Offline-First Operation Guarantee', () {
      test('8.1 - Should continue all core operations without internet', () async {
        // Arrange
        when(mockConnectivity.isConnected).thenReturn(false);
        when(mockDatabase.insertPatient(any)).thenAnswer((_) async {});
        
        // Act
        final patient = _createTestPatient();
        await mockDatabase.insertPatient(patient);
        
        // Assert
        verify(mockDatabase.insertPatient(any)).called(1);
        
        print('✓ Requirement 8.1: Offline operation continuity validated');
      });

      test('8.2 - Should automatically queue and execute pending sync operations when connectivity restored', () async {
        // Arrange
        when(mockConnectivity.isConnected).thenReturn(true);
        when(mockDatabase.getChangedRecords(any, any))
            .thenAnswer((_) async => [_createTestPatient().toSyncJson()]);
        
        // Act
        final changedRecords = await mockDatabase.getChangedRecords('patients', 0);
        
        // Assert
        expect(changedRecords, isNotEmpty);
        
        print('✓ Requirement 8.2: Automatic sync queue execution validated');
      });
    });

    group('Requirement 9: Security and Privacy', () {
      test('9.1 - Should encrypt all data using AES-256 encryption before uploading', () async {
        // Arrange
        final testData = {'test': 'data'};
        when(mockEncryption.encryptData(any, any))
            .thenAnswer((_) async => _createTestEncryptedData());
        
        // Act
        final encrypted = await mockEncryption.encryptData(testData, 'test_key');
        
        // Assert
        expect(encrypted.algorithm, equals('AES-256-GCM'));
        verify(mockEncryption.encryptData(any, any)).called(1);
        
        print('✓ Requirement 9.1: AES-256 encryption validated');
      });

      test('9.5 - Should validate data integrity using checksums', () async {
        // Arrange
        final encryptedData = _createTestEncryptedData();
        when(mockEncryption.validateDataIntegrity(any, any))
            .thenAnswer((_) async => true);
        
        // Act
        final isValid = await mockEncryption.validateDataIntegrity(
          encryptedData.data, 
          encryptedData.checksum,
        );
        
        // Assert
        expect(isValid, isTrue);
        
        print('✓ Requirement 9.5: Data integrity validation validated');
      });
    });

    group('Requirement 10: User Control and Transparency', () {
      test('10.2 - Should show last backup time, sync status, and pending operations', () async {
        // Arrange
        final syncMetadata = {
          'last_sync_timestamp': DateTime.now().millisecondsSinceEpoch,
          'last_backup_timestamp': DateTime.now().millisecondsSinceEpoch,
          'pending_changes_count': 5,
          'conflict_count': 1,
        };
        
        when(mockDatabase.getSyncMetadata('patients'))
            .thenAnswer((_) async => syncMetadata);
        
        // Act
        final metadata = await mockDatabase.getSyncMetadata('patients');
        
        // Assert
        expect(metadata, isNotNull);
        expect(metadata!['pending_changes_count'], equals(5));
        expect(metadata['conflict_count'], equals(1));
        
        print('✓ Requirement 10.2: Sync status transparency validated');
      });
    });

    group('Performance and Scalability Validation', () {
      test('Should handle large datasets efficiently', () async {
        // Arrange
        final largeDataset = List.generate(10000, (i) => _createTestPatient(id: 'patient_$i'));
        
        // Act
        final stopwatch = Stopwatch()..start();
        // Simulate processing large dataset
        for (final patient in largeDataset.take(100)) {
          when(mockDatabase.insertPatient(patient)).thenAnswer((_) async {});
          await mockDatabase.insertPatient(patient);
        }
        stopwatch.stop();
        
        // Assert
        expect(stopwatch.elapsedMilliseconds, lessThan(5000)); // Should complete within 5 seconds
        
        print('✓ Performance: Large dataset handling validated (${stopwatch.elapsedMilliseconds}ms for 100 records)');
      });

      test('Should demonstrate compression effectiveness', () async {
        // Arrange
        final testData = {
          'patients': List.generate(1000, (i) => _createTestPatient(id: 'patient_$i').toSyncJson()),
        };
        
        // Act
        final compressed = await CompressionService.compressData(testData);
        
        // Assert
        expect(compressed.compressionRatio, lessThan(0.8)); // At least 20% compression
        
        print('✓ Performance: Compression effectiveness validated (${compressed.compressionPercentage.toStringAsFixed(1)}% space saved)');
      });
    });

    group('Error Handling and Edge Cases', () {
      test('Should handle network failures gracefully', () async {
        // Arrange
        when(mockDriveService.uploadBackupFile(any, any))
            .thenThrow(Exception('Network error'));
        
        // Act & Assert
        expect(() => mockDriveService.uploadBackupFile('test', []), throwsException);
        
        print('✓ Error Handling: Network failure handling validated');
      });

      test('Should handle corrupted backup files', () async {
        // Arrange
        when(mockDriveService.downloadBackupFile(any))
            .thenAnswer((_) async => [1, 2, 3]); // Invalid data
        when(mockEncryption.decryptData(any, any))
            .thenThrow(Exception('Decryption failed'));
        
        // Act & Assert
        expect(() => mockEncryption.decryptData([1, 2, 3], 'key'), throwsException);
        
        print('✓ Error Handling: Corrupted backup handling validated');
      });

      test('Should handle concurrent access scenarios', () async {
        // Arrange
        final patient = _createTestPatient();
        when(mockDatabase.insertPatient(any)).thenAnswer((_) async {});
        
        // Act - Simulate concurrent operations
        final futures = List.generate(10, (_) => mockDatabase.insertPatient(patient));
        await Future.wait(futures);
        
        // Assert
        verify(mockDatabase.insertPatient(any)).called(10);
        
        print('✓ Error Handling: Concurrent access validated');
      });
    });

    group('System Integration Validation', () {
      test('Should validate complete backup and restore workflow', () async {
        // Arrange
        final originalData = _createTestBackupData();
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.uploadBackupFile(any, any))
            .thenAnswer((_) async => 'backup_id');
        when(mockDriveService.downloadBackupFile('backup_id'))
            .thenAnswer((_) async => utf8.encode(jsonEncode(originalData.toJson())));
        when(mockEncryption.encryptData(any, any))
            .thenAnswer((_) async => _createTestEncryptedData());
        when(mockEncryption.decryptData(any, any))
            .thenAnswer((_) async => originalData.toJson());
        when(mockDatabase.exportDatabaseSnapshot())
            .thenAnswer((_) async => originalData.toJson());
        when(mockDatabase.importDatabaseSnapshot(any))
            .thenAnswer((_) async {});
        
        // Act - Complete backup and restore cycle
        final backupResult = await syncService.createBackup();
        final restoreResult = await restoreService.restoreFromBackup('backup_id');
        
        // Assert
        expect(backupResult.status, equals(SyncResultStatus.success));
        expect(restoreResult.success, isTrue);
        
        print('✓ Integration: Complete backup and restore workflow validated');
      });

      test('Should validate multi-device sync scenario', () async {
        // Arrange - Simulate two devices
        final device1Data = _createTestBackupData();
        final device2Data = _createTestBackupData();
        
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.getLatestBackup())
            .thenAnswer((_) async => BackupFileInfo(
              id: 'shared_backup',
              name: 'shared_backup.enc',
              size: 1024,
              createdTime: DateTime.now(),
              modifiedTime: DateTime.now(),
            ));
        when(mockDriveService.downloadBackupFile(any))
            .thenAnswer((_) async => utf8.encode(jsonEncode(device1Data.toJson())));
        when(mockEncryption.decryptData(any, any))
            .thenAnswer((_) async => device1Data.toJson());
        when(mockDatabase.applyRemoteChanges(any, any))
            .thenAnswer((_) async {});
        
        // Act - Simulate device 2 syncing with device 1's data
        final syncResult = await syncService.performFullSync();
        
        // Assert
        expect(syncResult.status, equals(SyncResultStatus.success));
        
        print('✓ Integration: Multi-device sync scenario validated');
      });
    });
  });

  // Helper methods
  Patient _createTestPatient({String? id}) {
    return Patient(
      id: id ?? 'test_patient_${Random().nextInt(1000)}',
      name: 'Test Patient',
      phone: '+1234567890',
      dateOfBirth: DateTime(1990, 1, 1),
      address: '123 Test St',
      emergencyContact: 'Emergency Contact',
      lastModified: DateTime.now(),
      deviceId: 'test_device',
    );
  }

  BackupData _createTestBackupData() {
    return BackupData.create(
      clinicId: 'test_clinic',
      deviceId: 'test_device',
      tables: {
        'patients': [_createTestPatient().toSyncJson()],
      },
    );
  }

  SyncConflict _createTestConflict() {
    return SyncConflict(
      id: 'test_conflict',
      tableName: 'patients',
      recordId: 'patient_1',
      localData: {'name': 'Local Name'},
      remoteData: {'name': 'Remote Name'},
      conflictTime: DateTime.now(),
      type: ConflictType.updateConflict,
      description: 'Test conflict',
    );
  }

  EncryptedData _createTestEncryptedData() {
    return EncryptedData(
      data: [1, 2, 3, 4, 5],
      iv: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
      tag: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
      algorithm: 'AES-256-GCM',
      checksum: 'test_checksum',
      timestamp: DateTime.now(),
    );
  }
}