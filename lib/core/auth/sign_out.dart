import 'package:flutter/material.dart';

import '../services/service_locator.dart';
import '../cloud/services/google_drive_service.dart';

Future<void> performSignOut(BuildContext context) async {
  try {
    if (serviceLocator.isRegistered<GoogleDriveService>()) {
      await serviceLocator.get<GoogleDriveService>().signOut();
    }
  } catch (_) {}

  if (context.mounted) {
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }
}


