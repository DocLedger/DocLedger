import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';

import '../../../../lib/core/sync/models/sync_exceptions.dart';
import '../../../../lib/core/sync/services/offline_handler.dart';
import '../../../../lib/core/connectivity/services/connectivity_service.dart';

import 'offline_handler_test.mocks.dart';

@GenerateMocks([ConnectivityService])
void main() {
  group('OfflineHandler', () {
    late OfflineHandler offlineHandler;
    late MockConnectivityService mockConnectivityService;
    late StreamController<bool> connectivityController;

    setUp(() {
      mockConnectivityService = MockConnectivityService();
      connectivityController = StreamController<bool>.broadcast();
      
      when(mockConnectivityService.connectivityStream)
          .thenAnswer((_) => connectivityController.stream);
      
      offlineHandler = OfflineHandler(mockConnectivityService);
    });

    tearDown(() {
      connectivityController.close();
      offlineHandler.dispose();
    });

    group('queueOperation', () {
      test('should queue operation and update status', () async {
        when(mockConnectivityService.isConnected()).thenAnswer((_) async => false);

        final operation = PendingOperation(
          id: 'test_op',
          type: OperationType.sync,
          operation: () async => 'result',
          timestamp: DateTime.now(),
        );

        await offlineHandler.queueOperation(operation);

        expect(offlineHandler.pendingOperationsCount, 1);
      });

      test('should emit status update when operation is queued', () async {
        when(mockConnectivityService.isConnected()).thenAnswer((_) async => false);

        final statusStream = offlineHandler.statusStream;
        final statusFuture = statusStream.first;

        final operation = PendingOperation(
          id: 'test_op',
          type: OperationType.sync,
          operation: () async => 'result',
          timestamp: DateTime.now(),
        );

        await offlineHandler.queueOperation(operation);

        final status = await statusFuture;
        expect(status.isOnline, false);
        expect(status.pendingOperations, 1);
      });
    });

    group('executePendingOperations', () {
      test('should execute all pending operations when online', () async {
        var executionCount = 0;
        final operations = [
          PendingOperation(
            id: 'op1',
            type: OperationType.sync,
            operation: () async {
              executionCount++;
              return 'result1';
            },
            timestamp: DateTime.now(),
          ),
          PendingOperation(
            id: 'op2',
            type: OperationType.sync,
            operation: () async {
              executionCount++;
              return 'result2';
            },
            timestamp: DateTime.now(),
          ),
        ];

        for (final op in operations) {
          await offlineHandler.queueOperation(operation);
        }

        final results = await offlineHandler.executePendingOperations();

        expect(results.length, 2);
        expect(executionCount, 2);
        expect(offlineHandler.pendingOperationsCount, 0);
        expect(results.every((r) => r.success), true);
      });

      test('should handle operation failures and re-queue retryable errors', () async {
        final retryableError = NetworkException(
          'Network timeout',
          NetworkErrorType.timeout,
        );

        final nonRetryableError = NetworkException(
          'Authentication failed',
          NetworkErrorType.authenticationFailed,
        );

        final operations = [
          PendingOperation(
            id: 'retryable_op',
            type: OperationType.sync,
            operation: () async => throw retryableError,
            timestamp: DateTime.now(),
          ),
          PendingOperation(
            id: 'non_retryable_op',
            type: OperationType.sync,
            operation: () async => throw nonRetryableError,
            timestamp: DateTime.now(),
          ),
        ];

        for (final op in operations) {
          await offlineHandler.queueOperation(operation);
        }

        final results = await offlineHandler.executePendingOperations();

        expect(results.length, 2);
        expect(results.every((r) => !r.success), true);
        
        // Retryable error should be re-queued
        expect(offlineHandler.pendingOperationsCount, 1);
      });

      test('should return empty list when no pending operations', () async {
        final results = await offlineHandler.executePendingOperations();
        expect(results, isEmpty);
      });
    });

    group('handleOfflineOperation', () {
      test('should execute online operation when connected', () async {
        when(mockConnectivityService.isConnected()).thenAnswer((_) async => true);

        var onlineExecuted = false;
        var offlineExecuted = false;

        final result = await offlineHandler.handleOfflineOperation<String>(
          'test_op',
          () async {
            onlineExecuted = true;
            return 'online_result';
          },
          () {
            offlineExecuted = true;
            return 'offline_result';
          },
        );

        expect(result, 'online_result');
        expect(onlineExecuted, true);
        expect(offlineExecuted, false);
        expect(offlineHandler.pendingOperationsCount, 0);
      });

      test('should execute offline fallback when not connected', () async {
        when(mockConnectivityService.isConnected()).thenAnswer((_) async => false);

        var onlineExecuted = false;
        var offlineExecuted = false;

        final result = await offlineHandler.handleOfflineOperation<String>(
          'test_op',
          () async {
            onlineExecuted = true;
            return 'online_result';
          },
          () {
            offlineExecuted = true;
            return 'offline_result';
          },
        );

        expect(result, 'offline_result');
        expect(onlineExecuted, false);
        expect(offlineExecuted, true);
        expect(offlineHandler.pendingOperationsCount, 1);
      });

      test('should fallback to offline when online operation fails with network error', () async {
        when(mockConnectivityService.isConnected()).thenAnswer((_) async => true);

        final networkError = NetworkException(
          'Connection failed',
          NetworkErrorType.connectionRefused,
        );

        var offlineExecuted = false;

        final result = await offlineHandler.handleOfflineOperation<String>(
          'test_op',
          () async => throw networkError,
          () {
            offlineExecuted = true;
            return 'offline_result';
          },
        );

        expect(result, 'offline_result');
        expect(offlineExecuted, true);
        expect(offlineHandler.pendingOperationsCount, 1);
      });

      test('should rethrow non-network errors', () async {
        when(mockConnectivityService.isConnected()).thenAnswer((_) async => true);

        final nonNetworkError = Exception('Non-network error');

        expect(
          () => offlineHandler.handleOfflineOperation<String>(
            'test_op',
            () async => throw nonNetworkError,
            () => 'offline_result',
          ),
          throwsA(nonNetworkError),
        );
      });
    });

    group('getOfflineErrorMessage', () {
      test('should return appropriate message for NetworkException types', () {
        final testCases = [
          (
            NetworkException('No internet', NetworkErrorType.noInternet),
            'No internet connection. Changes will be synced when connection is restored.'
          ),
          (
            NetworkException('Timeout', NetworkErrorType.timeout),
            'Connection timeout. Your changes are saved locally and will be synced later.'
          ),
          (
            NetworkException('Server error', NetworkErrorType.serverError),
            'Server temporarily unavailable. Working in offline mode.'
          ),
          (
            NetworkException('Rate limited', NetworkErrorType.rateLimited),
            'Rate limited. Your changes are queued and will be synced shortly.'
          ),
        ];

        for (final (error, expectedMessage) in testCases) {
          final message = offlineHandler.getOfflineErrorMessage(error);
          expect(message, expectedMessage);
        }
      });

      test('should return appropriate message for AuthenticationException', () {
        final error = AuthenticationException(
          'Token expired',
          AuthErrorType.tokenExpired,
        );

        final message = offlineHandler.getOfflineErrorMessage(error);
        expect(message, 'Authentication required. Your changes are saved locally.');
      });

      test('should return generic message for unknown errors', () {
        final error = Exception('Unknown error');

        final message = offlineHandler.getOfflineErrorMessage(error);
        expect(message, 'Working in offline mode. Changes will be synced when possible.');
      });
    });

    group('canContinueOffline', () {
      test('should return true for offline-capable operations', () {
        final offlineOperations = [
          'create_patient',
          'update_patient',
          'create_visit',
          'update_visit',
          'create_payment',
          'update_payment',
          'view_data',
          'search_data',
        ];

        for (final operation in offlineOperations) {
          expect(offlineHandler.canContinueOffline(operation), true,
              reason: 'Operation $operation should work offline');
        }
      });

      test('should return false for online-only operations', () {
        final onlineOnlyOperations = [
          'sync_data',
          'backup_data',
          'restore_data',
          'upload_file',
        ];

        for (final operation in onlineOnlyOperations) {
          expect(offlineHandler.canContinueOffline(operation), false,
              reason: 'Operation $operation should not work offline');
        }
      });
    });

    group('getOfflineCapabilities', () {
      test('should return correct offline capabilities', () {
        final capabilities = offlineHandler.getOfflineCapabilities();

        expect(capabilities.canCreateRecords, true);
        expect(capabilities.canUpdateRecords, true);
        expect(capabilities.canViewRecords, true);
        expect(capabilities.canSearchRecords, true);
        expect(capabilities.canBackupData, false);
        expect(capabilities.canSyncData, false);
        expect(capabilities.canRestoreData, false);
        expect(capabilities.estimatedOfflineDays, 30);
      });
    });

    group('connectivity changes', () {
      test('should execute pending operations when connectivity is restored', () async {
        // Start offline
        when(mockConnectivityService.isConnected()).thenAnswer((_) async => false);

        var executionCount = 0;
        final operation = PendingOperation(
          id: 'test_op',
          type: OperationType.sync,
          operation: () async {
            executionCount++;
            return 'result';
          },
          timestamp: DateTime.now(),
        );

        await offlineHandler.queueOperation(operation);
        expect(offlineHandler.pendingOperationsCount, 1);

        // Simulate connectivity restored
        connectivityController.add(true);
        
        // Wait for operations to execute
        await Future.delayed(const Duration(milliseconds: 100));

        expect(executionCount, 1);
        expect(offlineHandler.pendingOperationsCount, 0);
      });

      test('should emit status updates on connectivity changes', () async {
        final statusUpdates = <OfflineStatus>[];
        offlineHandler.statusStream.listen(statusUpdates.add);

        // Simulate connectivity changes
        connectivityController.add(false);
        await Future.delayed(const Duration(milliseconds: 10));
        
        connectivityController.add(true);
        await Future.delayed(const Duration(milliseconds: 10));

        expect(statusUpdates.length, greaterThanOrEqualTo(2));
        expect(statusUpdates.last.isOnline, true);
      });
    });

    group('utility methods', () {
      test('should track oldest pending operation', () async {
        final now = DateTime.now();
        final operations = [
          PendingOperation(
            id: 'op1',
            type: OperationType.sync,
            operation: () async => 'result',
            timestamp: now.subtract(const Duration(minutes: 5)),
          ),
          PendingOperation(
            id: 'op2',
            type: OperationType.sync,
            operation: () async => 'result',
            timestamp: now.subtract(const Duration(minutes: 2)),
          ),
        ];

        for (final op in operations) {
          await offlineHandler.queueOperation(operation);
        }

        final oldest = offlineHandler.oldestPendingOperation;
        expect(oldest, isNotNull);
        expect(oldest!.isBefore(now.subtract(const Duration(minutes: 4))), true);
      });

      test('should return null for oldest pending operation when queue is empty', () {
        expect(offlineHandler.oldestPendingOperation, isNull);
      });

      test('should clear all pending operations', () async {
        final operation = PendingOperation(
          id: 'test_op',
          type: OperationType.sync,
          operation: () async => 'result',
          timestamp: DateTime.now(),
        );

        await offlineHandler.queueOperation(operation);
        expect(offlineHandler.pendingOperationsCount, 1);

        offlineHandler.clearPendingOperations();
        expect(offlineHandler.pendingOperationsCount, 0);
      });
    });
  });
}