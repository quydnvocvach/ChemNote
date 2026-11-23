import 'package:flutter/material.dart';

import '../../core/models/drawing_elements.dart';
import '../../core/theme/app_theme.dart';

class CreateNotebookResult {
  final String title;
  final String coverStyle;
  final int coverColorValue;
  final PaperTemplateType template;
  final PaperColorType paperColor;
  final bool isLandscape;

  const CreateNotebookResult({
    required this.title,
    required this.coverStyle,
    required this.coverColorValue,
    required this.template,
    required this.paperColor,
    required this.isLandscape,
  });
}

class CreateNotebookDialog extends StatefulWidget {
  const CreateNotebookDialog({super.key});

  @override
  State<CreateNotebookDialog> createState() => _CreateNotebookDialogState();
}

class _CreateNotebookDialogState extends State<CreateNotebookDialog> {
  final _titleController = TextEditingController();
  String _coverStyle = 'molecular';
  int _coverColorValue = AppTheme.notebookCoverColors.first;
  PaperTemplateType _template = PaperTemplateType.sageRibbon;
  PaperColorType _paperColor = PaperColorType.cream;
  bool _isLandscape = false;

  static const _coverStyles = <(String, String)>[
    ('molecular', 'Phân tử'),
    ('classic', 'Cổ điển'),
    ('lab', 'Phòng Lab'),
    ('gradient', 'Hiện đại'),
  ];

  static const _templates = <(PaperTemplateType, String, IconData)>[
    (PaperTemplateType.sageRibbon, 'Kẻ ngang ruy-băng xanh', Icons.bookmark_border_rounded),
    (PaperTemplateType.pastelGrid, 'Ô ly tiêu đề pastel', Icons.grid_on_rounded),
    (PaperTemplateType.vintageCream, 'Giấy cổ điển viền khung', Icons.auto_stories_outlined),
    (PaperTemplateType.twoColumnStudy, 'Chia 2 cột bài tập', Icons.view_column_outlined),
    (PaperTemplateType.hexagonal, 'Lưới lục giác (Hữu cơ)', Icons.hexagon_outlined),
    (PaperTemplateType.cornell, 'Giấy Cornell', Icons.view_sidebar_outlined),
    (PaperTemplateType.ruled, 'Kẻ ngang cổ điển', Icons.subject_rounded),
    (PaperTemplateType.grid, 'Ô ly vuông', Icons.grid_4x4_rounded),
    (PaperTemplateType.dotted, 'Chấm dot tối giản', Icons.grain_rounded),
    (PaperTemplateType.blank, 'Giấy trắng trơn', Icons.crop_portrait_rounded),
  ];

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tạo sổ tay mới'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _titleController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Tên sổ tay',
                  hintText: 'VD: Hóa Hữu Cơ 2 - Cơ chế phản ứng',
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Kiểu bìa & màu sắc',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _coverStyles.map((item) {
                  final selected = _coverStyle == item.$1;
                  return ChoiceChip(
                    label: Text(item.$2),
                    selected: selected,
                    onSelected: (_) => setState(() => _coverStyle = item.$1),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: AppTheme.notebookCoverColors.map((colorVal) {
                  final selected = _coverColorValue == colorVal;
                  return GestureDetector(
                    onTap: () => setState(() => _coverColorValue = colorVal),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Color(colorVal),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: selected
                          ? const Icon(Icons.check, size: 16, color: Colors.white)
                          : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),
              const Text(
                'Mẫu giấy mặc định',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _templates.map((item) {
                  final selected = _template == item.$1;
                  return ChoiceChip(
                    avatar: Icon(item.$3, size: 16),
                    label: Text(item.$2),
                    selected: selected,
                    onSelected: (_) => setState(() => _template = item.$1),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Màu giấy',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        SegmentedButton<PaperColorType>(
                          segments: const [
                            ButtonSegment(
                              value: PaperColorType.white,
                              label: Text('Trắng'),
                            ),
                            ButtonSegment(
                              value: PaperColorType.cream,
                              label: Text('Kem'),
                            ),
                            ButtonSegment(
                              value: PaperColorType.dark,
                              label: Text('Tối'),
                            ),
                          ],
                          selected: {_paperColor},
                          onSelectionChanged: (set) =>
                              setState(() => _paperColor = set.first),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Khổ giấy ngang (Landscape)'),
                subtitle: const Text('Phù hợp vẽ sơ đồ phản ứng dài và bảng biểu'),
                value: _isLandscape,
                onChanged: (val) => setState(() => _isLandscape = val),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton.icon(
          onPressed: () {
            final title = _titleController.text.trim();
            Navigator.of(context).pop(
              CreateNotebookResult(
                title: title.isEmpty ? 'Sổ tay Hóa học mới' : title,
                coverStyle: _coverStyle,
                coverColorValue: _coverColorValue,
                template: _template,
                paperColor: _paperColor,
                isLandscape: _isLandscape,
              ),
            );
          },
          icon: const Icon(Icons.add_rounded),
          label: const Text('Tạo sổ'),
        ),
      ],
    );
  }
}
