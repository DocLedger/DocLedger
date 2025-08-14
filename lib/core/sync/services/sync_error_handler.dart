import 'dart:async';
import 'dart:io';
import '../models/sync_exceptions.dart';
import '../models/sync_models.dart';

/// Handles network and API errors for sync operations
class SyncErrorHandler {
  /// Handles network-related errors and returns appropriate sync result
  static SyncResult handleNetworkError(dynamic error, [StackTrace? stackTrace]) {
    if (error is NetworkException) {
      return _handleNetworkException(error);
    }

    // Handle common network errors
    if (error is SocketException) {
      return _handleSocketException(error);
    }

    if (error is HttpException) {
      return _handleHttpException(error);
    }

    if (error is TimeoutException) {
      return SyncResult.retry(
        error: NetworkException(
          'Operation timed out',
          NetworkErrorType.timeout,
          originalError: error,
          stackTrace: stackTrace,
        ),
        retryAfter: const Duration(minutes: 1),
      );
    }

    // Generic network error
    return SyncResult.withError(
      NetworkException(
        'Unknown network error: ${error.toString()}',
        NetworkErrorType.serverError,
        originalError: error,
        stackTrace: stackTrace,
      ),
    );
  }

  /// Handles authentication errors
  static SyncResult handleAuthenticationError(dynamic error, [StackTrace? stackTrace]) {
    if (error is AuthenticationException) {
      switch (error.type) {
        case AuthErrorType.tokenExpired:
          return SyncResult.requiresReauth(
            message: 'Authentication token expired',
            error: error,
          );
        case AuthErrorType.invalidCredentials:
          return SyncResult.requiresReauth(
            message: 'Invalid credentials',
            error: error,
          );
        case AuthErrorType.accountDisabled:
          return SyncResult.withError(error);
        case AuthErrorType.permissionDenied:
          return SyncResult.withError(error);
        case AuthErrorType.scopeInsufficient:
          return SyncResult.requiresReauth(
            message: 'Insufficient permissions',
            error: error,
          );
      }
    }

    return SyncResult.requiresReauth(
      message: 'Authentication failed',
      error: AuthenticationException(
        error.toString(),
        AuthErrorType.invalidCredentials,
        originalError: error,
        stackTrace: stackTrace,
      ),
    );
  }

  /// Handles storage-related errors
  static SyncResult handleStorageError(dynamic error, [StackTrace? stackTrace]) {
    if (error is StorageException) {
      switch (error.type) {
        case StorageErrorType.insufficientSpace:
        case StorageErrorType.quotaExceeded:
        case StorageErrorType.diskFull:
          return SyncResult.withError(error);
        case StorageErrorType.fileNotFound:
          return SyncResult.retry(
            error: error,
            retryAfter: const Duration(seconds: 30),
          );
        case StorageErrorType.accessDenied:
          return SyncResult.requiresReauth(
            message: 'Access denied to storage',
            error: error,
          );
      }
    }

    return SyncResult.withError(
      StorageException(
        'Storage error: ${error.toString()}',
        StorageErrorType.accessDenied,
        originalError: error,
        stackTrace: stackTrace,
      ),
    );
  }

  /// Handles sync operation errors
  static SyncResult handleSyncOperationError(dynamic error, [StackTrace? stackTrace]) {
    if (error is SyncOperationException) {
      switch (error.type) {
        case SyncOperationErrorType.syncInProgress:
          return SyncResult.deferred('Sync already in progress');
        case SyncOperationErrorType.invalidState:
          return SyncResult.withError(error);
        case SyncOperationErrorType.operationCancelled:
          return SyncResult.cancelled();
        case SyncOperationErrorType.syncFailed:
        case SyncOperationErrorType.backupFailed:
        case SyncOperationErrorType.restoreFailed:
          return SyncResult.retry(
            error: error,
            retryAfter: const Duration(minutes: 5),
          );
      }
    }

    return SyncResult.withError(
      SyncOperationException(
        'Sync operation failed: ${error.toString()}',
        SyncOperationErrorType.syncFailed,
        originalError: error,
        stackTrace: stackTrace,
      ),
    );
  }

  /// Determines if an error is retryable
  static bool isRetryableError(dynamic error) {
    if (error is NetworkException) {
      switch (error.type) {
        case NetworkErrorType.noInternet:
        case NetworkErrorType.timeout:
        case NetworkErrorType.serverError:
        case NetworkErrorType.connectionRefused:
        case NetworkErrorType.dnsResolutionFailed:
          return true;
        case NetworkErrorType.rateLimited:
          return true;
        case NetworkErrorType.authenticationFailed:
        case NetworkErrorType.insufficientStorage:
          return false;
      }
    }

    if (error is AuthenticationException) {
      return error.type == AuthErrorType.tokenExpired;
    }

    if (error is StorageException) {
      return error.type == StorageErrorType.fileNotFound;
    }

    if (error is SyncOperationException) {
      switch (error.type) {
        case SyncOperationErrorType.syncFailed:
        case SyncOperationErrorType.backupFailed:
        case SyncOperationErrorType.restoreFailed:
          return true;
        case SyncOperationErrorType.syncInProgress:
        case SyncOperationErrorType.invalidState:
        case SyncOperationErrorType.operationCancelled:
          return false;
      }
    }

    return false;
  }

