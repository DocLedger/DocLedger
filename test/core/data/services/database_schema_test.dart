import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:doc_ledger/core/data/services/database_schema.dart';

void main() {
  group('DatabaseSchema Tests', () {
    late Database database;

    setUpAll(() {
      // Initialize FFI for testing
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      // Create in-memory database for each test
      database = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (db, version) async {
          // Create base tables without sync columns (version 1)
          await db.execute(DatabaseSchema.createPatientsTable);
          await db.execute(DatabaseSchema.createVisitsTable);
          await db.execute(DatabaseSchema.createPaymentsTable);
        },
      );
    });

    tearDown(() async {
      await database.close();
    });

    group('Schema Migration Tests', () {
      test('should migrate from version 1 to version 2 successfully', () async {
        // Verify initial state (version 1)
        final initialTables = await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'"
        );
        expect(initialTables.length, equals(3)); // patients, visits, payments

        // Check that sync columns don't exist initially
        final patientsColumns = await database.rawQuery("PRAGMA table_info(patients)");
        final columnNames = patientsColumns.map((col) => col['name'] as String).toSet();
        expect(columnNames.contains('last_modified'), isFalse);
        expect(columnNames.contains('sync_status'), isFalse);
        expect(columnNames.contains('device_id'), isFalse);

        // Perform migration to version 2
        await DatabaseSchema.onUpgrade(database, 1, 2);

        // Verify sync columns were added
        final updatedPatientsColumns = await database.rawQuery("PRAGMA table_info(patients)");
        final updatedColumnNames = updatedPatientsColumns.map((col) => col['name'] as String).toSet();
        expect(updatedColumnNames.contains('last_modified'), isTrue);
        expect(updatedColumnNames.contains('sync_status'), isTrue);
        expect(updatedColumnNames.contains('device_id'), isTrue);

        // Verify sync tables were created
        final finalTables = await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'"
        );
        final tableNames = finalTables.map((table) => table['name'] as String).toSet();
        expect(tableNames.contains('sync_metadata'), isTrue);
        expect(tableNames.contains('sync_conflicts'), isTrue);

        // Verify sync metadata was initialized
        final syncMetadata = await database.query('sync_metadata');
        expect(syncMetadata.length, equals(3)); // patients, visits, payments
        
        final tableNamesInMetadata = syncMetadata.map((row) => row['table_name'] as String).toSet();
        expect(tableNamesInMetadata, equals({'patients', 'visits', 'payments'}));
      });

      test('should create indexes for sync optimization', () async {
        await DatabaseSchema.onUpgrade(database, 1, 2);

        // Check that indexes were created
        final indexes = await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%'"
        );
        
        expect(indexes.length, greaterThan(10)); // Should have multiple sync indexes
        
        final indexNames = indexes.map((idx) => idx['name'] as String).toSet();
        expect(indexNames.contains('idx_patients_sync_status'), isTrue);
        expect(indexNames.contains('idx_patients_last_modified'), isTrue);
        expect(indexNames.contains('idx_visits_sync_modified'), isTrue);
        expect(indexNames.contains('idx_sync_conflicts_table_record'), isTrue);
      });

      test('should handle migration with existing data', () async {
        // Insert test data before migration
        await database.insert('patients', {
          'id': 'patient1',
          'name': 'John Doe',
          'phone': '1234567890',
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        });

        await database.insert('visits', {
          'id': 'visit1',
          'patient_id': 'patient1',
          'visit_date': DateTime.now().toIso8601String(),
          'diagnosis': 'Test diagnosis',
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        });

        // Perform migration
        await DatabaseSchema.onUpgrade(database, 1, 2);

        // Verify data is preserved and sync columns have default values
        final patients = await database.query('patients');
        expect(patients.length, equals(1));
        expect(patients.first['name'], equals('John Doe'));
        expect(patients.first['sync_status'], equals('pending'));
        expect(patients.first['last_modified'], equals(0));
        expect(patients.first['device_id'], equals(''));

        final visits = await database.query('visits');
        expect(visits.length, equals(1));
        expect(visits.first['diagnosis'], equals('Test diagnosis'));
        expect(visits.first['sync_status'], equals('pending'));
      });
    });

    group('Schema Creation Tests', () {
      test('should create database with version 2 schema directly', () async {
        await database.close();
        
        // Create new database with version 2
        database = await openDatabase(
          inMemoryDatabasePath,
          version: 2,
          onCreate: DatabaseSchema.onCreate,
        );

        // Verify all tables exist
        final tables = await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'"
        );
        final tableNames = tables.map((table) => table['name'] as String).toSet();
        expect(tableNames, containsAll(['patients', 'visits', 'payments', 'sync_metadata', 'sync_conflicts']));

        // Verify sync columns exist in main tables
        final patientsColumns = await database.rawQuery("PRAGMA table_info(patients)");
        final columnNames = patientsColumns.map((col) => col['name'] as String).toSet();
        expect(columnNames.containsAll(['last_modified', 'sync_status', 'device_id']), isTrue);

        // Verify sync metadata is initialized
        final syncMetadata = await database.query('sync_metadata');
        expect(syncMetadata.length, equals(3));
      });
    });

    group('Schema Validation Tests', () {
      test('should validate complete schema correctly', () async {
        await DatabaseSchema.onUpgrade(database, 1, 2);
        
        final isValid = await DatabaseSchema.validateSchema(database);
        expect(isValid, isTrue);
      });

      test('should detect incomplete schema', () async {
        // Don't run migration, so schema is incomplete
        final isValid = await DatabaseSchema.validateSchema(database);
        expect(isValid, isFalse);
      });

      test('should detect missing sync columns', () async {
        // Create sync tables but don't add sync columns to main tables
        await database.execute(DatabaseSchema.createSyncMetadataTable);
        await database.execute(DatabaseSchema.createSyncConflictsTable);
        
        final isValid = await DatabaseSchema.validateSchema(database);
        expect(isValid, isFalse);
      });
    });

    group('Rollback Tests', () {
      test('should rollback migration successfully', () async {
        // First migrate to version 2
        await DatabaseSchema.onUpgrade(database, 1, 2);
        
        // Verify migration was successful
        var isValid = await DatabaseSchema.validateSchema(database);
        expect(isValid, isTrue);

        // Perform rollback
        await DatabaseSchema.rollbackToVersion1(database);

        // Verify sync tables are removed
        final tables = await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'"
        );
        final tableNames = tables.map((table) => table['name'] as String).toSet();
        expect(tableNames.contains('sync_metadata'), isFalse);
        expect(tableNames.contains('sync_conflicts'), isFalse);

        // Verify indexes are removed
        final indexes = await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%'"
        );
        expect(indexes.length, equals(0));

        // Note: Sync columns remain due to SQLite limitations
        // This is expected behavior documented in the rollback method
      });
    });

    group('Sync Metadata Operations', () {
      test('should initialize sync metadata for all tables', () async {
        await DatabaseSchema.onUpgrade(database, 1, 2);

        final metadata = await database.query('sync_metadata');
        expect(metadata.length, equals(3));

        for (final row in metadata) {
          expect(row['last_sync_timestamp'], equals(0));
          expect(row['last_backup_timestamp'], equals(0));
          expect(row['pending_changes_count'], equals(0));
          expect(row['conflict_count'], equals(0));
          expect(row['created_at'], isA<int>());
          expect(row['updated_at'], isA<int>());
        }
      });

      test('should not duplicate sync metadata on multiple migrations', () async {
        await DatabaseSchema.onUpgrade(database, 1, 2);
        
        // Run migration again (should not create duplicates)
        await DatabaseSchema.onUpgrade(database, 1, 2);

        final metadata = await database.query('sync_metadata');
        expect(metadata.length, equals(3)); // Should still be 3, not 6
      });
    });

    group('Sync Conflicts Table Tests', () {
      test('should create sync conflicts table with correct schema', () async {
        await DatabaseSchema.onUpgrade(database, 1, 2);

        final columns = await database.rawQuery("PRAGMA table_info(sync_conflicts)");
        final columnNames = columns.map((col) => col['name'] as String).toSet();
        
        expect(columnNames.containsAll([
          'id', 'table_name', 'record_id', 'local_data', 'remote_data',
          'conflict_timestamp', 'conflict_type', 'resolution_status',
          'resolved_data', 'resolution_timestamp', 'resolution_strategy',
          'notes', 'created_at', 'updated_at'
        ]), isTrue);
      });

      test('should allow inserting conflict records', () async {
        await DatabaseSchema.onUpgrade(database, 1, 2);

        final now = DateTime.now().millisecondsSinceEpoch;
        await database.insert('sync_conflicts', {
          'id': 'conflict1',
          'table_name': 'patients',
          'record_id': 'patient1',
          'local_data': '{"name": "John Local"}',
          'remote_data': '{"name": "John Remote"}',
          'conflict_timestamp': now,
          'conflict_type': 'updateConflict',
          'resolution_status': 'pending',
          'created_at': now,
          'updated_at': now,
        });

        final conflicts = await database.query('sync_conflicts');
        expect(conflicts.length, equals(1));
        expect(conflicts.first['table_name'], equals('patients'));
        expect(conflicts.first['resolution_status'], equals('pending'));
      });
    });

    group('Index Performance Tests', () {
      test('should create all required indexes for sync operations', () async {
        await DatabaseSchema.onUpgrade(database, 1, 2);

        final expectedIndexes = [
          'idx_patients_sync_status',
          'idx_patients_last_modified',
          'idx_patients_device_id',
          'idx_visits_sync_status',
          'idx_visits_last_modified',
          'idx_visits_device_id',
          'idx_payments_sync_status',
          'idx_payments_last_modified',
          'idx_payments_device_id',
          'idx_sync_conflicts_table_record',
          'idx_sync_conflicts_status',
          'idx_patients_sync_modified',
          'idx_visits_sync_modified',
          'idx_payments_sync_modified',
        ];

        final indexes = await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%'"
        );
        final indexNames = indexes.map((idx) => idx['name'] as String).toSet();

        for (final expectedIndex in expectedIndexes) {
          expect(indexNames.contains(expectedIndex), isTrue, 
                 reason: 'Missing index: $expectedIndex');
        }
      });
    });
  });
}