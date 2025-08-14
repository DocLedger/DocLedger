import 'package:flutter/material.dart';
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
  List<Visit> _visits = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _repo = serviceLocator.get<DataRepository>();
    _load();
  }

  Future<void> _load() async {
    final v = await _repo.getVisitsForPatient(widget.patient.id);
    if (mounted) setState(() { _visits = v; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.patient.name)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoRow(label: 'Phone', value: widget.patient.phone),
            if (widget.patient.address != null && widget.patient.address!.isNotEmpty)
              _InfoRow(label: 'Address', value: widget.patient.address!),
            if (widget.patient.dateOfBirth != null)
              _InfoRow(label: 'DOB', value: _formatDate(widget.patient.dateOfBirth!)),
            const SizedBox(height: 16),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: () async {
                    final changed = await Navigator.of(context).pushNamed('/visit-form', arguments: widget.patient);
                    if (changed == true) {
                      await _load();
                    }
                  },
                  icon: const Icon(Icons.add_chart),
                  label: const Text('Add Visit'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _visits.isEmpty
                      ? const Center(child: Text('No visits yet'))
                      : ListView.builder(
                          itemCount: _visits.length,
                          itemBuilder: (context, index) {
                            final v = _visits[index];
                            return ListTile(
                              leading: const Icon(Icons.receipt_long),
                              title: Text(v.diagnosis ?? 'Visit'),
                              subtitle: Text(_formatDate(v.visitDate)),
                              trailing: v.fee != null ? Text('৳${v.fee!.toStringAsFixed(0)}') : null,
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
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
          SizedBox(width: 140, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

