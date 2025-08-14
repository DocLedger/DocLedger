import 'package:flutter/material.dart';

/// Widget that displays an offline indicator when network is unavailable
/// 
/// This widget shows a discrete banner at the top of screens when the
/// device is offline, informing users that sync operations are not available.
class OfflineIndicatorWidget extends StatelessWidget {
  final bool isOffline;
  final String? customMessage;

  const OfflineIndicatorWidget({
    super.key,
    required this.isOffline,
    this.customMessage,
  });

  @override
  Widget build(BuildContext context) {
    if (!isOffline) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orange[100],
        border: Border(
          bottom: BorderSide(
            color: Colors.orange[300]!,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cloud_off,
            size: 16,
            color: Colors.orange[700],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              customMessage ?? 'You are offline. Changes will sync when connection is restored.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget that shows sync conflicts requiring attention
/// 
/// This widget displays a warning banner when there are unresolved
/// sync conflicts that need user attention.
class ConflictIndicatorWidget extends StatelessWidget {
  final int conflictCount;
  final VoidCallback? onResolveConflicts;

  const ConflictIndicatorWidget({
    super.key,
    required this.conflictCount,
    this.onResolveConflicts,
  });

  @override
  Widget build(BuildContext context) {
    if (conflictCount == 0) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red[100],
        border: Border(
          bottom: BorderSide(
            color: Colors.red[300]!,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning,
            size: 16,
            color: Colors.red[700],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$conflictCount sync conflict${conflictCount > 1 ? 's' : ''} need${conflictCount == 1 ? 's' : ''} attention',
              style: TextStyle(
                fontSize: 12,
                color: Colors.red[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (onResolveConflicts != null)
            TextButton(
              onPressed: onResolveConflicts,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Resolve',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.red[700],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Widget that shows pending sync operations
/// 
/// This widget displays information about pending sync operations
/// and provides a way to trigger manual sync.
class PendingSyncIndicatorWidget extends StatelessWidget {
  final int pendingCount;
  final bool isSyncing;
  final VoidCallback? onManualSync;

  const PendingSyncIndicatorWidget({
    super.key,
    required this.pendingCount,
    this.isSyncing = false,
    this.onManualSync,
  });

  @override
  Widget build(BuildContext context) {
    if (pendingCount == 0 && !isSyncing) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        border: Border(
          bottom: BorderSide(
            color: Colors.blue[200]!,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          if (isSyncing)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[700]!),
              ),
            )
          else
            Icon(
              Icons.cloud_upload,
              size: 16,
              color: Colors.blue[700],
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isSyncing
                  ? 'Syncing changes...'
                  : '$pendingCount change${pendingCount > 1 ? 's' : ''} pending sync',
              style: TextStyle(
                fontSize: 12,
                color: Colors.blue[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (!isSyncing && onManualSync != null)
            TextButton(
              onPressed: onManualSync,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Sync Now',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.blue[700],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}