import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../../core/cloud/services/cloud_save_service.dart';
import '../../../../core/cloud/models/cloud_save_models.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/cloud/services/webdav_backup_service.dart';
import '../../../../core/cloud/webdav_config.dart';
import '../../../subscription/presentation/pages/subscription_page.dart';
import 'package:url_launcher/url_launcher.dart';

/// Simplified cloud save settings page
class SettingsPage extends StatefulWidget {
  static const String routeName = '/settings';

  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  CloudSaveService? _cloudSaveService;
  WebDavBackupService? _webdavService;
  bool _isLoading = false;
  CloudSaveState? _currentState;
  bool _hasCloudBackup = false;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  String? _loggedInUsername;
  String? _clinicId;
  String? _accountMessage;
  bool _accountHydrated = false;
  
  @override
  void initState() {
    super.initState();
    try {
  _cloudSaveService = serviceLocator.get<CloudSaveService>();
  _webdavService = serviceLocator.get<WebDavBackupService>();
      _cloudSaveService?.stateStream.listen((state) {
        if (mounted) setState(() => _currentState = state);
      });
      _currentState = _cloudSaveService?.currentState;
  _loadLoggedInUsername();
    } catch (e) {
      setState(() { _isLoading = false; });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureAccountHydrated();
  }

  void _ensureAccountHydrated() async {
    if (_accountHydrated) return;
    try {
      final linked = await (_webdavService?.isReady() ?? Future.value(false));
      if (!linked) return;
      bool changed = false;
      if (_clinicId == null || _clinicId!.isEmpty) {
        try {
          final cid = await _webdavService!.getCurrentClinicId();
          if (mounted) {
            setState(() { _clinicId = cid; });
            changed = true;
          }
        } catch (_) {}
      }
    if (_loggedInUsername == null || _loggedInUsername!.isEmpty) {
        try {
      final u = _webdavService!.getCurrentUsernameCached() ?? await _secureStorage.read(key: 'webdav_username');
          if (u != null && u.isNotEmpty && mounted) {
            setState(() { _loggedInUsername = u; });
            changed = true;
          }
        } catch (_) {}
      }
      if (changed) {
        setState(() { _accountHydrated = true; });
      } else {
        _accountHydrated = true;
      }
    } catch (_) {}
  }

  Future<void> _loadLoggedInUsername() async {
    try {
    final stored = await _secureStorage.read(key: 'webdav_username');
    final clinicId = await _secureStorage.read(key: 'webdav_clinic_id');
      if (mounted) {
        setState(() {
          _loggedInUsername = stored;
      _clinicId = clinicId;
          // Keep any explicit message; else show logged in line if available
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), centerTitle: false),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _cloudSaveService == null || _webdavService == null
              ? _buildErrorState()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildAccountSection(),
                      const SizedBox(height: 16),
                      _buildSubscriptionSection(),
                      const SizedBox(height: 16),
                      _buildCloudSaveSection(),
                      const SizedBox(height: 16),
                      _buildStatusSection(),
                      if (MediaQuery.sizeOf(context).width < 600) ...[
                        const SizedBox(height: 16),
                        _buildSupportSection(),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildAccountSection() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Account', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
      Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
        // Match the Free Plan card background tone
        color: Theme.of(context).colorScheme.surfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _webDavAccountRow(),
                  const SizedBox(height: 8),
                  _buildAccountMessageBox(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountMessageBox() {
    final theme = Theme.of(context);
    final color = theme.colorScheme;
    final String text;
    if (_accountMessage != null && _accountMessage!.isNotEmpty) {
      text = _accountMessage!;
    } else if ((_loggedInUsername != null && _loggedInUsername!.isNotEmpty) || (_clinicId != null && _clinicId!.isNotEmpty)) {
      final who = _loggedInUsername ?? 'unknown-user';
      final cid = _clinicId ?? 'unknown-clinic';
      text = 'Logged in as $who';
    } else {
      text = 'No account linked';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
  // Keep inner message box color as before (slightly lifted surface)
  color: color.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
  border: Border.all(color: color.outlineVariant.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(
            (_loggedInUsername != null && _loggedInUsername!.isNotEmpty) ? Icons.verified_user : Icons.info_outline,
            size: 18,
            color: (_loggedInUsername != null && _loggedInUsername!.isNotEmpty) ? color.primary : color.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(color: color.onSurfaceVariant),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _webDavAccountRow() {
  final linkedFuture = _webdavService?.isReady() ?? Future.value(false);
    return FutureBuilder<bool>(
      future: linkedFuture,
      builder: (context, snapshot) {
        final linked = snapshot.data == true;
        if (linked && !_accountHydrated) {
          // Hydrate missing account info on rebuilds (e.g., tab switches)
          _ensureAccountHydrated();
        }
        return Row(
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: linked ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.cloud, color: linked ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurfaceVariant, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                'WebDAV Cloud',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: linked ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 12),
            if (!linked)
              FilledButton.icon(
                onPressed: _isLoading ? null : _openLoginFromLinkDialog,
                icon: const Icon(Icons.login, size: 18),
                label: const Text('Login'),
                style: MediaQuery.sizeOf(context).width < 600
                    ? FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14))
                    : null,
              )
            else
              OutlinedButton.icon(
                onPressed: _isLoading
                    ? null
                    : () async {
                        setState(() => _isLoading = true);
                        try {
                          await _webdavService!.logout();
                          // Clear local UI state
                          setState(() {
                            _loggedInUsername = null;
                            _clinicId = null;
                            _accountMessage = null;
                          });
                          // Inform cloud save service to recompute status
                          await _cloudSaveService?.refreshSyncStatus();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Logged out.')),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Logout failed: $e')),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _isLoading = false);
                        }
                      },
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Logout'),
                style: OutlinedButton.styleFrom(
                  // Softer error tint and a lighter outline to match overall theme
                  foregroundColor: Theme.of(context).colorScheme.error.withValues(alpha: 0.85),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6),
                    width: 1.0,
                  ),
                  padding: MediaQuery.sizeOf(context).width < 600
                      ? const EdgeInsets.symmetric(horizontal: 16, vertical: 14)
                      : null,
                ),
              ),
          ],
        );
      },
    );
  }

  // Login dialog (username/password), uses preconfigured WebDAV URL/email/password from WebDavConfig or stored setup
  Future<void> _openLoginFromLinkDialog() async {
    // If not configured in code, ensure stored creds exist
    if (!WebDavConfig.hasCredentials) {
      final ensured = await _ensureServerCreds();
      if (!ensured) return;
    }

  final usernameController = TextEditingController();
  final passwordController = TextEditingController(); // plain text for initial phase
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Login to Cloud'),
        content: Form(
          key: formKey,
          child: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: usernameController,
                decoration: const InputDecoration(labelText: 'Username'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: passwordController,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ],
            ),
          ),
        ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
                style: MediaQuery.sizeOf(context).width < 600
                    ? TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14))
                    : null,
              ),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState?.validate() == true) {
                    Navigator.of(context).pop(true);
                  }
                },
                child: const Text('Continue'),
                style: MediaQuery.sizeOf(context).width < 600
                    ? FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14))
                    : null,
              ),
            ],
      ),
    );

    if (confirmed != true) return;

    final username = usernameController.text.trim().toLowerCase();
    setState(() => _isLoading = true);
    try {
      // If using stored creds, load them, else WebDavConfig has them
      final creds = WebDavConfig.hasCredentials ? {
        'baseUrl': WebDavConfig.baseUrl,
        'email': WebDavConfig.email,
        'password': WebDavConfig.password,
      } : await _loadServerCreds();
      if (creds == null) {
        throw Exception('Server credentials not set');
      }

      // Apply credentials to the runtime service to ensure `isReady()` reflects link state now
      try {
        await _webdavService!.setCredentials(creds['baseUrl']!, creds['email']!, creds['password']!);
      } catch (_) {}

    // Find clinic for credentials (plain text compare) using index/scan
  // Ensure index scaffolding exists before lookup (idempotent)
  try { await _webdavService!.ensureClinicsIndex(); } catch (_) {}
  final clinicId = await _webdavService!.findClinicForCredentials(username, passwordController.text);
    final ok = clinicId != null;
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('User not found in clinics metadata.')),
        );
        return;
      }

  // Set clinic id for clinic-centric backups
  await _webdavService!.setClinicId(clinicId!);
  // Cache username for hydration across tab switches
  try { await _webdavService!.setCurrentUsername(username); } catch (_) {}

      // Update UI immediately and persist username (best effort on desktop)
  if (mounted) setState(() { _loggedInUsername = username; _clinicId = clinicId; });
  try { await _secureStorage.write(key: 'webdav_username', value: username); } catch (_) {}
  try { await _secureStorage.write(key: 'webdav_clinic_id', value: clinicId); } catch (_) {}

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logged in successfully. Cloud index verified.')),
      );

  // Refresh sync readiness so controls update immediately
  try { await _cloudSaveService?.refreshSyncStatus(); } catch (_) {}

  // Optional: trigger a first backup or handle restore prompt
  await _handlePostLink();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildSupportSection() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Support',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _openSupportDialog,
                    icon: const Icon(Icons.support_agent, size: 20),
                    label: const Text('Contact Support'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubscriptionSection() {
    final colorScheme = Theme.of(context).colorScheme;
  final bgColor = colorScheme.surfaceVariant.withValues(alpha: 0.4);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.workspace_premium,
                color: colorScheme.primary,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Free Plan',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Basic features with limited cloud storage',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pushNamed(SubscriptionPage.routeName);
                },
        style: MediaQuery.sizeOf(context).width < 600
          ? FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14))
          : null,
        child: const Text('Manage'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCloudSaveSection() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: FutureBuilder<bool>(
          future: _webdavService?.isReady() ?? Future.value(false),
          builder: (context, snapshot) {
            final linked = snapshot.data == true;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Auto-Save to Cloud',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Automatically save your data to cloud with simple controls.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                _SettingSwitch(
                  title: 'Auto-Save to Cloud',
                  subtitle: 'Automatically save your data to cloud',
                  value: _cloudSaveService?.autoSaveEnabled ?? true,
                  redWhenOff: true,
                  onChanged: (!linked || _cloudSaveService == null) ? null : (value) async {
                    await _cloudSaveService!.setAutoSaveEnabled(value);
                    setState(() {});
                  },
                ),
                _SettingSwitch(
                  title: 'WiFi Only',
                  subtitle: 'Only save to cloud when connected to WiFi',
                  value: _cloudSaveService?.wifiOnlyMode ?? true,
                  redWhenOff: true,
                  onChanged: (!linked || _cloudSaveService == null) ? null : (value) async {
                    await _cloudSaveService!.setWifiOnlyMode(value);
                    setState(() {});
                  },
                ),
                _SettingSwitch(
                  title: 'Show Notifications',
                  subtitle: 'Show notifications when data is saved or restored',
                  value: _cloudSaveService?.showNotifications ?? true,
                  redWhenOff: true,
                  onChanged: (!linked || _cloudSaveService == null) ? null : (value) async {
                    await _cloudSaveService!.setShowNotifications(value);
                    setState(() {});
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatusSection() {
    if (_currentState == null) {
      return const SizedBox.shrink();
    }

    final state = _currentState!;
    final isIdle = state.status == CloudSaveStatus.idle;
    final isError = state.status == CloudSaveStatus.error;
    final isWorking = state.status == CloudSaveStatus.saving || state.status == CloudSaveStatus.restoring;
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Status',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                // No explicit Save button; auto-save handles backups
              ],
            ),
            const SizedBox(height: 16),
            
            // Status indicator
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isError 
                  ? Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.3)
                  : isWorking
                    ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
                    : Theme.of(context).colorScheme.surfaceVariant.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isError
                    ? Theme.of(context).colorScheme.error.withValues(alpha: 0.3)
                    : isWorking
                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
                      : Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: isError 
                            ? Theme.of(context).colorScheme.error
                            : isWorking
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.surfaceVariant,
                          shape: BoxShape.circle,
                        ),
                        child: isWorking
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Theme.of(context).colorScheme.onPrimary,
                                ),
                              ),
                            )
                          : Icon(
                              isError ? Icons.error : Icons.cloud_done,
                              color: isError 
                                ? Theme.of(context).colorScheme.onError
                                : isIdle
                                  ? Theme.of(context).colorScheme.onSurfaceVariant
                                  : Theme.of(context).colorScheme.onPrimary,
                              size: 18,
                            ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            state.statusMessage,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isError 
                                ? Theme.of(context).colorScheme.error
                                : Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  // Progress bar for active operations
                  if (isWorking && state.progress != null) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: state.progress,
                      backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                  
                  // No inline action buttons; actions appear consistently below
                ],
              ),
            ),
            
            // Actions area: Sync with Cloud (decides restore/upload)
            FutureBuilder<bool>(
              future: _webdavService?.isReady() ?? Future.value(false),
              builder: (context, snapshot) {
                final linked = snapshot.data == true;
                if (!isWorking && linked) {
                  final bool syncEnabled = _cloudSaveService?.shouldEnableSync ?? false;
                  final bool restoreEnabled = _hasCloudBackup == true;
                  return Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: isMobile
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              FilledButton.icon(
                                onPressed: syncEnabled ? _syncNow : null,
                                icon: const Icon(Icons.sync, size: 18),
                                label: const Text('Sync with Cloud'),
                                style: MediaQuery.sizeOf(context).width < 600
                                    ? FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14))
                                    : null,
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              FilledButton.icon(
                                onPressed: syncEnabled ? _syncNow : null,
                                icon: const Icon(Icons.sync, size: 18),
                                label: const Text('Sync with Cloud'),
                              ),
                            ],
                          ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }

  // Removed manual Save Now UI entry point; auto-save and _scheduleFirstBackup handle backups

  Future<void> _restoreFromCloud() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore from Cloud'),
        content: const Text(
          'This will replace your current data with the data from your most recent cloud save. Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _startRestoreDirect();
  }

  Future<void> _startRestoreDirect() async {
    if (_cloudSaveService == null) return;
    // Inform user immediately; progress will appear in the Status card
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Restoring data from cloud...')),
      );
    }
    try {
      final result = await _cloudSaveService!.restoreFromCloud();
      if (!mounted) return;
      if (result.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data restored from cloud successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Restore failed: ${result.errorMessage}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Restore error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _syncNow() async {
    try {
      final result = await _cloudSaveService!.syncNow();
      if (!mounted) return;
      if (result.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sync completed successfully')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.errorMessage ?? 'Sync failed')),
        );
      }
    } finally {}
  }

  Future<void> _openSupportDialog() async {
    // Desktop variant behavior: open default mail client with prefilled subject
      final subject = Uri.encodeComponent('DocLedger Support');
    final uri = Uri.parse('mailto:docledger.pk@gmail.com?subject=$subject');
      try {
        await launchUrl(uri);
      } catch (_) {
        if (!mounted) return;
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Contact Support'),
            content: const SelectableText('Email us at\n\n' 'docledger.pk@gmail.com'),
            actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
          ),
        );
    }
  }

  // Schedules an automatic first backup shortly after linking
  void _scheduleFirstBackup() {
    if (_cloudSaveService == null) return;
    // Let the UI settle, then trigger a save (respects WiFi-only and auth checks internally)
    Future.delayed(const Duration(seconds: 2), () async {
      try {
        // Only run an immediate save if auto-save is enabled
        if (_cloudSaveService!.autoSaveEnabled) {
          await _cloudSaveService!.saveNow();
        }
      } catch (_) {
        // Ignore; status card will show any error
      } finally {
        _refreshBackupAvailability();
      }
    });
  }

  // Checks whether at least one backup exists to enable restore
  Future<void> _refreshBackupAvailability() async {
    try {
      final linked = await (_webdavService?.isReady() ?? Future.value(false));
      if (linked) {
        await _cloudSaveService?.refreshSyncStatus();
        // Robust check: try latest then list
        bool any = await _cloudSaveService?.hasAnyCloudBackup() ?? false;
        if (!any) {
          try {
            final svc = serviceLocator.get<WebDavBackupService>();
            final list = await svc.listBackups();
            any = list.isNotEmpty;
          } catch (_) {}
        }
        if (mounted) {
          setState(() {
            _hasCloudBackup = any;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _hasCloudBackup = false;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _hasCloudBackup = false;
        });
      }
    }
  }

  // After a fresh link on a new install, prefer recovery if a backup exists
  Future<void> _handlePostLink() async {
    // Refresh availability first
    await _refreshBackupAvailability();
    if (_hasCloudBackup) {
      // Ask user whether to restore now; keep simple yes/no
      final restoreNow = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Restore from Cloud?'),
          content: const Text('We found a previous cloud backup for your account. Do you want to restore your data now?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Not Now')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Restore')),
          ],
        ),
      );
      if (restoreNow == true) {
        // Navigate away immediately, then start restore (status card will show progress)
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/');
        }
        await _startRestoreDirect();
        return;
      }
      // User skipped restore while a cloud backup exists: do NOT create a new
      // empty backup. Leave the Restore button enabled so they can restore later.
      return;
    }
    // No existing backup: do not schedule an immediate backup. User can sync manually later.
    return;
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Cloud Save Service Unavailable',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'The cloud save service failed to initialize. Please restart the app.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                // Try to reinitialize
                setState(() {
                  _isLoading = true;
                });
                
                Future.delayed(const Duration(seconds: 1), () {
                  if (mounted) {
                    setState(() {
                      _isLoading = false;
                    });
                  }
                });
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _ensureServerCreds() async {
    final existing = await _loadServerCreds();
    if (existing != null || WebDavConfig.hasCredentials) return true;

    return await _promptServerCredsDialog() == true;
  }

  Future<bool?> _promptServerCredsDialog() async {
    final baseUrlController = TextEditingController(text: 'https://ewebdav.pcloud.com');
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set up WebDAV server'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: baseUrlController,
                decoration: const InputDecoration(labelText: 'Server URL'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: emailController,
                decoration: const InputDecoration(labelText: 'WebDAV Email'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: passwordController,
                decoration: const InputDecoration(labelText: 'WebDAV Password'),
                obscureText: true,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                Navigator.of(context).pop(true);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved == true) {
      final base = baseUrlController.text.trim();
      final email = emailController.text.trim();
      final pass = passwordController.text;
      await _saveServerCreds(base, email, pass);
      // Update the runtime service too
      try {
        final svc = serviceLocator.get<WebDavBackupService>();
        await svc.setCredentials(base, email, pass);
      } catch (_) {}
      return true;
    }
    return false;
  }

  Future<Map<String, String>?> _loadServerCreds() async {
    if (WebDavConfig.hasCredentials) {
      return {
        'baseUrl': WebDavConfig.baseUrl,
        'email': WebDavConfig.email,
        'password': WebDavConfig.password,
      };
    }
    final baseUrl = await _secureStorage.read(key: 'webdav_base_url');
    final email = await _secureStorage.read(key: 'webdav_email');
    final password = await _secureStorage.read(key: 'webdav_password');
    if (baseUrl != null && email != null && password != null) {
      return {
        'baseUrl': baseUrl,
        'email': email,
        'password': password,
      };
    }
    return null;
  }

  Future<void> _saveServerCreds(String baseUrl, String email, String password) async {
    await _secureStorage.write(key: 'webdav_base_url', value: baseUrl);
    await _secureStorage.write(key: 'webdav_email', value: email);
    await _secureStorage.write(key: 'webdav_password', value: password);
  }

  // Deprecated: username marker flow replaced by clinic-centric metadata
  Future<bool> _verifyUserAndPrepareFolder(String username) async {
    final creds = await _loadServerCreds();
    if (creds == null) return false;

    String _normalize(String url) => url.endsWith('/') ? url.substring(0, url.length - 1) : url;

    final base = _normalize(creds['baseUrl']!);
    final email = creds['email']!;
    final password = creds['password']!;
    final authHeader = 'Basic ' + base64Encode(utf8.encode('$email:$password'));

    // Verify user marker exists
  final markerUri = Uri.parse('$base/docledger_backups/clinics-index/by-username/$username.json');
    final markerResp = await http.get(markerUri, headers: {
      'Authorization': authHeader,
    });

    // add a log for the terminal to check response
    print('Checking user marker at $markerUri: ${markerResp.statusCode}');

    if (markerResp.statusCode != 200) {
      return false;
    }

    // Ensure user backup folder exists
    final folderUri = Uri.parse('$base/docledger_backups/$username/');
    final mkcol = http.Request('MKCOL', folderUri);
    mkcol.headers['Authorization'] = authHeader;
    mkcol.headers['Content-Length'] = '0';
    final mkcolResp = await mkcol.send();

    if (mkcolResp.statusCode == 201 || mkcolResp.statusCode == 405 || mkcolResp.statusCode == 409) {
      return true;
    }
    if (mkcolResp.statusCode >= 200 && mkcolResp.statusCode < 400) {
      return true;
    }
    return false;
  }
  
}

class _SettingSwitch extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool redWhenOff;

  const _SettingSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  this.redWhenOff = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Builder(builder: (context) {
            final enabled = onChanged != null;
            final isOff = !value;
            final showRed = enabled && redWhenOff && isOff;
            final scheme = Theme.of(context).colorScheme;
            return Switch(
              value: value,
              onChanged: onChanged,
        // Softer red styling when OFF (still enabled)
        thumbColor: showRed
          ? MaterialStateProperty.resolveWith<Color?>((_) => scheme.error.withValues(alpha: 0.55))
          : null,
        trackColor: showRed
          ? MaterialStateProperty.resolveWith<Color?>((_) => scheme.error.withValues(alpha: 0.22))
          : null,
        // Remove dark outline to match the app's soft surfaces
        trackOutlineColor: showRed
          ? MaterialStateProperty.resolveWith<Color?>((_) => Colors.transparent)
          : null,
            );
          }),
        ],
      ),
    );
  }
}