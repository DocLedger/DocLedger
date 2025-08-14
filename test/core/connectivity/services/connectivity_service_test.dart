import 'package:flutter_test/flutter_test.dart';
import 'package:doc_ledger/core/connectivity/services/connectivity_service.dart';

void main() {
  group('AppConnectivityService', () {
    test('should create instance successfully', () {
      final service = AppConnectivityService();
      expect(service, isNotNull);
      service.dispose();
    });

    test('should have default values', () {
      final service = AppConnectivityService();
      expect(service.isConnected, isFalse);
      expect(service.wifiPreferredSync, isTrue);
      expect(service.queuedOperationsCount, 0);
      service.dispose();
    });

    test('should allow changing WiFi preference', () {
      final service = AppConnectivityService();
      service.wifiPreferredSync = false;
      expect(service.wifiPreferredSync, isFalse);
      service.dispose();
    });

    test('should provide streams', () {
      final service = AppConnectivityService();
      expect(service.connectivityStream, isA<Stream<bool>>());
      expect(service.wifiStream, isA<Stream<bool>>());
      service.dispose();
    });
  });

  group('NetworkOperation', () {
    test('should create with required parameters', () {
      final operation = NetworkOperation(
        id: 'test',
        description: 'Test',
        execute: () async {},
      );

      expect(operation.id, 'test');
      expect(operation.description, 'Test');
      expect(operation.maxRetries, 3);
      expect(operation.retryCount, 0);
    });

    test('should execute successfully', () async {
      bool executed = false;
      final operation = NetworkOperation(
        id: 'test',
        description: 'Test',
        execute: () async {
          executed = true;
        },
      );

      await operation.execute();
      expect(executed, isTrue);
    });
  });
}