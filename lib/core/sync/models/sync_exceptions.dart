/// Custom exception classes for sync operations
library sync_exceptions;

/// Base class for all sync-related exceptions
abstract class SyncException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;
  final StackTrace? stackTrace;

  const SyncException(
    this.message, {
    this.code,
    this.originalError,
    this.stackTrace,
  });

  @override
  String toString() => 'SyncException: $message${code != null ? ' (Code: $code)' : ''}';
}

/// Network-related exceptions
class NetworkException extends SyncException {
  final NetworkErrorType type;

  const NetworkException(
    String message,
    this.type, {
    String? code,
    dynamic originalError,
    StackTrace? stackTrace,
  }) : super(message, code: code, originalError: originalError, stackTrace: stackTrace);

  @override
  String toString() => 'NetworkException: $message (Type: $type)';
}

enum NetworkErrorType {
  noInternet,
  timeout,
  serverError,
  rateLimited,
  authenticationFailed,
  insufficientStorage,
  connectionRefused,
  dnsResolutionFailed,
}

/// Authentication-related exceptions
class AuthenticationException extends SyncException {
  final AuthErrorType type;

  const AuthenticationException(
    String message,
    this.type, {
    String? code,
    dynamic originalError,
    StackTrace? stackTrace,
  }) : super(message, code: code, originalError: originalError, stackTrace: stackTrace);

  @override
  String toString() => 'AuthenticationException: $message (Type: $type)';
}

enum AuthErrorType {
  tokenExpired,
  invalidCredentials,
  accountDisabled,
  permissionDenied,
  scopeInsufficient,
}

/// Data integrity exceptions
class DataIntegrityException extends SyncException {
  final DataIntegrityErrorType type;

  const DataIntegrityException(
    String message,
    this.type, {
    String? code,
    dynamic originalError,
    StackTrace? stackTrace,
  }) : super(message, code: code, originalError: originalError, stackTrace: stackTrace);

  @override
  String toString() => 'DataIntegrityException: $message (Type: $type)';
}

enum DataIntegrityErrorType {
  checksumMismatch,
  corruptedData,
  invalidFormat,
  versionMismatch,
  encryptionFailed,
  decryptionFailed,
}

/// Storage-related exceptions
class StorageException extends SyncException {
  final StorageErrorType type;

  const StorageException(
    String message,
    this.type, {
    String? code,
    dynamic originalError,
    StackTrace? stackTrace,
  }) : super(message, code: code, originalError: originalError, stackTrace: stackTrace);

  @override
  String toString() => 'StorageException: $message (Type: $type)';
}

enum StorageErrorType {
  insufficientSpace,
  fileNotFound,
  accessDenied,
  quotaExceeded,
  diskFull,
}

/// Conflict resolution exceptions
class ConflictException extends SyncException {
  final ConflictErrorType type;
  final Map<String, dynamic>? conflictData;

  const ConflictException(
    String message,
    this.type, {
    this.conflictData,
    String? code,
    dynamic originalError,
    StackTrace? stackTrace,
  }) : super(message, code: code, originalError: originalError, stackTrace: stackTrace);

  @override
  String toString() => 'ConflictException: $message (Type: $type)';
}

enum ConflictErrorType {
  unresolvableConflict,
  multipleConflicts,
  invalidResolution,
  conflictResolutionFailed,
}

/// Sync operation exceptions
class SyncOperationException extends SyncException {
  final SyncOperationErrorType type;

  const SyncOperationException(
    String message,
    this.type, {
    String? code,
    dynamic originalError,
    StackTrace? stackTrace,
  }) : super(message, code: code, originalError: originalError, stackTrace: stackTrace);

  @override
  String toString() => 'SyncOperationException: $message (Type: $type)';
}

enum SyncOperationErrorType {
  syncInProgress,
  syncFailed,
  backupFailed,
  restoreFailed,
  invalidState,
  operationCancelled,
}