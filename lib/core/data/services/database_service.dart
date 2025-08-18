import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/data_models.dart';
import 'database_schema.dart';

/// Abstract interface for database operations with sync support
abstract class DatabaseService {
  Future<void> initialize();
  Future<void> close();
  
  // Simplified change tracking (for cloud save)
  Future<bool> hasDataChanged() async => true; // Simplified - always assume data has changed
  
  // Database snapshot operations
  Future<Map<String, dynamic>> exportDatabaseSnapshot();
  Future<void> importDatabaseSnapshot(Map<String, dynamic> snapshot);
  
  // Cloud save metadata operations (simplified)
  Future<void> updateSyncMetadata(String key, {int? lastSyncTimestamp});
  Future<Map<String, dynamic>?> getSyncMetadata(String key);
  
  // CRUD operations with sync tracking
  Future<void> insertPatient(Patient patient);
  Future<void> updatePatient(Patient patient);
  Future<void> deletePatient(String patientId);
  Future<Patient?> getPatient(String patientId);
  Future<List<Patient>> getAllPatients();
  
  Future<void> insertVisit(Visit visit);
  Future<void> updateVisit(Visit visit);
  Future<void> deleteVisit(String visitId);
  Future<Visit?> getVisit(String visitId);
  Future<List<Visit>> getVisitsForPatient(String patientId);
  
  Future<void> insertPayment(Payment payment);
  Future<void> updatePayment(Payment payment);
  Future<void> deletePayment(String paymentId);
  Future<Payment?> getPayment(String paymentId);
  Future<List<Payment>> getPaymentsForPatient(String patientId);

  // Aggregates for dashboard
  Future<int> getPatientCount();
  Future<int> getVisitCountBetween(DateTime from, DateTime to);
  Future<double> getRevenueTotalBetween(DateTime from, DateTime to);
  Future<int> getPendingFollowUpsCountUntil(DateTime until);
  Future<List<Visit>> getUpcomingFollowUps({int limit = 5});
  Future<List<Patient>> getRecentPatients({int limit = 5});
  
  // Additional methods for CloudSaveService
  Stream<void> get changesStream;
  Future<Map<String, dynamic>?> getRecordById(String tableName, String recordId);
  Future<void> updateRecord(String tableName, String recordId, Map<String, dynamic> record);
  Future<void> insertRecord(String tableName, Map<String, dynamic> record);
  Future<Map<String, dynamic>?> getSettings(String key);
  Future<void> saveSettings(String key, Map<String, dynamic> settings);
}

/// SQLite implementation of DatabaseService with sync support
class SQLiteDatabaseService implements DatabaseService {
  Database? _database;
  String? _deviceId;
  final StreamController<void> _changeController = StreamController<void>.broadcast();
  
  // Ensures the lightweight key/value settings table exists
  Future<void> _ensureSettingsTable() async {
    final db = database;
    try {
      final sql = DatabaseSchema.createSettingsTable
          .replaceFirst('CREATE TABLE settings', 'CREATE TABLE IF NOT EXISTS settings');
      await db.execute(sql);
    } catch (_) {
      // Ignore – table may already exist or creation raced
    }
  }
  
  // For testing purposes
  set testDatabase(Database database) => _database = database;
  
  SQLiteDatabaseService({String? deviceId}) : _deviceId = deviceId ?? 'unknown_device';
  
  @override
  Future<void> initialize() async {
    if (_database != null) return;
    
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, DatabaseSchema.databaseName);
    
