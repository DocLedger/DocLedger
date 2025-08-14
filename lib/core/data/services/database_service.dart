import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/data_models.dart';
import 'database_schema.dart';

/// Abstract interface for database operations with sync support
abstract class DatabaseService {
  Future<void> initialize();
  Future<void> close();
  
  // Change tracking methods
  Future<List<Map<String, dynamic>>> getChangedRecords(String tableName, int sinceTimestamp);
  Future<void> markRecordsSynced(String tableName, List<String> recordIds);
  Future<void> applyRemoteChanges(String tableName, List<Map<String, dynamic>> records);
  
  // Conflict resolution
  Future<List<SyncConflict>> detectConflicts(String tableName, List<Map<String, dynamic>> remoteRecords);
  Future<void> storeConflict(SyncConflict conflict);
  Future<List<SyncConflict>> getPendingConflicts();
  Future<void> resolveConflict(String conflictId, ConflictResolution resolution);
  
  // Database snapshot operations
  Future<Map<String, dynamic>> exportDatabaseSnapshot();
  Future<void> importDatabaseSnapshot(Map<String, dynamic> snapshot);
  
  // Sync metadata operations
  Future<void> updateSyncMetadata(String tableName, {
    int? lastSyncTimestamp,
    int? lastBackupTimestamp,
    int? pendingChangesCount,
    int? conflictCount,
  });
  Future<Map<String, dynamic>?> getSyncMetadata(String tableName);
  
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
}

