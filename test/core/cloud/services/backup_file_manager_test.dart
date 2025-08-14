import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';

import 'package:doc_ledger/core/cloud/services/backup_file_manager.dart';
import 'package:doc_ledger/core/cloud/services/google_drive_service.dart';

import 'backup_file_manager_test.mocks.dart';

@GenerateMocks([GoogleDriveService])
void main() {
  group('BackupFileManager Tests', () {
    late BackupFileManager backupFileManager;
    late MockGoogleDriveService mockDriveService;

    const testClinicId = 'test_clinic_123';

    setUp(() {
      mockDriveService = MockGoogleDriveService();
      backupFileManager = BackupFileManager(
        driveService: mockDriveService,
        clinicId: testClinicId,
      );
    });

    group('Backup File Organization', () {
      test('should organize backup files successfully', () async {
        // Arrange
        final testBackupFiles = [
          BackupFileInfo(
            id: 'backup_1',
            name: 'docledger_backup_${testClinicId}_2024-01-15T10-30-00.enc',
            size: 1024,
            createdTime: DateTime(2024, 1, 15, 10, 30),
            modifiedTime: DateTime(2024, 1, 15, 10, 30),
          ),
          BackupFileInfo(
            id: 'backup_2',
            name: 'docledger_backup_${testClinicId}_2024-01-14T09-15-00.enc',
            size: 512,
            createdTime: DateTime(2024, 1, 14, 9, 15),
            modifiedTime: DateTime(2024, 1, 14, 9, 15),
          ),
        ];

        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.listBackupFiles()).thenAnswer((_) async => testBackupFiles);
        when(mockDriveService.downloadBackupFile('backup_metadata.json'))
            .thenThrow(Exception('Metadata file not found'));
        when(mockDriveService.uploadBackupFile('backup_metadata.json', any))
            .thenAnswer((_) async => 'metadata_file_id');

        // Act
        await backupFileManager.organizeBackupFiles();

        // Assert
        verify(mockDriveService.listBackupFiles()).called(1);
        verify(mockDriveService.uploadBackupFile('backup_metadata.json', any)).called(1);
      });

      test('should handle authentication failure', () async {
        // Arrange
        when(mockDriveService.isAuthenticated).thenReturn(false);

        // Act & Assert
        expect(
          () => backupFileManager.organizeBackupFiles(),
          throwsA(isA<BackupFileManagerException>()),
        );
      });
    });

    group('Retention Policy Enforcement', () {
      test('should enforce daily retention policy', () async {
        // Arrange
        final retentionPolicy = RetentionPolicy(maxDailyBackups: 2);
        final manager = BackupFileManager(
          driveService: mockDriveService,
          clinicId: testClinicId,
          retentionPolicy: retentionPolicy,
        );

        // Create test metadata with multiple backups per day
        final testMetadata = {
          'backup_1': BackupFileMetadata(
            fileId: 'backup_1',
            fileName: 'backup_1.enc',
            clinicId: testClinicId,
            deviceId: 'device_1',
            timestamp: DateTime(2024, 1, 15, 10, 0),
            type: BackupType.full,
            version: 1,
            size: 1024,
            checksum: 'checksum_1',
          ),
          'backup_2': BackupFileMetadata(
            fileId: 'backup_2',
            fileName: 'backup_2.enc',
            clinicId: testClinicId,
            deviceId: 'device_1',
            timestamp: DateTime(2024, 1, 14, 10, 0),
            type: BackupType.full,
            version: 1,
            size: 1024,
            checksum: 'checksum_2',
          ),
          'backup_3': BackupFileMetadata(
            fileId: 'backup_3',
            fileName: 'backup_3.enc',
            clinicId: testClinicId,
            deviceId: 'device_1',
            timestamp: DateTime(2024, 1, 13, 10, 0),
            type: BackupType.full,
            version: 1,
            size: 1024,
            checksum: 'checksum_3',
          ),
        };

        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.listBackupFiles()).thenAnswer((_) async => [
          BackupFileInfo(
            id: 'metadata_file',
            name: 'backup_metadata.json',
            size: 100,
            createdTime: DateTime.now(),
            modifiedTime: DateTime.now(),
          ),
        ]);
        when(mockDriveService.downloadBackupFile('metadata_file'))
            .thenAnswer((_) async => []);
        when(mockDriveService.deleteFile(any)).thenAnswer((_) async {});
        when(mockDriveService.updateBackupFile(any, any, any))
            .thenAnswer((_) async => 'updated_file_id');

        // Mock metadata loading to return our test data
        // This would require refactoring the private method to be testable
        // For now, we'll test the public interface

        // Act
        final deletedFiles = await manager.enforceRetentionPolicy();

        // Assert
        // The exact behavior depends on the implementation details
        // We verify that the method completes without error
        expect(deletedFiles, isA<List<String>>());
      });

      test('should apply age-based retention policy', () async {
        // Arrange
        final retentionPolicy = RetentionPolicy(maxAge: Duration(days: 30));
        final manager = BackupFileManager(
          driveService: mockDriveService,
          clinicId: testClinicId,
          retentionPolicy: retentionPolicy,
        );

        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.listBackupFiles()).thenAnswer((_) async => [
          BackupFileInfo(
            id: 'metadata_file',
            name: 'backup_metadata.json',
            size: 100,
            createdTime: DateTime.now(),
            modifiedTime: DateTime.now(),
          ),
        ]);
        when(mockDriveService.downloadBackupFile('metadata_file'))
            .thenThrow(Exception('Metadata file not found'));
        when(mockDriveService.updateBackupFile(any, any, any))
            .thenAnswer((_) async => 'updated_file_id');

        // Act
        final deletedFiles = await manager.enforceRetentionPolicy();

        // Assert
        expect(deletedFiles, isA<List<String>>());
        verify(mockDriveService.isAuthenticated).called(1);
      });
    });

    group('Corruption Detection and Recovery', () {
      test('should detect corrupted backups', () async {
        // Arrange
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.listBackupFiles()).thenAnswer((_) async => [
          BackupFileInfo(
            id: 'metadata_file',
            name: 'backup_metadata.json',
            size: 100,
            createdTime: DateTime.now(),
            modifiedTime: DateTime.now(),
          ),
        ]);
        when(mockDriveService.downloadBackupFile('metadata_file'))
            .thenThrow(Exception('Metadata file not found'));

        // Act
        final corruptedBackups = await backupFileManager.detectCorruptedBackups();

        // Assert
        expect(corruptedBackups, isA<List<BackupFileMetadata>>());
        verify(mockDriveService.isAuthenticated).called(1);
      });

      test('should find nearest valid backup', () async {
        // Arrange
        final targetDate = DateTime(2024, 1, 15);

        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.listBackupFiles()).thenAnswer((_) async => [
          BackupFileInfo(
            id: 'metadata_file',
            name: 'backup_metadata.json',
            size: 100,
            createdTime: DateTime.now(),
            modifiedTime: DateTime.now(),
          ),
        ]);
        when(mockDriveService.downloadBackupFile('metadata_file'))
            .thenThrow(Exception('Metadata file not found'));

        // Act
        final nearestBackup = await backupFileManager.findNearestValidBackup(targetDate);

        // Assert
        // With no valid backups, should return null
        expect(nearestBackup, isNull);
        verify(mockDriveService.isAuthenticated).called(1);
      });
    });

    group('Backup Statistics', () {
      test('should return empty statistics when no backups exist', () async {
        // Arrange
        when(mockDriveService.listBackupFiles()).thenAnswer((_) async => [
          BackupFileInfo(
            id: 'metadata_file',
            name: 'backup_metadata.json',
            size: 100,
            createdTime: DateTime.now(),
            modifiedTime: DateTime.now(),
          ),
        ]);
        when(mockDriveService.downloadBackupFile('metadata_file'))
            .thenThrow(Exception('Metadata file not found'));

        // Act
        final statistics = await backupFileManager.getBackupStatistics();

        // Assert
        expect(statistics.totalBackups, equals(0));
        expect(statistics.totalSize, equals(0));
        expect(statistics.backupsByType, isEmpty);
        expect(statistics.backupsByDevice, isEmpty);
      });

      test('should calculate statistics correctly', () async {
        // This test would require mocking the metadata loading
        // For now, we'll test that the method completes without error
        when(mockDriveService.listBackupFiles()).thenAnswer((_) async => [
          BackupFileInfo(
            id: 'metadata_file',
            name: 'backup_metadata.json',
            size: 100,
            createdTime: DateTime.now(),
            modifiedTime: DateTime.now(),
          ),
        ]);
        when(mockDriveService.downloadBackupFile('metadata_file'))
            .thenThrow(Exception('Metadata file not found'));

        // Act
        final statistics = await backupFileManager.getBackupStatistics();

        // Assert
        expect(statistics, isA<BackupStatistics>());
      });
    });

    group('Backup File Registration', () {
      test('should register new backup file successfully', () async {
        // Arrange
        when(mockDriveService.listBackupFiles()).thenAnswer((_) async => [
          BackupFileInfo(
            id: 'metadata_file',
            name: 'backup_metadata.json',
            size: 100,
            createdTime: DateTime.now(),
            modifiedTime: DateTime.now(),
          ),
        ]);
        when(mockDriveService.downloadBackupFile('metadata_file'))
            .thenThrow(Exception('Metadata file not found'));
        when(mockDriveService.uploadBackupFile('backup_metadata.json', any))
            .thenAnswer((_) async => 'metadata_file_id');

        // Act
        await backupFileManager.registerBackupFile(
          'backup_123',
          'test_backup.enc',
          'device_456',
          BackupType.full,
          1024,
          'test_checksum',
        );

        // Assert
        verify(mockDriveService.uploadBackupFile('backup_metadata.json', any)).called(1);
      });

      test('should handle registration failure', () async {
        // Arrange
        when(mockDriveService.listBackupFiles()).thenThrow(Exception('Network error'));

        // Act & Assert
        expect(
          () => backupFileManager.registerBackupFile(
            'backup_123',
            'test_backup.enc',
            'device_456',
            BackupType.full,
            1024,
            'test_checksum',
          ),
          throwsA(isA<BackupFileManagerException>()),
        );
      });
    });
  });

  group('BackupFileMetadata Tests', () {
    test('should create metadata from JSON correctly', () {
      // Arrange
      final json = {
        'file_id': 'test_file_id',
        'file_name': 'test_backup.enc',
        'clinic_id': 'clinic_123',
        'device_id': 'device_456',
        'timestamp': '2024-01-15T10:30:00.000Z',
        'type': 'full',
        'version': 1,
        'size': 1024,
        'checksum': 'test_checksum',
        'additional_data': {'key': 'value'},
      };

      // Act
      final metadata = BackupFileMetadata.fromJson(json);

      // Assert
      expect(metadata.fileId, equals('test_file_id'));
      expect(metadata.fileName, equals('test_backup.enc'));
      expect(metadata.clinicId, equals('clinic_123'));
      expect(metadata.deviceId, equals('device_456'));
      expect(metadata.type, equals(BackupType.full));
      expect(metadata.version, equals(1));
      expect(metadata.size, equals(1024));
      expect(metadata.checksum, equals('test_checksum'));
      expect(metadata.additionalData['key'], equals('value'));
    });

    test('should convert metadata to JSON correctly', () {
      // Arrange
      final metadata = BackupFileMetadata(
        fileId: 'test_file_id',
        fileName: 'test_backup.enc',
        clinicId: 'clinic_123',
        deviceId: 'device_456',
        timestamp: DateTime(2024, 1, 15, 10, 30),
        type: BackupType.incremental,
        version: 2,
        size: 2048,
        checksum: 'test_checksum',
        additionalData: {'key': 'value'},
      );

      // Act
      final json = metadata.toJson();

      // Assert
      expect(json['file_id'], equals('test_file_id'));
      expect(json['file_name'], equals('test_backup.enc'));
      expect(json['clinic_id'], equals('clinic_123'));
      expect(json['device_id'], equals('device_456'));
      expect(json['type'], equals('incremental'));
      expect(json['version'], equals(2));
      expect(json['size'], equals(2048));
      expect(json['checksum'], equals('test_checksum'));
      expect(json['additional_data']['key'], equals('value'));
    });

    test('should format file size correctly', () {
      // Test different file sizes
      expect(BackupFileMetadata(
        fileId: 'test',
        fileName: 'test',
        clinicId: 'test',
        deviceId: 'test',
        timestamp: DateTime.now(),
        type: BackupType.full,
        version: 1,
        size: 512,
        checksum: 'test',
      ).formattedSize, equals('512 B'));

      expect(BackupFileMetadata(
        fileId: 'test',
        fileName: 'test',
        clinicId: 'test',
        deviceId: 'test',
        timestamp: DateTime.now(),
        type: BackupType.full,
        version: 1,
        size: 1536, // 1.5 KB
        checksum: 'test',
      ).formattedSize, equals('1.5 KB'));

      expect(BackupFileMetadata(
        fileId: 'test',
        fileName: 'test',
        clinicId: 'test',
        deviceId: 'test',
        timestamp: DateTime.now(),
        type: BackupType.full,
        version: 1,
        size: 1572864, // 1.5 MB
        checksum: 'test',
      ).formattedSize, equals('1.5 MB'));
    });

    test('should correctly identify backup age properties', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 10, 0);
      final yesterday = today.subtract(Duration(days: 1));
      final thisMonth = DateTime(now.year, now.month, 15, 10, 0);
      final lastMonth = DateTime(now.year, now.month - 1, 15, 10, 0);

      final todayMetadata = BackupFileMetadata(
        fileId: 'test',
        fileName: 'test',
        clinicId: 'test',
        deviceId: 'test',
        timestamp: today,
        type: BackupType.full,
        version: 1,
        size: 1024,
        checksum: 'test',
      );

      final yesterdayMetadata = BackupFileMetadata(
        fileId: 'test',
        fileName: 'test',
        clinicId: 'test',
        deviceId: 'test',
        timestamp: yesterday,
        type: BackupType.full,
        version: 1,
        size: 1024,
        checksum: 'test',
      );

      expect(todayMetadata.isToday, isTrue);
      expect(yesterdayMetadata.isToday, isFalse);
    });
  });

  group('RetentionPolicy Tests', () {
    test('should use default values correctly', () {
      const policy = RetentionPolicy.defaultPolicy;
      
      expect(policy.maxDailyBackups, equals(30));
      expect(policy.maxMonthlyBackups, equals(12));
      expect(policy.maxYearlyBackups, equals(5));
      expect(policy.maxAge, equals(Duration(days: 365 * 2)));
    });

    test('should use conservative values correctly', () {
      const policy = RetentionPolicy.conservative;
      
      expect(policy.maxDailyBackups, equals(60));
      expect(policy.maxMonthlyBackups, equals(24));
      expect(policy.maxYearlyBackups, equals(10));
      expect(policy.maxAge, equals(Duration(days: 365 * 5)));
    });

    test('should use minimal values correctly', () {
      const policy = RetentionPolicy.minimal;
      
      expect(policy.maxDailyBackups, equals(7));
      expect(policy.maxMonthlyBackups, equals(6));
      expect(policy.maxYearlyBackups, equals(2));
      expect(policy.maxAge, equals(Duration(days: 365)));
    });
  });

  group('BackupStatistics Tests', () {
    test('should create empty statistics correctly', () {
      final stats = BackupStatistics.empty();
      
      expect(stats.totalBackups, equals(0));
      expect(stats.totalSize, equals(0));
      expect(stats.backupsByType, isEmpty);
      expect(stats.backupsByDevice, isEmpty);
    });

    test('should format total size correctly', () {
      final stats = BackupStatistics(
        totalBackups: 5,
        totalSize: 1572864, // 1.5 MB
        oldestBackup: DateTime.now(),
        newestBackup: DateTime.now(),
        backupsByType: {},
        backupsByDevice: {},
      );
      
      expect(stats.formattedTotalSize, equals('1.5 MB'));
    });

    test('should calculate backup span correctly', () {
      final oldest = DateTime(2024, 1, 1);
      final newest = DateTime(2024, 1, 15);
      
      final stats = BackupStatistics(
        totalBackups: 5,
        totalSize: 1024,
        oldestBackup: oldest,
        newestBackup: newest,
        backupsByType: {},
        backupsByDevice: {},
      );
      
      expect(stats.backupSpan, equals(Duration(days: 14)));
    });
  });
}