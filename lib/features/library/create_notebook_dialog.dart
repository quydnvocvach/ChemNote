import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/models/drawing_elements.dart';
import '../../core/providers/app_state.dart';
import '../../core/theme/app_theme.dart';
import '../canvas/paper_templates.dart';

class CreateNotebookResult {
  final String title;
  final String coverStyle;
  final int coverColorValue;
  final PaperTemplateType template;
  final PaperColorType paperColor;
  final bool isLandscape;
  final bool isWhiteboard;
  final String? customCoverImagePath;
  final bool useFirstPageAsCover;
  final bool allowAutoRandomCover;

  const CreateNotebookResult({
    required this.title,
    required this.coverStyle,
    required this.coverColorValue,
    required this.template,
    required this.paperColor,
    required this.isLandscape,
    this.isWhiteboard = false,
    this.customCoverImagePath,
    this.useFirstPageAsCover = false,
    this.allowAutoRandomCover = false,
  });
}

enum _CreatorMode { cover, paper }

class CreateNotebookDialog extends StatefulWidget {
  const CreateNotebookDialog({super.key});

  @override
  State<CreateNotebookDialog> createState() => _CreateNotebookDialogState();
}

class _CreateNotebookDialogState extends State<CreateNotebookDialog> {
  final _titleController = TextEditingController();
  final _imagePicker = ImagePicker();

  _CreatorMode _mode = _CreatorMode.cover;
  int _coverTabIndex = 0; // 0: TÙY CHỈNH, 1: ĐƠN GIẢN, 2: HỌA TIẾT, 3: CỔ ĐIỂN

  String _coverStyle = 'molecular';
  int _coverColorValue = AppTheme.notebookCoverColors.first;
  String? _customCoverImagePath;
  bool _useFirstPageAsCover = false;

  PaperTemplateType _template = PaperTemplateType.sageRibbon;
  PaperColorType _paperColor = PaperColorType.white;
  bool _isLandscape = false;
  bool _isWhiteboard = false;

