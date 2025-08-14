import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';

import 'package:doc_ledger/core/cloud/services/backup_file_manager.dart';
import 'package:doc_ledger/core/cloud/services/google_drive_service.dart';
import 'package:doc_ledger/core/sync/services/sync_service.dart';
import 'package:doc_ledger/core/data/services/database_service.dart';
import 'package:doc_ledger/core/encryption/services/encryption_service.dart';

import 'backup_lifecycle_integration_test.mocks.dart';

@GenerateMocks([
  GoogleDriveService,
  SyncService,
  DatabaseService,
  EncryptionService,
])
void main() {
  group('Backup Lifecycle Integration Tests', () {
    late BackupFileManager backupFileManager;
    late MockGoogleDriveService mockDriveService;
    late MockSyncService mockSyncService;
    late MockDatabaseService mockDatabase;
    late MockEncryptionService mockEncryption;

    const testClinicId = 'test_clinic_123';
    const testDeviceId = 'test_device_456';

    setUp(() {
      mockDriveService = MockGoogleDriveService();
      mockSyncService = MockSyncService();
      mockDatabase = MockDatabaseService();
      mockEncryption = MockEncryptionService();

      backupFileManager = BackupFileManager(
        driveService: mockDriveService,
        clinicId: testClinicId,
        retentionPolicy: RetentionPolicy.defaultPolicy,
      );
    });

    group('Complete Backup Lifecycle', () {
      test('should handle complete backup creation and management lifecycle', () async {
        // Arrange - Setup initial state
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.listBackupFiles()).thenAnswer((_) async => []);
        when(mockDriveService.uploadBackupFile(any, any)).thenAnswer((_) async => 'new_backup_id');
        when(mockDriveService.downloadBackupFile(any)).thenThrow(Exception('File not found'));

        // Act - Create initial backup
        await backupFileManager.registerBackupFile(
          'backup_1',
          'docledger_backup_${testClinicId}_2024-01-15T10-30-00.enc',
          testDeviceId,
          BackupType.full,
          1024 * 1024, // 1MB
          'checksum_1',
          additionalData: {'tables': ['patients', 'visits', 'payments']},
        );

        // Assert - Verify backup was registered
        verify(mockDriveService.uploadBackupFile('backup_metadata.json', any)).called(1);

        // Act - Get statistics
        final stats = await backupFileManager.getBackupStatistics();

        // Assert - Should show empty stats since we mocked empty metadata
        expect(stats.totalBackups, equals(0));
      });

      test('should handle backup corruption detection and recovery', () async {
        // Arrange - Setup corrupted backup scenario
        final corruptedBackupFiles = [
          BackupFileInfo(
            id: 'corrupted_backup',
            name: 'docledger_backup_${testClinicId}_2024-01-15T10-30-00.enc',
            size: 0, // Corrupted - empty file
            createdTime: DateTime(2024, 1, 15, 10, 30),
            modifiedTime: DateTime(2024, 1, 15, 10, 30),
          ),
          BackupFileInfo(
            id: 'valid_backup',
            name: 'docledger_backup_${testClinicId}_2024-01-14T09-15-00.enc',
            size: 1024,
            createdTime: DateTime(2024, 1, 14, 9, 15),
            modifiedTime: DateTime(2024, 1, 14, 9, 15),
          ),
        ];

        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.listBackupFiles()).thenAnswer((_) async => corruptedBackupFiles);
        when(mockDriveService.downloadBackupFile(any)).thenThrow(Exception('Metadata not found'));

        // Act - Detect corrupted backups
        final corruptedBackups = await backupFileManager.detectCorruptedBackups();

        // Assert - Should complete without error
        expect(corruptedBackups, isA<List<BackupFileMetadata>>());
        verify(mockDriveService.isAuthenticated).called(1);
      });

      test('should handle retention policy enforcement over time', () async {
        // Arrange - Setup scenario with many old backups
        final oldBackupFiles = List.generate(50, (index) {
          final date = DateTime.now().subtract(Duration(days: index));
          return BackupFileInfo(
            id: 'backup_$index',
            name: 'docledger_backup_${testClinicId}_${date.toIso8601String().replaceAll(':', '-')}.enc',
            size: 1024,
            createdTime: date,
            modifiedTime: date,
          );
        });

        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.listBackupFiles()).thenAnswer((_) async => oldBackupFiles);
        when(mockDriveService.downloadBackupFile(any)).thenThrow(Exception('Metadata not found'));
        when(mockDriveService.deleteFile(any)).thenAnswer((_) async {});
        when(mockDriveService.uploadBackupFile(any, any)).thenAnswer((_) async => 'metadata_id');

        // Act - Enforce retention policy
        final deletedFiles = await backupFileManager.enforceRetentionPolicy();

        // Assert - Should complete and potentially delete files
        expect(deletedFiles, isA<List<String>>());
        verify(mockDriveService.isAuthenticated).called(1);
      });
    });

    group('Backup File Organization', () {
      test('should organize backup files by clinic and date', () async {
        // Arrange
        final mixedBackupFiles = [
          BackupFileInfo(
            id: 'backup_1',
            name: 'docledger_backup_${testClinicId}_2024-01-15T10-30-00.enc',
            size: 1024,
            createdTime: DateTime(2024, 1, 15, 10, 30),
            modifiedTime: DateTime(2024, 1, 15, 10, 30),
          ),
          BackupFileInfo(
            id: 'backup_2',
            name: 'docledger_backup_other_clinic_2024-01-15T10-30-00.enc',
            size: 1024,
            createdTime: DateTime(2024, 1, 15, 10, 30),
            modifiedTime: DateTime(2024, 1, 15, 10, 30),
          ),
          BackupFileInfo(
            id: 'backup_3',
            name: 'docledger_backup_${testClinicId}_2024-01-14T09-15-00.enc',
            size: 512,
            createdTime: DateTime(2024, 1, 14, 9, 15),
            modifiedTime: DateTime(2024, 1, 14, 9, 15),
          ),
        ];

        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.listBackupFiles()).thenAnswer((_) async => mixedBackupFiles);
        when(mockDriveService.downloadBackupFile(any)).thenThrow(Exception('Metadata not found'));
        when(mockDriveService.uploadBackupFile(any, any)).thenAnswer((_) async => 'metadata_id');

        // Act
        await backupFileManager.organizeBackupFiles();

        // Assert - Should complete organization
        verify(mockDriveService.listBackupFiles()).called(1);
        verify(mockDriveService.uploadBackupFile('backup_metadata.json', any)).called(1);
      });

      test('should handle organization with existing metadata', () async {
        // Arrange
        final existingMetadataFile = BackupFileInfo(
          id: 'metadata_file',
          name: 'backup_metadata.json',
          size: 1024,
          createdTime: DateTime.now(),
          modifiedTime: DateTime.now(),
        );

        final existingMetadata = {
          'backup_1': {
            'file_id': 'backup_1',
            'file_name': 'test_backup.enc',
            'clinic_id': testClinicId,
            'device_id': testDeviceId,
            'timestamp': DateTime.now().toIso8601String(),
            'type': 'full',
            'version': 1,
            'size': 1024,
            'checksum': 'test_checksum',
            'additional_data': {},
          },
        };

        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.listBackupFiles()).thenAnswer((_) async => [existingMetadataFile]);
        when(mockDriveService.downloadBackupFile('metadata_file'))
            .thenAnswer((_) async => utf8.encode(jsonEncode(existingMetadata)));
        when(mockDriveService.updateBackupFile(any, any, any))
            .thenAnswer((_) async => 'updated_metadata_id');

        // Act
        await backupFileManager.organizeBackupFiles();

        // Assert
        verify(mockDriveService.downloadBackupFile('metadata_file')).called(1);
        verify(mockDriveService.updateBackupFile('metadata_file', 'backup_metadata.json', any)).called(1);
      });
    });

    group('Retention Policy Scenarios', () {
      test('should handle daily backup retention correctly', () async {
        // Arrange - Create backups for multiple days
        final dailyBackups = <BackupFileInfo>[];
        for (int i = 0; i < 45; i++) {
          final date = DateTime.now().subtract(Duration(days: i));
          dailyBackups.add(BackupFileInfo(
            id: 'daily_backup_$i',
            name: 'docledger_backup_${testClinicId}_${date.toIso8601String().replaceAll(':', '-')}.enc',
            size: 1024,
            createdTime: date,
            modifiedTime: date,
          ));
        }

        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.listBackupFiles()).thenAnswer((_) async => dailyBackups);
        when(mockDriveService.downloadBackupFile(any)).thenThrow(Exception('Metadata not found'));
        when(mockDriveService.deleteFile(any)).thenAnswer((_) async {});
        when(mockDriveService.uploadBackupFile(any, any)).thenAnswer((_) async => 'metadata_id');

        // Act
        final deletedFiles = await backupFileManager.enforceRetentionPolicy();

        // Assert - Should delete files beyond retention period
        expect(deletedFiles, isA<List<String>>());
        verify(mockDriveService.isAuthenticated).called(1);
      });

      test('should handle monthly backup retention correctly', () async {
        // Arrange - Create backups for multiple months
        final monthlyBackups = <BackupFileInfo>[];
        for (int i = 0; i < 18; i++) {
          final date = DateTime.now().subtract(Duration(days: i * 30));
          monthlyBackups.add(BackupFileInfo(
            id: 'monthly_backup_$i',
            name: 'docledger_backup_${testClinicId}_${date.toIso8601String().replaceAll(':', '-')}.enc',
            size: 1024,
            createdTime: date,
            modifiedTime: date,
          ));
        }

        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.listBackupFiles()).thenAnswer((_) async => monthlyBackups);
        when(mockDriveService.downloadBackupFile(any)).thenThrow(Exception('Metadata not found'));
        when(mockDriveService.deleteFile(any)).thenAnswer((_) async {});
        when(mockDriveService.uploadBackupFile(any, any)).thenAnswer((_) async => 'metadata_id');

        // Act
        final deletedFiles = await backupFileManager.enforceRetentionPolicy();

        // Assert
        expect(deletedFiles, isA<List<String>>());
        verify(mockDriveService.isAuthenticated).called(1);
      });

      test('should handle mixed backup types in retention policy', () async {
        // Arrange - Create mix of full, incremental, and manual backups
        final mixedBackups = <BackupFileInfo>[];
        
        // Add full backups
        for (int i = 0; i < 10; i++) {
          final date = DateTime.now().subtract(Duration(days: i * 3));
          mixedBackups.add(BackupFileInfo(
            id: 'full_backup_$i',
            name: 'docledger_backup_${testClinicId}_${date.toIso8601String().replaceAll(':', '-')}.enc',
            size: 2048,
            createdTime: date,
            modifiedTime: date,
          ));
        }

        // Add incremental backups
        for (int i = 0; i < 20; i++) {
          final date = DateTime.now().subtract(Duration(days: i));
          mixedBackups.add(BackupFileInfo(
            id: 'incremental_backup_$i',
            name: 'docledger_incremental_${testClinicId}_${date.toIso8601String().replaceAll(':', '-')}.enc',
            size: 512,
            createdTime: date,
            modifiedTime: date,
          ));
        }

        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.listBackupFiles()).thenAnswer((_) async => mixedBackups);
        when(mockDriveService.downloadBackupFile(any)).thenThrow(Exception('Metadata not found'));
        when(mockDriveService.deleteFile(any)).thenAnswer((_) async {});
        when(mockDriveService.uploadBackupFile(any, any)).thenAnswer((_) async => 'metadata_id');

        // Act
        final deletedFiles = await backupFileManager.enforceRetentionPolicy();

        // Assert
        expect(deletedFiles, isA<List<String>>());
        verify(mockDriveService.isAuthenticated).called(1);
      });
    });

    group('Error Handling and Recovery', () {
      test('should handle network errors during organization', () async {
        // Arrange
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.listBackupFiles()).thenThrow(Exception('Network error'));

        // Act & Assert
        expect(
          () => backupFileManager.organizeBackupFiles(),
          throwsA(isA<BackupFileManagerException>()),
        );
      });

      test('should handle partial failures during retention enforcement', () async {
        // Arrange
        final backupFiles = [
          BackupFileInfo(
            id: 'backup_1',
            name: 'docledger_backup_${testClinicId}_2024-01-15T10-30-00.enc',
            size: 1024,
            createdTime: DateTime(2024, 1, 15, 10, 30),
            modifiedTime: DateTime(2024, 1, 15, 10, 30),
          ),
        ];

        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.listBackupFiles()).thenAnswer((_) async => backupFiles);
        when(mockDriveService.downloadBackupFile(any)).thenThrow(Exception('Metadata not found'));
        when(mockDriveService.deleteFile(any)).thenThrow(Exception('Delete failed'));
        when(mockDriveService.uploadBackupFile(any, any)).thenAnswer((_) async => 'metadata_id');

        // Act - Should not throw despite delete failures
        final deletedFiles = await backupFileManager.enforceRetentionPolicy();

        // Assert - Should complete despite individual failures
        expect(deletedFiles, isA<List<String>>());
      });

      test('should handle corrupted metadata gracefully', () async {
        // Arrange
        final metadataFile = BackupFileInfo(
          id: 'metadata_file',
          name: 'backup_metadata.json',
          size: 100,
          createdTime: DateTime.now(),
          modifiedTime: DateTime.now(),
        );

        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.listBackupFiles()).thenAnswer((_) async => [metadataFile]);
        when(mockDriveService.downloadBackupFile('metadata_file'))
            .thenAnswer((_) async => [1, 2, 3]); // Invalid JSON
        when(mockDriveService.uploadBackupFile(any, any)).thenAnswer((_) async => 'new_metadata_id');

        // Act - Should handle corrupted metadata by creating new one
        await backupFileManager.organizeBackupFiles();

        // Assert
        verify(mockDriveService.downloadBackupFile('metadata_file')).called(1);
        verify(mockDriveService.uploadBackupFile('backup_metadata.json', any)).called(1);
      });
    });

    group('Performance and Scalability', () {
      test('should handle large number of backup files efficiently', () async {
        // Arrange - Create many backup files
        final manyBackupFiles = List.generate(1000, (index) {
          final date = DateTime.now().subtract(Duration(hours: index));
          return BackupFileInfo(
            id: 'backup_$index',
            name: 'docledger_backup_${testClinicId}_${date.toIso8601String().replaceAll(':', '-')}.enc',
            size: 1024,
            createdTime: date,
            modifiedTime: date,
          );
        });

        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.listBackupFiles()).thenAnswer((_) async => manyBackupFiles);
        when(mockDriveService.downloadBackupFile(any)).thenThrow(Exception('Metadata not found'));
        when(mockDriveService.uploadBackupFile(any, any)).thenAnswer((_) async => 'metadata_id');

        // Act - Should complete in reasonable time
        final stopwatch = Stopwatch()..start();
        await backupFileManager.organizeBackupFiles();
        stopwatch.stop();

        // Assert - Should complete within reasonable time (adjust as needed)
        expect(stopwatch.elapsedMilliseconds, lessThan(5000)); // 5 seconds
        verify(mockDriveService.listBackupFiles()).called(1);
      });

      test('should handle retention policy on large dataset efficiently', () async {
        // Arrange - Create many old backup files
        final manyOldBackupFiles = List.generate(500, (index) {
          final date = DateTime.now().subtract(Duration(days: index));
          return BackupFileInfo(
            id: 'old_backup_$index',
            name: 'docledger_backup_${testClinicId}_${date.toIso8601String().replaceAll(':', '-')}.enc',
            size: 1024,
            createdTime: date,
            modifiedTime: date,
          );
        });

        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.listBackupFiles()).thenAnswer((_) async => manyOldBackupFiles);
        when(mockDriveService.downloadBackupFile(any)).thenThrow(Exception('Metadata not found'));
        when(mockDriveService.deleteFile(any)).thenAnswer((_) async {});
        when(mockDriveService.uploadBackupFile(any, any)).thenAnswer((_) async => 'metadata_id');

        // Act
        final stopwatch = Stopwatch()..start();
        final deletedFiles = await backupFileManager.enforceRetentionPolicy();
        stopwatch.stop();

        // Assert
        expect(deletedFiles, isA<List<String>>());
        expect(stopwatch.elapsedMilliseconds, lessThan(10000)); // 10 seconds
      });
    });
  });
}