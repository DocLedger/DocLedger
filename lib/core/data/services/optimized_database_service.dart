import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/data_models.dart';
import 'database_schema.dart';
import 'database_service.dart';

/// Connection pool for managing database connections efficiently
class DatabaseConnectionPool {
  final Queue<Database> _availableConnections = Queue<Database>();
  final Set<Database> _allConnections = <Database>{};
  final int _maxConnections;
  final String _databasePath;
  bool _isInitialized = false;
  
  DatabaseConnectionPool({
    int maxConnections = 5,
    required String databasePath,
  }) : _maxConnections = maxConnections,
       _databasePath = databasePath;

  /// Initialize the connection pool
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    // Create initial connections
    for (int i = 0; i < _maxConnections; i++) {
      final db = await openDatabase(
        _databasePath,
        version: DatabaseSchema.currentVersion,
        onCreate: DatabaseSchema.onCreate,
        onUpgrade: DatabaseSchema.onUpgrade,
      );
      _availableConnections.add(db);
      _allConnections.add(db);
    }
    
    _isInitialized = true;
  }

  /// Get a database connection from the pool
  Future<Database> getConnection() async {
    if (!_isInitialized) {
      await initialize();
    }
    
    if (_availableConnections.isNotEmpty) {
      return _availableConnections.removeFirst();
    }
    
    // If no connections available, wait briefly and try again
    await Future.delayed(const Duration(milliseconds: 10));
    return getConnection();
  }

  /// Return a connection to the pool
  void returnConnection(Database db) {
    if (_allConnections.contains(db)) {
      _availableConnections.add(db);
    }
  }

  /// Close all connections in the pool
  Future<void> close() async {
    for (final db in _allConnections) {
      await db.close();
    }
    _availableConnections.clear();
    _allConnections.clear();
    _isInitialized = false;
  }

  /// Get pool statistics
  Map<String, int> get stats => {
    'total_connections': _allConnections.length,
    'available_connections': _availableConnections.length,
    'active_connections': _allConnections.length - _availableConnections.length,
  };
}

/// Optimized SQLite database service with connection pooling and performance enhancements
class OptimizedSQLiteDatabaseService implements DatabaseService {
  late DatabaseConnectionPool _connectionPool;
  String? _deviceId;
  bool _isInitialized = false;
  
  // Lazy loading cache for frequently accessed data
  final Map<String, List<Patient>> _patientCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheExpiry = Duration(minutes: 5);
  
  // Batch operation queue for improved performance
  final List<_BatchOperation> _batchQueue = [];
  Timer? _batchTimer;
  static const Duration _batchDelay = Duration(milliseconds: 100);
  
  OptimizedSQLiteDatabaseService({String? deviceId}) : _deviceId = deviceId ?? 'unknown_device';
  
