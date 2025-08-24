import 'package:flutter/material.dart';
import '../../../../core/widgets/compact_date_picker.dart';
import 'package:flutter/services.dart';

import '../../../../core/services/service_locator.dart';
import '../../../../core/data/models/data_models.dart';
import '../../../../core/data/repositories/data_repository.dart';
import '../../../../core/cloud/services/cloud_save_service.dart';
import '../widgets/patient_list_item.dart';
import 'patient_detail_page.dart';

/// Page displaying the list of patients with sync integration
/// 
/// This page demonstrates the integration of sync functionality with
/// the existing UI, showing sync status and providing manual sync triggers.
class PatientListPage extends StatefulWidget {
  static const String routeName = '/patients';

  const PatientListPage({super.key});

  @override
  State<PatientListPage> createState() => _PatientListPageState();
}

class _PatientListPageState extends State<PatientListPage> {
  late final CloudSaveService _cloudSaveService;
  late final DataRepository _dataRepository;
  
  // Holds the full dataset loaded from repository
  List<Patient> _allPatients = [];
  // Holds the list currently displayed (may be filtered)
  List<Patient> _patients = [];
  Map<String, double> _dueByPatient = {};
  bool _isLoading = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cloudSaveService = serviceLocator.get<CloudSaveService>();
    _dataRepository = serviceLocator.get<DataRepository>();
    _loadPatients();
    
    // Listen to cloud save state changes
    _cloudSaveService.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          // Update UI based on cloud save state changes
        });
      }
    });
  }

  Future<void> _loadPatients() async {
    setState(() {
      _isLoading = true;
    });

    try {
      _allPatients = await _dataRepository.getPatients();
      _patients = List<Patient>.from(_allPatients);
      // compute due per patient
      final dueMap = <String, double>{};
      for (final p in _allPatients) {
        final visits = await _dataRepository.getVisitsForPatient(p.id);
        final payments = await _dataRepository.getPaymentsForPatient(p.id);
        final paidByVisit = <String, double>{};
        double unlinkedPaid = 0;
        for (final pay in payments) {
          if (pay.visitId == null) {
            unlinkedPaid += pay.amount;
            continue;
          }
          paidByVisit.update(pay.visitId!, (v) => v + pay.amount, ifAbsent: () => pay.amount);
        }
        // Compute due per-visit
        double billedTotal = 0;
        double paidTotal = 0;
        for (final v in visits) {
          final fee = (v.fee ?? 0);
          billedTotal += fee;
          paidTotal += (paidByVisit[v.id] ?? 0);
        }
        // Apply unlinked payments towards overall due for this patient
  final totalDue = (billedTotal - (paidTotal + unlinkedPaid));
  final double dueClamped = totalDue > 0 ? totalDue : 0.0;
  if (dueClamped > 0) dueMap[p.id] = dueClamped;
      }
      _dueByPatient = dueMap;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading patients: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _onRefresh() async {
    // Trigger manual cloud save
    try {
      if (!_cloudSaveService.autoSaveEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Auto-Save is disabled'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      final result = await _cloudSaveService.saveNow();
      if (!mounted) return;
      if (result.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cloud save completed'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.errorMessage ?? 'Cloud save failed'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cloud save error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }

    // Reload patients after sync
    await _loadPatients();
  }

  // Sync settings navigation no longer used here.

  void _addPatient() {
    _showAddPatientDialog();
  }

  @override
  Widget build(BuildContext context) {
    final bool isWide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patients'),
        actions: [
          if (isWide)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: FilledButton.icon(
                onPressed: _addPatient,
                icon: const Icon(Icons.add),
                label: const Text('Add Patient'),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search patients',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (q) {
                final query = q.trim().toLowerCase();
                setState(() {
                  if (query.isEmpty) {
                    _patients = List<Patient>.from(_allPatients);
                  } else {
                    _patients = _allPatients
                        .where((p) => p.name.toLowerCase().contains(query) || p.phone.contains(q.trim()))
                        .toList();
                  }
                });
              },
            ),
          ),
          // All sync/offline UI moved to Settings per product decision.
          
          // Patient list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _onRefresh,
                    child: _patients.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.people_outline,
                                  size: 64,
                                  color: Colors.grey,
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'No patients found',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Pull down to refresh or add a new patient',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _patients.length,
                            itemBuilder: (context, index) {
                              final patient = _patients[index];
                              return PatientListItem(
                                patient: patient,
                                onTap: () => _navigateToPatientDetail(patient),
                                dueAmount: _dueByPatient[patient.id],
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
      floatingActionButton: isWide
          ? null
          : FloatingActionButton(
              onPressed: _addPatient,
              tooltip: 'Add Patient',
              child: const Icon(Icons.add),
            ),
    );
  }

  Future<void> _navigateToPatientDetail(Patient patient) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PatientDetailPage(patient: patient)),
    );
    if (!mounted) return;
    await _loadPatients();
  }

  Future<void> _showAddPatientDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    DateTime? dateOfBirth;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Patient'),
        content: Form(
          key: formKey,
          child: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: phoneController,
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
                        Expanded(child: Text(dateOfBirth != null ? '${dateOfBirth!.day}/${dateOfBirth!.month}/${dateOfBirth!.year}' : '-')),
                        TextButton.icon(
                          onPressed: () async {
                            final now = DateTime.now();
                            final picked = await showCompactDatePicker(
                              context: context,
                              initialDate: dateOfBirth ?? DateTime(2000, 1, 1),
                              firstDate: DateTime(1900),
                              lastDate: DateTime(now.year + 50),
                              previewLength: 1,
                              title: 'Select date of birth',
                            );
                            if (picked != null) {
                              dateOfBirth = picked;
                              // ignore: invalid_use_of_protected_member
                              (context as Element).markNeedsBuild();
                            }
                          },
                          icon: const Icon(Icons.event),
                          label: const Text('Pick date'),
                        ),
                        // No Clear button; DOB is optional and can be left unset
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final patient = Patient(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                name: nameController.text.trim(),
                phone: phoneController.text.trim(),
                dateOfBirth: dateOfBirth,
                lastModified: DateTime.now(),
                deviceId: 'this_device',
                syncStatus: 'pending',
              );
              try {
                await _dataRepository.addPatient(patient);
                if (!mounted) return;
                Navigator.of(context).pop();
                await _loadPatients();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Patient added')),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to add: $e')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // Conflict resolution removed in simplified cloud save system
}