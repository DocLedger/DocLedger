import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:doc_ledger/core/data/models/data_models.dart';
import 'package:doc_ledger/features/patients/presentation/widgets/patient_list_item.dart';
import 'package:doc_ledger/core/services/service_locator.dart';

void main() {
  group('PatientListItem Widget Tests', () {
    setUp(() async {
      // Initialize services for testing
      await initializeServices();
    });

    tearDown(() async {
      await serviceLocator.reset();
    });

    testWidgets('should display patient information correctly', (tester) async {
      final patient = Patient(
        id: '1',
        name: 'John Doe',
        phone: '+1234567890',
        dateOfBirth: DateTime(1980, 5, 15),
        lastModified: DateTime.now(),
        deviceId: 'device1',
        syncStatus: 'synced',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PatientListItem(patient: patient),
          ),
        ),
      );

      // Verify patient information is displayed
      expect(find.text('John Doe'), findsOneWidget);
      expect(find.text('+1234567890'), findsOneWidget);
      expect(find.text('DOB: 15/5/1980'), findsOneWidget);
    });

    testWidgets('should show synced status indicator', (tester) async {
      final patient = Patient(
        id: '1',
        name: 'John Doe',
        phone: '+1234567890',
        lastModified: DateTime.now(),
        deviceId: 'device1',
        syncStatus: 'synced',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PatientListItem(patient: patient),
          ),
        ),
      );

      // Verify synced icon is displayed
      expect(find.byIcon(Icons.cloud_done), findsOneWidget);
    });

    testWidgets('should show pending sync status indicator', (tester) async {
      final patient = Patient(
        id: '1',
        name: 'John Doe',
        phone: '+1234567890',
        lastModified: DateTime.now(),
        deviceId: 'device1',
        syncStatus: 'pending',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PatientListItem(patient: patient),
          ),
        ),
      );

      // Verify pending sync icon is displayed
      expect(find.byIcon(Icons.cloud_upload), findsOneWidget);
    });

    testWidgets('should show conflict indicator for conflicted patient', (tester) async {
      final patient = Patient(
        id: '1',
        name: 'John Doe',
        phone: '+1234567890',
        lastModified: DateTime.now(),
        deviceId: 'device1',
        syncStatus: 'conflict',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PatientListItem(patient: patient),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify conflict icon is displayed
      expect(find.byIcon(Icons.warning), findsWidgets);
      expect(find.textContaining('conflict'), findsOneWidget);
    });

    testWidgets('should show error status indicator', (tester) async {
      final patient = Patient(
        id: '1',
        name: 'John Doe',
        phone: '+1234567890',
        lastModified: DateTime.now(),
        deviceId: 'device1',
        syncStatus: 'error',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PatientListItem(patient: patient),
          ),
        ),
      );

      // Verify error icon is displayed
      expect(find.byIcon(Icons.error), findsOneWidget);
    });

    testWidgets('should handle tap events', (tester) async {
      bool tapped = false;
      final patient = Patient(
        id: '1',
        name: 'John Doe',
        phone: '+1234567890',
        lastModified: DateTime.now(),
        deviceId: 'device1',
        syncStatus: 'synced',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PatientListItem(
              patient: patient,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      // Tap the list item
      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();

      // Verify tap was handled
      expect(tapped, isTrue);
    });
  });
}