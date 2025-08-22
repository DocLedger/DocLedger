import 'package:flutter/material.dart';
import 'compact_date_picker.dart' as date_only;

/// Shows a compact combined date & time picker dialog.
/// Returns the selected DateTime when Apply is pressed, or null on Cancel/close.
Future<DateTime?> showCompactDateTimePicker({
  required BuildContext context,
  required DateTime initialDateTime,
  required DateTime firstDate,
  required DateTime lastDate,
  String? title,
}) async {
  // Clamp initial date within range
  DateTime clampDate(DateTime d, DateTime min, DateTime max) {
    if (d.isBefore(min)) return min;
    if (d.isAfter(max)) return max;
    return d;
  }
  final init = clampDate(initialDateTime, firstDate, lastDate);
  return showDialog<DateTime>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _CompactDateTimeDialog(
      initial: init,
      firstDate: DateUtils.dateOnly(firstDate),
      lastDate: DateUtils.dateOnly(lastDate),
      title: title ?? 'Select date & time',
    ),
  );
}

class _CompactDateTimeDialog extends StatefulWidget {
  final DateTime initial;
  final DateTime firstDate;
  final DateTime lastDate;
  final String title;
  const _CompactDateTimeDialog({
    required this.initial,
    required this.firstDate,
    required this.lastDate,
    required this.title,
  });

  @override
  State<_CompactDateTimeDialog> createState() => _CompactDateTimeDialogState();
}

class _CompactDateTimeDialogState extends State<_CompactDateTimeDialog> {
  late DateTime _selectedDate; // date part only
  late TimeOfDay _selectedTime; // time part

  @override
  void initState() {
    super.initState();
    _selectedDate = DateUtils.dateOnly(widget.initial);
    _selectedTime = TimeOfDay(hour: widget.initial.hour, minute: widget.initial.minute);
  }

  Future<void> _pickDate() async {
    final d = await date_only.showCompactDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: widget.firstDate,
      lastDate: widget.lastDate,
      previewLength: 1,
      title: 'Select date',
    );
    if (d != null) setState(() => _selectedDate = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _selectedTime);
    if (t != null) setState(() => _selectedTime = t);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 520, minWidth: 320),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              // Date selector (opens compact date picker)
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_month),
                label: Text(_fmtDate(_selectedDate)),
              ),
              const SizedBox(height: 8),
              // Time selector (inline button, same visual weight as date)
              OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.schedule),
                label: Text(_fmtTime(context, _selectedTime)),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      final dt = DateTime(
                        _selectedDate.year,
                        _selectedDate.month,
                        _selectedDate.day,
                        _selectedTime.hour,
                        _selectedTime.minute,
                      );
                      Navigator.of(context).pop(dt);
                    },
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) {
    const a = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${a[d.month - 1]} ${d.day}, ${d.year}';
  }

  String _fmtTime(BuildContext ctx, TimeOfDay t) => MaterialLocalizations.of(ctx).formatTimeOfDay(t);
}
