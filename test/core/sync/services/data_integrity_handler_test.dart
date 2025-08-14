import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';

import '../../../../lib/core/sync/models/sync_exceptions.dart';
import '../../../../lib/core/sync/models/sync_models.dart';
import '../../../../lib/core/sync/services/data_integrity_handler.dart';
import '../../../../lib/core/cloud/services/google_drive_service.dart';
import '../../../../lib/core/encryption/services/encryption_service.dart';
import '../../../../lib/core/cloud/models/drive_file.dart';

import 'data_integrity_handler_test.mocks.dart';

@GenerateMocks([GoogleDriveService, EncryptionService])
void main() {
  group('DataIntegrityHandler', () {
    late DataIntegrityHandler handler;
    late MockGoogleDriveService mockDriveService;
    late MockEncryptionService mockEncryptionService;

    setUp(() {
      mockDriveService = MockGoogleDriveService();
      mockEncryptionService = MockEncryptionService();
      handler = DataIntegrityHandler(mockDriveService, mockEncryptionService);
    });

    group('validateDataIntegrity', () {
      test('should return true for valid data with correct checksum', () async {
        final data = {
          'clinic_id': 'test_clinic',
          'timestamp': '2024-01-15T10:00:00.000Z',
          'version': 1,
          'tables': {'patients': []},
          'checksum': 'valid_checksum',
        };

        // Mock the checksum calculation to return the expected value
        final dataWithoutChecksum = Map<String, dynamic>.from(data);
        dataWithoutChecksum.remove('checksum');
        
        final result = await handler.validateDataIntegrity(data);
        
        // Since we can't easily mock the internal checksum calculation,
        // we'll test with a real checksum
        final realData = {
          'clinic_id': 'test_clinic',
          'timestamp': '2024-01-15T10:00:00.000Z',
          'version': 1,
          'tables': {'patients': []},
        };
        final realChecksum = BackupData.generateChecksum(realData);
        realData['checksum'] = realChecksum;
        
        final realResult = await handler.validateDataIntegrity(realData);
        expect(realResult, true);
      });

      test('should return false for data with incorrect checksum', () async {
        final data = {
          'clinic_id': 'test_clinic',
          'timestamp': '2024-01-15T10:00:00.000Z',
          'version': 1,
          'tables': {'patients': []},
          'checksum': 'invalid_checksum',
        };

        final result = await handler.validateDataIntegrity(data);
        expect(result, false);
      });

      test('should throw DataIntegrityException for missing checksum', () async {
        final data = {
          'clinic_id': 'test_clinic',
          'timestamp': '2024-01-15T10:00:00.000Z',
          'version': 1,
          'tables': {'patients': []},
        };

        expect(
          () => handler.validateDataIntegrity(data),
          throwsA(isA<DataIntegrityException>()),
        );
      });
    });

    group('handleCorruptedBackup', () {
      test('should recover backup if current file is valid after retry', () async {
        final backupData = Uint8List.fromList([1, 2, 3, 4]);
        final decryptedData = {
          'clinic_id': 'test_clinic',
          'timestamp': '2024-01-15T10:00:00.000Z',
          'version': 1,
          'tables': {'patients': [{'id': '1', 'name': 'John'}]},
        };
        final checksum = BackupData.generateChecksum(decryptedData);
        decryptedData['checksum'] = checksum;

        when(mockDriveService.downloadBackupFile('backup_id'))
            .thenAnswer((_) async => backupData);
        when(mockEncryptionService.decryptBackupData(backupData, 'test_clinic'))
            .thenAnswer((_) async => decryptedData);

        final result = await handler.handleCorruptedBackup('backup_id', 'test_clinic');

        expect(result.success, true);
        expect(result.restoredRecords, 1);
        expect(result.message, 'Backup recovered successfully');
      });

      test('should try previous backups if current is corrupted', () async {
        final corruptedData = Uint8List.fromList([1, 2, 3, 4]);
        final validBackupData = Uint8List.fromList([5, 6, 7, 8]);
        final validDecryptedData = {
          'clinic_id': 'test_clinic',
          'timestamp': '2024-01-15T10:00:00.000Z',
          'version': 1,
          'tables': {'patients': [{'id': '1', 'name': 'John'}]},
        };
        final checksum = BackupData.generateChecksum(validDecryptedData);
        validDecryptedData['checksum'] = checksum;

        final backupFiles = [
          DriveFile(
            id: 'backup_1',
            name: 'backup_1.enc',
            createdTime: DateTime.now(),
          ),
          DriveFile(
            id: 'backup_2',
            name: 'backup_2.enc',
            createdTime: DateTime.now().subtract(const Duration(days: 1)),
          ),
        ];

        when(mockDriveService.downloadBackupFile('backup_1'))
            .thenAnswer((_) async => corruptedData);
        when(mockEncryptionService.decryptBackupData(corruptedData, 'test_clinic'))
            .thenThrow(Exception('Decryption failed'));
        
        when(mockDriveService.listBackupFiles())
            .thenAnswer((_) async => backupFiles);
        when(mockDriveService.downloadBackupFile('backup_2'))
            .thenAnswer((_) async => validBackupData);
        when(mockEncryptionService.decryptBackupData(validBackupData, 'test_clinic'))
            .thenAnswer((_) async => validDecryptedData);

        final result = await handler.handleCorruptedBackup('backup_1', 'test_clinic');

        expect(result.success, true);
        expect(result.message, contains('backup_2.enc'));
        verify(mockDriveService.listBackupFiles()).called(1);
        verify(mockDriveService.downloadBackupFile('backup_2')).called(1);
      });

      test('should return error if all backups are corrupted', () async {
        final corruptedData = Uint8List.fromList([1, 2, 3, 4]);
        final backupFiles = [
          DriveFile(
            id: 'backup_1',
            name: 'backup_1.enc',
            createdTime: DateTime.now(),
          ),
          DriveFile(
            id: 'backup_2',
            name: 'backup_2.enc',
            createdTime: DateTime.now().subtract(const Duration(days: 1)),
          ),
        ];

        when(mockDriveService.downloadBackupFile(any))
            .thenAnswer((_) async => corruptedData);
        when(mockEncryptionService.decryptBackupData(any, any))
            .thenThrow(Exception('Decryption failed'));
        when(mockDriveService.listBackupFiles())
            .thenAnswer((_) async => backupFiles);

        final result = await handler.handleCorruptedBackup('backup_1', 'test_clinic');

        expect(result.success, false);
        expect(result.error, isA<DataIntegrityException>());
        final error = result.error as DataIntegrityException;
        expect(error.type, DataIntegrityErrorType.corruptedData);
        expect(error.message, 'All available backups are corrupted');
      });
    });

    group('handleVersionMismatch', () {
      test('should handle local version newer than remote', () async {
        final localData = {'version': 2};
        final remoteData = {'version': 1};

        final result = await handler.handleVersionMismatch(localData, remoteData);

        expect(result.status, SyncResultStatus.success);
        expect(result.errorMessage, 'Local version is newer, will upload changes');
      });

      test('should handle compatible version migration', () async {
        final localData = {'version': 1};
        final remoteData = {'version': 2};

        final result = await handler.handleVersionMismatch(localData, remoteData);

        expect(result.status, SyncResultStatus.success);
        expect(result.errorMessage, 'Version migration available');
      });

      test('should handle incompatible version migration', () async {
        final localData = {'version': 1};
        final remoteData = {'version': 5}; // Unsupported migration

        final result = await handler.handleVersionMismatch(localData, remoteData);

        expect(result.status, SyncResultStatus.failure);
        expect(result.error, isA<DataIntegrityException>());
        final error = result.error as DataIntegrityException;
        expect(error.type, DataIntegrityErrorType.versionMismatch);
      });

      test('should handle matching versions', () async {
        final localData = {'version': 1};
        final remoteData = {'version': 1};

        final result = await handler.handleVersionMismatch(localData, remoteData);

        expect(result.status, SyncResultStatus.success);
        expect(result.errorMessage, 'Versions match');
      });
    });

    group('handleEncryptionFailure', () {
      test('should handle invalid key error during encryption', () async {
        final error = Exception('Invalid key provided');

        final result = await handler.handleEncryptionFailure(error, 'encrypt');

        expect(result.status, SyncResultStatus.failure);
        expect(result.metadata?['requires_reauth'], true);
        expect(result.error, isA<DataIntegrityException>());
        final integrityError = result.error as DataIntegrityException;
        expect(integrityError.type, DataIntegrityErrorType.encryptionFailed);
      });

      test('should handle corrupted data error during decryption', () async {
        final error = Exception('Corrupted data detected');

        final result = await handler.handleEncryptionFailure(error, 'decrypt');

        expect(result.status, SyncResultStatus.failure);
        expect(result.error, isA<DataIntegrityException>());
        final integrityError = result.error as DataIntegrityException;
        expect(integrityError.type, DataIntegrityErrorType.decryptionFailed);
      });

      test('should handle authentication failed error', () async {
        final error = Exception('Authentication failed during encryption');

        final result = await handler.handleEncryptionFailure(error, 'encrypt');

        expect(result.status, SyncResultStatus.failure);
        expect(result.metadata?['requires_reauth'], true);
      });

      test('should handle generic encryption error', () async {
        final error = Exception('Unknown encryption error');

        final result = await handler.handleEncryptionFailure(error, 'encrypt');

        expect(result.status, SyncResultStatus.failure);
        expect(result.error, isA<DataIntegrityException>());
        final integrityError = result.error as DataIntegrityException;
        expect(integrityError.type, DataIntegrityErrorType.encryptionFailed);
        expect(integrityError.message, contains('Unknown encryption error'));
      });
    });

    group('repairCorruptedData', () {
      test('should return repair result with counts', () async {
        final corruptedRecordIds = ['record1', 'record2', 'record3'];

        final result = await handler.repairCorruptedData('patients', corruptedRecordIds);

        expect(result.repairedCount + result.unrepairedCount, corruptedRecordIds.length);
        expect(result.repairedRecords.length, result.repairedCount);
        expect(result.unrepairedRecords.length, result.unrepairedCount);
      });

      test('should handle repair failure', () async {
        final corruptedRecordIds = ['record1'];

        expect(
          () => handler.repairCorruptedData('invalid_table', corruptedRecordIds),
          throwsA(isA<DataIntegrityException>()),
        );
      });
    });

    group('quarantineCorruptedRecords', () {
      test('should quarantine records without throwing', () async {
        final recordIds = ['record1', 'record2'];

        // Should not throw
        await handler.quarantineCorruptedRecords('patients', recordIds);
      });
    });
  });
}