import 'package:flutter/material.dart';
import 'compact_date_picker.dart' as date_only; // kept for date utilities only

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
  late DateTime _visibleMonth; // first day of visible month
  late bool _isAm;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateUtils.dateOnly(widget.initial);
    _selectedTime = TimeOfDay(hour: widget.initial.hour, minute: widget.initial.minute);
    _visibleMonth = DateTime(widget.initial.year, widget.initial.month, 1);
    _isAm = _selectedTime.hour < 12;
  }

  void _prevMonth() {
    final prev = DateTime(_visibleMonth.year, _visibleMonth.month - 1, 1);
    if (!prev.isBefore(DateTime(widget.firstDate.year, widget.firstDate.month, 1))) {
      setState(() => _visibleMonth = prev);
    }
  }

  void _nextMonth() {
    final next = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 1);
    if (!next.isAfter(DateTime(widget.lastDate.year, widget.lastDate.month, 1))) {
      setState(() => _visibleMonth = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560, minWidth: 320),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              // Inline calendar (no nested popups)
              Row(
                children: [
                  IconButton(icon: const Icon(Icons.chevron_left), onPressed: _prevMonth),
                  Text('${_monthName(_visibleMonth.month)} ${_visibleMonth.year}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  IconButton(icon: const Icon(Icons.chevron_right), onPressed: _nextMonth),
                  const Spacer(),
                  Icon(Icons.calendar_month, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(_fmtDate(_selectedDate)),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  _WdDT('M'), _WdDT('T'), _WdDT('W'), _WdDT('T'), _WdDT('F'), _WdDT('S'), _WdDT('S'),
                ],
              ),
              const SizedBox(height: 4),
              _MonthGridDT(
                month: _visibleMonth,
                firstDate: widget.firstDate,
                lastDate: widget.lastDate,
                selected: _selectedDate,
                onSelect: (d) => setState(() => _selectedDate = d),
              ),
              const SizedBox(height: 14),
              // Time controls (inline)
              Row(
                children: [
                  const Icon(Icons.schedule, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      decoration: const InputDecoration(labelText: 'Hour'),
                      value: _to12h(_selectedTime.hour),
                      onChanged: (v) {
                        if (v == null) return;
                        final h24 = _from12h(v, _isAm);
                        setState(() => _selectedTime = TimeOfDay(hour: h24, minute: _selectedTime.minute));
                      },
                      items: List.generate(12, (i) => i + 1)
                          .map((h) => DropdownMenuItem(value: h, child: Text(h.toString().padLeft(2, '0'))))
                          .toList(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      decoration: const InputDecoration(labelText: 'Minute'),
                      value: (_selectedTime.minute ~/ 5) * 5,
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _selectedTime = TimeOfDay(hour: _selectedTime.hour, minute: v));
                      },
                      items: List.generate(12, (i) => i * 5)
                          .map((m) => DropdownMenuItem(value: m, child: Text(m.toString().padLeft(2, '0'))))
                          .toList(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'AM', label: Text('AM')),
                      ButtonSegment(value: 'PM', label: Text('PM')),
                    ],
                    selected: {_isAm ? 'AM' : 'PM'},
                    onSelectionChanged: (s) {
                      final pick = s.first == 'AM';
                      if (pick == _isAm) return;
                      setState(() {
                        _isAm = pick;
                        final h24 = _from12h(_to12h(_selectedTime.hour), _isAm);
                        _selectedTime = TimeOfDay(hour: h24, minute: _selectedTime.minute);
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
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

  String _monthName(int m) {
    const a = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return a[(m - 1).clamp(0, 11)];
  }

  int _to12h(int h24) {
    final h = h24 % 12;
    return h == 0 ? 12 : h;
  }

  int _from12h(int h12, bool am) {
    final base = h12 % 12;
    return am ? base : base + 12;
  }
}

class _WdDT extends StatelessWidget {
  final String t;
  const _WdDT(this.t);
  @override
  Widget build(BuildContext context) {
    return Expanded(child: Center(child: Text(t, style: const TextStyle(fontSize: 11, color: Colors.grey))));
  }
}

class _MonthGridDT extends StatelessWidget {
  final DateTime month; // first day of month
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;
  const _MonthGridDT({
    required this.month,
    required this.firstDate,
    required this.lastDate,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final firstWeekday = DateTime(month.year, month.month, 1).weekday;
    final leadingBlanks = (firstWeekday - 1) % 7;
    final totalCells = leadingBlanks + daysInMonth;
    final rows = (totalCells / 7).ceil();

    bool isDisabled(DateTime d) => d.isBefore(firstDate) || d.isAfter(lastDate);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(rows, (row) {
        return Row(
          children: List.generate(7, (col) {
            final cellIndex = row * 7 + col;
            final dayNum = cellIndex - leadingBlanks + 1;
            if (dayNum < 1 || dayNum > daysInMonth) {
              return const _CellDT.blank();
            }
            final d = DateTime(month.year, month.month, dayNum);
            final disabled = isDisabled(d);
            final selectedFlag = DateUtils.isSameDay(d, selected);
            return _CellDT(
              date: d,
              disabled: disabled,
              selected: selectedFlag,
              onTap: () => !disabled ? onSelect(d) : null,
            );
          }),
        );
      }),
    );
  }
}

class _CellDT extends StatelessWidget {
  final DateTime? date;
  final bool disabled;
  final bool selected;
  final VoidCallback? onTap;
  const _CellDT({this.date, this.disabled = false, this.selected = false, this.onTap});
  const _CellDT.blank()
      : date = null,
        disabled = true,
        selected = false,
        onTap = null;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final bgColor = selected ? color.primary.withValues(alpha: 0.18) : Colors.transparent;
    final textStyle = TextStyle(
      color: disabled ? Colors.grey.withOpacity(0.5) : null,
      fontWeight: selected ? FontWeight.bold : FontWeight.w500,
    );

    final box = Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: SizedBox(
        width: 40,
        height: 36,
        child: Center(child: Text(date != null ? '${date!.day}' : '', style: textStyle)),
      ),
    );

    if (onTap == null) return Expanded(child: box);
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: box,
      ),
    );
  }
}
