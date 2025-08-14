import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doc_ledger/features/sync/presentation/widgets/sync_status_widget.dart';
import 'package:doc_ledger/core/sync/models/sync_models.dart';

void main() {
  group('SyncStatusWidget', () {
    testWidgets('displays idle state correctly', (WidgetTester tester) async {
      final syncState = SyncState(
        status: SyncStatus.idle,
        lastSyncTime: DateTime.now().subtract(const Duration(minutes: 5)),
        lastBackupTime: DateTime.now().subtract(const Duration(hours: 1)),
        pendingChanges: 0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncStatusWidget(syncState: syncState),
          ),
        ),
      );

      expect(find.text('Up to date'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_done), findsOneWidget);
      expect(find.text('5m ago'), findsOneWidget);
      expect(find.text('1h ago'), findsOneWidget);
    });

    testWidgets('displays syncing state with progress', (WidgetTester tester) async {
      final syncState = SyncState(
        status: SyncStatus.syncing,
        progress: 0.6,
        currentOperation: 'Uploading patient data...',
        pendingChanges: 5,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncStatusWidget(syncState: syncState),
          ),
        ),
      );

      expect(find.text('Syncing...'), findsOneWidget);
      expect(find.text('Uploading patient data...'), findsOneWidget);
      expect(find.text('60% complete'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('displays backing up state', (WidgetTester tester) async {
      final syncState = SyncState(
        status: SyncStatus.backingUp,
        progress: 0.3,
        currentOperation: 'Creating backup file...',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncStatusWidget(syncState: syncState),
          ),
        ),
      );

      expect(find.text('Backing up...'), findsOneWidget);
      expect(find.text('Creating backup file...'), findsOneWidget);
      expect(find.text('30% complete'), findsOneWidget);
    });

    testWidgets('displays restoring state', (WidgetTester tester) async {
      final syncState = SyncState(
        status: SyncStatus.restoring,
        progress: 0.8,
        currentOperation: 'Restoring database...',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncStatusWidget(syncState: syncState),
          ),
        ),
      );

      expect(find.text('Restoring...'), findsOneWidget);
      expect(find.text('Restoring database...'), findsOneWidget);
      expect(find.text('80% complete'), findsOneWidget);
    });

    testWidgets('displays error state with error message', (WidgetTester tester) async {
      final syncState = SyncState(
        status: SyncStatus.error,
        errorMessage: 'Network connection failed',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncStatusWidget(syncState: syncState),
          ),
        ),
      );

      expect(find.text('Sync error'), findsOneWidget);
      expect(find.text('Network connection failed'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('displays pending changes count', (WidgetTester tester) async {
      final syncState = SyncState(
        status: SyncStatus.idle,
        pendingChanges: 12,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncStatusWidget(syncState: syncState),
          ),
        ),
      );

      expect(find.text('Ready to sync'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.byIcon(Icons.pending_actions), findsOneWidget);
    });

    testWidgets('displays conflicts count', (WidgetTester tester) async {
      final syncState = SyncState(
        status: SyncStatus.idle,
        conflicts: ['conflict1', 'conflict2', 'conflict3'],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncStatusWidget(syncState: syncState),
          ),
        ),
      );

      expect(find.text('3'), findsOneWidget);
      expect(find.byIcon(Icons.warning), findsOneWidget);
    });

    testWidgets('shows manual sync button when pending changes exist', (WidgetTester tester) async {
      bool syncTriggered = false;
      final syncState = SyncState(
        status: SyncStatus.idle,
        pendingChanges: 5,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncStatusWidget(
              syncState: syncState,
              onManualSync: () => syncTriggered = true,
            ),
          ),
        ),
      );

      expect(find.text('Sync Now'), findsOneWidget);
      
      await tester.tap(find.text('Sync Now'));
      expect(syncTriggered, isTrue);
    });

    testWidgets('hides manual sync button when no pending changes', (WidgetTester tester) async {
      final syncState = SyncState(
        status: SyncStatus.idle,
        pendingChanges: 0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncStatusWidget(
              syncState: syncState,
              onManualSync: () {},
            ),
          ),
        ),
      );

      expect(find.text('Sync Now'), findsNothing);
    });

    testWidgets('shows settings button when enabled', (WidgetTester tester) async {
      bool settingsOpened = false;
      final syncState = SyncState(status: SyncStatus.idle);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncStatusWidget(
              syncState: syncState,
              onSettings: () => settingsOpened = true,
              showSettings: true,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.settings), findsOneWidget);
      
      await tester.tap(find.byIcon(Icons.settings));
      expect(settingsOpened, isTrue);
    });

    testWidgets('hides settings button when disabled', (WidgetTester tester) async {
      final syncState = SyncState(status: SyncStatus.idle);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncStatusWidget(
              syncState: syncState,
              showSettings: false,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.settings), findsNothing);
    });

    testWidgets('displays compact view correctly', (WidgetTester tester) async {
      final syncState = SyncState(
        status: SyncStatus.idle,
        pendingChanges: 3,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncStatusWidget(
              syncState: syncState,
              compact: true,
            ),
          ),
        ),
      );

      expect(find.text('Sync pending'), findsOneWidget); // Should show "Sync pending" when there are pending changes
      expect(find.text('3'), findsOneWidget);
      // Should not show detailed info in compact mode
      expect(find.text('Last Sync'), findsNothing);
      expect(find.text('Last Backup'), findsNothing);
    });

    testWidgets('formats time correctly for different durations', (WidgetTester tester) async {
      final now = DateTime.now();
      
      // Test "Just now"
      var syncState = SyncState(
        status: SyncStatus.idle,
        lastSyncTime: now.subtract(const Duration(seconds: 30)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncStatusWidget(syncState: syncState),
          ),
        ),
      );

      expect(find.text('Just now'), findsOneWidget);

      // Test minutes ago
      syncState = SyncState(
        status: SyncStatus.idle,
        lastSyncTime: now.subtract(const Duration(minutes: 15)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncStatusWidget(syncState: syncState),
          ),
        ),
      );

      expect(find.text('15m ago'), findsOneWidget);

      // Test hours ago
      syncState = SyncState(
        status: SyncStatus.idle,
        lastSyncTime: now.subtract(const Duration(hours: 3)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncStatusWidget(syncState: syncState),
          ),
        ),
      );

      expect(find.text('3h ago'), findsOneWidget);

      // Test days ago
      syncState = SyncState(
        status: SyncStatus.idle,
        lastSyncTime: now.subtract(const Duration(days: 2)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncStatusWidget(syncState: syncState),
          ),
        ),
      );

      expect(find.text('2d ago'), findsOneWidget);
    });

    testWidgets('displays "Never" when no sync time available', (WidgetTester tester) async {
      final syncState = SyncState(
        status: SyncStatus.idle,
        lastSyncTime: null,
        lastBackupTime: null,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncStatusWidget(syncState: syncState),
          ),
        ),
      );

      expect(find.text('Never'), findsNWidgets(2)); // Both sync and backup
    });

    testWidgets('compact view shows syncing state correctly', (WidgetTester tester) async {
      final syncState = SyncState(
        status: SyncStatus.syncing,
        pendingChanges: 0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncStatusWidget(
              syncState: syncState,
              compact: true,
            ),
          ),
        ),
      );

      expect(find.text('Syncing'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('compact view shows error state correctly', (WidgetTester tester) async {
      final syncState = SyncState(
        status: SyncStatus.error,
        errorMessage: 'Connection failed',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncStatusWidget(
              syncState: syncState,
              compact: true,
            ),
          ),
        ),
      );

      expect(find.text('Error'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    });
  });
}