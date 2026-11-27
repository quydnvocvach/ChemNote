import 'dart:async' show unawaited;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/drawing_elements.dart';
import '../../core/models/folder.dart';
import '../../core/models/note_page.dart';
import '../../core/models/notebook.dart';
import '../../core/providers/app_state.dart';
import '../../core/services/app_updater_service.dart';
import '../../core/theme/app_theme.dart';
import '../canvas/note_editor_screen.dart';
import '../pdf/pdf_export_service.dart';
import '../pdf/pdf_import_progress_overlay.dart';
import '../pdf/pdf_import_service.dart';
import '../sync/sync_manager.dart';
import '../sync/sync_settings_screen.dart';
import 'create_notebook_dialog.dart';
import 'notebook_cover_widget.dart';
import 'search_screen.dart';

enum _LibrarySection {
  allNotes,
  favorites,
  locked,
  trash,
  folder,
  templates,
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  _LibrarySection _section = _LibrarySection.allNotes;
  String? _selectedFolderId;
  bool _isSelectionMode = false;
  final Set<String> _selectedNotebookIds = <String>{};
  final Set<String> _expandedFolderIds = <String>{};

  List<Notebook> _notebooksForCurrentSection(AppState appState) {
    return switch (_section) {
      _LibrarySection.allNotes => appState.activeNotebooks,
      _LibrarySection.favorites => appState.favoriteNotebooks,
      _LibrarySection.locked => appState.lockedNotebooks,
      _LibrarySection.trash => appState.trashedNotebooks,
      _LibrarySection.folder => appState.getNotebooksInFolder(_selectedFolderId),
      _LibrarySection.templates => const [],
    };
  }

