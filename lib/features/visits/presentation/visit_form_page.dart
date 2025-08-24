import 'package:flutter/material.dart';
import '../../../core/widgets/compact_date_picker.dart';
import '../../../core/data/models/data_models.dart' as models;
import '../../../core/services/service_locator.dart';
import '../../../core/data/repositories/data_repository.dart';

class VisitFormPage extends StatefulWidget {
  static const String routeName = '/visit-form';
  final models.Patient patient;
  const VisitFormPage({super.key, required this.patient});

  @override
  State<VisitFormPage> createState() => _VisitFormPageState();
}

class _VisitFormPageState extends State<VisitFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _diagnosis = TextEditingController();
  final _prescriptions = TextEditingController();
  final _notes = TextEditingController();
  final _fee = TextEditingController();
  DateTime? _followUpDate;
  TimeOfDay? _followUpTime;

  @override
  void dispose() {
    _diagnosis.dispose();
    _prescriptions.dispose();
    _notes.dispose();
    _fee.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Visit')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Patient: ${widget.patient.name}', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextFormField(
              controller: _diagnosis,
              decoration: const InputDecoration(labelText: 'Diagnosis'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _prescriptions,
              decoration: const InputDecoration(labelText: 'Prescriptions'),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _fee,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Fee'),
            ),
            const SizedBox(height: 12),
            // Follow-up picker: separate outlined buttons for date and time (matches Appointments)
            Builder(builder: (context) {
              final cs = Theme.of(context).colorScheme;
              final btnStyle = OutlinedButton.styleFrom(
                side: BorderSide(color: cs.primary.withValues(alpha: 0.35)),
              );
              final current = _followUpDate != null
                  ? DateTime(
                      _followUpDate!.year,
                      _followUpDate!.month,
                      _followUpDate!.day,
                      (_followUpTime ?? TimeOfDay.now()).hour,
                      (_followUpTime ?? TimeOfDay.now()).minute,
                    )
                  : null;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Text('Follow-up'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: btnStyle,
                          onPressed: () async {
                            final now = DateTime.now();
                            final base = current ?? now;
                            final d = await showCompactDatePicker(
                              context: context,
                              initialDate: base,
                              firstDate: now.subtract(const Duration(days: 365)),
                              lastDate: now.add(const Duration(days: 365 * 2)),
                              previewLength: 1,
                              title: 'Select follow-up date',
                            );
                            if (d == null) return;
                            setState(() {
                              _followUpDate = DateUtils.dateOnly(d);
                            });
                          },
                          child: Align(
                            alignment: Alignment.center,
                            child: Text(current != null ? _formatDate(current) : 'Select date'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          style: btnStyle,
                          onPressed: () async {
                            final base = current ?? DateTime.now();
                            final t = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.fromDateTime(base),
                              initialEntryMode: TimePickerEntryMode.input,
                            );
                            if (t == null) return;
                            setState(() {
                              _followUpTime = t;
                              _followUpDate = _followUpDate ?? DateUtils.dateOnly(base);
                            });
                          },
                          child: Align(
                            alignment: Alignment.center,
                            child: Text(
                              (_followUpTime != null
                                      ? _followUpTime!
                                      : current != null
                                          ? TimeOfDay.fromDateTime(current)
                                          : TimeOfDay.now())
                                  .format(context),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            }),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notes'),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _save,
              child: const Text('Save Visit'),
            ),
          ],
        ),
      ),
    );
  }

  // Date & time are picked separately above; keep helper removed to avoid confusion.

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final repo = serviceLocator.get<DataRepository>();
    final visit = models.Visit(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      patientId: widget.patient.id,
      visitDate: DateTime.now(),
      diagnosis: _diagnosis.text.trim(),
      prescriptions: _prescriptions.text.trim().isEmpty ? null : _prescriptions.text.trim(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      fee: _fee.text.trim().isEmpty ? null : double.tryParse(_fee.text.trim()),
      followUpDate: _followUpDate != null
          ? DateTime(
              _followUpDate!.year,
              _followUpDate!.month,
              _followUpDate!.day,
              (_followUpTime ?? TimeOfDay.now()).hour,
              (_followUpTime ?? TimeOfDay.now()).minute,
            )
          : null,
      lastModified: DateTime.now(),
      deviceId: 'this_device',
      syncStatus: 'pending',
    );
    await repo.addVisit(visit);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  String _formatDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

