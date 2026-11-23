import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/providers/app_state.dart';
import 'core/theme/app_theme.dart';
import 'features/library/library_screen.dart';
import 'features/sync/sync_manager.dart';

class ChemNoteApp extends StatefulWidget {
  final AppState? appState;
  final SyncManager? syncManager;

  const ChemNoteApp({
    super.key,
    this.appState,
    this.syncManager,
  });

  @override
  State<ChemNoteApp> createState() => _ChemNoteAppState();
}

class _ChemNoteAppState extends State<ChemNoteApp> {
  late final AppState _appState;
  late final SyncManager _syncManager;
  late final bool _ownsAppState;
  late final bool _ownsSyncManager;

  @override
  void initState() {
    super.initState();
    _ownsAppState = widget.appState == null;
    _ownsSyncManager = widget.syncManager == null;

    _appState = widget.appState ?? AppState();
    _syncManager = widget.syncManager ?? SyncManager(appState: _appState);

    if (_ownsAppState) {
      _appState.loadAll().then((_) {
        if (_ownsSyncManager) {
          _syncManager.initialize();
        }
      });
    } else if (_ownsSyncManager) {
      _syncManager.initialize();
    }
  }

  @override
  void dispose() {
    if (_ownsSyncManager) {
      _syncManager.dispose();
    }
    if (_ownsAppState) {
      _appState.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: _appState),
        ChangeNotifierProvider<SyncManager>.value(value: _syncManager),
      ],
      child: Consumer<AppState>(
        builder: (context, state, _) {
          return MaterialApp(
            title: 'ChemNote',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme(),
            darkTheme: AppTheme.darkTheme(),
            themeMode: state.themeMode,
            home: const LibraryScreen(),
          );
        },
      ),
    );
  }
}