  void _selectSection(
    _LibrarySection section, {
    String? folderId,
    bool popDrawer = false,
  }) {
    final appState = context.read<AppState>();
    setState(() {
      _section = section;
      _selectedFolderId = folderId;
      _isSelectionMode = false;
      _selectedNotebookIds.clear();
      if (folderId != null) {
        for (final f in appState.getFolderPath(folderId)) {
          if (f.id != folderId) {
            _expandedFolderIds.add(f.id);
          }
        }
      }
    });
    if (popDrawer && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _enterSelectionMode(String notebookId) {
    setState(() {
      _isSelectionMode = true;
      _selectedNotebookIds
        ..clear()
        ..add(notebookId);
    });
  }

  void _toggleNotebookSelection(String notebookId) {
    setState(() {
      if (!_selectedNotebookIds.remove(notebookId)) {
        _selectedNotebookIds.add(notebookId);
      }
    });
  }

  void _exitSelectionMode() {
    if (!_isSelectionMode && _selectedNotebookIds.isEmpty) return;
    setState(() {
      _isSelectionMode = false;
      _selectedNotebookIds.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    context.select<AppState, int>((s) => s.libraryUiRevision);
    final appState = context.read<AppState>();
    final isWide = MediaQuery.sizeOf(context).width >= 820;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final visibleNotebooks = _notebooksForCurrentSection(appState);

    final sidebar = _buildSidebar(context, appState, closeDrawer: !isWide);

    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isSelectionMode) {
          _exitSelectionMode();
        }
      },
      child: Scaffold(
        drawer: isWide || _isSelectionMode
            ? null
            : Drawer(width: 280, child: SafeArea(child: sidebar)),
        appBar: _isSelectionMode
            ? AppBar(
                leading: IconButton(
                  tooltip: 'Thoát chọn nhiều',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: _exitSelectionMode,
                ),
                title: Text('Đã chọn ${_selectedNotebookIds.length} sổ'),
                actions: [
                  TextButton.icon(
                    onPressed: visibleNotebooks.isEmpty
                        ? null
                        : () {
                            setState(() {
                              if (_selectedNotebookIds.length ==
                                  visibleNotebooks.length) {
                                _selectedNotebookIds.clear();
                              } else {
                                _selectedNotebookIds
                                  ..clear()
                                  ..addAll(visibleNotebooks.map((n) => n.id));
                              }
                            });
                          },
                    icon: Icon(
                      visibleNotebooks.isNotEmpty &&
                              _selectedNotebookIds.length ==
                                  visibleNotebooks.length
                          ? Icons.deselect_rounded
                          : Icons.select_all_rounded,
                      size: 19,
                    ),
                    label: Text(
                      visibleNotebooks.isNotEmpty &&
                              _selectedNotebookIds.length ==
                                  visibleNotebooks.length
                          ? 'Bỏ chọn'
                          : 'Chọn tất cả',
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              )
            : AppBar(
                titleSpacing: isWide ? 20 : 8,
                title: Text(_sectionTitle(appState)),
                actions: [
                  IconButton(
                    tooltip: 'Tìm kiếm',
                    icon: const Icon(Icons.search_rounded),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SearchScreen()),
                      );
                    },
                  ),
                  IconButton(
                    tooltip: isDark
                        ? 'Chuyển sang giao diện Sáng'
                        : 'Chuyển sang giao diện Tối',
                    icon: Icon(
                      isDark
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                    ),
                    onPressed: appState.toggleTheme,
                  ),
                  IconButton(
                    tooltip: 'Đồng bộ Google Drive',
                    icon: const Icon(Icons.cloud_sync_outlined),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const SyncSettingsScreen()),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ),
        body: Row(
          children: [
            if (isWide) ...[
              SizedBox(
                width: 268,
                child: Container(
                  color: isDark ? AppTheme.obsidianSurface : AppTheme.lightSurface,
                  child: sidebar,
                ),
              ),
              const VerticalDivider(width: 1),
            ],
            Expanded(
              child: _buildMainContent(context, appState),
            ),
          ],
        ),
        bottomNavigationBar: _isSelectionMode
            ? _buildSelectionBottomBar(context, appState, visibleNotebooks)
            : null,
      ),
    );
  }

  String _sectionTitle(AppState appState) {
    return switch (_section) {
      _LibrarySection.allNotes => 'Tất cả ghi chú',
      _LibrarySection.favorites => 'Ưa thích',
      _LibrarySection.locked => 'Ghi chú đã khóa',
      _LibrarySection.trash => 'Đã xóa gần đây',
      _LibrarySection.templates => 'Trung tâm mẫu giấy & bìa',
      _LibrarySection.folder =>
        appState.getFolderById(_selectedFolderId ?? '')?.name ?? 'Thư mục',
    };
  }

  Widget _buildSidebar(
    BuildContext context,
    AppState appState, {
    required bool closeDrawer,
  }) {
    final theme = Theme.of(context);
    final rootFolders = appState.getSubfolders(null);

    void select(_LibrarySection section, {String? folderId}) {
      _selectSection(section, folderId: folderId, popDrawer: closeDrawer);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 14),
          child: Text(
            'ChemNote',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
        ),
        _SidebarHeader(title: 'Ghi chú của tôi'),
        _SidebarTile(
          icon: Icons.menu_book_outlined,
          label: 'Tất cả ghi chú',
          count: appState.activeNotebooks.length,
          selected: _section == _LibrarySection.allNotes,
          onTap: () => select(_LibrarySection.allNotes),
        ),
        _SidebarTile(
          icon: Icons.star_outline_rounded,
          label: 'Ưa thích',
          count: appState.favoriteNotebooks.length,
          selected: _section == _LibrarySection.favorites,
          onTap: () => select(_LibrarySection.favorites),
        ),
        _SidebarTile(
          icon: Icons.lock_outline_rounded,
          label: 'Ghi chú đã khóa',
          count: appState.lockedNotebooks.length,
          selected: _section == _LibrarySection.locked,
          onTap: () => select(_LibrarySection.locked),
        ),
        _SidebarTile(
          icon: Icons.delete_outline_rounded,
          label: 'Đã xóa gần đây',
          count: appState.trashedNotebooks.length,
          selected: _section == _LibrarySection.trash,
          onTap: () => select(_LibrarySection.trash),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(child: _SidebarHeader(title: 'Thư mục')),
            IconButton(
              onPressed: () => _createFolder(
                context,
                parentId:
                    _section == _LibrarySection.folder ? _selectedFolderId : null,
              ),
              icon: const Icon(Icons.create_new_folder_outlined, size: 18),
              tooltip: 'Tạo thư mục mới',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        if (rootFolders.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              'Chưa có thư mục',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          ..._buildSidebarFolderTree(
            context,
            appState,
            parentId: null,
            depth: 0,
            onOpenFolder: (id) => select(_LibrarySection.folder, folderId: id),
          ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),
        _SidebarTile(
          icon: Icons.auto_awesome_mosaic_outlined,
          label: 'Trung tâm mẫu giấy & bìa',
          selected: _section == _LibrarySection.templates,
          onTap: () => select(_LibrarySection.templates),
        ),
        _SidebarTile(
          icon: Icons.cloud_done_outlined,
          label: 'Đồng bộ Google Drive',
          selected: false,
          onTap: () {
            if (closeDrawer && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SyncSettingsScreen()),
            );
          },
        ),
        _SidebarTile(
          icon: Icons.settings_outlined,
          label: 'Cài đặt & Cập nhật',
          selected: false,
          onTap: () {
            if (closeDrawer && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
            _showLibrarySettingsSheet(context);
          },
        ),
      ],
    );
  }

  List<Widget> _buildSidebarFolderTree(
    BuildContext context,
    AppState appState, {
    required String? parentId,
    required int depth,
    required void Function(String folderId) onOpenFolder,
  }) {
    final children = appState.getSubfolders(parentId);
    final widgets = <Widget>[];
    for (final folder in children) {
      final subFolders = appState.getSubfolders(folder.id);
      final hasChildren = subFolders.isNotEmpty;
      final isExpanded = _expandedFolderIds.contains(folder.id);
      final isSelected = _section == _LibrarySection.folder &&
          _selectedFolderId == folder.id;
      final totalCount = appState.getTotalNotebookCountInFolder(folder.id);

      widgets.add(
        _SidebarTile(
          icon: isSelected || isExpanded
              ? Icons.folder_open_rounded
              : Icons.folder_rounded,
          iconColor: Color(folder.colorValue),
          label: folder.name,
          count: totalCount,
          indentLevel: depth,
          hasChildren: hasChildren,
          isExpanded: isExpanded,
          onToggleExpand: hasChildren
              ? () {
                  setState(() {
                    if (!_expandedFolderIds.remove(folder.id)) {
                      _expandedFolderIds.add(folder.id);
                    }
                  });
                }
              : null,
          selected: isSelected,
          onTap: () => onOpenFolder(folder.id),
          onLongPress: () => _showFolderOptions(context, folder),
        ),
      );
      if (hasChildren && isExpanded && depth < 6) {
        widgets.addAll(
          _buildSidebarFolderTree(
            context,
            appState,
            parentId: folder.id,
            depth: depth + 1,
            onOpenFolder: onOpenFolder,
          ),
        );
      }
    }
    return widgets;
  }

  void _showLibrarySettingsSheet(BuildContext context) {
    bool checkingUpdate = false;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final state = ctx.watch<AppState>();
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10, left: 4),
                    child: Text(
                      'Cài đặt ChemNote',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    secondary: Icon(
                      state.isDarkMode
                          ? Icons.dark_mode_outlined
                          : Icons.light_mode_outlined,
                    ),
                    title: const Text('Giao diện Tối (Obsidian Dark)'),
                    subtitle: Text(
                      state.isDarkMode ? 'Đang bật chế độ tối' : 'Đang bật chế độ sáng',
                    ),
                    value: state.isDarkMode,
                    onChanged: (val) => state.setDarkMode(val),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.speed_outlined, size: 22),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Text(
                                'Tốc độ lướt trang',
                                style: TextStyle(fontSize: 15),
                              ),
                            ),
                            Text(
                              '${state.scrollSpeedMultiplier.toStringAsFixed(1)}×',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.accentBlue,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: state.scrollSpeedMultiplier.clamp(1.0, 25.0),
                          min: 1.0,
                          max: 25.0,
                          divisions: 24,
                          onChanged: (val) => state.setScrollSpeedMultiplier(val),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: const Icon(Icons.folder_open_outlined),
                    title: const Text('Thư mục xuất PDF mặc định'),
                    subtitle: Text(
                      state.pdfExportDirectory ?? 'Documents/ChemNote',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: state.pdfExportDirectory != null
                        ? IconButton(
                            tooltip: 'Đặt lại mặc định',
                            icon: const Icon(Icons.restart_alt_rounded, size: 20),
                            onPressed: () => state.setPdfExportDirectory(null),
                          )
                        : const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      final dir = await FilePicker.platform.getDirectoryPath();
                      if (dir != null && dir.trim().isNotEmpty) {
                        state.setPdfExportDirectory(dir);
                      }
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: const Icon(Icons.drive_folder_upload_outlined),
                    title: const Text('Thư mục nhập tệp mặc định'),
                    subtitle: Text(
                      state.defaultImportDirectory ?? 'Download',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: state.defaultImportDirectory != null
                        ? IconButton(
                            tooltip: 'Đặt lại về Download',
                            icon: const Icon(Icons.restart_alt_rounded, size: 20),
                            onPressed: () =>
                                state.setDefaultImportDirectory(null),
                          )
                        : const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      final dir = await FilePicker.platform.getDirectoryPath();
                      if (dir != null && dir.trim().isNotEmpty) {
                        state.setDefaultImportDirectory(dir);
                      }
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: checkingUpdate
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.system_update_outlined),
                    title: const Text('Kiểm tra cập nhật APK'),
                    subtitle: const Text('Phiên bản hiện tại: v$kAppVersion'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: checkingUpdate
                        ? null
                        : () async {
                            setSheetState(() => checkingUpdate = true);
                            final info = await AppUpdaterService.checkForUpdate();
                            if (!ctx.mounted) return;
                            setSheetState(() => checkingUpdate = false);
                            if (info.errorMessage != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(info.errorMessage!)),
                              );
                            } else if (info.hasUpdate) {
                              Navigator.of(ctx).pop();
                              await AppUpdaterService.openDownloadUrl(
                                info.downloadUrl,
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Bạn đang dùng phiên bản mới nhất (v$kAppVersion).',
                                  ),
                                ),
                              );
                            }
                          },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMainContent(BuildContext context, AppState appState) {
    if (appState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_section == _LibrarySection.templates) {
      return _buildTemplateCenter(context, appState);
    }

    final List<Notebook> notebooks = _notebooksForCurrentSection(appState);
    final bool isFolderView = _section == _LibrarySection.folder;
    final List<Folder> visibleFolders = _isSelectionMode
        ? const <Folder>[]
        : isFolderView
            ? appState.getSubfolders(_selectedFolderId)
            : (_section == _LibrarySection.allNotes
                ? appState.getSubfolders(null)
                : const <Folder>[]);

    final bool showAddTile = (_section == _LibrarySection.allNotes ||
            _section == _LibrarySection.folder) &&
        !_isSelectionMode;

    final Widget? headerSection = _buildLibraryHeaderSection(
      context,
      appState,
      notebooks: notebooks,
      visibleFolders: visibleFolders,
    );

    if (!showAddTile && notebooks.isEmpty && visibleFolders.isEmpty && !isFolderView) {
      return _buildEmptySection(context);
    }

    return _buildBookshelfGrid(
      context,
      notebooks: notebooks,
      showAddTile: showAddTile,
      isTrash: _section == _LibrarySection.trash,
      headerSection: headerSection,
      emptyFolderHint: isFolderView && !showAddTile && notebooks.isEmpty,
    );
  }

  Widget? _buildLibraryHeaderSection(
    BuildContext context,
    AppState appState, {
    required List<Notebook> notebooks,
    required List<Folder> visibleFolders,
  }) {
    final bool hasTrashBar =
        _section == _LibrarySection.trash && notebooks.isNotEmpty;
    final bool isFolderView = _section == _LibrarySection.folder;
    final bool hasFolders = visibleFolders.isNotEmpty;
    if (!hasTrashBar && !isFolderView && !hasFolders) return null;

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final folderPath = isFolderView && _selectedFolderId != null
        ? appState.getFolderPath(_selectedFolderId!)
        : const <Folder>[];
    final currentFolder = folderPath.isNotEmpty ? folderPath.last : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasTrashBar)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            color:
                theme.colorScheme.errorContainer.withValues(alpha: 0.25),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Các sổ tay trong thùng rác có thể khôi phục hoặc xóa vĩnh viễn.',
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final ok = await _confirmDialog(
                      context,
                      'Dọn sạch thùng rác?',
                      'Tất cả ${notebooks.length} sổ tay sẽ bị xóa vĩnh viễn.',
                      confirmLabel: 'Xóa tất cả',
                      isDestructive: true,
                    );
                    if (ok == true) {
                      await appState.emptyTrash();
                      if (context.mounted) {
                        final syncManager = context.read<SyncManager>();
                        if (syncManager.isSignedIn &&
                            (syncManager.isOnline || syncManager.isDemoMode)) {
                          unawaited(syncManager.syncNow(isManualSync: true));
                        }
                      }
                    }
                  },
                  icon: const Icon(Icons.delete_forever_outlined, size: 18),
                  label: const Text('Dọn thùng rác'),
                ),
              ],
            ),
          ),
        if (isFolderView && currentFolder != null)
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        InkWell(
                          onTap: () =>
                              _selectSection(_LibrarySection.allNotes),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 5),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.home_outlined,
                                  size: 16,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'Tất cả ghi chú',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        for (int i = 0; i < folderPath.length; i++) ...[
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          () {
                            final crumb = folderPath[i];
                            final bool isCurrent = i == folderPath.length - 1;
                            return InkWell(
                              onTap: isCurrent
                                  ? null
                                  : () => _selectSection(
                                        _LibrarySection.folder,
                                        folderId: crumb.id,
                                      ),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 9, vertical: 5),
                                decoration: isCurrent
                                    ? BoxDecoration(
                                        color: Color(crumb.colorValue)
                                            .withValues(alpha: 0.14),
                                        borderRadius: BorderRadius.circular(8),
                                      )
                                    : null,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.folder_rounded,
                                      size: 15,
                                      color: Color(crumb.colorValue),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      crumb.name,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        fontWeight: isCurrent
                                            ? FontWeight.w700
                                            : FontWeight.w600,
                                        color: isCurrent
                                            ? Color(crumb.colorValue)
                                            : theme
                                                .colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }(),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () =>
                      _createFolder(context, parentId: currentFolder.id),
                  icon: const Icon(Icons.create_new_folder_outlined, size: 17),
                  label: const Text('Thư mục con'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                  ),
                ),
                IconButton(
                  tooltip: 'Tùy chọn thư mục',
                  icon: const Icon(Icons.more_horiz_rounded),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _showFolderOptions(context, currentFolder),
                ),
              ],
            ),
          ),
        if (hasFolders)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isFolderView ? 'Thư mục con' : 'Thư mục',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    if (!isFolderView)
                      TextButton.icon(
                        onPressed: () => _createFolder(context),
                        icon: const Icon(Icons.create_new_folder_outlined,
                            size: 16),
                        label: const Text('Tạo thư mục'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (ctx, box) {
                    final int cols =
                        (box.maxWidth / 225).floor().clamp(1, 5);
                    final double itemW =
                        (box.maxWidth - (cols - 1) * 12) / cols;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final folder in visibleFolders)
                          SizedBox(
                            width: itemW,
                            child: _FolderShelfCard(
                              folder: folder,
                              subFolderCount:
                                  appState.getSubfolders(folder.id).length,
                              notebookCount: appState
                                  .getTotalNotebookCountInFolder(folder.id),
                              isDark: isDark,
                              onTap: () => _selectSection(
                                _LibrarySection.folder,
                                folderId: folder.id,
                              ),
                              onMorePressed: () =>
                                  _showFolderOptions(context, folder),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
      ],
    );
  }

  /// Kệ sách Huawei Notes × GoodNotes 6 với thanh kệ nổi tinh tế dưới mỗi hàng sổ tay.
  Widget _buildBookshelfGrid(
    BuildContext context, {
    required List<Notebook> notebooks,
    required bool showAddTile,
    required bool isTrash,
    Widget? headerSection,
    bool emptyFolderHint = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalItems = notebooks.length + (showAddTile ? 1 : 0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth - 40;
        final crossAxisCount = (availableWidth / 172).floor().clamp(2, 6);
        final rowCount = totalItems == 0
            ? 0
            : (totalItems / crossAxisCount).ceil();

        return CustomScrollView(
          slivers: [
            if (headerSection != null)
              SliverToBoxAdapter(child: headerSection),
            if (rowCount == 0 && emptyFolderHint)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 36),
                  child: Center(
                    child: Text(
                      'Chưa có sổ tay nào trực tiếp trong thư mục này.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                  ),
                ),
              ),
            if (rowCount > 0)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 48),
                sliver: SliverList.builder(
                  itemCount: rowCount,
                  itemBuilder: (context, rowIndex) {
                    final start = rowIndex * crossAxisCount;
                    final end = (start + crossAxisCount).clamp(0, totalItems);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (int i = start;
                                i < start + crossAxisCount;
                                i++) ...[
                              Expanded(
                                child: i < end
                                    ? AspectRatio(
                                        aspectRatio: 0.68,
                                        child: _buildGridItem(
                                          context,
                                          itemIndex: i,
                                          showAddTile: showAddTile,
                                          notebooks: notebooks,
                                          isTrash: isTrash,
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                              if (i < start + crossAxisCount - 1)
                                const SizedBox(width: 18),
                            ],
                          ],
                        ),
                        // Thanh kệ sách nổi nhẹ dưới mỗi hàng
                        Container(
                          height: 8,
                          margin: const EdgeInsets.only(top: 8, bottom: 22),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: isDark
                                  ? const [
                                      Color(0xFF232732),
                                      Color(0xFF13151B),
                                    ]
                                  : const [
                                      Color(0xFFDFD9CC),
                                      Color(0xFFCCC4B5),
                                    ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black
                                    .withValues(alpha: isDark ? 0.35 : 0.08),
                                blurRadius: 6,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildGridItem(
    BuildContext context, {
    required int itemIndex,
    required bool showAddTile,
    required List<Notebook> notebooks,
    required bool isTrash,
  }) {
    if (showAddTile && itemIndex == 0) {
      return _NewNotebookTile(
        onTap: () => _showQuickAddMenu(context),
        onDoubleTap: () => _createQuickNote(context),
      );
    }

    final nb = notebooks[showAddTile ? itemIndex - 1 : itemIndex];
    final bool isSelected = _selectedNotebookIds.contains(nb.id);
    return NotebookCoverWidget(
      notebook: nb,
      selectionMode: _isSelectionMode,
      isSelected: isSelected,
      onTap: () {
        if (_isSelectionMode) {
          _toggleNotebookSelection(nb.id);
          return;
        }
        if (isTrash) {
          _showTrashNotebookOptions(context, nb);
        } else {
          _openNotebook(context, nb);
        }
      },
      onLongPress: () {
        if (_isSelectionMode) {
          _toggleNotebookSelection(nb.id);
        } else {
          _enterSelectionMode(nb.id);
        }
      },
      onMorePressed: () => isTrash
          ? _showTrashNotebookOptions(context, nb)
          : _showNotebookOptions(context, nb),
    );
  }

  Widget _buildSelectionBottomBar(
    BuildContext context,
    AppState appState,
    List<Notebook> visibleNotebooks,
  ) {
    final bool hasSelection = _selectedNotebookIds.isNotEmpty;
    final bool isTrash = _section == _LibrarySection.trash;
    final selectedList = visibleNotebooks
        .where((nb) => _selectedNotebookIds.contains(nb.id))
        .toList();
    final selectedIds = selectedList.map((n) => n.id).toList();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Widget actionBtn({
      required IconData icon,
      required String label,
      Color? color,
      required VoidCallback? onPressed,
    }) {
      final Color effectiveColor = !hasSelection
          ? theme.disabledColor
          : (color ?? theme.colorScheme.onSurface);
      return InkWell(
        onTap: hasSelection ? onPressed : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: effectiveColor),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: effectiveColor,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.obsidianSurface : AppTheme.lightSurface,
        border: Border(
          top: BorderSide(color: theme.dividerColor),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: isTrash
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    actionBtn(
                      icon: Icons.restore_rounded,
                      label: 'Khôi phục (${selectedIds.length})',
                      onPressed: () async {
                        await appState.restoreNotebooksFromTrash(selectedIds);
                        _exitSelectionMode();
                      },
                    ),
                    actionBtn(
                      icon: Icons.delete_forever_outlined,
                      label: 'Xóa vĩnh viễn (${selectedIds.length})',
                      color: Colors.redAccent,
                      onPressed: () =>
                          _batchDeleteNotebooks(context, selectedList, permanent: true),
                    ),
                  ],
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      actionBtn(
                        icon: Icons.drive_file_move_outlined,
                        label: 'Di chuyển',
                        onPressed: () =>
                            _batchMoveNotebooksDialog(context, selectedIds),
                      ),
                      const SizedBox(width: 6),
                      actionBtn(
                        icon: Icons.palette_outlined,
                        label: 'Đổi bìa',
                        onPressed: () =>
                            _batchChangeCoverSheet(context, selectedList),
                      ),
                      const SizedBox(width: 6),
                      actionBtn(
                        icon: Icons.copy_all_rounded,
                        label: 'Nhân bản',
                        onPressed: () async {
                          final copies =
                              await appState.duplicateNotebooks(selectedIds);
                          _exitSelectionMode();
                          if (context.mounted && copies.isNotEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Đã nhân bản ${copies.length} sổ tay.'),
                              ),
                            );
                          }
                        },
                      ),
                      const SizedBox(width: 6),
                      actionBtn(
                        icon: Icons.picture_as_pdf_outlined,
                        label: 'Xuất PDF',
                        onPressed: () =>
                            _batchExportPdfs(context, selectedList),
                      ),
                      const SizedBox(width: 6),
                      actionBtn(
                        icon: Icons.delete_outline_rounded,
                        label: 'Xóa',
                        color: Colors.redAccent,
                        onPressed: () =>
                            _batchDeleteNotebooks(context, selectedList, permanent: false),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildTemplateCenter(BuildContext context, AppState appState) {
    final templates = <(PaperTemplateType, String, String, IconData, int)>[
      (
        PaperTemplateType.sageRibbon,
        'Kẻ ngang ruy-băng xanh',
        'Giấy kẻ ngang viền xanh xô thơm kèm ruy-băng đánh dấu nhẹ nhàng',
        Icons.bookmark_border_rounded,
        0xFF6E7F68,
      ),
      (
        PaperTemplateType.pastelGrid,
        'Ô ly tiêu đề pastel',
        'Tiêu đề xanh tím pastel kèm khung Ngày / Chủ đề và lưới 5mm sắc nét',
        Icons.grid_on_rounded,
        0xFF6366F1,
      ),
      (
        PaperTemplateType.vintageCream,
        'Giấy cổ điển viền khung',
        'Nền kem ấm áp với khung viền đôi cổ điển và dòng kẻ nâu dịu mắt',
        Icons.auto_stories_outlined,
        0xFF9A6B3E,
      ),
      (
        PaperTemplateType.twoColumnStudy,
        'Chia 2 cột bài tập',
        'Bố cục chia đôi trang giúp trình bày Tóm tắt và Lời giải song song',
        Icons.view_column_outlined,
        0xFF2563EB,
      ),
      (
        PaperTemplateType.hexagonal,
        'Lưới lục giác Hóa hữu cơ',
        'Vẽ vòng benzen, cơ chế phản ứng và đồng phân lập thể chuẩn xác',
        Icons.hexagon_outlined,
        0xFF0F766E,
      ),
      (
        PaperTemplateType.cornell,
        'Ghi chú Cornell',
        'Cột từ khóa trái, nội dung chính phải và tóm tắt cuối trang',
        Icons.view_sidebar_outlined,
        0xFF1E3A5F,
      ),
      (
        PaperTemplateType.ruled,
        'Kẻ ngang cổ điển',
        'Ghi chép bài giảng lý thuyết gọn gàng, rõ ràng',
        Icons.subject_rounded,
        0xFF334155,
      ),
      (
        PaperTemplateType.grid,
        'Ô ly vuông 5mm',
        'Kẻ bảng số liệu, tính toán cân bằng và sơ đồ năng lượng',
        Icons.grid_4x4_rounded,
        0xFF4C1D95,
      ),
      (
        PaperTemplateType.dotted,
        'Chấm dot tối giản',
        'Linh hoạt vẽ sơ đồ tư duy và ghi chú tự do',
        Icons.grain_rounded,
        0xFF365314,
      ),
      (
        PaperTemplateType.blank,
        'Giấy trắng trơn',
        'Không gian phác thảo tự do và chèn slide bài giảng',
        Icons.crop_portrait_rounded,
        0xFF9F1239,
      ),
    ];

    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 280,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 1.45,
      ),
      itemCount: templates.length,
      itemBuilder: (context, index) {
        final item = templates[index];
        return Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () async {
              final nb = await appState.createNotebook(
                title: item.$2,
                coverStyle: 'molecular',
                coverColorValue: item.$5,
                defaultTemplate: item.$1,
              );
              if (!context.mounted) return;
              _openNotebook(context, nb);
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: Color(item.$5).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(item.$4, color: Color(item.$5), size: 22),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    item.$2,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Text(
                      item.$3,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptySection(BuildContext context) {
    final (IconData icon, String title, String subtitle) = switch (_section) {
      _LibrarySection.favorites => (
          Icons.star_outline_rounded,
          'Chưa có sổ tay ưa thích',
          'Nhấn dấu ba chấm trên bìa sổ để ghim vào danh sách Ưa thích.',
        ),
      _LibrarySection.locked => (
          Icons.lock_outline_rounded,
          'Chưa có sổ tay nào được khóa',
          'Bạn có thể đặt mã PIN bảo vệ cho sổ tay quan trọng.',
        ),
      _LibrarySection.trash => (
          Icons.delete_outline_rounded,
          'Thùng rác trống',
          'Các sổ tay đã xóa sẽ nằm ở đây trước khi xóa vĩnh viễn.',
        ),
      _ => (
          Icons.menu_book_outlined,
          'Chưa có sổ tay nào',
          'Tạo sổ tay mới để bắt đầu ghi chép.',
        ),
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 56,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.4),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openNotebook(BuildContext context, Notebook notebook) async {
    if (notebook.isLocked) {
      final unlocked = await _promptPinVerification(context, notebook);
      if (!unlocked || !context.mounted) return;
    }
    final appState = context.read<AppState>();
    appState.openTab(notebook.id);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(notebookId: notebook.id),
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 320), () {
      unawaited(appState.markNotebookOpened(notebook.id));
    });
  }

  Future<bool> _promptPinVerification(
    BuildContext context,
    Notebook notebook,
  ) async {
    final controller = TextEditingController();
    String? errorText;

    final verified = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.lock_outline_rounded, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Mở khóa "${notebook.title}"',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: InputDecoration(
              labelText: 'Nhập mã PIN',
              errorText: errorText,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () {
                if (AppState.verifyPin(controller.text, notebook.pinCode)) {
                  Navigator.of(ctx).pop(true);
                } else {
                  setDialogState(() => errorText = 'Mã PIN không chính xác');
                }
              },
              child: const Text('Mở khóa'),
            ),
          ],
        ),
      ),
    );

    controller.dispose();
    return verified == true;
  }

  Future<void> _createNotebook(BuildContext context) async {
    final result = await showDialog<CreateNotebookResult>(
      context: context,
      builder: (_) => const CreateNotebookDialog(),
    );
    if (result == null || !context.mounted) return;
    final appState = context.read<AppState>();
    final notebook = await appState.createNotebook(
      title: result.title,
      folderId: _section == _LibrarySection.folder ? _selectedFolderId : null,
      coverStyle: result.coverStyle,
      coverColorValue: result.coverColorValue,
      defaultTemplate: result.template,
      defaultPaperColor: result.paperColor,
      defaultOrientationLandscape: result.isLandscape,
      isWhiteboard: result.isWhiteboard,
      customCoverImagePath: result.customCoverImagePath,
      useFirstPageAsCover: result.useFirstPageAsCover,
    );
    if (!context.mounted) return;
    await _openNotebook(context, notebook);
  }

  Future<void> _createQuickNote(BuildContext context) async {
    final appState = context.read<AppState>();
    final now = DateTime.now();
    final nb = await appState.createNotebook(
      title:
          'Ghi chú ${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}',
      folderId: _section == _LibrarySection.folder ? _selectedFolderId : null,
      defaultTemplate: PaperTemplateType.sageRibbon,
      defaultPaperColor: PaperColorType.white,
    );
    if (!context.mounted) return;
    await _openNotebook(context, nb);
  }

  Future<void> _createQuickWhiteboard(BuildContext context) async {
    final appState = context.read<AppState>();
    final nb = await appState.createNotebook(
      title: 'Bảng vô cực Hóa học',
      folderId: _section == _LibrarySection.folder ? _selectedFolderId : null,
      defaultTemplate: PaperTemplateType.dotted,
      isWhiteboard: true,
    );
    if (!context.mounted) return;
    await _openNotebook(context, nb);
  }

  Future<void> _importImageAsNotebook(BuildContext context) async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null || !context.mounted) return;
      final appState = context.read<AppState>();
      final savedPath = await appState.storage.saveImportedFile(
        File(picked.path),
        subfolder: 'images',
      );
      appState.addRecentImagePath(savedPath);
      double w = 560.0;
      double h = 420.0;
      try {
        final bytes = await File(savedPath).readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        final img = frame.image;
        if (img.width > 0 && img.height > 0) {
          final double ratio = img.width / img.height;
          const double maxW = 620.0;
          const double maxH = 820.0;
          if (maxW / maxH >= ratio) {
            h = maxH;
            w = maxH * ratio;
          } else {
            w = maxW;
            h = maxW / ratio;
          }
        }
        img.dispose();
      } catch (_) {}
      final double x = ((794.0 - w) * 0.5).clamp(24.0, 740.0);
      final double y = ((1123.0 - h) * 0.5).clamp(40.0, 1040.0);
      final now = DateTime.now();
      final page = NotePage(
        id: const Uuid().v4(),
        index: 0,
        templateType: PaperTemplateType.blank,
        paperColor: PaperColorType.white,
        imageElements: [
          ImageElement(
            id: const Uuid().v4(),
            x: x,
            y: y,
            width: w,
            height: h,
            filePath: savedPath,
          ),
        ],
        updatedAt: now,
      );
      final nb = await appState.createNotebook(
        title: 'Ghi chú hình ảnh',
        folderId: _section == _LibrarySection.folder ? _selectedFolderId : null,
        initialPages: [page],
      );
      if (!context.mounted) return;
      await _openNotebook(context, nb);
    } catch (_) {}
  }

  Future<void> _importPdfAsNotebook(BuildContext context) async {
    final progressBar = PdfImportBottomProgressOverlay();
    try {
      final appState = context.read<AppState>();
      final result = await PdfImportService().pickAndImportPdf(
        initialDirectory: appState.defaultImportDirectory,
        onProgress: (current, total, stage) {
          if (!context.mounted) return;
          progressBar.show(context, title: 'Đang nhập tệp PDF');
          progressBar.update(current, total, stage);
        },
      );
      progressBar.hide();
      if (result == null || result.pages.isEmpty || !context.mounted) return;
      final nb = await appState.createNotebook(
        title: result.suggestedTitle,
        folderId: _section == _LibrarySection.folder ? _selectedFolderId : null,
        initialPages: result.pages,
      );
      if (!context.mounted) return;
      await _openNotebook(context, nb);
    } catch (e) {
      progressBar.hide();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thể nhập PDF: $e')),
      );
    } finally {
      progressBar.hide();
    }
  }

  Future<void> _importDocPptAsNotebook(BuildContext context) async {
    final progressBar = PdfImportBottomProgressOverlay();
    try {
      final appState = context.read<AppState>();
      final result = await PdfImportService().pickAndImportDocx(
        initialDirectory: appState.defaultImportDirectory,
        onProgress: (current, total, stage) {
          if (!context.mounted) return;
          progressBar.show(context, title: 'Đang nhập tài liệu Word/PPT');
          progressBar.update(current, total, stage);
        },
      );
      progressBar.hide();
      if (result == null || result.pages.isEmpty || !context.mounted) return;
      final nb = await appState.createNotebook(
        title: result.suggestedTitle,
        folderId: _section == _LibrarySection.folder ? _selectedFolderId : null,
        initialPages: result.pages,
      );
      if (!context.mounted) return;
      await _openNotebook(context, nb);
    } catch (e) {
      progressBar.hide();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thể nhập tài liệu Word/PPT: $e')),
      );
    } finally {
      progressBar.hide();
    }
  }

  void _showQuickAddMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.note_add_outlined),
              title: const Text('Ghi chú mới'),
              subtitle: const Text('Chọn bìa cá nhân & mẫu giấy học thuật'),
              onTap: () {
                Navigator.of(ctx).pop();
                _createNotebook(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.all_inclusive_rounded),
              title: const Text('Bảng vô cực mới'),
              subtitle: const Text('Không gian 6000×6000 vẽ sơ đồ không giới hạn'),
              onTap: () {
                Navigator.of(ctx).pop();
                _createQuickWhiteboard(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('Thư mục mới'),
              onTap: () {
                Navigator.of(ctx).pop();
                _createFolder(
                  context,
                  parentId: _section == _LibrarySection.folder
                      ? _selectedFolderId
                      : null,
                );
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Nhập hình ảnh'),
              onTap: () {
                Navigator.of(ctx).pop();
                _importImageAsNotebook(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Nhập tệp tin PDF'),
              onTap: () {
                Navigator.of(ctx).pop();
                _importPdfAsNotebook(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Nhập DOC/PPT'),
              onTap: () {
                Navigator.of(ctx).pop();
                _importDocPptAsNotebook(context);
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                "Chạm đúp vào '+' để tạo nhanh ghi chú mới.",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createFolder(
    BuildContext context, {
    String? parentId,
  }) async {
    final controller = TextEditingController();
    int selectedColor = AppTheme.folderColors.first;
    final parentFolder = parentId != null
        ? context.read<AppState>().getFolderById(parentId)
        : null;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            parentFolder != null
                ? 'Tạo thư mục con'
                : 'Tạo thư mục mới',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (parentFolder != null) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: Color(parentFolder.colorValue)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.folder_rounded,
                        size: 16,
                        color: Color(parentFolder.colorValue),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Bên trong: ${parentFolder.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Tên thư mục',
                  hintText: 'VD: Chương 1 - Đại cương',
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                children: AppTheme.folderColors.map((colorVal) {
                  final selected = selectedColor == colorVal;
                  return GestureDetector(
                    onTap: () =>
                        setDialogState(() => selectedColor = colorVal),
                    child: CircleAvatar(
                      radius: 15,
                      backgroundColor: Color(colorVal),
                      child: selected
                          ? const Icon(Icons.check, size: 16, color: Colors.white)
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Tạo'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && context.mounted) {
      await context.read<AppState>().createFolder(
            name: controller.text,
            parentId: parentId,
            colorValue: selectedColor,
          );
      if (parentId != null && mounted) {
        setState(() => _expandedFolderIds.add(parentId));
      }
    }
    controller.dispose();
  }

  void _showNotebookOptions(BuildContext context, Notebook notebook) {
    final appState = context.read<AppState>();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                notebook.isFavorite
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                color: notebook.isFavorite ? const Color(0xFFFBBF24) : null,
              ),
              title: Text(
                notebook.isFavorite ? 'Bỏ khỏi Ưa thích' : 'Thêm vào Ưa thích',
              ),
              onTap: () async {
                Navigator.of(ctx).pop();
                await appState.toggleFavorite(notebook.id);
              },
            ),
            ListTile(
              leading: Icon(
                notebook.isLocked
                    ? Icons.lock_open_rounded
                    : Icons.lock_outline_rounded,
              ),
              title: Text(
                notebook.isLocked ? 'Gỡ khóa mã PIN' : 'Khóa sổ tay bằng mã PIN',
              ),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _toggleNotebookLockDialog(context, notebook);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Đổi tên sổ tay'),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _renameNotebook(context, notebook);
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outlined),
              title: const Text('Di chuyển sang thư mục khác'),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _moveNotebookDialog(context, notebook);
              },
            ),
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const Text('Sao chép link PDF Google Drive'),
              subtitle: Text(
                notebook.drivePdfFileId != null &&
                        notebook.drivePdfFileId!.isNotEmpty
                    ? 'Đã có bản PDF trên Google Drive'
                    : 'Tạo & tải PDF lên Drive nếu chưa có',
              ),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _copyNotebookDrivePdfLink(context, notebook);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              title: const Text(
                'Chuyển vào Thùng rác',
                style: TextStyle(color: Colors.redAccent),
              ),
              onTap: () async {
                Navigator.of(ctx).pop();
                await appState.moveToTrash(notebook.id);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _copyNotebookDrivePdfLink(
    BuildContext context,
    Notebook notebook,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final syncManager = context.read<SyncManager>();
    final hasCachedPdf = notebook.drivePdfFileId != null &&
        notebook.drivePdfFileId!.trim().isNotEmpty;

    if (!hasCachedPdf) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Đang tạo & tải PDF lên Google Drive để lấy link...'),
          duration: Duration(seconds: 3),
        ),
      );
    }

    try {
      final url = await syncManager.getOrUploadNotebookPdfDriveLink(notebook);
      await Clipboard.setData(ClipboardData(text: url));
      if (!context.mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Đã sao chép link PDF Google Drive: $url'),
          ),
        );
    } catch (e) {
      if (!context.mounted) return;
      final message = e is StateError ? e.message : 'Không lấy được link PDF: $e';
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _showTrashNotebookOptions(BuildContext context, Notebook notebook) {
    final appState = context.read<AppState>();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.restore_rounded),
              title: const Text('Khôi phục sổ tay'),
              onTap: () async {
                Navigator.of(ctx).pop();
                await appState.restoreFromTrash(notebook.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever_outlined, color: Colors.redAccent),
              title: const Text(
                'Xóa vĩnh viễn',
                style: TextStyle(color: Colors.redAccent),
              ),
              onTap: () async {
                Navigator.of(ctx).pop();
                final ok = await _confirmDialog(
                  context,
                  'Xóa vĩnh viễn "${notebook.title}"?',
                  'Hành động này không thể hoàn tác.',
                  confirmLabel: 'Xóa vĩnh viễn',
                  isDestructive: true,
                );
                if (ok == true) {
                  await appState.deleteNotebook(notebook.id);
                  if (context.mounted) {
                    final syncManager = context.read<SyncManager>();
                    if (syncManager.isSignedIn &&
                        (syncManager.isOnline || syncManager.isDemoMode)) {
                      unawaited(syncManager.syncNow(isManualSync: true));
                    }
                  }
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleNotebookLockDialog(
    BuildContext context,
    Notebook notebook,
  ) async {
    final appState = context.read<AppState>();
    if (notebook.isLocked) {
      final ok = await _promptPinVerification(context, notebook);
      if (ok) {
        await appState.setNotebookLock(notebook.id, isLocked: false);
      }
      return;
    }

    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đặt mã PIN khóa sổ'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: 'Mã PIN (4-6 chữ số)',
            hintText: 'VD: 1234',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Khóa sổ'),
          ),
        ],
      ),
    );

    if (ok == true && controller.text.trim().length >= 4) {
      await appState.setNotebookLock(
        notebook.id,
        isLocked: true,
        pinCode: controller.text.trim(),
      );
    }
    controller.dispose();
  }

  Future<void> _renameNotebook(BuildContext context, Notebook notebook) async {
    final controller = TextEditingController(text: notebook.title);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đổi tên sổ tay'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Tên mới'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (ok == true && controller.text.trim().isNotEmpty && context.mounted) {
      await context.read<AppState>().updateNotebook(
            notebook.copyWith(title: controller.text.trim()),
          );
    }
    controller.dispose();
  }

  Future<({bool picked, String? folderId})> _pickTargetFolderDialog(
    BuildContext context, {
    required String title,
    String? currentFolderId,
    Set<String> excludedFolderIds = const <String>{},
  }) async {
    final appState = context.read<AppState>();
    final flattened = <({Folder folder, int depth})>[];
    void appendChildren(String? parentId, int depth) {
      for (final f in appState.getSubfolders(parentId)) {
        if (excludedFolderIds.contains(f.id)) continue;
        flattened.add((folder: f, depth: depth));
        if (depth < 6) {
          appendChildren(f.id, depth + 1);
        }
      }
    }

    appendChildren(null, 0);

    final result = await showDialog<({bool picked, String? folderId})>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 360,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 380),
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  leading: const Icon(Icons.home_outlined),
                  title: const Text('Thư mục gốc'),
                  selected: currentFolderId == null,
                  onTap: () => Navigator.of(ctx).pop(
                    (picked: true, folderId: null),
                  ),
                ),
                for (final entry in flattened)
                  ListTile(
                    contentPadding: EdgeInsets.only(
                      left: 16.0 + entry.depth * 18.0,
                      right: 16.0,
                    ),
                    leading: Icon(
                      Icons.folder_rounded,
                      color: Color(entry.folder.colorValue),
                    ),
                    title: Text(
                      entry.folder.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    selected: currentFolderId == entry.folder.id,
                    onTap: () => Navigator.of(ctx).pop(
                      (picked: true, folderId: entry.folder.id),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop((picked: false, folderId: null)),
            child: const Text('Hủy'),
          ),
        ],
      ),
    );
    return result ?? (picked: false, folderId: null);
  }

  Future<void> _moveNotebookDialog(
    BuildContext context,
    Notebook notebook,
  ) async {
    final choice = await _pickTargetFolderDialog(
      context,
      title: 'Chọn thư mục đích',
      currentFolderId: notebook.folderId,
    );
    if (!choice.picked || !context.mounted) return;
    await context.read<AppState>().moveNotebook(notebook.id, choice.folderId);
  }

  Future<void> _batchMoveNotebooksDialog(
    BuildContext context,
    List<String> notebookIds,
  ) async {
    if (notebookIds.isEmpty) return;
    final choice = await _pickTargetFolderDialog(
      context,
      title: 'Di chuyển ${notebookIds.length} sổ tay vào thư mục',
    );
    if (!choice.picked || !context.mounted) return;
    await context.read<AppState>().moveNotebooks(notebookIds, choice.folderId);
    _exitSelectionMode();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã di chuyển ${notebookIds.length} sổ tay.')),
      );
    }
  }

  Future<void> _batchChangeCoverSheet(
    BuildContext context,
    List<Notebook> selected,
  ) async {
    if (selected.isEmpty) return;
    final appState = context.read<AppState>();
    int selectedColor = selected.first.coverColorValue;
    String selectedStyle = selected.first.coverStyle;
    String? customCoverPath;
    bool useFirstPage = false;

    const styles = <(String, String)>[
      ('molecular', 'Phân tử'),
      ('lab', 'Ô phòng lab'),
      ('classic', 'Cổ điển'),
      ('gradient', 'Chuyển sắc'),
    ];

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final state = ctx.watch<AppState>();
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Đổi bìa cho ${selected.length} sổ tay',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Dùng trang đầu tiên làm bìa'),
                    value: useFirstPage,
                    onChanged: (v) => setSheetState(() {
                      useFirstPage = v;
                      if (v) customCoverPath = null;
                    }),
                  ),
                  if (!useFirstPage) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Màu & họa tiết bìa',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: AppTheme.notebookCoverColors.map((colorVal) {
                        final isChosen = customCoverPath == null &&
                            selectedColor == colorVal;
                        return GestureDetector(
                          onTap: () => setSheetState(() {
                            customCoverPath = null;
                            selectedColor = colorVal;
                          }),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: Color(colorVal),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isChosen
                                    ? AppTheme.accentBlue
                                    : Colors.black26,
                                width: isChosen ? 2.6 : 1,
                              ),
                            ),
                            child: isChosen
                                ? const Icon(Icons.check,
                                    size: 16, color: Colors.white)
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final item in styles)
                          ChoiceChip(
                            label: Text(item.$2),
                            selected: customCoverPath == null &&
                                selectedStyle == item.$1,
                            onSelected: (_) => setSheetState(() {
                              customCoverPath = null;
                              selectedStyle = item.$1;
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          final picked = await ImagePicker()
                              .pickImage(source: ImageSource.gallery);
                          if (picked == null) return;
                          final savedPath =
                              await appState.storage.saveImportedFile(
                            File(picked.path),
                            subfolder: 'covers',
                          );
                          appState.addCustomCoverPath(savedPath);
                          setSheetState(() {
                            customCoverPath = savedPath;
                            useFirstPage = false;
                          });
                        } catch (_) {}
                      },
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(
                        customCoverPath != null
                            ? 'Đã chọn ảnh bìa cá nhân (nhấn để đổi)'
                            : 'Chọn ảnh bìa từ thư viện ảnh',
                      ),
                    ),
                    if (state.customCoverPaths.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 64,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: state.customCoverPaths.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, idx) {
                            final path = state.customCoverPaths[idx];
                            final active = customCoverPath == path;
                            return GestureDetector(
                              onTap: () => setSheetState(() {
                                customCoverPath = path;
                                useFirstPage = false;
                              }),
                              child: Container(
                                width: 48,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: active
                                        ? AppTheme.accentBlue
                                        : Colors.transparent,
                                    width: 2.2,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.file(
                                    File(path),
                                    fit: BoxFit.cover,
                                    cacheWidth: 160,
                                    errorBuilder: (_, __, ___) =>
                                        const Icon(Icons.broken_image_outlined),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Áp dụng cho các sổ đã chọn'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (confirmed != true || !context.mounted) return;
    final ids = selected.map((n) => n.id).toList();
    if (useFirstPage) {
      await appState.updateNotebooksCover(
        ids,
        clearCustomCoverImagePath: true,
        useFirstPageAsCover: true,
      );
    } else if (customCoverPath != null && customCoverPath!.isNotEmpty) {
      await appState.updateNotebooksCover(
        ids,
        customCoverImagePath: customCoverPath,
        useFirstPageAsCover: false,
      );
    } else {
      await appState.updateNotebooksCover(
        ids,
        coverStyle: selectedStyle,
        coverColorValue: selectedColor,
        clearCustomCoverImagePath: true,
        useFirstPageAsCover: false,
      );
    }
    _exitSelectionMode();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã đổi bìa cho ${ids.length} sổ tay.')),
      );
    }
  }

  Future<void> _batchExportPdfs(
    BuildContext context,
    List<Notebook> selected,
  ) async {
    if (selected.isEmpty) return;
    final mode = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                'Xuất ${selected.length} sổ tay ra PDF',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.save_alt_rounded),
              title: const Text('Lưu tất cả PDF vào bộ nhớ máy'),
              onTap: () => Navigator.of(ctx).pop('save'),
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Xuất & Chia sẻ tất cả PDF'),
              onTap: () => Navigator.of(ctx).pop('share'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (mode == null || !context.mounted) return;

    final appState = context.read<AppState>();
    final exportService = PdfExportService();
    final progressNotifier = ValueNotifier<
        ({int nbIdx, int totalNb, String title, int page, int totalPages, String stage})>(
      (
        nbIdx: 1,
        totalNb: selected.length,
        title: selected.first.title,
        page: 1,
        totalPages: math.max(1, selected.first.pages.length),
        stage: 'Đang chuẩn bị...',
      ),
    );

    bool dialogOpen = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dCtx) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('Đang xuất PDF đồng loạt'),
            content: ValueListenableBuilder(
              valueListenable: progressNotifier,
              builder: (_, p, __) {
                final double frac = p.totalNb <= 0
                    ? 0.0
                    : (((p.nbIdx - 1) +
                                (p.totalPages > 0 ? p.page / p.totalPages : 0.0)) /
                            p.totalNb)
                        .clamp(0.0, 1.0);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sổ ${p.nbIdx}/${p.totalNb}: ${p.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: frac),
                    const SizedBox(height: 8),
                    Text(p.stage, style: const TextStyle(fontSize: 12.5)),
                  ],
                );
              },
            ),
          ),
        ),
      ).whenComplete(() => dialogOpen = false),
    );

    final exportedFiles = <File>[];
    final errors = <String>[];
    try {
      for (int i = 0; i < selected.length; i++) {
        final nb = selected[i];
        progressNotifier.value = (
          nbIdx: i + 1,
          totalNb: selected.length,
          title: nb.title,
          page: 1,
          totalPages: math.max(1, nb.pages.length),
          stage: 'Đang khởi tạo...',
        );
        try {
          final f = await exportService.exportNotebookToFile(
            nb,
            customDirectory: appState.pdfExportDirectory,
            onProgress: (cur, total, stage) {
              progressNotifier.value = (
                nbIdx: i + 1,
                totalNb: selected.length,
                title: nb.title,
                page: cur,
                totalPages: math.max(1, total),
                stage: stage,
              );
            },
          );
          exportedFiles.add(f);
        } catch (e) {
          errors.add('${nb.title}: $e');
        }
      }
    } finally {
      if (dialogOpen && context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      progressNotifier.dispose();
    }

    if (!context.mounted) return;
    _exitSelectionMode();
    if (exportedFiles.isNotEmpty) {
      if (mode == 'share') {
        await Share.shareXFiles(
          exportedFiles.map((f) => XFile(f.path)).toList(),
          subject: 'ChemNote (${exportedFiles.length} PDF)',
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Đã xuất ${exportedFiles.length} PDF vào: ${exportedFiles.first.parent.path}',
            ),
          ),
        );
      }
    }
    if (errors.isNotEmpty && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Một số sổ chưa xuất được: ${errors.first}')),
      );
    }
  }

  Future<void> _batchDeleteNotebooks(
    BuildContext context,
    List<Notebook> selected, {
    required bool permanent,
  }) async {
    if (selected.isEmpty) return;
    final ok = await _confirmDialog(
      context,
      permanent
          ? 'Xóa vĩnh viễn ${selected.length} sổ tay?'
          : 'Chuyển ${selected.length} sổ tay vào Thùng rác?',
      permanent
          ? 'Hành động này không thể hoàn tác.'
          : 'Bạn có thể khôi phục lại trong Thùng rác.',
      confirmLabel: permanent ? 'Xóa vĩnh viễn' : 'Chuyển vào Thùng rác',
      isDestructive: true,
    );
    if (ok != true || !context.mounted) return;
    final appState = context.read<AppState>();
    final ids = selected.map((n) => n.id).toList();
    if (permanent) {
      await appState.deleteNotebooks(ids);
      if (context.mounted) {
        final syncManager = context.read<SyncManager>();
        if (syncManager.isSignedIn &&
            (syncManager.isOnline || syncManager.isDemoMode)) {
          unawaited(syncManager.syncNow(isManualSync: true));
        }
      }
    } else {
      await appState.moveNotebooksToTrash(ids);
    }
    _exitSelectionMode();
  }

  void _showFolderOptions(BuildContext context, Folder folder) {
    final appState = context.read<AppState>();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('Tạo thư mục con'),
              onTap: () {
                Navigator.of(ctx).pop();
                _createFolder(context, parentId: folder.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Đổi tên & màu thư mục'),
              onTap: () async {
                Navigator.of(ctx).pop();
                final controller = TextEditingController(text: folder.name);
                int selectedColor = folder.colorValue;
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (dCtx) => StatefulBuilder(
                    builder: (dCtx, setDialogState) => AlertDialog(
                      title: const Text('Chỉnh sửa thư mục'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(controller: controller, autofocus: true),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 10,
                            children: AppTheme.folderColors.map((colorVal) {
                              final selected = selectedColor == colorVal;
                              return GestureDetector(
                                onTap: () => setDialogState(
                                    () => selectedColor = colorVal),
                                child: CircleAvatar(
                                  radius: 15,
                                  backgroundColor: Color(colorVal),
                                  child: selected
                                      ? const Icon(Icons.check,
                                          size: 16, color: Colors.white)
                                      : null,
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(dCtx).pop(false),
                          child: const Text('Hủy'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(dCtx).pop(true),
                          child: const Text('Lưu'),
                        ),
                      ],
                    ),
                  ),
                );
                if (ok == true && controller.text.trim().isNotEmpty) {
                  await appState.updateFolder(
                    folder.copyWith(
                      name: controller.text.trim(),
                      colorValue: selectedColor,
                    ),
                  );
                }
                controller.dispose();
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outlined),
              title: const Text('Di chuyển thư mục'),
              onTap: () async {
                Navigator.of(ctx).pop();
                final excluded = {
                  folder.id,
                  ...appState.getDescendantFolderIds(folder.id),
                };
                final choice = await _pickTargetFolderDialog(
                  context,
                  title: 'Di chuyển "${folder.name}" vào',
                  currentFolderId: folder.parentId,
                  excludedFolderIds: excluded,
                );
                if (choice.picked && context.mounted) {
                  await appState.moveFolder(folder.id, choice.folderId);
                  if (choice.folderId != null && mounted) {
                    setState(() => _expandedFolderIds.add(choice.folderId!));
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: Colors.redAccent),
              title: const Text(
                'Xóa thư mục',
                style: TextStyle(color: Colors.redAccent),
              ),
              subtitle: const Text(
                'Thư mục con & sổ tay bên trong sẽ được giữ lại',
              ),
              onTap: () async {
                Navigator.of(ctx).pop();
                final ok = await _confirmDialog(
                  context,
                  'Xóa thư mục "${folder.name}"?',
                  'Thư mục con và sổ tay bên trong sẽ được chuyển lên cấp trên.',
                  confirmLabel: 'Xóa',
                  isDestructive: true,
                );
                if (ok == true) {
                  if (_selectedFolderId == folder.id) {
                    final String? nextParentId = folder.parentId;
                    setState(() {
                      if (nextParentId != null) {
                        _section = _LibrarySection.folder;
                        _selectedFolderId = nextParentId;
                      } else {
                        _section = _LibrarySection.allNotes;
                        _selectedFolderId = null;
                      }
                    });
                  }
                  await appState.deleteFolder(folder.id);
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<bool?> _confirmDialog(
    BuildContext context,
    String title,
    String message, {
    String confirmLabel = 'Xác nhận',
    bool isDestructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: isDestructive
                ? FilledButton.styleFrom(backgroundColor: Colors.redAccent)
                : null,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  final String title;

  const _SidebarHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
            ),
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;
  final int? count;
  final int indentLevel;
  final bool hasChildren;
  final bool isExpanded;
  final VoidCallback? onToggleExpand;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _SidebarTile({
    required this.icon,
    this.iconColor,
    required this.label,
    this.count,
    this.indentLevel = 0,
    this.hasChildren = false,
    this.isExpanded = false,
    this.onToggleExpand,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeBg = AppTheme.accentBlue.withValues(alpha: 0.16);
    final activeFg = AppTheme.accentBlue;
    final double leftPad = 10.0 + indentLevel * 14.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? activeBg : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: EdgeInsets.fromLTRB(leftPad, 8, 10, 8),
            child: Row(
              children: [
                if (hasChildren)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onToggleExpand,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.keyboard_arrow_right_rounded,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else if (indentLevel > 0)
                  const SizedBox(width: 22),
                Icon(
                  icon,
                  size: 19,
                  color: selected
                      ? activeFg
                      : (iconColor ?? theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? activeFg : null,
                    ),
                  ),
                ),
                if (count != null)
                  Text(
                    '$count',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: selected
                          ? activeFg
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FolderShelfCard extends StatelessWidget {
  final Folder folder;
  final int subFolderCount;
  final int notebookCount;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onMorePressed;

  const _FolderShelfCard({
    required this.folder,
    required this.subFolderCount,
    required this.notebookCount,
    required this.isDark,
    required this.onTap,
    required this.onMorePressed,
  });

  @override
  Widget build(BuildContext context) {
    final folderColor = Color(folder.colorValue);
    final theme = Theme.of(context);
    final bgColor =
        isDark ? AppTheme.obsidianCard : AppTheme.lightSurface;
    final subtitle = subFolderCount > 0
        ? '$subFolderCount thư mục con • $notebookCount sổ'
        : '$notebookCount sổ tay';

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        onLongPress: onMorePressed,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: folderColor.withValues(alpha: isDark ? 0.35 : 0.25),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: folderColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.folder_rounded,
                  color: folderColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      folder.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11.5,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onMorePressed,
                icon: const Icon(Icons.more_vert_rounded, size: 18),
                visualDensity: VisualDensity.compact,
                tooltip: 'Tùy chọn thư mục',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ô đầu tiên trên kệ sách: "+ Ghi chú mới" theo phong cách Huawei Notes.
class _NewNotebookTile extends StatelessWidget {
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;

  const _NewNotebookTile({
    required this.onTap,
    this.onDoubleTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Material(
              color: isDark
                  ? AppTheme.obsidianCard.withValues(alpha: 0.6)
                  : AppTheme.lightSurface,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: onTap,
                onDoubleTap: onDoubleTap,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.accentBlue.withValues(alpha: 0.45),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.accentBlue.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.add_rounded,
                          color: AppTheme.accentBlue,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Ghi chú mới',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppTheme.accentBlue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const SizedBox(height: 32),
      ],
    );
  }
}
