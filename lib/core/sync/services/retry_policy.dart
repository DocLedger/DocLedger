import 'dart:async';
import 'dart:math';
import '../models/sync_exceptions.dart';
import 'sync_error_handler.dart';

/// Configurable retry policy with exponential backoff
class RetryPolicy {
  final int maxRetries;
  final Duration baseDelay;
  final Duration maxDelay;
  final double backoffMultiplier;
  final double jitterFactor;
  final bool Function(dynamic error)? retryCondition;

  const RetryPolicy({
    this.maxRetries = 3,
    this.baseDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(minutes: 5),
    this.backoffMultiplier = 2.0,
    this.jitterFactor = 0.1,
    this.retryCondition,
  });

  /// Default retry policy for network operations
  static const RetryPolicy network = RetryPolicy(
    maxRetries: 3,
    baseDelay: Duration(seconds: 2),
    maxDelay: Duration(minutes: 2),
    backoffMultiplier: 2.0,
    jitterFactor: 0.1,
  );

  /// Aggressive retry policy for critical operations
  static const RetryPolicy aggressive = RetryPolicy(
    maxRetries: 5,
    baseDelay: Duration(seconds: 1),
    maxDelay: Duration(minutes: 10),
    backoffMultiplier: 1.5,
    jitterFactor: 0.2,
  );

  /// Conservative retry policy for non-critical operations
  static const RetryPolicy conservative = RetryPolicy(
    maxRetries: 2,
    baseDelay: Duration(seconds: 5),
    maxDelay: Duration(minutes: 1),
    backoffMultiplier: 3.0,
    jitterFactor: 0.05,
  );

  /// Executes an operation with retry logic
  Future<T> executeWithRetry<T>(
    Future<T> Function() operation, {
    String? operationName,
    void Function(int attempt, dynamic error, Duration nextDelay)? onRetry,
  }) async {
    dynamic lastError;
    
    for (int attempt = 1; attempt <= maxRetries + 1; attempt++) {
      try {
        return await operation();
      } catch (error) {
        lastError = error;
        
        // Check if we should retry this error
        if (!_shouldRetry(error, attempt)) {
          rethrow;
        }
        
        // If this was the last attempt, don't wait
        if (attempt > maxRetries) {
          rethrow;
        }
        
        // Calculate delay for next attempt
        final delay = _calculateDelay(attempt, error);
        
        // Call retry callback if provided
        onRetry?.call(attempt, error, delay);
        
        // Wait before next attempt
        await Future.delayed(delay);
      }
    }
    
    // This should never be reached, but just in case
    throw lastError ?? Exception('Retry failed with unknown error');
  }

  /// Executes an operation with retry and returns a result wrapper
  Future<RetryResult<T>> executeWithRetryResult<T>(
    Future<T> Function() operation, {
    String? operationName,
  }) async {
    final attempts = <RetryAttempt>[];
    final stopwatch = Stopwatch()..start();
    
    for (int attempt = 1; attempt <= maxRetries + 1; attempt++) {
      final attemptStart = DateTime.now();
      
      try {
        final result = await operation();
        stopwatch.stop();
        
        attempts.add(RetryAttempt(
          attemptNumber: attempt,
          timestamp: attemptStart,
          success: true,
          duration: DateTime.now().difference(attemptStart),
        ));
        
        return RetryResult.withSuccess<T>(
          result: result,
          attempts: attempts,
          totalDuration: stopwatch.elapsed,
          operationName: operationName,
        );
      } catch (error) {
        final attemptDuration = DateTime.now().difference(attemptStart);
        
        attempts.add(RetryAttempt(
          attemptNumber: attempt,
          timestamp: attemptStart,
          success: false,
          error: error,
          duration: attemptDuration,
        ));
        
        // Check if we should retry this error
        if (!_shouldRetry(error, attempt)) {
          stopwatch.stop();
          return RetryResult.withFailure<T>(
            error: error,
            attempts: attempts,
            totalDuration: stopwatch.elapsed,
            operationName: operationName,
          );
        }
        
        // If this was the last attempt, return failure
        if (attempt > maxRetries) {
          stopwatch.stop();
          return RetryResult.withFailure<T>(
            error: error,
            attempts: attempts,
            totalDuration: stopwatch.elapsed,
            operationName: operationName,
          );
        }
        
        // Calculate delay for next attempt
        final delay = _calculateDelay(attempt, error);
        attempts.last = attempts.last.copyWith(retryDelay: delay);
        
        // Wait before next attempt
        await Future.delayed(delay);
      }
    }
    
    // This should never be reached
    stopwatch.stop();
    return RetryResult.withFailure<T>(
      error: Exception('Retry failed with unknown error'),
      attempts: attempts,
      totalDuration: stopwatch.elapsed,
      operationName: operationName,
    );
  }

