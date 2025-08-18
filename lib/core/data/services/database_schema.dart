import 'package:sqflite/sqflite.dart';

/// Database schema definitions and migration scripts for sync-enabled DocLedger
class DatabaseSchema {
  static const int currentVersion = 3;
  static const String databaseName = 'docledger.db';

  /// Initial database schema creation (version 1)
  static const String createPatientsTable = '''
    CREATE TABLE patients (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      phone TEXT NOT NULL,
      date_of_birth TEXT,
      address TEXT,
      emergency_contact TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''';

  static const String createVisitsTable = '''
    CREATE TABLE visits (
      id TEXT PRIMARY KEY,
      patient_id TEXT NOT NULL,
      visit_date TEXT NOT NULL,
      diagnosis TEXT,
      treatment TEXT,
      prescriptions TEXT,
      notes TEXT,
      fee REAL,
      follow_up_date TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      FOREIGN KEY (patient_id) REFERENCES patients (id) ON DELETE CASCADE
    )
  ''';

  static const String createPaymentsTable = '''
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
      FOREIGN KEY (patient_id) REFERENCES patients (id) ON DELETE CASCADE,
      FOREIGN KEY (visit_id) REFERENCES visits (id) ON DELETE SET NULL
    )
  ''';

  /// Sync tracking columns migration (version 2)
  static const String addSyncColumnsToPatients = '''
    ALTER TABLE patients ADD COLUMN last_modified INTEGER DEFAULT 0
  ''';

  static const String addSyncStatusToPatients = '''
    ALTER TABLE patients ADD COLUMN sync_status TEXT DEFAULT 'pending'
  ''';

  static const String addDeviceIdToPatients = '''
    ALTER TABLE patients ADD COLUMN device_id TEXT DEFAULT ''
  ''';

  static const String addSyncColumnsToVisits = '''
    ALTER TABLE visits ADD COLUMN last_modified INTEGER DEFAULT 0
  ''';

  static const String addSyncStatusToVisits = '''
    ALTER TABLE visits ADD COLUMN sync_status TEXT DEFAULT 'pending'
  ''';

  static const String addDeviceIdToVisits = '''
    ALTER TABLE visits ADD COLUMN device_id TEXT DEFAULT ''
  ''';

  static const String addPrescriptionsToVisits = '''
    ALTER TABLE visits ADD COLUMN prescriptions TEXT
  ''';

  static const String addFollowUpDateToVisits = '''
    ALTER TABLE visits ADD COLUMN follow_up_date TEXT
  ''';

  static const String addSyncColumnsToPayments = '''
    ALTER TABLE payments ADD COLUMN last_modified INTEGER DEFAULT 0
  ''';

  static const String addSyncStatusToPayments = '''
    ALTER TABLE payments ADD COLUMN sync_status TEXT DEFAULT 'pending'
  ''';

  static const String addDeviceIdToPayments = '''
    ALTER TABLE payments ADD COLUMN device_id TEXT DEFAULT ''
  ''';

  // Simplified - no complex sync metadata table needed

  /// Settings table for storing application settings
  static const String createSettingsTable = '''
    CREATE TABLE settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''';

  /// Database indexes for sync query optimization
  static const List<String> syncOptimizationIndexes = [
    // Indexes for sync status queries
    'CREATE INDEX idx_patients_sync_status ON patients (sync_status)',
    'CREATE INDEX idx_patients_last_modified ON patients (last_modified)',
    'CREATE INDEX idx_patients_device_id ON patients (device_id)',
    
    'CREATE INDEX idx_visits_sync_status ON visits (sync_status)',
    'CREATE INDEX idx_visits_last_modified ON visits (last_modified)',
    'CREATE INDEX idx_visits_device_id ON visits (device_id)',
    'CREATE INDEX idx_visits_patient_id ON visits (patient_id)',
    
    'CREATE INDEX idx_payments_sync_status ON payments (sync_status)',
    'CREATE INDEX idx_payments_last_modified ON payments (last_modified)',
    'CREATE INDEX idx_payments_device_id ON payments (device_id)',
    'CREATE INDEX idx_payments_patient_id ON payments (patient_id)',
    
    // Indexes for conflict resolution (table may not exist in simplified model)
    'CREATE INDEX IF NOT EXISTS idx_sync_conflicts_table_record ON sync_conflicts (table_name, record_id)',
    'CREATE INDEX IF NOT EXISTS idx_sync_conflicts_status ON sync_conflicts (resolution_status)',
    'CREATE INDEX IF NOT EXISTS idx_sync_conflicts_timestamp ON sync_conflicts (conflict_timestamp)',
    
    // Composite indexes for common sync queries
    'CREATE INDEX idx_patients_sync_modified ON patients (sync_status, last_modified)',
    'CREATE INDEX idx_visits_sync_modified ON visits (sync_status, last_modified)',
    'CREATE INDEX idx_payments_sync_modified ON payments (sync_status, last_modified)',
  ];

