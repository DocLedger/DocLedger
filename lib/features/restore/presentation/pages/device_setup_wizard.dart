import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/backup_selection_widget.dart';
import '../widgets/restore_progress_widget.dart';
import '../widgets/restore_result_widget.dart';
import '../../models/restore_models.dart';
import '../../services/restore_service.dart';

/// Device setup wizard that guides users through the restoration process
class DeviceSetupWizard extends StatefulWidget {
  final RestoreService restoreService;
  final VoidCallback? onSetupComplete;
  final VoidCallback? onSkipRestore;

  const DeviceSetupWizard({
    super.key,
    required this.restoreService,
    this.onSetupComplete,
    this.onSkipRestore,
  });

  @override
  State<DeviceSetupWizard> createState() => _DeviceSetupWizardState();
}

class _DeviceSetupWizardState extends State<DeviceSetupWizard> {
  RestoreState _currentState = RestoreState.initial();
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeWizard();
  }

  @override
  void dispose() {
    widget.restoreService.dispose();
    super.dispose();
  }

  Future<void> _initializeWizard() async {
    // Listen to restore state changes
    widget.restoreService.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          _currentState = state;
        });
      }
    });

    // Start the setup process
    try {
      await widget.restoreService.startDeviceSetupWizard();
    } catch (e) {
      if (mounted) {
        setState(() {
          _currentState = RestoreState.error('Failed to start setup: ${e.toString()}');
        });
      }
    }

    setState(() {
      _isInitialized = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Setup DocLedger'),
        automaticallyImplyLeading: false,
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      body: SafeArea(
        child: _isInitialized ? _buildWizardContent() : _buildLoadingContent(),
      ),
    );
  }

  Widget _buildLoadingContent() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Initializing setup wizard...'),
        ],
      ),
    );
  }

  Widget _buildWizardContent() {
    switch (_currentState.status) {
      case RestoreStatus.notStarted:
        return _buildWelcomeScreen();
      
      case RestoreStatus.selectingBackup:
        return _buildBackupSelectionScreen();
      
      case RestoreStatus.validatingBackup:
      case RestoreStatus.downloading:
      case RestoreStatus.decrypting:
      case RestoreStatus.importing:
        return _buildProgressScreen();
      
      case RestoreStatus.completed:
        return _buildCompletionScreen();
      
      case RestoreStatus.error:
        return _buildErrorScreen();
      
      case RestoreStatus.cancelled:
        return _buildCancelledScreen();
    }
  }

  Widget _buildWelcomeScreen() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.cloud_download,
            size: 80,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 32),
          Text(
            'Welcome to DocLedger',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Would you like to restore your data from a previous backup?',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          ElevatedButton.icon(
            onPressed: _startRestore,
            icon: const Icon(Icons.restore),
            label: const Text('Restore from Backup'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _skipRestore,
            icon: const Icon(Icons.skip_next),
            label: const Text('Start Fresh'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackupSelectionScreen() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
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
                        'Select Backup to Restore',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose which backup you want to restore from. The most recent backup is recommended.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: BackupSelectionWidget(
              backups: _currentState.availableBackups,
              selectedBackup: _currentState.selectedBackup,
              onBackupSelected: _selectBackup,
              onRestoreSelected: _restoreFromSelectedBackup,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _skipRestore,
                  child: const Text('Skip Restore'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: _currentState.selectedBackup != null ? _restoreFromSelectedBackup : null,
                  child: const Text('Restore'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressScreen() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.restore,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Restoring Data',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please wait while we restore your data from the backup. This may take a few minutes.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: RestoreProgressWidget(
              state: _currentState,
              onCancel: _currentState.canCancel ? _cancelRestore : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletionScreen() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Expanded(
            child: RestoreResultWidget(
              result: _currentState.result!,
              onContinue: _completeSetup,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorScreen() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.error_outline,
            size: 80,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 32),
          Text(
            'Restore Failed',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.error,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                _currentState.errorMessage ?? 'An unknown error occurred',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _retryRestore,
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _skipRestore,
            icon: const Icon(Icons.skip_next),
            label: const Text('Start Fresh Instead'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCancelledScreen() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.cancel_outlined,
            size: 80,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 32),
          Text(
            'Restore Cancelled',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'The restore operation was cancelled. You can try again or start fresh.',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          ElevatedButton.icon(
            onPressed: _retryRestore,
            icon: const Icon(Icons.restore),
            label: const Text('Try Restore Again'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _skipRestore,
            icon: const Icon(Icons.skip_next),
            label: const Text('Start Fresh'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  // Event handlers

  void _startRestore() {
    HapticFeedback.lightImpact();
    widget.restoreService.startDeviceSetupWizard();
  }

  void _skipRestore() {
    HapticFeedback.lightImpact();
    widget.onSkipRestore?.call();
  }

  void _selectBackup(RestoreBackupInfo backup) {
    HapticFeedback.selectionClick();
    widget.restoreService.selectBackup(backup);
  }

  void _restoreFromSelectedBackup() {
    if (_currentState.selectedBackup != null) {
      HapticFeedback.lightImpact();
      widget.restoreService.restoreFromBackup(_currentState.selectedBackup!.id);
    }
  }

  void _cancelRestore() {
    HapticFeedback.lightImpact();
    widget.restoreService.cancelRestore();
  }

  void _retryRestore() {
    HapticFeedback.lightImpact();
    setState(() {
      _currentState = RestoreState.initial();
    });
    widget.restoreService.startDeviceSetupWizard();
  }

  void _completeSetup() {
    HapticFeedback.lightImpact();
    widget.onSetupComplete?.call();
  }
}