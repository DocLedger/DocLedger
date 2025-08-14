import 'dart:convert';

/// Base class for all sync-enabled data models
abstract class SyncableModel {
  String get id;
  DateTime get lastModified;
  String get syncStatus;
  String get deviceId;
  
  Map<String, dynamic> toSyncJson();
  
  /// Updates sync metadata when the model is modified
  SyncableModel updateSyncMetadata({
    String? syncStatus,
    String? deviceId,
    DateTime? lastModified,
  });
}

/// Patient model with sync capabilities
class Patient implements SyncableModel {
  final String id;
  final String name;
  final String phone;
  final DateTime? dateOfBirth;
  final String? address;
  final String? emergencyContact;
  final DateTime lastModified;
  final String syncStatus;
  final String deviceId;

  const Patient({
    required this.id,
    required this.name,
    required this.phone,
    this.dateOfBirth,
    this.address,
    this.emergencyContact,
    required this.lastModified,
    this.syncStatus = 'pending',
    required this.deviceId,
  });

  @override
  Map<String, dynamic> toSyncJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'date_of_birth': dateOfBirth?.toIso8601String(),
      'address': address,
      'emergency_contact': emergencyContact,
      'last_modified': lastModified.millisecondsSinceEpoch,
      'sync_status': syncStatus,
      'device_id': deviceId,
    };
  }

  static Patient fromSyncJson(Map<String, dynamic> json) {
    return Patient(
      id: json['id'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String,
      dateOfBirth: json['date_of_birth'] != null 
          ? DateTime.parse(json['date_of_birth'] as String)
          : null,
      address: json['address'] as String?,
      emergencyContact: json['emergency_contact'] as String?,
      lastModified: DateTime.fromMillisecondsSinceEpoch(json['last_modified'] as int),
      syncStatus: json['sync_status'] as String? ?? 'pending',
      deviceId: json['device_id'] as String,
    );
  }

  @override
  Patient updateSyncMetadata({
    String? syncStatus,
    String? deviceId,
    DateTime? lastModified,
  }) {
    return Patient(
      id: id,
      name: name,
      phone: phone,
      dateOfBirth: dateOfBirth,
      address: address,
      emergencyContact: emergencyContact,
      lastModified: lastModified ?? DateTime.now(),
      syncStatus: syncStatus ?? this.syncStatus,
      deviceId: deviceId ?? this.deviceId,
    );
  }

  Patient copyWith({
    String? id,
    String? name,
    String? phone,
    DateTime? dateOfBirth,
    String? address,
    String? emergencyContact,
    DateTime? lastModified,
    String? syncStatus,
    String? deviceId,
  }) {
    return Patient(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      address: address ?? this.address,
      emergencyContact: emergencyContact ?? this.emergencyContact,
      lastModified: lastModified ?? this.lastModified,
      syncStatus: syncStatus ?? this.syncStatus,
      deviceId: deviceId ?? this.deviceId,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Patient &&
        other.id == id &&
        other.name == name &&
        other.phone == phone &&
        other.dateOfBirth == dateOfBirth &&
        other.address == address &&
        other.emergencyContact == emergencyContact;
  }

  @override
  int get hashCode {
    return Object.hash(id, name, phone, dateOfBirth, address, emergencyContact);
  }
}

/// Visit model with sync capabilities
class Visit implements SyncableModel {
  final String id;
  final String patientId;
  final DateTime visitDate;
  final String? diagnosis;
  final String? treatment; // legacy field; keep for compatibility
  final String? prescriptions;
  final String? notes;
  final double? fee;
  final DateTime? followUpDate;
  final DateTime lastModified;
  final String syncStatus;
  final String deviceId;

  const Visit({
    required this.id,
    required this.patientId,
    required this.visitDate,
    this.diagnosis,
    this.treatment,
    this.prescriptions,
    this.notes,
    this.fee,
    this.followUpDate,
    required this.lastModified,
    this.syncStatus = 'pending',
    required this.deviceId,
  });

  @override
  Map<String, dynamic> toSyncJson() {
    return {
      'id': id,
      'patient_id': patientId,
      'visit_date': visitDate.toIso8601String(),
      'diagnosis': diagnosis,
      'treatment': treatment,
      'prescriptions': prescriptions,
      'notes': notes,
      'fee': fee,
      'follow_up_date': followUpDate?.toIso8601String(),
      'last_modified': lastModified.millisecondsSinceEpoch,
      'sync_status': syncStatus,
      'device_id': deviceId,
    };
  }

  static Visit fromSyncJson(Map<String, dynamic> json) {
    return Visit(
      id: json['id'] as String,
      patientId: json['patient_id'] as String,
      visitDate: DateTime.parse(json['visit_date'] as String),
      diagnosis: json['diagnosis'] as String?,
      treatment: json['treatment'] as String?,
      prescriptions: json['prescriptions'] as String?,
      notes: json['notes'] as String?,
      fee: json['fee'] as double?,
      followUpDate: (json['follow_up_date'] as String?) != null
          ? DateTime.parse(json['follow_up_date'] as String)
          : null,
      lastModified: DateTime.fromMillisecondsSinceEpoch(json['last_modified'] as int),
      syncStatus: json['sync_status'] as String? ?? 'pending',
      deviceId: json['device_id'] as String,
    );
  }

  @override
  Visit updateSyncMetadata({
    String? syncStatus,
    String? deviceId,
    DateTime? lastModified,
  }) {
    return Visit(
      id: id,
      patientId: patientId,
      visitDate: visitDate,
      diagnosis: diagnosis,
      treatment: treatment,
      prescriptions: prescriptions,
      notes: notes,
      fee: fee,
      followUpDate: followUpDate,
      lastModified: lastModified ?? DateTime.now(),
      syncStatus: syncStatus ?? this.syncStatus,
      deviceId: deviceId ?? this.deviceId,
    );
  }

  Visit copyWith({
    String? id,
    String? patientId,
    DateTime? visitDate,
    String? diagnosis,
    String? treatment,
    String? prescriptions,
    String? notes,
    double? fee,
    DateTime? followUpDate,
    DateTime? lastModified,
    String? syncStatus,
    String? deviceId,
  }) {
    return Visit(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      visitDate: visitDate ?? this.visitDate,
      diagnosis: diagnosis ?? this.diagnosis,
      treatment: treatment ?? this.treatment,
      prescriptions: prescriptions ?? this.prescriptions,
      notes: notes ?? this.notes,
      fee: fee ?? this.fee,
      followUpDate: followUpDate ?? this.followUpDate,
      lastModified: lastModified ?? this.lastModified,
      syncStatus: syncStatus ?? this.syncStatus,
      deviceId: deviceId ?? this.deviceId,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Visit &&
        other.id == id &&
        other.patientId == patientId &&
        other.visitDate == visitDate &&
        other.diagnosis == diagnosis &&
        other.treatment == treatment &&
        other.notes == notes &&
        other.fee == fee;
  }

  @override
  int get hashCode {
    return Object.hash(id, patientId, visitDate, diagnosis, treatment, notes, fee);
  }
}

/// Payment model with sync capabilities
class Payment implements SyncableModel {
  final String id;
  final String patientId;
  final String? visitId;
  final double amount;
  final DateTime paymentDate;
  final String paymentMethod;
  final String? notes;
  final DateTime lastModified;
  final String syncStatus;
  final String deviceId;

  const Payment({
    required this.id,
    required this.patientId,
    this.visitId,
    required this.amount,
    required this.paymentDate,
    required this.paymentMethod,
    this.notes,
    required this.lastModified,
    this.syncStatus = 'pending',
    required this.deviceId,
  });

  @override
  Map<String, dynamic> toSyncJson() {
    return {
      'id': id,
      'patient_id': patientId,
      'visit_id': visitId,
      'amount': amount,
      'payment_date': paymentDate.toIso8601String(),
      'payment_method': paymentMethod,
      'notes': notes,
      'last_modified': lastModified.millisecondsSinceEpoch,
      'sync_status': syncStatus,
      'device_id': deviceId,
    };
  }

  static Payment fromSyncJson(Map<String, dynamic> json) {
    return Payment(
      id: json['id'] as String,
      patientId: json['patient_id'] as String,
      visitId: json['visit_id'] as String?,
      amount: (json['amount'] as num).toDouble(),
      paymentDate: DateTime.parse(json['payment_date'] as String),
      paymentMethod: json['payment_method'] as String,
      notes: json['notes'] as String?,
      lastModified: DateTime.fromMillisecondsSinceEpoch(json['last_modified'] as int),
      syncStatus: json['sync_status'] as String? ?? 'pending',
      deviceId: json['device_id'] as String,
    );
  }

  @override
  Payment updateSyncMetadata({
    String? syncStatus,
    String? deviceId,
    DateTime? lastModified,
  }) {
    return Payment(
      id: id,
      patientId: patientId,
      visitId: visitId,
      amount: amount,
      paymentDate: paymentDate,
      paymentMethod: paymentMethod,
      notes: notes,
      lastModified: lastModified ?? DateTime.now(),
      syncStatus: syncStatus ?? this.syncStatus,
      deviceId: deviceId ?? this.deviceId,
    );
  }

  Payment copyWith({
    String? id,
    String? patientId,
    String? visitId,
    double? amount,
    DateTime? paymentDate,
    String? paymentMethod,
    String? notes,
    DateTime? lastModified,
    String? syncStatus,
    String? deviceId,
  }) {
    return Payment(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      visitId: visitId ?? this.visitId,
      amount: amount ?? this.amount,
      paymentDate: paymentDate ?? this.paymentDate,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      notes: notes ?? this.notes,
      lastModified: lastModified ?? this.lastModified,
      syncStatus: syncStatus ?? this.syncStatus,
      deviceId: deviceId ?? this.deviceId,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Payment &&
        other.id == id &&
        other.patientId == patientId &&
        other.visitId == visitId &&
        other.amount == amount &&
        other.paymentDate == paymentDate &&
        other.paymentMethod == paymentMethod &&
        other.notes == notes;
  }

  @override
  int get hashCode {
    return Object.hash(id, patientId, visitId, amount, paymentDate, paymentMethod, notes);
  }
}

/// Enum for different types of sync conflicts
enum ConflictType {
  updateConflict,
  deleteConflict,
  createConflict,
}

/// Enum for conflict resolution strategies
enum ResolutionStrategy {
  useLocal,
  useRemote,
  merge,
  manual,
}

/// Model representing a sync conflict between local and remote data
class SyncConflict {
  final String id;
  final String tableName;
  final String recordId;
  final Map<String, dynamic> localData;
  final Map<String, dynamic> remoteData;
  final DateTime conflictTime;
  final ConflictType type;
  final String? description;

  const SyncConflict({
    required this.id,
    required this.tableName,
    required this.recordId,
    required this.localData,
    required this.remoteData,
    required this.conflictTime,
    required this.type,
    this.description,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'table_name': tableName,
      'record_id': recordId,
      'local_data': jsonEncode(localData),
      'remote_data': jsonEncode(remoteData),
      'conflict_time': conflictTime.toIso8601String(),
      'type': type.name,
      'description': description,
    };
  }

  static SyncConflict fromJson(Map<String, dynamic> json) {
    return SyncConflict(
      id: json['id'] as String,
      tableName: json['table_name'] as String,
      recordId: json['record_id'] as String,
      localData: jsonDecode(json['local_data'] as String) as Map<String, dynamic>,
      remoteData: jsonDecode(json['remote_data'] as String) as Map<String, dynamic>,
      conflictTime: DateTime.fromMillisecondsSinceEpoch(json['conflict_timestamp'] as int),
      type: ConflictType.values.firstWhere((e) => e.name == json['conflict_type']),
      description: json['notes'] as String?,
    );
  }

  SyncConflict copyWith({
    String? id,
    String? tableName,
    String? recordId,
    Map<String, dynamic>? localData,
    Map<String, dynamic>? remoteData,
    DateTime? conflictTime,
    ConflictType? type,
    String? description,
  }) {
    return SyncConflict(
      id: id ?? this.id,
      tableName: tableName ?? this.tableName,
      recordId: recordId ?? this.recordId,
      localData: localData ?? this.localData,
      remoteData: remoteData ?? this.remoteData,
      conflictTime: conflictTime ?? this.conflictTime,
      type: type ?? this.type,
      description: description ?? this.description,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SyncConflict &&
        other.id == id &&
        other.tableName == tableName &&
        other.recordId == recordId &&
        other.type == type;
  }

  @override
  int get hashCode {
    return Object.hash(id, tableName, recordId, type);
  }
}

/// Model representing the resolution of a sync conflict
class ConflictResolution {
  final String conflictId;
  final ResolutionStrategy strategy;
  final Map<String, dynamic> resolvedData;
  final DateTime resolutionTime;
  final String? notes;

  const ConflictResolution({
    required this.conflictId,
    required this.strategy,
    required this.resolvedData,
    required this.resolutionTime,
    this.notes,
  });

  Map<String, dynamic> toJson() {
    return {
      'conflict_id': conflictId,
      'strategy': strategy.name,
      'resolved_data': jsonEncode(resolvedData),
      'resolution_time': resolutionTime.toIso8601String(),
      'notes': notes,
    };
  }

  static ConflictResolution fromJson(Map<String, dynamic> json) {
    return ConflictResolution(
      conflictId: json['conflict_id'] as String,
      strategy: ResolutionStrategy.values.firstWhere((e) => e.name == json['strategy']),
      resolvedData: jsonDecode(json['resolved_data'] as String) as Map<String, dynamic>,
      resolutionTime: DateTime.parse(json['resolution_time'] as String),
      notes: json['notes'] as String?,
    );
  }

  ConflictResolution copyWith({
    String? conflictId,
    ResolutionStrategy? strategy,
    Map<String, dynamic>? resolvedData,
    DateTime? resolutionTime,
    String? notes,
  }) {
    return ConflictResolution(
      conflictId: conflictId ?? this.conflictId,
      strategy: strategy ?? this.strategy,
      resolvedData: resolvedData ?? this.resolvedData,
      resolutionTime: resolutionTime ?? this.resolutionTime,
      notes: notes ?? this.notes,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ConflictResolution &&
        other.conflictId == conflictId &&
        other.strategy == strategy &&
        other.resolutionTime == resolutionTime;
  }

  @override
  int get hashCode {
    return Object.hash(conflictId, strategy, resolutionTime);
  }
}