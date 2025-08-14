import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';

import 'package:doc_ledger/core/sync/services/sync_service.dart';
import 'package:doc_ledger/core/sync/models/sync_models.dart';
import 'package:doc_ledger/core/data/models/data_models.dart';
import 'package:doc_ledger/core/data/services/database_service.dart';
import 'package:doc_ledger/core/cloud/services/google_drive_service.dart';
import 'package:doc_ledger/core/encryption/services/encryption_service.dart';
import 'package:doc_ledger/core/encryption/models/encryption_models.dart';

import 'sync_service_test.mocks.dart';

@GenerateMocks([
  DatabaseService,
  GoogleDriveService,
  EncryptionService,
])
void main() {
  group('SyncService', () {
    late MockDatabaseService mockDatabase;
    late MockGoogleDriveService mockDriveService;
    late MockEncryptionService mockEncryption;
    late SyncService syncService;
    
    const testClinicId = 'test_clinic_123';
    const testDeviceId = 'test_device_456';

    setUp(() {
      mockDatabase = MockDatabaseService();
      mockDriveService = MockGoogleDriveService();
      mockEncryption = MockEncryptionService();
      
      syncService = SyncService(
        database: mockDatabase,
        driveService: mockDriveService,
        encryption: mockEncryption,
        clinicId: testClinicId,
        deviceId: testDeviceId,
      );
    });

    tearDown(() {
      syncService.dispose();
    });

    group('performFullSync', () {
      test('should complete successfully when all operations succeed', () async {
        // Arrange
        when(mockDriveService.isAuthenticated).thenReturn(true);
        
        // Mock database operations
        when(mockDatabase.getChangedRecords('patients', 0))
            .thenAnswer((_) async => [
              {'id': 'patient1', 'name': 'John Doe', 'last_modified': 1234567890}
            ]);
        when(mockDatabase.getChangedRecords('visits', 0))
            .thenAnswer((_) async => []);
        when(mockDatabase.getChangedRecords('payments', 0))
            .thenAnswer((_) async => []);
        
        when(mockDatabase.markRecordsSynced('patients', ['patient1']))
            .thenAnswer((_) async {});
        
        when(mockDatabase.detectConflicts(any, any))
            .thenAnswer((_) async => <SyncConflict>[]);
        
        when(mockDatabase.applyRemoteChanges(any, any))
            .thenAnswer((_) async {});
        
        when(mockDatabase.updateSyncMetadata(any, lastSyncTimestamp: anyNamed('lastSyncTimestamp')))
            .thenAnswer((_) async {});
        
        // Mock encryption operations
        when(mockEncryption.deriveEncryptionKey(testClinicId, testDeviceId))
            .thenAnswer((_) async => 'test_encryption_key');
        
        final mockEncryptedData = EncryptedData(
          data: [1, 2, 3, 4, 5],
          iv: [1, 2, 3],
          tag: [4, 5, 6],
          algorithm: 'AES-256-GCM',
          checksum: 'test_checksum',
          timestamp: DateTime.now(),
        );
        
        when(mockEncryption.encryptData(any, any))
            .thenAnswer((_) async => mockEncryptedData);
        
        when(mockEncryption.decryptData(any, any))
            .thenAnswer((_) async => {
              'clinic_id': testClinicId,
              'device_id': 'other_device',
              'timestamp': DateTime.now().toIso8601String(),
              'version': 1,
              'tables': {
                'patients': [
                  {'id': 'patient2', 'name': 'Jane Doe', 'last_modified': 1234567891}
                ]
              },
              'checksum': 'test_checksum',
            });
        
        // Mock Google Drive operations
        when(mockDriveService.uploadBackupFile(any, any, onProgress: anyNamed('onProgress')))
            .thenAnswer((_) async => 'file_id_123');
        
        when(mockDriveService.getLatestBackup())
            .thenAnswer((_) async => BackupFileInfo(
              id: 'backup_file_id',
              name: 'test_backup.enc',
              size: 1024,
              createdTime: DateTime.now(),
              modifiedTime: DateTime.now(),
            ));
        
        when(mockDriveService.downloadBackupFile(any, onProgress: anyNamed('onProgress')))
            .thenAnswer((_) async => [1, 2, 3, 4, 5]);

        // Act
        final result = await syncService.performFullSync();

        // Assert
        expect(result.isSuccess, isTrue);
        expect(result.syncedCounts, isNotNull);
        expect(result.duration, isNotNull);
        
        // Verify interactions
        verify(mockDatabase.getChangedRecords('patients', 0)).called(1);
        verify(mockDatabase.markRecordsSynced('patients', ['patient1'])).called(1);
        verify(mockDriveService.uploadBackupFile(any, any, onProgress: anyNamed('onProgress'))).called(1);
        verify(mockEncryption.encryptData(any, any)).called(1);
      });

      test('should fail when Google Drive is not authenticated', () async {
        // Arrange
        when(mockDriveService.isAuthenticated).thenReturn(false);

        // Act
        final result = await syncService.performFullSync();

        // Assert
        expect(result.isFailure, isTrue);
        expect(result.errorMessage, contains('Google Drive not authenticated'));
        
        // Verify no other operations were attempted
        verifyNever(mockDatabase.getChangedRecords(any, any));
        verifyNever(mockDriveService.uploadBackupFile(any, any));
      });

      test('should handle database errors gracefully', () async {
        // Arrange
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDatabase.getChangedRecords(any, any))
            .thenThrow(Exception('Database error'));

        // Act
        final result = await syncService.performFullSync();

        // Assert
        expect(result.isFailure, isTrue);
        expect(result.errorMessage, contains('Database error'));
      });

      test('should handle encryption errors gracefully', () async {
        // Arrange
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDatabase.getChangedRecords('patients', 0))
            .thenAnswer((_) async => [
              {'id': 'patient1', 'name': 'John Doe', 'last_modified': 1234567890}
            ]);
        when(mockDatabase.getChangedRecords('visits', 0))
            .thenAnswer((_) async => []);
        when(mockDatabase.getChangedRecords('payments', 0))
            .thenAnswer((_) async => []);
        when(mockDriveService.getLatestBackup())
            .thenAnswer((_) async => null);
        when(mockEncryption.deriveEncryptionKey(any, any))
            .thenThrow(EncryptionException('Encryption failed'));

        // Act
        final result = await syncService.performFullSync();

        // Assert
        expect(result.isFailure, isTrue);
        expect(result.errorMessage, contains('Encryption failed'));
      });

      test('should handle Google Drive upload errors gracefully', () async {
        // Arrange
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDatabase.getChangedRecords('patients', 0))
            .thenAnswer((_) async => [
              {'id': 'patient1', 'name': 'John Doe', 'last_modified': 1234567890}
            ]);
        when(mockDatabase.getChangedRecords('visits', 0))
            .thenAnswer((_) async => []);
        when(mockDatabase.getChangedRecords('payments', 0))
            .thenAnswer((_) async => []);
        
        when(mockEncryption.deriveEncryptionKey(any, any))
            .thenAnswer((_) async => 'test_key');
        when(mockEncryption.encryptData(any, any))
            .thenAnswer((_) async => EncryptedData(
              data: [1, 2, 3],
              iv: [1, 2, 3],
              tag: [4, 5, 6],
              algorithm: 'AES-256-GCM',
              checksum: 'test_checksum',
              timestamp: DateTime.now(),
            ));
        
        when(mockDriveService.uploadBackupFile(any, any, onProgress: anyNamed('onProgress')))
            .thenThrow(GoogleDriveException('Upload failed'));

        // Act
        final result = await syncService.performFullSync();

        // Assert
        expect(result.isFailure, isTrue);
        expect(result.errorMessage, contains('Upload failed'));
      });
    });

    group('performIncrementalSync', () {
      test('should perform full sync when no previous sync exists', () async {
        // Arrange
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDatabase.getSyncMetadata(any))
            .thenAnswer((_) async => null);
        
        // Mock full sync operations
        when(mockDatabase.getChangedRecords(any, 0))
            .thenAnswer((_) async => []);
        when(mockDatabase.detectConflicts(any, any))
            .thenAnswer((_) async => <SyncConflict>[]);
        when(mockDatabase.applyRemoteChanges(any, any))
            .thenAnswer((_) async {});
        when(mockDatabase.updateSyncMetadata(any, lastSyncTimestamp: anyNamed('lastSyncTimestamp')))
            .thenAnswer((_) async {});
        
        when(mockEncryption.deriveEncryptionKey(any, any))
            .thenAnswer((_) async => 'test_key');
        when(mockEncryption.decryptData(any, any))
            .thenAnswer((_) async => {
              'clinic_id': testClinicId,
              'device_id': testDeviceId,
              'timestamp': DateTime.now().toIso8601String(),
              'version': 1,
              'tables': <String, List<Map<String, dynamic>>>{},
              'checksum': 'test_checksum',
            });
        
        when(mockDriveService.getLatestBackup())
            .thenAnswer((_) async => null);

        // Act
        final result = await syncService.performIncrementalSync();

        // Assert
        expect(result.isSuccess, isTrue);
        
        // Verify it called full sync operations
        verify(mockDatabase.getChangedRecords(any, 0)).called(greaterThan(0));
      });

      test('should sync only changes since last sync', () async {
        // Arrange
        final lastSyncTime = DateTime.now().subtract(const Duration(hours: 1));
        
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDatabase.getSyncMetadata('patients'))
            .thenAnswer((_) async => {
              'last_sync_timestamp': lastSyncTime.millisecondsSinceEpoch,
            });
        when(mockDatabase.getSyncMetadata('visits'))
            .thenAnswer((_) async => {
              'last_sync_timestamp': lastSyncTime.millisecondsSinceEpoch,
            });
        when(mockDatabase.getSyncMetadata('payments'))
            .thenAnswer((_) async => {
              'last_sync_timestamp': lastSyncTime.millisecondsSinceEpoch,
            });
        
        when(mockDatabase.getChangedRecords('patients', lastSyncTime.millisecondsSinceEpoch))
            .thenAnswer((_) async => [
              {'id': 'patient1', 'name': 'John Doe', 'last_modified': DateTime.now().millisecondsSinceEpoch}
            ]);
        when(mockDatabase.getChangedRecords('visits', lastSyncTime.millisecondsSinceEpoch))
            .thenAnswer((_) async => []);
        when(mockDatabase.getChangedRecords('payments', lastSyncTime.millisecondsSinceEpoch))
            .thenAnswer((_) async => []);
        
        when(mockDatabase.markRecordsSynced('patients', ['patient1']))
            .thenAnswer((_) async {});
        when(mockDatabase.detectConflicts(any, any))
            .thenAnswer((_) async => <SyncConflict>[]);
        when(mockDatabase.applyRemoteChanges(any, any))
            .thenAnswer((_) async {});
        when(mockDatabase.updateSyncMetadata(any, lastSyncTimestamp: anyNamed('lastSyncTimestamp')))
            .thenAnswer((_) async {});
        
        when(mockEncryption.deriveEncryptionKey(any, any))
            .thenAnswer((_) async => 'test_key');
        when(mockEncryption.encryptData(any, any))
            .thenAnswer((_) async => EncryptedData(
              data: [1, 2, 3],
              iv: [1, 2, 3],
              tag: [4, 5, 6],
              algorithm: 'AES-256-GCM',
              checksum: 'test_checksum',
              timestamp: DateTime.now(),
            ));
        when(mockEncryption.decryptData(any, any))
            .thenAnswer((_) async => {
              'clinic_id': testClinicId,
              'device_id': testDeviceId,
              'timestamp': DateTime.now().toIso8601String(),
              'version': 1,
              'tables': <String, List<Map<String, dynamic>>>{},
              'checksum': 'test_checksum',
            });
        
        when(mockDriveService.uploadBackupFile(any, any, onProgress: anyNamed('onProgress')))
            .thenAnswer((_) async => 'file_id_123');
        when(mockDriveService.getLatestBackup())
            .thenAnswer((_) async => null);

        // Act
        final result = await syncService.performIncrementalSync();

        // Assert
        expect(result.isSuccess, isTrue);
        expect(result.metadata?['incremental'], isTrue);
        expect(result.metadata?['had_local_changes'], isTrue);
        
        // Verify it used the correct timestamp
        verify(mockDatabase.getChangedRecords('patients', lastSyncTime.millisecondsSinceEpoch)).called(2);
      });
    });

    group('createBackup', () {
      test('should create backup successfully', () async {
        // Arrange
        when(mockDriveService.isAuthenticated).thenReturn(true);
        
        final mockSnapshot = {
          'version': 1,
          'timestamp': DateTime.now().toIso8601String(),
          'device_id': testDeviceId,
          'tables': {
            'patients': [
              {'id': 'patient1', 'name': 'John Doe'}
            ],
            'visits': <Map<String, dynamic>>[],
            'payments': <Map<String, dynamic>>[],
          },
        };
        
        when(mockDatabase.exportDatabaseSnapshot())
            .thenAnswer((_) async => mockSnapshot);
        
        when(mockEncryption.getDeviceInfo())
            .thenAnswer((_) async => DeviceInfo(
              deviceId: testDeviceId,
              platform: 'Test',
              model: 'Test Model',
              osVersion: '1.0',
              registeredAt: DateTime.now(),
            ));
        
        when(mockEncryption.deriveEncryptionKey(testClinicId, testDeviceId))
            .thenAnswer((_) async => 'test_encryption_key');
        
        when(mockEncryption.encryptData(any, any))
            .thenAnswer((_) async => EncryptedData(
              data: [1, 2, 3, 4, 5],
              iv: [1, 2, 3],
              tag: [4, 5, 6],
              algorithm: 'AES-256-GCM',
              checksum: 'test_checksum',
              timestamp: DateTime.now(),
            ));
        
        when(mockDriveService.uploadBackupFile(any, any, onProgress: anyNamed('onProgress')))
            .thenAnswer((_) async => 'backup_file_id_123');
        
        when(mockDriveService.deleteOldBackups())
            .thenAnswer((_) async {});
        
        when(mockDatabase.updateSyncMetadata(any, lastBackupTimestamp: anyNamed('lastBackupTimestamp')))
            .thenAnswer((_) async {});

        // Act
        final result = await syncService.createBackup();

        // Assert
        expect(result.isSuccess, isTrue);
        expect(result.metadata?['backup_file_id'], equals('backup_file_id_123'));
        expect(result.metadata?['backup_size'], equals(5));
        
        // Verify operations were called
        verify(mockDatabase.exportDatabaseSnapshot()).called(1);
        verify(mockEncryption.encryptData(any, any)).called(1);
        verify(mockDriveService.uploadBackupFile(any, any, onProgress: anyNamed('onProgress'))).called(1);
        verify(mockDriveService.deleteOldBackups()).called(1);
      });

      test('should fail when not authenticated', () async {
        // Arrange
        when(mockDriveService.isAuthenticated).thenReturn(false);

        // Act
        final result = await syncService.createBackup();

        // Assert
        expect(result.isFailure, isTrue);
        expect(result.errorMessage, contains('Google Drive not authenticated'));
        
        // Verify no operations were attempted
        verifyNever(mockDatabase.exportDatabaseSnapshot());
        verifyNever(mockEncryption.encryptData(any, any));
        verifyNever(mockDriveService.uploadBackupFile(any, any));
      });
    });

    group('restoreFromBackup', () {
      test('should restore backup successfully', () async {
        // Arrange
        const backupFileId = 'backup_file_123';
        
        when(mockDriveService.isAuthenticated).thenReturn(true);
        
        when(mockDriveService.downloadBackupFile(backupFileId, onProgress: anyNamed('onProgress')))
            .thenAnswer((_) async => [1, 2, 3, 4, 5]);
        
        when(mockEncryption.deriveEncryptionKey(testClinicId, testDeviceId))
            .thenAnswer((_) async => 'test_encryption_key');
        
        final timestamp = DateTime.now().toIso8601String();
        final tablesData = {
          'patients': [
            {'id': 'patient1', 'name': 'John Doe'}
          ],
        };
        
        final dataToHash = {
          'clinic_id': testClinicId,
          'device_id': 'other_device',
          'timestamp': timestamp,
          'version': 1,
          'tables': tablesData,
        };
        
        final mockBackupData = {
          'clinic_id': testClinicId,
          'device_id': 'other_device',
          'timestamp': timestamp,
          'version': 1,
          'tables': tablesData,
          'checksum': BackupData.generateChecksum(dataToHash),
        };
        
        when(mockEncryption.decryptData(any, any))
            .thenAnswer((_) async => mockBackupData);
        
        when(mockDatabase.importDatabaseSnapshot(any))
            .thenAnswer((_) async {});
        
        when(mockDatabase.updateSyncMetadata(any, lastSyncTimestamp: anyNamed('lastSyncTimestamp')))
            .thenAnswer((_) async {});

        // Act
        final result = await syncService.restoreFromBackup(backupFileId);

        // Assert
        expect(result.isSuccess, isTrue);
        expect(result.metadata?['backup_file_id'], equals(backupFileId));
        expect(result.metadata?['tables_restored'], equals(1));
        
        // Verify operations were called
        verify(mockDriveService.downloadBackupFile(backupFileId, onProgress: anyNamed('onProgress'))).called(1);
        verify(mockEncryption.decryptData(any, any)).called(1);
        verify(mockDatabase.importDatabaseSnapshot(any)).called(1);
      });

      test('should fail when backup data integrity check fails', () async {
        // Arrange
        const backupFileId = 'backup_file_123';
        
        when(mockDriveService.isAuthenticated).thenReturn(true);
        
        when(mockDriveService.downloadBackupFile(backupFileId, onProgress: anyNamed('onProgress')))
            .thenAnswer((_) async => [1, 2, 3, 4, 5]);
        
        when(mockEncryption.deriveEncryptionKey(testClinicId, testDeviceId))
            .thenAnswer((_) async => 'test_encryption_key');
        
        // Mock backup data with invalid checksum
        final mockBackupData = {
          'clinic_id': testClinicId,
          'device_id': 'other_device',
          'timestamp': DateTime.now().toIso8601String(),
          'version': 1,
          'tables': {
            'patients': [
              {'id': 'patient1', 'name': 'John Doe'}
            ],
          },
          'checksum': 'invalid_checksum', // This will cause integrity check to fail
        };
        
        when(mockEncryption.decryptData(any, any))
            .thenAnswer((_) async => mockBackupData);

        // Act
        final result = await syncService.restoreFromBackup(backupFileId);

        // Assert
        expect(result.isFailure, isTrue);
        expect(result.errorMessage, contains('integrity validation failed'));
        
        // Verify database import was not called
        verifyNever(mockDatabase.importDatabaseSnapshot(any));
      });
    });

    group('resolveConflicts', () {
      test('should resolve conflicts using last-write-wins strategy', () async {
        // Arrange
        final conflict = SyncConflict(
          id: 'conflict_1',
          tableName: 'patients',
          recordId: 'patient_1',
          localData: {
            'id': 'patient_1',
            'name': 'John Doe',
            'last_modified': 1234567890,
          },
          remoteData: {
            'id': 'patient_1',
            'name': 'John Smith',
            'last_modified': 1234567891, // More recent
          },
          conflictTime: DateTime.now(),
          type: ConflictType.updateConflict,
        );
        
        when(mockDatabase.getPendingConflicts())
            .thenAnswer((_) async => [conflict]);
        
        when(mockDatabase.resolveConflict(any, any))
            .thenAnswer((_) async {});

        // Act
        final result = await syncService.resolveConflicts(ResolutionStrategy.manual);

        // Assert
        expect(result.isSuccess, isTrue);
        expect(result.metadata?['conflicts_resolved'], equals(1));
        
        // Verify the conflict was resolved with remote data (more recent timestamp)
        final capturedResolution = verify(mockDatabase.resolveConflict('conflict_1', captureAny))
            .captured.single as ConflictResolution;
        expect(capturedResolution.resolvedData['name'], equals('John Smith'));
      });

      test('should handle empty conflict list', () async {
        // Arrange
        when(mockDatabase.getPendingConflicts())
            .thenAnswer((_) async => <SyncConflict>[]);

        // Act
        final result = await syncService.resolveConflicts(ResolutionStrategy.useLocal);

        // Assert
        expect(result.isSuccess, isTrue);
        expect(result.metadata?['conflicts_resolved'], equals(0));
        
        // Verify no resolution calls were made
        verifyNever(mockDatabase.resolveConflict(any, any));
      });

      test('should use local data when strategy is useLocal', () async {
        // Arrange
        final conflict = SyncConflict(
          id: 'conflict_1',
          tableName: 'patients',
          recordId: 'patient_1',
          localData: {
            'id': 'patient_1',
            'name': 'Local Name',
            'last_modified': 1234567890,
          },
          remoteData: {
            'id': 'patient_1',
            'name': 'Remote Name',
            'last_modified': 1234567891,
          },
          conflictTime: DateTime.now(),
          type: ConflictType.updateConflict,
        );
        
        when(mockDatabase.getPendingConflicts())
            .thenAnswer((_) async => [conflict]);
        
        when(mockDatabase.resolveConflict(any, any))
            .thenAnswer((_) async {});

        // Act
        final result = await syncService.resolveConflicts(ResolutionStrategy.useLocal);

        // Assert
        expect(result.isSuccess, isTrue);
        
        // Verify the conflict was resolved with local data
        final capturedResolution = verify(mockDatabase.resolveConflict('conflict_1', captureAny))
            .captured.single as ConflictResolution;
        expect(capturedResolution.resolvedData['name'], equals('Local Name'));
        expect(capturedResolution.strategy, equals(ResolutionStrategy.useLocal));
      });

      test('should use remote data when strategy is useRemote', () async {
        // Arrange
        final conflict = SyncConflict(
          id: 'conflict_1',
          tableName: 'patients',
          recordId: 'patient_1',
          localData: {
            'id': 'patient_1',
            'name': 'Local Name',
            'last_modified': 1234567890,
          },
          remoteData: {
            'id': 'patient_1',
            'name': 'Remote Name',
            'last_modified': 1234567891,
          },
          conflictTime: DateTime.now(),
          type: ConflictType.updateConflict,
        );
        
        when(mockDatabase.getPendingConflicts())
            .thenAnswer((_) async => [conflict]);
        
        when(mockDatabase.resolveConflict(any, any))
            .thenAnswer((_) async {});

        // Act
        final result = await syncService.resolveConflicts(ResolutionStrategy.useRemote);

        // Assert
        expect(result.isSuccess, isTrue);
        
        // Verify the conflict was resolved with remote data
        final capturedResolution = verify(mockDatabase.resolveConflict('conflict_1', captureAny))
            .captured.single as ConflictResolution;
        expect(capturedResolution.resolvedData['name'], equals('Remote Name'));
        expect(capturedResolution.strategy, equals(ResolutionStrategy.useRemote));
      });

      test('should merge data when strategy is merge', () async {
        // Arrange
        final conflict = SyncConflict(
          id: 'conflict_1',
          tableName: 'patients',
          recordId: 'patient_1',
          localData: {
            'id': 'patient_1',
            'name': 'John Doe',
            'phone': '123-456-7890',
            'address': '', // Empty local address
            'last_modified': 1234567890,
          },
          remoteData: {
            'id': 'patient_1',
            'name': 'John Smith',
            'phone': '', // Empty remote phone
            'address': '123 Main St',
            'last_modified': 1234567891,
          },
          conflictTime: DateTime.now(),
          type: ConflictType.updateConflict,
        );
        
        when(mockDatabase.getPendingConflicts())
            .thenAnswer((_) async => [conflict]);
        
        when(mockDatabase.resolveConflict(any, any))
            .thenAnswer((_) async {});

        // Act
        final result = await syncService.resolveConflicts(ResolutionStrategy.merge);

        // Assert
        expect(result.isSuccess, isTrue);
        
        // Verify the conflict was resolved with merged data
        final capturedResolution = verify(mockDatabase.resolveConflict('conflict_1', captureAny))
            .captured.single as ConflictResolution;
        
        // Should keep local phone (not empty) and remote address (not empty)
        expect(capturedResolution.resolvedData['phone'], equals('123-456-7890'));
        expect(capturedResolution.resolvedData['address'], equals('123 Main St'));
        expect(capturedResolution.strategy, equals(ResolutionStrategy.merge));
      });

      test('should handle conflict resolution failures gracefully', () async {
        // Arrange
        final conflict = SyncConflict(
          id: 'conflict_1',
          tableName: 'patients',
          recordId: 'patient_1',
          localData: {'id': 'patient_1'},
          remoteData: {'id': 'patient_1'},
          conflictTime: DateTime.now(),
          type: ConflictType.updateConflict,
        );
        
        when(mockDatabase.getPendingConflicts())
            .thenAnswer((_) async => [conflict]);
        
        when(mockDatabase.resolveConflict(any, any))
            .thenThrow(Exception('Database error'));

        // Act
        final result = await syncService.resolveConflicts(ResolutionStrategy.useLocal);

        // Assert
        expect(result.isPartial, isTrue);
        expect(result.conflictIds, contains('conflict_1'));
        expect(result.errorMessage, contains('Some conflicts could not be resolved'));
      });
    });

    group('resolveConflictManually', () {
      test('should resolve conflict with user-provided data', () async {
        // Arrange
        const conflictId = 'conflict_1';
        final resolvedData = {
          'id': 'patient_1',
          'name': 'Manually Resolved Name',
          'phone': '555-0123',
        };
        const notes = 'Manually resolved by user';
        
        when(mockDatabase.resolveConflict(any, any))
            .thenAnswer((_) async {});
        
        when(mockDatabase.getPendingConflicts())
            .thenAnswer((_) async => [
              SyncConflict(
                id: conflictId,
                tableName: 'patients',
                recordId: 'patient_1',
                localData: {'id': 'patient_1', 'name': 'Local'},
                remoteData: {'id': 'patient_1', 'name': 'Remote'},
                conflictTime: DateTime.now(),
                type: ConflictType.updateConflict,
              ),
            ]);

        // Act
        final result = await syncService.resolveConflictManually(
          conflictId,
          resolvedData,
          notes: notes,
        );

        // Assert
        expect(result.isSuccess, isTrue);
        expect(result.metadata?['conflict_id'], equals(conflictId));
        expect(result.metadata?['resolution_strategy'], equals('manual'));
        
        // Verify the resolution was stored
        final capturedResolution = verify(mockDatabase.resolveConflict(conflictId, captureAny))
            .captured.single as ConflictResolution;
        expect(capturedResolution.strategy, equals(ResolutionStrategy.manual));
        expect(capturedResolution.resolvedData, equals(resolvedData));
        expect(capturedResolution.notes, equals(notes));
      });

      test('should handle manual resolution failures', () async {
        // Arrange
        const conflictId = 'conflict_1';
        final resolvedData = {'id': 'patient_1'};
        
        when(mockDatabase.resolveConflict(any, any))
            .thenThrow(Exception('Database error'));

        // Act
        final result = await syncService.resolveConflictManually(conflictId, resolvedData);

        // Assert
        expect(result.isFailure, isTrue);
        expect(result.errorMessage, contains('Manual conflict resolution failed'));
      });
    });

    group('getPendingConflicts', () {
      test('should return pending conflicts from database', () async {
        // Arrange
        final expectedConflicts = [
          SyncConflict(
            id: 'conflict_1',
            tableName: 'patients',
            recordId: 'patient_1',
            localData: {'id': 'patient_1'},
            remoteData: {'id': 'patient_1'},
            conflictTime: DateTime.now(),
            type: ConflictType.updateConflict,
          ),
        ];
        
        when(mockDatabase.getPendingConflicts())
            .thenAnswer((_) async => expectedConflicts);

        // Act
        final conflicts = await syncService.getPendingConflicts();

        // Assert
        expect(conflicts, equals(expectedConflicts));
        verify(mockDatabase.getPendingConflicts()).called(1);
      });
    });

    group('state management', () {
      test('should emit state changes during sync operations', () async {
        // Arrange
        final stateChanges = <SyncStatus>[];
        syncService.stateStream.listen((state) {
          stateChanges.add(state.status);
        });
        
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDatabase.getChangedRecords(any, any))
            .thenAnswer((_) async => []);
        when(mockDatabase.detectConflicts(any, any))
            .thenAnswer((_) async => <SyncConflict>[]);
        when(mockDatabase.applyRemoteChanges(any, any))
            .thenAnswer((_) async {});
        when(mockDatabase.updateSyncMetadata(any, lastSyncTimestamp: anyNamed('lastSyncTimestamp')))
            .thenAnswer((_) async {});
        when(mockEncryption.decryptData(any, any))
            .thenAnswer((_) async => {
              'clinic_id': testClinicId,
              'device_id': testDeviceId,
              'timestamp': DateTime.now().toIso8601String(),
              'version': 1,
              'tables': <String, List<Map<String, dynamic>>>{},
              'checksum': 'test_checksum',
            });
        when(mockDriveService.getLatestBackup())
            .thenAnswer((_) async => null);

        // Act
        await syncService.performFullSync();
        
        // Allow time for state changes to propagate
        await Future.delayed(const Duration(milliseconds: 10));

        // Assert
        expect(stateChanges, contains(SyncStatus.syncing));
        expect(stateChanges, contains(SyncStatus.idle));
      });

      test('should emit error state when sync fails', () async {
        // Arrange
        final stateChanges = <SyncStatus>[];
        syncService.stateStream.listen((state) {
          stateChanges.add(state.status);
        });
        
        when(mockDriveService.isAuthenticated).thenReturn(false);

        // Act
        await syncService.performFullSync();
        
        // Allow time for state changes to propagate
        await Future.delayed(const Duration(milliseconds: 10));

        // Assert
        expect(stateChanges, contains(SyncStatus.error));
      });
    });
  });
}