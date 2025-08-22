/// WebDAV server configuration for DocLedger
///
/// Fill in your production credentials here if you want to hard-code them.
/// In development, you can leave email/password empty and the app will prompt
/// once to store them securely on the device.
class WebDavConfig {
  // Example: 'https://ewebdav.pcloud.com'
  static const String baseUrl = 'https://ewebdav.pcloud.com';

  // Hard-code the WebDAV login if desired. Leave empty to prompt and store securely.
  static const String email = 'docledger.pk@gmail.com';
  static const String password = 'Capsl0ck130_';

  static bool get hasCredentials => email.isNotEmpty && password.isNotEmpty;
}
