import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io' show Platform;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/services/service_locator.dart';
import 'features/auth/presentation/login_page.dart';
import 'features/sync/presentation/pages/sync_settings_page.dart';
import 'features/patients/presentation/pages/patient_list_page.dart';
import 'features/dashboard/presentation/dashboard_page.dart';
import 'theme/app_theme.dart';
import 'features/patients/presentation/pages/patient_detail_page.dart';
import 'features/visits/presentation/visit_form_page.dart';
import 'features/dashboard/reports/reports_page.dart';
import 'features/shell/adaptive_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize core services including sync system
  try {
    // Initialize sqflite FFI on desktop platforms
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    await initializeServices();
  } catch (e) {
    // Log initialization error but continue with app startup
    debugPrint('Service initialization error: $e');
  }
  
  runApp(const DocLedgerApp());
}

class DocLedgerApp extends StatelessWidget {
  const DocLedgerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DocLedger',
      theme: AppTheme.light(),
      home: const AdaptiveShell(),
      routes: {
        LoginPage.routeName: (_) => const LoginPage(),
        SyncSettingsPage.routeName: (_) => const SyncSettingsPage(),
        PatientListPage.routeName: (_) => const PatientListPage(),
        DashboardPage.routeName: (_) => const DashboardPage(),
        ReportsPage.routeName: (_) => const ReportsPage(),
        // For pages with arguments, use onGenerateRoute when needed.
      },
      onGenerateRoute: (settings) {
        if (settings.name == PatientDetailPage.routeName && settings.arguments is PatientDetailArgs) {
          final args = settings.arguments as PatientDetailArgs;
          return MaterialPageRoute(builder: (_) => PatientDetailPage(patient: args.patient));
        }
        if (settings.name == VisitFormPage.routeName && settings.arguments is Object) {
          final patient = settings.arguments as dynamic; // kept simple for now
          return MaterialPageRoute(builder: (_) => VisitFormPage(patient: patient));
        }
        return null;
      },
      // Use home instead of initialRoute to avoid duplicate navigator during startup
    );
  }
}
