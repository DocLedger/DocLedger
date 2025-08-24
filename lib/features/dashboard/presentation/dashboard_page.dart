import 'package:flutter/material.dart';
import '../../../core/data/repositories/data_repository.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/data/models/data_models.dart' as models;
import '../../appointments/presentation/appointments_page.dart' show showNewAppointmentDialog;

class DashboardPage extends StatelessWidget {
  final bool embedded; // true when placed inside shells which provide chrome
  const DashboardPage({super.key, this.embedded = false});
  static const String routeName = '/dashboard';

  @override
  Widget build(BuildContext context) {
    final repo = serviceLocator.get<DataRepository>();
    final width = MediaQuery.sizeOf(context).width;
  final isCompact = width < 900;

  // Single metrics list card that combines the three small boxes into one.
  // If height is null, the card will size to its content (removes extra whitespace).
  Widget metricsListCard({double? height}) {
      return FutureBuilder<List<dynamic>>(
        future: Future.wait([
          repo.getPatientCount(),
          repo.getTodayVisitCount(),
          repo.getPendingFollowUpsCount(),
          _todayAppointmentsCount(repo),
        ]),
        builder: (context, snapshot) {
          final data = snapshot.data;
          final patients = data != null ? data[0] as int : 0;
          final todayVisits = data != null ? data[1] as int : 0;
          final pendingFollowUps = data != null ? data[2] as int : 0;
          final todayAppts = data != null ? data[3] as int : 0;

          // A single-row metric: icon + title on the left, number on the right.
      Widget metricRow(String title, String value, IconData icon) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: Theme.of(context).colorScheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(fontSize: 15),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      value,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              );

          // Build rows for compact (content-sized) layout.
            // Build rows for compact (content-sized) layout.
            final compactRows = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                metricRow('Total Patients', patients.toString(), Icons.people),
                const Divider(height: 1, thickness: 1),
                metricRow('Appointments Today', todayAppts.toString(), Icons.event),
                const Divider(height: 1, thickness: 1),
                metricRow("Patient Visits Today", todayVisits.toString(), Icons.event_available),
                const Divider(height: 1, thickness: 1),
                metricRow('Follow-ups (7d)', pendingFollowUps.toString(), Icons.schedule),
              ],
            );

            // Build rows for fixed-height layout (wide screens): expand rows to fill height evenly.
            final stretchedRows = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: metricRow('Total Patients', patients.toString(), Icons.people)),
                const Divider(height: 1, thickness: 1),
                Expanded(child: metricRow('Appointments Today', todayAppts.toString(), Icons.event)),
                const Divider(height: 1, thickness: 1),
                Expanded(child: metricRow("Patient Visits Today", todayVisits.toString(), Icons.event_available)),
                const Divider(height: 1, thickness: 1),
                Expanded(child: metricRow('Follow-ups (7d)', pendingFollowUps.toString(), Icons.schedule)),
              ],
            );

            return _DashboardCard(
              child: height == null
                  ? compactRows
                  : SizedBox(height: height, child: stretchedRows),
            );
        },
      );
    }

  Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header is now shown in the AppBar (like Patients/Analytics). No in-body title.
  if (isCompact) ...[
    // Compact screens (Android): Metrics first, then Today, then the remaining two boxes.
    metricsListCard(),
    const SizedBox(height: 12),
    _DashboardCard(
            child: SizedBox(
              height: 240,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle('Today'),
                  const SizedBox(height: 8),
      _TodayFollowUpsList(repo: repo, embedded: true),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _DashboardCard(
            child: SizedBox(
              height: 240,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle('Upcoming Follow-ups'),
                  const SizedBox(height: 8),
      _UpcomingList(repo: repo, embedded: true),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _DashboardCard(
            child: SizedBox(
              height: 240,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle('Recent Patients'),
                  const SizedBox(height: 8),
                  _RecentPatientsList(repo: repo, embedded: true),
                ],
              ),
            ),
          ),
        ] else ...[
          // Wide screens: First row has Metrics (left) and Today (right), both at a compact equal height. Next row has the two remaining boxes.
          Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 1,
                    child: metricsListCard(height: 240),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: _DashboardCard(
                      child: SizedBox(
                        height: 240,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _SectionTitle('Today'),
                            const SizedBox(height: 8),
                            Expanded(child: _TodayFollowUpsList(repo: repo)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _DashboardCard(
                      child: SizedBox(
                        height: 260,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _SectionTitle('Upcoming Follow-ups'),
                            const SizedBox(height: 8),
                            Expanded(child: _UpcomingList(repo: repo)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DashboardCard(
                      child: SizedBox(
                        height: 260,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _SectionTitle('Recent Patients'),
                            const SizedBox(height: 8),
                            Expanded(child: _RecentPatientsList(repo: repo)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
      ],
    );

    // Always use an AppBar (requested) whether embedded in shell or not
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        centerTitle: false,
        actions: [
          Builder(builder: (context) {
            final cs = Theme.of(context).colorScheme;
            return OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: cs.primary.withValues(alpha: 0.35)),
                foregroundColor: cs.primary,
                backgroundColor: cs.primary.withValues(alpha: 0.10),
              ),
              onPressed: () async {
                // Open the same dialog used on Appointments page
                final res = await showNewAppointmentDialog(context);
                if (res == true && context.mounted) {
                  // After save, take user to Appointments page
                  Navigator.of(context).pushNamed('/appointments');
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('New Appointment'),
            );
          }),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: _SyncStatusIcon(repo: repo),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: body),
    );
  }
}

Future<int> _todayAppointmentsCount(DataRepository repo) async {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day);
  final end = start.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
  try {
    final list = await repo.getAppointments(from: start, to: end);
    return list.length;
  } catch (_) {
    return 0;
  }
}

class _TodayFollowUpsList extends StatelessWidget {
  final DataRepository repo;
  final bool embedded;
  const _TodayFollowUpsList({required this.repo, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    return FutureBuilder<List<dynamic>>(
      future: repo.getUpcomingFollowUps(limit: 12),
      builder: (context, snapshot) {
        final List<dynamic> items = snapshot.data ?? const <dynamic>[];
        final filtered = items.whereType<models.Visit>().where((v) {
          final d = DateUtils.dateOnly(v.followUpDate ?? v.visitDate);
          return d == today;
        }).toList();
        if (filtered.isEmpty) {
          return const Center(child: Text('No follow-ups today'));
        }
        final list = ListView.separated(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const Divider(height: 8),
          itemBuilder: (context, i) {
            final v = filtered[i];
            return FutureBuilder<models.Patient?>(
              future: serviceLocator.get<DataRepository>().getPatient(v.patientId),
              builder: (context, snap) {
                final name = (snap.data?.name ?? '').trim();
                final diag = (v.diagnosis ?? 'Visit').trim();
                final left = name.isNotEmpty ? '$name • $diag' : diag;
                return Row(
                  children: [
                    const Icon(Icons.today, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(left, style: const TextStyle(fontSize: 15), overflow: TextOverflow.ellipsis)),
                    Text(_time(v.followUpDate ?? v.visitDate)),
                  ],
                );
              },
            );
          },
        );
        return MediaQuery.removePadding(
          context: context,
          removeTop: true,
          removeBottom: true,
          child: list,
        );
      },
    );
  }
}

class _UpcomingList extends StatelessWidget {
  final DataRepository repo;
  final bool embedded;
  const _UpcomingList({required this.repo, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: repo.getUpcomingFollowUps(limit: 6),
      builder: (context, snapshot) {
  final items = snapshot.data ?? const <dynamic>[];
        if (items.isEmpty) {
          return const Center(child: Text('No upcoming follow-ups'));
        }
        final tomorrow = DateUtils.dateOnly(DateTime.now().add(const Duration(days: 1)));
  final filtered = items
            .whereType<models.Visit>()
            .where((v) => DateUtils.dateOnly(v.followUpDate ?? v.visitDate).isAfter(tomorrow.subtract(const Duration(days: 1))))
            .toList();
        if (filtered.isEmpty) {
          return const Center(child: Text('No upcoming follow-ups'));
        }
        final list = ListView.separated(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const Divider(height: 8),
          itemBuilder: (context, i) {
            final v = filtered[i];
            return FutureBuilder<models.Patient?>(
              future: serviceLocator.get<DataRepository>().getPatient(v.patientId),
              builder: (context, snap) {
                final name = (snap.data?.name ?? '').trim();
                final diag = (v.diagnosis ?? 'Visit').trim();
                final left = name.isNotEmpty ? '$name • $diag' : diag;
                return Row(
                  children: [
                    const Icon(Icons.schedule, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(left, style: const TextStyle(fontSize: 15), overflow: TextOverflow.ellipsis)),
                    Text(_date(v.followUpDate ?? v.visitDate)),
                  ],
                );
              },
            );
          },
        );
        return MediaQuery.removePadding(
          context: context,
          removeTop: true,
          removeBottom: true,
          child: list,
        );
      },
    );
  }
}

class _RecentPatientsList extends StatelessWidget {
  final DataRepository repo;
  final bool embedded;
  const _RecentPatientsList({required this.repo, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: repo.getRecentPatients(limit: 6),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <dynamic>[];
        if (items.isEmpty) {
          return const Center(child: Text('No recent patients'));
        }
        final list = ListView.separated(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 8),
          itemBuilder: (context, i) {
            final p = items[i] as models.Patient;
            return Row(
              children: [
                const CircleAvatar(radius: 12, child: Icon(Icons.person, size: 14)),
                const SizedBox(width: 8),
                Expanded(child: Text(p.name, style: const TextStyle(fontSize: 15))),
                Text(p.phone, style: const TextStyle(fontSize: 15)),
              ],
            );
          },
        );
        return MediaQuery.removePadding(
          context: context,
          removeTop: true,
          removeBottom: true,
          child: list,
        );
      },
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final Widget child;
  const _DashboardCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
      color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Text(text, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}

// _MetricTile removed (unused)

class _SyncStatusIcon extends StatelessWidget {
  final DataRepository repo;
  const _SyncStatusIcon({required this.repo});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: repo.getPendingSyncCount(),
      builder: (context, snapshot) {
        final pending = snapshot.data ?? 0;
        final color = pending == 0 ? Colors.green : Colors.orange;
        return Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Icon(pending == 0 ? Icons.cloud_done : Icons.cloud_upload, color: color, size: 20),
        );
      },
    );
  }
}

String _date(DateTime d) => '${d.day}/${d.month}/${d.year}';
String _time(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  final ampm = d.hour < 12 ? 'AM' : 'PM';
  return '$h:$m $ampm';
}

