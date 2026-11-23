import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/drawing_elements.dart';
import '../../core/models/folder.dart';
import '../../core/models/notebook.dart';
import '../../core/providers/app_state.dart';
import '../../core/theme/app_theme.dart';
import '../canvas/note_editor_screen.dart';
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

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isWide = MediaQuery.sizeOf(context).width >= 820;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final sidebar = _buildSidebar(context, appState, closeDrawer: !isWide);

    return Scaffold(
      drawer: isWide ? null : Drawer(width: 280, child: SafeArea(child: sidebar)),
      appBar: AppBar(
        titleSpacing: isWide ? 20 : 8,
        title: Row(
          children: [
            if (!isWide) ...[
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.accentBlue,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.science_outlined,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Text(_sectionTitle(appState)),
          ],
        ),
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
            tooltip: isDark ? 'Chuyển sang giao diện Sáng' : 'Chuyển sang giao diện Tối',
            icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            ),
            onPressed: appState.toggleTheme,
          ),
          IconButton(
            tooltip: 'Đồng bộ Google Drive',
            icon: const Icon(Icons.cloud_sync_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SyncSettingsScreen()),
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
    final folders = appState.folders;

    void select(_LibrarySection section, {String? folderId}) {
      setState(() {
        _section = section;
        _selectedFolderId = folderId;
      });
      if (closeDrawer && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppTheme.accentBlue,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.science_outlined,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ChemNote',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    'MatePad 144Hz • Hóa học',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
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
              onPressed: () => _createFolder(context),
              icon: const Icon(Icons.create_new_folder_outlined, size: 18),
              tooltip: 'Tạo thư mục mới',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        if (folders.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              'Chưa có thư mục môn học',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final folder in folders)
            _SidebarTile(
              icon: Icons.folder_outlined,
              iconColor: Color(folder.colorValue),
              label: folder.name,
              count: appState.getNotebooksInFolder(folder.id).length,
              selected: _section == _LibrarySection.folder &&
                  _selectedFolderId == folder.id,
              onTap: () => select(_LibrarySection.folder, folderId: folder.id),
              onLongPress: () => _showFolderOptions(context, folder),
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
      ],
    );
  }

  Widget _buildMainContent(BuildContext context, AppState appState) {
    if (appState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_section == _LibrarySection.templates) {
      return _buildTemplateCenter(context, appState);
    }

    final List<Notebook> notebooks = switch (_section) {
      _LibrarySection.allNotes => appState.activeNotebooks,
      _LibrarySection.favorites => appState.favoriteNotebooks,
      _LibrarySection.locked => appState.lockedNotebooks,
      _LibrarySection.trash => appState.trashedNotebooks,
      _LibrarySection.folder => appState.getNotebooksInFolder(_selectedFolderId),
      _LibrarySection.templates => const [],
    };

    final showAddTile = _section == _LibrarySection.allNotes ||
        _section == _LibrarySection.folder;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_section == _LibrarySection.trash && notebooks.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.25),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Các sổ tay trong thùng rác có thể khôi phục hoặc xóa vĩnh viễn.'),
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
                    }
                  },
                  icon: const Icon(Icons.delete_forever_outlined, size: 18),
                  label: const Text('Dọn thùng rác'),
                ),
              ],
            ),
          ),
        Expanded(
          child: !showAddTile && notebooks.isEmpty
              ? _buildEmptySection(context)
              : _buildBookshelfGrid(
                  context,
                  notebooks: notebooks,
                  showAddTile: showAddTile,
                  isTrash: _section == _LibrarySection.trash,
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
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalItems = notebooks.length + (showAddTile ? 1 : 0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth - 40;
        final crossAxisCount = (availableWidth / 172).floor().clamp(2, 6);
        final rowCount = (totalItems / crossAxisCount).ceil();

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 48),
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
                    for (int i = start; i < start + crossAxisCount; i++) ...[
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
                          ? const [Color(0xFF232732), Color(0xFF13151B)]
                          : const [Color(0xFFE2E8F0), Color(0xFFCBD5E1)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
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
        onTap: () => _createNotebook(context),
      );
    }

    final nb = notebooks[showAddTile ? itemIndex - 1 : itemIndex];
    return NotebookCoverWidget(
      notebook: nb,
      onTap: () => isTrash
          ? _showTrashNotebookOptions(context, nb)
          : _openNotebook(context, nb),
      onLongPress: () => isTrash
          ? _showTrashNotebookOptions(context, nb)
          : _showNotebookOptions(context, nb),
      onMorePressed: () => isTrash
          ? _showTrashNotebookOptions(context, nb)
          : _showNotebookOptions(context, nb),
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
    context.read<AppState>().openTab(notebook.id);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(notebookId: notebook.id),
      ),
    );
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
    );
    if (!context.mounted) return;
    await _openNotebook(context, notebook);
  }

  Future<void> _createFolder(BuildContext context) async {
    final controller = TextEditingController();
    int selectedColor = AppTheme.folderColors.first;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Tạo thư mục mới'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Tên thư mục',
                  hintText: 'VD: Học kỳ 1 - Hóa Hữu Cơ',
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
            colorValue: selectedColor,
          );
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

  Future<void> _moveNotebookDialog(
    BuildContext context,
    Notebook notebook,
  ) async {
    final appState = context.read<AppState>();
    final folders = appState.folders;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chọn thư mục đích'),
        content: SizedBox(
          width: 340,
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: const Text('Thư mục gốc'),
                selected: notebook.folderId == null,
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await appState.moveNotebook(notebook.id, null);
                },
              ),
              for (final folder in folders)
                ListTile(
                  leading: Icon(
                    Icons.folder_rounded,
                    color: Color(folder.colorValue),
                  ),
                  title: Text(folder.name),
                  selected: notebook.folderId == folder.id,
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await appState.moveNotebook(notebook.id, folder.id);
                  },
                ),
            ],
          ),
        ),
      ),
    );
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
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Đổi tên thư mục'),
              onTap: () async {
                Navigator.of(ctx).pop();
                final controller = TextEditingController(text: folder.name);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (dCtx) => AlertDialog(
                    title: const Text('Đổi tên thư mục'),
                    content: TextField(controller: controller, autofocus: true),
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
                );
                if (ok == true && controller.text.trim().isNotEmpty) {
                  await appState.updateFolder(
                    folder.copyWith(name: controller.text.trim()),
                  );
                }
                controller.dispose();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              title: const Text(
                'Xóa thư mục',
                style: TextStyle(color: Colors.redAccent),
              ),
              subtitle: const Text('Sổ tay bên trong sẽ được giữ lại ở Tất cả ghi chú'),
              onTap: () async {
                Navigator.of(ctx).pop();
                final ok = await _confirmDialog(
                  context,
                  'Xóa thư mục "${folder.name}"?',
                  'Các sổ tay bên trong sẽ được giữ lại.',
                  confirmLabel: 'Xóa',
                  isDestructive: true,
                );
                if (ok == true) {
                  if (_selectedFolderId == folder.id) {
                    setState(() {
                      _section = _LibrarySection.allNotes;
                      _selectedFolderId = null;
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
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _SidebarTile({
    required this.icon,
    this.iconColor,
    required this.label,
    this.count,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeBg = AppTheme.accentBlue.withValues(alpha: 0.16);
    final activeFg = AppTheme.accentBlue;

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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 19,
                  color: selected
                      ? activeFg
                      : (iconColor ?? theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(width: 10),
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

/// Ô đầu tiên trên kệ sách: "+ Ghi chú mới" theo phong cách Huawei Notes.
class _NewNotebookTile extends StatelessWidget {
  final VoidCallback onTap;

  const _NewNotebookTile({required this.onTap});

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
