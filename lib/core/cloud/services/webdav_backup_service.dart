import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;
import '../webdav_config.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class WebDavBackupFileInfo {
  final String path;
  final DateTime modifiedTime;
  WebDavBackupFileInfo(this.path, this.modifiedTime);
}

class WebDavBackupService {
  // Clinic-centric configuration
  String? _clinicId; // e.g., clinic-1234
  String? _username; // cached logged-in username (clinic user)
  String? _baseUrl;
  String? _email;
  String? _password;

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<void> initialize() async {
    // Initialize from config if provided
    if (WebDavConfig.hasCredentials) {
      _baseUrl = WebDavConfig.baseUrl;
      _email = WebDavConfig.email;
      _password = WebDavConfig.password;
    }
    // Load persisted credentials if available
    try {
      _baseUrl ??= await _storage.read(key: 'webdav_base_url');
      _email ??= await _storage.read(key: 'webdav_email');
      _password ??= await _storage.read(key: 'webdav_password');
      _clinicId = await _storage.read(key: 'webdav_clinic_id');
  _username = await _storage.read(key: 'webdav_username');
    } catch (_) {}
  }

  /// Ensures the clinics index exists under /docledger_backups/clinics-index/
  /// Creates base folders and a minimal README if missing. Also ensures the
  /// by-username folder exists. This is idempotent.
  Future<void> ensureClinicsIndex() async {
    await _ensureBaseFolder();
    // Create parent folders
    final indexFolder = '/docledger_backups/clinics-index/';
    for (final path in [indexFolder, indexFolder + 'by-username/']) {
      final req = http.Request('MKCOL', _uri(path));
      req.headers['Authorization'] = _authHeader();
      req.headers['Content-Length'] = '0';
      final res = await req.send();
      // Accept common success/exists codes; ignore errors to keep idempotent
      if (!(res.statusCode == 201 || res.statusCode == 405 || res.statusCode == 409 || (res.statusCode >= 200 && res.statusCode < 400))) {
        // Non-fatal; continue
      }
    }
    // Create a small README marker if not present
    try {
      final readmePath = indexFolder + 'README.txt';
      final head = await http.head(_uri(readmePath), headers: {'Authorization': _authHeader()});
      if (head.statusCode == 404) {
        await http.put(
          _uri(readmePath),
          headers: {'Authorization': _authHeader()},
          body: utf8.encode('DocLedger Clinics Index\nThis folder holds index files like by-username/<username>.json.'),
        );
      }
    } catch (_) {}
  }

  Future<void> setCredentials(String baseUrl, String email, String password) async {
    _baseUrl = baseUrl;
    _email = email;
    _password = password;
    try {
      await _storage.write(key: 'webdav_base_url', value: baseUrl);
      await _storage.write(key: 'webdav_email', value: email);
      await _storage.write(key: 'webdav_password', value: password);
    } catch (_) {}
  }

  Future<void> setClinicId(String clinicId) async {
    _clinicId = clinicId;
    try {
      await _storage.write(key: 'webdav_clinic_id', value: _clinicId);
    } catch (_) {}
  }

  /// Clear all persisted credentials and unlink current account
  Future<void> logout() async {
    _baseUrl = null;
    _email = null;
    _password = null;
    _clinicId = null;
    _username = null;
    try {
      await _storage.delete(key: 'webdav_base_url');
      await _storage.delete(key: 'webdav_email');
      await _storage.delete(key: 'webdav_password');
      await _storage.delete(key: 'webdav_clinic_id');
      await _storage.delete(key: 'webdav_username');
    } catch (_) {}
  }

  Future<String> getCurrentClinicId() async {
    if (_clinicId == null || _clinicId!.isEmpty) {
      throw StateError('Clinic ID not set. Call setClinicId after login.');
    }
    return _clinicId!;
  }

  /// Set and persist the current clinic-user username for display/hydration
  Future<void> setCurrentUsername(String username) async {
    _username = username;
    try {
      await _storage.write(key: 'webdav_username', value: username);
    } catch (_) {}
  }

  /// Get cached username if available (does not hit storage)
  String? getCurrentUsernameCached() {
    return _username;
  }

  bool _hasCreds() {
    return (_email != null && _email!.isNotEmpty &&
        _password != null && _password!.isNotEmpty &&
        _baseUrl != null && _baseUrl!.isNotEmpty);
  }

  Future<bool> isReady() async {
  return _hasCreds() && _clinicId != null && _clinicId!.isNotEmpty;
  }

  String _authHeader() {
    final email = _email ?? WebDavConfig.email;
    final password = _password ?? WebDavConfig.password;
    return 'Basic ' + base64Encode(utf8.encode('$email:$password'));
  }

  String _getBaseUrl() {
    final raw = _baseUrl ?? WebDavConfig.baseUrl;
    var base = raw.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return base;
  }

  Uri _uri(String path) {
    final base = _getBaseUrl();
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse(base + normalizedPath);
  }

