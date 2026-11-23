import 'package:flutter/material.dart';

import 'app.dart';
import 'core/providers/app_state.dart';
import 'features/sync/sync_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final appState = AppState();
  await appState.loadAll();

  final syncManager = SyncManager(appState: appState);
  await syncManager.initialize();

  runApp(
    ChemNoteApp(
      appState: appState,
      syncManager: syncManager,
    ),
  );
}
