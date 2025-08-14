import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../../../lib/core/sync/models/sync_exceptions.dart';
import '../../../../lib/core/sync/models/sync_models.dart';
import '../../../../lib/core/sync/services/sync_error_handler.dart';

void main() {
  group('SyncErrorHandler', () {
    group('handleNetworkError', () {
      test('should handle NetworkException with noInternet type', () {
        final error = NetworkException(
          'No internet connection',
          NetworkErrorType.noInternet,
        );

        final result = SyncErrorHandler.handleNetworkError(error);

        expect(result.status, SyncResultStatus.partial);
        expect(result.errorMessage, 'No internet connection available');
      });

      test('should handle NetworkException with timeout type', () {
        final error = NetworkException(
          'Request timeout',
          NetworkErrorType.timeout,
        );

        final result = SyncErrorHandler.handleNetworkError(error);

        expect(result.status, SyncResultStatus.failure);
        expect(result.retryAfter, const Duration(seconds: 30));
      });

      test('should handle NetworkException with serverError type', () {
        final error = NetworkException(
          'Server error',
          NetworkErrorType.serverError,
        );

        final result = SyncErrorHandler.handleNetworkError(error);

        expect(result.status, SyncResultStatus.failure);
        expect(result.retryAfter, const Duration(minutes: 2));
      });

      test('should handle NetworkException with rateLimited type', () {
        final error = NetworkException(
          'Rate limited',
          NetworkErrorType.rateLimited,
        );

        final result = SyncErrorHandler.handleNetworkError(error);

        expect(result.status, SyncResultStatus.failure);
        expect(result.retryAfter, const Duration(minutes: 5));
      });

      test('should handle NetworkException with authenticationFailed type', () {
        final error = NetworkException(
          'Authentication failed',
          NetworkErrorType.authenticationFailed,
        );

        final result = SyncErrorHandler.handleNetworkError(error);

        expect(result.status, SyncResultStatus.failure);
        expect(result.metadata?['requires_reauth'], true);
      });

      test('should handle SocketException with DNS resolution error', () {
        final error = SocketException(
          'Failed host lookup',
          osError: OSError('No address associated with hostname', 7),
        );

        final result = SyncErrorHandler.handleNetworkError(error);

        expect(result.status, SyncResultStatus.failure);
        expect(result.retryAfter, const Duration(seconds: 30));
        expect(result.error, isA<NetworkException>());
        final networkError = result.error as NetworkException;
        expect(networkError.type, NetworkErrorType.dnsResolutionFailed);
      });

      test('should handle SocketException with connection refused error', () {
        final error = SocketException(
          'Connection refused',
          osError: OSError('Connection refused', 111),
        );

        final result = SyncErrorHandler.handleNetworkError(error);

        expect(result.status, SyncResultStatus.failure);
        expect(result.retryAfter, const Duration(seconds: 15));
        expect(result.error, isA<NetworkException>());
        final networkError = result.error as NetworkException;
        expect(networkError.type, NetworkErrorType.connectionRefused);
      });

      test('should handle TimeoutException', () {
        final error = TimeoutException('Operation timed out');

        final result = SyncErrorHandler.handleNetworkError(error);

        expect(result.status, SyncResultStatus.failure);
        expect(result.retryAfter, const Duration(minutes: 1));
        expect(result.error, isA<NetworkException>());
        final networkError = result.error as NetworkException;
        expect(networkError.type, NetworkErrorType.timeout);
      });

      test('should handle HttpException with 500 status code', () {
        final error = HttpException('Server returned status code 500');

        final result = SyncErrorHandler.handleNetworkError(error);

        expect(result.status, SyncResultStatus.failure);
        expect(result.retryAfter, const Duration(minutes: 2));
        expect(result.error, isA<NetworkException>());
        final networkError = result.error as NetworkException;
        expect(networkError.type, NetworkErrorType.serverError);
      });

      test('should handle HttpException with 429 status code', () {
        final error = HttpException('Too Many Requests - status code 429');

        final result = SyncErrorHandler.handleNetworkError(error);

        expect(result.status, SyncResultStatus.failure);
        expect(result.retryAfter, const Duration(minutes: 5));
        expect(result.error, isA<NetworkException>());
        final networkError = result.error as NetworkException;
        expect(networkError.type, NetworkErrorType.rateLimited);
      });

      test('should handle HttpException with 401 status code', () {
        final error = HttpException('Unauthorized - status code 401');

        final result = SyncErrorHandler.handleNetworkError(error);

        expect(result.status, SyncResultStatus.failure);
        expect(result.metadata?['requires_reauth'], true);
        expect(result.error, isA<AuthenticationException>());
        final authError = result.error as AuthenticationException;
        expect(authError.type, AuthErrorType.tokenExpired);
      });

      test('should handle unknown network error', () {
        final error = Exception('Unknown network error');

        final result = SyncErrorHandler.handleNetworkError(error);

        expect(result.status, SyncResultStatus.failure);
        expect(result.error, isA<NetworkException>());
        final networkError = result.error as NetworkException;
        expect(networkError.type, NetworkErrorType.serverError);
        expect(networkError.message, contains('Unknown network error'));
      });
    });

    group('handleAuthenticationError', () {
      test('should handle AuthenticationException with tokenExpired type', () {
        final error = AuthenticationException(
          'Token expired',
          AuthErrorType.tokenExpired,
        );

        final result = SyncErrorHandler.handleAuthenticationError(error);

        expect(result.status, SyncResultStatus.failure);
        expect(result.metadata?['requires_reauth'], true);
        expect(result.errorMessage, 'Authentication token expired');
      });

      test('should handle AuthenticationException with invalidCredentials type', () {
        final error = AuthenticationException(
          'Invalid credentials',
          AuthErrorType.invalidCredentials,
        );

        final result = SyncErrorHandler.handleAuthenticationError(error);

        expect(result.status, SyncResultStatus.failure);
        expect(result.metadata?['requires_reauth'], true);
        expect(result.errorMessage, 'Invalid credentials');
      });

      test('should handle AuthenticationException with accountDisabled type', () {
        final error = AuthenticationException(
          'Account disabled',
          AuthErrorType.accountDisabled,
        );

        final result = SyncErrorHandler.handleAuthenticationError(error);

        expect(result.status, SyncResultStatus.failure);
        expect(result.metadata, isNull);
      });

      test('should handle unknown authentication error', () {
        final error = Exception('Unknown auth error');

        final result = SyncErrorHandler.handleAuthenticationError(error);

        expect(result.status, SyncResultStatus.failure);
        expect(result.metadata?['requires_reauth'], true);
        expect(result.error, isA<AuthenticationException>());
        final authError = result.error as AuthenticationException;
        expect(authError.type, AuthErrorType.invalidCredentials);
      });
    });

    group('handleStorageError', () {
      test('should handle StorageException with insufficientSpace type', () {
        final error = StorageException(
          'Insufficient storage space',
          StorageErrorType.insufficientSpace,
        );

        final result = SyncErrorHandler.handleStorageError(error);

        expect(result.status, SyncResultStatus.failure);
        expect(result.error, error);
      });

      test('should handle StorageException with fileNotFound type', () {
        final error = StorageException(
          'File not found',
          StorageErrorType.fileNotFound,
        );

        final result = SyncErrorHandler.handleStorageError(error);

        expect(result.status, SyncResultStatus.failure);
        expect(result.retryAfter, const Duration(seconds: 30));
      });

      test('should handle StorageException with accessDenied type', () {
        final error = StorageException(
          'Access denied',
          StorageErrorType.accessDenied,
        );

        final result = SyncErrorHandler.handleStorageError(error);

        expect(result.status, SyncResultStatus.failure);
        expect(result.metadata?['requires_reauth'], true);
      });

      test('should handle unknown storage error', () {
        final error = Exception('Unknown storage error');

        final result = SyncErrorHandler.handleStorageError(error);

        expect(result.status, SyncResultStatus.failure);
        expect(result.error, isA<StorageException>());
        final storageError = result.error as StorageException;
        expect(storageError.type, StorageErrorType.accessDenied);
      });
    });

    group('handleSyncOperationError', () {
      test('should handle SyncOperationException with syncInProgress type', () {
        final error = SyncOperationException(
          'Sync already in progress',
          SyncOperationErrorType.syncInProgress,
        );

        final result = SyncErrorHandler.handleSyncOperationError(error);

        expect(result.status, SyncResultStatus.partial);
        expect(result.errorMessage, 'Sync already in progress');
      });

      test('should handle SyncOperationException with syncFailed type', () {
        final error = SyncOperationException(
          'Sync failed',
          SyncOperationErrorType.syncFailed,
        );

        final result = SyncErrorHandler.handleSyncOperationError(error);

        expect(result.status, SyncResultStatus.failure);
        expect(result.retryAfter, const Duration(minutes: 5));
      });

      test('should handle SyncOperationException with operationCancelled type', () {
        final error = SyncOperationException(
          'Operation cancelled',
          SyncOperationErrorType.operationCancelled,
        );

        final result = SyncErrorHandler.handleSyncOperationError(error);

        expect(result.status, SyncResultStatus.cancelled);
      });
    });

    group('isRetryableError', () {
      test('should return true for retryable network errors', () {
        final retryableErrors = [
          NetworkException('No internet', NetworkErrorType.noInternet),
          NetworkException('Timeout', NetworkErrorType.timeout),
          NetworkException('Server error', NetworkErrorType.serverError),
          NetworkException('Connection refused', NetworkErrorType.connectionRefused),
          NetworkException('DNS failed', NetworkErrorType.dnsResolutionFailed),
        ];

        for (final error in retryableErrors) {
          expect(SyncErrorHandler.isRetryableError(error), true,
              reason: 'Error ${error.type} should be retryable');
        }
      });

      test('should return false for non-retryable network errors', () {
        final nonRetryableErrors = [
          NetworkException('Auth failed', NetworkErrorType.authenticationFailed),
          NetworkException('No storage', NetworkErrorType.insufficientStorage),
          NetworkException('Rate limited', NetworkErrorType.rateLimited),
        ];

        for (final error in nonRetryableErrors) {
          expect(SyncErrorHandler.isRetryableError(error), false,
              reason: 'Error ${error.type} should not be retryable');
        }
      });

      test('should return true for token expired authentication error', () {
        final error = AuthenticationException(
          'Token expired',
          AuthErrorType.tokenExpired,
        );

        expect(SyncErrorHandler.isRetryableError(error), true);
      });

      test('should return false for other authentication errors', () {
        final nonRetryableAuthErrors = [
          AuthenticationException('Invalid creds', AuthErrorType.invalidCredentials),
          AuthenticationException('Account disabled', AuthErrorType.accountDisabled),
          AuthenticationException('Permission denied', AuthErrorType.permissionDenied),
        ];

        for (final error in nonRetryableAuthErrors) {
          expect(SyncErrorHandler.isRetryableError(error), false,
              reason: 'Auth error ${error.type} should not be retryable');
        }
      });
    });

    group('getRetryDelay', () {
      test('should return appropriate delay for network errors', () {
        final testCases = [
          (NetworkException('No internet', NetworkErrorType.noInternet), 1, Duration(minutes: 1)),
          (NetworkException('Timeout', NetworkErrorType.timeout), 1, Duration(seconds: 30)),
          (NetworkException('Server error', NetworkErrorType.serverError), 1, Duration(minutes: 2)),
          (NetworkException('Rate limited', NetworkErrorType.rateLimited), 1, Duration(minutes: 5)),
        ];

        for (final (error, attempt, expectedBaseDelay) in testCases) {
          final delay = SyncErrorHandler.getRetryDelay(error, attempt);
          expect(delay, expectedBaseDelay,
              reason: 'Delay for ${error.type} should be $expectedBaseDelay');
        }
      });

      test('should apply exponential backoff', () {
        final error = NetworkException('Timeout', NetworkErrorType.timeout);
        
        final delay1 = SyncErrorHandler.getRetryDelay(error, 1);
        final delay2 = SyncErrorHandler.getRetryDelay(error, 2);
        final delay3 = SyncErrorHandler.getRetryDelay(error, 3);

        expect(delay1, const Duration(seconds: 30));
        expect(delay2, const Duration(minutes: 1));
        expect(delay3, const Duration(minutes: 2));
      });

      test('should cap maximum delay', () {
        final error = NetworkException('Timeout', NetworkErrorType.timeout);
        
        final delay = SyncErrorHandler.getRetryDelay(error, 20); // Very high attempt number
        
        expect(delay.inMilliseconds, lessThanOrEqualTo(300000)); // 5 minutes max
      });

      test('should have minimum delay', () {
        final error = Exception('Unknown error');
        
        final delay = SyncErrorHandler.getRetryDelay(error, 1);
        
        expect(delay.inMilliseconds, greaterThanOrEqualTo(1000)); // 1 second min
      });
    });
  });
}