import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import '../../../../lib/core/sync/models/sync_exceptions.dart';
import '../../../../lib/core/sync/services/retry_policy.dart';

void main() {
  group('RetryPolicy', () {
    group('executeWithRetry', () {
      test('should succeed on first attempt', () async {
        final policy = RetryPolicy(maxRetries: 3);
        var attemptCount = 0;

        final result = await policy.executeWithRetry(() async {
          attemptCount++;
          return 'success';
        });

        expect(result, 'success');
        expect(attemptCount, 1);
      });

      test('should retry on retryable errors', () async {
        final policy = RetryPolicy(
          maxRetries: 3,
          baseDelay: Duration(milliseconds: 10),
        );
        var attemptCount = 0;

        final result = await policy.executeWithRetry(() async {
          attemptCount++;
          if (attemptCount < 3) {
            throw NetworkException('Network error', NetworkErrorType.timeout);
          }
          return 'success';
        });

        expect(result, 'success');
        expect(attemptCount, 3);
      });

      test('should not retry on non-retryable errors', () async {
        final policy = RetryPolicy(maxRetries: 3);
        var attemptCount = 0;

        expect(
          () => policy.executeWithRetry(() async {
            attemptCount++;
            throw NetworkException('Auth failed', NetworkErrorType.authenticationFailed);
          }),
          throwsA(isA<NetworkException>()),
        );

        expect(attemptCount, 1);
      });

      test('should respect max retry limit', () async {
        final policy = RetryPolicy(
          maxRetries: 2,
          baseDelay: Duration(milliseconds: 10),
        );
        var attemptCount = 0;

        expect(
          () => policy.executeWithRetry(() async {
            attemptCount++;
            throw NetworkException('Network error', NetworkErrorType.timeout);
          }),
          throwsA(isA<NetworkException>()),
        );

        expect(attemptCount, 3); // Initial attempt + 2 retries
      });

      test('should call onRetry callback', () async {
        final policy = RetryPolicy(
          maxRetries: 2,
          baseDelay: Duration(milliseconds: 10),
        );
        final retryCallbacks = <int>[];

        try {
          await policy.executeWithRetry(
            () async => throw NetworkException('Network error', NetworkErrorType.timeout),
            onRetry: (attempt, error, delay) {
              retryCallbacks.add(attempt);
            },
          );
        } catch (e) {
          // Expected to fail
        }

        expect(retryCallbacks, [1, 2]);
      });

      test('should apply exponential backoff', () async {
        final policy = RetryPolicy(
          maxRetries: 3,
          baseDelay: Duration(milliseconds: 100),
          backoffMultiplier: 2.0,
          jitterFactor: 0.0, // No jitter for predictable testing
        );
        final delays = <Duration>[];
        final stopwatch = Stopwatch();

        try {
          await policy.executeWithRetry(
            () async => throw NetworkException('Network error', NetworkErrorType.timeout),
            onRetry: (attempt, error, delay) {
              delays.add(delay);
            },
          );
        } catch (e) {
          // Expected to fail
        }

        expect(delays.length, 3);
        // Note: Actual delays might vary due to error-specific delay calculation
        expect(delays[0].inMilliseconds, greaterThanOrEqualTo(100));
        expect(delays[1].inMilliseconds, greaterThan(delays[0].inMilliseconds));
        expect(delays[2].inMilliseconds, greaterThan(delays[1].inMilliseconds));
      });

      test('should respect maximum delay', () async {
        final policy = RetryPolicy(
          maxRetries: 5,
          baseDelay: Duration(seconds: 1),
          maxDelay: Duration(seconds: 2),
          backoffMultiplier: 10.0,
          jitterFactor: 0.0,
        );
        final delays = <Duration>[];

        try {
          await policy.executeWithRetry(
            () async => throw NetworkException('Network error', NetworkErrorType.timeout),
            onRetry: (attempt, error, delay) {
              delays.add(delay);
            },
          );
        } catch (e) {
          // Expected to fail
        }

        // All delays should be capped at maxDelay
        for (final delay in delays) {
          expect(delay.inMilliseconds, lessThanOrEqualTo(policy.maxDelay.inMilliseconds));
        }
      });
    });

    group('executeWithRetryResult', () {
      test('should return success result with attempt details', () async {
        final policy = RetryPolicy(
          maxRetries: 3,
          baseDelay: Duration(milliseconds: 10),
        );
        var attemptCount = 0;

        final result = await policy.executeWithRetryResult(() async {
          attemptCount++;
          if (attemptCount < 2) {
            throw NetworkException('Network error', NetworkErrorType.timeout);
          }
          return 'success';
        });

        expect(result.success, true);
        expect(result.result, 'success');
        expect(result.attemptCount, 2);
        expect(result.successfulAttempts, 1);
        expect(result.failedAttempts, 1);
        expect(result.totalDuration.inMilliseconds, greaterThan(0));
      });

      test('should return failure result when all attempts fail', () async {
        final policy = RetryPolicy(
          maxRetries: 2,
          baseDelay: Duration(milliseconds: 10),
        );

        final result = await policy.executeWithRetryResult(() async {
          throw NetworkException('Network error', NetworkErrorType.timeout);
        });

        expect(result.success, false);
        expect(result.result, isNull);
        expect(result.error, isA<NetworkException>());
        expect(result.attemptCount, 3); // Initial + 2 retries
        expect(result.successfulAttempts, 0);
        expect(result.failedAttempts, 3);
      });

      test('should include operation name in result', () async {
        final policy = RetryPolicy(maxRetries: 1);

        final result = await policy.executeWithRetryResult(
          () async => 'success',
          operationName: 'test_operation',
        );

        expect(result.operationName, 'test_operation');
      });
    });

    group('predefined policies', () {
      test('should have correct network policy configuration', () {
        expect(RetryPolicy.network.maxRetries, 3);
        expect(RetryPolicy.network.baseDelay, Duration(seconds: 2));
        expect(RetryPolicy.network.maxDelay, Duration(minutes: 2));
        expect(RetryPolicy.network.backoffMultiplier, 2.0);
      });

      test('should have correct aggressive policy configuration', () {
        expect(RetryPolicy.aggressive.maxRetries, 5);
        expect(RetryPolicy.aggressive.baseDelay, Duration(seconds: 1));
        expect(RetryPolicy.aggressive.maxDelay, Duration(minutes: 10));
        expect(RetryPolicy.aggressive.backoffMultiplier, 1.5);
      });

      test('should have correct conservative policy configuration', () {
        expect(RetryPolicy.conservative.maxRetries, 2);
        expect(RetryPolicy.conservative.baseDelay, Duration(seconds: 5));
        expect(RetryPolicy.conservative.maxDelay, Duration(minutes: 1));
        expect(RetryPolicy.conservative.backoffMultiplier, 3.0);
      });
    });

    group('forErrorType', () {
      test('should return appropriate policy for NetworkException', () {
        final policy = RetryPolicy.forErrorType(NetworkException);
        expect(policy.maxRetries, 4);
        expect(policy.baseDelay, Duration(seconds: 2));
        expect(policy.maxDelay, Duration(minutes: 5));
      });

      test('should return appropriate policy for AuthenticationException', () {
        final policy = RetryPolicy.forErrorType(AuthenticationException);
        expect(policy.maxRetries, 2);
        expect(policy.baseDelay, Duration(seconds: 5));
        expect(policy.maxDelay, Duration(seconds: 30));
      });

      test('should return appropriate policy for DataIntegrityException', () {
        final policy = RetryPolicy.forErrorType(DataIntegrityException);
        expect(policy.maxRetries, 1);
        expect(policy.baseDelay, Duration(seconds: 1));
        expect(policy.maxDelay, Duration(seconds: 5));
      });

      test('should return default policy for unknown error type', () {
        final policy = RetryPolicy.forErrorType(Exception);
        expect(policy.maxRetries, 3); // Default
      });
    });

    group('custom retry condition', () {
      test('should use custom retry condition when provided', () async {
        final policy = RetryPolicy(
          maxRetries: 3,
          baseDelay: Duration(milliseconds: 10),
          retryCondition: (error) => error.toString().contains('retry_me'),
        );
        var attemptCount = 0;

        // Should retry
        final result1 = await policy.executeWithRetry(() async {
          attemptCount++;
          if (attemptCount < 2) {
            throw Exception('retry_me');
          }
          return 'success';
        });

        expect(result1, 'success');
        expect(attemptCount, 2);

        // Should not retry
        attemptCount = 0;
        expect(
          () => policy.executeWithRetry(() async {
            attemptCount++;
            throw Exception('do_not_retry');
          }),
          throwsA(isA<Exception>()),
        );

        expect(attemptCount, 1);
      });
    });

    group('copyWith', () {
      test('should create copy with modified parameters', () {
        final original = RetryPolicy(
          maxRetries: 3,
          baseDelay: Duration(seconds: 1),
          maxDelay: Duration(minutes: 1),
          backoffMultiplier: 2.0,
          jitterFactor: 0.1,
        );

        final copy = original.copyWith(
          maxRetries: 5,
          baseDelay: Duration(seconds: 2),
        );

        expect(copy.maxRetries, 5);
        expect(copy.baseDelay, Duration(seconds: 2));
        expect(copy.maxDelay, original.maxDelay); // Unchanged
        expect(copy.backoffMultiplier, original.backoffMultiplier); // Unchanged
        expect(copy.jitterFactor, original.jitterFactor); // Unchanged
      });
    });
  });

  group('CircuitBreaker', () {
    test('should start in closed state', () {
      final circuitBreaker = CircuitBreaker();
      expect(circuitBreaker.state, CircuitBreakerState.closed);
      expect(circuitBreaker.failureCount, 0);
    });

    test('should execute operation when closed', () async {
      final circuitBreaker = CircuitBreaker();
      
      final result = await circuitBreaker.execute(() async => 'success');
      
      expect(result, 'success');
      expect(circuitBreaker.state, CircuitBreakerState.closed);
    });

    test('should open after failure threshold is reached', () async {
      final circuitBreaker = CircuitBreaker(
        failureThreshold: 2,
        timeout: Duration(milliseconds: 100),
      );

      // First failure
      try {
        await circuitBreaker.execute(() async => throw Exception('error'));
      } catch (e) {}
      expect(circuitBreaker.state, CircuitBreakerState.closed);
      expect(circuitBreaker.failureCount, 1);

      // Second failure - should open circuit
      try {
        await circuitBreaker.execute(() async => throw Exception('error'));
      } catch (e) {}
      expect(circuitBreaker.state, CircuitBreakerState.open);
      expect(circuitBreaker.failureCount, 2);
    });

    test('should throw CircuitBreakerOpenException when open', () async {
      final circuitBreaker = CircuitBreaker(failureThreshold: 1);

      // Cause failure to open circuit
      try {
        await circuitBreaker.execute(() async => throw Exception('error'));
      } catch (e) {}

      // Should now throw CircuitBreakerOpenException
      expect(
        () => circuitBreaker.execute(() async => 'success'),
        throwsA(isA<CircuitBreakerOpenException>()),
      );
    });

    test('should transition to half-open after reset timeout', () async {
      final circuitBreaker = CircuitBreaker(
        failureThreshold: 1,
        resetTimeout: Duration(milliseconds: 50),
      );

      // Cause failure to open circuit
      try {
        await circuitBreaker.execute(() async => throw Exception('error'));
      } catch (e) {}
      expect(circuitBreaker.state, CircuitBreakerState.open);

      // Wait for reset timeout
      await Future.delayed(Duration(milliseconds: 60));

      // Next execution should transition to half-open
      final result = await circuitBreaker.execute(() async => 'success');
      expect(result, 'success');
      expect(circuitBreaker.state, CircuitBreakerState.closed);
    });

    test('should reset failure count on success', () async {
      final circuitBreaker = CircuitBreaker(failureThreshold: 3);

      // Cause some failures
      try {
        await circuitBreaker.execute(() async => throw Exception('error'));
      } catch (e) {}
      try {
        await circuitBreaker.execute(() async => throw Exception('error'));
      } catch (e) {}
      expect(circuitBreaker.failureCount, 2);

      // Success should reset count
      await circuitBreaker.execute(() async => 'success');
      expect(circuitBreaker.failureCount, 0);
      expect(circuitBreaker.state, CircuitBreakerState.closed);
    });

    test('should handle timeout', () async {
      final circuitBreaker = CircuitBreaker(timeout: Duration(milliseconds: 50));

      expect(
        () => circuitBreaker.execute(() async {
          await Future.delayed(Duration(milliseconds: 100));
          return 'success';
        }),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('should reset manually', () async {
      final circuitBreaker = CircuitBreaker(failureThreshold: 1);

      // Cause failure to open circuit
      try {
        await circuitBreaker.execute(() async => throw Exception('error'));
      } catch (e) {}
      expect(circuitBreaker.state, CircuitBreakerState.open);

      // Manual reset
      circuitBreaker.reset();
      expect(circuitBreaker.state, CircuitBreakerState.closed);
      expect(circuitBreaker.failureCount, 0);

      // Should work normally after reset
      final result = await circuitBreaker.execute(() async => 'success');
      expect(result, 'success');
    });
  });

  group('IntelligentRetryCoordinator', () {
    late IntelligentRetryCoordinator coordinator;

    setUp(() {
      coordinator = IntelligentRetryCoordinator();
    });

    test('should execute operation successfully', () async {
      final result = await coordinator.executeWithIntelligentRetry(
        () async => 'success',
        operationName: 'test_operation',
      );

      expect(result, 'success');
    });

    test('should record and adapt to error patterns', () async {
      // Record multiple network errors
      for (int i = 0; i < 6; i++) {
        coordinator.recordError(NetworkException('Network error', NetworkErrorType.timeout));
      }

      var attemptCount = 0;
      final result = await coordinator.executeWithIntelligentRetry(() async {
        attemptCount++;
        if (attemptCount < 3) {
          throw NetworkException('Network error', NetworkErrorType.timeout);
        }
        return 'success';
      });

      expect(result, 'success');
      expect(attemptCount, 3);
    });

    test('should use circuit breaker when specified', () async {
      // First, cause failures to open circuit breaker
      for (int i = 0; i < 5; i++) {
        try {
          await coordinator.executeWithIntelligentRetry(
            () async => throw Exception('error'),
            circuitBreakerKey: 'test_circuit',
          );
        } catch (e) {}
      }

      // Circuit breaker should now be open
      expect(
        () => coordinator.executeWithIntelligentRetry(
          () async => 'success',
          circuitBreakerKey: 'test_circuit',
        ),
        throwsA(isA<CircuitBreakerOpenException>()),
      );
    });

    test('should provide error statistics', () {
      coordinator.recordError(NetworkException('Network error', NetworkErrorType.timeout));
      coordinator.recordError(AuthenticationException('Auth error', AuthErrorType.tokenExpired));
      coordinator.recordError(NetworkException('Another network error', NetworkErrorType.serverError));

      final stats = coordinator.getErrorStatistics();
      
      expect(stats['error_counts'], isA<Map>());
      expect(stats['last_error_times'], isA<Map>());
      expect(stats['circuit_breaker_states'], isA<Map>());
    });

    test('should reset error tracking', () {
      coordinator.recordError(NetworkException('Network error', NetworkErrorType.timeout));
      
      var stats = coordinator.getErrorStatistics();
      expect(stats['error_counts'], isNotEmpty);

      coordinator.resetErrorTracking(NetworkException);
      
      stats = coordinator.getErrorStatistics();
      expect(stats['error_counts'], isEmpty);
    });

    test('should reset all error tracking', () {
      coordinator.recordError(NetworkException('Network error', NetworkErrorType.timeout));
      coordinator.recordError(AuthenticationException('Auth error', AuthErrorType.tokenExpired));
      
      var stats = coordinator.getErrorStatistics();
      expect(stats['error_counts'], isNotEmpty);

      coordinator.resetAllErrorTracking();
      
      stats = coordinator.getErrorStatistics();
      expect(stats['error_counts'], isEmpty);
    });
  });

  group('RetryResult', () {
    test('should create success result correctly', () {
      final attempts = [
        RetryAttempt(
          attemptNumber: 1,
          timestamp: DateTime.now(),
          success: false,
          error: Exception('error'),
          duration: Duration(milliseconds: 100),
          retryDelay: Duration(seconds: 1),
        ),
        RetryAttempt(
          attemptNumber: 2,
          timestamp: DateTime.now(),
          success: true,
          duration: Duration(milliseconds: 50),
        ),
      ];

      final result = RetryResult.withSuccess(
        result: 'success',
        attempts: attempts,
        totalDuration: Duration(milliseconds: 200),
        operationName: 'test_op',
      );

      expect(result.success, true);
      expect(result.result, 'success');
      expect(result.attemptCount, 2);
      expect(result.successfulAttempts, 1);
      expect(result.failedAttempts, 1);
      expect(result.totalRetryDelay, Duration(seconds: 1));
    });

    test('should create failure result correctly', () {
      final attempts = [
        RetryAttempt(
          attemptNumber: 1,
          timestamp: DateTime.now(),
          success: false,
          error: Exception('error'),
          duration: Duration(milliseconds: 100),
        ),
      ];

      final result = RetryResult.withFailure(
        error: Exception('final error'),
        attempts: attempts,
        totalDuration: Duration(milliseconds: 100),
      );

      expect(result.success, false);
      expect(result.result, isNull);
      expect(result.error, isA<Exception>());
      expect(result.attemptCount, 1);
      expect(result.successfulAttempts, 0);
      expect(result.failedAttempts, 1);
    });

    test('should serialize to JSON correctly', () {
      final attempts = [
        RetryAttempt(
          attemptNumber: 1,
          timestamp: DateTime.now(),
          success: true,
          duration: Duration(milliseconds: 100),
        ),
      ];

      final result = RetryResult.withSuccess(
        result: 'success',
        attempts: attempts,
        totalDuration: Duration(milliseconds: 100),
        operationName: 'test_op',
      );

      final json = result.toJson();
      
      expect(json['success'], true);
      expect(json['operation_name'], 'test_op');
      expect(json['attempt_count'], 1);
      expect(json['successful_attempts'], 1);
      expect(json['failed_attempts'], 0);
      expect(json['total_duration_ms'], 100);
      expect(json['attempts'], isA<List>());
    });
  });

  group('RetryAttempt', () {
    test('should create attempt correctly', () {
      final timestamp = DateTime.now();
      final attempt = RetryAttempt(
        attemptNumber: 1,
        timestamp: timestamp,
        success: false,
        error: Exception('error'),
        duration: Duration(milliseconds: 100),
        retryDelay: Duration(seconds: 1),
      );

      expect(attempt.attemptNumber, 1);
      expect(attempt.timestamp, timestamp);
      expect(attempt.success, false);
      expect(attempt.error, isA<Exception>());
      expect(attempt.duration, Duration(milliseconds: 100));
      expect(attempt.retryDelay, Duration(seconds: 1));
    });

    test('should copy with modifications', () {
      final original = RetryAttempt(
        attemptNumber: 1,
        timestamp: DateTime.now(),
        success: false,
        duration: Duration(milliseconds: 100),
      );

      final copy = original.copyWith(
        success: true,
        retryDelay: Duration(seconds: 1),
      );

      expect(copy.attemptNumber, original.attemptNumber);
      expect(copy.timestamp, original.timestamp);
      expect(copy.success, true); // Modified
      expect(copy.duration, original.duration);
      expect(copy.retryDelay, Duration(seconds: 1)); // Added
    });

    test('should serialize to JSON correctly', () {
      final timestamp = DateTime.now();
      final attempt = RetryAttempt(
        attemptNumber: 1,
        timestamp: timestamp,
        success: false,
        error: Exception('error'),
        duration: Duration(milliseconds: 100),
        retryDelay: Duration(seconds: 1),
      );

      final json = attempt.toJson();
      
      expect(json['attempt_number'], 1);
      expect(json['timestamp'], timestamp.toIso8601String());
      expect(json['success'], false);
      expect(json['error'], 'Exception: error');
      expect(json['duration_ms'], 100);
      expect(json['retry_delay_ms'], 1000);
    });
  });
}