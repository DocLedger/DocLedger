import 'package:flutter/material.dart';

/// Shows a compact date picker dialog with optional N-day range preview highlight.
/// Returns the selected start date when Apply is pressed, or null on Cancel/close.
Future<DateTime?> showCompactDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  int previewLength = 1,
  String? title,
}) {
  assert(!lastDate.isBefore(firstDate), 'lastDate must be on/after firstDate');
  DateTime clampDate(DateTime d, DateTime min, DateTime max) {
    if (d.isBefore(min)) return min;
    if (d.isAfter(max)) return max;
    return d;
  }
  final init = DateUtils.dateOnly(clampDate(initialDate, firstDate, lastDate));
  return showDialog<DateTime>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _CompactDatePickerDialog(
      initial: init,
      firstDate: DateUtils.dateOnly(firstDate),
      lastDate: DateUtils.dateOnly(lastDate),
      previewLength: previewLength.clamp(1, 3650),
      title: title ?? 'Select date',
    ),
  );
}

class _CompactDatePickerDialog extends StatefulWidget {
  final DateTime initial;
  final DateTime firstDate;
  final DateTime lastDate;
  final int previewLength;
  final String title;
  const _CompactDatePickerDialog({
    required this.initial,
    required this.firstDate,
    required this.lastDate,
    required this.previewLength,
    required this.title,
  });

  @override
  State<_CompactDatePickerDialog> createState() => _CompactDatePickerDialogState();
}

class _CompactDatePickerDialogState extends State<_CompactDatePickerDialog> {
  late DateTime _visibleMonth; // first day of month
  late DateTime _selected; // start date

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
    _visibleMonth = DateTime(widget.initial.year, widget.initial.month, 1);
  }

  DateTime get _previewEnd {
    final end = _selected.add(Duration(days: widget.previewLength - 1));
    final clamped = end.isAfter(widget.lastDate) ? widget.lastDate : end;
    return DateUtils.dateOnly(clamped);
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
    final color = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360, maxHeight: 480, minWidth: 320),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  Expanded(
                    child: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: _prevMonth,
                  ),
                  Text('${_monthName(_visibleMonth.month)} ${_visibleMonth.year}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _nextMonth,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Weekday labels
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  _Wd('M'), _Wd('T'), _Wd('W'), _Wd('T'), _Wd('F'), _Wd('S'), _Wd('S'),
                ],
              ),
              const SizedBox(height: 6),
              // Calendar grid
              _MonthGrid(
                month: _visibleMonth,
                firstDate: widget.firstDate,
                lastDate: widget.lastDate,
                selectedStart: _selected,
                selectedEnd: _previewEnd,
                onSelect: (d) => setState(() => _selected = d),
              ),
              const SizedBox(height: 8),
              if (widget.previewLength > 1)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Selected: ${_fmt(_selected)} – ${_fmt(_previewEnd)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
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
                    onPressed: () => Navigator.of(context).pop(_selected),
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

  String _monthName(int m) {
    const a = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return a[(m - 1).clamp(0, 11)];
  }

  String _fmt(DateTime d) => '${_monthName(d.month)} ${d.day}';
}

class _Wd extends StatelessWidget {
  final String t;
  const _Wd(this.t);
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(child: Text(t, style: const TextStyle(fontSize: 11, color: Colors.grey))),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  final DateTime month; // first day of month
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime selectedStart;
  final DateTime selectedEnd;
  final ValueChanged<DateTime> onSelect;
  const _MonthGrid({
    required this.month,
    required this.firstDate,
    required this.lastDate,
    required this.selectedStart,
    required this.selectedEnd,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final firstWeekday = DateTime(month.year, month.month, 1).weekday; // 1=Mon..7=Sun
    final leadingBlanks = (firstWeekday - 1) % 7; // number of blanks before day 1

    final totalCells = leadingBlanks + daysInMonth;
    final rows = (totalCells / 7).ceil();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(rows, (row) {
        return Row(
          children: List.generate(7, (col) {
            final cellIndex = row * 7 + col;
            final dayNum = cellIndex - leadingBlanks + 1;
            if (dayNum < 1 || dayNum > daysInMonth) {
              return const _Cell.blank();
            }
            final date = DateTime(month.year, month.month, dayNum);
            final disabled = date.isBefore(firstDate) || date.isAfter(lastDate);
            final inRange = !disabled && !date.isBefore(selectedStart) && !date.isAfter(selectedEnd);
            final isStart = DateUtils.isSameDay(date, selectedStart);
            final isEnd = DateUtils.isSameDay(date, selectedEnd);
            return _Cell(
              date: date,
              disabled: disabled,
              inRange: inRange,
              isStart: isStart,
              isEnd: isEnd,
              onTap: () => !disabled ? onSelect(date) : null,
            );
          }),
        );
      }),
    );
  }
}

class _Cell extends StatelessWidget {
  final DateTime? date;
  final bool disabled;
  final bool inRange;
  final bool isStart;
  final bool isEnd;
  final VoidCallback? onTap;
  const _Cell({
    this.date,
    this.disabled = false,
    this.inRange = false,
    this.isStart = false,
    this.isEnd = false,
    this.onTap,
  });
  const _Cell.blank()
      : date = null,
        disabled = true,
        inRange = false,
        isStart = false,
        isEnd = false,
        onTap = null;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final txtStyle = TextStyle(
      color: disabled ? Colors.grey.withOpacity(0.5) : null,
      fontWeight: isStart || isEnd ? FontWeight.bold : FontWeight.w500,
    );

    final bgColor = inRange ? color.primary.withValues(alpha: 0.12) : Colors.transparent;
    BorderRadius? radius;
    if (isStart && isEnd) {
      radius = BorderRadius.circular(10);
    } else if (isStart) {
      radius = const BorderRadius.only(topLeft: Radius.circular(10), bottomLeft: Radius.circular(10));
    } else if (isEnd) {
      radius = const BorderRadius.only(topRight: Radius.circular(10), bottomRight: Radius.circular(10));
    }

    final child = SizedBox(
      width: 40,
      height: 36,
      child: Center(
        child: Text(date != null ? '${date!.day}' : '' , style: txtStyle),
      ),
    );

    Widget box = Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(color: bgColor, borderRadius: radius),
      child: child,
    );

    if (onTap == null) return Expanded(child: box);
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: box,
      ),
    );
  }
}
