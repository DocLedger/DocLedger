library flutter_secure_storage;

class AndroidOptions {
  const AndroidOptions({bool encryptedSharedPreferences = true});
}

class IOSOptions {
  const IOSOptions({dynamic accessibility});
}

class LinuxOptions {
  const LinuxOptions();
}

class WindowsOptions {
  const WindowsOptions({bool useBackwardCompatibility = false});
}

class FlutterSecureStorage {
  const FlutterSecureStorage({AndroidOptions? aOptions, IOSOptions? iOptions, LinuxOptions? lOptions, WindowsOptions? wOptions});

  Future<void> write({required String key, required String? value}) async {}
  Future<String?> read({required String key}) async => null;
  Future<Map<String, String>> readAll({IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WindowsOptions? wOptions}) async => <String, String>{};
  Future<void> delete({required String key}) async {}
}

