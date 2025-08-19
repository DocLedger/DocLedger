import 'package:flutter/material.dart';
import '../../../../core/cloud/services/cloud_save_service.dart';
import '../../../../core/cloud/models/cloud_save_models.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/cloud/services/google_drive_service.dart';
import '../../../../core/data/services/database_service.dart';
import '../../../subscription/presentation/pages/subscription_page.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../dashboard/presentation/dashboard_page.dart';

/// Simplified cloud save settings page
class SettingsPage extends StatefulWidget {
  static const String routeName = '/settings';

  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  CloudSaveService? _cloudSaveService;
  GoogleDriveService? _driveService;
  bool _isLoading = false;
  CloudSaveState? _currentState;
  bool _hasCloudBackup = false;

  @override
  void initState() {
    super.initState();
    
    try {
      _cloudSaveService = serviceLocator.get<CloudSaveService>();
      _driveService = serviceLocator.get<GoogleDriveService>();
      
      // Listen to cloud save state changes
      _cloudSaveService?.stateStream.listen((state) {
        if (mounted) {
          setState(() {
            _currentState = state;
          });
        }
        if (state.status == CloudSaveStatus.idle) {
          _refreshBackupAvailability();
        }
      });
      
      // Get initial state
      _currentState = _cloudSaveService?.currentState;
      // Check if any backups exist initially
      _refreshBackupAvailability();
    } catch (e) {
      print('Failed to initialize SettingsPage: $e');
      // Show error state
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: false,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _cloudSaveService == null || _driveService == null
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
    final isLinked = _driveService?.isAuthenticated ?? false;
    final email = _driveService?.currentAccount?.email ?? '';
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Account',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isLinked 
                  ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.2)
                  : Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: isMobile
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: isLinked 
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.surfaceVariant,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isLinked ? Icons.account_circle : Icons.account_circle_outlined,
                                color: isLinked 
                                  ? Theme.of(context).colorScheme.onPrimary
                                  : Theme.of(context).colorScheme.onSurfaceVariant,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                isLinked ? 'Google Account Linked' : 'No Account Linked',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: isLinked 
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            FilledButton.icon(
                              onPressed: _isLoading || _driveService == null
                                  ? null
                                  : () async {
                                      setState(() => _isLoading = true);
                                      try {
                                        final ok = await _driveService!.authenticate(forceAccountSelection: true);
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text(ok ? 'Google account linked successfully' : 'Account linking cancelled')),
                                        );
                                        setState(() {
                                          if (ok) {
                                            _currentState = CloudSaveState.idle(
                                              lastSaveTime: _currentState?.lastSaveTime,
                                            );
                                          }
                                        });
                                        if (ok) {
                                          await _handlePostLink();
                                        }
                                      } catch (e) {
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Failed to link account: $e')),
                                        );
                                      } finally {
                                        if (mounted) setState(() => _isLoading = false);
                                      }
                                    },
                              icon: Icon(
                                isLinked ? Icons.swap_horiz : Icons.link,
                                size: 18,
                              ),
                              label: Text(isLinked ? 'Switch' : 'Link'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                (isLinked && email.isNotEmpty) ? Icons.email_outlined : Icons.info_outline,
                                size: 18,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  (isLinked && email.isNotEmpty)
                                      ? 'Account email: $email'
                                      : 'Link your Google account to enable cloud storage',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                  softWrap: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: isLinked 
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.surfaceVariant,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isLinked ? Icons.account_circle : Icons.account_circle_outlined,
                                color: isLinked 
                                  ? Theme.of(context).colorScheme.onPrimary
                                  : Theme.of(context).colorScheme.onSurfaceVariant,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                isLinked ? 'Google Account Linked' : 'No Account Linked',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: isLinked 
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            FilledButton.icon(
                              onPressed: _isLoading || _driveService == null
                                  ? null
                                  : () async {
                                      setState(() => _isLoading = true);
                                      try {
                                        final ok = await _driveService!.authenticate(forceAccountSelection: true);
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text(ok ? 'Google account linked successfully' : 'Account linking cancelled')),
                                        );
                                        setState(() {
                                          if (ok) {
                                            _currentState = CloudSaveState.idle(
                                              lastSaveTime: _currentState?.lastSaveTime,
                                            );
                                          }
                                        });
                                        if (ok) {
                                          await _handlePostLink();
                                        }
                                      } catch (e) {
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Failed to link account: $e')),
                                        );
                                      } finally {
                                        if (mounted) setState(() => _isLoading = false);
                                      }
                                    },
                              icon: Icon(
                                isLinked ? Icons.swap_horiz : Icons.link,
                                size: 18,
                              ),
                              label: Text(isLinked ? 'Switch' : 'Link'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                (isLinked && email.isNotEmpty) ? Icons.email_outlined : Icons.info_outline,
                                size: 18,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  (isLinked && email.isNotEmpty)
                                      ? 'Account email: $email'
                                      : 'Link your Google account to enable cloud storage',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                  softWrap: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
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
    final bgColor = colorScheme.surfaceVariant.withOpacity(0.4);
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
        child: Column(
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
              onChanged: _cloudSaveService == null ? null : (value) async {
                await _cloudSaveService!.setAutoSaveEnabled(value);
                setState(() {});
              },
            ),
            _SettingSwitch(
              title: 'WiFi Only',
              subtitle: 'Only save to cloud when connected to WiFi',
              value: _cloudSaveService?.wifiOnlyMode ?? true,
              onChanged: _cloudSaveService == null ? null : (value) async {
                await _cloudSaveService!.setWifiOnlyMode(value);
                setState(() {});
              },
            ),
            _SettingSwitch(
              title: 'Show Notifications',
              subtitle: 'Show notifications when data is saved or restored',
              value: _cloudSaveService?.showNotifications ?? true,
              onChanged: _cloudSaveService == null ? null : (value) async {
                await _cloudSaveService!.setShowNotifications(value);
                setState(() {});
              },
            ),
          ],
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
                  ? Theme.of(context).colorScheme.errorContainer.withOpacity(0.3)
                  : isWorking
                    ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
                    : Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isError 
                    ? Theme.of(context).colorScheme.error.withOpacity(0.3)
                    : isWorking
                      ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
                      : Theme.of(context).colorScheme.outline.withOpacity(0.3),
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
            if (!isWorking && (_driveService?.isAuthenticated ?? false)) ...[
              const SizedBox(height: 16),
              Builder(
                builder: (context) {
                  if (isMobile) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FilledButton.icon(
                          onPressed: (_cloudSaveService?.shouldEnableSync ?? false) ? _syncNow : null,
                          icon: const Icon(Icons.sync, size: 18),
                          label: const Text('Sync with Cloud'),
                        ),
                      ],
                    );
                  }
                  // Desktop/tablet wide: Sync
                  return Row(
                    children: [
                      FilledButton.icon(
                        onPressed: (_cloudSaveService?.shouldEnableSync ?? false) ? _syncNow : null,
                        icon: const Icon(Icons.sync, size: 18),
                        label: const Text('Sync with Cloud'),
                      ),
                    ],
                  );
                },
              ),
            ],
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
        await _cloudSaveService!.saveNow();
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
      if (_driveService?.isAuthenticated ?? false) {
        final latest = await _driveService!.getLatestBackup();
        if (mounted) {
          setState(() {
            _hasCloudBackup = latest != null;
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
    // If no backup exists, schedule the first backup as before
    _scheduleFirstBackup();
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
}

class _SettingSwitch extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _SettingSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
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
          Switch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}