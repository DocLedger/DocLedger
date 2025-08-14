import 'package:flutter_test/flutter_test.dart';
import 'package:doc_ledger/core/sync/models/sync_exceptions.dart';

void main() {
  group('NetworkException Tests', () {
    test('should create NetworkException with message and type', () {
      const message = 'Network error occurred';
      final exception = NetworkException(message, NetworkErrorType.noInternet);

      expect(exception.message, equals(message));
      expect(exception.type, equals(NetworkErrorType.noInternet));
      expect(exception.toString(), contains(message));
      expect(exception.toString(), contains('noInternet'));
    });

    test('should handle all network error types', () {
      for (final type in NetworkErrorType.values) {
        final exception = NetworkException('Test error', type);
        expect(exception.type, equals(type));
      }
    });

    test('should include code and original error', () {
      final originalError = Exception('Original error');
      final exception = NetworkException(
        'Network failed',
        NetworkErrorType.timeout,
        code: 'NET_001',
        originalError: originalError,
      );

      expect(exception.code, equals('NET_001'));
      expect(exception.originalError, equals(originalError));
      expect(exception.toString(), contains('Network failed'));
      expect(exception.toString(), contains('timeout'));
    });
  });

  group('AuthenticationException Tests', () {
    test('should create AuthenticationException with message and type', () {
      const message = 'Authentication failed';
      final exception = AuthenticationException(message, AuthErrorType.tokenExpired);

      expect(exception.message, equals(message));
      expect(exception.type, equals(AuthErrorType.tokenExpired));
      expect(exception.toString(), contains(message));
      expect(exception.toString(), contains('tokenExpired'));
    });

    test('should handle all auth error types', () {
      for (final type in AuthErrorType.values) {
        final exception = AuthenticationException('Test error', type);
        expect(exception.type, equals(type));
      }
    });

    test('should include code and original error', () {
      final originalError = Exception('Auth error');
      final exception = AuthenticationException(
        'Token expired',
        AuthErrorType.tokenExpired,
        code: 'AUTH_001',
        originalError: originalError,
      );

      expect(exception.code, equals('AUTH_001'));
      expect(exception.originalError, equals(originalError));
    });
  });

  group('DataIntegrityException Tests', () {
    test('should create DataIntegrityException with message and type', () {
      const message = 'Data integrity check failed';
      final exception = DataIntegrityException(message, DataIntegrityErrorType.checksumMismatch);

      expect(exception.message, equals(message));
      expect(exception.type, equals(DataIntegrityErrorType.checksumMismatch));
      expect(exception.toString(), contains(message));
      expect(exception.toString(), contains('checksumMismatch'));
    });

    test('should handle all data integrity error types', () {
      for (final type in DataIntegrityErrorType.values) {
        final exception = DataIntegrityException('Test error', type);
        expect(exception.type, equals(type));
      }
    });

    test('should include code and original error', () {
      final originalError = Exception('Checksum error');
      final exception = DataIntegrityException(
        'Checksum mismatch',
        DataIntegrityErrorType.checksumMismatch,
        code: 'DATA_001',
        originalError: originalError,
      );

      expect(exception.code, equals('DATA_001'));
      expect(exception.originalError, equals(originalError));
    });
  });

  group('StorageException Tests', () {
    test('should create StorageException with message and type', () {
      const message = 'Storage operation failed';
      final exception = StorageException(message, StorageErrorType.insufficientSpace);

      expect(exception.message, equals(message));
      expect(exception.type, equals(StorageErrorType.insufficientSpace));
      expect(exception.toString(), contains(message));
      expect(exception.toString(), contains('insufficientSpace'));
    });

    test('should handle all storage error types', () {
      for (final type in StorageErrorType.values) {
        final exception = StorageException('Test error', type);
        expect(exception.type, equals(type));
      }
    });

    test('should include code and original error', () {
      final originalError = Exception('Disk full');
      final exception = StorageException(
        'Insufficient space',
        StorageErrorType.diskFull,
        code: 'STORAGE_001',
        originalError: originalError,
      );

      expect(exception.code, equals('STORAGE_001'));
      expect(exception.originalError, equals(originalError));
    });
  });

  group('ConflictException Tests', () {
    test('should create ConflictException with message and type', () {
      const message = 'Conflict resolution failed';
      final conflictData = {'record_id': 'patient_1', 'field': 'name'};
      final exception = ConflictException(
        message,
        ConflictErrorType.unresolvableConflict,
        conflictData: conflictData,
      );

      expect(exception.message, equals(message));
      expect(exception.type, equals(ConflictErrorType.unresolvableConflict));
      expect(exception.conflictData, equals(conflictData));
      expect(exception.toString(), contains(message));
      expect(exception.toString(), contains('unresolvableConflict'));
    });

    test('should handle all conflict error types', () {
      for (final type in ConflictErrorType.values) {
        final exception = ConflictException('Test error', type);
        expect(exception.type, equals(type));
      }
    });

    test('should include code and original error', () {
      final originalError = Exception('Conflict error');
      final exception = ConflictException(
        'Multiple conflicts detected',
        ConflictErrorType.multipleConflicts,
        code: 'CONFLICT_001',
        originalError: originalError,
      );

      expect(exception.code, equals('CONFLICT_001'));
      expect(exception.originalError, equals(originalError));
    });
  });

  group('SyncOperationException Tests', () {
    test('should create SyncOperationException with message and type', () {
      const message = 'Sync operation failed';
      final exception = SyncOperationException(message, SyncOperationErrorType.syncFailed);

      expect(exception.message, equals(message));
      expect(exception.type, equals(SyncOperationErrorType.syncFailed));
      expect(exception.toString(), contains(message));
      expect(exception.toString(), contains('syncFailed'));
    });

    test('should handle all sync operation error types', () {
      for (final type in SyncOperationErrorType.values) {
        final exception = SyncOperationException('Test error', type);
        expect(exception.type, equals(type));
      }
    });

    test('should include code and original error', () {
      final originalError = Exception('Sync error');
      final exception = SyncOperationException(
        'Backup failed',
        SyncOperationErrorType.backupFailed,
        code: 'SYNC_001',
        originalError: originalError,
      );

      expect(exception.code, equals('SYNC_001'));
      expect(exception.originalError, equals(originalError));
    });
  });

  group('Enum Tests', () {
    test('should handle all NetworkErrorType values', () {
      final types = NetworkErrorType.values;
      expect(types, contains(NetworkErrorType.noInternet));
      expect(types, contains(NetworkErrorType.timeout));
      expect(types, contains(NetworkErrorType.serverError));
      expect(types, contains(NetworkErrorType.rateLimited));
      expect(types, contains(NetworkErrorType.authenticationFailed));
      expect(types, contains(NetworkErrorType.insufficientStorage));
      expect(types, contains(NetworkErrorType.connectionRefused));
      expect(types, contains(NetworkErrorType.dnsResolutionFailed));
    });

    test('should handle all AuthErrorType values', () {
      final types = AuthErrorType.values;
      expect(types, contains(AuthErrorType.tokenExpired));
      expect(types, contains(AuthErrorType.invalidCredentials));
      expect(types, contains(AuthErrorType.accountDisabled));
      expect(types, contains(AuthErrorType.permissionDenied));
      expect(types, contains(AuthErrorType.scopeInsufficient));
    });

    test('should handle all DataIntegrityErrorType values', () {
      final types = DataIntegrityErrorType.values;
      expect(types, contains(DataIntegrityErrorType.checksumMismatch));
      expect(types, contains(DataIntegrityErrorType.corruptedData));
      expect(types, contains(DataIntegrityErrorType.invalidFormat));
      expect(types, contains(DataIntegrityErrorType.versionMismatch));
      expect(types, contains(DataIntegrityErrorType.encryptionFailed));
      expect(types, contains(DataIntegrityErrorType.decryptionFailed));
    });

    test('should handle all StorageErrorType values', () {
      final types = StorageErrorType.values;
      expect(types, contains(StorageErrorType.insufficientSpace));
      expect(types, contains(StorageErrorType.fileNotFound));
      expect(types, contains(StorageErrorType.accessDenied));
      expect(types, contains(StorageErrorType.quotaExceeded));
      expect(types, contains(StorageErrorType.diskFull));
    });

    test('should handle all ConflictErrorType values', () {
      final types = ConflictErrorType.values;
      expect(types, contains(ConflictErrorType.unresolvableConflict));
      expect(types, contains(ConflictErrorType.multipleConflicts));
      expect(types, contains(ConflictErrorType.invalidResolution));
      expect(types, contains(ConflictErrorType.conflictResolutionFailed));
    });

    test('should handle all SyncOperationErrorType values', () {
      final types = SyncOperationErrorType.values;
      expect(types, contains(SyncOperationErrorType.syncInProgress));
      expect(types, contains(SyncOperationErrorType.syncFailed));
      expect(types, contains(SyncOperationErrorType.backupFailed));
      expect(types, contains(SyncOperationErrorType.restoreFailed));
      expect(types, contains(SyncOperationErrorType.invalidState));
      expect(types, contains(SyncOperationErrorType.operationCancelled));
    });
  });

  group('Exception Hierarchy Tests', () {
    test('should maintain proper exception hierarchy', () {
      final networkException = NetworkException('test', NetworkErrorType.noInternet);
      final authException = AuthenticationException('test', AuthErrorType.tokenExpired);
      final dataIntegrityException = DataIntegrityException('test', DataIntegrityErrorType.checksumMismatch);
      final storageException = StorageException('test', StorageErrorType.insufficientSpace);
      final conflictException = ConflictException('test', ConflictErrorType.unresolvableConflict);
      final syncOperationException = SyncOperationException('test', SyncOperationErrorType.syncFailed);

      expect(networkException, isA<SyncException>());
      expect(authException, isA<SyncException>());
      expect(dataIntegrityException, isA<SyncException>());
      expect(storageException, isA<SyncException>());
      expect(conflictException, isA<SyncException>());
      expect(syncOperationException, isA<SyncException>());
    });

    test('should implement Exception interface', () {
      final networkException = NetworkException('test', NetworkErrorType.noInternet);
      expect(networkException, isA<Exception>());
    });
  });
}