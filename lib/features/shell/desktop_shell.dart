import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dashboard/presentation/dashboard_page.dart' show DashboardPage; // reuse Home content
import '../patients/presentation/pages/patient_list_page.dart';
import '../settings/presentation/pages/settings_page.dart';
import '../analytics/presentation/analytics_page.dart';
import 'package:url_launcher/url_launcher.dart';
// Cloud save state not shown here; no need to import the service

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
    AnalyticsPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    // Make the sidebar width adaptive so it scales better on very wide screens
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final double sidebarWidth = (screenWidth * 0.18).clamp(240.0, 360.0) as double;
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
              // Adaptive sidebar width: 18% of screen, clamped to 240-360px
              Container(
                width: sidebarWidth,
                color: Theme.of(context).colorScheme.surface,
                child: Column(
                  children: [
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Image.asset('assets/images/doc_ledger_logo.png', height: 36, errorBuilder: (_, __, ___) => const SizedBox(width: 36, height: 36)),
                          const SizedBox(width: 12),
                          Text('DocLedger', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, fontSize: 24)),
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
                      icon: Icons.analytics,
                      label: 'Analytics',
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
                    _ProfileTile(),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    // Top bar – only show a right spacer now (search moved to patients page)
                    Container(
                      height: 64,
                      color: Theme.of(context).scaffoldBackgroundColor,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: const SizedBox.shrink(),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.topCenter,
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


class _ProfileTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Center(
        child: FilledButton(
          onPressed: () => _openSupportDialog(context),
          style: FilledButton.styleFrom(
            backgroundColor: color.primary,
            foregroundColor: color.onPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Contact Support'),
        ),
      ),
    );
  }
}

Future<void> _openSupportDialog(BuildContext context) async {
  final uri = Uri.parse('mailto:docledger.pk@gmail.com?subject=${Uri.encodeComponent('DocLedger Support')}');
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Contact Support'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Email us at'),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => launchUrl(uri),
                child: const Text(
                  'docledger.pk@gmail.com',
                  style: TextStyle(decoration: TextDecoration.underline, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        ],
      );
    },
  );
}


