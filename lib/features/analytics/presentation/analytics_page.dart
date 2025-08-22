import 'package:flutter/material.dart';
import '../../../core/widgets/compact_date_picker.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/data/services/database_service.dart';

class AnalyticsPage extends StatefulWidget {
  static const String routeName = '/analytics';
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

enum _Period { d1, d7, d30 }

class _AnalyticsPageState extends State<AnalyticsPage> {
  final DatabaseService _db = serviceLocator.get<DatabaseService>();

  _Period _period = _Period.d1;
  bool _loading = false;

  // KPIs
  int _visitsInRange = 0;
  double _collectedInRange = 0;
  double _billedInRange = 0;
  double get _outstandingInRange => (_billedInRange - _collectedInRange).clamp(0, double.infinity);

  // Trends per day (kept simple)
  late List<DateTime> _days; // ascending
  List<int> _visitsSeries = const [];
  List<double> _collectedSeries = const [];
  DateTime? _anchorStart; // user-picked start date

  @override
  void initState() {
    super.initState();
    _computeDays();
    _load();
  }

  void _computeDays() {
    final today = DateUtils.dateOnly(DateTime.now());
    final len = _period == _Period.d1 ? 1 : _period == _Period.d7 ? 7 : 30;
    final start = DateUtils.dateOnly(_anchorStart ?? today.subtract(Duration(days: len - 1)));
    _days = List.generate(len, (i) => DateTime(start.year, start.month, start.day + i));
  }

