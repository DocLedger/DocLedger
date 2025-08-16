import 'package:flutter/material.dart';

import '../../../../core/data/models/data_models.dart';
// Sync visuals removed from main pages per product decision

/// Widget displaying a single patient in the list with sync indicators
/// 
/// This widget shows patient information along with sync status indicators
/// and conflict warnings when applicable.
class PatientListItem extends StatelessWidget {
  final Patient patient;
  final VoidCallback? onTap;
  final double? dueAmount;

  const PatientListItem({
    super.key,
    required this.patient,
    this.onTap,
    this.dueAmount,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: Text(
            patient.name.isNotEmpty ? patient.name[0].toUpperCase() : 'P',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          patient.name,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(patient.phone, style: const TextStyle(fontSize: 15)),
            if (patient.dateOfBirth != null)
              Text(
                'DOB: ${_formatDate(patient.dateOfBirth!)}',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
              ),
            // No sync/conflict indicators on list items
          ],
        ),
        trailing: _TrailingStatus(dueAmount: dueAmount),
        onTap: onTap,
      ),
    );
  }

  /// Formats a date for display
  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _TrailingStatus extends StatelessWidget {
  final double? dueAmount;
  const _TrailingStatus({this.dueAmount});

  @override
  Widget build(BuildContext context) {
    final due = (dueAmount ?? 0).toDouble();
    if (due <= 0) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.check_circle, color: Colors.green),
          SizedBox(width: 8),
          Icon(Icons.chevron_right),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.orange.withOpacity(0.3)),
          ),
          child: Text('Due Rs.${due.toStringAsFixed(0)}', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 8),
        const Icon(Icons.chevron_right),
      ],
    );
  }
}