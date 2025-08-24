library flutter_secure_storage;

import 'dart:convert';
import 'dart:io';

// Simple file-backed store to simulate secure storage on desktop targets.
// NOTE: This is NOT cryptographically secure; it's a lightweight stub for
// development/desktop where real secure storage isn't available.
class _FileBackedStore {
  static final _FileBackedStore _instance = _FileBackedStore._();
  factory _FileBackedStore() => _instance;
  _FileBackedStore._();

  final Map<String, String> _cache = <String, String>{};
  bool _loaded = false;

  File get _file {
    final envHome = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
    final dir = Directory(
      Platform.isWindows
          ? '${envHome}\\.docledger'
          : '$envHome/.config/docledger',
    );
    if (!dir.existsSync()) {
      try { dir.createSync(recursive: true); } catch (_) {}
    }
    return File('${dir.path}${Platform.pathSeparator}secure_store.json');
  }

  void _ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = _file;
      if (f.existsSync()) {
        final txt = f.readAsStringSync();
        if (txt.trim().isNotEmpty) {
          final map = jsonDecode(txt) as Map<String, dynamic>;
          map.forEach((k, v) {
            if (k is String && v is String) {
              _cache[k] = v;
            }
          });
        }
      }
    } catch (_) {}
  }

  void _flush() {
    try {
      final f = _file;
      f.writeAsStringSync(jsonEncode(_cache));
    } catch (_) {}
  }

  Future<void> write({required String key, required String? value}) async {
    _ensureLoaded();
    if (value == null) {
      _cache.remove(key);
    } else {
      _cache[key] = value;
    }
    _flush();
  }

  Future<String?> read({required String key}) async {
    _ensureLoaded();
    return _cache[key];
  }

  Future<Map<String, String>> readAll() async {
    _ensureLoaded();
    return Map<String, String>.from(_cache);
  }

  Future<void> delete({required String key}) async {
    _ensureLoaded();
    _cache.remove(key);
    _flush();
  }
}

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

  Future<void> write({required String key, required String? value}) async {
    await _FileBackedStore().write(key: key, value: value);
  }

  Future<String?> read({required String key}) async {
    return _FileBackedStore().read(key: key);
  }

  Future<Map<String, String>> readAll({IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WindowsOptions? wOptions}) async {
    return _FileBackedStore().readAll();
  }

  Future<void> delete({required String key}) async {
    await _FileBackedStore().delete(key: key);
  }
}