  /// Gets retry delay based on error type
  static Duration getRetryDelay(dynamic error, int attemptNumber) {
    const baseDelays = {
      NetworkErrorType.noInternet: Duration(minutes: 1),
      NetworkErrorType.timeout: Duration(seconds: 30),
      NetworkErrorType.serverError: Duration(minutes: 2),
      NetworkErrorType.rateLimited: Duration(minutes: 5),
      NetworkErrorType.connectionRefused: Duration(seconds: 15),
      NetworkErrorType.dnsResolutionFailed: Duration(seconds: 30),
    };

    Duration baseDelay = const Duration(seconds: 30);

    if (error is NetworkException && baseDelays.containsKey(error.type)) {
      baseDelay = baseDelays[error.type]!;
    }

    // Apply exponential backoff
    final multiplier = (1 << (attemptNumber - 1)).clamp(1, 16);
    return Duration(milliseconds: (baseDelay.inMilliseconds * multiplier).clamp(1000, 300000));
  }

  static SyncResult _handleNetworkException(NetworkException error) {
    switch (error.type) {
      case NetworkErrorType.noInternet:
        return SyncResult.deferred('No internet connection available');
      case NetworkErrorType.timeout:
        return SyncResult.retry(
          error: error,
          retryAfter: const Duration(seconds: 30),
        );
      case NetworkErrorType.serverError:
        return SyncResult.retry(
          error: error,
          retryAfter: const Duration(minutes: 2),
        );
      case NetworkErrorType.rateLimited:
        return SyncResult.retry(
          error: error,
          retryAfter: const Duration(minutes: 5),
        );
      case NetworkErrorType.authenticationFailed:
        return SyncResult.requiresReauth(
          message: 'Authentication failed',
          error: error,
        );
      case NetworkErrorType.insufficientStorage:
        return SyncResult.withError(error);
      case NetworkErrorType.connectionRefused:
        return SyncResult.retry(
          error: error,
          retryAfter: const Duration(seconds: 15),
        );
      case NetworkErrorType.dnsResolutionFailed:
        return SyncResult.retry(
          error: error,
          retryAfter: const Duration(seconds: 30),
        );
    }
  }

  static SyncResult _handleSocketException(SocketException error) {
    if (error.osError?.errorCode == 7) {
      // No address associated with hostname
      return SyncResult.retry(
        error: NetworkException(
          'DNS resolution failed',
          NetworkErrorType.dnsResolutionFailed,
          originalError: error,
        ),
        retryAfter: const Duration(seconds: 30),
      );
    }

    if (error.osError?.errorCode == 111) {
      // Connection refused
      return SyncResult.retry(
        error: NetworkException(
          'Connection refused',
          NetworkErrorType.connectionRefused,
          originalError: error,
        ),
        retryAfter: const Duration(seconds: 15),
      );
    }

    return SyncResult.deferred(
      'Network unavailable: ${error.message}',
    );
  }

  static SyncResult _handleHttpException(HttpException error) {
    final statusCode = _extractStatusCode(error.message);
    
    if (statusCode != null) {
      if (statusCode >= 500) {
        return SyncResult.retry(
          error: NetworkException(
            'Server error: ${error.message}',
            NetworkErrorType.serverError,
            originalError: error,
          ),
          retryAfter: const Duration(minutes: 2),
        );
      }

      if (statusCode == 429) {
        return SyncResult.retry(
          error: NetworkException(
            'Rate limited',
            NetworkErrorType.rateLimited,
            originalError: error,
          ),
          retryAfter: const Duration(minutes: 5),
        );
      }

      if (statusCode == 401 || statusCode == 403) {
        return SyncResult.requiresReauth(
          message: 'Authentication required',
          error: AuthenticationException(
            error.message,
            statusCode == 401 ? AuthErrorType.tokenExpired : AuthErrorType.permissionDenied,
            originalError: error,
          ),
        );
      }
    }

    return SyncResult.withError(
      NetworkException(
        'HTTP error: ${error.message}',
        NetworkErrorType.serverError,
        originalError: error,
      ),
    );
  }

  static int? _extractStatusCode(String message) {
    final regex = RegExp(r'(\d{3})');
    final match = regex.firstMatch(message);
    return match != null ? int.tryParse(match.group(1)!) : null;
  }
}