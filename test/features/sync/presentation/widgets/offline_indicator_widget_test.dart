import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:doc_ledger/features/sync/presentation/widgets/offline_indicator_widget.dart';

void main() {
  group('Offline Indicator Widget Tests', () {
    testWidgets('should not display when online', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OfflineIndicatorWidget(isOffline: false),
          ),
        ),
      );

      // Verify nothing is displayed when online
      expect(find.byType(Container), findsNothing);
      expect(find.text('You are offline'), findsNothing);
    });

    testWidgets('should display offline message when offline', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OfflineIndicatorWidget(isOffline: true),
          ),
        ),
      );

      // Verify offline indicator is displayed
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
      expect(find.textContaining('You are offline'), findsOneWidget);
    });

    testWidgets('should display custom message when provided', (tester) async {
      const customMessage = 'Custom offline message';
      
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OfflineIndicatorWidget(
              isOffline: true,
              customMessage: customMessage,
            ),
          ),
        ),
      );

      // Verify custom message is displayed
      expect(find.text(customMessage), findsOneWidget);
    });
  });

  group('Conflict Indicator Widget Tests', () {
    testWidgets('should not display when no conflicts', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ConflictIndicatorWidget(conflictCount: 0),
          ),
        ),
      );

      // Verify nothing is displayed when no conflicts
      expect(find.byType(Container), findsNothing);
      expect(find.text('conflict'), findsNothing);
    });

    testWidgets('should display single conflict message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ConflictIndicatorWidget(conflictCount: 1),
          ),
        ),
      );

      // Verify single conflict message is displayed
      expect(find.byIcon(Icons.warning), findsOneWidget);
      expect(find.text('1 sync conflict needs attention'), findsOneWidget);
    });

    testWidgets('should display multiple conflicts message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ConflictIndicatorWidget(conflictCount: 3),
          ),
        ),
      );

      // Verify multiple conflicts message is displayed
      expect(find.byIcon(Icons.warning), findsOneWidget);
      expect(find.text('3 sync conflicts need attention'), findsOneWidget);
    });

    testWidgets('should show resolve button when callback provided', (tester) async {
      bool resolvePressed = false;
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConflictIndicatorWidget(
              conflictCount: 1,
              onResolveConflicts: () => resolvePressed = true,
            ),
          ),
        ),
      );

      // Verify resolve button is displayed
      expect(find.text('Resolve'), findsOneWidget);

      // Tap resolve button
      await tester.tap(find.text('Resolve'));
      await tester.pumpAndSettle();

      // Verify callback was called
      expect(resolvePressed, isTrue);
    });
  });

  group('Pending Sync Indicator Widget Tests', () {
    testWidgets('should not display when no pending changes and not syncing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PendingSyncIndicatorWidget(
              pendingCount: 0,
              isSyncing: false,
            ),
          ),
        ),
      );

      // Verify nothing is displayed
      expect(find.byType(Container), findsNothing);
    });

    testWidgets('should display pending changes message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PendingSyncIndicatorWidget(
              pendingCount: 2,
              isSyncing: false,
            ),
          ),
        ),
      );

      // Verify pending changes message is displayed
      expect(find.byIcon(Icons.cloud_upload), findsOneWidget);
      expect(find.text('2 changes pending sync'), findsOneWidget);
    });

    testWidgets('should display syncing message when syncing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PendingSyncIndicatorWidget(
              pendingCount: 0,
              isSyncing: true,
            ),
          ),
        ),
      );

      // Verify syncing message is displayed
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Syncing changes...'), findsOneWidget);
    });

    testWidgets('should show sync now button when callback provided', (tester) async {
      bool syncPressed = false;
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PendingSyncIndicatorWidget(
              pendingCount: 1,
              isSyncing: false,
              onManualSync: () => syncPressed = true,
            ),
          ),
        ),
      );

      // Verify sync now button is displayed
      expect(find.text('Sync Now'), findsOneWidget);

      // Tap sync now button
      await tester.tap(find.text('Sync Now'));
      await tester.pumpAndSettle();

      // Verify callback was called
      expect(syncPressed, isTrue);
    });
  });
}