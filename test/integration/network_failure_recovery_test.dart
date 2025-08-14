import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';

import 'package:doc_ledger/core/sync/services/sync_service.dart';
import 'package:doc_ledger/core/cloud/services/google_drive_service.dart';
import 'package:doc_ledger/core/data/services/database_service.dart';
import 'package:doc_ledger/core/encryption/services/encryption_service.dart';
import 'package:doc_ledger/core/connectivity/services/connectivity_service.dart';
import 'package:doc_ledger/core/data/models/data_models.dart';
import 'package:doc_ledger/core/sync/models/sync_models.dart';
import 'package:doc_ledger/core/sync/models/sync_exceptions.dart';

import '../core/sync/services/sync_service_test.mocks.dart';
void main() {
  group('Network Failure Recovery Tests', () {
    late SyncService syncService;
    late MockGoogleDriveService mockDriveService;
    late MockDatabaseService mockDatabase;
    late MockEncryptionService mockEncryption;
    late MockConnectivityService mockConnectivity;

    const testClinicId = 'network_test_clinic';
    const testDeviceId = 'network_test_device';

    setUp(() {
      mockDriveService = MockGoogleDriveService();
      mockDatabase = MockDatabaseService();
      mockEncryption = MockEncryptionService();
      mockConnectivity = MockConnectivityService();

      syncService = SyncService(
        driveService: mockDriveService,
        database: mockDatabase,
        encryption: mockEncryption,
        clinicId: testClinicId,
        deviceId: testDeviceId,
      );
    });

    tearDown(() {
      syncService.dispose();
    });

    group('Connection Loss Scenarios', () {
      test('should handle connection loss during upload with retry', () async {
        // Arrange
        final testPatient = Patient(
          id: 'patient_1',
          name: 'John Doe',
          phone: '+1234567890',
          lastModified: DateTime.now(),
          deviceId: testDeviceId,
        );

        final backupData = BackupData.create(
          clinicId: testClinicId,
          deviceId: testDeviceId,
          tables: {'patients': [testPatient.toSyncJson()]},
        );

        // Mock database operations
        when(mockDatabase.getChangedRecordsSince(any))
            .thenAnswer((_) async => {'patients': [testPatient.toSyncJson()]});
        when(mockDatabase.markRecordsAsSynced(any, any))
            .thenAnswer((_) async {});

        // Mock connectivity - starts connected, then disconnects, then reconnects
        when(mockConnectivity.isConnected).thenReturn(true);
        when(mockConnectivity.connectionStream)
            .thenAnswer((_) => Stream.fromIterable([true, false, true]));

        // Mock Google Drive operations
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.getLatestBackup()).thenAnswer((_) async => null);

        // First upload attempt fails due to network error
        // Second attempt succeeds after reconnection
        when(mockDriveService.uploadBackupFile(any, any))
            .thenThrow(const NetworkException('Connection lost', NetworkErrorType.noInternet));
        when(mockDriveService.uploadBackupFile(any, any))
            .thenAnswer((_) async => 'backup_after_retry');

        // Mock encryption
        when(mockEncryption.deriveEncryptionKey(testClinicId, testDeviceId))
            .thenAnswer((_) async => 'network_test_key');
        when(mockEncryption.encryptData(any, 'network_test_key'))
            .thenAnswer((_) async => utf8.encode(jsonEncode(backupData.toJson())));

        // Act
        final result = await syncService.performIncrementalSync();

        // Assert
        expect(result.status, equals(SyncResultStatus.success));
        expect(result.syncedCounts!['patients'], equals(1));

        // Verify retry was attempted
        verify(mockDriveService.uploadBackupFile(any, any)).called(2);
      });

      test('should handle intermittent connection during download', () async {
        // Arrange
        final remoteBackupData = BackupData.create(
          clinicId: testClinicId,
          deviceId: 'remote_device',
          tables: {
            'patients': [
              {
                'id': 'remote_patient',
                'name': 'Remote Patient',
                'phone': '+9876543210',
                'last_modified': DateTime.now().millisecondsSinceEpoch,
                'device_id': 'remote_device',
              },
            ],
          },
        );

        // Mock database operations
        when(mockDatabase.getChangedRecordsSince(any))
            .thenAnswer((_) async => <String, List<Map<String, dynamic>>>{});
        when(mockDatabase.applyRemoteChanges(any))
            .thenAnswer((_) async => <SyncConflict>[]);

        // Mock connectivity
        when(mockConnectivity.isConnected).thenReturn(true);

        // Mock Google Drive operations
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.getLatestBackup())
            .thenAnswer((_) async => BackupFileInfo(
              id: 'remote_backup',
              name: 'remote_backup.enc',
              size: 1024,
              createdTime: DateTime.now().subtract(const Duration(minutes: 30)),
              modifiedTime: DateTime.now().subtract(const Duration(minutes: 30)),
            ));

        // First download attempt fails, second succeeds
        when(mockDriveService.downloadBackupFile('remote_backup'))
            .thenThrow(const NetworkException('Download interrupted', NetworkErrorType.connectionRefused));
        when(mockDriveService.downloadBackupFile('remote_backup'))
            .thenAnswer((_) async => utf8.encode(jsonEncode(remoteBackupData.toJson())));

        // Mock encryption
        when(mockEncryption.deriveEncryptionKey(testClinicId, testDeviceId))
            .thenAnswer((_) async => 'download_test_key');
        when(mockEncryption.decryptData(any, 'download_test_key'))
            .thenAnswer((_) async => remoteBackupData.toJson());

        // Act
        final result = await syncService.performIncrementalSync();

        // Assert
        expect(result.status, equals(SyncResultStatus.success));

        // Verify retry was attempted
        verify(mockDriveService.downloadBackupFile('remote_backup')).called(2);
        verify(mockDatabase.applyRemoteChanges(any)).called(1);
      });

      test('should queue operations when offline and sync when back online', () async {
        // Arrange
        final offlinePatients = [
          Patient(
            id: 'offline_patient_1',
            name: 'Offline Patient 1',
            phone: '+1111111111',
            lastModified: DateTime.now().subtract(const Duration(hours: 2)),
            deviceId: testDeviceId,
          ),
          Patient(
            id: 'offline_patient_2',
            name: 'Offline Patient 2',
            phone: '+2222222222',
            lastModified: DateTime.now().subtract(const Duration(hours: 1)),
            deviceId: testDeviceId,
          ),
        ];

        final queuedBackupData = BackupData.create(
          clinicId: testClinicId,
          deviceId: testDeviceId,
          tables: {
            'patients': offlinePatients.map((p) => p.toSyncJson()).toList(),
          },
        );

        // Mock database operations
        when(mockDatabase.getChangedRecordsSince(any))
            .thenAnswer((_) async => {
          'patients': offlinePatients.map((p) => p.toSyncJson()).toList(),
        });
        when(mockDatabase.markRecordsAsSynced(any, any))
            .thenAnswer((_) async {});

        // Mock connectivity - starts offline, then comes online
        when(mockConnectivity.isConnected).thenReturn(false);
        when(mockConnectivity.connectionStream)
            .thenAnswer((_) => Stream.fromIterable([false, false, true]));

        // Mock Google Drive operations
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.getLatestBackup()).thenAnswer((_) async => null);
        when(mockDriveService.uploadBackupFile(any, any))
            .thenAnswer((_) async => 'queued_backup_id');

        // Mock encryption
        when(mockEncryption.deriveEncryptionKey(testClinicId, testDeviceId))
            .thenAnswer((_) async => 'offline_test_key');
        when(mockEncryption.encryptData(any, 'offline_test_key'))
            .thenAnswer((_) async => utf8.encode(jsonEncode(queuedBackupData.toJson())));

        // Act - First sync attempt while offline (should queue)
        var result = await syncService.performIncrementalSync();

        // Assert - Should indicate deferred due to no connection
        expect(result.status, equals(SyncResultStatus.partial));

        // Simulate coming back online
        when(mockConnectivity.isConnected).thenReturn(true);

        // Act - Second sync attempt when back online
        result = await syncService.performIncrementalSync();

        // Assert - Should now succeed
        expect(result.status, equals(SyncResultStatus.success));
        expect(result.syncedCounts!['patients'], equals(2));

        // Verify upload was attempted only when online
        verify(mockDriveService.uploadBackupFile(any, any)).called(1);
      });
    });

    group('Timeout and Rate Limiting', () {
      test('should handle API rate limiting with exponential backoff', () async {
        // Arrange
        final testPatient = Patient(
          id: 'rate_limit_patient',
          name: 'Rate Limit Test',
          phone: '+5555555555',
          lastModified: DateTime.now(),
          deviceId: testDeviceId,
        );

        final backupData = BackupData.create(
          clinicId: testClinicId,
          deviceId: testDeviceId,
          tables: {'patients': [testPatient.toSyncJson()]},
        );

        // Mock database operations
        when(mockDatabase.getChangedRecordsSince(any))
            .thenAnswer((_) async => {'patients': [testPatient.toSyncJson()]});
        when(mockDatabase.markRecordsAsSynced(any, any))
            .thenAnswer((_) async {});

        // Mock connectivity
        when(mockConnectivity.isConnected).thenReturn(true);

        // Mock Google Drive operations
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.getLatestBackup()).thenAnswer((_) async => null);

        // Simulate rate limiting followed by success
        var callCount = 0;
        when(mockDriveService.uploadBackupFile(any, any)).thenAnswer((_) async {
          callCount++;
          if (callCount <= 2) {
            throw const NetworkException('Rate limit exceeded', NetworkErrorType.rateLimited);
          }
          return 'rate_limit_backup_id';
        });

        // Mock encryption
        when(mockEncryption.deriveEncryptionKey(testClinicId, testDeviceId))
            .thenAnswer((_) async => 'rate_limit_key');
        when(mockEncryption.encryptData(any, 'rate_limit_key'))
            .thenAnswer((_) async => utf8.encode(jsonEncode(backupData.toJson())));

        // Act
        final stopwatch = Stopwatch()..start();
        final result = await syncService.performIncrementalSync();
        stopwatch.stop();

        // Assert
        expect(result.status, equals(SyncResultStatus.success));
        expect(result.syncedCounts!['patients'], equals(1));

        // Should have taken some time due to backoff delays
        expect(stopwatch.elapsedMilliseconds, greaterThan(1000)); // At least 1 second

        // Verify multiple attempts were made
        verify(mockDriveService.uploadBackupFile(any, any)).called(3);
      });

      test('should handle request timeouts with retry', () async {
        // Arrange
        final testVisit = Visit(
          id: 'timeout_visit',
          patientId: 'timeout_patient',
          visitDate: DateTime.now(),
          diagnosis: 'Timeout Test',
          lastModified: DateTime.now(),
          deviceId: testDeviceId,
        );

        final backupData = BackupData.create(
          clinicId: testClinicId,
          deviceId: testDeviceId,
          tables: {'visits': [testVisit.toSyncJson()]},
        );

        // Mock database operations
        when(mockDatabase.getChangedRecordsSince(any))
            .thenAnswer((_) async => {'visits': [testVisit.toSyncJson()]});
        when(mockDatabase.markRecordsAsSynced(any, any))
            .thenAnswer((_) async {});

        // Mock connectivity
        when(mockConnectivity.isConnected).thenReturn(true);

        // Mock Google Drive operations
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.getLatestBackup()).thenAnswer((_) async => null);

        // Simulate timeout followed by success
        var timeoutCallCount = 0;
        when(mockDriveService.uploadBackupFile(any, any)).thenAnswer((_) async {
          timeoutCallCount++;
          if (timeoutCallCount == 1) {
            throw const NetworkException('Request timeout', NetworkErrorType.timeout);
          }
          return 'timeout_backup_id';
        });

        // Mock encryption
        when(mockEncryption.deriveEncryptionKey(testClinicId, testDeviceId))
            .thenAnswer((_) async => 'timeout_key');
        when(mockEncryption.encryptData(any, 'timeout_key'))
            .thenAnswer((_) async => utf8.encode(jsonEncode(backupData.toJson())));

        // Act
        final result = await syncService.performIncrementalSync();

        // Assert
        expect(result.status, equals(SyncResultStatus.success));
        expect(result.syncedCounts!['visits'], equals(1));

        // Verify retry was attempted
        verify(mockDriveService.uploadBackupFile(any, any)).called(2);
      });
    });

    group('Server Error Recovery', () {
      test('should handle server errors with appropriate retry strategy', () async {
        // Arrange
        final testPayment = Payment(
          id: 'server_error_payment',
          patientId: 'server_error_patient',
          amount: 100.0,
          paymentDate: DateTime.now(),
          paymentMethod: 'cash',
          lastModified: DateTime.now(),
          deviceId: testDeviceId,
        );

        final backupData = BackupData.create(
          clinicId: testClinicId,
          deviceId: testDeviceId,
          tables: {'payments': [testPayment.toSyncJson()]},
        );

        // Mock database operations
        when(mockDatabase.getChangedRecordsSince(any))
            .thenAnswer((_) async => {'payments': [testPayment.toSyncJson()]});
        when(mockDatabase.markRecordsAsSynced(any, any))
            .thenAnswer((_) async {});

        // Mock connectivity
        when(mockConnectivity.isConnected).thenReturn(true);

        // Mock Google Drive operations
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.getLatestBackup()).thenAnswer((_) async => null);

        // Simulate server error followed by success
        var serverErrorCallCount = 0;
        when(mockDriveService.uploadBackupFile(any, any)).thenAnswer((_) async {
          serverErrorCallCount++;
          if (serverErrorCallCount == 1) {
            throw const NetworkException('Internal server error', NetworkErrorType.serverError);
          }
          return 'server_error_backup_id';
        });

        // Mock encryption
        when(mockEncryption.deriveEncryptionKey(testClinicId, testDeviceId))
            .thenAnswer((_) async => 'server_error_key');
        when(mockEncryption.encryptData(any, 'server_error_key'))
            .thenAnswer((_) async => utf8.encode(jsonEncode(backupData.toJson())));

        // Act
        final result = await syncService.performIncrementalSync();

        // Assert
        expect(result.status, equals(SyncResultStatus.success));
        expect(result.syncedCounts!['payments'], equals(1));

        // Verify retry was attempted
        verify(mockDriveService.uploadBackupFile(any, any)).called(2);
      });

      test('should handle authentication failures with re-authentication', () async {
        // Arrange
        final testPatient = Patient(
          id: 'auth_failure_patient',
          name: 'Auth Failure Test',
          phone: '+7777777777',
          lastModified: DateTime.now(),
          deviceId: testDeviceId,
        );

        final backupData = BackupData.create(
          clinicId: testClinicId,
          deviceId: testDeviceId,
          tables: {'patients': [testPatient.toSyncJson()]},
        );

        // Mock database operations
        when(mockDatabase.getChangedRecordsSince(any))
            .thenAnswer((_) async => {'patients': [testPatient.toSyncJson()]});
        when(mockDatabase.markRecordsAsSynced(any, any))
            .thenAnswer((_) async {});

        // Mock connectivity
        when(mockConnectivity.isConnected).thenReturn(true);

        // Mock Google Drive operations
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.getLatestBackup()).thenAnswer((_) async => null);

        // Simulate authentication failure followed by re-auth and success
        var authCallCount = 0;
        when(mockDriveService.uploadBackupFile(any, any)).thenAnswer((_) async {
          authCallCount++;
          if (authCallCount == 1) {
            throw const AuthenticationException('Token expired', AuthErrorType.tokenExpired);
          }
          return 'auth_recovery_backup_id';
        });

        // Mock re-authentication
        when(mockDriveService.refreshTokens()).thenAnswer((_) async => true);

        // Mock encryption
        when(mockEncryption.deriveEncryptionKey(testClinicId, testDeviceId))
            .thenAnswer((_) async => 'auth_failure_key');
        when(mockEncryption.encryptData(any, 'auth_failure_key'))
            .thenAnswer((_) async => utf8.encode(jsonEncode(backupData.toJson())));

        // Act
        final result = await syncService.performIncrementalSync();

        // Assert
        expect(result.status, equals(SyncResultStatus.success));
        expect(result.syncedCounts!['patients'], equals(1));

        // Verify re-authentication and retry were attempted
        verify(mockDriveService.refreshTokens()).called(1);
        verify(mockDriveService.uploadBackupFile(any, any)).called(2);
      });
    });

    group('Partial Failure Recovery', () {
      test('should handle partial upload failures gracefully', () async {
        // Arrange - Large dataset where some uploads might fail
        final largeDataset = List.generate(100, (index) => Patient(
          id: 'bulk_patient_$index',
          name: 'Bulk Patient $index',
          phone: '+${1000000000 + index}',
          lastModified: DateTime.now().subtract(Duration(minutes: index)),
          deviceId: testDeviceId,
        ));

        final backupData = BackupData.create(
          clinicId: testClinicId,
          deviceId: testDeviceId,
          tables: {
            'patients': largeDataset.map((p) => p.toSyncJson()).toList(),
          },
        );

        // Mock database operations
        when(mockDatabase.getChangedRecordsSince(any))
            .thenAnswer((_) async => {
          'patients': largeDataset.map((p) => p.toSyncJson()).toList(),
        });
        when(mockDatabase.markRecordsAsSynced(any, any))
            .thenAnswer((_) async {});

        // Mock connectivity
        when(mockConnectivity.isConnected).thenReturn(true);

        // Mock Google Drive operations
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.getLatestBackup()).thenAnswer((_) async => null);

        // Simulate partial failure - first attempt fails, second succeeds
        var partialCallCount = 0;
        when(mockDriveService.uploadBackupFile(any, any)).thenAnswer((_) async {
          partialCallCount++;
          if (partialCallCount == 1) {
            throw const NetworkException('Partial upload failure', NetworkErrorType.connectionRefused);
          }
          return 'partial_failure_backup_id';
        });

        // Mock encryption
        when(mockEncryption.deriveEncryptionKey(testClinicId, testDeviceId))
            .thenAnswer((_) async => 'partial_failure_key');
        when(mockEncryption.encryptData(any, 'partial_failure_key'))
            .thenAnswer((_) async => utf8.encode(jsonEncode(backupData.toJson())));

        // Act
        final result = await syncService.performIncrementalSync();

        // Assert
        expect(result.status, equals(SyncResultStatus.success));
        expect(result.syncedCounts!['patients'], equals(100));

        // Verify retry was attempted
        verify(mockDriveService.uploadBackupFile(any, any)).called(2);
      });

      test('should handle DNS resolution failures with retry', () async {
        // Arrange
        final testVisit = Visit(
          id: 'dns_failure_visit',
          patientId: 'dns_failure_patient',
          visitDate: DateTime.now(),
          diagnosis: 'DNS Failure Test',
          lastModified: DateTime.now(),
          deviceId: testDeviceId,
        );

        final backupData = BackupData.create(
          clinicId: testClinicId,
          deviceId: testDeviceId,
          tables: {'visits': [testVisit.toSyncJson()]},
        );

        // Mock database operations
        when(mockDatabase.getChangedRecordsSince(any))
            .thenAnswer((_) async => {'visits': [testVisit.toSyncJson()]});
        when(mockDatabase.markRecordsAsSynced(any, any))
            .thenAnswer((_) async {});

        // Mock connectivity
        when(mockConnectivity.isConnected).thenReturn(true);

        // Mock Google Drive operations
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.getLatestBackup()).thenAnswer((_) async => null);

        // Simulate DNS failure followed by success
        var dnsCallCount = 0;
        when(mockDriveService.uploadBackupFile(any, any)).thenAnswer((_) async {
          dnsCallCount++;
          if (dnsCallCount == 1) {
            throw const NetworkException('DNS resolution failed', NetworkErrorType.dnsResolutionFailed);
          }
          return 'dns_failure_backup_id';
        });

        // Mock encryption
        when(mockEncryption.deriveEncryptionKey(testClinicId, testDeviceId))
            .thenAnswer((_) async => 'dns_failure_key');
        when(mockEncryption.encryptData(any, 'dns_failure_key'))
            .thenAnswer((_) async => utf8.encode(jsonEncode(backupData.toJson())));

        // Act
        final result = await syncService.performIncrementalSync();

        // Assert
        expect(result.status, equals(SyncResultStatus.success));
        expect(result.syncedCounts!['visits'], equals(1));

        // Verify retry was attempted
        verify(mockDriveService.uploadBackupFile(any, any)).called(2);
      });
    });

    group('Circuit Breaker Pattern', () {
      test('should implement circuit breaker for repeated failures', () async {
        // Arrange
        final testPatient = Patient(
          id: 'circuit_breaker_patient',
          name: 'Circuit Breaker Test',
          phone: '+8888888888',
          lastModified: DateTime.now(),
          deviceId: testDeviceId,
        );

        // Mock database operations
        when(mockDatabase.getChangedRecordsSince(any))
            .thenAnswer((_) async => {'patients': [testPatient.toSyncJson()]});

        // Mock connectivity
        when(mockConnectivity.isConnected).thenReturn(true);

        // Mock Google Drive operations
        when(mockDriveService.isAuthenticated).thenReturn(true);
        when(mockDriveService.getLatestBackup()).thenAnswer((_) async => null);

        // Simulate repeated failures
        when(mockDriveService.uploadBackupFile(any, any))
            .thenThrow(const NetworkException('Persistent server error', NetworkErrorType.serverError));

        // Mock encryption
        when(mockEncryption.deriveEncryptionKey(testClinicId, testDeviceId))
            .thenAnswer((_) async => 'circuit_breaker_key');
        when(mockEncryption.encryptData(any, 'circuit_breaker_key'))
            .thenAnswer((_) async => [1, 2, 3, 4, 5]);

        // Act - Multiple sync attempts
        final results = <SyncResult>[];
        for (int i = 0; i < 5; i++) {
          final result = await syncService.performIncrementalSync();
          results.add(result);
          
          // Small delay between attempts
          await Future.delayed(const Duration(milliseconds: 100));
        }

        // Assert - Should eventually stop trying (circuit breaker opens)
        expect(results.any((r) => r.status == SyncResultStatus.failure), isTrue);
        
        // Should have attempted multiple times but not excessively
        verify(mockDriveService.uploadBackupFile(any, any)).called(lessThanOrEqualTo(15));
      });
    });
  });
}