  static const _coverTabLabels = [
    'TÙY CHỈNH',
    'ĐƠN GIẢN',
    'HỌA TIẾT',
    'CỔ ĐIỂN',
  ];

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    if (appState.randomCoverEnabled && appState.randomCoverPaths.isNotEmpty) {
      _customCoverImagePath = appState.pickRandomCoverPath();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickPersonalCover(BuildContext context) async {
    try {
      final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (picked == null || !context.mounted) return;
      final appState = context.read<AppState>();
      final savedPath = await appState.storage.saveImportedFile(
        File(picked.path),
        subfolder: 'covers',
      );
      appState.addCustomCoverPath(savedPath);
      if (!mounted) return;
      setState(() {
        _customCoverImagePath = savedPath;
        _useFirstPageAsCover = false;
      });
    } catch (_) {
      // Bỏ qua an toàn nếu người dùng hủy chọn ảnh.
    }
  }

  void _confirmCreate() {
    final title = _titleController.text.trim();
    Navigator.of(context).pop(
      CreateNotebookResult(
        title: title.isEmpty
            ? (_isWhiteboard ? 'Bảng vô cực Hóa học' : 'Sổ tay Hóa học mới')
            : title,
        coverStyle: _coverStyle,
        coverColorValue: _coverColorValue,
        template: _template,
        paperColor: _paperColor,
        isLandscape: _isLandscape,
        isWhiteboard: _isWhiteboard,
        customCoverImagePath: _useFirstPageAsCover ? null : _customCoverImagePath,
        useFirstPageAsCover: _useFirstPageAsCover,
        allowAutoRandomCover: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surfaceBg = isDark ? AppTheme.obsidianSurface : AppTheme.lightSurface;
    final cardBg = isDark ? AppTheme.obsidianCard : AppTheme.lightCard;

    return Dialog(
      backgroundColor: surfaceBg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Thanh trên cùng giống Huawei Notes: × | Nhập tên ghi chú (bút) | ✓
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Đóng',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _titleController,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: InputDecoration(
                        hintText: _isWhiteboard
                            ? 'Nhập tên bảng vô cực'
                            : 'Nhập tên ghi chú',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        suffixIcon: Icon(
                          Icons.edit_outlined,
                          size: 17,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Tạo ghi chú',
                    onPressed: _confirmCreate,
                    icon: const Icon(
                      Icons.check_rounded,
                      color: AppTheme.accentBlue,
                      size: 26,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Khung xem trước song song: Bìa (trái) & Mẫu giấy trực tiếp (phải)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _PreviewCard(
                    label: 'Bìa sổ',
                    selected: _mode == _CreatorMode.cover,
                    onTap: () => setState(() => _mode = _CreatorMode.cover),
                    child: _buildCoverPreview(),
                  ),
                  if (appState.randomCoverPaths.length > 1) ...[
                    const SizedBox(width: 10),
                    IconButton.filledTonal(
                      tooltip: 'Bốc ảnh bìa ngẫu nhiên khác',
                      onPressed: () {
                        final picked = appState.pickRandomCoverPath(force: true);
                        if (picked == null) return;
                        setState(() {
                          _customCoverImagePath = picked;
                          _useFirstPageAsCover = false;
                        });
                      },
                      icon: const Icon(Icons.shuffle_rounded, size: 18),
                    ),
                  ],
                  const SizedBox(width: 24),
                  _PreviewCard(
                    label: _isWhiteboard ? 'Nền vô cực' : 'Mẫu giấy',
                    selected: _mode == _CreatorMode.paper,
                    onTap: () => setState(() => _mode = _CreatorMode.paper),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CustomPaint(
                        painter: PaperTemplatePainter(
                          templateType: _template,
                          paperColor: _paperColor,
                          isLandscape: _isLandscape,
                          isInfiniteWhiteboard: _isWhiteboard,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Khu vực tùy chọn phía dưới
            Expanded(
              child: _mode == _CreatorMode.cover
                  ? _buildCoverPicker(context, appState, cardBg)
                  : _buildPaperPicker(context, cardBg),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverPreview() {
    if (_useFirstPageAsCover) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CustomPaint(
          painter: PaperTemplatePainter(
            templateType: _template,
            paperColor: _paperColor,
            isLandscape: _isLandscape,
            isInfiniteWhiteboard: _isWhiteboard,
          ),
        ),
      );
    }

    if (_customCoverImagePath != null &&
        _customCoverImagePath!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(_customCoverImagePath!),
          fit: BoxFit.cover,
          cacheWidth: 360,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => ColoredBox(color: Color(_coverColorValue)),
        ),
      );
    }

    final color = Color(_coverColorValue);
    final darker = Color.lerp(color, Colors.black, 0.25) ?? color;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, darker],
        ),
      ),
      child: Center(
        child: Icon(
          _coverStyle == 'molecular'
              ? Icons.hexagon_outlined
              : _coverStyle == 'lab'
                  ? Icons.grid_4x4_rounded
                  : Icons.menu_book_outlined,
          color: Colors.white.withValues(alpha: 0.35),
          size: 32,
        ),
      ),
    );
  }

  Widget _buildCoverPicker(
    BuildContext context,
    AppState appState,
    Color cardBg,
  ) {
    final customCovers = appState.customCoverPaths;

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text(
            'Sử dụng nội dung trang đầu làm bìa',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
          value: _useFirstPageAsCover,
          onChanged: (v) => setState(() => _useFirstPageAsCover = v),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (int i = 0; i < _coverTabLabels.length; i++) ...[
                ChoiceChip(
                  label: Text(
                    _coverTabLabels[i],
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                  selected: _coverTabIndex == i,
                  onSelected: (_) {
                    setState(() {
                      _coverTabIndex = i;
                      if (i == 1) _coverStyle = 'gradient';
                      if (i == 2) _coverStyle = 'molecular';
                      if (i == 3) _coverStyle = 'classic';
                    });
                  },
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_coverTabIndex == 0)
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              InkWell(
                onTap: () => _pickPersonalCover(context),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 78,
                  height: 104,
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.accentBlue.withValues(alpha: 0.5),
                      width: 1.4,
                    ),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined,
                          color: AppTheme.accentBlue, size: 24),
                      SizedBox(height: 6),
                      Text(
                        'Thêm ảnh',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.accentBlue,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              for (final path in customCovers)
                if (path.trim().isNotEmpty)
                  GestureDetector(
                    onTap: () => setState(() {
                      _customCoverImagePath = path;
                      _useFirstPageAsCover = false;
                    }),
                    child: Container(
                      width: 78,
                      height: 104,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _customCoverImagePath == path &&
                                  !_useFirstPageAsCover
                              ? AppTheme.accentBlue
                              : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(9.5),
                        child: Image.file(
                          File(path),
                          fit: BoxFit.cover,
                          cacheWidth: 240,
                          filterQuality: FilterQuality.medium,
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) => const ColoredBox(
                            color: Color(0xFF22252E),
                            child: Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                size: 22,
                                color: Colors.white38,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
            ],
          )
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: AppTheme.notebookCoverColors.map((colorVal) {
              final selected = _customCoverImagePath == null &&
                  !_useFirstPageAsCover &&
                  _coverColorValue == colorVal;
              return GestureDetector(
                onTap: () => setState(() {
                  _coverColorValue = colorVal;
                  _customCoverImagePath = null;
                  _useFirstPageAsCover = false;
                }),
                child: Container(
                  width: 78,
                  height: 104,
                  decoration: BoxDecoration(
                    color: Color(colorVal),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? AppTheme.accentBlue : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                  child: Center(
                    child: selected
                        ? const Icon(Icons.check_circle_rounded,
                            color: Colors.white, size: 22)
                        : Icon(
                            _coverTabIndex == 2
                                ? Icons.hexagon_outlined
                                : Icons.menu_book_outlined,
                            color: Colors.white.withValues(alpha: 0.4),
                            size: 22,
                          ),
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildPaperPicker(BuildContext context, Color cardBg) {
    final templates = PaperTemplateInfo.orderedTemplates;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('A4')),
                ButtonSegment(value: true, label: Text('Vô cực')),
              ],
              selected: {_isWhiteboard},
              onSelectionChanged: (s) {
                final wb = s.first;
                setState(() {
                  _isWhiteboard = wb;
                  if (wb) _template = PaperTemplateType.dotted;
                });
              },
            ),
            if (!_isWhiteboard)
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Dọc')),
                  ButtonSegment(value: true, label: Text('Ngang')),
                ],
                selected: {_isLandscape},
                onSelectionChanged: (s) =>
                    setState(() => _isLandscape = s.first),
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PaperColorDot(
                  color: const Color(0xFFFFFFFF),
                  label: 'Trắng',
                  selected: _paperColor == PaperColorType.white,
                  onTap: () =>
                      setState(() => _paperColor = PaperColorType.white),
                ),
                const SizedBox(width: 8),
                _PaperColorDot(
                  color: const Color(0xFFFAF6EC),
                  label: 'Kem',
                  selected: _paperColor == PaperColorType.cream,
                  onTap: () =>
                      setState(() => _paperColor = PaperColorType.cream),
                ),
                const SizedBox(width: 8),
                _PaperColorDot(
                  color: const Color(0xFF1E1E24),
                  label: 'Tối',
                  selected: _paperColor == PaperColorType.dark,
                  onTap: () =>
                      setState(() => _paperColor = PaperColorType.dark),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.78,
          ),
          itemCount: templates.length,
          itemBuilder: (context, idx) {
            final tpl = templates[idx];
            final selected = _template == tpl;
            return InkWell(
              onTap: () => setState(() => _template = tpl),
              borderRadius: BorderRadius.circular(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                              ? AppTheme.accentBlue
                              : Theme.of(context).dividerColor,
                          width: selected ? 2.2 : 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8.5),
                        child: CustomPaint(
                          painter: PaperTemplatePainter(
                            templateType: tpl,
                            paperColor: _paperColor,
                            isLandscape: _isLandscape,
                            isInfiniteWhiteboard: _isWhiteboard,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    PaperTemplateInfo.templateLabel(tpl),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? AppTheme.accentBlue : null,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  const _PreviewCard({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 88,
            height: 118,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: selected ? AppTheme.accentBlue : Colors.transparent,
                width: 2.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: child,
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppTheme.accentBlue : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaperColorDot extends StatelessWidget {
  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PaperColorDot({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? AppTheme.accentBlue : Colors.grey.shade500,
              width: selected ? 2.5 : 1,
            ),
          ),
        ),
      ),
    );
  }
}