  /// Creates a retry policy for specific error types
  static RetryPolicy forErrorType(Type errorType) {
    if (errorType == NetworkException) {
      return const RetryPolicy(
        maxRetries: 4,
        baseDelay: Duration(seconds: 2),
        maxDelay: Duration(minutes: 5),
        backoffMultiplier: 2.0,
        jitterFactor: 0.15,
      );
    }
    
    if (errorType == AuthenticationException) {
      return const RetryPolicy(
        maxRetries: 2,
        baseDelay: Duration(seconds: 5),
        maxDelay: Duration(seconds: 30),
        backoffMultiplier: 2.0,
        jitterFactor: 0.1,
      );
    }
    
    if (errorType == DataIntegrityException) {
      return const RetryPolicy(
        maxRetries: 1,
        baseDelay: Duration(seconds: 1),
        maxDelay: Duration(seconds: 5),
        backoffMultiplier: 1.0,
        jitterFactor: 0.0,
      );
    }
    
    return const RetryPolicy(); // Default policy
  }

  /// Calculates the delay before the next retry attempt
  Duration _calculateDelay(int attemptNumber, dynamic error) {
    // Use error-specific delay if available
    Duration delay;
    if (SyncErrorHandler.isRetryableError(error)) {
      delay = SyncErrorHandler.getRetryDelay(error, attemptNumber);
    } else {
      // Calculate exponential backoff
      final exponentialDelay = baseDelay.inMilliseconds * 
          pow(backoffMultiplier, attemptNumber - 1);
      delay = Duration(milliseconds: exponentialDelay.round());
    }
    
    // Apply maximum delay limit
    if (delay > maxDelay) {
      delay = maxDelay;
    }
    
    // Add jitter to prevent thundering herd
    if (jitterFactor > 0) {
      final jitter = delay.inMilliseconds * jitterFactor * (Random().nextDouble() - 0.5);
      delay = Duration(milliseconds: (delay.inMilliseconds + jitter).round());
    }
    
    // Ensure minimum delay
    if (delay < const Duration(milliseconds: 100)) {
      delay = const Duration(milliseconds: 100);
    }
    
    return delay;
  }

  /// Determines if an error should be retried
  bool _shouldRetry(dynamic error, int attemptNumber) {
    // Don't retry if we've exceeded max attempts
    if (attemptNumber > maxRetries) {
      return false;
    }
    
    // Use custom retry condition if provided
    if (retryCondition != null) {
      return retryCondition!(error);
    }
    
    // Use default retry logic
    return SyncErrorHandler.isRetryableError(error);
  }

  /// Creates a copy of this policy with modified parameters
  RetryPolicy copyWith({
    int? maxRetries,
    Duration? baseDelay,
    Duration? maxDelay,
    double? backoffMultiplier,
    double? jitterFactor,
    bool Function(dynamic error)? retryCondition,
  }) {
    return RetryPolicy(
      maxRetries: maxRetries ?? this.maxRetries,
      baseDelay: baseDelay ?? this.baseDelay,
      maxDelay: maxDelay ?? this.maxDelay,
      backoffMultiplier: backoffMultiplier ?? this.backoffMultiplier,
      jitterFactor: jitterFactor ?? this.jitterFactor,
      retryCondition: retryCondition ?? this.retryCondition,
    );
  }
}

/// Circuit breaker pattern implementation for repeated failures
class CircuitBreaker {
  final int failureThreshold;
  final Duration timeout;
  final Duration resetTimeout;
  
  int _failureCount = 0;
  DateTime? _lastFailureTime;
  CircuitBreakerState _state = CircuitBreakerState.closed;

  CircuitBreaker({
    this.failureThreshold = 5,
    this.timeout = const Duration(seconds: 30),
    this.resetTimeout = const Duration(minutes: 1),
  });