  /// Ensure the base backups folder exists: /docledger_backups/
  Future<void> _ensureBaseFolder() async {
    final baseFolder = '/docledger_backups/';
    final req = http.Request('MKCOL', _uri(baseFolder));
    req.headers['Authorization'] = _authHeader();
    req.headers['Content-Length'] = '0';
    final res = await req.send();
    // Accept: 201 Created, 405 Method Not Allowed (already exists), 409 Conflict (intermediate race), or any 2xx/3xx
    if (!(res.statusCode == 201 || res.statusCode == 405 || res.statusCode == 409 || (res.statusCode >= 200 && res.statusCode < 400))) {
      throw Exception('Failed to ensure base folder: ${res.statusCode}');
    }
  }

  /// Ensure the clinic backup folder exists
  Future<void> ensureClinicFolder(String clinicId) async {
    await _ensureBaseFolder();
    final folder = '/docledger_backups/$clinicId/';
    final req = http.Request('MKCOL', _uri(folder));
    req.headers['Authorization'] = _authHeader();
    req.headers['Content-Length'] = '0';
    final res = await req.send();
    if (!(res.statusCode == 201 || res.statusCode == 405 || res.statusCode == 409 || (res.statusCode >= 200 && res.statusCode < 400))) {
      throw Exception('Failed to ensure clinic folder: ${res.statusCode}');
    }
  }

  Future<void> uploadBackupFile({
    required String clinicId,
    required String fileName,
    required Uint8List bytes,
    void Function(int sent, int total)? onProgress,
  }) async {
    final path = '/docledger_backups/$clinicId/$fileName';
    final res = await http.put(
      _uri(path),
      headers: {'Authorization': _authHeader()},
      body: bytes,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Upload failed: ${res.statusCode}');
    }
    onProgress?.call(bytes.length, bytes.length);
  }

  Future<Uint8List> downloadBackupFile(String path, {void Function(int, int)? onProgress}) async {
    final res = await http.get(_uri(path), headers: {'Authorization': _authHeader()});
    if (res.statusCode != 200) {
      throw Exception('Download failed: ${res.statusCode}');
    }
    final bytes = Uint8List.fromList(res.bodyBytes);
    onProgress?.call(bytes.length, bytes.length);
    return bytes;
  }

  DateTime? _parseHttpDate(String s) {
    try {
      return HttpDate.parse(s);
    } catch (_) {
      try {
        return DateTime.parse(s);
      } catch (_) {
        return null;
      }
    }
  }

  Future<List<WebDavBackupFileInfo>> _propfindList(String folderPath, String? clinicIdFilterExt) async {
    final uri = _uri(folderPath);
    _log('PROPFIND ' + uri.toString());
    final req = http.Request('PROPFIND', uri);
    req.headers['Authorization'] = _authHeader();
    req.headers['Depth'] = '1';
    req.headers['Content-Type'] = 'text/xml';
    req.body = '''<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:displayname/>
    <d:getcontentlength/>
    <d:getlastmodified/>
    <d:resourcetype/>
  </d:prop>
</d:propfind>''';
    final streamed = await req.send();
    final status = streamed.statusCode;
    final text = await streamed.stream.bytesToString();
    if (status < 200 || status >= 300) {
      _log('PROPFIND failed ' + status.toString() + ' body=' + (text.length > 200 ? text.substring(0, 200) + '...' : text));
      return <WebDavBackupFileInfo>[];
    }
    _log('PROPFIND ok ' + status.toString());

    final results = <WebDavBackupFileInfo>[];
    try {
      final doc = xml.XmlDocument.parse(text);
      final responses = doc
          .descendants
          .whereType<xml.XmlElement>()
          .where((e) => e.name.local.toLowerCase() == 'response')
          .toList();
      _log('PROPFIND responses count=' + responses.length.toString());
      for (final resp in responses) {
        final hrefEl = resp
            .descendants
            .whereType<xml.XmlElement>()
            .firstWhere(
              (e) => e.name.local.toLowerCase() == 'href',
              orElse: () => xml.XmlElement(xml.XmlName('none')),
            );
        if (hrefEl.name.local == 'none') continue;
        final href = hrefEl.innerText;

        // Determine if this is a collection (directory)
        xml.XmlElement? propstat200;
        final propstats = resp
            .descendants
            .whereType<xml.XmlElement>()
            .where((e) => e.name.local.toLowerCase() == 'propstat');
        for (final ps in propstats) {
          final statusText = ps
              .descendants
              .whereType<xml.XmlElement>()
              .where((e) => e.name.local.toLowerCase() == 'status')
              .map((e) => e.innerText)
              .join(' ');
          if (statusText.contains('200')) {
            propstat200 = ps;
            break;
          }
        }
        if (propstat200 == null) continue;
        final prop = propstat200
            .descendants
            .whereType<xml.XmlElement>()
            .firstWhere(
              (e) => e.name.local.toLowerCase() == 'prop',
              orElse: () => xml.XmlElement(xml.XmlName('none')),
            );
        if (prop.name.local == 'none') continue;
        final isCollection = prop
            .descendants
            .whereType<xml.XmlElement>()
            .where((e) => e.name.local.toLowerCase() == 'resourcetype')
            .expand((e) => e.descendants.whereType<xml.XmlElement>())
            .any((e) => e.name.local.toLowerCase() == 'collection');
        if (isCollection) {
          // Skip folder entries
          continue;
        }

        // Normalize href to a path
        final decodedHref = Uri.decodeFull(href);
        final path = decodedHref.startsWith('http') ? Uri.parse(decodedHref).path : decodedHref;

        // If clinicIdFilterExt is provided, treat it as a file extension filter
        if (clinicIdFilterExt != null && clinicIdFilterExt.isNotEmpty) {
          if (!path.toLowerCase().endsWith(clinicIdFilterExt.toLowerCase())) continue;
        }

        // Parse last modified
        DateTime modified = DateTime.now();
        final lastModEl = prop
            .descendants
            .whereType<xml.XmlElement>()
            .firstWhere(
              (e) => e.name.local.toLowerCase() == 'getlastmodified',
              orElse: () => xml.XmlElement(xml.XmlName('none')),
            );
        if (lastModEl.name.local != 'none') {
          final parsed = _parseHttpDate(lastModEl.innerText.trim());
          if (parsed != null) modified = parsed.toUtc();
        }

        results.add(WebDavBackupFileInfo(path, modified));
      }
    } catch (e) {
      _log('PROPFIND parse error: ' + e.toString() + ' body=' + (text.length > 400 ? text.substring(0, 400) + '...' : text));
      return <WebDavBackupFileInfo>[];
    }

    _log('PROPFIND parsed ' + results.length.toString() + ' .enc files in folder');
    return results;
  }

