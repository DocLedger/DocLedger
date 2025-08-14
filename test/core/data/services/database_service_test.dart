import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:doc_ledger/core/data/services/database_service.dart';
import 'package:doc_ledger/core/data/models/data_models.dart';

void main() {
  group('DatabaseService Tests', () {
    late SQLiteDatabaseService databaseService;

    setUpAll(() {
      // Initialize FFI for testing
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      databaseService = SQLiteDatabaseService(deviceId: 'test_device');
      // Use in-memory database for each test to avoid conflicts
      databaseService.testDatabase = await openDatabase(
        inMemoryDatabasePath,
        version: 2,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE patients (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              phone TEXT NOT NULL,
              date_of_birth TEXT,
              address TEXT,
              emergency_contact TEXT,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              last_modified INTEGER DEFAULT 0,
              sync_status TEXT DEFAULT 'pending',
              device_id TEXT DEFAULT ''
            )
          ''');
          
          await db.execute('''
            CREATE TABLE visits (
              id TEXT PRIMARY KEY,
              patient_id TEXT NOT NULL,
              visit_date TEXT NOT NULL,
              diagnosis TEXT,
              treatment TEXT,
              notes TEXT,
              fee REAL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              last_modified INTEGER DEFAULT 0,
              sync_status TEXT DEFAULT 'pending',
              device_id TEXT DEFAULT '',
              FOREIGN KEY (patient_id) REFERENCES patients (id) ON DELETE CASCADE
            )
          ''');
          
          await db.execute('''
            CREATE TABLE payments (
              id TEXT PRIMARY KEY,
              patient_id TEXT NOT NULL,
              visit_id TEXT,
              amount REAL NOT NULL,
              payment_date TEXT NOT NULL,
              payment_method TEXT NOT NULL,
              notes TEXT,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              last_modified INTEGER DEFAULT 0,
              sync_status TEXT DEFAULT 'pending',
              device_id TEXT DEFAULT '',
              FOREIGN KEY (patient_id) REFERENCES patients (id) ON DELETE CASCADE,
              FOREIGN KEY (visit_id) REFERENCES visits (id) ON DELETE SET NULL
            )
          ''');
          
          await db.execute('''
            CREATE TABLE sync_metadata (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              table_name TEXT NOT NULL UNIQUE,
              last_sync_timestamp INTEGER DEFAULT 0,
              last_backup_timestamp INTEGER DEFAULT 0,
              pending_changes_count INTEGER DEFAULT 0,
              conflict_count INTEGER DEFAULT 0,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
          
          await db.execute('''
            CREATE TABLE sync_conflicts (
              id TEXT PRIMARY KEY,
              table_name TEXT NOT NULL,
              record_id TEXT NOT NULL,
              local_data TEXT NOT NULL,
              remote_data TEXT NOT NULL,
              conflict_timestamp INTEGER NOT NULL,
              conflict_type TEXT NOT NULL,
              resolution_status TEXT DEFAULT 'pending',
              resolved_data TEXT,
              resolution_timestamp INTEGER,
              resolution_strategy TEXT,
              notes TEXT,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
          
          // Initialize sync metadata
          final now = DateTime.now().millisecondsSinceEpoch;
          await db.execute('''INSERT INTO sync_metadata 
             (table_name, created_at, updated_at) 
             VALUES ('patients', $now, $now)''');
          await db.execute('''INSERT INTO sync_metadata 
             (table_name, created_at, updated_at) 
             VALUES ('visits', $now, $now)''');
          await db.execute('''INSERT INTO sync_metadata 
             (table_name, created_at, updated_at) 
             VALUES ('payments', $now, $now)''');
        },
      );
    });

    tearDown(() async {
      await databaseService.close();
    });

    group('Initialization Tests', () {
      test('should initialize database successfully', () async {
        expect(databaseService.database, isNotNull);
        
        // Verify tables exist
        final tables = await databaseService.database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'"
        );
        final tableNames = tables.map((table) => table['name'] as String).toSet();
        expect(tableNames, containsAll(['patients', 'visits', 'payments', 'sync_metadata', 'sync_conflicts']));
      });

      test('should initialize sync metadata for all tables', () async {
        final metadata = await databaseService.database.query('sync_metadata');
        expect(metadata.length, equals(3));
        
        final tableNames = metadata.map((row) => row['table_name'] as String).toSet();
        expect(tableNames, equals({'patients', 'visits', 'payments'}));
      });
    });

    group('Patient CRUD Operations', () {
      test('should insert patient with sync tracking', () async {
        final patient = Patient(
          id: 'patient1',
          name: 'John Doe',
          phone: '1234567890',
          lastModified: DateTime.now(),
          deviceId: 'test_device',
        );

        await databaseService.insertPatient(patient);

        final retrieved = await databaseService.getPatient('patient1');
        expect(retrieved, isNotNull);
        expect(retrieved!.name, equals('John Doe'));
        expect(retrieved.syncStatus, equals('pending'));
        expect(retrieved.deviceId, equals('test_device'));

        // Check sync metadata was updated
        final metadata = await databaseService.getSyncMetadata('patients');
        expect(metadata!['pending_changes_count'], equals(1));
      });

      test('should update patient and track changes', () async {
        final patient = Patient(
          id: 'patient1',
          name: 'John Doe',
          phone: '1234567890',
          lastModified: DateTime.now(),
          deviceId: 'test_device',
        );

        await databaseService.insertPatient(patient);
        
        final updatedPatient = patient.copyWith(name: 'Jane Doe');
        await databaseService.updatePatient(updatedPatient);

        final retrieved = await databaseService.getPatient('patient1');
        expect(retrieved!.name, equals('Jane Doe'));
        expect(retrieved.syncStatus, equals('pending'));

        // Should still have 1 pending change (same record)
        final metadata = await databaseService.getSyncMetadata('patients');
        expect(metadata!['pending_changes_count'], equals(1));
      });

      test('should delete patient and update sync metadata', () async {
        final patient = Patient(
          id: 'patient1',
          name: 'John Doe',
          phone: '1234567890',
          lastModified: DateTime.now(),
          deviceId: 'test_device',
        );

        await databaseService.insertPatient(patient);
        await databaseService.deletePatient('patient1');

        final retrieved = await databaseService.getPatient('patient1');
        expect(retrieved, isNull);

        // Pending changes should be 0 after deletion
        final metadata = await databaseService.getSyncMetadata('patients');
        expect(metadata!['pending_changes_count'], equals(0));
      });

      test('should get all patients ordered by name', () async {
        final patients = [
          Patient(id: 'p1', name: 'Charlie', phone: '111', lastModified: DateTime.now(), deviceId: 'test_device'),
          Patient(id: 'p2', name: 'Alice', phone: '222', lastModified: DateTime.now(), deviceId: 'test_device'),
          Patient(id: 'p3', name: 'Bob', phone: '333', lastModified: DateTime.now(), deviceId: 'test_device'),
        ];

        for (final patient in patients) {
          await databaseService.insertPatient(patient);
        }

        final retrieved = await databaseService.getAllPatients();
        expect(retrieved.length, equals(3));
        expect(retrieved[0].name, equals('Alice'));
        expect(retrieved[1].name, equals('Bob'));
        expect(retrieved[2].name, equals('Charlie'));
      });
    });

    group('Visit CRUD Operations', () {
      test('should insert and retrieve visit', () async {
        final visit = Visit(
          id: 'visit1',
          patientId: 'patient1',
          visitDate: DateTime.now(),
          diagnosis: 'Test diagnosis',
          lastModified: DateTime.now(),
          deviceId: 'test_device',
        );

        await databaseService.insertVisit(visit);

        final retrieved = await databaseService.getVisit('visit1');
        expect(retrieved, isNotNull);
        expect(retrieved!.diagnosis, equals('Test diagnosis'));
        expect(retrieved.syncStatus, equals('pending'));
      });

      test('should get visits for patient ordered by date', () async {
        final now = DateTime.now();
        final visits = [
          Visit(id: 'v1', patientId: 'p1', visitDate: now.subtract(Duration(days: 2)), lastModified: now, deviceId: 'test_device'),
          Visit(id: 'v2', patientId: 'p1', visitDate: now.subtract(Duration(days: 1)), lastModified: now, deviceId: 'test_device'),
          Visit(id: 'v3', patientId: 'p1', visitDate: now, lastModified: now, deviceId: 'test_device'),
        ];

        for (final visit in visits) {
          await databaseService.insertVisit(visit);
        }

        final retrieved = await databaseService.getVisitsForPatient('p1');
        expect(retrieved.length, equals(3));
        // Should be ordered by visit_date DESC (most recent first)
        expect(retrieved[0].id, equals('v3'));
        expect(retrieved[1].id, equals('v2'));
        expect(retrieved[2].id, equals('v1'));
      });
    });

    group('Payment CRUD Operations', () {
      test('should insert and retrieve payment', () async {
        final payment = Payment(
          id: 'payment1',
          patientId: 'patient1',
          amount: 100.0,
          paymentDate: DateTime.now(),
          paymentMethod: 'cash',
          lastModified: DateTime.now(),
          deviceId: 'test_device',
        );

        await databaseService.insertPayment(payment);

        final retrieved = await databaseService.getPayment('payment1');
        expect(retrieved, isNotNull);
        expect(retrieved!.amount, equals(100.0));
        expect(retrieved.paymentMethod, equals('cash'));
        expect(retrieved.syncStatus, equals('pending'));
      });

      test('should get payments for patient ordered by date', () async {
        final now = DateTime.now();
        final payments = [
          Payment(id: 'pay1', patientId: 'p1', amount: 50.0, paymentDate: now.subtract(Duration(days: 1)), paymentMethod: 'cash', lastModified: now, deviceId: 'test_device'),
          Payment(id: 'pay2', patientId: 'p1', amount: 75.0, paymentDate: now, paymentMethod: 'card', lastModified: now, deviceId: 'test_device'),
        ];

        for (final payment in payments) {
          await databaseService.insertPayment(payment);
        }

        final retrieved = await databaseService.getPaymentsForPatient('p1');
        expect(retrieved.length, equals(2));
        // Should be ordered by payment_date DESC (most recent first)
        expect(retrieved[0].id, equals('pay2'));
        expect(retrieved[1].id, equals('pay1'));
      });
    });

    group('Change Tracking Tests', () {
      test('should get changed records since timestamp', () async {
        final baseTime = DateTime.now().millisecondsSinceEpoch;
        
        // Wait a bit to ensure timestamps are after baseTime
        await Future.delayed(Duration(milliseconds: 10));
        
        // Insert some records
        await databaseService.insertPatient(Patient(
          id: 'p1', name: 'Patient 1', phone: '111', 
          lastModified: DateTime.now(), deviceId: 'test_device'
        ));
        
        await Future.delayed(Duration(milliseconds: 10));
        
        await databaseService.insertPatient(Patient(
          id: 'p2', name: 'Patient 2', phone: '222', 
          lastModified: DateTime.now(), deviceId: 'test_device'
        ));

        final changedRecords = await databaseService.getChangedRecords('patients', baseTime);
        expect(changedRecords.length, equals(2));
        expect(changedRecords.every((record) => record['sync_status'] == 'pending'), isTrue);
      });

      test('should mark records as synced', () async {
        // Insert records
        await databaseService.insertPatient(Patient(
          id: 'p1', name: 'Patient 1', phone: '111', 
          lastModified: DateTime.now(), deviceId: 'test_device'
        ));
        await databaseService.insertPatient(Patient(
          id: 'p2', name: 'Patient 2', phone: '222', 
          lastModified: DateTime.now(), deviceId: 'test_device'
        ));

        // Mark as synced
        await databaseService.markRecordsSynced('patients', ['p1', 'p2']);

        // Verify sync status
        final p1 = await databaseService.getPatient('p1');
        final p2 = await databaseService.getPatient('p2');
        expect(p1!.syncStatus, equals('synced'));
        expect(p2!.syncStatus, equals('synced'));

        // Verify pending changes count
        final metadata = await databaseService.getSyncMetadata('patients');
        expect(metadata!['pending_changes_count'], equals(0));
      });
    });

    group('Conflict Detection and Resolution Tests', () {
      test('should detect conflicts between local and remote records', () async {
        final now = DateTime.now().millisecondsSinceEpoch;
        
        // Insert local record
        await databaseService.insertPatient(Patient(
          id: 'p1', name: 'Local Name', phone: '111', 
          lastModified: DateTime.fromMillisecondsSinceEpoch(now), deviceId: 'test_device'
        ));

        // Simulate remote record with different timestamp
        final remoteRecords = [
          {
            'id': 'p1',
            'name': 'Remote Name',
            'phone': '111',
            'last_modified': now + 1000, // Remote is newer
            'sync_status': 'synced',
            'device_id': 'remote_device',
          }
        ];

        final conflicts = await databaseService.detectConflicts('patients', remoteRecords);
        expect(conflicts.length, equals(1));
        expect(conflicts.first.type, equals(ConflictType.updateConflict));
        expect(conflicts.first.localData['name'], equals('Local Name'));
        expect(conflicts.first.remoteData['name'], equals('Remote Name'));
      });

      test('should store and retrieve conflicts', () async {
        final conflict = SyncConflict(
          id: 'conflict1',
          tableName: 'patients',
          recordId: 'p1',
          localData: {'name': 'Local'},
          remoteData: {'name': 'Remote'},
          conflictTime: DateTime.now(),
          type: ConflictType.updateConflict,
          description: 'Test conflict',
        );

        await databaseService.storeConflict(conflict);

        final conflicts = await databaseService.getPendingConflicts();
        expect(conflicts.length, equals(1));
        expect(conflicts.first.id, equals('conflict1'));
        expect(conflicts.first.description, equals('Test conflict'));

        // Check conflict count in metadata
        final metadata = await databaseService.getSyncMetadata('patients');
        expect(metadata!['conflict_count'], equals(1));
      });

      test('should resolve conflicts and update records', () async {
        // Create and store a conflict
        final conflict = SyncConflict(
          id: 'conflict1',
          tableName: 'patients',
          recordId: 'p1',
          localData: {'id': 'p1', 'name': 'Local'},
          remoteData: {'id': 'p1', 'name': 'Remote'},
          conflictTime: DateTime.now(),
          type: ConflictType.updateConflict,
        );

        await databaseService.storeConflict(conflict);

        // Insert the actual record
        await databaseService.insertPatient(Patient(
          id: 'p1', name: 'Local', phone: '111', 
          lastModified: DateTime.now(), deviceId: 'test_device'
        ));

        // Resolve conflict using remote data
        final resolution = ConflictResolution(
          conflictId: 'conflict1',
          strategy: ResolutionStrategy.useRemote,
          resolvedData: {'id': 'p1', 'name': 'Remote', 'phone': '111'},
          resolutionTime: DateTime.now(),
        );

        await databaseService.resolveConflict('conflict1', resolution);

        // Verify conflict is resolved
        final pendingConflicts = await databaseService.getPendingConflicts();
        expect(pendingConflicts.length, equals(0));

        // Verify record was updated
        final patient = await databaseService.getPatient('p1');
        expect(patient!.name, equals('Remote'));
        expect(patient.syncStatus, equals('pending')); // Should be marked for re-sync

        // Check conflict count decreased
        final metadata = await databaseService.getSyncMetadata('patients');
        expect(metadata!['conflict_count'], equals(0));
      });
    });

    group('Remote Changes Application Tests', () {
      test('should apply remote changes without conflicts', () async {
        final now = DateTime.now().millisecondsSinceEpoch;
        final remoteRecords = [
          {
            'id': 'p1',
            'name': 'Remote Patient',
            'phone': '111',
            'last_modified': now,
            'sync_status': 'synced',
            'device_id': 'remote_device',
            'created_at': now,
            'updated_at': now,
          }
        ];

        await databaseService.applyRemoteChanges('patients', remoteRecords);

        final patient = await databaseService.getPatient('p1');
        expect(patient, isNotNull);
        expect(patient!.name, equals('Remote Patient'));
        expect(patient.syncStatus, equals('synced'));
        expect(patient.deviceId, equals('remote_device'));
      });

      test('should handle conflicts when applying remote changes', () async {
        final now = DateTime.now().millisecondsSinceEpoch;
        
        // Insert local record first
        await databaseService.insertPatient(Patient(
          id: 'p1', name: 'Local Patient', phone: '111', 
          lastModified: DateTime.fromMillisecondsSinceEpoch(now + 1000), // Local is newer
          deviceId: 'test_device'
        ));

        // Apply older remote record
        final remoteRecords = [
          {
            'id': 'p1',
            'name': 'Remote Patient',
            'phone': '111',
            'last_modified': now, // Remote is older
            'sync_status': 'synced',
            'device_id': 'remote_device',
            'created_at': now,
            'updated_at': now,
          }
        ];

        await databaseService.applyRemoteChanges('patients', remoteRecords);

        // Local record should remain unchanged
        final patient = await databaseService.getPatient('p1');
        expect(patient!.name, equals('Local Patient'));

        // Should have created a conflict
        final conflicts = await databaseService.getPendingConflicts();
        expect(conflicts.length, equals(1));
      });

      test('should update local record when remote is newer', () async {
        final now = DateTime.now().millisecondsSinceEpoch;
        
        // Insert local record first
        await databaseService.insertPatient(Patient(
          id: 'p1', name: 'Local Patient', phone: '111', 
          lastModified: DateTime.fromMillisecondsSinceEpoch(now), // Local is older
          deviceId: 'test_device'
        ));

        // Mark the local record as synced first
        await databaseService.markRecordsSynced('patients', ['p1']);

        // Apply newer remote record
        final remoteRecords = [
          {
            'id': 'p1',
            'name': 'Remote Patient',
            'phone': '111',
            'last_modified': now + 1000, // Remote is newer
            'sync_status': 'synced',
            'device_id': 'remote_device',
            'created_at': now,
            'updated_at': now,
          }
        ];

        await databaseService.applyRemoteChanges('patients', remoteRecords);

        // Local record should be updated
        final patient = await databaseService.getPatient('p1');
        expect(patient!.name, equals('Remote Patient'));
        expect(patient.syncStatus, equals('synced'));
        expect(patient.deviceId, equals('remote_device'));

        // Should not have created conflicts
        final conflicts = await databaseService.getPendingConflicts();
        expect(conflicts.length, equals(0));
      });
    });

    group('Database Snapshot Tests', () {
      test('should export database snapshot', () async {
        // Insert test data
        await databaseService.insertPatient(Patient(
          id: 'p1', name: 'Patient 1', phone: '111', 
          lastModified: DateTime.now(), deviceId: 'test_device'
        ));
        await databaseService.insertVisit(Visit(
          id: 'v1', patientId: 'p1', visitDate: DateTime.now(), 
          lastModified: DateTime.now(), deviceId: 'test_device'
        ));

        final snapshot = await databaseService.exportDatabaseSnapshot();

        expect(snapshot['version'], equals(2));
        expect(snapshot['device_id'], equals('test_device'));
        expect(snapshot['tables'], isA<Map<String, dynamic>>());
        
        final tables = snapshot['tables'] as Map<String, dynamic>;
        expect(tables['patients'], isA<List>());
        expect(tables['visits'], isA<List>());
        expect(tables['payments'], isA<List>());
        
        final patients = tables['patients'] as List;
        expect(patients.length, equals(1));
        expect(patients.first['name'], equals('Patient 1'));
      });

      test('should import database snapshot', () async {
        final now = DateTime.now().millisecondsSinceEpoch;
        final snapshot = {
          'version': 2,
          'timestamp': DateTime.now().toIso8601String(),
          'device_id': 'imported_device',
          'tables': {
            'patients': [
              {
                'id': 'p1',
                'name': 'Imported Patient',
                'phone': '111',
                'last_modified': now,
                'sync_status': 'synced',
                'device_id': 'imported_device',
                'created_at': now,
                'updated_at': now,
              }
            ],
            'visits': [],
            'payments': [],
          }
        };

        await databaseService.importDatabaseSnapshot(snapshot);

        final patient = await databaseService.getPatient('p1');
        expect(patient, isNotNull);
        expect(patient!.name, equals('Imported Patient'));
        expect(patient.deviceId, equals('imported_device'));
      });

      test('should clear existing data when importing snapshot', () async {
        // Insert existing data
        await databaseService.insertPatient(Patient(
          id: 'existing', name: 'Existing Patient', phone: '999', 
          lastModified: DateTime.now(), deviceId: 'test_device'
        ));

        // Import snapshot with different data
        final now = DateTime.now().millisecondsSinceEpoch;
        final snapshot = {
          'version': 2,
          'timestamp': DateTime.now().toIso8601String(),
          'device_id': 'imported_device',
          'tables': {
            'patients': [
              {
                'id': 'imported',
                'name': 'Imported Patient',
                'phone': '111',
                'last_modified': now,
                'sync_status': 'synced',
                'device_id': 'imported_device',
                'created_at': now,
                'updated_at': now,
              }
            ],
            'visits': [],
            'payments': [],
          }
        };

        await databaseService.importDatabaseSnapshot(snapshot);

        // Existing data should be gone
        final existing = await databaseService.getPatient('existing');
        expect(existing, isNull);

        // Imported data should be present
        final imported = await databaseService.getPatient('imported');
        expect(imported, isNotNull);
        expect(imported!.name, equals('Imported Patient'));
      });
    });

    group('Sync Metadata Tests', () {
      test('should update and retrieve sync metadata', () async {
        final now = DateTime.now().millisecondsSinceEpoch;
        
        await databaseService.updateSyncMetadata('patients',
          lastSyncTimestamp: now,
          lastBackupTimestamp: now - 1000,
          pendingChangesCount: 5,
          conflictCount: 2,
        );

        final metadata = await databaseService.getSyncMetadata('patients');
        expect(metadata, isNotNull);
        expect(metadata!['last_sync_timestamp'], equals(now));
        expect(metadata['last_backup_timestamp'], equals(now - 1000));
        expect(metadata['pending_changes_count'], equals(5));
        expect(metadata['conflict_count'], equals(2));
      });

      test('should return null for non-existent table metadata', () async {
        final metadata = await databaseService.getSyncMetadata('non_existent_table');
        expect(metadata, isNull);
      });
    });
  });
}