  /// Initialize sync metadata for all tables
  static List<String> initializeSyncMetadata() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return [
      '''INSERT OR IGNORE INTO sync_metadata 
         (table_name, created_at, updated_at) 
         VALUES ('patients', $now, $now)''',
      '''INSERT OR IGNORE INTO sync_metadata 
         (table_name, created_at, updated_at) 
         VALUES ('visits', $now, $now)''',
      '''INSERT OR IGNORE INTO sync_metadata 
         (table_name, created_at, updated_at) 
         VALUES ('payments', $now, $now)''',
    ];
  }

  /// Legacy sync tables for compatibility in simplified model
  static const String createSyncMetadataTable = '''
    CREATE TABLE IF NOT EXISTS sync_metadata (
      table_name TEXT PRIMARY KEY,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''';

  static const String createSyncConflictsTable = '''
    CREATE TABLE IF NOT EXISTS sync_conflicts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      table_name TEXT NOT NULL,
      record_id TEXT NOT NULL,
      conflict_timestamp INTEGER NOT NULL,
      resolution_status TEXT DEFAULT 'unresolved'
    )
  ''';

  /// Database migration handler
  static Future<void> onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _migrateToVersion2(db);
    }
    if (oldVersion < 3) {
      await _migrateToVersion3(db);
    }
  }

  /// Migration to version 2: Add sync tracking columns and tables
  static Future<void> _migrateToVersion2(Database db) async {
    // Add sync columns to existing tables (with error handling for existing columns)
    try {
      await db.execute(addSyncColumnsToPatients);
    } catch (e) {
      // Column might already exist, ignore error
    }
    try {
      await db.execute(addSyncStatusToPatients);
    } catch (e) {
      // Column might already exist, ignore error
    }
    try {
      await db.execute(addDeviceIdToPatients);
    } catch (e) {
      // Column might already exist, ignore error
    }
    
    try {
      await db.execute(addSyncColumnsToVisits);
    } catch (e) {
      // Column might already exist, ignore error
    }
    try {
      await db.execute(addSyncStatusToVisits);
    } catch (e) {
      // Column might already exist, ignore error
    }
    try {
      await db.execute(addDeviceIdToVisits);
    } catch (e) {
      // Column might already exist, ignore error
    }
    
    try {
      await db.execute(addSyncColumnsToPayments);
    } catch (e) {
      // Column might already exist, ignore error
    }
    try {
      await db.execute(addSyncStatusToPayments);
    } catch (e) {
      // Column might already exist, ignore error
    }
    try {
      await db.execute(addDeviceIdToPayments);
    } catch (e) {
      // Column might already exist, ignore error
    }

    // Create sync-related tables (with error handling for existing tables)
    try {
      await db.execute(createSyncMetadataTable);
    } catch (e) {
      // Table might already exist, ignore error
    }
    try {
      await db.execute(createSyncConflictsTable);
    } catch (e) {
      // Table might already exist, ignore error
    }

    // Create optimization indexes (with error handling for existing indexes)
    for (final index in syncOptimizationIndexes) {
      try {
        await db.execute(index);
      } catch (e) {
        // Index might already exist, ignore error
      }
    }

    // Initialize sync metadata
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.execute('''INSERT OR IGNORE INTO sync_metadata 
       (table_name, created_at, updated_at) 
       VALUES ('patients', $now, $now)''');
    await db.execute('''INSERT OR IGNORE INTO sync_metadata 
       (table_name, created_at, updated_at) 
       VALUES ('visits', $now, $now)''');
    await db.execute('''INSERT OR IGNORE INTO sync_metadata 
       (table_name, created_at, updated_at) 
       VALUES ('payments', $now, $now)''');
  }

  static Future<void> _migrateToVersion3(Database db) async {
    try { await db.execute(addPrescriptionsToVisits); } catch (_) {}
    try { await db.execute(addFollowUpDateToVisits); } catch (_) {}
    try { await db.execute(createSettingsTable); } catch (_) {}
  }

  /// Database creation handler
  static Future<void> onCreate(Database db, int version) async {
    // Create base tables
    await db.execute(createPatientsTable);
    await db.execute(createVisitsTable);
    await db.execute(createPaymentsTable);
    await db.execute(createSettingsTable);

    // If creating at version 2 or higher, add sync features
    if (version >= 2) {
      await _migrateToVersion2(db);
    }
  }

  /// Rollback migration (for testing purposes)
  static Future<void> rollbackToVersion1(Database db) async {
    // Drop sync-related tables
    await db.execute('DROP TABLE IF EXISTS sync_conflicts');
    await db.execute('DROP TABLE IF EXISTS sync_metadata');

    // Drop sync indexes
    final indexNames = [
      'idx_patients_sync_status', 'idx_patients_last_modified', 'idx_patients_device_id',
      'idx_visits_sync_status', 'idx_visits_last_modified', 'idx_visits_device_id', 'idx_visits_patient_id',
      'idx_payments_sync_status', 'idx_payments_last_modified', 'idx_payments_device_id', 'idx_payments_patient_id',
      'idx_sync_conflicts_table_record', 'idx_sync_conflicts_status', 'idx_sync_conflicts_timestamp',
      'idx_patients_sync_modified', 'idx_visits_sync_modified', 'idx_payments_sync_modified',
    ];

    for (final indexName in indexNames) {
      await db.execute('DROP INDEX IF EXISTS $indexName');
    }

    // Note: SQLite doesn't support DROP COLUMN, so we can't remove the sync columns
    // In a real rollback scenario, you would need to recreate the tables without sync columns
  }

  /// Get all table names that support sync
  static List<String> get syncEnabledTables => ['patients', 'visits', 'payments'];

  /// Validate database schema integrity
  static Future<bool> validateSchema(Database db) async {
    try {
      // Check if all required tables exist
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('patients', 'visits', 'payments', 'sync_metadata', 'sync_conflicts')"
      );
      
      if (tables.length != 5) return false;

      // Check if sync columns exist in main tables
      for (final tableName in syncEnabledTables) {
        final columns = await db.rawQuery("PRAGMA table_info($tableName)");
        final columnNames = columns.map((col) => col['name'] as String).toSet();
        
        if (!columnNames.containsAll(['last_modified', 'sync_status', 'device_id'])) {
          return false;
        }
      }

      return true;
    } catch (e) {
      return false;
    }
  }
}