/// SQLite implementation of DatabaseService with sync support
class SQLiteDatabaseService implements DatabaseService {
  Database? _database;
  String? _deviceId;
  
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
      onCreate: DatabaseSchema.onCreate,
      onUpgrade: DatabaseSchema.onUpgrade,
    );
  }
  
  @override
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
  
  Database get database {
    if (_database == null) {
      throw StateError('Database not initialized. Call initialize() first.');
    }
    return _database!;
  }
  
  @override
  Future<List<Map<String, dynamic>>> getChangedRecords(String tableName, int sinceTimestamp) async {
    final records = await database.query(
      tableName,
      where: 'last_modified > ? AND sync_status = ?',
      whereArgs: [sinceTimestamp, 'pending'],
      orderBy: 'last_modified ASC',
    );
    return records;
  }
  
  @override
  Future<void> markRecordsSynced(String tableName, List<String> recordIds) async {
    if (recordIds.isEmpty) return;
    
    final batch = database.batch();
    for (final recordId in recordIds) {
      batch.update(
        tableName,
        {'sync_status': 'synced'},
        where: 'id = ?',
        whereArgs: [recordId],
      );
    }
    await batch.commit(noResult: true);
    
    // Update sync metadata
    await _updatePendingChangesCount(tableName);
  }
  
  @override
  Future<void> applyRemoteChanges(String tableName, List<Map<String, dynamic>> records) async {
    if (records.isEmpty) return;
    
    final batch = database.batch();
    final conflicts = <SyncConflict>[];
    
    for (final remoteRecord in records) {
      final recordId = remoteRecord['id'] as String;
      final remoteTimestamp = remoteRecord['last_modified'] as int;
      
      // Check if local record exists
      final localRecords = await database.query(
        tableName,
        where: 'id = ?',
        whereArgs: [recordId],
      );
      
      if (localRecords.isEmpty) {
        // No local record, insert remote record
        final now = DateTime.now().millisecondsSinceEpoch;
        batch.insert(tableName, {
          ...remoteRecord,
          'sync_status': 'synced',
          'created_at': now,
          'updated_at': now,
        });
      } else {
        final localRecord = localRecords.first;
        final localTimestamp = localRecord['last_modified'] as int;
        
        final localSyncStatus = localRecord['sync_status'] as String;
        
        // If local record has pending changes, create conflict regardless of timestamp
        if (localSyncStatus == 'pending') {
          conflicts.add(SyncConflict(
            id: '${tableName}_${recordId}_${DateTime.now().millisecondsSinceEpoch}',
            tableName: tableName,
            recordId: recordId,
            localData: Map<String, dynamic>.from(localRecord),
            remoteData: remoteRecord,
            conflictTime: DateTime.now(),
            type: ConflictType.updateConflict,
            description: 'Local record has pending changes that conflict with remote',
          ));
        } else if (localTimestamp < remoteTimestamp) {
          // Remote is newer and local is synced, update local record
          batch.update(
            tableName,
            {
              ...remoteRecord,
              'sync_status': 'synced',
              'updated_at': DateTime.now().millisecondsSinceEpoch,
            },
            where: 'id = ?',
            whereArgs: [recordId],
          );
        }
        // If timestamps are equal or local is newer but synced, no action needed
      }
    }
    
    await batch.commit(noResult: true);
    
    // Store any conflicts found
    for (final conflict in conflicts) {
      await storeConflict(conflict);
    }
    
    // Update sync metadata
    await updateSyncMetadata(tableName, 
      lastSyncTimestamp: DateTime.now().millisecondsSinceEpoch,
      conflictCount: conflicts.length,
    );
  }
  
  @override
  Future<List<SyncConflict>> detectConflicts(String tableName, List<Map<String, dynamic>> remoteRecords) async {
    final conflicts = <SyncConflict>[];
    
    for (final remoteRecord in remoteRecords) {
      final recordId = remoteRecord['id'] as String;
      final remoteTimestamp = remoteRecord['last_modified'] as int;
      
      final localRecords = await database.query(
        tableName,
        where: 'id = ?',
        whereArgs: [recordId],
      );
      
      if (localRecords.isNotEmpty) {
        final localRecord = localRecords.first;
        final localTimestamp = localRecord['last_modified'] as int;
        final localSyncStatus = localRecord['sync_status'] as String;
        
        // Conflict if both records have been modified and local is pending sync
        if (localSyncStatus == 'pending' && localTimestamp != remoteTimestamp) {
          conflicts.add(SyncConflict(
            id: '${tableName}_${recordId}_${DateTime.now().millisecondsSinceEpoch}',
            tableName: tableName,
            recordId: recordId,
            localData: Map<String, dynamic>.from(localRecord),
            remoteData: remoteRecord,
            conflictTime: DateTime.now(),
            type: ConflictType.updateConflict,
            description: 'Both local and remote records have been modified',
          ));
        }
      }
    }
    
    return conflicts;
  }
  
  @override
  Future<void> storeConflict(SyncConflict conflict) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await database.insert('sync_conflicts', {
      'id': conflict.id,
      'table_name': conflict.tableName,
      'record_id': conflict.recordId,
      'local_data': jsonEncode(conflict.localData),
      'remote_data': jsonEncode(conflict.remoteData),
      'conflict_timestamp': conflict.conflictTime.millisecondsSinceEpoch,
      'conflict_type': conflict.type.name,
      'resolution_status': 'pending',
      'notes': conflict.description,
      'created_at': now,
      'updated_at': now,
    });
    
    // Update conflict count in sync metadata
    await _incrementConflictCount(conflict.tableName);
  }
  
  @override
  Future<List<SyncConflict>> getPendingConflicts() async {
    final records = await database.query(
      'sync_conflicts',
      where: 'resolution_status = ?',
      whereArgs: ['pending'],
      orderBy: 'conflict_timestamp DESC',
    );
    
    return records.map((record) => SyncConflict.fromJson(record)).toList();
  }
  
  @override
  Future<void> resolveConflict(String conflictId, ConflictResolution resolution) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // Update conflict record
    await database.update(
      'sync_conflicts',
      {
        'resolution_status': 'resolved',
        'resolved_data': jsonEncode(resolution.resolvedData),
        'resolution_timestamp': resolution.resolutionTime.millisecondsSinceEpoch,
        'resolution_strategy': resolution.strategy.name,
        'notes': resolution.notes,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [conflictId],
    );
    
    // Get conflict details to update the actual record
    final conflictRecords = await database.query(
      'sync_conflicts',
      where: 'id = ?',
      whereArgs: [conflictId],
    );
    
    if (conflictRecords.isNotEmpty) {
      final conflict = conflictRecords.first;
      final tableName = conflict['table_name'] as String;
      final recordId = conflict['record_id'] as String;
      
      // Apply the resolved data to the actual table
      await database.update(
        tableName,
        {
          ...resolution.resolvedData,
          'sync_status': 'pending', // Mark for re-sync
          'last_modified': now,
        },
        where: 'id = ?',
        whereArgs: [recordId],
      );
      
      // Update conflict count in sync metadata
      await _decrementConflictCount(tableName);
    }
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
  
  @override
  Future<void> updateSyncMetadata(String tableName, {
    int? lastSyncTimestamp,
    int? lastBackupTimestamp,
    int? pendingChangesCount,
    int? conflictCount,
  }) async {
    final updates = <String, dynamic>{
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    };
    
    if (lastSyncTimestamp != null) updates['last_sync_timestamp'] = lastSyncTimestamp;
    if (lastBackupTimestamp != null) updates['last_backup_timestamp'] = lastBackupTimestamp;
    if (pendingChangesCount != null) updates['pending_changes_count'] = pendingChangesCount;
    if (conflictCount != null) updates['conflict_count'] = conflictCount;
    
    await database.update(
      'sync_metadata',
      updates,
      where: 'table_name = ?',
      whereArgs: [tableName],
    );
  }
  
  @override
  Future<Map<String, dynamic>?> getSyncMetadata(String tableName) async {
    final records = await database.query(
      'sync_metadata',
      where: 'table_name = ?',
      whereArgs: [tableName],
    );
    
    return records.isNotEmpty ? records.first : null;
  }
  
  // Helper methods
  Future<void> _updatePendingChangesCount(String tableName) async {
    final count = Sqflite.firstIntValue(await database.rawQuery(
      'SELECT COUNT(*) FROM $tableName WHERE sync_status = ?',
      ['pending'],
    )) ?? 0;
    
    await updateSyncMetadata(tableName, pendingChangesCount: count);
  }
  
  Future<void> _incrementConflictCount(String tableName) async {
    final metadata = await getSyncMetadata(tableName);
    final currentCount = metadata?['conflict_count'] as int? ?? 0;
    await updateSyncMetadata(tableName, conflictCount: currentCount + 1);
  }
  
  Future<void> _decrementConflictCount(String tableName) async {
    final metadata = await getSyncMetadata(tableName);
    final currentCount = metadata?['conflict_count'] as int? ?? 0;
    await updateSyncMetadata(tableName, conflictCount: (currentCount - 1).clamp(0, double.infinity).toInt());
  }
  
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
    
    await _updatePendingChangesCount('patients');
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
    
    await _updatePendingChangesCount('patients');
  }
  
  @override
  Future<void> deletePatient(String patientId) async {
    await database.delete(
      'patients',
      where: 'id = ?',
      whereArgs: [patientId],
    );
    
    await _updatePendingChangesCount('patients');
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
  }
  
  @override
  Future<void> deleteVisit(String visitId) async {
    await database.delete(
      'visits',
      where: 'id = ?',
      whereArgs: [visitId],
    );
    
    await _updatePendingChangesCount('visits');
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
  }
  
  @override
  Future<void> deletePayment(String paymentId) async {
    await database.delete(
      'payments',
      where: 'id = ?',
      whereArgs: [paymentId],
    );
    
    await _updatePendingChangesCount('payments');
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
}