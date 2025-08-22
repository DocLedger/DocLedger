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
  String? _usernameFolder; // e.g., admin-docledger
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
      _usernameFolder = await _storage.read(key: 'webdav_username');
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

  Future<void> setUsernameFolder(String username) async {
    _usernameFolder = username.toLowerCase();
    try {
      await _storage.write(key: 'webdav_username', value: _usernameFolder);
    } catch (_) {}
  }

  Future<String> getCurrentUsernameFolder() async {
    if (_usernameFolder == null || _usernameFolder!.isEmpty) {
      throw StateError('Username folder not set. Call setUsernameFolder after login.');
    }
    return _usernameFolder!;
  }

  bool _hasCreds() {
    return (_email != null && _email!.isNotEmpty &&
        _password != null && _password!.isNotEmpty &&
        _baseUrl != null && _baseUrl!.isNotEmpty);
  }

  Future<bool> isReady() async {
    return _hasCreds() && _usernameFolder != null && _usernameFolder!.isNotEmpty;
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

  Future<bool> verifyUserExists(String username) async {
    final marker = '/docledger_backups/users/${username.toLowerCase()}.json';
    final resp = await http.get(_uri(marker), headers: {'Authorization': _authHeader()});
    return resp.statusCode == 200;
  }

  Future<void> ensureUserFolder(String username) async {
    final folder = '/docledger_backups/${username.toLowerCase()}/';
    final req = http.Request('MKCOL', _uri(folder));
    req.headers['Authorization'] = _authHeader();
    req.headers['Content-Length'] = '0';
    final res = await req.send();
    if (!(res.statusCode == 201 || res.statusCode == 405 || res.statusCode == 409 || (res.statusCode >= 200 && res.statusCode < 400))) {
      throw Exception('Failed to ensure user folder: ${res.statusCode}');
    }
  }

  Future<void> uploadBackupFile({
    required String usernameFolder,
    required String fileName,
    required Uint8List bytes,
    void Function(int sent, int total)? onProgress,
  }) async {
    final path = '/docledger_backups/$usernameFolder/$fileName';
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

  Future<List<WebDavBackupFileInfo>> _propfindList(String folderPath, String? clinicId) async {
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

  // Only consider .enc files; match by clinicId only if provided
        if (!path.toLowerCase().endsWith('.enc')) continue;
  if (clinicId != null && clinicId.isNotEmpty && !path.contains(clinicId)) continue;

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

  Future<WebDavBackupFileInfo?> getLatestBackup(String? clinicId) async {
    final folder = '/docledger_backups/${await getCurrentUsernameFolder()}/';
    final files = await _propfindList(folder, clinicId);
    if (files.isEmpty) return null;
    files.sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));
    return files.first;
  }

  Future<List<WebDavBackupFileInfo>> listBackups(String? clinicId) async {
    final folder = '/docledger_backups/${await getCurrentUsernameFolder()}/';
    final files = await _propfindList(folder, clinicId);
    files.sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));
    return files;
  }

  Future<void> cleanupOldBackups(String usernameFolder, {required int keep, String? clinicId}) async {
    final folder = '/docledger_backups/$usernameFolder/';
    final files = await _propfindList(folder, clinicId);
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

  void _log(String message) {
    try {
      final ts = DateTime.now().toIso8601String();
      // ignore: avoid_print
      print('[WebDAV] ' + ts + ' ' + message);
    } catch (_) {}
  }
}