  CircuitBreakerState get state => _state;
  int get failureCount => _failureCount;

  /// Executes an operation through the circuit breaker
  Future<T> execute<T>(Future<T> Function() operation) async {
    if (_state == CircuitBreakerState.open) {
      if (_shouldAttemptReset()) {
        _state = CircuitBreakerState.halfOpen;
      } else {
        throw CircuitBreakerOpenException(
          'Circuit breaker is open. Last failure: $_lastFailureTime',
        );
      }
    }

    try {
      final result = await operation().timeout(timeout);
      _onSuccess();
      return result;
    } catch (error) {
      _onFailure();
      rethrow;
    }
  }

  /// Resets the circuit breaker to closed state
  void reset() {
    _failureCount = 0;
    _lastFailureTime = null;
    _state = CircuitBreakerState.closed;
  }

  void _onSuccess() {
    _failureCount = 0;
    _state = CircuitBreakerState.closed;
  }

  void _onFailure() {
    _failureCount++;
    _lastFailureTime = DateTime.now();
    
    if (_failureCount >= failureThreshold) {
      _state = CircuitBreakerState.open;
    }
  }

  bool _shouldAttemptReset() {
    if (_lastFailureTime == null) return true;
    return DateTime.now().difference(_lastFailureTime!) > resetTimeout;
  }
}

enum CircuitBreakerState { closed, open, halfOpen }

/// Exception thrown when circuit breaker is open
class CircuitBreakerOpenException extends SyncException {
  const CircuitBreakerOpenException(String message) : super(message);
}

/// Wrapper for retry operation results
class RetryResult<T> {
  final bool success;
  final T? result;
  final dynamic error;
  final List<RetryAttempt> attempts;
  final Duration totalDuration;
  final String? operationName;

  const RetryResult({
    required this.success,
    this.result,
    this.error,
    required this.attempts,
    required this.totalDuration,
    this.operationName,
  });

  static RetryResult<T> withSuccess<T>({
    required T result,
    required List<RetryAttempt> attempts,
    required Duration totalDuration,
    String? operationName,
  }) {
    return RetryResult<T>(
      success: true,
      result: result,
      attempts: attempts,
      totalDuration: totalDuration,
      operationName: operationName,
    );
  }

  static RetryResult<T> withFailure<T>({
    required dynamic error,
    required List<RetryAttempt> attempts,
    required Duration totalDuration,
    String? operationName,
  }) {
    return RetryResult<T>(
      success: false,
      error: error,
      attempts: attempts,
      totalDuration: totalDuration,
      operationName: operationName,
    );
  }

  int get attemptCount => attempts.length;
  int get successfulAttempts => attempts.where((a) => a.success).length;
  int get failedAttempts => attempts.where((a) => !a.success).length;
  
  Duration get totalRetryDelay => attempts
      .where((a) => a.retryDelay != null)
      .fold(Duration.zero, (sum, a) => sum + a.retryDelay!);

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'operation_name': operationName,
      'attempt_count': attemptCount,
      'successful_attempts': successfulAttempts,
      'failed_attempts': failedAttempts,
      'total_duration_ms': totalDuration.inMilliseconds,
      'total_retry_delay_ms': totalRetryDelay.inMilliseconds,
      'error': error?.toString(),
      'attempts': attempts.map((a) => a.toJson()).toList(),
    };
  }
}

/// Represents a single retry attempt
class RetryAttempt {
  final int attemptNumber;
  final DateTime timestamp;
  final bool success;
  final dynamic error;
  final Duration duration;
  final Duration? retryDelay;

  const RetryAttempt({
    required this.attemptNumber,
    required this.timestamp,
    required this.success,
    this.error,
    required this.duration,
    this.retryDelay,
  });

  RetryAttempt copyWith({
    int? attemptNumber,
    DateTime? timestamp,
    bool? success,
    dynamic error,
    Duration? duration,
    Duration? retryDelay,
  }) {
    return RetryAttempt(
      attemptNumber: attemptNumber ?? this.attemptNumber,
      timestamp: timestamp ?? this.timestamp,
      success: success ?? this.success,
      error: error ?? this.error,
      duration: duration ?? this.duration,
      retryDelay: retryDelay ?? this.retryDelay,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'attempt_number': attemptNumber,
      'timestamp': timestamp.toIso8601String(),
      'success': success,
      'error': error?.toString(),
      'duration_ms': duration.inMilliseconds,
      'retry_delay_ms': retryDelay?.inMilliseconds,
    };
  }
}