  DateTimeRange get _range {
  final start = _days.first;
  final today = DateUtils.dateOnly(DateTime.now());
  final lastDay = _days.last.isAfter(today) ? today : _days.last;
  final end = DateTime(lastDay.year, lastDay.month, lastDay.day, 23, 59, 59, 999);
    return DateTimeRange(start: start, end: end);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // KPIs using DB aggregates
  _visitsInRange = await _db.getVisitCountBetween(_range.start, _range.end);
  _collectedInRange = await _db.getRevenueTotalBetween(_range.start, _range.end);
  _billedInRange = await _db.getBilledTotalBetween(_range.start, _range.end);

      // Series by day: use per-day aggregate calls (simple, no new queries needed)
      final visits = <int>[];
      final collected = <double>[];
      final today = DateUtils.dateOnly(DateTime.now());
      for (final d in _days) {
        final dayStart = DateTime(d.year, d.month, d.day);
        if (dayStart.isAfter(today)) {
          visits.add(0);
          collected.add(0);
          continue;
        }
        final dayEnd = DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
        final v = await _db.getVisitCountBetween(dayStart, dayEnd);
        final c = await _db.getRevenueTotalBetween(dayStart, dayEnd);
        visits.add(v);
        collected.add(c);
      }
      _visitsSeries = visits;
      _collectedSeries = collected;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setPeriod(_Period p) {
    if (_period == p) return;
    setState(() {
      _period = p;
  // Reset to last N days immediately
  final today = DateUtils.dateOnly(DateTime.now());
  final len = _period == _Period.d1 ? 1 : _period == _Period.d7 ? 7 : 30;
  _anchorStart = today.subtract(Duration(days: len - 1));
  _computeDays();
    });
    _load();
  }

  Future<void> _pickAnchorDate() async {
    final now = DateTime.now();
    final initial = _anchorStart ?? DateUtils.dateOnly(now);
    final firstDate = DateTime(now.year - 3);
    final lastDate = DateUtils.dateOnly(now); // don't allow future selection
    final len = _period == _Period.d1 ? 1 : _period == _Period.d7 ? 7 : 30;
    final picked = await showCompactDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: lastDate,
      previewLength: len,
      title: 'Select start date',
    );
    if (picked != null) {
      setState(() {
        _anchorStart = DateUtils.dateOnly(picked);
        _computeDays();
      });
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Analytics'), centerTitle: false),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: range label + period chips (no "more analytics" per request)
            Row(
              children: [
        _RangePill(text: _formatRange(_range), onTap: _pickAnchorDate),
                const SizedBox(width: 12),
                _PeriodChip(
                  label: '1d',
                  selected: _period == _Period.d1,
                  onTap: () => _setPeriod(_Period.d1),
                ),
                const SizedBox(width: 8),
                _PeriodChip(
                  label: '7d',
                  selected: _period == _Period.d7,
                  onTap: () => _setPeriod(_Period.d7),
                ),
                const SizedBox(width: 8),
                _PeriodChip(
                  label: '30d',
                  selected: _period == _Period.d30,
                  onTap: () => _setPeriod(_Period.d30),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // KPI tiles (responsive: stack/wrap on narrow screens to avoid squish)
            LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final cols = w < 380 ? 1 : (w < 640 ? 2 : 3);
                final gap = 12.0;
                final tileWidth = (w - (cols - 1) * gap) / cols;
                Widget tile(Widget child) => SizedBox(width: tileWidth, child: child);
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    tile(_kpiTileBox(context, title: 'Collected', value: _money(_collectedInRange), icon: Icons.payments)),
                    tile(_kpiTileBox(context, title: 'Outstanding', value: _money(_outstandingInRange), icon: Icons.receipt_long)),
                    tile(_kpiTileBox(context, title: 'Visits', value: _visitsInRange.toString(), icon: Icons.event_available)),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            // Chart
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 220),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.outlineVariant.withValues(alpha: 0.3)),
                ),
                padding: const EdgeInsets.all(12),
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : SizedBox.expand(
                        child: _SimpleTwoSeriesChart(
                          xLabels: _days.map((d) => _abbrDay(d)).toList(),
                          seriesA: _visitsSeries.map((e) => e.toDouble()).toList(),
                          seriesALabel: 'Visits',
                          seriesB: _collectedSeries,
                          seriesBLabel: 'Collected',
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Non-expanded KPI tile used within a Wrap for responsiveness.
  Widget _kpiTileBox(BuildContext context, {required String title, required String value, required IconData icon}) {
    final color = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatRange(DateTimeRange r) {
    String p(DateTime d) => '${_monthAbbr(d.month)} ${d.day}';
    return '${p(r.start)} – ${p(r.end)}';
  }

  String _monthAbbr(int m) {
    const a = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return a[(m - 1).clamp(0, 11)];
  }

  String _abbrDay(DateTime d) {
    // For short ranges show 'Aug 20', for longer show just day number every few ticks
    if (_period == _Period.d1) return '${_monthAbbr(d.month)} ${d.day}';
    return '${_monthAbbr(d.month)} ${d.day}';
  }

  String _money(double v) {
    return 'Rs.${v.toStringAsFixed(0)}';
  }
}

class _RangePill extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  const _RangePill({required this.text, this.onTap});
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.date_range, size: 18),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
    if (onTap == null) return pill;
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: pill,
    );
  }
}

class _PeriodChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PeriodChip({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.primary.withValues(alpha: 0.15) : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: selected ? color.primary : color.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(fontWeight: FontWeight.w600, color: selected ? color.primary : null),
        ),
      ),
    );
  }
}

class _SimpleTwoSeriesChart extends StatelessWidget {
  final List<String> xLabels;
  final List<double> seriesA; // Visits (converted to double)
  final String seriesALabel;
  final List<double> seriesB; // Collected
  final String seriesBLabel;

  const _SimpleTwoSeriesChart({
    required this.xLabels,
    required this.seriesA,
    required this.seriesALabel,
    required this.seriesB,
    required this.seriesBLabel,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 600.0;
      final height = constraints.maxHeight.isFinite ? constraints.maxHeight : 280.0;
      return SizedBox(
        width: width,
        height: height,
        child: CustomPaint(
          painter: _TwoSeriesPainter(
            xLabels: xLabels,
            seriesA: seriesA,
            seriesALabel: seriesALabel,
            seriesB: seriesB,
            seriesBLabel: seriesBLabel,
            colorScheme: Theme.of(context).colorScheme,
          ),
        ),
      );
    });
  }
}

class _TwoSeriesPainter extends CustomPainter {
  final List<String> xLabels;
  final List<double> seriesA;
  final String seriesALabel;
  final List<double> seriesB;
  final String seriesBLabel;
  final ColorScheme colorScheme;

