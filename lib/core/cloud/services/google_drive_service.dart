/// Deprecated Google Drive service stub.
///
/// Google Drive integration has been removed from DocLedger.
/// This stub remains to avoid build errors if referenced anywhere.
class GoogleDriveService {
  bool get isAuthenticated => false;

  Future<void> initialize() async {}

  Future<bool> authenticate({bool forceAccountSelection = false}) async => false;

  Future<void> signOut() async {}

  Future<void> deleteOldBackups({int maxDailyBackups = 30, int maxMonthlyBackups = 12}) async {}
}