/// Intelligent retry coordinator that adapts based on error patterns
class IntelligentRetryCoordinator {
  final Map<Type, RetryPolicy> _errorPolicies = {};
  final Map<String, CircuitBreaker> _circuitBreakers = {};
  final Map<Type, int> _errorCounts = {};
  final Map<Type, DateTime> _lastErrorTimes = {};

  /// Executes an operation with intelligent retry based on error history
  Future<T> executeWithIntelligentRetry<T>(
    Future<T> Function() operation, {
    String? operationName,
    String? circuitBreakerKey,
  }) async {
    final policy = _getAdaptivePolicy();
    
    if (circuitBreakerKey != null) {
      final circuitBreaker = _getCircuitBreaker(circuitBreakerKey);
      return await circuitBreaker.execute(() => 
          policy.executeWithRetry(operation, operationName: operationName));
    } else {
      return await policy.executeWithRetry(operation, operationName: operationName);
    }
  }

  /// Records an error for adaptive policy adjustment
  void recordError(dynamic error) {
    final errorType = error.runtimeType;
    _errorCounts[errorType] = (_errorCounts[errorType] ?? 0) + 1;
    _lastErrorTimes[errorType] = DateTime.now();
    
    // Adjust policy based on error frequency
    _adjustPolicyForErrorType(errorType);
  }

  /// Gets or creates a circuit breaker for the given key
  CircuitBreaker _getCircuitBreaker(String key) {
    return _circuitBreakers.putIfAbsent(key, () => CircuitBreaker());
  }

  /// Gets an adaptive retry policy based on recent error patterns
  RetryPolicy _getAdaptivePolicy() {
    // If we have frequent network errors, use more aggressive retry
    final networkErrorCount = _errorCounts[NetworkException] ?? 0;
    final recentNetworkErrors = _isRecentError(NetworkException);
    
    if (networkErrorCount > 5 && recentNetworkErrors) {
      return RetryPolicy.aggressive;
    }
    
    // If we have authentication errors, use conservative retry
    final authErrorCount = _errorCounts[AuthenticationException] ?? 0;
    if (authErrorCount > 2) {
      return RetryPolicy.conservative;
    }
    
    return RetryPolicy.network; // Default
  }

  void _adjustPolicyForErrorType(Type errorType) {
    final errorCount = _errorCounts[errorType] ?? 0;
    
    if (errorType == NetworkException && errorCount > 3) {
      // Increase retry attempts for frequent network errors
      _errorPolicies[errorType] = RetryPolicy.network.copyWith(
        maxRetries: 5,
        baseDelay: const Duration(seconds: 1),
      );
    } else if (errorType == AuthenticationException && errorCount > 1) {
      // Reduce retry attempts for auth errors
      _errorPolicies[errorType] = RetryPolicy.conservative.copyWith(
        maxRetries: 1,
      );
    }
  }

  bool _isRecentError(Type errorType) {
    final lastError = _lastErrorTimes[errorType];
    if (lastError == null) return false;
    
    return DateTime.now().difference(lastError) < const Duration(minutes: 5);
  }

  /// Resets error tracking for a specific error type
  void resetErrorTracking(Type errorType) {
    _errorCounts.remove(errorType);
    _lastErrorTimes.remove(errorType);
    _errorPolicies.remove(errorType);
  }

  /// Resets all error tracking
  void resetAllErrorTracking() {
    _errorCounts.clear();
    _lastErrorTimes.clear();
    _errorPolicies.clear();
    _circuitBreakers.values.forEach((cb) => cb.reset());
  }

  /// Gets error statistics
  Map<String, dynamic> getErrorStatistics() {
    return {
      'error_counts': _errorCounts.map((k, v) => MapEntry(k.toString(), v)),
      'last_error_times': _lastErrorTimes.map((k, v) => MapEntry(k.toString(), v.toIso8601String())),
      'circuit_breaker_states': _circuitBreakers.map((k, v) => MapEntry(k, v.state.toString())),
    };
  }
}