  @override
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, DatabaseSchema.databaseName);
    
    _connectionPool = DatabaseConnectionPool(
      maxConnections: 5,
      databasePath: path,
    );
    
    await _connectionPool.initialize();
    
    // Optimize database settings for performance
    final db = await _connectionPool.getConnection();
    try {
      // Enable WAL mode for better concurrent access
      await db.execute('PRAGMA journal_mode=WAL');
      // Increase cache size for better performance
      await db.execute('PRAGMA cache_size=10000');
      // Enable foreign key constraints
      await db.execute('PRAGMA foreign_keys=ON');
      // Optimize synchronous mode for better performance
      await db.execute('PRAGMA synchronous=NORMAL');
      // Set temp store to memory for faster operations
      await db.execute('PRAGMA temp_store=MEMORY');
    } finally {
      _connectionPool.returnConnection(db);
    }
    
    _isInitialized = true;
  }
  
  @override
  Future<void> close() async {
    _batchTimer?.cancel();
    await _processBatchQueue();
    await _connectionPool.close();
    _patientCache.clear();
    _cacheTimestamps.clear();
    _isInitialized = false;
  }
  
  /// Execute a database operation with connection pooling
  Future<T> _executeWithConnection<T>(Future<T> Function(Database db) operation) async {
    if (!_isInitialized) {
      await initialize();
    }
    
    final db = await _connectionPool.getConnection();
    try {
      return await operation(db);
    } finally {
      _connectionPool.returnConnection(db);
    }
  }
  
  /// Execute multiple operations in a single transaction for better performance
  Future<List<T>> _executeBatch<T>(List<Future<T> Function(Database db)> operations) async {
    return _executeWithConnection<List<T>>((db) async {
      final results = <T>[];
      await db.transaction((txn) async {
        for (final operation in operations) {
          final result = await operation(txn);
          results.add(result);
        }
      });
      return results;
    });
  }
  
  @override
  Future<List<Map<String, dynamic>>> getChangedRecords(String tableName, int sinceTimestamp) async {
    return _executeWithConnection((db) async {
      // Use optimized query with proper indexing
      return await db.query(
        tableName,
        where: 'last_modified > ? AND sync_status = ?',
        whereArgs: [sinceTimestamp, 'pending'],
        orderBy: 'last_modified ASC',
        // Limit results to prevent memory issues with very large datasets
        limit: 10000,
      );
    });
  }
  
  @override
  Future<void> markRecordsSynced(String tableName, List<String> recordIds) async {
    if (recordIds.isEmpty) return;
    
    // Use batch operations for better performance
    await _executeWithConnection((db) async {
      await db.transaction((txn) async {
        // Use batch update for better performance
        final batch = txn.batch();
        for (final recordId in recordIds) {
          batch.update(
            tableName,
            {'sync_status': 'synced'},
            where: 'id = ?',
            whereArgs: [recordId],
          );
        }
        await batch.commit(noResult: true);
      });
    });
    
    // Update sync metadata
    await _updatePendingChangesCount(tableName);
    
    // Invalidate cache for this table
    _invalidateCache(tableName);
  }
  
  @override
  Future<void> applyRemoteChanges(String tableName, List<Map<String, dynamic>> records) async {
    if (records.isEmpty) return;
    
    await _executeWithConnection((db) async {
      await db.transaction((txn) async {
        final batch = txn.batch();
        final conflicts = <SyncConflict>[];
        
        // Process records in chunks for better memory management
        const chunkSize = 100;
        for (int i = 0; i < records.length; i += chunkSize) {
          final chunk = records.skip(i).take(chunkSize).toList();
          
          for (final remoteRecord in chunk) {
            final recordId = remoteRecord['id'] as String;
            final remoteTimestamp = remoteRecord['last_modified'] as int;
            
            // Check if local record exists
            final localRecords = await txn.query(
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
              
              // If local record has pending changes, create conflict
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
            }
          }
        }
        
        await batch.commit(noResult: true);
        
        // Store conflicts in batch
        if (conflicts.isNotEmpty) {
          final conflictBatch = txn.batch();
          for (final conflict in conflicts) {
            final now = DateTime.now().millisecondsSinceEpoch;
            conflictBatch.insert('sync_conflicts', {
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
          }
          await conflictBatch.commit(noResult: true);
        }
      });
    });
    
    // Update sync metadata
    await updateSyncMetadata(tableName, 
      lastSyncTimestamp: DateTime.now().millisecondsSinceEpoch,
    );
    
    // Invalidate cache
    _invalidateCache(tableName);
  }
  
  @override
  Future<List<SyncConflict>> detectConflicts(String tableName, List<Map<String, dynamic>> remoteRecords) async {
    return _executeWithConnection((db) async {
      final conflicts = <SyncConflict>[];
      
      // Process in chunks for better performance
      const chunkSize = 100;
      for (int i = 0; i < remoteRecords.length; i += chunkSize) {
        final chunk = remoteRecords.skip(i).take(chunkSize).toList();
        
        for (final remoteRecord in chunk) {
          final recordId = remoteRecord['id'] as String;
          final remoteTimestamp = remoteRecord['last_modified'] as int;
          
          final localRecords = await db.query(
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
      }
      
      return conflicts;
    });
  }
  
  @override
  Future<void> storeConflict(SyncConflict conflict) async {
    await _executeWithConnection((db) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('sync_conflicts', {
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
    });
    
    // Update conflict count in sync metadata
    await _incrementConflictCount(conflict.tableName);
  }
  
  @override
  Future<List<SyncConflict>> getPendingConflicts() async {
    return _executeWithConnection((db) async {
      final records = await db.query(
        'sync_conflicts',
        where: 'resolution_status = ?',
        whereArgs: ['pending'],
        orderBy: 'conflict_timestamp DESC',
        limit: 1000, // Limit to prevent memory issues
      );
      
      return records.map((record) => SyncConflict.fromJson(record)).toList();
    });
  }
  
  @override
  Future<void> resolveConflict(String conflictId, ConflictResolution resolution) async {
    await _executeWithConnection((db) async {
      await db.transaction((txn) async {
        final now = DateTime.now().millisecondsSinceEpoch;
        
        // Update conflict record
        await txn.update(
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
        final conflictRecords = await txn.query(
          'sync_conflicts',
          where: 'id = ?',
          whereArgs: [conflictId],
        );
        
        if (conflictRecords.isNotEmpty) {
          final conflict = conflictRecords.first;
          final tableName = conflict['table_name'] as String;
          final recordId = conflict['record_id'] as String;
          
          // Apply the resolved data to the actual table
          await txn.update(
            tableName,
            {
              ...resolution.resolvedData,
              'sync_status': 'pending', // Mark for re-sync
              'last_modified': now,
            },
            where: 'id = ?',
            whereArgs: [recordId],
          );
        }
      });
    });
    
    // Update conflict count in sync metadata
    await _decrementConflictCount(''); // Will be updated in the transaction
    
    // Invalidate cache
    _invalidateCache('all');
  }
  
  @override
  Future<Map<String, dynamic>> exportDatabaseSnapshot() async {
    return _executeWithConnection((db) async {
      final snapshot = <String, dynamic>{
        'version': DatabaseSchema.currentVersion,
        'timestamp': DateTime.now().toIso8601String(),
        'device_id': _deviceId,
        'tables': <String, List<Map<String, dynamic>>>{},
      };
      
      // Export all sync-enabled tables in chunks
      for (final tableName in DatabaseSchema.syncEnabledTables) {
        final allRecords = <Map<String, dynamic>>[];
        int offset = 0;
        const chunkSize = 1000;
        
        while (true) {
          final records = await db.query(
            tableName,
            limit: chunkSize,
            offset: offset,
          );
          
          if (records.isEmpty) break;
          
          allRecords.addAll(records);
          offset += chunkSize;
        }
        
        snapshot['tables'][tableName] = allRecords;
      }
      
      // Export sync metadata
      final syncMetadata = await db.query('sync_metadata');
      snapshot['sync_metadata'] = syncMetadata;
      
      return snapshot;
    });
  }
  
  @override
  Future<void> importDatabaseSnapshot(Map<String, dynamic> snapshot) async {
    await _executeWithConnection((db) async {
      await db.transaction((txn) async {
        final tables = snapshot['tables'] as Map<String, dynamic>;
        
        // Clear existing data
        for (final tableName in DatabaseSchema.syncEnabledTables) {
          await txn.delete(tableName);
        }
        
        // Import data from snapshot in chunks
        for (final entry in tables.entries) {
          final tableName = entry.key;
          final records = entry.value as List<dynamic>;
          
          const chunkSize = 100;
          for (int i = 0; i < records.length; i += chunkSize) {
            final chunk = records.skip(i).take(chunkSize).toList();
            final batch = txn.batch();
            
            for (final record in chunk) {
              final recordMap = Map<String, dynamic>.from(record as Map);
              // Ensure required fields are present
              final now = DateTime.now().millisecondsSinceEpoch;
              recordMap['created_at'] ??= now;
              recordMap['updated_at'] ??= now;
              batch.insert(tableName, recordMap);
            }
            
            await batch.commit(noResult: true);
          }
        }
        
        // Import sync metadata if available
        if (snapshot.containsKey('sync_metadata')) {
          final syncMetadata = snapshot['sync_metadata'] as List<dynamic>;
          
          await txn.delete('sync_metadata');
          for (final metadata in syncMetadata) {
            await txn.insert('sync_metadata', Map<String, dynamic>.from(metadata as Map));
          }
        }
      });
    });
    
    // Clear all caches after import
    _invalidateCache('all');
  }
  
  @override
  Future<void> updateSyncMetadata(String tableName, {
    int? lastSyncTimestamp,
    int? lastBackupTimestamp,
    int? pendingChangesCount,
    int? conflictCount,
  }) async {
    await _executeWithConnection((db) async {
      final updates = <String, dynamic>{
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      };
      
      if (lastSyncTimestamp != null) updates['last_sync_timestamp'] = lastSyncTimestamp;
      if (lastBackupTimestamp != null) updates['last_backup_timestamp'] = lastBackupTimestamp;
      if (pendingChangesCount != null) updates['pending_changes_count'] = pendingChangesCount;
      if (conflictCount != null) updates['conflict_count'] = conflictCount;
      
      await db.update(
        'sync_metadata',
        updates,
        where: 'table_name = ?',
        whereArgs: [tableName],
      );
    });
  }
  
  @override
  Future<Map<String, dynamic>?> getSyncMetadata(String tableName) async {
    return _executeWithConnection((db) async {
      final records = await db.query(
        'sync_metadata',
        where: 'table_name = ?',
        whereArgs: [tableName],
      );
      
      return records.isNotEmpty ? records.first : null;
    });
  }
  
  // Helper methods
  Future<void> _updatePendingChangesCount(String tableName) async {
    await _executeWithConnection((db) async {
      final count = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM $tableName WHERE sync_status = ?',
        ['pending'],
      )) ?? 0;
      
      await updateSyncMetadata(tableName, pendingChangesCount: count);
    });
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
  
  /// Cache management methods
  void _invalidateCache(String tableName) {
    if (tableName == 'all') {
      _patientCache.clear();
      _cacheTimestamps.clear();
    } else {
      _patientCache.remove(tableName);
      _cacheTimestamps.remove(tableName);
    }
  }
  
  bool _isCacheValid(String key) {
    final timestamp = _cacheTimestamps[key];
    if (timestamp == null) return false;
    return DateTime.now().difference(timestamp) < _cacheExpiry;
  }
  
  /// Batch operation management
  void _addToBatchQueue(_BatchOperation operation) {
    _batchQueue.add(operation);
    
    // Start batch timer if not already running
    _batchTimer ??= Timer(_batchDelay, _processBatchQueue);
  }
  
  Future<void> _processBatchQueue() async {
    if (_batchQueue.isEmpty) return;
    
    final operations = List<_BatchOperation>.from(_batchQueue);
    _batchQueue.clear();
    _batchTimer = null;
    
    // Group operations by type for better performance
    final insertOperations = operations.where((op) => op.type == _BatchOperationType.insert).toList();
    final updateOperations = operations.where((op) => op.type == _BatchOperationType.update).toList();
    final deleteOperations = operations.where((op) => op.type == _BatchOperationType.delete).toList();
    
    await _executeWithConnection((db) async {
      await db.transaction((txn) async {
        final batch = txn.batch();
        
        // Process inserts
        for (final op in insertOperations) {
          batch.insert(op.tableName, op.data!);
        }
        
        // Process updates
        for (final op in updateOperations) {
          batch.update(
            op.tableName,
            op.data!,
            where: op.whereClause,
            whereArgs: op.whereArgs,
          );
        }
        
        // Process deletes
        for (final op in deleteOperations) {
          batch.delete(
            op.tableName,
            where: op.whereClause,
            whereArgs: op.whereArgs,
          );
        }
        
        await batch.commit(noResult: true);
      });
    });
  }
  
  // CRUD operations with optimizations (implementing interface methods)
  @override
  Future<void> insertPatient(Patient patient) async {
    final record = patient.toSyncJson();
    _markRecordModified(record);
    
    await _executeWithConnection((db) async {
      await db.insert('patients', {
        ...record,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
    });
    
    await _updatePendingChangesCount('patients');
    _invalidateCache('patients');
  }
  
  @override
  Future<void> updatePatient(Patient patient) async {
    final record = patient.toSyncJson();
    _markRecordModified(record);
    
    await _executeWithConnection((db) async {
      await db.update(
        'patients',
        {
          ...record,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [patient.id],
      );
    });
    
    await _updatePendingChangesCount('patients');
    _invalidateCache('patients');
  }
  
  @override
  Future<void> deletePatient(String patientId) async {
    await _executeWithConnection((db) async {
      await db.delete(
        'patients',
        where: 'id = ?',
        whereArgs: [patientId],
      );
    });
    
    await _updatePendingChangesCount('patients');
    _invalidateCache('patients');
  }
  
  @override
  Future<Patient?> getPatient(String patientId) async {
    return _executeWithConnection((db) async {
      final records = await db.query(
        'patients',
        where: 'id = ?',
        whereArgs: [patientId],
      );
      
      return records.isNotEmpty ? Patient.fromSyncJson(records.first) : null;
    });
  }
  
  @override
  Future<List<Patient>> getAllPatients() async {
    // Check cache first
    const cacheKey = 'all_patients';
    if (_isCacheValid(cacheKey) && _patientCache.containsKey(cacheKey)) {
      return _patientCache[cacheKey]!;
    }
    
    final patients = await _executeWithConnection((db) async {
      final records = await db.query('patients', orderBy: 'name ASC');
      return records.map((record) => Patient.fromSyncJson(record)).toList();
    });
    
    // Cache the results
    _patientCache[cacheKey] = patients;
    _cacheTimestamps[cacheKey] = DateTime.now();
    
    return patients;
  }
  
  // Similar implementations for Visit and Payment operations...
  @override
  Future<void> insertVisit(Visit visit) async {
    final record = visit.toSyncJson();
    _markRecordModified(record);
    
    await _executeWithConnection((db) async {
      await db.insert('visits', {
        ...record,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
    });
    
    await _updatePendingChangesCount('visits');
  }
  
  @override
  Future<void> updateVisit(Visit visit) async {
    final record = visit.toSyncJson();
    _markRecordModified(record);
    
    await _executeWithConnection((db) async {
      await db.update(
        'visits',
        {
          ...record,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [visit.id],
      );
    });
    
    await _updatePendingChangesCount('visits');
  }
  
  @override
  Future<void> deleteVisit(String visitId) async {
    await _executeWithConnection((db) async {
      await db.delete(
        'visits',
        where: 'id = ?',
        whereArgs: [visitId],
      );
    });
    
    await _updatePendingChangesCount('visits');
  }
  
  @override
  Future<Visit?> getVisit(String visitId) async {
    return _executeWithConnection((db) async {
      final records = await db.query(
        'visits',
        where: 'id = ?',
        whereArgs: [visitId],
      );
      
      return records.isNotEmpty ? Visit.fromSyncJson(records.first) : null;
    });
  }
  
  @override
  Future<List<Visit>> getVisitsForPatient(String patientId) async {
    return _executeWithConnection((db) async {
      final records = await db.query(
        'visits',
        where: 'patient_id = ?',
        whereArgs: [patientId],
        orderBy: 'visit_date DESC',
      );
      
      return records.map((record) => Visit.fromSyncJson(record)).toList();
    });
  }
  
  @override
  Future<void> insertPayment(Payment payment) async {
    final record = payment.toSyncJson();
    _markRecordModified(record);
    
    await _executeWithConnection((db) async {
      await db.insert('payments', {
        ...record,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
    });
    
    await _updatePendingChangesCount('payments');
  }
  
  @override
  Future<void> updatePayment(Payment payment) async {
    final record = payment.toSyncJson();
    _markRecordModified(record);
    
    await _executeWithConnection((db) async {
      await db.update(
        'payments',
        {
          ...record,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [payment.id],
      );
    });
    
    await _updatePendingChangesCount('payments');
  }
  
  @override
  Future<void> deletePayment(String paymentId) async {
    await _executeWithConnection((db) async {
      await db.delete(
        'payments',
        where: 'id = ?',
        whereArgs: [paymentId],
      );
    });
    
    await _updatePendingChangesCount('payments');
  }
  
  @override
  Future<Payment?> getPayment(String paymentId) async {
    return _executeWithConnection((db) async {
      final records = await db.query(
        'payments',
        where: 'id = ?',
        whereArgs: [paymentId],
      );
      
      return records.isNotEmpty ? Payment.fromSyncJson(records.first) : null;
    });
  }
  
  @override
  Future<List<Payment>> getPaymentsForPatient(String patientId) async {
    return _executeWithConnection((db) async {
      final records = await db.query(
        'payments',
        where: 'patient_id = ?',
        whereArgs: [patientId],
        orderBy: 'payment_date DESC',
      );
      
      return records.map((record) => Payment.fromSyncJson(record)).toList();
    });
  }
  
  /// Get connection pool statistics for monitoring
  Map<String, int> getConnectionPoolStats() {
    return _connectionPool.stats;
  }
  
  /// Perform database maintenance operations
  Future<void> performMaintenance() async {
    await _executeWithConnection((db) async {
      // Analyze tables for query optimization
      await db.execute('ANALYZE');
      
      // Vacuum database to reclaim space (only if needed)
      final pageCount = Sqflite.firstIntValue(await db.rawQuery('PRAGMA page_count')) ?? 0;
      final freePageCount = Sqflite.firstIntValue(await db.rawQuery('PRAGMA freelist_count')) ?? 0;
      
      // Vacuum if more than 25% of pages are free
      if (freePageCount > pageCount * 0.25) {
        await db.execute('VACUUM');
      }
      
      // Update table statistics
      await db.execute('PRAGMA optimize');
    });
  }
}

/// Batch operation for queuing database operations
class _BatchOperation {
  final _BatchOperationType type;
  final String tableName;
  final Map<String, dynamic>? data;
  final String? whereClause;
  final List<dynamic>? whereArgs;
  
  _BatchOperation({
    required this.type,
    required this.tableName,
    this.data,
    this.whereClause,
    this.whereArgs,
  });
}

enum _BatchOperationType { insert, update, delete }