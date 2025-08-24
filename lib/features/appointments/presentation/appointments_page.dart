import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/widgets/compact_date_picker.dart';
import '../../../core/data/repositories/data_repository.dart';
import '../../../core/data/models/data_models.dart';
import '../../../core/services/service_locator.dart';
import '../../patients/presentation/pages/patient_detail_page.dart';

class AppointmentsPage extends StatefulWidget {
  static const String routeName = '/appointments';
  const AppointmentsPage({super.key});

  @override
  State<AppointmentsPage> createState() => _AppointmentsPageState();
}

class _AppointmentsPageState extends State<AppointmentsPage> {
  final _repo = serviceLocator.get<DataRepository>();
  String _filter = 'Upcoming'; // All | Today | Upcoming

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Appointments'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: FilledButton.icon(
              onPressed: _openAddDialog,
              icon: const Icon(Icons.add),
              label: const Text('New Appointment'),
            ),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FilterChips(
              value: _filter,
              onChanged: (v) => setState(() => _filter = v),
            ),
            const SizedBox(height: 12),
            Expanded(child: _AppointmentsList(filter: _filter, repo: _repo)),
          ],
        ),
      ),
    );
  }

  Future<void> _openAddDialog() async {
    await showDialog<bool>(
      context: context,
      builder: (_) => _AppointmentDialog(repo: _repo),
    );
    if (!mounted) return;
    setState(() {});
  }
}

class _FilterChips extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _FilterChips({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final opts = ['All', 'Today', 'Upcoming'];
    final color = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      children: [
        for (final o in opts)
          ChoiceChip(
            label: Text(o),
            selected: value == o,
            onSelected: (_) => onChanged(o),
            selectedColor: color.primary.withValues(alpha: 0.15),
            side: BorderSide(color: value == o ? color.primary.withValues(alpha: 0.45) : color.primary.withValues(alpha: 0.25)),
            labelStyle: TextStyle(color: value == o ? color.primary : null),
            checkmarkColor: color.primary,
          )
      ],
    );
  }
}

class _AppointmentsList extends StatelessWidget {
  final String filter;
  final DataRepository repo;
  const _AppointmentsList({required this.filter, required this.repo});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    DateTime? from;
    DateTime? to;
    if (filter == 'Today') {
      final start = DateTime(now.year, now.month, now.day);
      from = start;
      to = start.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
    } else if (filter == 'Upcoming') {
      from = DateTime(now.year, now.month, now.day);
    }
    return FutureBuilder<List<Appointment>>(
      future: repo.getAppointments(from: from, to: to),
      builder: (context, snap) {
        final data = snap.data ?? const <Appointment>[];
        if (data.isEmpty) {
          return const Center(child: Text('No appointments'));
        }
        return ListView.separated(
          itemCount: data.length,
          separatorBuilder: (_, __) => const Divider(height: 8),
          itemBuilder: (_, i) => _AppointmentRow(appt: data[i], repo: repo),
        );
      },
    );
  }
}

class _AppointmentRow extends StatelessWidget {
  final Appointment appt;
  final DataRepository repo;
  const _AppointmentRow({required this.appt, required this.repo});

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay.fromDateTime(appt.dateTime);
    final timeStr = time.format(context);
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.event, color: Theme.of(context).colorScheme.primary, size: 18),
                    const SizedBox(width: 6),
                    Text('${_date(appt.dateTime)} • $timeStr', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.only(left: 24), // align with date text after 18px icon + 6px gap
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appt.patientId == null ? (appt.name ?? '—') : 'Linked to patient',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if ((appt.phone ?? '').isNotEmpty)
                        Text(appt.phone!, style: const TextStyle(color: Colors.black54)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35)),
              foregroundColor: Theme.of(context).colorScheme.primary,
            ),
            onPressed: () async {
              if (appt.patientId != null) {
                final patient = await repo.getPatient(appt.patientId!);
                if (patient == null) return;
                if (!context.mounted) return;
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => PatientDetailPage(patient: patient)));
              } else {
                if (!context.mounted) return;
                await showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => _LinkToPatientSheet(appt: appt, repo: repo),
                );
              }
            },
            icon: const Icon(Icons.person),
            label: const Text('As patient'),
          ),
        ],
      ),
    );
  }
}

class _AppointmentDialog extends StatefulWidget {
  final DataRepository repo;
  const _AppointmentDialog({required this.repo});

  @override
  State<_AppointmentDialog> createState() => _AppointmentDialogState();
}

