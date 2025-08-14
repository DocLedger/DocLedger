import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Exception thrown when Google Drive operations fail
class GoogleDriveException implements Exception {
  final String message;
  final String? code;
  final Exception? originalException;

  const GoogleDriveException(this.message, {this.code, this.originalException});

  @override
  String toString() => 'GoogleDriveException: $message${code != null ? ' (Code: $code)' : ''}';
}

/// Authentication state for Google Drive
enum AuthenticationState {
  notAuthenticated,
  authenticating,
  authenticated,
  authenticationFailed,
  tokenExpired,
}

/// Progress callback for file operations
typedef ProgressCallback = void Function(int bytesTransferred, int totalBytes);

/// Google Drive service for backup and sync operations
class GoogleDriveService {
  static const List<String> _scopes = [
    drive.DriveApi.driveFileScope,
  ];

  static const String _tokenKey = 'google_drive_tokens';
  static const String _accountKey = 'google_drive_account';
  static const String _backupFolderName = 'DocLedger_Backups';

  final GoogleSignIn _googleSignIn;
  final FlutterSecureStorage _secureStorage;
  
  drive.DriveApi? _driveApi;
  GoogleSignInAccount? _currentAccount;
  http.Client? _authClient;
  String? _backupFolderId;
  
  AuthenticationState _authState = AuthenticationState.notAuthenticated;
  
  GoogleDriveService({
    GoogleSignIn? googleSignIn,
    FlutterSecureStorage? secureStorage,
  }) : _googleSignIn = googleSignIn ?? GoogleSignIn(scopes: _scopes),
       _secureStorage = secureStorage ?? const FlutterSecureStorage();

  /// Current authentication state
  AuthenticationState get authenticationState => _authState;

  /// Currently authenticated account
  GoogleSignInAccount? get currentAccount => _currentAccount;

  /// Whether the service is currently authenticated
  bool get isAuthenticated => _authState == AuthenticationState.authenticated;

  /// Initialize the service and attempt to restore previous authentication
  Future<void> initialize() async {
    try {
      _authState = AuthenticationState.authenticating;
      
      // Try to restore previous authentication
      final storedTokens = await _secureStorage.read(key: _tokenKey);
      final storedAccount = await _secureStorage.read(key: _accountKey);
      
      if (storedTokens != null && storedAccount != null) {
        try {
          final tokenData = jsonDecode(storedTokens) as Map<String, dynamic>;
          final accountData = jsonDecode(storedAccount) as Map<String, dynamic>;
          
          // Attempt to restore authentication with stored tokens
          await _restoreAuthentication(tokenData, accountData);
          return;
        } catch (e) {
          // If restoration fails, clear stored data and continue with fresh auth
          await _clearStoredCredentials();
        }
      }
      
      // Try silent sign-in
      final account = await _googleSignIn.signInSilently();
      if (account != null) {
        await _completeAuthentication(account);
      } else {
        _authState = AuthenticationState.notAuthenticated;
      }
    } catch (e) {
      _authState = AuthenticationState.authenticationFailed;
      throw GoogleDriveException(
        'Failed to initialize Google Drive service: ${e.toString()}',
        originalException: e is Exception ? e : Exception(e.toString()),
      );
    }
  }

  /// Authenticate with Google Drive using OAuth2
  Future<bool> authenticate({bool forceAccountSelection = false}) async {
    try {
      _authState = AuthenticationState.authenticating;
      
      GoogleSignInAccount? account;
      
      if (forceAccountSelection) {
        // Sign out first to force account selection
        await _googleSignIn.signOut();
        account = await _googleSignIn.signIn();
      } else {
        // Try silent sign-in first
        account = await _googleSignIn.signInSilently();
        account ??= await _googleSignIn.signIn();
      }
      
      if (account == null) {
        _authState = AuthenticationState.notAuthenticated;
        return false;
      }
      
      await _completeAuthentication(account);
      return true;
    } catch (e) {
      _authState = AuthenticationState.authenticationFailed;
      throw GoogleDriveException(
        'Authentication failed: ${e.toString()}',
        originalException: e is Exception ? e : Exception(e.toString()),
      );
    }
  }

