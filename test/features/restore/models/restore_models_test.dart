import 'package:flutter_test/flutter_test.dart';
import 'package:doc_ledger/features/restore/models/restore_models.dart';

void main() {
  group('RestoreBackupInfo Tests', () {
    late RestoreBackupInfo testBackupInfo;
    late DateTime testCreatedTime;
    late DateTime testModifiedTime;

    setUp(() {
      testCreatedTime = DateTime(2024, 1, 15, 10, 0);
      testModifiedTime = DateTime(2024, 1, 15, 11, 0);
      testBackupInfo = RestoreBackupInfo(
        id: 'backup_123',
        name: 'clinic_backup_2024_01_15.enc',
        size: 1024000,
        createdTime: testCreatedTime,
        modifiedTime: testModifiedTime,
        description: 'Full backup with all data',
        isValid: true,
        validationError: null,
      );
    });

    test('should create RestoreBackupInfo with all properties', () {
      expect(testBackupInfo.id, equals('backup_123'));
      expect(testBackupInfo.name, equals('clinic_backup_2024_01_15.enc'));
      expect(testBackupInfo.size, equals(1024000));
      expect(testBackupInfo.createdTime, equals(testCreatedTime));
      expect(testBackupInfo.modifiedTime, equals(testModifiedTime));
      expect(testBackupInfo.description, equals('Full backup with all data'));
      expect(testBackupInfo.isValid, isTrue);
      expect(testBackupInfo.validationError, isNull);
    });

    test('should format size correctly', () {
      expect(testBackupInfo.formattedSize, equals('1000.0 KB'));

      final smallBackup = testBackupInfo.copyWith(size: 512);
      expect(smallBackup.formattedSize, equals('512 B'));

      final largeBackup = testBackupInfo.copyWith(size: 1073741824);
      expect(largeBackup.formattedSize, equals('1.0 GB'));

      final megabyteBackup = testBackupInfo.copyWith(size: 2097152);
      expect(megabyteBackup.formattedSize, equals('2.0 MB'));
    });

    test('should copy with modifications', () {
      final copiedBackup = testBackupInfo.copyWith(
        name: 'new_backup.enc',
        size: 2048000,
        isValid: false,
        validationError: 'Corrupted file',
      );

      expect(copiedBackup.name, equals('new_backup.enc'));
      expect(copiedBackup.size, equals(2048000));
      expect(copiedBackup.isValid, isFalse);
      expect(copiedBackup.validationError, equals('Corrupted file'));
      
      // Other properties should remain the same
      expect(copiedBackup.id, equals(testBackupInfo.id));
      expect(copiedBackup.createdTime, equals(testBackupInfo.createdTime));
    });

    test('should implement equality correctly', () {
      final sameBackup = RestoreBackupInfo(
        id: 'backup_123',
        name: 'clinic_backup_2024_01_15.enc',
        size: 1024000,
        createdTime: testCreatedTime,
        modifiedTime: testModifiedTime,
        description: 'Full backup with all data',
        isValid: true,
        validationError: null,
      );

      expect(testBackupInfo == sameBackup, isTrue);
      expect(testBackupInfo.hashCode, equals(sameBackup.hashCode));

      final differentBackup = sameBackup.copyWith(id: 'different_backup');
      expect(testBackupInfo == differentBackup, isFalse);
    });

    test('should handle toString correctly', () {
      final stringRepresentation = testBackupInfo.toString();
      expect(stringRepresentation, contains('backup_123'));
      expect(stringRepresentation, contains('clinic_backup_2024_01_15.enc'));
      expect(stringRepresentation, contains('1000.0 KB'));
      expect(stringRepresentation, contains('valid: true'));
    });
  });

  group('RestoreState Tests', () {
    test('should create initial state correctly', () {
      final initialState = RestoreState.initial();

      expect(initialState.status, equals(RestoreStatus.notStarted));
      expect(initialState.progress, isNull);
      expect(initialState.currentOperation, isNull);
      expect(initialState.errorMessage, isNull);
      expect(initialState.availableBackups, isEmpty);
      expect(initialState.selectedBackup, isNull);
      expect(initialState.result, isNull);
    });

    test('should create selecting backup state correctly', () {
      final backups = [
        RestoreBackupInfo(
          id: 'backup_1',
          name: 'backup1.enc',
          size: 1000,
          createdTime: DateTime.now(),
          modifiedTime: DateTime.now(),
        ),
      ];

      final selectingState = RestoreState.selectingBackup(backups);

      expect(selectingState.status, equals(RestoreStatus.selectingBackup));
      expect(selectingState.availableBackups, equals(backups));
    });

    test('should create restoring state correctly', () {
      final restoringState = RestoreState.restoring(
        operation: 'Downloading backup file',
        progress: 0.5,
      );

      expect(restoringState.status, equals(RestoreStatus.downloading));
      expect(restoringState.currentOperation, equals('Downloading backup file'));
      expect(restoringState.progress, equals(0.5));
    });

    test('should create completed state correctly', () {
      final result = RestoreResult.success(
        duration: const Duration(minutes: 5),
        restoredCounts: {'patients': 10},
      );

      final completedState = RestoreState.completed(result);

      expect(completedState.status, equals(RestoreStatus.completed));
      expect(completedState.result, equals(result));
    });

    test('should create error state correctly', () {
      final errorState = RestoreState.error('Restore failed');

      expect(errorState.status, equals(RestoreStatus.error));
      expect(errorState.errorMessage, equals('Restore failed'));
    });

    test('should create cancelled state correctly', () {
      final cancelledState = RestoreState.cancelled();

      expect(cancelledState.status, equals(RestoreStatus.cancelled));
    });

    test('should check if restoration is in progress', () {
      final downloadingState = RestoreState.restoring(operation: 'Downloading');
      expect(downloadingState.isInProgress, isTrue);

      final decryptingState = RestoreState.restoring(operation: 'Decrypting');
      expect(decryptingState.isInProgress, isTrue);

      final completedState = RestoreState.completed(
        RestoreResult.success(duration: const Duration(minutes: 1)),
      );
      expect(completedState.isInProgress, isFalse);
    });

    test('should check if restoration can be cancelled', () {
      final downloadingState = RestoreState.restoring(operation: 'Downloading');
      expect(downloadingState.canCancel, isTrue);

      final completedState = RestoreState.completed(
        RestoreResult.success(duration: const Duration(minutes: 1)),
      );
      expect(completedState.canCancel, isFalse);
    });

    test('should check if backup can be selected', () {
      final backups = [
        RestoreBackupInfo(
          id: 'backup_1',
          name: 'backup1.enc',
          size: 1000,
          createdTime: DateTime.now(),
          modifiedTime: DateTime.now(),
        ),
      ];

      final selectingState = RestoreState.selectingBackup(backups);
      expect(selectingState.canSelectBackup, isTrue);

      final emptySelectingState = RestoreState.selectingBackup([]);
      expect(emptySelectingState.canSelectBackup, isFalse);

      final downloadingState = RestoreState.restoring(operation: 'Downloading');
      expect(downloadingState.canSelectBackup, isFalse);
    });

    test('should copy with modifications', () {
      final initialState = RestoreState.initial();
      final copiedState = initialState.copyWith(
        status: RestoreStatus.downloading,
        progress: 0.3,
        currentOperation: 'Downloading backup',
      );

      expect(copiedState.status, equals(RestoreStatus.downloading));
      expect(copiedState.progress, equals(0.3));
      expect(copiedState.currentOperation, equals('Downloading backup'));
      
      // Other properties should remain the same
      expect(copiedState.availableBackups, equals(initialState.availableBackups));
      expect(copiedState.selectedBackup, equals(initialState.selectedBackup));
    });
  });

  group('RestoreResult Tests', () {
    test('should create success result correctly', () {
      final successResult = RestoreResult.success(
        duration: const Duration(minutes: 5, seconds: 30),
        restoredCounts: {'patients': 50, 'visits': 100},
        metadata: {'restore_type': 'full'},
      );

      expect(successResult.success, isTrue);
      expect(successResult.duration, equals(const Duration(minutes: 5, seconds: 30)));
      expect(successResult.restoredCounts, equals({'patients': 50, 'visits': 100}));
      expect(successResult.metadata, equals({'restore_type': 'full'}));
      expect(successResult.errorMessage, isNull);
    });

    test('should create failure result correctly', () {
      final failureResult = RestoreResult.failure(
        duration: const Duration(minutes: 2),
        errorMessage: 'Decryption failed',
        metadata: {'error_code': 'DECRYPT_001'},
      );

      expect(failureResult.success, isFalse);
      expect(failureResult.duration, equals(const Duration(minutes: 2)));
      expect(failureResult.errorMessage, equals('Decryption failed'));
      expect(failureResult.metadata, equals({'error_code': 'DECRYPT_001'}));
      expect(failureResult.restoredCounts, isNull);
    });

    test('should calculate total restored count correctly', () {
      final result = RestoreResult.success(
        duration: const Duration(minutes: 1),
        restoredCounts: {'patients': 25, 'visits': 50, 'payments': 75},
      );

      expect(result.totalRestored, equals(150)); // 25 + 50 + 75

      final emptyResult = RestoreResult.success(
        duration: const Duration(minutes: 1),
        restoredCounts: {},
      );
      expect(emptyResult.totalRestored, equals(0));

      final nullResult = RestoreResult.success(
        duration: const Duration(minutes: 1),
        restoredCounts: null,
      );
      expect(nullResult.totalRestored, equals(0));
    });

    test('should format duration correctly', () {
      final minutesResult = RestoreResult.success(
        duration: const Duration(minutes: 5, seconds: 30),
      );
      expect(minutesResult.formattedDuration, equals('5m 30s'));

      final secondsResult = RestoreResult.success(
        duration: const Duration(seconds: 45),
      );
      expect(secondsResult.formattedDuration, equals('45s'));

      final hoursResult = RestoreResult.success(
        duration: const Duration(hours: 1, minutes: 30, seconds: 15),
      );
      expect(hoursResult.formattedDuration, equals('90m 15s'));
    });

    test('should implement equality correctly', () {
      final result1 = RestoreResult.success(
        duration: const Duration(minutes: 5),
        restoredCounts: {'patients': 10},
      );

      final result2 = RestoreResult.success(
        duration: const Duration(minutes: 5),
        restoredCounts: {'patients': 10},
      );

      expect(result1 == result2, isTrue);

      final differentResult = RestoreResult.success(
        duration: const Duration(minutes: 10), // Different duration
        restoredCounts: {'patients': 10},
      );
      expect(result1 == differentResult, isFalse);
    });
  });

  group('RestoreException Tests', () {
    test('should create RestoreException with message', () {
      const message = 'Restore operation failed';
      final exception = RestoreException(message);

      expect(exception.message, equals(message));
      expect(exception.code, isNull);
      expect(exception.originalException, isNull);
      expect(exception.toString(), contains(message));
    });

    test('should create RestoreException with code and original exception', () {
      const message = 'Decryption failed';
      const code = 'RESTORE_001';
      final originalException = Exception('Key not found');
      final exception = RestoreException(
        message,
        code: code,
        originalException: originalException,
      );

      expect(exception.message, equals(message));
      expect(exception.code, equals(code));
      expect(exception.originalException, equals(originalException));
      expect(exception.toString(), contains(message));
      expect(exception.toString(), contains(code));
    });
  });

  group('RestoreStatus Enum Tests', () {
    test('should handle all status values', () {
      final statuses = RestoreStatus.values;
      expect(statuses, contains(RestoreStatus.notStarted));
      expect(statuses, contains(RestoreStatus.selectingBackup));
      expect(statuses, contains(RestoreStatus.validatingBackup));
      expect(statuses, contains(RestoreStatus.downloading));
      expect(statuses, contains(RestoreStatus.decrypting));
      expect(statuses, contains(RestoreStatus.importing));
      expect(statuses, contains(RestoreStatus.completed));
      expect(statuses, contains(RestoreStatus.error));
      expect(statuses, contains(RestoreStatus.cancelled));
    });
  });
}