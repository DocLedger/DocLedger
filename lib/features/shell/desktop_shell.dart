import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dashboard/presentation/dashboard_page.dart' show DashboardPage; // reuse Home content
import '../patients/presentation/pages/patient_list_page.dart';
import '../dashboard/reports/reports_page.dart';
import '../sync/presentation/pages/sync_settings_page.dart';
import '../../core/auth/sign_out.dart';

class DesktopShell extends StatefulWidget {
  static const String routeName = '/';
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  int _index = 0;

  late final List<Widget> _pages = const [
    DashboardPage(embedded: true),
    PatientListPage(),
    ReportsPage(),
    SyncSettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyN): const _GoPatientsAndAddIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyS): const _GoSettingsIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _GoPatientsAndAddIntent: CallbackAction<_GoPatientsAndAddIntent>(onInvoke: (i) {
            setState(() => _index = 1);
            // open add dialog via Navigator message to page state if needed
            return null;
          }),
          _GoSettingsIntent: CallbackAction<_GoSettingsIntent>(onInvoke: (i) {
            setState(() => _index = 3);
            return null;
          }),
        },
        child: Scaffold(
          body: Row(
            children: [
              // Custom sidebar ~240px width to match the reference
              Container(
                width: 240,
                color: Theme.of(context).colorScheme.surface,
                child: Column(
                  children: [
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          const CircleAvatar(radius: 14, child: Icon(Icons.local_hospital, size: 16)),
                          const SizedBox(width: 8),
                          Text('DocLedger', style: Theme.of(context).textTheme.titleLarge),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    _NavItem(
                      icon: Icons.dashboard,
                      label: 'Dashboard',
                      selected: _index == 0,
                      onTap: () => setState(() => _index = 0),
                    ),
                    _NavItem(
                      icon: Icons.people,
                      label: 'Patients',
                      selected: _index == 1,
                      onTap: () => setState(() => _index = 1),
                    ),
                    _NavItem(
                      icon: Icons.description,
                      label: 'Reports',
                      selected: _index == 2,
                      onTap: () => setState(() => _index = 2),
                    ),
                    _NavItem(
                      icon: Icons.settings,
                      label: 'Settings',
                      selected: _index == 3,
                      onTap: () => setState(() => _index = 3),
                    ),
                    const Spacer(),
                    _NavItem(
                      icon: Icons.logout,
                      label: 'Sign out',
                      selected: false,
                      onTap: () => performSignOut(context),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    // Top bar with search and user avatar
                    Container(
                      height: 64,
                      color: Theme.of(context).scaffoldBackgroundColor,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 520),
                            child: TextField(
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.search),
                                hintText: 'Search patient name or ID',
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(28),
                                  borderSide: BorderSide(color: Theme.of(context).dividerColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(28),
                                  borderSide: BorderSide(color: Theme.of(context).dividerColor),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const CircleAvatar(child: Icon(Icons.person)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1200),
                          child: _pages[_index],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoPatientsAndAddIntent extends Intent { const _GoPatientsAndAddIntent(); }
class _GoSettingsIntent extends Intent { const _GoSettingsIntent(); }

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: selected ? color.primary.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: selected ? color.primary : color.onSurfaceVariant),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: selected ? color.primary : color.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


