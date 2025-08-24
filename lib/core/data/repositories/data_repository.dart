import '../models/data_models.dart';
import '../services/database_service.dart';
import '../../cloud/services/cloud_save_service.dart';
import '../../services/service_locator.dart';

/// Repository for managing patient, visit, and payment data with sync integration
/// 
/// This repository provides a high-level interface for data operations while
/// automatically triggering sync operations when data is modified.
class DataRepository {
  final DatabaseService _database;
  final CloudSaveService _cloudSaveService;

  DataRepository({
    DatabaseService? database,
    CloudSaveService? cloudSaveService,
  }) : _database = database ?? serviceLocator.get<DatabaseService>(),
       _cloudSaveService = cloudSaveService ?? serviceLocator.get<CloudSaveService>();

  // Patient operations

  /// Gets all patients from the local database
  Future<List<Patient>> getPatients() async {
    try {
      return await _database.getAllPatients();
    } catch (e) {
      throw DataRepositoryException('Failed to load patients: $e');
    }
  }

  /// Gets a specific patient by ID
  Future<Patient?> getPatient(String id) async {
    try {
      return await _database.getPatient(id);
    } catch (e) {
      throw DataRepositoryException('Failed to load patient: $e');
    }
  }

  /// Adds a new patient and triggers sync
  Future<void> addPatient(Patient patient) async {
    try {
      await _database.insertPatient(patient);
      _triggerSync();
    } catch (e) {
      throw DataRepositoryException('Failed to add patient: $e');
    }
  }

  /// Updates an existing patient and triggers sync
  Future<void> updatePatient(Patient patient) async {
    try {
      await _database.updatePatient(patient);
      _triggerSync();
    } catch (e) {
      throw DataRepositoryException('Failed to update patient: $e');
    }
  }

  /// Deletes a patient and triggers sync
  Future<void> deletePatient(String id) async {
    try {
      await _database.deletePatient(id);
      _triggerSync();
    } catch (e) {
      throw DataRepositoryException('Failed to delete patient: $e');
    }
  }

  // Visit operations

  /// Gets all visits for a specific patient
  Future<List<Visit>> getVisitsForPatient(String patientId) async {
    try {
      return await _database.getVisitsForPatient(patientId);
    } catch (e) {
      throw DataRepositoryException('Failed to load visits: $e');
    }
  }

  /// Adds a new visit and triggers sync
  Future<void> addVisit(Visit visit) async {
    try {
      await _database.insertVisit(visit);
      _triggerSync();
    } catch (e) {
      throw DataRepositoryException('Failed to add visit: $e');
    }
  }

  /// Updates an existing visit and triggers sync
  Future<void> updateVisit(Visit visit) async {
    try {
      await _database.updateVisit(visit);
      _triggerSync();
    } catch (e) {
      throw DataRepositoryException('Failed to update visit: $e');
    }
  }
  
  /// Deletes a visit and triggers sync
  Future<void> deleteVisit(String visitId) async {
    try {
      await _database.deleteVisit(visitId);
      _triggerSync();
    } catch (e) {
      throw DataRepositoryException('Failed to delete visit: $e');
    }
  }

  // Payment operations

  /// Gets all payments for a specific patient
  Future<List<Payment>> getPaymentsForPatient(String patientId) async {
    try {
      return await _database.getPaymentsForPatient(patientId);
    } catch (e) {
      throw DataRepositoryException('Failed to load payments: $e');
    }
  }

  /// Adds a new payment and triggers sync
  Future<void> addPayment(Payment payment) async {
    try {
      await _database.insertPayment(payment);
      _triggerSync();
    } catch (e) {
      throw DataRepositoryException('Failed to add payment: $e');
    }
  }

  /// Updates an existing payment and triggers sync
  Future<void> updatePayment(Payment payment) async {
    try {
      await _database.updateRecord('payments', payment.id, payment.toSyncJson());
      _triggerSync();
    } catch (e) {
      throw DataRepositoryException('Failed to update payment: $e');
    }
  }

  // Sync operations

  /// Gets the count of pending sync operations
  Future<int> getPendingSyncCount() async {
    try {
      final tables = ['patients', 'visits', 'payments'];
      int totalPending = 0;

      for (final table in tables) {
        final metadata = await _database.getSyncMetadata(table);
        totalPending += (metadata?['pending_changes_count'] as int? ?? 0);
      }

      return totalPending;
    } catch (e) {
      return 0;
    }
  }

  /// Triggers background sync (non-blocking)
  void _triggerSync() {
    // Schedule sync in the background without blocking the UI
    Future.microtask(() async {
      try {
        // Honor user's Auto-Save setting; skip background saves when disabled
        if (_cloudSaveService.autoSaveEnabled) {
          await _cloudSaveService.saveNow();
        }
      } catch (e) {
        // Log error but don't throw - sync failures shouldn't break data operations
        print('Background sync failed: $e');
      }
    });
  }

  // Dashboard aggregates
  Future<int> getPatientCount() => _database.getPatientCount();
  Future<int> getTodayVisitCount() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
    return _database.getVisitCountBetween(start, end);
  }
  Future<double> getThisMonthRevenue() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 1).subtract(const Duration(milliseconds: 1));
    return _database.getRevenueTotalBetween(start, end);
  }
  Future<int> getPendingFollowUpsCount() {
    final until = DateTime.now().add(const Duration(days: 7));
    return _database.getPendingFollowUpsCountUntil(until);
  }
  Future<List<Visit>> getUpcomingFollowUps({int limit = 5}) => _database.getUpcomingFollowUps(limit: limit);
  Future<List<Patient>> getRecentPatients({int limit = 5}) => _database.getRecentPatients(limit: limit);
}

/// Exception thrown by data repository operations
class DataRepositoryException implements Exception {
  final String message;
  final Exception? originalException;

  const DataRepositoryException(this.message, {this.originalException});

  @override
  String toString() => 'DataRepositoryException: $message';
}