  Future<WebDavBackupFileInfo?> getLatestBackup() async {
    final folder = '/docledger_backups/${await getCurrentClinicId()}/';
    final files = await _propfindList(folder, '.enc');
    if (files.isEmpty) return null;
    files.sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));
    return files.first;
  }

  Future<List<WebDavBackupFileInfo>> listBackups() async {
    final folder = '/docledger_backups/${await getCurrentClinicId()}/';
    final files = await _propfindList(folder, '.enc');
    files.sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));
    return files;
  }

  Future<void> cleanupOldBackups(String clinicId, {required int keep}) async {
    final folder = '/docledger_backups/$clinicId/';
    final files = await _propfindList(folder, '.enc');
    if (files.length <= keep) return;
    files.sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));
    final toDelete = files.skip(keep);
    for (final f in toDelete) {
      try {
        final req = http.Request('DELETE', _uri(f.path));
        req.headers['Authorization'] = _authHeader();
        final res = await req.send();
        if (!(res.statusCode >= 200 && res.statusCode < 300) && res.statusCode != 404) {
          // Keep going even if deletion fails
        }
      } catch (_) {
        // Ignore individual deletion errors
      }
    }
  }

  /// Try to find a clinic for given credentials using an index first, else scan all clinics
  Future<String?> findClinicForCredentials(String username, String password) async {
    final u = username.toLowerCase();
    // 1) Index lookup
    final indexPath = '/docledger_backups/clinics-index/by-username/$u.json';
    try {
      final idxRes = await http.get(_uri(indexPath), headers: {'Authorization': _authHeader()});
      if (idxRes.statusCode == 200) {
        final obj = jsonDecode(idxRes.body) as Map<String, dynamic>;
        final memberships = (obj['memberships'] as List?)?.cast<dynamic>() ?? const [];
        for (final m in memberships) {
          final clinicId = (m as Map)['clinic_id']?.toString();
          if (clinicId == null) continue;
          final ok = await _checkClinicFileForCredentials(clinicId, u, password);
          if (ok) return clinicId;
        }
      }
    } catch (_) {}
    // 2) Scan clinics folder (low scale)
    try {
      final clinics = await _listClinicJsonFiles();
      for (final path in clinics) {
        final name = path.split('/').last; // clinic-xxxx.json
        final cid = name.replaceAll('.json', '');
        final ok = await _checkClinicFileForCredentials(cid, u, password);
        if (ok) return cid;
      }
    } catch (_) {}
    return null;
  }

  Future<bool> _checkClinicFileForCredentials(String clinicId, String username, String password) async {
    final metaPath = '/docledger_backups/clinics/$clinicId.json';
    try {
      final res = await http.get(_uri(metaPath), headers: {'Authorization': _authHeader()});
      if (res.statusCode != 200) return false;
      final obj = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final users = (obj['users'] as List?)?.cast<dynamic>() ?? const [];
      for (final u in users) {
        final m = u as Map<String, dynamic>;
        if ((m['username']?.toString().toLowerCase() ?? '') == username.toLowerCase()) {
          // Plain-text comparison (as requested for initial simple phase)
          final pw = m['password']?.toString() ?? '';
          return pw == password;
        }
      }
    } catch (_) {}
    return false;
  }

  Future<List<String>> _listClinicJsonFiles() async {
    final folder = '/docledger_backups/clinics/';
    final files = await _propfindList(folder, '.json');
    // Return normalized paths
    return files.map((f) => f.path).toList();
  }

  void _log(String message) {
    try {
      final ts = DateTime.now().toIso8601String();
      // ignore: avoid_print
      print('[WebDAV] ' + ts + ' ' + message);
    } catch (_) {}
  }
}
