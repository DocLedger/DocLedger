import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'desktop_shell.dart';
import '../dashboard/presentation/dashboard_page.dart';
import '../sync/presentation/pages/sync_settings_page.dart';
import '../patients/presentation/pages/patient_list_page.dart';
import '../dashboard/reports/reports_page.dart';

/// Picks the right shell for the current form factor.
/// - Desktop/tablet wide screens: `DesktopShell`
/// - Phones: compact bottom navigation shell
class AdaptiveShell extends StatelessWidget {
  const AdaptiveShell({super.key});

  bool _isWide(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= 900; // desktop-like width
  }

  @override
  Widget build(BuildContext context) {
    // Prefer width-based decision so foldables/tablets on Android get desktop shell when wide
    if (_isWide(context) || (!kIsWeb && (defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows))) {
      return const DesktopShell();
    }

    // Mobile: bottom navigation with four tabs including Settings
    return const _MobileRootShell();
  }
}

class _MobileRootShell extends StatefulWidget {
  const _MobileRootShell();

  @override
  State<_MobileRootShell> createState() => _MobileRootShellState();
}

class _MobileRootShellState extends State<_MobileRootShell> {
  int _index = 0;

  static const List<Widget> _pages = <Widget>[
    DashboardPage(embedded: true),
    PatientListPage(),
    ReportsPage(),
    SyncSettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DocLedger')),
      body: _pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Patients'),
          NavigationDestination(icon: Icon(Icons.assessment_outlined), selectedIcon: Icon(Icons.assessment), label: 'Reports'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
        onDestinationSelected: (i) => setState(() => _index = i),
      ),
    );
  }
}