class _AppointmentDialogState extends State<_AppointmentDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  DateTime _dateTime = DateTime.now().add(const Duration(hours: 1));
  String? _patientId;
  final _note = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Appointment'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _phone,
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
            _DateTimePicker(value: _dateTime, onChanged: (d) => setState(() => _dateTime = d)),
            const SizedBox(height: 8),
            TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note (optional)')),
          ],
        )),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final id = UniqueKey().toString();
    final appt = Appointment(
      id: id,
      dateTime: _dateTime,
      patientId: _patientId,
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      lastModified: DateTime.now(),
      deviceId: 'local',
    );
    await widget.repo.addAppointment(appt);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }
}

class _LinkToPatientSheet extends StatefulWidget {
  final Appointment appt;
  final DataRepository repo;
  const _LinkToPatientSheet({required this.appt, required this.repo});

  @override
  State<_LinkToPatientSheet> createState() => _LinkToPatientSheetState();
}

class _LinkToPatientSheetState extends State<_LinkToPatientSheet> {
  final _query = TextEditingController();
  List<Patient> _results = const [];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SizedBox(
          height: 420,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Link to patient', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                const SizedBox(height: 12),
                TextField(
                  controller: _query,
                  decoration: InputDecoration(
                    labelText: 'Search by name or phone',
                    suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _doSearch),
                  ),
                  onSubmitted: (_) => _doSearch(),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _results.isEmpty
                      ? const Center(child: Text('No results'))
                      : ListView.separated(
                          itemCount: _results.length,
                          separatorBuilder: (_, __) => const Divider(height: 8),
                          itemBuilder: (_, i) {
                            final p = _results[i];
                            return ListTile(
                              leading: const CircleAvatar(child: Icon(Icons.person, size: 16)),
                              title: Text(p.name),
                              subtitle: Text(p.phone),
                              trailing: FilledButton(
                                onPressed: () async {
                                  final updated = widget.appt.copyWith(patientId: p.id, name: null, phone: null, lastModified: DateTime.now());
                                  await widget.repo.updateAppointment(updated);
                                  if (!context.mounted) return;
                                  Navigator.of(context).pop();
                                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => PatientDetailPage(patient: p)));
                                },
                                child: const Text('Link and open'),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () async {
                      // Create a new patient from the appointment details
                      final newPatient = Patient(
                        id: UniqueKey().toString(),
                        name: widget.appt.name ?? 'Unnamed',
                        phone: widget.appt.phone ?? '',
                        dateOfBirth: null,
                        address: null,
                        emergencyContact: null,
                        lastModified: DateTime.now(),
                        deviceId: 'local',
                      );
                      await serviceLocator.get<DataRepository>().addPatient(newPatient);
                      final updated = widget.appt.copyWith(patientId: newPatient.id, name: null, phone: null, lastModified: DateTime.now());
                      await widget.repo.updateAppointment(updated);
                      if (!context.mounted) return;
                      Navigator.of(context).pop();
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => PatientDetailPage(patient: newPatient)));
                    },
                    child: const Text('Create new patient'),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _doSearch() async {
    final all = await serviceLocator.get<DataRepository>().getPatients();
    final q = _query.text.trim().toLowerCase();
    _results = all.where((p) => p.name.toLowerCase().contains(q) || p.phone.contains(q)).toList();
    if (mounted) setState(() {});
  }
}

class _DateTimePicker extends StatelessWidget {
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  const _DateTimePicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final btnStyle = OutlinedButton.styleFrom(
      side: BorderSide(color: cs.primary.withValues(alpha: 0.35)),
    );
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            style: btnStyle,
            onPressed: () async {
              final d = await showCompactDatePicker(
                context: context,
                initialDate: value,
                firstDate: DateTime.now().subtract(const Duration(days: 1)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                previewLength: 1,
                title: 'Select date',
              );
              if (d == null) return;
              onChanged(DateTime(d.year, d.month, d.day, value.hour, value.minute));
            },
            child: Text(_date(value)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            style: btnStyle,
            onPressed: () async {
              final t = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(value),
                initialEntryMode: TimePickerEntryMode.input,
              );
              if (t == null) return;
              onChanged(DateTime(value.year, value.month, value.day, t.hour, t.minute));
            },
            child: Text(TimeOfDay.fromDateTime(value).format(context)),
          ),
        ),
      ],
    );
  }
}

String _date(DateTime d) => '${d.day}/${d.month}/${d.year}';

/// Expose a simple dialog helper for reuse (e.g., from Dashboard)
Future<bool?> showNewAppointmentDialog(BuildContext context) {
  final repo = serviceLocator.get<DataRepository>();
  return showDialog<bool>(
    context: context,
    builder: (_) => _AppointmentDialog(repo: repo),
  );
}