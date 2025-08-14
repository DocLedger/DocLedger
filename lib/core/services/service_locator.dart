import 'package:get_it/get_it.dart';
import 'package:flutter/foundation.dart';

import '../sync/models/sync_models.dart';
import '../sync/services/sync_service.dart';
import '../data/services/database_service.dart';
import '../data/repositories/data_repository.dart';
import '../cloud/services/google_drive_service.dart';
import '../encryption/services/encryption_service.dart';
import '../connectivity/services/connectivity_service.dart';
import '../../features/sync/models/sync_settings.dart';

/// Global service locator
final GetIt serviceLocator = GetIt.instance;

/// Initializes all core services for the application (idempotent)
Future<void> initializeServices() async {
  try {
    if (serviceLocator.isRegistered<SyncService>()) return;

    // Core settings
    final syncSettings = SyncSettings.defaultSettings();
    serviceLocator.registerSingleton<SyncSettings>(syncSettings);

    // Connectivity
    final connectivityService = AppConnectivityService();
    await connectivityService.initialize();
    serviceLocator.registerSingleton<AppConnectivityService>(connectivityService);

    // Encryption
    final encryptionService = EncryptionService();
    serviceLocator.registerSingleton<EncryptionService>(encryptionService);

    // IDs
    final String clinicId = await _getOrCreateClinicId(encryptionService);
    final String deviceId = await encryptionService.generateDeviceId();

    // Database
    final database = SQLiteDatabaseService(deviceId: deviceId);
    await database.initialize();
    serviceLocator.registerSingleton<DatabaseService>(database);

    // Google Drive
    final driveService = GoogleDriveService();
    // Best-effort init; may fail on desktop without Google setup
    try {
      await driveService.initialize();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('GoogleDriveService init skipped/failed on this platform: $e');
      }
    }
    serviceLocator.registerSingleton<GoogleDriveService>(driveService);

    // Sync service
    final syncService = SyncService(
      database: database,
      driveService: driveService,
      encryption: encryptionService,
      clinicId: clinicId,
      deviceId: deviceId,
    );
    serviceLocator.registerSingleton<SyncService>(syncService);

    // Repository
    final dataRepository = DataRepository();
    serviceLocator.registerSingleton<DataRepository>(dataRepository);

  } catch (e) {
    debugPrint('Service initialization error: $e');
  }
}

Future<String> _getOrCreateClinicId(EncryptionService encryptionService) async {
  // For now derive deterministic clinic ID from device info to simulate single-clinic setup
  try {
    final info = await encryptionService.getDeviceInfo();
    return 'clinic_${info.platform}_${info.deviceId}'.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
  } catch (_) {
    return 'clinic_default';
  }
}

/// Dispose services (call on app exit)
Future<void> disposeServices() async {
  try {
    if (serviceLocator.isRegistered<SyncService>()) {
      serviceLocator.get<SyncService>().dispose();
    }
    if (serviceLocator.isRegistered<AppConnectivityService>()) {
      serviceLocator.get<AppConnectivityService>().dispose();
    }
  } catch (e) {
    debugPrint('Error disposing services: $e');
  }
  await serviceLocator.reset();
}