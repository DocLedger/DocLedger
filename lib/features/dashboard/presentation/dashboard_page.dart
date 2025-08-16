import 'package:flutter/material.dart';

import '../../patients/presentation/pages/patient_list_page.dart';
import '../../../core/auth/sign_out.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/data/repositories/data_repository.dart';
import '../../../core/data/models/data_models.dart' as models;

/// Main dashboard with bottom navigation and quick actions
class DashboardPage extends StatefulWidget {
  static const String routeName = '/dashboard';

  final bool embedded; // when true, render content without bottom navigation

  const DashboardPage({super.key, this.embedded = false});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _index = 0;

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = const [
      _HomeTab(),
      PatientListPage(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      // When embedded inside another Scaffold (desktop or mobile shells), return the content directly
      return const _HomeTab();
    }
    return Scaffold(
      body: _pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Patients'),
        ],
        onDestinationSelected: (i) => setState(() => _index = i),
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final repo = serviceLocator.get<DataRepository>();
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 700;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            const SizedBox(height: 12),
            FutureBuilder<List<dynamic>>(
          future: Future.wait([
            repo.getPatientCount(),
            repo.getTodayVisitCount(),
            repo.getThisMonthRevenue(),
            repo.getPendingFollowUpsCount(),
          ]),
          builder: (context, snapshot) {
            final data = snapshot.data;
            final patients = data != null ? data[0] as int : 0;
            final todayVisits = data != null ? data[1] as int : 0;
            final monthRevenue = data != null ? data[2] as double : 0.0;
            final pendingFollowUps = data != null ? data[3] as int : 0;
            Widget buildMetric(String title, String value, IconData icon) {
              final content = _MetricTile(title: title, value: value, icon: icon);
              return _DashboardCard(
                child: SizedBox(
                  height: isCompact ? 128 : 140,
                  child: content,
                ),
              );
            }
            final tiles = <Widget>[
              buildMetric('Total Patients', patients.toString(), Icons.people),
              buildMetric("Today's Visits", todayVisits.toString(), Icons.event_available),
              buildMetric('This Month Revenue', 'Rs.${monthRevenue.toStringAsFixed(0)}', Icons.payments),
              buildMetric('Follow-ups (7d)', pendingFollowUps.toString(), Icons.schedule),
            ];
            if (isCompact) {
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  mainAxisExtent: 128, // taller cards to avoid overflow
                ),
                itemCount: tiles.length,
                itemBuilder: (_, i) => tiles[i],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: tiles[0]),
                const SizedBox(width: 12),
                Expanded(child: tiles[1]),
                const SizedBox(width: 12),
                Expanded(child: tiles[2]),
                const SizedBox(width: 12),
                Expanded(child: tiles[3]),
              ],
            );
          },
        ),
            const SizedBox(height: 12),
            if (isCompact)
              Column(
                children: [
                  _DashboardCard(
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
                  const SizedBox(height: 12),
                  _DashboardCard(
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
                ],
              )
            else
              Row(
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
        );
      },
    );
  }
}

class _UpcomingList extends StatelessWidget {
  final DataRepository repo;
  const _UpcomingList({required this.repo});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: repo.getUpcomingFollowUps(limit: 6),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <dynamic>[];
        if (items.isEmpty) {
          return const Center(child: Text('No upcoming follow-ups'));
        }
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 8),
          itemBuilder: (context, i) {
            final v = items[i] as models.Visit;
            return Row(
              children: [
                const Icon(Icons.schedule, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(v.diagnosis ?? 'Visit', style: const TextStyle(fontSize: 15))),
                Text(_date(v.followUpDate ?? v.visitDate)),
              ],
            );
          },
        );
      },
    );
  }
}

class _RecentPatientsList extends StatelessWidget {
  final DataRepository repo;
  const _RecentPatientsList({required this.repo});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: repo.getRecentPatients(limit: 6),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <dynamic>[];
        if (items.isEmpty) {
          return const Center(child: Text('No recent patients'));
        }
        return ListView.separated(
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
      },
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  final String title;
  final String value;
  const _KpiTile({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 6),
          Text(value, style: Theme.of(context).textTheme.headlineSmall),
        ],
      ),
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
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }
}

class _VitalMiniCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  const _VitalMiniCard({required this.title, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
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

class _MetricTile extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  const _MetricTile({required this.title, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(child: Icon(icon, color: color.primary)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.grey, fontSize: 15),
                maxLines: 2,
                softWrap: true,
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _date(DateTime d) => '${d.day}/${d.month}/${d.year}';

