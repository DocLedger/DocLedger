import 'package:flutter/material.dart';

import '../../../../core/services/service_locator.dart';
import '../../../../core/data/models/data_models.dart';
import '../../../../core/sync/models/sync_models.dart';
import '../../../../core/data/repositories/data_repository.dart';
import '../../../../core/sync/services/sync_service.dart';
import '../../../sync/presentation/widgets/sync_status_widget.dart';
import '../../../sync/presentation/widgets/offline_indicator_widget.dart';
import '../../../sync/presentation/pages/sync_settings_page.dart';
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
  late final SyncService _syncService;
  late final DataRepository _dataRepository;
  List<Patient> _patients = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _syncService = serviceLocator.get<SyncService>();
    _dataRepository = serviceLocator.get<DataRepository>();
    _loadPatients();
    
    // Listen to sync state changes
    _syncService.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          // Update UI based on sync state changes
        });
      }
    });
  }

  Future<void> _loadPatients() async {
    setState(() {
      _isLoading = true;
    });

    try {
      _patients = await _dataRepository.getPatients();
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
    // Trigger manual sync
    try {
      final result = await _syncService.performIncrementalSync();
      
      if (mounted) {
        if (result.isSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sync completed successfully'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sync failed: ${result.errorMessage}'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    
    // Reload patients after sync
    await _loadPatients();
  }

  void _navigateToSyncSettings() {
    Navigator.of(context).pushNamed(SyncSettingsPage.routeName);
  }

  void _addPatient() {
    _showAddPatientDialog();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patients'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _navigateToSyncSettings,
            tooltip: 'Settings',
          ),
        ],
      ),
      body: Column(
        children: [
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
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addPatient,
        tooltip: 'Add Patient',
        child: const Icon(Icons.add),
      ),
    );
  }

  void _navigateToPatientDetail(Patient patient) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PatientDetailPage(patient: patient)),
    );
  }

  Future<void> _showAddPatientDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final phoneController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Patient'),
        content: Form(
          key: formKey,
          child: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneController,
                  decoration: const InputDecoration(labelText: 'Phone'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ],
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

  Future<int> _getConflictCount() async {
    try {
      final conflicts = await _syncService.getPendingConflicts();
      return conflicts.length;
    } catch (e) {
      return 0;
    }
  }

  void _resolveConflicts() {
    // TODO: Navigate to conflict resolution page
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Conflict resolution will be implemented'),
      ),
    );
  }
}