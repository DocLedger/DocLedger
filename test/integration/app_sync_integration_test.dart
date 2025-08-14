import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';

import 'package:doc_ledger/main.dart';
import 'package:doc_ledger/core/services/service_locator.dart';
import 'package:doc_ledger/core/sync/services/sync_service.dart';
import 'package:doc_ledger/core/data/repositories/data_repository.dart';
import 'package:doc_ledger/core/data/models/data_models.dart';
import 'package:doc_ledger/core/sync/models/sync_models.dart';
import 'package:doc_ledger/features/patients/presentation/pages/patient_list_page.dart';
import 'package:doc_ledger/features/sync/presentation/pages/sync_settings_page.dart';

import 'app_sync_integration_test.mocks.dart';

@GenerateMocks([
  SyncService,
  DataRepository,
])
void main() {
  group('App Sync Integration Tests', () {
    late MockSyncService mockSyncService;
    late MockDataRepository mockDataRepository;

    setUp(() async {
      mockSyncService = MockSyncService();
      mockDataRepository = MockDataRepository();

      // Reset service locator
      await serviceLocator.reset();

      // Register mocked services
      serviceLocator.registerSingleton<SyncService>(mockSyncService);
      serviceLocator.registerSingleton<DataRepository>(mockDataRepository);

      // Setup default mock behaviors
      when(mockSyncService.currentState).thenReturn(SyncState.idle());
      when(mockSyncService.stateStream).thenAnswer((_) => Stream.value(SyncState.idle()));
      when(mockDataRepository.getPatients()).thenAnswer((_) async => []);
      when(mockDataRepository.getPendingSyncCount()).thenAnswer((_) async => 0);
      when(mockDataRepository.getSyncConflicts()).thenAnswer((_) async => []);
    });

    tearDown(() async {
      await serviceLocator.reset();
    });

    testWidgets('should initialize sync services on app startup', (tester) async {
      // Build the app
      await tester.pumpWidget(const DocLedgerApp());
      await tester.pumpAndSettle();

      // Verify that services are registered
      expect(serviceLocator.isRegistered<SyncService>(), isTrue);
      expect(serviceLocator.isRegistered<DataRepository>(), isTrue);
    });

    testWidgets('should display sync status in patient list', (tester) async {
      // Setup mock data
      final testPatients = [
        Patient(
          id: '1',
          name: 'John Doe',
          phone: '+1234567890',
          lastModified: DateTime.now(),
          deviceId: 'device1',
          syncStatus: 'synced',
        ),
        Patient(
          id: '2',
          name: 'Jane Smith',
          phone: '+1987654321',
          lastModified: DateTime.now(),
          deviceId: 'device1',
          syncStatus: 'pending',
        ),
      ];

      when(mockDataRepository.getPatients()).thenAnswer((_) async => testPatients);

      // Navigate to patient list
      await tester.pumpWidget(const MaterialApp(home: PatientListPage()));
      await tester.pumpAndSettle();

      // Verify sync status widget is displayed
      expect(find.byType(SyncStatusWidget), findsOneWidget);

      // Verify patient list items show sync indicators
      expect(find.byIcon(Icons.cloud_done), findsOneWidget); // Synced patient
      expect(find.byIcon(Icons.cloud_upload), findsOneWidget); // Pending patient
    });

    testWidgets('should trigger sync on pull-to-refresh', (tester) async {
      when(mockDataRepository.getPatients()).thenAnswer((_) async => []);
      when(mockSyncService.performIncrementalSync()).thenAnswer(
        (_) async => SyncResult.success(duration: const Duration(seconds: 1)),
      );

      // Navigate to patient list
      await tester.pumpWidget(const MaterialApp(home: PatientListPage()));
      await tester.pumpAndSettle();

      // Perform pull-to-refresh
      await tester.fling(find.byType(RefreshIndicator), const Offset(0, 300), 1000);
      await tester.pumpAndSettle();

      // Verify sync was triggered
      verify(mockSyncService.performIncrementalSync()).called(1);
    });

    testWidgets('should navigate to sync settings from patient list', (tester) async {
      when(mockDataRepository.getPatients()).thenAnswer((_) async => []);

      // Build app with routes
      await tester.pumpWidget(MaterialApp(
        home: const PatientListPage(),
        routes: {
          SyncSettingsPage.routeName: (_) => const SyncSettingsPage(),
        },
      ));
      await tester.pumpAndSettle();

      // Tap sync settings button
      await tester.tap(find.byIcon(Icons.sync));
      await tester.pumpAndSettle();

      // Verify navigation to sync settings
      expect(find.byType(SyncSettingsPage), findsOneWidget);
    });

    testWidgets('should show sync conflicts in patient list', (tester) async {
      // Setup patient with conflict
      final conflictPatient = Patient(
        id: '1',
        name: 'John Doe',
        phone: '+1234567890',
        lastModified: DateTime.now(),
        deviceId: 'device1',
        syncStatus: 'conflict',
      );

      final testConflict = SyncConflict(
        id: 'conflict1',
        tableName: 'patients',
        recordId: '1',
        localData: {'name': 'John Doe'},
        remoteData: {'name': 'John Smith'},
        conflictTime: DateTime.now(),
        type: ConflictType.updateConflict,
      );

      when(mockDataRepository.getPatients()).thenAnswer((_) async => [conflictPatient]);
      when(mockSyncService.getPendingConflicts()).thenAnswer((_) async => [testConflict]);

      // Navigate to patient list
      await tester.pumpWidget(const MaterialApp(home: PatientListPage()));
      await tester.pumpAndSettle();

      // Verify conflict indicator is shown
      expect(find.byIcon(Icons.warning), findsWidgets);
      expect(find.textContaining('conflict'), findsOneWidget);
    });

    testWidgets('should handle sync errors gracefully', (tester) async {
      when(mockDataRepository.getPatients()).thenAnswer((_) async => []);
      when(mockSyncService.performIncrementalSync()).thenThrow(
        Exception('Network error'),
      );

      // Navigate to patient list
      await tester.pumpWidget(const MaterialApp(home: PatientListPage()));
      await tester.pumpAndSettle();

      // Perform pull-to-refresh
      await tester.fling(find.byType(RefreshIndicator), const Offset(0, 300), 1000);
      await tester.pumpAndSettle();

      // Verify error message is shown
      expect(find.textContaining('Sync error'), findsOneWidget);
    });

    testWidgets('should update UI when sync state changes', (tester) async {
      when(mockDataRepository.getPatients()).thenAnswer((_) async => []);

      // Create a stream controller for sync state
      final stateController = StreamController<SyncState>();
      when(mockSyncService.stateStream).thenAnswer((_) => stateController.stream);
      when(mockSyncService.currentState).thenReturn(SyncState.idle());

      // Navigate to patient list
      await tester.pumpWidget(const MaterialApp(home: PatientListPage()));
      await tester.pumpAndSettle();

      // Emit syncing state
      stateController.add(SyncState.syncing(currentOperation: 'Syncing patients'));
      await tester.pumpAndSettle();

      // Verify UI shows syncing state
      expect(find.textContaining('Syncing'), findsOneWidget);

      // Emit idle state
      stateController.add(SyncState.idle());
      await tester.pumpAndSettle();

      // Clean up
      await stateController.close();
    });

    testWidgets('should show offline indicator when network unavailable', (tester) async {
      when(mockDataRepository.getPatients()).thenAnswer((_) async => []);
      when(mockSyncService.currentState).thenReturn(
        SyncState.error('No internet connection'),
      );
      when(mockSyncService.stateStream).thenAnswer(
        (_) => Stream.value(SyncState.error('No internet connection')),
      );

      // Navigate to patient list
      await tester.pumpWidget(const MaterialApp(home: PatientListPage()));
      await tester.pumpAndSettle();

      // Verify offline indicator is shown
      expect(find.textContaining('No internet'), findsOneWidget);
    });
  });
}