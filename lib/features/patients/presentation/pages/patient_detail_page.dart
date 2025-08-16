import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../../core/data/models/data_models.dart';
import '../../../../core/data/repositories/data_repository.dart';
import '../../../../core/services/service_locator.dart';

class PatientDetailPage extends StatefulWidget {
  static const String routeName = '/patient-detail';
  final Patient patient;

  const PatientDetailPage({super.key, required this.patient});

  @override
  State<PatientDetailPage> createState() => _PatientDetailPageState();
}

class _PatientDetailPageState extends State<PatientDetailPage> {
  late final DataRepository _repo;
  late Patient _patient;
  List<Visit> _visits = [];
  List<Payment> _payments = [];
  Map<String, double> _paidByVisit = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _repo = serviceLocator.get<DataRepository>();
    _patient = widget.patient;
    _load();
  }

  Future<void> _load() async {
    final v = await _repo.getVisitsForPatient(_patient.id);
    final p = await _repo.getPaymentsForPatient(_patient.id);
    final byVisit = <String, double>{};
    for (final pay in p) {
      if (pay.visitId == null) continue;
      byVisit.update(pay.visitId!, (value) => value + pay.amount, ifAbsent: () => pay.amount);
    }
    if (mounted) {
      setState(() {
        _visits = v;
        _payments = p;
        _paidByVisit = byVisit;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final totals = _computeTotals();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient details'),
        actions: [
          IconButton(onPressed: _editPatient, icon: const Icon(Icons.edit)),
          IconButton(onPressed: _printPatientSummary, icon: const Icon(Icons.print)),
          IconButton(
            tooltip: 'Delete patient',
            onPressed: _confirmDeletePatient,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _patient.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _InfoPill(icon: Icons.phone, label: 'Phone', value: _patient.phone),
                    const SizedBox(width: 12),
                    _InfoPill(
                      icon: Icons.cake,
                      label: 'DOB',
                      value: _patient.dateOfBirth != null ? _formatDate(_patient.dateOfBirth!) : '-',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Divider(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5), thickness: 1, height: 1),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: _addVisit,
                      icon: const Icon(Icons.add_chart),
                      label: const Text('Add Visit'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _SummaryHeader(
                  totalVisits: totals.totalVisits,
                  totalBilled: totals.totalBilled,
                  totalPaid: totals.totalPaid,
                  totalOutstanding: totals.totalOutstanding,
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _visits.isEmpty
                          ? const Center(child: Text('No visits yet'))
                          : ListView.separated(
                              itemCount: _visits.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final v = _visits[index];
                                final double paid = (_paidByVisit[v.id] ?? 0).toDouble();
                                final double total = (v.fee ?? 0).toDouble();
                                final double due = (total - paid).clamp(0, double.infinity).toDouble();
                                return _VisitCard(
                                  visit: v,
                                  paidAmount: paid,
                                  dueAmount: due,
                                  onEdit: () => _editVisit(v),
                                  onAddPayment: () => _addPayment(v),
                                  onPrint: () => _printVisitSummary(v),
                                  onDelete: () => _confirmDeleteVisit(context, v),
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

class _VisitCard extends StatelessWidget {
  final Visit visit;
  final double paidAmount;
  final double dueAmount;
  final VoidCallback onEdit;
  final VoidCallback onAddPayment;
  final VoidCallback onPrint;
  final VoidCallback onDelete;

  const _VisitCard({
    required this.visit,
    required this.paidAmount,
    required this.dueAmount,
    required this.onEdit,
    required this.onAddPayment,
    required this.onPrint,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.3)),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(visit.diagnosis ?? 'Visit', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(width: 8),
                    Text(_fmtDate(visit.visitDate), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                    const Spacer(),
                    if (visit.fee != null)
                      Text('Rs.${visit.fee!.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  ],
                ),
                const SizedBox(height: 6),
                if ((visit.prescriptions ?? '').isNotEmpty)
                  Text('Rx: ${visit.prescriptions}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                if ((visit.notes ?? '').isNotEmpty)
                  Text('Notes: ${visit.notes}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                if (visit.followUpDate != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(children: [
                      const Icon(Icons.event, size: 14),
                      const SizedBox(width: 4),
                      Text('Follow-up: ${_fmtDate(visit.followUpDate!)}', style: const TextStyle(fontSize: 13)),
                    ]),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _StatusChip(
                            label: dueAmount > 0 ? 'Due Rs.${dueAmount.toStringAsFixed(0)}' : 'Paid',
                            color: dueAmount > 0 ? Colors.orange : Colors.green,
                          ),
                          _StatusChip(label: 'Paid Rs.${paidAmount.toStringAsFixed(0)}'),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _ActionIcon(icon: Icons.edit, tooltip: 'Edit', onPressed: onEdit),
                    const SizedBox(width: 7),
                    _ActionIcon(icon: Icons.payments, tooltip: 'Add payment', onPressed: onAddPayment),
                    const SizedBox(width: 7),
                    _ActionIcon(icon: Icons.print, tooltip: 'Print', onPressed: onPrint),
                    const SizedBox(width: 7),
                    _ActionIcon(icon: Icons.delete_outline, tooltip: 'Delete', onPressed: onDelete),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  const _ActionIcon({required this.icon, required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18),
        ),
      ),
    );
  }
}
extension on _PatientDetailPageState {
  Future<void> _editPatient() async {
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController(text: _patient.name);
    final phone = TextEditingController(text: _patient.phone);
    DateTime? dob = _patient.dateOfBirth;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Patient'),
        content: Form(
          key: formKey,
          child: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: phone,
                    decoration: const InputDecoration(labelText: 'Phone (11 digits)'),
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(11),
                    ],
                    validator: (v) {
                      final s = (v ?? '').trim();
                      if (s.isEmpty) return 'Required';
                      if (s.length != 11) return 'Must be 11 digits';
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  InputDecorator(
                    decoration: const InputDecoration(labelText: 'Date of Birth', border: OutlineInputBorder()),
                    child: Row(
                      children: [
                        Expanded(child: Text(dob != null ? _formatDate(dob!) : 'Pick a date')),
                        TextButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              firstDate: DateTime(1900),
                              lastDate: DateTime(2100),
                              initialDate: dob ?? DateTime(2000, 1, 1),
                            );
                            if (picked != null) {
                              dob = picked;
                              // ignore: invalid_use_of_protected_member
                              (context as Element).markNeedsBuild();
                            }
                          },
                          icon: const Icon(Icons.event),
                          label: const Text('Pick date'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );

    if (ok == true) {
      if (!(formKey.currentState?.validate() ?? false) || dob == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all fields correctly')));
        return;
      }
      final updated = _patient.copyWith(name: name.text.trim(), phone: phone.text.trim(), dateOfBirth: dob);
      await _repo.updatePatient(updated);
      if (!mounted) return;
      setState(() => _patient = updated);
      await _load();
    }
  }
  Future<void> _confirmDeletePatient() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete patient?'),
        content: const Text('This will remove the patient and all related data. This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await serviceLocator.get<DataRepository>().deletePatient(widget.patient.id);
        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Patient deleted')));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      }
    }
  }

  Future<void> _confirmDeleteVisit(BuildContext context, Visit v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete visit?'),
        content: const Text('This will delete the visit and its payments.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await _repo.deleteVisit(v.id);
        await _load();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Visit deleted')));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete visit: $e')));
      }
    }
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color? color;
  const _StatusChip({required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = (color ?? scheme.primary).withOpacity(0.1);
    final fg = color ?? scheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 13)),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  final int totalVisits;
  final double totalBilled;
  final double totalPaid;
  final double totalOutstanding;

  const _SummaryHeader({
    required this.totalVisits,
    required this.totalBilled,
    required this.totalPaid,
    required this.totalOutstanding,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    Widget tile(String title, String value, IconData icon, Color color) {
      return Container(
        width: 180,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Flexible(child: Text(title, style: textTheme.labelLarge?.copyWith(color: color), overflow: TextOverflow.ellipsis)),
              ],
            ),
            const SizedBox(height: 6),
            Text(value, style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          tile('Visits', totalVisits.toString(), Icons.event_note, Theme.of(context).colorScheme.primary),
          tile('Billed', 'Rs.${totalBilled.toStringAsFixed(0)}', Icons.request_quote, Colors.blueGrey),
          tile('Paid', 'Rs.${totalPaid.toStringAsFixed(0)}', Icons.verified, Colors.teal),
          tile('Outstanding', 'Rs.${totalOutstanding.toStringAsFixed(0)}', Icons.warning_amber, Colors.orange),
        ],
      ),
    );
  }
}

class _Totals {
  final int totalVisits;
  final double totalBilled;
  final double totalPaid;
  final double totalOutstanding;
  const _Totals({
    required this.totalVisits,
    required this.totalBilled,
    required this.totalPaid,
    required this.totalOutstanding,
  });
}

extension on _PatientDetailPageState {
  _Totals _computeTotals() {
    double billed = 0;
    double paid = 0;
    for (final v in _visits) {
      billed += (v.fee ?? 0);
      paid += (_paidByVisit[v.id] ?? 0);
    }
    final outstanding = (billed - paid).clamp(0, double.infinity).toDouble();
    return _Totals(
      totalVisits: _visits.length,
      totalBilled: billed.toDouble(),
      totalPaid: paid.toDouble(),
      totalOutstanding: outstanding,
    );
  }

  Future<void> _printPatientSummary() async {
    final totals = _computeTotals();
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Patient Summary', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Text('Name: ${widget.patient.name}'),
            pw.Text('Phone: ${widget.patient.phone}'),
            pw.SizedBox(height: 12),
            pw.Text('Totals', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Bullet(text: 'Visits: ${totals.totalVisits}'),
            pw.Bullet(text: 'Billed: Rs.${totals.totalBilled.toStringAsFixed(0)}'),
            pw.Bullet(text: 'Paid: Rs.${totals.totalPaid.toStringAsFixed(0)}'),
            pw.Bullet(text: 'Outstanding: Rs.${totals.totalOutstanding.toStringAsFixed(0)}'),
            pw.SizedBox(height: 12),
            pw.Text('Visits', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ..._visits.map((v) => pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 6),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('${_formatDate(v.visitDate)} - ${v.diagnosis ?? 'Visit'}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      if ((v.prescriptions ?? '').isNotEmpty) pw.Text('Rx: ${v.prescriptions}'),
                      if ((v.notes ?? '').isNotEmpty) pw.Text('Notes: ${v.notes}'),
                      if (v.fee != null) pw.Text('Fee: Rs.${v.fee!.toStringAsFixed(0)}'),
                      if (v.followUpDate != null) pw.Text('Follow-up: ${_formatDate(v.followUpDate!)}'),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
    await Printing.layoutPdf(onLayout: (format) async => doc.save());
  }

  Future<void> _printVisitSummary(Visit v) async {
    final doc = pw.Document();
    final double paid = (_paidByVisit[v.id] ?? 0).toDouble();
    final double total = (v.fee ?? 0).toDouble();
    final double due = (total - paid).clamp(0, double.infinity).toDouble();
    doc.addPage(
      pw.Page(
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Visit Summary', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Text('Patient: ${widget.patient.name}'),
            pw.Text('Phone: ${widget.patient.phone}'),
            pw.SizedBox(height: 12),
            pw.Text('Date: ${_formatDate(v.visitDate)}'),
            pw.Text('Diagnosis: ${v.diagnosis ?? '-'}'),
            if ((v.prescriptions ?? '').isNotEmpty) pw.Text('Prescriptions: ${v.prescriptions}'),
            if ((v.notes ?? '').isNotEmpty) pw.Text('Notes: ${v.notes}'),
            if (v.followUpDate != null) pw.Text('Follow-up: ${_formatDate(v.followUpDate!)}'),
            pw.SizedBox(height: 12),
            pw.Text('Billing', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Bullet(text: 'Fee: Rs.${total.toStringAsFixed(0)}'),
            pw.Bullet(text: 'Paid: Rs.${paid.toStringAsFixed(0)}'),
            pw.Bullet(text: 'Due: Rs.${due.toStringAsFixed(0)}'),
          ],
        ),
      ),
    );
    await Printing.layoutPdf(onLayout: (format) async => doc.save());
  }
  Future<void> _addVisit() async {
    final diagnosis = TextEditingController();
    final prescriptions = TextEditingController();
    final notes = TextEditingController();
    final feeCtrl = TextEditingController();
    DateTime? followUp;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Visit'),
        content: SizedBox(
          width: 520,
          child: StatefulBuilder(
            builder: (context, setLocalState) {
              return SingleChildScrollView(
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(controller: diagnosis, decoration: const InputDecoration(labelText: 'Diagnosis')),
                    const SizedBox(height: 6),
                    TextField(controller: prescriptions, decoration: const InputDecoration(labelText: 'Prescriptions')),
                    const SizedBox(height: 6),
                    TextField(controller: feeCtrl, decoration: const InputDecoration(labelText: 'Fee (Rs.)'), keyboardType: TextInputType.number),
                    const SizedBox(height: 6),
                    InputDecorator(
                      decoration: const InputDecoration(labelText: 'Follow-up', border: OutlineInputBorder()),
                      child: Row(
                        children: [
                          Expanded(child: Text(followUp != null ? _formatDate(followUp!) : 'No date')),
                          TextButton.icon(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                                initialDate: followUp ?? DateTime.now(),
                              );
                              if (picked != null) {
                                setLocalState(() => followUp = picked);
                              }
                            },
                            icon: const Icon(Icons.event),
                            label: const Text('Pick date'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notes')),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );

    if (saved == true) {
      final repo = serviceLocator.get<DataRepository>();
      final visit = Visit(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        patientId: widget.patient.id,
        visitDate: DateTime.now(),
        diagnosis: diagnosis.text.trim().isEmpty ? null : diagnosis.text.trim(),
        prescriptions: prescriptions.text.trim().isEmpty ? null : prescriptions.text.trim(),
        notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
        fee: feeCtrl.text.trim().isEmpty ? null : double.tryParse(feeCtrl.text.trim()),
        followUpDate: followUp,
        lastModified: DateTime.now(),
        deviceId: 'local',
        syncStatus: 'pending',
      );
      await repo.addVisit(visit);
      await _load();
    }
  }
  Future<void> _editVisit(Visit v) async {
    final diagnosis = TextEditingController(text: v.diagnosis ?? '');
    final prescriptions = TextEditingController(text: v.prescriptions ?? '');
    final notes = TextEditingController(text: v.notes ?? '');
    final feeCtrl = TextEditingController(text: v.fee?.toStringAsFixed(0) ?? '');
    DateTime? followUp = v.followUpDate;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Visit'),
        content: SizedBox(
          width: 520,
          child: StatefulBuilder(
            builder: (context, setLocalState) {
              return SingleChildScrollView(
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(controller: diagnosis, decoration: const InputDecoration(labelText: 'Diagnosis')),
                    const SizedBox(height: 6),
                    TextField(controller: prescriptions, decoration: const InputDecoration(labelText: 'Prescriptions')),
                    const SizedBox(height: 6),
                    TextField(controller: feeCtrl, decoration: const InputDecoration(labelText: 'Fee (Rs.)'), keyboardType: TextInputType.number),
                    const SizedBox(height: 6),
                    InputDecorator(
                      decoration: const InputDecoration(labelText: 'Follow-up', border: OutlineInputBorder()),
                      child: Row(
                        children: [
                          Expanded(child: Text(followUp != null ? _formatDate(followUp!) : 'No date')),
                          TextButton.icon(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                                initialDate: followUp ?? DateTime.now(),
                              );
                              if (picked != null) {
                                setLocalState(() => followUp = picked);
                              }
                            },
                            icon: const Icon(Icons.event),
                            label: const Text('Pick date'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notes')),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );

    if (saved == true) {
      final updated = v.copyWith(
        diagnosis: diagnosis.text.trim().isEmpty ? null : diagnosis.text.trim(),
        prescriptions: prescriptions.text.trim().isEmpty ? null : prescriptions.text.trim(),
        notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
        fee: double.tryParse(feeCtrl.text.trim()),
        followUpDate: followUp,
      );
      await _repo.updateVisit(updated);
      await _load();
    }
  }

  Future<void> _addPayment(Visit v) async {
    final amountCtrl = TextEditingController();
    final methodCtrl = TextEditingController(text: 'Cash');
    final notesCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Payment'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(controller: amountCtrl, decoration: const InputDecoration(labelText: 'Amount (Rs.)'), keyboardType: TextInputType.number),
                const SizedBox(height: 6),
                TextField(controller: methodCtrl, decoration: const InputDecoration(labelText: 'Method')),
                const SizedBox(height: 6),
                TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );

    if (ok == true) {
      final amount = double.tryParse(amountCtrl.text.trim());
      if (amount == null || amount <= 0) return;
      final p = Payment(
        id: 'pay_${DateTime.now().millisecondsSinceEpoch}',
        patientId: v.patientId,
        visitId: v.id,
        amount: amount,
        paymentDate: DateTime.now(),
        paymentMethod: methodCtrl.text.trim().isEmpty ? 'Cash' : methodCtrl.text.trim(),
        notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
        lastModified: DateTime.now(),
        deviceId: 'local',
      );
      await _repo.addPayment(p);
      await _load();
    }
  }
}

class PatientDetailArgs {
  final Patient patient;
  const PatientDetailArgs(this.patient);
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 140, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 15))),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoPill({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