  _TwoSeriesPainter({
    required this.xLabels,
    required this.seriesA,
    required this.seriesALabel,
    required this.seriesB,
    required this.seriesBLabel,
    required this.colorScheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
  final left = 44.0;
  final right = 12.0;
  final top = 20.0;
  final bottom = 36.0;
  final chartRect = Rect.fromLTWH(left, top, size.width - left - right, size.height - top - bottom);

    // Axes
    final axisPaint = Paint()
      ..color = colorScheme.outlineVariant.withValues(alpha: 0.4)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(chartRect.left, chartRect.bottom), Offset(chartRect.right, chartRect.bottom), axisPaint);
    canvas.drawLine(Offset(chartRect.left, chartRect.top), Offset(chartRect.left, chartRect.bottom), axisPaint);

    // Determine max value
    final maxY = [
      ...(seriesA.isEmpty ? [0.0] : seriesA),
      ...(seriesB.isEmpty ? [0.0] : seriesB),
    ].reduce((a, b) => a > b ? a : b);
    final safeMax = (maxY <= 0) ? 1.0 : maxY;

    // Gridlines (4)
    final gridPaint = Paint()
      ..color = colorScheme.outlineVariant.withValues(alpha: 0.2)
      ..strokeWidth = 1;
    for (int i = 1; i <= 4; i++) {
      final y = chartRect.bottom - (chartRect.height * (i / 4));
      canvas.drawLine(Offset(chartRect.left, y), Offset(chartRect.right, y), gridPaint);
    }

    // Plot function
    void drawSeries(List<double> s, Color col) {
      if (s.isEmpty) return;
      final dx = chartRect.width / (s.length - 1).clamp(1, 1000000);
      final path = Path();
      for (int i = 0; i < s.length; i++) {
        final x = chartRect.left + dx * i;
        final y = chartRect.bottom - (s[i] / safeMax) * chartRect.height;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      final paint = Paint()
        ..color = col
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawPath(path, paint);
      // End dots
      final dotPaint = Paint()..color = col;
      for (int i = 0; i < s.length; i++) {
        final x = chartRect.left + dx * i;
        final y = chartRect.bottom - (s[i] / safeMax) * chartRect.height;
        canvas.drawCircle(Offset(x, y), 2.5, dotPaint);
      }
    }

    drawSeries(seriesA, colorScheme.primary.withValues(alpha: 0.9));
    drawSeries(seriesB, colorScheme.tertiary.withValues(alpha: 0.9));

    // X labels (sparse)
    final tp = TextPainter(textDirection: TextDirection.ltr);
    final tickCount = xLabels.length.clamp(2, 8);
    final step = (xLabels.length / tickCount).ceil();
    for (int i = 0; i < xLabels.length; i += step) {
      final label = xLabels[i];
      tp.text = TextSpan(text: label, style: const TextStyle(fontSize: 10, color: Colors.grey));
      tp.layout();
      final dx = chartRect.width / (xLabels.length - 1).clamp(1, 1000000);
      final x = chartRect.left + dx * i - tp.width / 2;
      final y = chartRect.bottom + 6;
      tp.paint(canvas, Offset(x, y));
    }

    // Legend
  final legendY = chartRect.top - 10;
    void legendDot(double x, Color c, String text) {
      final p = Paint()..color = c;
      canvas.drawCircle(Offset(x, legendY), 4, p);
      final t = TextPainter(
        text: TextSpan(text: ' $text', style: const TextStyle(fontSize: 11, color: Colors.grey)),
        textDirection: TextDirection.ltr,
      )..layout();
      t.paint(canvas, Offset(x + 6, legendY - t.height / 2));
    }
    legendDot(chartRect.left, colorScheme.primary, seriesALabel);
    legendDot(chartRect.left + 100, colorScheme.tertiary, seriesBLabel);
  }

  @override
  bool shouldRepaint(covariant _TwoSeriesPainter oldDelegate) {
    return oldDelegate.seriesA != seriesA ||
        oldDelegate.seriesB != seriesB ||
        oldDelegate.xLabels != xLabels;
  }
}


