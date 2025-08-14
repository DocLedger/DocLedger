import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:doc_ledger/features/patients/presentation/pages/patient_list_page.dart';

void main() {
  testWidgets('Add patient dialog validates required fields', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PatientListPage()));

    // Tap FAB to open dialog
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // Try to save without input
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Required'), findsNWidgets(2));
  });
}

