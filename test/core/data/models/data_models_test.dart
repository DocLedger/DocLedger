import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:doc_ledger/core/data/models/data_models.dart';

void main() {
  group('Patient Model Tests', () {
    late Patient testPatient;
    late DateTime testDate;

    setUp(() {
      testDate = DateTime(2024, 1, 15, 10, 30);
      testPatient = Patient(
        id: 'patient_1',
        name: 'John Doe',
        phone: '+1234567890',
        dateOfBirth: DateTime(1990, 5, 15),
        address: '123 Main St',
        emergencyContact: 'Jane Doe - +0987654321',
        lastModified: testDate,
        syncStatus: 'pending',
        deviceId: 'device_123',
      );
    });

    test('should serialize to sync JSON correctly', () {
      final json = testPatient.toSyncJson();

      expect(json['id'], equals('patient_1'));
      expect(json['name'], equals('John Doe'));
      expect(json['phone'], equals('+1234567890'));
      expect(json['date_of_birth'], equals('1990-05-15T00:00:00.000'));
      expect(json['address'], equals('123 Main St'));
      expect(json['emergency_contact'], equals('Jane Doe - +0987654321'));
      expect(json['last_modified'], equals(testDate.millisecondsSinceEpoch));
      expect(json['sync_status'], equals('pending'));
      expect(json['device_id'], equals('device_123'));
    });

    test('should deserialize from sync JSON correctly', () {
      final json = testPatient.toSyncJson();
      final deserializedPatient = Patient.fromSyncJson(json);

      expect(deserializedPatient.id, equals(testPatient.id));
      expect(deserializedPatient.name, equals(testPatient.name));
      expect(deserializedPatient.phone, equals(testPatient.phone));
      expect(deserializedPatient.dateOfBirth, equals(testPatient.dateOfBirth));
      expect(deserializedPatient.address, equals(testPatient.address));
      expect(deserializedPatient.emergencyContact, equals(testPatient.emergencyContact));
      expect(deserializedPatient.lastModified, equals(testPatient.lastModified));
      expect(deserializedPatient.syncStatus, equals('pending')); // Preserves original status
      expect(deserializedPatient.deviceId, equals(testPatient.deviceId));
    });

    test('should handle null values in serialization', () {
      final patientWithNulls = Patient(
        id: 'patient_2',
        name: 'Jane Smith',
        phone: '+1111111111',
        dateOfBirth: null,
        address: null,
        emergencyContact: null,
        lastModified: testDate,
        deviceId: 'device_456',
      );

      final json = patientWithNulls.toSyncJson();
      expect(json['date_of_birth'], isNull);
      expect(json['address'], isNull);
      expect(json['emergency_contact'], isNull);

      final deserialized = Patient.fromSyncJson(json);
      expect(deserialized.dateOfBirth, isNull);
      expect(deserialized.address, isNull);
      expect(deserialized.emergencyContact, isNull);
    });

    test('should update sync metadata correctly', () {
      final updatedPatient = testPatient.updateSyncMetadata(
        syncStatus: 'synced',
        deviceId: 'new_device',
      );

      expect(updatedPatient.syncStatus, equals('synced'));
      expect(updatedPatient.deviceId, equals('new_device'));
      expect(updatedPatient.lastModified.isAfter(testDate), isTrue);
      // Other fields should remain the same
      expect(updatedPatient.id, equals(testPatient.id));
      expect(updatedPatient.name, equals(testPatient.name));
    });

    test('should implement equality correctly', () {
      final samePatient = Patient(
        id: 'patient_1',
        name: 'John Doe',
        phone: '+1234567890',
        dateOfBirth: DateTime(1990, 5, 15),
        address: '123 Main St',
        emergencyContact: 'Jane Doe - +0987654321',
        lastModified: DateTime.now(), // Different timestamp
        syncStatus: 'synced', // Different sync status
        deviceId: 'different_device', // Different device
      );

      expect(testPatient == samePatient, isTrue);
      expect(testPatient.hashCode, equals(samePatient.hashCode));
    });
  });

  group('Visit Model Tests', () {
    late Visit testVisit;
    late DateTime testDate;
    late DateTime visitDate;

    setUp(() {
      testDate = DateTime(2024, 1, 15, 10, 30);
      visitDate = DateTime(2024, 1, 15, 9, 0);
      testVisit = Visit(
        id: 'visit_1',
        patientId: 'patient_1',
        visitDate: visitDate,
        diagnosis: 'Common cold',
        treatment: 'Rest and fluids',
        notes: 'Patient feeling better',
        fee: 50.0,
        lastModified: testDate,
        syncStatus: 'pending',
        deviceId: 'device_123',
      );
    });

    test('should serialize to sync JSON correctly', () {
      final json = testVisit.toSyncJson();

      expect(json['id'], equals('visit_1'));
      expect(json['patient_id'], equals('patient_1'));
      expect(json['visit_date'], equals(visitDate.toIso8601String()));
      expect(json['diagnosis'], equals('Common cold'));
      expect(json['treatment'], equals('Rest and fluids'));
      expect(json['notes'], equals('Patient feeling better'));
      expect(json['fee'], equals(50.0));
      expect(json['last_modified'], equals(testDate.millisecondsSinceEpoch));
      expect(json['sync_status'], equals('pending'));
      expect(json['device_id'], equals('device_123'));
    });

    test('should deserialize from sync JSON correctly', () {
      final json = testVisit.toSyncJson();
      final deserializedVisit = Visit.fromSyncJson(json);

      expect(deserializedVisit.id, equals(testVisit.id));
      expect(deserializedVisit.patientId, equals(testVisit.patientId));
      expect(deserializedVisit.visitDate, equals(testVisit.visitDate));
      expect(deserializedVisit.diagnosis, equals(testVisit.diagnosis));
      expect(deserializedVisit.treatment, equals(testVisit.treatment));
      expect(deserializedVisit.notes, equals(testVisit.notes));
      expect(deserializedVisit.fee, equals(testVisit.fee));
      expect(deserializedVisit.lastModified, equals(testVisit.lastModified));
      expect(deserializedVisit.syncStatus, equals('pending'));
      expect(deserializedVisit.deviceId, equals(testVisit.deviceId));
    });

    test('should handle null values in serialization', () {
      final visitWithNulls = Visit(
        id: 'visit_2',
        patientId: 'patient_2',
        visitDate: visitDate,
        diagnosis: null,
        treatment: null,
        notes: null,
        fee: null,
        lastModified: testDate,
        deviceId: 'device_456',
      );

      final json = visitWithNulls.toSyncJson();
      expect(json['diagnosis'], isNull);
      expect(json['treatment'], isNull);
      expect(json['notes'], isNull);
      expect(json['fee'], isNull);

      final deserialized = Visit.fromSyncJson(json);
      expect(deserialized.diagnosis, isNull);
      expect(deserialized.treatment, isNull);
      expect(deserialized.notes, isNull);
      expect(deserialized.fee, isNull);
    });
  });

  group('Payment Model Tests', () {
    late Payment testPayment;
    late DateTime testDate;
    late DateTime paymentDate;

    setUp(() {
      testDate = DateTime(2024, 1, 15, 10, 30);
      paymentDate = DateTime(2024, 1, 15, 11, 0);
      testPayment = Payment(
        id: 'payment_1',
        patientId: 'patient_1',
        visitId: 'visit_1',
        amount: 75.50,
        paymentDate: paymentDate,
        paymentMethod: 'cash',
        notes: 'Full payment received',
        lastModified: testDate,
        syncStatus: 'pending',
        deviceId: 'device_123',
      );
    });

    test('should serialize to sync JSON correctly', () {
      final json = testPayment.toSyncJson();

      expect(json['id'], equals('payment_1'));
      expect(json['patient_id'], equals('patient_1'));
      expect(json['visit_id'], equals('visit_1'));
      expect(json['amount'], equals(75.50));
      expect(json['payment_date'], equals(paymentDate.toIso8601String()));
      expect(json['payment_method'], equals('cash'));
      expect(json['notes'], equals('Full payment received'));
      expect(json['last_modified'], equals(testDate.millisecondsSinceEpoch));
      expect(json['sync_status'], equals('pending'));
      expect(json['device_id'], equals('device_123'));
    });

    test('should deserialize from sync JSON correctly', () {
      final json = testPayment.toSyncJson();
      final deserializedPayment = Payment.fromSyncJson(json);

      expect(deserializedPayment.id, equals(testPayment.id));
      expect(deserializedPayment.patientId, equals(testPayment.patientId));
      expect(deserializedPayment.visitId, equals(testPayment.visitId));
      expect(deserializedPayment.amount, equals(testPayment.amount));
      expect(deserializedPayment.paymentDate, equals(testPayment.paymentDate));
      expect(deserializedPayment.paymentMethod, equals(testPayment.paymentMethod));
      expect(deserializedPayment.notes, equals(testPayment.notes));
      expect(deserializedPayment.lastModified, equals(testPayment.lastModified));
      expect(deserializedPayment.syncStatus, equals('pending'));
      expect(deserializedPayment.deviceId, equals(testPayment.deviceId));
    });

    test('should handle integer amounts correctly', () {
      final jsonWithIntAmount = {
        'id': 'payment_2',
        'patient_id': 'patient_2',
        'visit_id': null,
        'amount': 100, // Integer instead of double
        'payment_date': paymentDate.toIso8601String(),
        'payment_method': 'card',
        'notes': null,
        'last_modified': testDate.millisecondsSinceEpoch,
        'sync_status': 'pending',
        'device_id': 'device_456',
      };

      final payment = Payment.fromSyncJson(jsonWithIntAmount);
      expect(payment.amount, equals(100.0));
    });
  });

  group('SyncConflict Model Tests', () {
    late SyncConflict testConflict;
    late DateTime conflictTime;

    setUp(() {
      conflictTime = DateTime(2024, 1, 15, 12, 0);
      testConflict = SyncConflict(
        id: 'conflict_1',
        tableName: 'patients',
        recordId: 'patient_1',
        localData: {'name': 'John Doe', 'phone': '+1111111111'},
        remoteData: {'name': 'John Smith', 'phone': '+2222222222'},
        conflictTime: conflictTime,
        type: ConflictType.updateConflict,
        description: 'Name and phone number conflict',
      );
    });

    test('should serialize to JSON correctly', () {
      final json = testConflict.toJson();

      expect(json['id'], equals('conflict_1'));
      expect(json['table_name'], equals('patients'));
      expect(json['record_id'], equals('patient_1'));
      expect(json['local_data'], contains('John Doe'));
      expect(json['remote_data'], contains('John Smith'));
      expect(json['conflict_time'], equals(conflictTime.toIso8601String()));
      expect(json['type'], equals('updateConflict'));
      expect(json['description'], equals('Name and phone number conflict'));
    });

    test('should deserialize from JSON correctly', () {
      // Create JSON in the format expected by fromJson
      final json = {
        'id': testConflict.id,
        'table_name': testConflict.tableName,
        'record_id': testConflict.recordId,
        'local_data': jsonEncode(testConflict.localData),
        'remote_data': jsonEncode(testConflict.remoteData),
        'conflict_timestamp': testConflict.conflictTime.millisecondsSinceEpoch,
        'conflict_type': testConflict.type.name,
        'notes': testConflict.description,
      };
      final deserializedConflict = SyncConflict.fromJson(json);

      expect(deserializedConflict.id, equals(testConflict.id));
      expect(deserializedConflict.tableName, equals(testConflict.tableName));
      expect(deserializedConflict.recordId, equals(testConflict.recordId));
      expect(deserializedConflict.localData, equals(testConflict.localData));
      expect(deserializedConflict.remoteData, equals(testConflict.remoteData));
      expect(deserializedConflict.conflictTime, equals(testConflict.conflictTime));
      expect(deserializedConflict.type, equals(testConflict.type));
      expect(deserializedConflict.description, equals(testConflict.description));
    });

    test('should handle all conflict types', () {
      for (final type in ConflictType.values) {
        final json = {
          'id': 'test_conflict',
          'table_name': 'patients',
          'record_id': 'patient_1',
          'local_data': jsonEncode({'name': 'John'}),
          'remote_data': jsonEncode({'name': 'Jane'}),
          'conflict_timestamp': DateTime.now().millisecondsSinceEpoch,
          'conflict_type': type.name,
          'notes': 'Test conflict',
        };
        final deserialized = SyncConflict.fromJson(json);
        expect(deserialized.type, equals(type));
      }
    });
  });

  group('ConflictResolution Model Tests', () {
    late ConflictResolution testResolution;
    late DateTime resolutionTime;

    setUp(() {
      resolutionTime = DateTime(2024, 1, 15, 12, 30);
      testResolution = ConflictResolution(
        conflictId: 'conflict_1',
        strategy: ResolutionStrategy.useLocal,
        resolvedData: {'name': 'John Doe', 'phone': '+1111111111'},
        resolutionTime: resolutionTime,
        notes: 'Used local version as it was more recent',
      );
    });

    test('should serialize to JSON correctly', () {
      final json = testResolution.toJson();

      expect(json['conflict_id'], equals('conflict_1'));
      expect(json['strategy'], equals('useLocal'));
      expect(json['resolved_data'], contains('John Doe'));
      expect(json['resolution_time'], equals(resolutionTime.toIso8601String()));
      expect(json['notes'], equals('Used local version as it was more recent'));
    });

    test('should deserialize from JSON correctly', () {
      final json = testResolution.toJson();
      final deserializedResolution = ConflictResolution.fromJson(json);

      expect(deserializedResolution.conflictId, equals(testResolution.conflictId));
      expect(deserializedResolution.strategy, equals(testResolution.strategy));
      expect(deserializedResolution.resolvedData, equals(testResolution.resolvedData));
      expect(deserializedResolution.resolutionTime, equals(testResolution.resolutionTime));
      expect(deserializedResolution.notes, equals(testResolution.notes));
    });

    test('should handle all resolution strategies', () {
      for (final strategy in ResolutionStrategy.values) {
        final resolution = testResolution.copyWith(strategy: strategy);
        final json = resolution.toJson();
        final deserialized = ConflictResolution.fromJson(json);
        expect(deserialized.strategy, equals(strategy));
      }
    });
  });
}