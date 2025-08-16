import 'package:flutter/material.dart';
import '../../models/sync_settings.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/cloud/services/google_drive_service.dart';
import '../../../../core/sync/services/sync_service.dart';

/// Page for configuring sync and backup settings
class SyncSettingsPage extends StatefulWidget {
  static const String routeName = '/sync-settings';
  
  final SyncSettings? initialSettings;
  final DriveStorageInfo? storageInfo;
  final Function(SyncSettings)? onSettingsChanged;
  final Future<void> Function()? onRefreshStorage;
  final VoidCallback? onManageBackups;
  final VoidCallback? onViewConflicts;

  const SyncSettingsPage({
    super.key,
    this.initialSettings,
    this.onSettingsChanged,
    this.storageInfo,
    this.onRefreshStorage,
    this.onManageBackups,
    this.onViewConflicts,
  });

  @override
  State<SyncSettingsPage> createState() => _SyncSettingsPageState();
}

class _SyncSettingsPageState extends State<SyncSettingsPage> {
  late SyncSettings _settings;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings ?? SyncSettings.defaultSettings();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync & Backup Settings'),
        actions: [
          if (widget.onRefreshStorage != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _isLoading ? null : _refreshStorage,
              tooltip: 'Refresh Storage Info',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSyncSection(),
                  const SizedBox(height: 16),
                  _buildBackupSection(),
                  const SizedBox(height: 16),
                  _buildStorageSection(),
                  const SizedBox(height: 16),
                  _buildAdvancedSection(),
                  const SizedBox(height: 12),
                  _buildActionsSection(),
                ],
              ),
            ),
    );
  }

  Widget _buildSyncSection() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Synchronization',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            SwitchListTile(
              title: const Text('Encrypt backups (AES‑GCM)')
              ,subtitle: const Text('Recommended. Disable only for debugging/plain JSON'),
              value: _settings.encryptBackups,
              onChanged: (value) {
                setState(() {
                  _settings = _settings.copyWith(encryptBackups: value);
                });
                widget.onSettingsChanged?.call(_settings);
              },
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Auto-Backup'),
              subtitle: const Text('Automatically backup data when changes are made'),
              value: _settings.autoBackupEnabled,
              onChanged: (value) {
                setState(() {
                  _settings = _settings.copyWith(autoBackupEnabled: value);
                });
                widget.onSettingsChanged?.call(_settings);
              },
            ),
            SwitchListTile(
              title: const Text('WiFi Only'),
              subtitle: const Text('Only sync when connected to WiFi'),
              value: _settings.wifiOnlySync,
              onChanged: (value) {
                setState(() {
                  _settings = _settings.copyWith(wifiOnlySync: value);
                });
                widget.onSettingsChanged?.call(_settings);
              },
            ),
            SwitchListTile(
              title: const Text('Sync Notifications'),
              subtitle: const Text('Show notifications for sync operations'),
              value: _settings.showSyncNotifications,
              onChanged: (value) {
                setState(() {
                  _settings = _settings.copyWith(showSyncNotifications: value);
                });
                widget.onSettingsChanged?.call(_settings);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsSection() {
    final drive = serviceLocator.get<GoogleDriveService>();
    final sync = serviceLocator.get<SyncService>();
    // propagate toggle into service
    sync.setEncryptBackups(_settings.encryptBackups);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Actions',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            // Row 1: Link account button + email/status
            Row(
              children: [
                _ActionButton(
                  icon: Icons.login,
                  label: drive.isAuthenticated ? 'Switch Account' : 'Link Google Account',
                  primary: true,
                  onPressed: _isLoading
                      ? null
                      : () async {
                          setState(() => _isLoading = true);
                          try {
                            final ok = await drive.authenticate(forceAccountSelection: true);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(ok ? 'Google linked' : 'Cancelled')),
                            );
                            setState(() {});
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Auth failed: $e')),
                            );
                          } finally {
                            if (mounted) setState(() => _isLoading = false);
                          }
                        },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    drive.isAuthenticated
                        ? 'Linked account: ${drive.currentAccount?.email ?? ''}'
                        : 'No Google account linked',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Row 2: Buttons with per-action descriptions
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 860;
                final items = <Widget>[
                  _ActionWithHelp(
                    button: _ActionButton(
                      icon: Icons.sync,
                      label: 'Run Incremental Sync',
                      onPressed: _isLoading
                          ? null
                          : () async {
                              setState(() => _isLoading = true);
                              try {
                                final res = await sync.performIncrementalSync();
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(res.isSuccess ? 'Sync complete' : 'Sync failed')),
                                );
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Sync error: $e')),
                                );
                              } finally {
                                if (mounted) setState(() => _isLoading = false);
                              }
                            },
                    ),
                    help: 'Uploads recent local changes and pulls the latest backup to merge.',
                  ),
                  _ActionWithHelp(
                    button: _ActionButton(
                      icon: Icons.cloud_upload,
                      label: 'Create Backup',
                      onPressed: _isLoading
                          ? null
                          : () async {
                              setState(() => _isLoading = true);
                              try {
                                final res = await sync.createBackup();
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(res.isSuccess ? 'Backup complete' : 'Backup failed')),
                                );
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Backup error: $e')),
                                );
                              } finally {
                                if (mounted) setState(() => _isLoading = false);
                              }
                            },
                    ),
                    help: 'Creates a full ${_settings.encryptBackups ? 'encrypted' : 'plain JSON'} snapshot to Google Drive.',
                  ),
                  _ActionWithHelp(
                    button: _ActionButton(
                      icon: Icons.restore,
                      label: 'Restore Latest Backup',
                      onPressed: _isLoading
                          ? null
                          : () async {
                              setState(() => _isLoading = true);
                              try {
                                final res = await sync.restoreLatestBackup();
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(res.isSuccess ? 'Restore complete' : 'Restore failed')),
                                );
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Restore error: $e')),
                                );
                              } finally {
                                if (mounted) setState(() => _isLoading = false);
                              }
                            },
                    ),
                    help: 'Downloads and imports the most recent backup file from Drive.',
                  ),
                ];

                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: items[0]),
                      const SizedBox(width: 12),
                      Expanded(child: items[1]),
                      const SizedBox(width: 12),
                      Expanded(child: items[2]),
                    ],
                  );
                }
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: items,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackupSection() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Backup Settings',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('Backup Frequency'),
              subtitle: Text(_getFrequencyText(_settings.backupFrequencyMinutes)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showFrequencyDialog,
            ),
            const Divider(),
            ListTile(
              title: const Text('Backup Retention'),
              subtitle: Text('Keep backups for ${_settings.maxBackupRetentionDays} days'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showRetentionDialog,
            ),
            if (widget.onManageBackups != null) ...[
              const Divider(),
              ListTile(
                title: const Text('Manage Backups'),
                subtitle: const Text('View and manage backup files'),
                trailing: const Icon(Icons.chevron_right),
                onTap: widget.onManageBackups,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStorageSection() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Google Drive Storage',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (widget.onRefreshStorage != null)
                  TextButton.icon(
                    onPressed: _isLoading ? null : _refreshStorage,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Refresh'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (widget.storageInfo != null) ...[
              _buildStorageInfo(widget.storageInfo!),
            ] else ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Storage information not available'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStorageInfo(DriveStorageInfo info) {
    return Column(
      children: [
        // Overall storage usage
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Storage',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: info.usagePercentage / 100,
                    backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${info.formattedUsedSize} of ${info.formattedTotalSize} used (${info.usagePercentage.toStringAsFixed(1)}%)',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // DocLedger specific usage
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                Icons.folder_special,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DocLedger Backups',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '${info.formattedDocLedgerSize} • ${info.backupFileCount} files',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Storage details
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildStorageDetail('Available', info.formattedAvailableSize, Colors.green),
            _buildStorageDetail('Used', info.formattedUsedSize, Colors.orange),
            _buildStorageDetail('Total', info.formattedTotalSize, Colors.blue),
          ],
        ),
        if (info.lastUpdated != null) ...[
          const SizedBox(height: 8),
          Text(
            'Last updated: ${_formatDateTime(info.lastUpdated!)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStorageDetail(String label, String value, Color color) {
    return Column(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildAdvancedSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Advanced Settings',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Conflict Resolution'),
              subtitle: const Text('Automatically resolve data conflicts'),
              value: _settings.enableConflictResolution,
              onChanged: (value) {
                setState(() {
                  _settings = _settings.copyWith(enableConflictResolution: value);
                });
                widget.onSettingsChanged?.call(_settings);
              },
            ),
            ListTile(
              title: const Text('Conflict Strategy'),
              subtitle: Text(_getConflictStrategyText(_settings.conflictResolutionStrategy)),
              trailing: const Icon(Icons.chevron_right),
              enabled: _settings.enableConflictResolution,
              onTap: _settings.enableConflictResolution ? _showConflictStrategyDialog : null,
            ),
            if (widget.onViewConflicts != null) ...[
              const Divider(),
              ListTile(
                title: const Text('View Conflicts'),
                subtitle: const Text('Review unresolved data conflicts'),
                trailing: const Icon(Icons.chevron_right),
                onTap: widget.onViewConflicts,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _getFrequencyText(int minutes) {
    if (minutes < 60) {
      return '$minutes minutes';
    } else if (minutes < 1440) {
      final hours = minutes ~/ 60;
      return '$hours ${hours == 1 ? 'hour' : 'hours'}';
    } else {
      final days = minutes ~/ 1440;
      return '$days ${days == 1 ? 'day' : 'days'}';
    }
  }

  String _getConflictStrategyText(String strategy) {
    switch (strategy) {
      case 'last_write_wins':
        return 'Last write wins';
      case 'manual_review':
        return 'Manual review required';
      case 'merge_when_possible':
        return 'Merge when possible';
      default:
        return 'Unknown strategy';
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }

  void _showFrequencyDialog() {
    final frequencies = [
      (5, '5 minutes'),
      (15, '15 minutes'),
      (30, '30 minutes'),
      (60, '1 hour'),
      (120, '2 hours'),
      (360, '6 hours'),
      (720, '12 hours'),
      (1440, '1 day'),
    ];

    showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        title: const Text('Backup Frequency'),
        content: SizedBox(
          width: 520,
          height: 360,
          child: ListView(
            shrinkWrap: true,
            children: frequencies.map((freq) {
              return RadioListTile<int>(
                title: Text(freq.$2),
                value: freq.$1,
                groupValue: _settings.backupFrequencyMinutes,
                onChanged: (value) {
                  Navigator.of(context).pop(value);
                },
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ).then((value) {
      if (value != null) {
        setState(() {
          _settings = _settings.copyWith(backupFrequencyMinutes: value);
        });
        widget.onSettingsChanged?.call(_settings);
      }
    });
  }

  void _showRetentionDialog() {
    final retentions = [
      (7, '1 week'),
      (14, '2 weeks'),
      (30, '1 month'),
      (60, '2 months'),
      (90, '3 months'),
      (180, '6 months'),
      (365, '1 year'),
    ];

    showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        title: const Text('Backup Retention'),
        content: SizedBox(
          width: 520,
          height: 360,
          child: ListView(
            shrinkWrap: true,
            children: retentions.map((retention) {
              return RadioListTile<int>(
                title: Text(retention.$2),
                value: retention.$1,
                groupValue: _settings.maxBackupRetentionDays,
                onChanged: (value) {
                  Navigator.of(context).pop(value);
                },
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ).then((value) {
      if (value != null) {
        setState(() {
          _settings = _settings.copyWith(maxBackupRetentionDays: value);
        });
        widget.onSettingsChanged?.call(_settings);
      }
    });
  }

  void _showConflictStrategyDialog() {
    final strategies = [
      ('last_write_wins', 'Last Write Wins', 'Most recent change takes precedence'),
      ('manual_review', 'Manual Review', 'Require manual resolution for conflicts'),
      ('merge_when_possible', 'Merge When Possible', 'Automatically merge non-conflicting changes'),
    ];

    showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        title: const Text('Conflict Resolution Strategy'),
        content: SizedBox(
          width: 520,
          height: 400,
          child: ListView(
            shrinkWrap: true,
            children: strategies.map((strategy) {
              return RadioListTile<String>(
                title: Text(strategy.$2),
                subtitle: Text(strategy.$3),
                value: strategy.$1,
                groupValue: _settings.conflictResolutionStrategy,
                onChanged: (value) {
                  Navigator.of(context).pop(value);
                },
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ).then((value) {
      if (value != null) {
        setState(() {
          _settings = _settings.copyWith(conflictResolutionStrategy: value);
        });
        widget.onSettingsChanged?.call(_settings);
      }
    });
  }

  void _refreshStorage() async {
    if (widget.onRefreshStorage == null) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      await widget.onRefreshStorage!.call();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.onPressed,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      side: BorderSide(color: scheme.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      foregroundColor: scheme.onSurface,
      backgroundColor: primary ? scheme.primary : scheme.surface,
    );

    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: primary ? scheme.onPrimary : scheme.primary),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: primary ? scheme.onPrimary : scheme.onSurface,
          ),
        ),
      ],
    );

    return OutlinedButton(onPressed: onPressed, style: style, child: child);
  }
}

class _ActionWithHelp extends StatelessWidget {
  final Widget button;
  final String help;
  const _ActionWithHelp({required this.button, required this.help});

  @override
  Widget build(BuildContext context) {
    final helpStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        button,
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Text(help, style: helpStyle),
        ),
      ],
    );
  }
}