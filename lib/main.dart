import 'package:flutter/material.dart';

import 'features/auth/presentation/login_page.dart';
import 'features/welcome/presentation/welcome_page.dart';

void main() {
  runApp(const DocLedgerApp());
}

class DocLedgerApp extends StatelessWidget {
  const DocLedgerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DocLedger',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      routes: {
        LoginPage.routeName: (_) => const LoginPage(),
        WelcomePage.routeName: (_) => const WelcomePage(),
      },
      initialRoute: LoginPage.routeName,
    );
  }
}
