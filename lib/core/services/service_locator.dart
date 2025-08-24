import 'package:get_it/get_it.dart';
import 'package:flutter/foundation.dart';

import '../cloud/services/cloud_save_service.dart';
import '../data/services/database_service.dart';
import '../data/repositories/data_repository.dart';
import '../encryption/services/encryption_service.dart';
import '../connectivity/services/connectivity_service.dart';
import '../cloud/services/webdav_backup_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Global service locator
final GetIt serviceLocator = GetIt.instance;

/// Initializes all core services for the application (idempotent)
Future<void> initializeServices() async {
  try {
    if (serviceLocator.isRegistered<CloudSaveService>()) return;

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

    // WebDAV backup service
    final webDavService = WebDavBackupService();
    await webDavService.initialize();
    // If credentials were persisted earlier, re-apply them to ensure link state
    try {
      const storage = FlutterSecureStorage();
      final base = await storage.read(key: 'webdav_base_url');
      final email = await storage.read(key: 'webdav_email');
      final pass = await storage.read(key: 'webdav_password');
      if (base != null && email != null && pass != null && base.isNotEmpty && email.isNotEmpty && pass.isNotEmpty) {
        await webDavService.setCredentials(base, email, pass);
      }
    } catch (_) {}
    serviceLocator.registerSingleton<WebDavBackupService>(webDavService);

    // Cloud Save service using WebDAV
    // Determine final clinic id: prefer username-based if available in storage
    String finalClinicId = clinicId;
    try {
      const storage = FlutterSecureStorage();
      final storedUsername = await storage.read(key: 'webdav_username');
      if (storedUsername != null && storedUsername.isNotEmpty) {
        finalClinicId = 'clinic_${storedUsername.toLowerCase()}';
      }
    } catch (_) {}

    final cloudSaveService = CloudSaveService(
      database: database,
      backupService: webDavService,
      encryption: encryptionService,
      clinicId: finalClinicId,
      deviceId: deviceId,
    );
    try {
      await cloudSaveService.initialize();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CloudSaveService initialization failed: $e');
      }
    }
    serviceLocator.registerSingleton<CloudSaveService>(cloudSaveService);

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
    if (serviceLocator.isRegistered<CloudSaveService>()) {
      serviceLocator.get<CloudSaveService>().dispose();
    }
    if (serviceLocator.isRegistered<AppConnectivityService>()) {
      serviceLocator.get<AppConnectivityService>().dispose();
    }
  } catch (e) {
    debugPrint('Error disposing services: $e');
  }
  await serviceLocator.reset();
}