  /// Complete the authentication process
  Future<void> _completeAuthentication(GoogleSignInAccount account) async {
    _currentAccount = account;
    
    // Get authentication headers
    final authHeaders = await account.authHeaders;
    
    // Create authenticated HTTP client
    _authClient = _GoogleSignInAuthClient(authHeaders);
    
    // Initialize Drive API
    _driveApi = drive.DriveApi(_authClient!);
    
    // Store credentials securely
    await _storeCredentials(account, authHeaders);
    
    // Ensure backup folder exists
    await _ensureBackupFolder();
    
    _authState = AuthenticationState.authenticated;
  }

  /// Restore authentication from stored credentials
  Future<void> _restoreAuthentication(
    Map<String, dynamic> tokenData,
    Map<String, dynamic> accountData,
  ) async {
    // Create auth client from stored tokens
    final accessToken = AccessToken(
      'Bearer',
      tokenData['access_token'] as String,
      DateTime.parse(tokenData['expiry_date'] as String).toUtc(),
    );
    
    final credentials = AccessCredentials(
      accessToken,
      tokenData['refresh_token'] as String?,
      _scopes,
    );
    
    _authClient = authenticatedClient(http.Client(), credentials);
    _driveApi = drive.DriveApi(_authClient!);
    
    // Create a mock account from stored data (simplified approach)
    // In a real implementation, you'd need to properly restore the account
    // For now, we'll mark as authenticated and verify with API call
    
    // Verify authentication is still valid
    try {
      await _driveApi!.about.get($fields: 'user');
      await _ensureBackupFolder();
      _authState = AuthenticationState.authenticated;
    } catch (e) {
      // Token might be expired, clear stored data and require fresh auth
      await _clearStoredCredentials();
      _authState = AuthenticationState.tokenExpired;
    }
  }

  /// Store authentication credentials securely
  Future<void> _storeCredentials(
    GoogleSignInAccount account,
    Map<String, String> authHeaders,
  ) async {
    try {
      // Extract token information
      final accessToken = authHeaders['Authorization']?.replaceFirst('Bearer ', '');
      if (accessToken == null) {
        throw GoogleDriveException('No access token found in auth headers');
      }
      
      // Get authentication details from Google Sign-In
      final authentication = await account.authentication;
      
      final tokenData = {
        'access_token': accessToken,
        // Note: Google Sign-In doesn't always provide refresh tokens
        // We'll store what's available
        'expiry_date': DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
      };
      
      final accountData = {
        'id': account.id,
        'email': account.email,
        'displayName': account.displayName,
        'photoUrl': account.photoUrl,
      };
      
      await _secureStorage.write(key: _tokenKey, value: jsonEncode(tokenData));
      await _secureStorage.write(key: _accountKey, value: jsonEncode(accountData));
    } catch (e) {
      throw GoogleDriveException(
        'Failed to store credentials: ${e.toString()}',
        originalException: e is Exception ? e : Exception(e.toString()),
      );
    }
  }

  /// Refresh authentication tokens
  Future<void> refreshTokens() async {
    await _refreshTokens();
  }

  Future<void> _refreshTokens() async {
    try {
      if (_currentAccount == null) {
        throw GoogleDriveException('No account available for token refresh');
      }
      
      // Force token refresh through Google Sign-In
      final authentication = await _currentAccount!.authentication;
      final authHeaders = await _currentAccount!.authHeaders;
      
      // Update auth client
      _authClient = _GoogleSignInAuthClient(authHeaders);
      _driveApi = drive.DriveApi(_authClient!);
      
      // Store updated credentials
      await _storeCredentials(_currentAccount!, authHeaders);
      
      _authState = AuthenticationState.authenticated;
    } catch (e) {
      _authState = AuthenticationState.tokenExpired;
      throw GoogleDriveException(
        'Failed to refresh tokens: ${e.toString()}',
        originalException: e is Exception ? e : Exception(e.toString()),
      );
    }
  }

  /// Sign out and clear stored credentials
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      await _clearStoredCredentials();
      