    _database = await openDatabase(
      path,
      version: DatabaseSchema.currentVersion,
      onConfigure: (db) async {
        // Ensure foreign key constraints are enforced so child rows are removed
        // when a parent is deleted (e.g., visits/payments when a patient is deleted)
        await db.execute('PRAGMA foreign_keys=ON');
      },
      onCreate: DatabaseSchema.onCreate,
      onUpgrade: DatabaseSchema.onUpgrade,
    );
    // Defensive: ensure settings table exists even if older DB missed a migration
    await _ensureSettingsTable();
  }
  
  @override
  Future<void> close() async {
    await _database?.close();
    _database = null;
    await _changeController.close();
  }
  
  Database get database {
    if (_database == null) {
      throw StateError('Database not initialized. Call initialize() first.');
    }
    return _database!;
  }
  
  // Simplified change tracking implementation
  @override
  Future<bool> hasDataChanged() async {
    // For now, always return true to trigger saves
    // In a more sophisticated implementation, you could track actual changes
    return true;
  }
  
  @override
  Future<Map<String, dynamic>> exportDatabaseSnapshot() async {
    final snapshot = <String, dynamic>{
      'version': DatabaseSchema.currentVersion,
      'timestamp': DateTime.now().toIso8601String(),
      'device_id': _deviceId,
      'tables': <String, List<Map<String, dynamic>>>{},
    };
    
    // Export all sync-enabled tables
    for (final tableName in DatabaseSchema.syncEnabledTables) {
      final records = await database.query(tableName);
      snapshot['tables'][tableName] = records;
    }
    
    // Export sync metadata
    final syncMetadata = await database.query('sync_metadata');
    snapshot['sync_metadata'] = syncMetadata;
    
    return snapshot;
  }
  
  @override
  Future<void> importDatabaseSnapshot(Map<String, dynamic> snapshot) async {
    final tables = snapshot['tables'] as Map<String, dynamic>;
    final batch = database.batch();
    
    // Clear existing data
    for (final tableName in DatabaseSchema.syncEnabledTables) {
      batch.delete(tableName);
    }
    
    // Import data from snapshot
    for (final entry in tables.entries) {
      final tableName = entry.key;
      final records = entry.value as List<dynamic>;
      
      for (final record in records) {
        final recordMap = Map<String, dynamic>.from(record as Map);
        // Ensure required fields are present
        final now = DateTime.now().millisecondsSinceEpoch;
        recordMap['created_at'] ??= now;
        recordMap['updated_at'] ??= now;
        batch.insert(tableName, recordMap);
      }
    }
    
    await batch.commit(noResult: true);
    
    // Import sync metadata if available
    if (snapshot.containsKey('sync_metadata')) {
      final syncMetadata = snapshot['sync_metadata'] as List<dynamic>;
      final metadataBatch = database.batch();
      
      metadataBatch.delete('sync_metadata');
      for (final metadata in syncMetadata) {
        metadataBatch.insert('sync_metadata', Map<String, dynamic>.from(metadata as Map));
      }
      
      await metadataBatch.commit(noResult: true);
    }
  }
  
  // Simplified sync metadata operations
  @override
  Future<void> updateSyncMetadata(String key, {int? lastSyncTimestamp}) async {
    try {
      await _ensureSettingsTable();
      await database.insert(
        'settings',
        {
          'key': 'sync_metadata_$key',
          'value': jsonEncode({
            'last_sync_timestamp': lastSyncTimestamp,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          }),
          'updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      print('Failed to update sync metadata: $e');
    }
  }
  
  @override
  Future<Map<String, dynamic>?> getSyncMetadata(String key) async {
    try {
      await _ensureSettingsTable();
      final results = await database.query(
        'settings',
        where: 'key = ?',
        whereArgs: ['sync_metadata_$key'],
        limit: 1,
      );
      
      if (results.isNotEmpty) {
        final settingsJson = results.first['value'] as String;
        return jsonDecode(settingsJson) as Map<String, dynamic>;
      }
    } catch (e) {
      print('Failed to get sync metadata: $e');
    }
    
    return null;
  }
  
  // Simplified helper methods removed - no longer needed
  
  void _markRecordModified(Map<String, dynamic> record) {
    record['last_modified'] = DateTime.now().millisecondsSinceEpoch;
    record['sync_status'] = 'pending';
    record['device_id'] = _deviceId;
  }
  
  // CRUD operations with sync tracking
  @override
  Future<void> insertPatient(Patient patient) async {
    final record = patient.toSyncJson();
    _markRecordModified(record);
    
    await database.insert('patients', {
      ...record,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
    
    _changeController.add(null);
  }
  
  @override
  Future<void> updatePatient(Patient patient) async {
    final record = patient.toSyncJson();
    _markRecordModified(record);
    
    await database.update(
      'patients',
      {
        ...record,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [patient.id],
    );
    
    _changeController.add(null);
  }
  
  @override
  Future<void> deletePatient(String patientId) async {
    // Manually cascade delete to handle environments where PRAGMA foreign_keys
    // may not be honored (defensive measure)
    await database.transaction((txn) async {
      await txn.delete('payments', where: 'patient_id = ?', whereArgs: [patientId]);
      await txn.delete('visits', where: 'patient_id = ?', whereArgs: [patientId]);
      await txn.delete('patients', where: 'id = ?', whereArgs: [patientId]);
    });
    
    _changeController.add(null);
  }
  
  @override
  Future<Patient?> getPatient(String patientId) async {
    final records = await database.query(
      'patients',
      where: 'id = ?',
      whereArgs: [patientId],
    );
    
    return records.isNotEmpty ? Patient.fromSyncJson(records.first) : null;
  }
  
  @override
  Future<List<Patient>> getAllPatients() async {
    final records = await database.query('patients', orderBy: 'name ASC');
    return records.map((record) => Patient.fromSyncJson(record)).toList();
  }
  
  @override
  Future<void> insertVisit(Visit visit) async {
    final record = visit.toSyncJson();
    _markRecordModified(record);
    
    await database.insert('visits', {
      ...record,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
    
    await _updatePendingChangesCount('visits');
    _changeController.add(null);
  }
  
  @override
  Future<void> updateVisit(Visit visit) async {
    final record = visit.toSyncJson();
    _markRecordModified(record);
    
    await database.update(
      'visits',
      {
        ...record,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [visit.id],
    );
    
    await _updatePendingChangesCount('visits');
    _changeController.add(null);
  }
  
  @override
  Future<void> deleteVisit(String visitId) async {
    await database.delete(
      'visits',
      where: 'id = ?',
      whereArgs: [visitId],
    );
    
    await _updatePendingChangesCount('visits');
    _changeController.add(null);
  }
  
  @override
  Future<Visit?> getVisit(String visitId) async {
    final records = await database.query(
      'visits',
      where: 'id = ?',
      whereArgs: [visitId],
    );
    
    return records.isNotEmpty ? Visit.fromSyncJson(records.first) : null;
  }
  
  @override
  Future<List<Visit>> getVisitsForPatient(String patientId) async {
    final records = await database.query(
      'visits',
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'visit_date DESC',
    );
    
    return records.map((record) => Visit.fromSyncJson(record)).toList();
  }
  
  @override
  Future<void> insertPayment(Payment payment) async {
    final record = payment.toSyncJson();
    _markRecordModified(record);
    
    await database.insert('payments', {
      ...record,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
    
    await _updatePendingChangesCount('payments');
    _changeController.add(null);
  }
  
  @override
  Future<void> updatePayment(Payment payment) async {
    final record = payment.toSyncJson();
    _markRecordModified(record);
    
    await database.update(
      'payments',
      {
        ...record,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [payment.id],
    );
    
    await _updatePendingChangesCount('payments');
    _changeController.add(null);
  }
  
  @override
  Future<void> deletePayment(String paymentId) async {
    await database.delete(
      'payments',
      where: 'id = ?',
      whereArgs: [paymentId],
    );
    
    await _updatePendingChangesCount('payments');
    _changeController.add(null);
  }
  
  @override
  Future<Payment?> getPayment(String paymentId) async {
    final records = await database.query(
      'payments',
      where: 'id = ?',
      whereArgs: [paymentId],
    );
    
    return records.isNotEmpty ? Payment.fromSyncJson(records.first) : null;
  }
  
  @override
  Future<List<Payment>> getPaymentsForPatient(String patientId) async {
    final records = await database.query(
      'payments',
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'payment_date DESC',
    );
    
    return records.map((record) => Payment.fromSyncJson(record)).toList();
  }

  // Dashboard aggregates
  @override
  Future<int> getPatientCount() async {
    final result = await database.rawQuery('SELECT COUNT(*) as c FROM patients');
    return (result.first['c'] as int?) ?? 0;
  }

  @override
  Future<int> getVisitCountBetween(DateTime from, DateTime to) async {
    final result = await database.rawQuery(
      'SELECT COUNT(*) as c FROM visits WHERE visit_date BETWEEN ? AND ?',
      [from.toIso8601String(), to.toIso8601String()],
    );
    return (result.first['c'] as int?) ?? 0;
  }

  @override
  Future<double> getRevenueTotalBetween(DateTime from, DateTime to) async {
    final result = await database.rawQuery(
      'SELECT IFNULL(SUM(amount),0) as s FROM payments WHERE payment_date BETWEEN ? AND ?',
      [from.toIso8601String(), to.toIso8601String()],
    );
    final value = result.first['s'];
    if (value is int) return value.toDouble();
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return 0;
  }

  @override
  Future<int> getPendingFollowUpsCountUntil(DateTime until) async {
    final result = await database.rawQuery(
      'SELECT COUNT(*) as c FROM visits WHERE follow_up_date IS NOT NULL AND follow_up_date <= ?',
      [until.toIso8601String()],
    );
    return (result.first['c'] as int?) ?? 0;
  }

  @override
  Future<List<Visit>> getUpcomingFollowUps({int limit = 5}) async {
    final records = await database.rawQuery(
      'SELECT * FROM visits WHERE follow_up_date IS NOT NULL AND follow_up_date >= ? ORDER BY follow_up_date ASC LIMIT ?',
      [DateTime.now().toIso8601String(), limit],
    );
    return records.map((e) => Visit.fromSyncJson(Map<String, dynamic>.from(e))).toList();
  }

  @override
  Future<List<Patient>> getRecentPatients({int limit = 5}) async {
    final records = await database.rawQuery(
      'SELECT * FROM patients ORDER BY created_at DESC LIMIT ?',
      [limit],
    );
    return records.map((e) => Patient.fromSyncJson(Map<String, dynamic>.from(e))).toList();
  }

  // Additional methods for CloudSaveService
  
  /// Stream that emits when database changes occur
  @override
  Stream<void> get changesStream {
    return _changeController.stream;
  }

  /// Get a record by ID from any table
  @override
  Future<Map<String, dynamic>?> getRecordById(String tableName, String recordId) async {
    final db = database;
    final results = await db.query(
      tableName,
      where: 'id = ?',
      whereArgs: [recordId],
      limit: 1,
    );
    
    return results.isNotEmpty ? results.first : null;
  }

  /// Update a record in any table
  @override
  Future<void> updateRecord(String tableName, String recordId, Map<String, dynamic> record) async {
    final db = database;
    await db.update(
      tableName,
      record,
      where: 'id = ?',
      whereArgs: [recordId],
    );
  }

  /// Insert a record into any table
  @override
  Future<void> insertRecord(String tableName, Map<String, dynamic> record) async {
    final db = database;
    await db.insert(
      tableName,
      record,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get settings by key
  @override
  Future<Map<String, dynamic>?> getSettings(String key) async {
    final db = database;
    await _ensureSettingsTable();
    final results = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    
    if (results.isNotEmpty) {
      final settingsJson = results.first['value'] as String;
      return jsonDecode(settingsJson) as Map<String, dynamic>;
    }
    
    return null;
  }

  /// Save settings by key
  @override
  Future<void> saveSettings(String key, Map<String, dynamic> settings) async {
    final db = database;
    final settingsJson = jsonEncode(settings);
    await _ensureSettingsTable();
    
    await db.insert(
      'settings',
      {
        'key': key,
        'value': settingsJson,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Internal helper for legacy pending-changes updates (no-op in simplified model)
  Future<void> _updatePendingChangesCount(String tableName) async {
    try {
      // In the simplified CloudSave model we don't track pending counts.
      // Touch the metadata timestamp so dependent code continues to work.
      await updateSyncMetadata(tableName, lastSyncTimestamp: DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      print('Failed to update pending changes count for $tableName: $e');
    }
  }
}