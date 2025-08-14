import 'package:flutter/material.dart';

class ReportsPage extends StatelessWidget {
  static const String routeName = '/reports';
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: const Center(
        child: Text('Reports and summaries will appear here'),
      ),
    );
  }
}

