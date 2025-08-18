import 'package:flutter/material.dart';
import '../../../../core/cloud/models/cloud_save_models.dart';

/// Widget that displays the current cloud save status with real-time updates
class SyncStatusWidget extends StatelessWidget {
  final CloudSaveState cloudSaveState;
  final VoidCallback? onManualSave;
  final VoidCallback? onSettings;
  final bool showSettings;
  final bool compact;

  const SyncStatusWidget({
    super.key,
    required this.cloudSaveState,
    this.onManualSave,
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
                      if (cloudSaveState.currentOperation != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          cloudSaveState.currentOperation!,
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
                    tooltip: 'Cloud Save Settings',
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (cloudSaveState.progress != null) ...[
              LinearProgressIndicator(
                value: cloudSaveState.progress,
                backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
              ),
              const SizedBox(height: 8),
              Text(
                '${(cloudSaveState.progress! * 100).toInt()}% complete',
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
                        'Last Save',
                        _formatLastSaveTime(),
                        Icons.cloud_upload,
                      ),
                    ],
                  ),
                ),
                if (_canTriggerManualSave())
                  ElevatedButton.icon(
                    onPressed: onManualSave,
                    icon: const Icon(Icons.cloud_upload, size: 18),
                    label: const Text('Save Now'),
                  ),
              ],
            ),
            if (cloudSaveState.errorMessage != null) ...[
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
                        cloudSaveState.errorMessage!,
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
        ],
      ),
    );
  }

  Widget _buildStatusIcon({double? size}) {
    final iconSize = size ?? 24.0;
    switch (cloudSaveState.status) {
      case CloudSaveStatus.idle:
        return Icon(
          Icons.cloud_done,
          color: Colors.green,
          size: iconSize,
        );
      case CloudSaveStatus.saving:
        return SizedBox(
          width: iconSize,
          height: iconSize,
          child: const CircularProgressIndicator(
            strokeWidth: 2,
          ),
        );
      case CloudSaveStatus.restoring:
        return SizedBox(
          width: iconSize,
          height: iconSize,
          child: const CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.orange,
          ),
        );
      case CloudSaveStatus.error:
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
    switch (cloudSaveState.status) {
      case CloudSaveStatus.idle:
        return cloudSaveState.statusMessage;
      case CloudSaveStatus.saving:
        return 'Saving...';
      case CloudSaveStatus.restoring:
        return 'Restoring...';
      case CloudSaveStatus.error:
        return 'Cloud save error';
    }
  }

  String _getCompactStatusText() {
    switch (cloudSaveState.status) {
      case CloudSaveStatus.idle:
        return cloudSaveState.statusMessage;
      case CloudSaveStatus.saving:
        return 'Saving';
      case CloudSaveStatus.restoring:
        return 'Restoring';
      case CloudSaveStatus.error:
        return 'Error';
    }
  }

  String _formatLastSaveTime() {
    final t = cloudSaveState.lastSaveTime;
    if (t == null) return 'Never';
    final now = DateTime.now();
    final difference = now.difference(t);
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }

  bool _canTriggerManualSave() {
    return onManualSave != null && cloudSaveState.status == CloudSaveStatus.idle;
  }
}


