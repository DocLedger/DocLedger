import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:doc_ledger/core/data/repositories/data_repository.dart';
import 'package:doc_ledger/core/data/services/database_service.dart';
import 'package:doc_ledger/core/data/models/data_models.dart';

import 'data_repository_test.mocks.dart';

@GenerateMocks([DatabaseService])
void main() {
  group('DataRepository Tests', () {
    late MockDatabaseService mockDatabaseService;
    late DataRepository dataRepository;
    late Patient testPatient;
    late Visit testVisit;
    late Payment testPayment;

    setUp(() {
      mockDatabaseService = MockDatabaseService();
      dataRepository = DataRepository(mockDatabaseService);
      
      testPatient = Patient(
        id: 'patient_1',
        name: 'John Doe',
        phone: '+1234567890',
        dateOfBirth: DateTime(1990, 5, 15),
        lastModified: DateTime.now(),
        deviceId: 'device_123',
      );

      testVisit = Visit(
        id: 'visit_1',
        patientId: 'patient_1',
        visitDate: DateTime.now(),
        diagnosis: 'Common cold',
        lastModified: DateTime.now(),
        deviceId: 'device_123',
      );

      testPayment = Payment(
        id: 'payment_1',
        patientId: 'patient_1',
        visitId: 'visit_1',
        amount: 50.0,
        paymentDate: DateTime.now(),
        paymentMethod: 'cash',
        lastModified: DateTime.now(),
        deviceId: 'device_123',
      );
    });

    group('Patient Operations', () {
      test('should create patient successfully', () async {
        when(mockDatabaseService.insertPatient(any))
            .thenAnswer((_) async => testPatient);

        final result = await dataRepository.createPatient(testPatient);

        expect(result, equals(testPatient));
        verify(mockDatabaseService.insertPatient(testPatient)).called(1);
      });

      test('should get patient by id', () async {
        when(mockDatabaseService.getPatientById('patient_1'))
            .thenAnswer((_) async => testPatient);

        final result = await dataRepository.getPatientById('patient_1');

        expect(result, equals(testPatient));
        verify(mockDatabaseService.getPatientById('patient_1')).called(1);
      });

      test('should get all patients', () async {
        final patients = [testPatient];
        when(mockDatabaseService.getAllPatients())
            .thenAnswer((_) async => patients);

        final result = await dataRepository.getAllPatients();

        expect(result, equals(patients));
        verify(mockDatabaseService.getAllPatients()).called(1);
      });

      test('should update patient successfully', () async {
        final updatedPatient = testPatient.copyWith(name: 'John Smith');
        when(mockDatabaseService.updatePatient(any))
            .thenAnswer((_) async => updatedPatient);

        final result = await dataRepository.updatePatient(updatedPatient);

        expect(result, equals(updatedPatient));
        verify(mockDatabaseService.updatePatient(updatedPatient)).called(1);
      });

      test('should delete patient successfully', () async {
        when(mockDatabaseService.deletePatient('patient_1'))
            .thenAnswer((_) async => true);

        final result = await dataRepository.deletePatient('patient_1');

        expect(result, isTrue);
        verify(mockDatabaseService.deletePatient('patient_1')).called(1);
      });

      test('should search patients by name', () async {
        final patients = [testPatient];
        when(mockDatabaseService.searchPatients('John'))
            .thenAnswer((_) async => patients);

        final result = await dataRepository.searchPatients('John');

        expect(result, equals(patients));
        verify(mockDatabaseService.searchPatients('John')).called(1);
      });
    });

    group('Visit Operations', () {
      test('should create visit successfully', () async {
        when(mockDatabaseService.insertVisit(any))
            .thenAnswer((_) async => testVisit);

        final result = await dataRepository.createVisit(testVisit);

        expect(result, equals(testVisit));
        verify(mockDatabaseService.insertVisit(testVisit)).called(1);
      });

      test('should get visits for patient', () async {
        final visits = [testVisit];
        when(mockDatabaseService.getVisitsForPatient('patient_1'))
            .thenAnswer((_) async => visits);

        final result = await dataRepository.getVisitsForPatient('patient_1');

        expect(result, equals(visits));
        verify(mockDatabaseService.getVisitsForPatient('patient_1')).called(1);
      });

      test('should get visit by id', () async {
        when(mockDatabaseService.getVisitById('visit_1'))
            .thenAnswer((_) async => testVisit);

        final result = await dataRepository.getVisitById('visit_1');

        expect(result, equals(testVisit));
        verify(mockDatabaseService.getVisitById('visit_1')).called(1);
      });

      test('should update visit successfully', () async {
        final updatedVisit = testVisit.copyWith(diagnosis: 'Flu');
        when(mockDatabaseService.updateVisit(any))
            .thenAnswer((_) async => updatedVisit);

        final result = await dataRepository.updateVisit(updatedVisit);

        expect(result, equals(updatedVisit));
        verify(mockDatabaseService.updateVisit(updatedVisit)).called(1);
      });

      test('should delete visit successfully', () async {
        when(mockDatabaseService.deleteVisit('visit_1'))
            .thenAnswer((_) async => true);

        final result = await dataRepository.deleteVisit('visit_1');

        expect(result, isTrue);
        verify(mockDatabaseService.deleteVisit('visit_1')).called(1);
      });
    });

    group('Payment Operations', () {
      test('should create payment successfully', () async {
        when(mockDatabaseService.insertPayment(any))
            .thenAnswer((_) async => testPayment);

        final result = await dataRepository.createPayment(testPayment);

        expect(result, equals(testPayment));
        verify(mockDatabaseService.insertPayment(testPayment)).called(1);
      });

      test('should get payments for patient', () async {
        final payments = [testPayment];
        when(mockDatabaseService.getPaymentsForPatient('patient_1'))
            .thenAnswer((_) async => payments);

        final result = await dataRepository.getPaymentsForPatient('patient_1');

        expect(result, equals(payments));
        verify(mockDatabaseService.getPaymentsForPatient('patient_1')).called(1);
      });

      test('should get payments for visit', () async {
        final payments = [testPayment];
        when(mockDatabaseService.getPaymentsForVisit('visit_1'))
            .thenAnswer((_) async => payments);

        final result = await dataRepository.getPaymentsForVisit('visit_1');

        expect(result, equals(payments));
        verify(mockDatabaseService.getPaymentsForVisit('visit_1')).called(1);
      });

      test('should update payment successfully', () async {
        final updatedPayment = testPayment.copyWith(amount: 75.0);
        when(mockDatabaseService.updatePayment(any))
            .thenAnswer((_) async => updatedPayment);

        final result = await dataRepository.updatePayment(updatedPayment);

        expect(result, equals(updatedPayment));
        verify(mockDatabaseService.updatePayment(updatedPayment)).called(1);
      });

      test('should delete payment successfully', () async {
        when(mockDatabaseService.deletePayment('payment_1'))
            .thenAnswer((_) async => true);

        final result = await dataRepository.deletePayment('payment_1');

        expect(result, isTrue);
        verify(mockDatabaseService.deletePayment('payment_1')).called(1);
      });
    });

    group('Sync Operations', () {
      test('should get changed records since timestamp', () async {
        final timestamp = DateTime.now().subtract(const Duration(hours: 1));
        final changedRecords = {
          'patients': [testPatient.toSyncJson()],
          'visits': [testVisit.toSyncJson()],
        };

        when(mockDatabaseService.getChangedRecordsSince(timestamp))
            .thenAnswer((_) async => changedRecords);

        final result = await dataRepository.getChangedRecordsSince(timestamp);

        expect(result, equals(changedRecords));
        verify(mockDatabaseService.getChangedRecordsSince(timestamp)).called(1);
      });

      test('should mark records as synced', () async {
        final recordIds = ['patient_1', 'visit_1'];
        when(mockDatabaseService.markRecordsAsSynced('patients', recordIds))
            .thenAnswer((_) async => {});

        await dataRepository.markRecordsAsSynced('patients', recordIds);

        verify(mockDatabaseService.markRecordsAsSynced('patients', recordIds)).called(1);
      });

      test('should apply remote changes', () async {
        final remoteChanges = {
          'patients': [testPatient.toSyncJson()],
        };

        when(mockDatabaseService.applyRemoteChanges(remoteChanges))
            .thenAnswer((_) async => []);

        final conflicts = await dataRepository.applyRemoteChanges(remoteChanges);

        expect(conflicts, isEmpty);
        verify(mockDatabaseService.applyRemoteChanges(remoteChanges)).called(1);
      });

      test('should get pending changes count', () async {
        when(mockDatabaseService.getPendingChangesCount())
            .thenAnswer((_) async => 5);

        final result = await dataRepository.getPendingChangesCount();

        expect(result, equals(5));
        verify(mockDatabaseService.getPendingChangesCount()).called(1);
      });
    });

    group('Error Handling', () {
      test('should handle database exceptions gracefully', () async {
        when(mockDatabaseService.getPatientById('patient_1'))
            .thenThrow(Exception('Database error'));

        expect(
          () => dataRepository.getPatientById('patient_1'),
          throwsException,
        );
      });

      test('should handle null results appropriately', () async {
        when(mockDatabaseService.getPatientById('nonexistent'))
            .thenAnswer((_) async => null);

        final result = await dataRepository.getPatientById('nonexistent');

        expect(result, isNull);
      });
    });

    group('Transaction Support', () {
      test('should execute operations in transaction', () async {
        when(mockDatabaseService.executeInTransaction(any))
            .thenAnswer((invocation) async {
          final callback = invocation.positionalArguments[0] as Function();
          return await callback();
        });

        final result = await dataRepository.executeInTransaction(() async {
          return 'transaction_result';
        });

        expect(result, equals('transaction_result'));
        verify(mockDatabaseService.executeInTransaction(any)).called(1);
      });

      test('should rollback transaction on error', () async {
        when(mockDatabaseService.executeInTransaction(any))
            .thenThrow(Exception('Transaction failed'));

        expect(
          () => dataRepository.executeInTransaction(() async {
            throw Exception('Operation failed');
          }),
          throwsException,
        );
      });
    });
  });
}