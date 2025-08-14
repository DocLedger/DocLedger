import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/restore_models.dart';

/// Widget for selecting a backup file for restoration
class BackupSelectionWidget extends StatelessWidget {
  final List<RestoreBackupInfo> backups;
  final RestoreBackupInfo? selectedBackup;
  final ValueChanged<RestoreBackupInfo> onBackupSelected;
  final VoidCallback? onRestoreSelected;

  const BackupSelectionWidget({
    super.key,
    required this.backups,
    this.selectedBackup,
    required this.onBackupSelected,
    this.onRestoreSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (backups.isEmpty) {
      return _buildEmptyState(context);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context),
        const SizedBox(height: 16),
        Expanded(
          child: _buildBackupList(context),
        ),
      ],
    );
  }

  Widget _buildHeader(Context context) {
    final validBackups = backups.where((backup) => backup.isValid).length;
    final totalBackups = backups.length;

    return Row(
      children: [
        Icon(
          Icons.backup,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Available Backups',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '$validBackups valid of $totalBackups total',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (selectedBackup != null)
          Chip(
            label: const Text('Selected'),
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            labelStyle: TextStyle(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
      ],
    );
  }

  Widget _buildBackupList(BuildContext context) {
    return ListView.separated(
      itemCount: backups.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final backup = backups[index];
        return _buildBackupCard(context, backup);
      },
    );
  }

  Widget _buildBackupCard(BuildContext context, RestoreBackupInfo backup) {
    final isSelected = selectedBackup?.id == backup.id;
    final dateFormat = DateFormat('MMM dd, yyyy \'at\' HH:mm');

    return Card(
      elevation: isSelected ? 4 : 1,
      color: isSelected 
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      child: InkWell(
        onTap: backup.isValid ? () => onBackupSelected(backup) : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    backup.isValid ? Icons.check_circle : Icons.error,
                    color: backup.isValid 
                        ? (isSelected 
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : Theme.of(context).colorScheme.primary)
                        : Theme.of(context).colorScheme.error,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _formatBackupName(backup.name),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isSelected 
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : null,
                      ),
                    ),
                  ),
                  if (isSelected)
                    Icon(
                      Icons.radio_button_checked,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    )
                  else
                    Icon(
                      Icons.radio_button_unchecked,
                      color: backup.isValid 
                          ? Theme.of(context).colorScheme.outline
                          : Theme.of(context).colorScheme.outlineVariant,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.schedule,
                    size: 16,
                    color: isSelected 
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    dateFormat.format(backup.createdTime),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isSelected 
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Icon(
                    Icons.storage,
                    size: 16,
                    color: isSelected 
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    backup.formattedSize,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isSelected 
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (backup.description != null) ...[
                const SizedBox(height: 8),
                Text(
                  backup.description!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isSelected 
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              if (!backup.isValid) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.warning,
                        size: 16,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          backup.validationError ?? 'Invalid backup',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (backup.isValid && index == 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.star,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSecondaryContainer,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Most Recent',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_off,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No Backups Found',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No backup files were found in your Google Drive.\nYou can start fresh or check your Google account.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Format backup name for display
  String _formatBackupName(String fileName) {
    // Remove file extension and clinic ID prefix for cleaner display
    String displayName = fileName;
    
    if (displayName.endsWith('.enc')) {
      displayName = displayName.substring(0, displayName.length - 4);
    }
    
    // Extract timestamp from filename if present
    final timestampRegex = RegExp(r'(\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2})');
    final match = timestampRegex.firstMatch(displayName);
    
    if (match != null) {
      final timestamp = match.group(1)!.replaceAll('-', ':');
      try {
        final date = DateTime.parse(timestamp);
        return 'Backup from ${DateFormat('MMM dd, yyyy').format(date)}';
      } catch (e) {
        // If parsing fails, return original name
      }
    }
    
    return displayName;
  }
}