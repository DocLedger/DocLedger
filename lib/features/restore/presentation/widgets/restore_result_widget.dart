import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/restore_models.dart';

/// Widget that displays the result of a restoration operation
class RestoreResultWidget extends StatelessWidget {
  final RestoreResult result;
  final VoidCallback? onContinue;
  final VoidCallback? onRetry;

  const RestoreResultWidget({
    super.key,
    required this.result,
    this.onContinue,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildResultIcon(context),
        const SizedBox(height: 32),
        _buildResultTitle(context),
        const SizedBox(height: 16),
        _buildResultSummary(context),
        const SizedBox(height: 32),
        if (result.success) _buildSuccessDetails(context),
        if (!result.success) _buildErrorDetails(context),
        const SizedBox(height: 48),
        _buildActionButtons(context),
      ],
    );
  }

  Widget _buildResultIcon(BuildContext context) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: result.success
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.errorContainer,
      ),
      child: Icon(
        result.success ? Icons.check_circle : Icons.error,
        size: 60,
        color: result.success
            ? Theme.of(context).colorScheme.onPrimaryContainer
            : Theme.of(context).colorScheme.onErrorContainer,
      ),
    );
  }

  Widget _buildResultTitle(BuildContext context) {
    return Text(
      result.success ? 'Restore Complete!' : 'Restore Failed',
      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: result.success
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.error,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildResultSummary(BuildContext context) {
    final summaryText = result.success
        ? 'Your data has been successfully restored from the backup.'
        : 'The restore operation failed. Please try again or contact support.';

    return Text(
      summaryText,
      style: Theme.of(context).textTheme.bodyLarge,
      textAlign: TextAlign.center,
    );
  }

  Widget _buildSuccessDetails(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Restore Summary',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildDetailRow(
              context,
              'Duration',
              result.formattedDuration,
              Icons.schedule,
            ),
            const SizedBox(height: 8),
            _buildDetailRow(
              context,
              'Records Restored',
              '${result.totalRestored}',
              Icons.storage,
            ),
            if (result.restoredCounts != null) ...[
              const SizedBox(height: 16),
              Text(
                'Restored by Type:',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              ...result.restoredCounts!.entries.map((entry) =>
                Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatTableName(entry.key),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      Text(
                        '${entry.value}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (result.metadata != null) ...[
              const SizedBox(height: 16),
              _buildMetadataSection(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorDetails(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  'Error Details',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              result.errorMessage ?? 'An unknown error occurred',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 16),
            _buildDetailRow(
              context,
              'Duration',
              result.formattedDuration,
              Icons.schedule,
              textColor: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    BuildContext context,
    String label,
    String value,
    IconData icon, {
    Color? textColor,
  }) {
    final color = textColor ?? Theme.of(context).colorScheme.onSurface;

    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: color,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildMetadataSection(BuildContext context) {
    final metadata = result.metadata!;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Additional Information:',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        if (metadata.containsKey('backup_timestamp'))
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Backup Date:'),
                Text(
                  _formatBackupTimestamp(metadata['backup_timestamp'] as String),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        if (metadata.containsKey('backup_device_id'))
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Source Device:'),
                Text(
                  _formatDeviceId(metadata['backup_device_id'] as String),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        if (metadata.containsKey('partial_restore') && metadata['partial_restore'] == true)
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 4),
            child: Row(
              children: [
                Icon(
                  Icons.warning,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 4),
                const Text('Partial restore completed'),
              ],
            ),
          ),
        if (metadata.containsKey('failed_tables'))
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Failed tables:'),
                ...((metadata['failed_tables'] as List).map((table) =>
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Text(
                      '• ${_formatTableName(table as String)}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                )),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    if (result.success) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: onContinue,
          icon: const Icon(Icons.arrow_forward),
          label: const Text('Continue to App'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onContinue,
            icon: const Icon(Icons.skip_next),
            label: const Text('Start Fresh Instead'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],
      );
    }
  }

  String _formatTableName(String tableName) {
    switch (tableName.toLowerCase()) {
      case 'patients':
        return 'Patients';
      case 'visits':
        return 'Visits';
      case 'payments':
        return 'Payments';
      default:
        return tableName.replaceAll('_', ' ').split(' ')
            .map((word) => word.isEmpty ? word : word[0].toUpperCase() + word.substring(1))
            .join(' ');
    }
  }

  String _formatBackupTimestamp(String timestamp) {
    try {
      final date = DateTime.parse(timestamp);
      return DateFormat('MMM dd, yyyy \'at\' HH:mm').format(date);
    } catch (e) {
      return timestamp;
    }
  }

  String _formatDeviceId(String deviceId) {
    // Show only first 8 characters for privacy
    if (deviceId.length > 8) {
      return '${deviceId.substring(0, 8)}...';
    }
    return deviceId;
  }
}