      _currentAccount = null;
      _authClient = null;
      _driveApi = null;
      _backupFolderId = null;
      _authState = AuthenticationState.notAuthenticated;
    } catch (e) {
      throw GoogleDriveException(
        'Failed to sign out: ${e.toString()}',
        originalException: e is Exception ? e : Exception(e.toString()),
      );
    }
  }

  /// Clear stored credentials
  Future<void> _clearStoredCredentials() async {
    await _secureStorage.delete(key: _tokenKey);
    await _secureStorage.delete(key: _accountKey);
  }

  /// Ensure the backup folder exists in Google Drive
  Future<void> _ensureBackupFolder() async {
    if (_driveApi == null) {
      throw GoogleDriveException('Drive API not initialized');
    }
    
    try {
      // Search for existing backup folder
      final query = "name='$_backupFolderName' and mimeType='application/vnd.google-apps.folder' and trashed=false";
      final searchResult = await _driveApi!.files.list(q: query);
      
      if (searchResult.files != null && searchResult.files!.isNotEmpty) {
        _backupFolderId = searchResult.files!.first.id;
        return;
      }
      
      // Create backup folder if it doesn't exist
      final folder = drive.File()
        ..name = _backupFolderName
        ..mimeType = 'application/vnd.google-apps.folder';
      
      final createdFolder = await _driveApi!.files.create(folder);
      _backupFolderId = createdFolder.id;
    } catch (e) {
      throw GoogleDriveException(
        'Failed to ensure backup folder exists: ${e.toString()}',
        originalException: e is Exception ? e : Exception(e.toString()),
      );
    }
  }

  /// Handle authentication failures gracefully
  Future<void> handleAuthenticationFailure(Exception error) async {
    _authState = AuthenticationState.authenticationFailed;
    
    // Clear stored credentials on authentication failure
    await _clearStoredCredentials();
    
    // Reset service state
    _currentAccount = null;
    _authClient = null;
    _driveApi = null;
    _backupFolderId = null;
    
    // Log the error (in a real app, you'd use a proper logging service)
    print('Authentication failure handled: ${error.toString()}');
  }

  /// Get list of available Google accounts
  Future<List<GoogleSignInAccount>> getAvailableAccounts() async {
    try {
      // Google Sign-In doesn't provide a direct way to list all accounts
      // This is a placeholder for the interface - actual implementation
      // would depend on platform-specific account management
      final currentAccount = await _googleSignIn.signInSilently();
      return currentAccount != null ? [currentAccount] : [];
    } catch (e) {
      throw GoogleDriveException(
        'Failed to get available accounts: ${e.toString()}',
        originalException: e is Exception ? e : Exception(e.toString()),
      );
    }
  }

  /// Switch to a different Google account
  Future<bool> switchAccount() async {
    try {
      await _googleSignIn.signOut();
      return await authenticate(forceAccountSelection: true);
    } catch (e) {
      throw GoogleDriveException(
        'Failed to switch account: ${e.toString()}',
        originalException: e is Exception ? e : Exception(e.toString()),
      );
    }
  }

  /// Check if authentication is still valid
  Future<bool> isAuthenticationValid() async {
    if (!isAuthenticated || _driveApi == null) {
      return false;
    }
    
    try {
      await _driveApi!.about.get($fields: 'user');
      return true;
    } catch (e) {
      _authState = AuthenticationState.tokenExpired;
      return false;
    }
  }

  /// Get backup folder ID (ensures folder exists)
  Future<String> getBackupFolderId() async {
    if (_backupFolderId == null) {
      await _ensureBackupFolder();
    }
    return _backupFolderId!;
  }

  /// Upload a backup file to Google Drive
  Future<String> uploadBackupFile(
    String fileName,
    List<int> encryptedData, {
    ProgressCallback? onProgress,
  }) async {
    if (!isAuthenticated || _driveApi == null) {
      throw GoogleDriveException('Not authenticated with Google Drive');
    }

    try {
      await _ensureBackupFolder();

      // Create file metadata
      final fileMetadata = drive.File()
        ..name = fileName
        ..parents = [_backupFolderId!]
        ..description = 'DocLedger encrypted backup file'
        ..createdTime = DateTime.now().toUtc();

      // Create media for upload
      final media = drive.Media(
        Stream.fromIterable([encryptedData]),
        encryptedData.length,
        contentType: 'application/octet-stream',
      );

      // Upload file with progress tracking
      final uploadedFile = await _driveApi!.files.create(
        fileMetadata,
        uploadMedia: media,
      );

      if (uploadedFile.id == null) {
        throw GoogleDriveException('Failed to upload file: No file ID returned');
      }

      // Call progress callback if provided
      onProgress?.call(encryptedData.length, encryptedData.length);

      return uploadedFile.id!;
    } catch (e) {
      if (e is GoogleDriveException) rethrow;
      throw GoogleDriveException(
        'Failed to upload backup file: ${e.toString()}',
        originalException: e is Exception ? e : Exception(e.toString()),
      );
    }
  }

  /// Download a backup file from Google Drive
  Future<List<int>> downloadBackupFile(
    String fileId, {
    ProgressCallback? onProgress,
  }) async {
    if (!isAuthenticated || _driveApi == null) {
      throw GoogleDriveException('Not authenticated with Google Drive');
    }

    try {
      // Get file metadata first to check size
      final fileMetadata = await _driveApi!.files.get(fileId) as drive.File;
      final fileSize = fileMetadata.size != null ? int.parse(fileMetadata.size!) : 0;

      // Download file content
      final media = await _driveApi!.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      final List<int> bytes = [];
      int totalBytesRead = 0;

      await for (final chunk in media.stream) {
        bytes.addAll(chunk);
        totalBytesRead += chunk.length;
        
        // Call progress callback if provided
        onProgress?.call(totalBytesRead, fileSize);
      }

      return bytes;
    } catch (e) {
      if (e is GoogleDriveException) rethrow;
      throw GoogleDriveException(
        'Failed to download backup file: ${e.toString()}',
        originalException: e is Exception ? e : Exception(e.toString()),
      );
    }
  }

  /// List all backup files in the backup folder
  Future<List<BackupFileInfo>> listBackupFiles() async {
    if (!isAuthenticated || _driveApi == null) {
      throw GoogleDriveException('Not authenticated with Google Drive');
    }

    try {
      await _ensureBackupFolder();

      // Query for backup files in the backup folder
      final query = "'$_backupFolderId' in parents and trashed=false";
      final fileList = await _driveApi!.files.list(
        q: query,
        orderBy: 'createdTime desc',
        $fields: 'files(id,name,size,createdTime,modifiedTime,description)',
      );

      final backupFiles = <BackupFileInfo>[];
      
      if (fileList.files != null) {
        for (final file in fileList.files!) {
          if (file.id != null && file.name != null) {
            backupFiles.add(BackupFileInfo(
              id: file.id!,
              name: file.name!,
              size: file.size != null ? int.parse(file.size!) : 0,
              createdTime: file.createdTime ?? DateTime.now(),
              modifiedTime: file.modifiedTime ?? DateTime.now(),
              description: file.description,
            ));
          }
        }
      }

      return backupFiles;
    } catch (e) {
      if (e is GoogleDriveException) rethrow;
      throw GoogleDriveException(
        'Failed to list backup files: ${e.toString()}',
        originalException: e is Exception ? e : Exception(e.toString()),
      );
    }
  }

  /// Get the latest backup file
  Future<BackupFileInfo?> getLatestBackup() async {
    try {
      final backupFiles = await listBackupFiles();
      
      if (backupFiles.isEmpty) {
        return null;
      }

      // Files are already ordered by creation time descending
      return backupFiles.first;
    } catch (e) {
      if (e is GoogleDriveException) rethrow;
      throw GoogleDriveException(
        'Failed to get latest backup: ${e.toString()}',
        originalException: e is Exception ? e : Exception(e.toString()),
      );
    }
  }

  /// Delete old backup files based on retention policy
  Future<void> deleteOldBackups({
    int maxDailyBackups = 30,
    int maxMonthlyBackups = 12,
  }) async {
    if (!isAuthenticated || _driveApi == null) {
      throw GoogleDriveException('Not authenticated with Google Drive');
    }

    try {
      final backupFiles = await listBackupFiles();
      
      if (backupFiles.length <= maxDailyBackups) {
        // Not enough files to require cleanup
        return;
      }

      // Sort files by creation time (newest first)
      backupFiles.sort((a, b) => b.createdTime.compareTo(a.createdTime));

      // Keep the most recent daily backups
      final filesToKeep = <BackupFileInfo>[];
      final filesToDelete = <BackupFileInfo>[];

      // Keep daily backups (most recent maxDailyBackups files)
      filesToKeep.addAll(backupFiles.take(maxDailyBackups));

      // For older files, keep one per month up to maxMonthlyBackups
      final monthlyBackups = <String, BackupFileInfo>{};
      for (final file in backupFiles.skip(maxDailyBackups)) {
        final monthKey = '${file.createdTime.year}-${file.createdTime.month.toString().padLeft(2, '0')}';
        
        if (!monthlyBackups.containsKey(monthKey) && monthlyBackups.length < maxMonthlyBackups) {
          monthlyBackups[monthKey] = file;
          filesToKeep.add(file);
        } else {
          filesToDelete.add(file);
        }
      }

      // Delete old files
      for (final file in filesToDelete) {
        try {
          await _driveApi!.files.delete(file.id);
        } catch (e) {
          // Log error but continue with other deletions
          print('Failed to delete backup file ${file.name}: ${e.toString()}');
        }
      }
    } catch (e) {
      if (e is GoogleDriveException) rethrow;
      throw GoogleDriveException(
        'Failed to delete old backups: ${e.toString()}',
        originalException: e is Exception ? e : Exception(e.toString()),
      );
    }
  }

  /// Validate backup file integrity
  Future<bool> validateBackupIntegrity(String fileId, String expectedChecksum) async {
    try {
      // Download the file
      final fileData = await downloadBackupFile(fileId);
      
      // Calculate checksum (this would typically use the same algorithm as encryption service)
      // For now, we'll use a simple approach
      final actualChecksum = _calculateChecksum(fileData);
      
      return actualChecksum == expectedChecksum;
    } catch (e) {
      throw GoogleDriveException(
        'Failed to validate backup integrity: ${e.toString()}',
        originalException: e is Exception ? e : Exception(e.toString()),
      );
    }
  }

  /// Delete a file from Google Drive
  Future<void> deleteFile(String fileId) async {
    if (!isAuthenticated || _driveApi == null) {
      throw GoogleDriveException('Not authenticated with Google Drive');
    }

    try {
      await _driveApi!.files.delete(fileId);
    } catch (e) {
      if (e is GoogleDriveException) rethrow;
      throw GoogleDriveException(
        'Failed to delete file: ${e.toString()}',
        originalException: e is Exception ? e : Exception(e.toString()),
      );
    }
  }

  /// Update an existing backup file in Google Drive
  Future<String> updateBackupFile(
    String fileId,
    String fileName,
    List<int> encryptedData, {
    ProgressCallback? onProgress,
  }) async {
    if (!isAuthenticated || _driveApi == null) {
      throw GoogleDriveException('Not authenticated with Google Drive');
    }

    try {
      // Create media for upload
      final media = drive.Media(
        Stream.fromIterable([encryptedData]),
        encryptedData.length,
        contentType: 'application/octet-stream',
      );

      // Update file with new content
      final updatedFile = await _driveApi!.files.update(
        drive.File()..name = fileName,
        fileId,
        uploadMedia: media,
      );

      if (updatedFile.id == null) {
        throw GoogleDriveException('Failed to update file: No file ID returned');
      }

      // Call progress callback if provided
      onProgress?.call(encryptedData.length, encryptedData.length);

      return updatedFile.id!;
    } catch (e) {
      if (e is GoogleDriveException) rethrow;
      throw GoogleDriveException(
        'Failed to update backup file: ${e.toString()}',
        originalException: e is Exception ? e : Exception(e.toString()),
      );
    }
  }

  /// Calculate checksum for data integrity validation
  String _calculateChecksum(List<int> data) {
    // This is a simplified checksum calculation
    // In a real implementation, you'd use a proper hash function
    int checksum = 0;
    for (final byte in data) {
      checksum = (checksum + byte) % 0xFFFFFFFF;
    }
    return checksum.toRadixString(16);
  }
}

/// Information about a backup file in Google Drive
class BackupFileInfo {
  final String id;
  final String name;
  final int size;
  final DateTime createdTime;
  final DateTime modifiedTime;
  final String? description;

  const BackupFileInfo({
    required this.id,
    required this.name,
    required this.size,
    required this.createdTime,
    required this.modifiedTime,
    this.description,
  });

  @override
  String toString() {
    return 'BackupFileInfo(id: $id, name: $name, size: $size, created: $createdTime)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BackupFileInfo &&
        other.id == id &&
        other.name == name &&
        other.size == size &&
        other.createdTime == createdTime &&
        other.modifiedTime == modifiedTime &&
        other.description == description;
  }

  @override
  int get hashCode {
    return Object.hash(id, name, size, createdTime, modifiedTime, description);
  }
}

/// Custom HTTP client that uses Google Sign-In authentication headers
class _GoogleSignInAuthClient extends http.BaseClient {
  final Map<String, String> _authHeaders;
  final http.Client _client = http.Client();

  _GoogleSignInAuthClient(this._authHeaders);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_authHeaders);
    return _client.send(request);
  }

  @override
  void close() {
    _client.close();
  }
}