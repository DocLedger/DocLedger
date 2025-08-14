import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:doc_ledger/features/sync/presentation/pages/sync_settings_page.dart';

void main() {
  testWidgets('Sync settings shows actions and allows triggering buttons', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SyncSettingsPage()));

    expect(find.text('Actions'), findsOneWidget);
    expect(find.text('Create Backup'), findsOneWidget);
    expect(find.text('Run Incremental Sync'), findsOneWidget);
  });
}

