import 'package:flutter/material.dart';

import '../../models/restore_models.dart';

/// Widget that displays the progress of a restoration operation
class RestoreProgressWidget extends StatelessWidget {
  final RestoreState state;
  final VoidCallback? onCancel;

  const RestoreProgressWidget({
    super.key,
    required this.state,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildProgressIndicator(context),
        const SizedBox(height: 32),
        _buildStatusText(context),
        const SizedBox(height: 16),
        _buildOperationText(context),
        if (state.progress != null) ...[
          const SizedBox(height: 24),
          _buildProgressBar(context),
        ],
        const SizedBox(height: 48),
        if (onCancel != null) _buildCancelButton(context),
      ],
    );
  }

  Widget _buildProgressIndicator(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 80,
            height: 80,
            child: CircularProgressIndicator(
              value: state.progress,
              strokeWidth: 6,
              backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          Icon(
            _getStatusIcon(),
            size: 32,
            color: Theme.of(context).colorScheme.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusText(BuildContext context) {
    return Text(
      _getStatusText(),
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.bold,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildOperationText(BuildContext context) {
    if (state.currentOperation == null) return const SizedBox.shrink();

    return Text(
      state.currentOperation!,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildProgressBar(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Progress',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              '${(state.progress! * 100).toInt()}%',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: state.progress,
          backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
          valueColor: AlwaysStoppedAnimation<Color>(
            Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildCancelButton(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onCancel,
      icon: const Icon(Icons.cancel),
      label: const Text('Cancel Restore'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.error,
        side: BorderSide(
          color: Theme.of(context).colorScheme.error,
        ),
      ),
    );
  }

  IconData _getStatusIcon() {
    switch (state.status) {
      case RestoreStatus.validatingBackup:
        return Icons.verified_user;
      case RestoreStatus.downloading:
        return Icons.cloud_download;
      case RestoreStatus.decrypting:
        return Icons.lock_open;
      case RestoreStatus.importing:
        return Icons.storage;
      default:
        return Icons.restore;
    }
  }

  String _getStatusText() {
    switch (state.status) {
      case RestoreStatus.validatingBackup:
        return 'Validating Backup';
      case RestoreStatus.downloading:
        return 'Downloading Backup';
      case RestoreStatus.decrypting:
        return 'Decrypting Data';
      case RestoreStatus.importing:
        return 'Importing Data';
      default:
        return 'Restoring Data';
    }
  }
}

/// Widget that shows detailed progress steps
class DetailedRestoreProgressWidget extends StatelessWidget {
  final RestoreState state;
  final VoidCallback? onCancel;

  const DetailedRestoreProgressWidget({
    super.key,
    required this.state,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final steps = _getProgressSteps();
    final currentStepIndex = _getCurrentStepIndex();

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: steps.length,
            itemBuilder: (context, index) {
              final step = steps[index];
              final isActive = index == currentStepIndex;
              final isCompleted = index < currentStepIndex;
              final isFuture = index > currentStepIndex;

              return _buildProgressStep(
                context,
                step,
                isActive: isActive,
                isCompleted: isCompleted,
                isFuture: isFuture,
                isLast: index == steps.length - 1,
              );
            },
          ),
        ),
        if (state.progress != null) ...[
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: state.progress,
            backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
          ),
          const SizedBox(height: 8),
          Text(
            '${(state.progress! * 100).toInt()}% Complete',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (onCancel != null) ...[
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: onCancel,
            icon: const Icon(Icons.cancel),
            label: const Text('Cancel'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildProgressStep(
    BuildContext context,
    _ProgressStep step, {
    required bool isActive,
    required bool isCompleted,
    required bool isFuture,
    required bool isLast,
  }) {
    Color iconColor;
    Color textColor;
    IconData icon;

    if (isCompleted) {
      iconColor = Theme.of(context).colorScheme.primary;
      textColor = Theme.of(context).colorScheme.onSurface;
      icon = Icons.check_circle;
    } else if (isActive) {
      iconColor = Theme.of(context).colorScheme.primary;
      textColor = Theme.of(context).colorScheme.onSurface;
      icon = step.icon;
    } else {
      iconColor = Theme.of(context).colorScheme.outline;
      textColor = Theme.of(context).colorScheme.onSurfaceVariant;
      icon = step.icon;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive || isCompleted
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.surfaceVariant,
              ),
              child: isActive && !isCompleted
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(iconColor),
                      ),
                    )
                  : Icon(icon, color: iconColor, size: 20),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 40,
                color: isCompleted
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outline,
              ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: textColor,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  step.description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (isActive && state.currentOperation != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    state.currentOperation!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<_ProgressStep> _getProgressSteps() {
    return [
      _ProgressStep(
        icon: Icons.verified_user,
        title: 'Validating Backup',
        description: 'Checking backup file integrity and compatibility',
      ),
      _ProgressStep(
        icon: Icons.cloud_download,
        title: 'Downloading Data',
        description: 'Downloading backup file from Google Drive',
      ),
      _ProgressStep(
        icon: Icons.lock_open,
        title: 'Decrypting Data',
        description: 'Decrypting backup data using your clinic key',
      ),
      _ProgressStep(
        icon: Icons.storage,
        title: 'Importing Data',
        description: 'Importing data into local database',
      ),
    ];
  }

  int _getCurrentStepIndex() {
    switch (state.status) {
      case RestoreStatus.validatingBackup:
        return 0;
      case RestoreStatus.downloading:
        return 1;
      case RestoreStatus.decrypting:
        return 2;
      case RestoreStatus.importing:
        return 3;
      default:
        return 0;
    }
  }
}

class _ProgressStep {
  final IconData icon;
  final String title;
  final String description;

  const _ProgressStep({
    required this.icon,
    required this.title,
    required this.description,
  });
}