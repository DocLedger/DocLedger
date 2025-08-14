import 'package:flutter/material.dart';
import '../../../../core/sync/models/sync_models.dart';

/// Widget that displays the current sync status with real-time updates
class SyncStatusWidget extends StatelessWidget {
  final SyncState syncState;
  final VoidCallback? onManualSync;
  final VoidCallback? onSettings;
  final bool showSettings;
  final bool compact;

  const SyncStatusWidget({
    super.key,
    required this.syncState,
    this.onManualSync,
    this.onSettings,
    this.showSettings = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _buildCompactView(context);
    }
    return _buildFullView(context);
  }

  Widget _buildFullView(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildStatusIcon(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getStatusText(),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (syncState.currentOperation != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          syncState.currentOperation!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (showSettings && onSettings != null)
                  IconButton(
                    icon: const Icon(Icons.settings),
                    onPressed: onSettings,
                    tooltip: 'Sync Settings',
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (syncState.progress != null) ...[
              LinearProgressIndicator(
                value: syncState.progress,
                backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
              ),
              const SizedBox(height: 8),
              Text(
                '${(syncState.progress! * 100).toInt()}% complete',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoRow(
                        context,
                        'Last Sync',
                        _formatLastSyncTime(),
                        Icons.sync,
                      ),
                      const SizedBox(height: 4),
                      _buildInfoRow(
                        context,
                        'Last Backup',
                        _formatLastBackupTime(),
                        Icons.backup,
                      ),
                      if (syncState.pendingChanges > 0) ...[
                        const SizedBox(height: 4),
                        _buildInfoRow(
                          context,
                          'Pending Changes',
                          '${syncState.pendingChanges}',
                          Icons.pending_actions,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ],
                      if (syncState.conflicts.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        _buildInfoRow(
                          context,
                          'Conflicts',
                          '${syncState.conflicts.length}',
                          Icons.warning,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ],
                    ],
                  ),
                ),
                if (_canTriggerManualSync())
                  ElevatedButton.icon(
                    onPressed: onManualSync,
                    icon: const Icon(Icons.sync, size: 18),
                    label: const Text('Sync Now'),
                  ),
              ],
            ),
            if (syncState.errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        syncState.errorMessage!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCompactView(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildStatusIcon(size: 16),
          const SizedBox(width: 8),
          Text(
            _getCompactStatusText(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          if (syncState.pendingChanges > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${syncState.pendingChanges}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusIcon({double? size}) {
    final iconSize = size ?? 24.0;
    
    switch (syncState.status) {
      case SyncStatus.idle:
        return Icon(
          Icons.cloud_done,
          color: Colors.green,
          size: iconSize,
        );
      case SyncStatus.syncing:
        return SizedBox(
          width: iconSize,
          height: iconSize,
          child: const CircularProgressIndicator(
            strokeWidth: 2,
          ),
        );
      case SyncStatus.backingUp:
        return SizedBox(
          width: iconSize,
          height: iconSize,
          child: const CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.blue,
          ),
        );
      case SyncStatus.restoring:
        return SizedBox(
          width: iconSize,
          height: iconSize,
          child: const CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.orange,
          ),
        );
      case SyncStatus.error:
        return Icon(
          Icons.cloud_off,
          color: Colors.red,
          size: iconSize,
        );
    }
  }

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value,
    IconData icon, {
    Color? color,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }

  String _getStatusText() {
    switch (syncState.status) {
      case SyncStatus.idle:
        if (syncState.pendingChanges > 0) {
          return 'Ready to sync';
        }
        return 'Up to date';
      case SyncStatus.syncing:
        return 'Syncing...';
      case SyncStatus.backingUp:
        return 'Backing up...';
      case SyncStatus.restoring:
        return 'Restoring...';
      case SyncStatus.error:
        return 'Sync error';
    }
  }

  String _getCompactStatusText() {
    switch (syncState.status) {
      case SyncStatus.idle:
        if (syncState.pendingChanges > 0) {
          return 'Sync pending';
        }
        return 'Synced';
      case SyncStatus.syncing:
        return 'Syncing';
      case SyncStatus.backingUp:
        return 'Backing up';
      case SyncStatus.restoring:
        return 'Restoring';
      case SyncStatus.error:
        return 'Error';
    }
  }

  String _formatLastSyncTime() {
    if (syncState.lastSyncTime == null) {
      return 'Never';
    }
    
    final now = DateTime.now();
    final difference = now.difference(syncState.lastSyncTime!);
    
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  String _formatLastBackupTime() {
    if (syncState.lastBackupTime == null) {
      return 'Never';
    }
    
    final now = DateTime.now();
    final difference = now.difference(syncState.lastBackupTime!);
    
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  bool _canTriggerManualSync() {
    return onManualSync != null && 
           syncState.status == SyncStatus.idle &&
           syncState.pendingChanges > 0;
  }
}