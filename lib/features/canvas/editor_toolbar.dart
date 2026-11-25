import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../core/models/drawing_elements.dart';
import '../../core/models/notebook.dart';
import '../../core/providers/app_state.dart';
import '../../core/services/app_updater_service.dart';
import 'paper_templates.dart';

/// Active interaction tool in the Huawei Notes × GoodNotes 6 editor.
enum EditorTool {
  fountainPen,
  ballpointPen,
  brushPen,
  pencil,
  highlighter,
  eraser,
  lasso,
  textBox,
  shape,
  image,
  studyTape,
  laserPointer,
  panZoom,
}

/// Eraser behavior mode.
enum EraserMode {
  stroke,
  precision,
}

/// Actions from the top-right `+` Insert Menu.
enum InsertMenuAction {
  newPage,
  newWhiteboard,
  stickyNote,
  attachment,
  image,
  pdf,
  docPpt,
}

extension EditorToolX on EditorTool {
  bool get isPenFamily =>
      this == EditorTool.fountainPen ||
      this == EditorTool.ballpointPen ||
      this == EditorTool.brushPen ||
      this == EditorTool.pencil;

  bool get isDrawingTool =>
      isPenFamily ||
      this == EditorTool.highlighter ||
      this == EditorTool.shape;

  ToolType toStrokeToolType() {
    switch (this) {
      case EditorTool.fountainPen:
        return ToolType.fountainPen;
      case EditorTool.ballpointPen:
        return ToolType.ballpointPen;
      case EditorTool.brushPen:
        return ToolType.brushPen;
      case EditorTool.pencil:
        return ToolType.pencil;
      case EditorTool.highlighter:
        return ToolType.highlighter;
      case EditorTool.studyTape:
        return ToolType.studyTape;
      case EditorTool.laserPointer:
        return ToolType.laserPointer;
      case EditorTool.shape:
        return ToolType.ballpointPen;
      default:
        return ToolType.fountainPen;
    }
  }

  static EditorTool fromStrokeToolType(ToolType t) {
    switch (t) {
      case ToolType.fountainPen:
        return EditorTool.fountainPen;
      case ToolType.ballpointPen:
        return EditorTool.ballpointPen;
      case ToolType.brushPen:
        return EditorTool.brushPen;
      case ToolType.pencil:
        return EditorTool.pencil;
      case ToolType.highlighter:
        return EditorTool.highlighter;
      case ToolType.studyTape:
        return EditorTool.studyTape;
      case ToolType.laserPointer:
        return EditorTool.laserPointer;
    }
  }

  String get labelVi {
    switch (this) {
      case EditorTool.fountainPen:
        return 'Bút máy';
      case EditorTool.ballpointPen:
        return 'Bút bi';
      case EditorTool.brushPen:
        return 'Bút lông';
      case EditorTool.pencil:
        return 'Bút chì';
      case EditorTool.highlighter:
        return 'Bút dạ quang';
      case EditorTool.eraser:
        return 'Tẩy';
      case EditorTool.lasso:
        return 'Lasso chọn tự do';
      case EditorTool.textBox:
        return 'Hộp văn bản';
      case EditorTool.shape:
        return 'Hình học tự động';
      case EditorTool.image:
        return 'Hình ảnh';
      case EditorTool.studyTape:
        return 'Băng che học thuộc';
      case EditorTool.laserPointer:
        return 'Con trỏ Laser';
      case EditorTool.panZoom:
        return 'Chế độ đọc / Cuộn';
    }
  }
}

/// Curated ink colors (Obsidian Pro / Huawei Notes + Chemistry palette).
class EditorColors {
  static const Color obsidianBg = Color(0xFF0B0C10);
  static const Color obsidianSurface = Color(0xFF16181D);
  static const Color obsidianPill = Color(0xFF22252E);
  static const Color activeBlue = Color(0xFF3B82F6);
  static const Color starGold = Color(0xFFFACC15);

  static const List<Color> penSwatches = [
    Color(0xFF3B5BDB), // Cobalt Blue
    Color(0xFF22C55E), // Emerald Green
    Color(0xFF0F172A), // Obsidian Black
    Color(0xFFEF4444), // Crimson Red
    Color(0xFFFFFFFF), // White (for dark paper)
    Color(0xFF7C3AED), // Organic Violet
    Color(0xFFD97706), // Amber
    Color(0xFF0891B2), // Cyan
    Color(0xFF475569), // Graphite Gray
  ];

  static const List<Color> highlighterSwatches = [
    Color(0xFFFACC15), // Yellow
    Color(0xFF34D399), // Mint Green
    Color(0xFF60A5FA), // Sky Blue
    Color(0xFFF472B6), // Pink
    Color(0xFFFB923C), // Peach Orange
    Color(0xFFC084FC), // Lavender
  ];
}

// =============================================================================
// ROW 1: MULTI-NOTEBOOK TAB BAR + TOP-RIGHT 5-ITEM INSERT `+` MENU
// =============================================================================

class EditorTabBar extends StatelessWidget {
  final List<Notebook> openNotebooks;
  final String activeNotebookId;
  final VoidCallback onBack;
  final ValueChanged<String> onSelectTab;
  final ValueChanged<String> onCloseTab;
  final VoidCallback onOpenTabPicker;
  final ValueChanged<InsertMenuAction> onInsertAction;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenPageGrid;
  final VoidCallback onOpenChemistryHub;
  final VoidCallback onOpenSettingsDrawer;

  const EditorTabBar({
    super.key,
    required this.openNotebooks,
    required this.activeNotebookId,
    required this.onBack,
    required this.onSelectTab,
    required this.onCloseTab,
    required this.onOpenTabPicker,
    required this.onInsertAction,
    required this.onOpenSearch,
    required this.onOpenPageGrid,
    required this.onOpenChemistryHub,
    required this.onOpenSettingsDrawer,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? EditorColors.obsidianSurface : Colors.white;
    final pillBg = isDark ? EditorColors.obsidianPill : const Color(0xFFF1F5F9);
    final border =
        isDark ? Colors.white.withAlpha(20) : Colors.black.withAlpha(18);
    final fg = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
    final muted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Container(
      color: bg,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: border)),
          ),
          child: Row(
            children: [
              _ChromeIconBtn(
                icon: Icons.arrow_back_ios_new_rounded,
                tooltip: 'Quay lại thư viện',
                color: fg,
                onTap: onBack,
              ),
              const SizedBox(width: 2),
              // Multi-notebook tab strip
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: openNotebooks.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (ctx, i) {
                    if (i == openNotebooks.length) {
                      return Tooltip(
                        message: 'Chuyển / Mở thêm sổ tay',
                        child: InkWell(
                          onTap: onOpenTabPicker,
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 30,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: pillBg,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.library_books_outlined,
                              size: 15,
                              color: muted,
                            ),
                          ),
                        ),
                      );
                    }
                    final nb = openNotebooks[i];
                    final isActive = nb.id == activeNotebookId;
                    return InkWell(
                      onTap: () => onSelectTab(nb.id),
                      borderRadius: BorderRadius.circular(10),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        constraints:
                            const BoxConstraints(maxWidth: 180, minWidth: 92),
                        padding: const EdgeInsets.only(left: 11, right: 6),
                        decoration: BoxDecoration(
                          color: isActive
                              ? EditorColors.activeBlue
                                  .withAlpha(isDark ? 48 : 30)
                              : pillBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isActive
                                ? EditorColors.activeBlue.withAlpha(170)
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                nb.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: isActive
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isActive
                                      ? EditorColors.activeBlue
                                      : fg,
                                ),
                              ),
                            ),
                            if (openNotebooks.length > 1) ...[
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () => onCloseTab(nb.id),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 14,
                                  color: isActive
                                      ? EditorColors.activeBlue
                                      : muted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 4),
              // Top-Right `+` Circle Button = 5-Item Insert Dropdown Menu
              PopupMenuButton<InsertMenuAction>(
                tooltip: 'Thêm trang / Tệp đính kèm / Hình ảnh / PDF / DOC',
                color: isDark ? EditorColors.obsidianSurface : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: border),
                ),
                offset: const Offset(0, 42),
                onSelected: onInsertAction,
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: InsertMenuAction.newPage,
                    child: _InsertMenuRow(
                      icon: Icons.note_add_outlined,
                      label: 'Trang mới',
                    ),
                  ),
                  PopupMenuItem(
                    value: InsertMenuAction.newWhiteboard,
                    child: _InsertMenuRow(
                      icon: Icons.dashboard_customize_outlined,
                      label: 'Thêm Bảng vô cực',
                    ),
                  ),
                  PopupMenuItem(
                    value: InsertMenuAction.stickyNote,
                    child: _InsertMenuRow(
                      icon: Icons.sticky_note_2_outlined,
                      label: 'Thêm Giấy nhớ dán',
                    ),
                  ),
                  PopupMenuItem(
                    value: InsertMenuAction.attachment,
                    child: _InsertMenuRow(
                      icon: Icons.attach_file_rounded,
                      label: 'Thêm tệp tin đính kèm',
                    ),
                  ),
                  PopupMenuItem(
                    value: InsertMenuAction.image,
                    child: _InsertMenuRow(
                      icon: Icons.add_photo_alternate_outlined,
                      label: 'Nhập hình ảnh',
                    ),
                  ),
                  PopupMenuItem(
                    value: InsertMenuAction.pdf,
                    child: _InsertMenuRow(
                      icon: Icons.picture_as_pdf_outlined,
                      label: 'Nhập tệp tin PDF',
                    ),
                  ),
                  PopupMenuItem(
                    value: InsertMenuAction.docPpt,
                    child: _InsertMenuRow(
                      icon: Icons.description_outlined,
                      label: 'Nhập DOC/PPT',
                    ),
                  ),
                ],
                child: Container(
                  width: 32,
                  height: 32,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: EditorColors.activeBlue.withAlpha(36),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: EditorColors.activeBlue.withAlpha(170),
                      width: 1.2,
                    ),
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    size: 19,
                    color: EditorColors.activeBlue,
                  ),
                ),
              ),
              _ChromeIconBtn(
                icon: Icons.search_rounded,
                tooltip: 'Tìm kiếm trong sổ tay',
                color: fg,
                onTap: onOpenSearch,
              ),
              _ChromeIconBtn(
                icon: Icons.grid_view_rounded,
                tooltip: 'Danh sách trang & Mục lục',
                color: fg,
                onTap: onOpenPageGrid,
              ),
              _ChromeIconBtn(
                icon: Icons.science_outlined,
                tooltip: 'Công cụ Hóa học',
                color: EditorColors.activeBlue,
                isActive: true,
                onTap: onOpenChemistryHub,
              ),
              _ChromeIconBtn(
                icon: Icons.more_horiz_rounded,
                tooltip: 'Cài đặt trang & Sổ tay',
                color: fg,
                onTap: onOpenSettingsDrawer,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InsertMenuRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InsertMenuRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 19),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(fontSize: 13.5)),
      ],
    );
  }
}

// =============================================================================
// ROW 2: SLEEK MONOCHROME VECTOR TOOL BAR (NO 3 Quick-Width Squiggles!)
// =============================================================================

class EditorToolBar extends StatelessWidget {
  final EditorTool activeTool;
  final EditorTool lastPenTool;
  final Color activeColor;
  final bool canUndo;
  final bool canRedo;
  final bool zoomWindowEnabled;
  final bool rulerVisible;
  final bool palmRejectionEnabled;
  final bool stylusPanMode;
  final bool isRecordingAudio;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final ValueChanged<EditorTool> onSelectTool;
  final VoidCallback onOpenPenPopover;
  final VoidCallback onOpenEraserPopover;
  final VoidCallback onInsertImage;
  final VoidCallback onOpenStickerPicker;
  final VoidCallback onAddStickyNote;
  final VoidCallback onToggleZoomWindow;
  final VoidCallback onToggleRuler;
  final VoidCallback onTogglePalmRejection;
  final VoidCallback? onToggleStylusPan;
  final VoidCallback onToggleAudioRecording;
  final ValueChanged<Color> onSelectColor;
  final VoidCallback onOpenColorPalette;

  const EditorToolBar({
    super.key,
    required this.activeTool,
    required this.lastPenTool,
    required this.activeColor,
    required this.canUndo,
    required this.canRedo,
    required this.zoomWindowEnabled,
    required this.rulerVisible,
    required this.palmRejectionEnabled,
    this.stylusPanMode = false,
    required this.isRecordingAudio,
    required this.onUndo,
    required this.onRedo,
    required this.onSelectTool,
    required this.onOpenPenPopover,
    required this.onOpenEraserPopover,
    required this.onInsertImage,
    required this.onOpenStickerPicker,
    required this.onAddStickyNote,
    required this.onToggleZoomWindow,
    required this.onToggleRuler,
    required this.onTogglePalmRejection,
    this.onToggleStylusPan,
    required this.onToggleAudioRecording,
    required this.onSelectColor,
    required this.onOpenColorPalette,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? EditorColors.obsidianSurface : const Color(0xFFF8FAFC);
    final border =
        isDark ? Colors.white.withAlpha(18) : Colors.black.withAlpha(16);
    final fg = isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B);

    final quickColors = activeTool == EditorTool.highlighter
        ? EditorColors.highlighterSwatches.take(3).toList()
        : EditorColors.penSwatches.take(3).toList();

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: bg,
        border: Border(bottom: BorderSide(color: border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            _ChromeIconBtn(
              icon: Icons.undo_rounded,
              tooltip: 'Hoàn tác (Chạm 2 ngón)',
              color: fg,
              enabled: canUndo,
              onTap: onUndo,
            ),
            _ChromeIconBtn(
              icon: Icons.redo_rounded,
              tooltip: 'Làm lại (Chạm 3 ngón)',
              color: fg,
              enabled: canRedo,
              onTap: onRedo,
            ),
            _vDivider(border),

            // Pen tool (tap active pen again -> opens Huawei Notes Pen Popover)
            _ChromeIconBtn(
              icon: _penIcon(lastPenTool),
              tooltip:
                  '${lastPenTool.labelVi} (Nhấn lần nữa để chỉnh nét, độ mờ & ghim sao)',
              color: fg,
              isActive: activeTool.isPenFamily,
              onTap: () {
                if (activeTool.isPenFamily) {
                  onOpenPenPopover();
                } else {
                  onSelectTool(lastPenTool);
                }
              },
            ),

            // Highlighter (tap again when active -> opens popover too)
            _ChromeIconBtn(
              icon: Icons.border_color_outlined,
              tooltip: 'Bút dạ quang (Nhấn lần nữa để chỉnh cỡ & ghim sao)',
              color: fg,
              isActive: activeTool == EditorTool.highlighter,
              onTap: () {
                if (activeTool == EditorTool.highlighter) {
                  onOpenPenPopover();
                } else {
                  onSelectTool(EditorTool.highlighter);
                }
              },
            ),

            // Eraser
            _ChromeIconBtn(
              icon: Icons.auto_fix_normal_outlined,
              tooltip: 'Tẩy (Nhấn lần nữa để chọn Tẩy nét / Tẩy điểm / Xóa trang)',
              color: fg,
              isActive: activeTool == EditorTool.eraser,
              onTap: () {
                if (activeTool == EditorTool.eraser) {
                  onOpenEraserPopover();
                } else {
                  onSelectTool(EditorTool.eraser);
                }
              },
            ),

            // Lasso
            _ChromeIconBtn(
              icon: Icons.gesture_rounded,
              tooltip: 'Lasso chọn tự do',
              color: fg,
              isActive: activeTool == EditorTool.lasso,
              onTap: () => onSelectTool(EditorTool.lasso),
            ),

            // Text Box
            _ChromeIconBtn(
              icon: Icons.text_fields_rounded,
              tooltip: 'Hộp văn bản',
              color: fg,
              isActive: activeTool == EditorTool.textBox,
              onTap: () => onSelectTool(EditorTool.textBox),
            ),

            // Auto Shape
            _ChromeIconBtn(
              icon: Icons.hexagon_outlined,
              tooltip: 'Hình học tự động',
              color: fg,
              isActive: activeTool == EditorTool.shape,
              onTap: () => onSelectTool(EditorTool.shape),
            ),

            // Image Tool (Selects EditorTool.image; tap again or on empty page opens Ảnh gần đây popover)
            _ChromeIconBtn(
              icon: Icons.add_photo_alternate_outlined,
              tooltip: 'Công cụ Hình ảnh (Chọn/Di chuyển ảnh hoặc nhấn để chèn ảnh mới)',
              color: fg,
              isActive: activeTool == EditorTool.image,
              onTap: onInsertImage,
            ),

            // Stencils / Stickers
            _ChromeIconBtn(
              icon: Icons.biotech_outlined,
              tooltip: 'Khuôn Hóa học & Hình dán',
              color: fg,
              onTap: onOpenStickerPicker,
            ),

            // Sticky Notes (Giấy nhớ dán GoodNotes)
            _ChromeIconBtn(
              icon: Icons.sticky_note_2_outlined,
              tooltip: 'Thêm Giấy nhớ dán (Sticky Note)',
              color: fg,
              onTap: onAddStickyNote,
            ),

            _vDivider(border),

            // Pro Note Tools
            _ChromeIconBtn(
              icon: Icons.zoom_in_rounded,
              tooltip: 'Cửa sổ phóng to',
              color: fg,
              isActive: zoomWindowEnabled,
              onTap: onToggleZoomWindow,
            ),
            _ChromeIconBtn(
              icon: Icons.flare_rounded,
              tooltip: 'Con trỏ Laser',
              color: fg,
              isActive: activeTool == EditorTool.laserPointer,
              onTap: () => onSelectTool(EditorTool.laserPointer),
            ),
            _ChromeIconBtn(
              icon: Icons.do_not_touch_outlined,
              tooltip: palmRejectionEnabled
                  ? 'Khoá lòng bàn tay: ĐANG BẬT (Bút viết · 1 ngón tay cuộn trang)'
                  : 'Khoá lòng bàn tay: ĐANG TẮT (1 ngón viết · 2 ngón thu phóng/cuộn)',
              color: fg,
              isActive: palmRejectionEnabled,
              onTap: onTogglePalmRejection,
            ),
            if (onToggleStylusPan != null)
              _ChromeIconBtn(
                icon: Icons.pan_tool_alt_outlined,
                tooltip: stylusPanMode
                    ? 'Chế độ Bút cuộn trang: ĐANG BẬT (Bút chỉ cuộn & nhấn nút, không viết)'
                    : 'Chế độ Bút cuộn trang: ĐANG TẮT (Bút chỉ dùng để viết/công cụ)',
                color: fg,
                isActive: stylusPanMode,
                onTap: onToggleStylusPan!,
              ),
            _ChromeIconBtn(
              icon: Icons.visibility_off_outlined,
              tooltip: 'Băng che học thuộc (Study Tape)',
              color: fg,
              isActive: activeTool == EditorTool.studyTape,
              onTap: () => onSelectTool(EditorTool.studyTape),
            ),
            _ChromeIconBtn(
              icon: Icons.straighten_rounded,
              tooltip: 'Thước kẻ thẳng',
              color: fg,
              isActive: rulerVisible,
              onTap: onToggleRuler,
            ),
            Tooltip(
              message: isRecordingAudio
                  ? 'Đang ghi âm bài giảng — Nhấn để dừng'
                  : 'Ghi âm bài giảng đồng bộ nét viết (Audio Note Replay)',
              child: InkWell(
                onTap: onToggleAudioRecording,
                borderRadius: BorderRadius.circular(18),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 34,
                  height: 34,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: isRecordingAudio
                        ? const Color(0xFFEF4444).withAlpha(46)
                        : Colors.transparent,
                    shape: BoxShape.circle,
                    border: isRecordingAudio
                        ? Border.all(color: const Color(0xFFEF4444), width: 1.4)
                        : null,
                  ),
                  child: Icon(
                    isRecordingAudio
                        ? Icons.stop_circle_outlined
                        : Icons.mic_none_rounded,
                    size: 19,
                    color: isRecordingAudio ? const Color(0xFFEF4444) : fg,
                  ),
                ),
              ),
            ),

            _vDivider(border),

            // 3 Quick Color Dots + Palette (No 3 quick-width squiggles!)
            for (final c in quickColors)
              _QuickColorDot(
                color: c,
                // ignore: deprecated_member_use
                isSelected: activeColor.value == c.value,
                onTap: () {
                  // ignore: deprecated_member_use
                  if (activeColor.value == c.value) {
                    onOpenColorPalette();
                  } else {
                    onSelectColor(c);
                  }
                },
              ),
            _ChromeIconBtn(
              icon: Icons.palette_outlined,
              tooltip: 'Bảng màu đầy đủ',
              color: fg,
              onTap: onOpenColorPalette,
            ),
          ],
        ),
      ),
    );
  }

  IconData _penIcon(EditorTool pen) {
    switch (pen) {
      case EditorTool.fountainPen:
        return Icons.edit_outlined;
      case EditorTool.ballpointPen:
        return Icons.create_outlined;
      case EditorTool.brushPen:
        return Icons.brush_outlined;
      case EditorTool.pencil:
        return Icons.mode_edit_outline_outlined;
      default:
        return Icons.edit_outlined;
    }
  }

  Widget _vDivider(Color color) {
    return Container(
      width: 1,
      height: 22,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: color,
    );
  }
}

class _ChromeIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final bool isActive;
  final bool enabled;
  final VoidCallback onTap;

  const _ChromeIconBtn({
    required this.icon,
    required this.tooltip,
    required this.color,
    this.isActive = false,
    this.enabled = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          width: 34,
          height: 34,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: isActive
                ? EditorColors.activeBlue.withAlpha(42)
                : Colors.transparent,
            shape: BoxShape.circle,
            border: isActive
                ? Border.all(
                    color: EditorColors.activeBlue.withAlpha(180),
                    width: 1.2,
                  )
                : null,
          ),
          child: Icon(
            icon,
            size: 19,
            color: !enabled
                ? color.withAlpha(75)
                : (isActive ? EditorColors.activeBlue : color),
          ),
        ),
      ),
    );
  }
}

class _QuickColorDot extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _QuickColorDot({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? EditorColors.activeBlue : Colors.transparent,
            width: 2,
          ),
        ),
        child: Container(
          width: 19,
          height: 19,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24, width: 1),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// STAR-ONLY FLOATING LEFT QUICK-PEN FAVORITES DOCK
// =============================================================================

class QuickPenFavoritesDock extends StatefulWidget {
  final List<PenPreset> favoritePens;
  final EditorTool activeTool;
  final Color activeColor;
  final double activeWidth;
  final ValueChanged<PenPreset> onSelectPreset;
  final ValueChanged<PenPreset> onRemovePreset;

  const QuickPenFavoritesDock({
    super.key,
    required this.favoritePens,
    required this.activeTool,
    required this.activeColor,
    required this.activeWidth,
    required this.onSelectPreset,
    required this.onRemovePreset,
  });

  @override
  State<QuickPenFavoritesDock> createState() => _QuickPenFavoritesDockState();
}

class _QuickPenFavoritesDockState extends State<QuickPenFavoritesDock> {
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    if (widget.favoritePens.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dockBg = isDark
        ? EditorColors.obsidianSurface.withAlpha(232)
        : Colors.white.withAlpha(240);
    final border = isDark ? Colors.white12 : Colors.black12;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 44,
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 3),
      decoration: BoxDecoration(
        color: dockBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 90 : 35),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_collapsed)
            for (final pen in widget.favoritePens) _buildPenItem(pen, isDark),
          InkWell(
            onTap: () => setState(() => _collapsed = !_collapsed),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 34,
              height: 28,
              alignment: Alignment.center,
              child: Icon(
                _collapsed
                    ? Icons.chevron_right_rounded
                    : Icons.chevron_left_rounded,
                size: 18,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPenItem(PenPreset pen, bool isDark) {
    final toolMatch =
        EditorToolX.fromStrokeToolType(pen.toolType) == widget.activeTool;
    // ignore: deprecated_member_use
    final colorMatch = widget.activeColor.value == pen.colorValue;
    final widthMatch = (widget.activeWidth - pen.width).abs() < 0.35;
    final isSelected = toolMatch && colorMatch && widthMatch;

    return Tooltip(
      message: '${pen.label} (${pen.width.toStringAsFixed(1)}px) — Giữ để bỏ ghim',
      child: GestureDetector(
        onTap: () => widget.onSelectPreset(pen),
        onLongPress: () => widget.onRemovePreset(pen),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          width: 36,
          height: 36,
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: isSelected
                ? EditorColors.activeBlue.withAlpha(46)
                : Colors.transparent,
            shape: BoxShape.circle,
            border: isSelected
                ? Border.all(color: EditorColors.activeBlue, width: 1.5)
                : null,
          ),
          child: CustomPaint(
            painter: _PenNibIconPainter(
              tipColor: Color(pen.colorValue),
              bodyColor:
                  isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
              toolType: pen.toolType,
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom vector painter for realistic illustrated pen nibs (Ballpoint,
/// Fountain, Pencil, Brush, Highlighter).
class _PenNibIconPainter extends CustomPainter {
  final Color tipColor;
  final Color bodyColor;
  final ToolType toolType;

  const _PenNibIconPainter({
    required this.tipColor,
    required this.bodyColor,
    required this.toolType,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    final bodyPaint = Paint()
      ..color = bodyColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round;
    final tipPaint = Paint()
      ..color = tipColor
      ..style = PaintingStyle.fill;

    if (toolType == ToolType.highlighter) {
      final tip = Path()
        ..moveTo(cx - 5, 13)
        ..lineTo(cx + 5, 9)
        ..lineTo(cx + 5, 16)
        ..lineTo(cx - 5, 16)
        ..close();
      canvas.drawPath(tip, tipPaint);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - 6, 16, 12, 13),
          const Radius.circular(2),
        ),
        bodyPaint,
      );
      canvas.drawRect(Rect.fromLTWH(cx - 5, 20, 10, 4), tipPaint);
    } else if (toolType == ToolType.pencil) {
      final cone = Path()
        ..moveTo(cx, 7)
        ..lineTo(cx + 5, 16)
        ..lineTo(cx - 5, 16)
        ..close();
      canvas.drawPath(cone, bodyPaint);
      final lead = Path()
        ..moveTo(cx, 7)
        ..lineTo(cx + 2.2, 11.5)
        ..lineTo(cx - 2.2, 11.5)
        ..close();
      canvas.drawPath(lead, tipPaint);
      canvas.drawRect(Rect.fromLTWH(cx - 5, 16, 10, 13), bodyPaint);
    } else if (toolType == ToolType.brushPen) {
      final brush = Path()
        ..moveTo(cx, 6)
        ..quadraticBezierTo(cx + 5.5, 12, cx + 4, 16)
        ..lineTo(cx - 4, 16)
        ..quadraticBezierTo(cx - 5.5, 12, cx, 6)
        ..close();
      canvas.drawPath(brush, tipPaint);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - 5, 16, 10, 13),
          const Radius.circular(3),
        ),
        bodyPaint,
      );
    } else if (toolType == ToolType.ballpointPen) {
      final cone = Path()
        ..moveTo(cx, 7)
        ..lineTo(cx + 4.5, 15)
        ..lineTo(cx - 4.5, 15)
        ..close();
      canvas.drawPath(cone, bodyPaint);
      canvas.drawCircle(Offset(cx, 7.5), 1.8, tipPaint);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - 5, 15, 10, 14),
          const Radius.circular(3),
        ),
        bodyPaint,
      );
      canvas.drawRect(Rect.fromLTWH(cx - 4, 19, 8, 5), tipPaint);
    } else {
      // Fountain pen nib with center slit
      final nib = Path()
        ..moveTo(cx, 6.5)
        ..lineTo(cx + 5.2, 15)
        ..lineTo(cx - 5.2, 15)
        ..close();
      canvas.drawPath(nib, tipPaint);
      canvas.drawLine(
        Offset(cx, 7.5),
        Offset(cx, 12.5),
        Paint()
          ..color = Colors.white.withAlpha(200)
          ..strokeWidth = 1.0,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - 5.5, 15, 11, 14),
          const Radius.circular(3),
        ),
        bodyPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PenNibIconPainter oldDelegate) =>
      oldDelegate.tipColor != tipColor ||
      oldDelegate.bodyColor != bodyColor ||
      oldDelegate.toolType != toolType;
}

// =============================================================================
// 6-BUTTON FLOATING IMAGE ACTION PILL
// =============================================================================

class ImageActionPill extends StatelessWidget {
  final VoidCallback onCropRect;
  final VoidCallback onCropFreehand;
  final VoidCallback onCopy;
  final VoidCallback onCut;
  final VoidCallback onAddToStickers;
  final VoidCallback onDelete;

  const ImageActionPill({
    super.key,
    required this.onCropRect,
    required this.onCropFreehand,
    required this.onCopy,
    required this.onCut,
    required this.onAddToStickers,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 10,
      borderRadius: BorderRadius.circular(22),
      color: EditorColors.obsidianSurface,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white12),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _pillItem(Icons.crop_rounded, 'Cắt chữ nhật', onCropRect),
              _pillItem(Icons.gesture_rounded, 'Cắt tùy chỉnh', onCropFreehand),
              _pillItem(Icons.content_copy_rounded, 'Sao chép', onCopy),
              _pillItem(Icons.content_cut_rounded, 'Cắt', onCut),
              _pillItem(
                Icons.bookmark_add_outlined,
                'Thêm vào hình dán',
                onAddToStickers,
              ),
              _pillItem(
                Icons.delete_outline_rounded,
                'Xóa',
                onDelete,
                color: const Color(0xFFEF4444),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pillItem(
    IconData icon,
    String label,
    VoidCallback onTap, {
    Color color = Colors.white,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// PRO LASSO FLOATING CONTEXT MENU
// =============================================================================

class LassoFloatingMenu extends StatelessWidget {
  final int selectedCount;
  final bool hasClipboard;
  final VoidCallback onCut;
  final VoidCallback onCopy;
  final VoidCallback onPaste;
  final VoidCallback onDuplicate;
  final VoidCallback onRotate;
  final VoidCallback onScaleUp;
  final VoidCallback onScaleDown;
  final ValueChanged<Color> onRecolor;
  final VoidCallback onDelete;
  final VoidCallback onClear;

  const LassoFloatingMenu({
    super.key,
    required this.selectedCount,
    required this.hasClipboard,
    required this.onCut,
    required this.onCopy,
    required this.onPaste,
    required this.onDuplicate,
    required this.onRotate,
    required this.onScaleUp,
    required this.onScaleDown,
    required this.onRecolor,
    required this.onDelete,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 10,
      borderRadius: BorderRadius.circular(24),
      color: EditorColors.obsidianSurface,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white12),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$selectedCount mục',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: EditorColors.activeBlue,
                ),
              ),
              const SizedBox(width: 6),
              _menuBtn(Icons.content_cut_rounded, 'Cắt', onCut),
              _menuBtn(Icons.content_copy_rounded, 'Sao chép', onCopy),
              if (hasClipboard)
                _menuBtn(Icons.content_paste_rounded, 'Dán', onPaste),
              _menuBtn(
                Icons.control_point_duplicate_rounded,
                'Nhân bản',
                onDuplicate,
              ),
              _menuBtn(Icons.rotate_right_rounded, 'Xoay +15°', onRotate),
              _menuBtn(Icons.zoom_in_rounded, 'Phóng to', onScaleUp),
              _menuBtn(Icons.zoom_out_rounded, 'Thu nhỏ', onScaleDown),
              PopupMenuButton<Color>(
                tooltip: 'Đổi màu',
                icon: const Icon(
                  Icons.palette_outlined,
                  size: 18,
                  color: Colors.white,
                ),
                onSelected: onRecolor,
                itemBuilder: (_) => [
                  for (final c in EditorColors.penSwatches)
                    PopupMenuItem(
                      value: c,
                      child: Row(
                        children: [
                          Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.black26),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // ignore: deprecated_member_use
                          Text('#${c.value.toRadixString(16).substring(2).toUpperCase()}'),
                        ],
                      ),
                    ),
                ],
              ),
              _menuBtn(
                Icons.delete_outline_rounded,
                'Xóa',
                onDelete,
                color: const Color(0xFFEF4444),
              ),
              _menuBtn(Icons.close_rounded, 'Bỏ chọn', onClear),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuBtn(
    IconData icon,
    String tooltip,
    VoidCallback onTap, {
    Color color = Colors.white,
  }) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 18, color: color),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      onPressed: onTap,
    );
  }
}

// =============================================================================
// HUAWEI NOTES PEN SETTINGS POPOVER (Star Toggle, 4 Nibs, Size/Opacity/Pressure,
// Eyedropper + Color Wheel + 5 Swatches, Show Favorites Bar Toggle)
// =============================================================================

Future<void> showPenSettingsSheet({
  required BuildContext context,
  required AppState appState,
  required EditorTool currentTool,
  required Color currentColor,
  required double strokeWidth,
  required double opacity,
  required double pressureSensitivity,
  required bool autoNeaten,
  required double smoothingStrength,
  required ValueChanged<EditorTool> onSelectPen,
  required ValueChanged<Color> onSelectColor,
  required VoidCallback onPickEyedropper,
  required VoidCallback onOpenColorWheel,
  required void Function({
    double? width,
    double? opacity,
    double? pressureSensitivity,
    bool? autoNeaten,
    double? smoothingStrength,
    bool? scribbleToErase,
    bool? holdToSnapShape,
  }) onUpdate,
}) {
  EditorTool tool = currentTool;
  Color color = currentColor;
  double width = strokeWidth;
  double localOpacity = opacity;
  double localPressure = pressureSensitivity;
  bool neaten = autoNeaten;
  double smooth = smoothingStrength;
  bool scribble = appState.scribbleToErase;
  bool holdShape = appState.holdToSnapShape;
  bool showFavBar = appState.showFavoritesBar;
  bool showHsvPicker = false;

  final bool isHighlighter = tool == EditorTool.highlighter;
  final swatches = isHighlighter
      ? EditorColors.highlighterSwatches.take(5).toList()
      : EditorColors.penSwatches.take(5).toList();

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setModalState) {
          if (showHsvPicker) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                4,
                20,
                20 + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: _HuaweiHsvColorPicker(
                initialColor: color,
                onBack: () => setModalState(() => showHsvPicker = false),
                onColorChanged: (c) {
                  setModalState(() => color = c);
                  onSelectColor(c);
                },
                onPickEyedropper: () {
                  Navigator.pop(ctx);
                  onPickEyedropper();
                },
              ),
            );
          }

          final bool isStarred = appState.isPenStarred(
            tool.toStrokeToolType(),
            // ignore: deprecated_member_use
            color.value,
            width,
            opacity: localOpacity,
          );

          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header: Tool Title Centered + Gold Star Toggle
                Row(
                  children: [
                    const SizedBox(width: 40),
                    Expanded(
                      child: Text(
                        tool.labelVi,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: isStarred
                          ? 'Bỏ ghim khỏi thanh ưa thích'
                          : 'Ghim bút này vào thanh ưa thích bên trái',
                      icon: Icon(
                        isStarred
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: isStarred ? EditorColors.starGold : null,
                        size: 24,
                      ),
                      onPressed: () {
                        appState.toggleStarPen(
                          PenPreset(
                            id: 'star_${DateTime.now().millisecondsSinceEpoch}',
                            toolType: tool.toStrokeToolType(),
                            // ignore: deprecated_member_use
                            colorValue: color.value,
                            width: width,
                            opacity: localOpacity,
                            pressureSensitivity: localPressure,
                            label: tool.labelVi,
                          ),
                        );
                        setModalState(() {});
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // 4 Realistic Illustrated Pen Nibs with Active Lift
                if (!isHighlighter)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final p in const [
                        EditorTool.ballpointPen,
                        EditorTool.fountainPen,
                        EditorTool.pencil,
                        EditorTool.brushPen,
                      ])
                        GestureDetector(
                          onTap: () {
                            final maxForP =
                                p == EditorTool.brushPen ? 12.0 : 5.0;
                            setModalState(() {
                              tool = p;
                              width = width.clamp(0.5, maxForP);
                            });
                            onSelectPen(p);
                            onUpdate(width: width);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            transform: Matrix4.translationValues(
                              0,
                              tool == p ? -6 : 0,
                              0,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: tool == p
                                  ? EditorColors.activeBlue.withAlpha(36)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: tool == p
                                    ? EditorColors.activeBlue
                                    : Colors.transparent,
                              ),
                            ),
                            child: Column(
                              children: [
                                SizedBox(
                                  width: 34,
                                  height: 34,
                                  child: CustomPaint(
                                    painter: _PenNibIconPainter(
                                      tipColor: color,
                                      bodyColor: Theme.of(ctx)
                                          .colorScheme
                                          .onSurface,
                                      toolType: p.toStrokeToolType(),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  p.labelVi,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: tool == p
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 12),

                // Tapered Size Slider (0.5 -> 5.0 for writing pens, 0.5 -> 12.0 for brush, 4.0 -> 32.0 for highlighter)
                Builder(
                  builder: (_) {
                    final double minW = isHighlighter ? 4.0 : 0.5;
                    final double maxW = isHighlighter
                        ? 32.0
                        : (tool == EditorTool.brushPen ? 12.0 : 5.0);
                    final double clampedW = width.clamp(minW, maxW);
                    return Row(
                      children: [
                        SizedBox(
                          width: 44,
                          child: Text(
                            clampedW.toStringAsFixed(1),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const Text('Cỡ nét', style: TextStyle(fontSize: 12.5)),
                        Expanded(
                          child: Slider(
                            value: clampedW,
                            min: minW,
                            max: maxW,
                            divisions: isHighlighter
                                ? 28
                                : (tool == EditorTool.brushPen ? 23 : 45),
                            onChanged: (v) {
                              setModalState(() => width = v);
                              onUpdate(width: v);
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),

                // Opacity Slider
                Row(
                  children: [
                    SizedBox(
                      width: 44,
                      child: Text(
                        '${(localOpacity * 100).round()}%',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const Text('Độ mờ', style: TextStyle(fontSize: 12.5)),
                    Expanded(
                      child: Slider(
                        value: localOpacity.clamp(0.1, 1.0),
                        min: 0.1,
                        max: 1.0,
                        onChanged: (v) {
                          setModalState(() => localOpacity = v);
                          onUpdate(opacity: v);
                        },
                      ),
                    ),
                  ],
                ),

                // Pressure Sensitivity Slider
                if (!isHighlighter)
                  Row(
                    children: [
                      SizedBox(
                        width: 44,
                        child: Text(
                          '${(localPressure * 100).round()}%',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const Text('Áp lực', style: TextStyle(fontSize: 12.5)),
                      Expanded(
                        child: Slider(
                          value: localPressure.clamp(0.0, 1.0),
                          min: 0.0,
                          max: 1.0,
                          onChanged: (v) {
                            setModalState(() => localPressure = v);
                            onUpdate(pressureSensitivity: v);
                          },
                        ),
                      ),
                    ],
                  ),

                // Color Row: Eyedropper + Color Wheel + 5 Swatches
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      tooltip: 'Ống nhỏ giọt hút màu trên trang',
                      icon: const Icon(Icons.colorize_rounded, size: 20),
                      onPressed: () {
                        Navigator.pop(ctx);
                        onPickEyedropper();
                      },
                    ),
                    GestureDetector(
                      onTap: () => setModalState(() => showHsvPicker = true),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: SweepGradient(
                            colors: [
                              Colors.red,
                              Colors.yellow,
                              Colors.green,
                              Colors.cyan,
                              Colors.blue,
                              Colors.purple,
                              Colors.red,
                            ],
                          ),
                        ),
                        child: Center(
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                          ),
                        ),
                      ),
                    ),
                    for (final s in swatches)
                      GestureDetector(
                        onTap: () {
                          setModalState(() => color = s);
                          onSelectColor(s);
                        },
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: s,
                            shape: BoxShape.circle,
                            border: Border.all(
                              // ignore: deprecated_member_use
                              color: color.value == s.value
                                  ? EditorColors.activeBlue
                                  : Colors.white30,
                              // ignore: deprecated_member_use
                              width: color.value == s.value ? 2.5 : 1.0,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                _CuratedColorGrid(
                  selectedColor: color,
                  onSelect: (c) {
                    setModalState(() => color = c);
                    onSelectColor(c);
                  },
                ),

                const Divider(height: 20),

                // Compact Smoothing & Smart Toggles
                Row(
                  children: [
                    const Text('Tự nắn nét:', style: TextStyle(fontSize: 12.5)),
                    Expanded(
                      child: Slider(
                        value: smooth,
                        min: 0.0,
                        max: 1.0,
                        divisions: 10,
                        onChanged: (v) {
                          setModalState(() {
                            smooth = v;
                            neaten = v > 0.05;
                          });
                          onUpdate(autoNeaten: neaten, smoothingStrength: v);
                        },
                      ),
                    ),
                    Text('${(smooth * 100).round()}%',
                        style: const TextStyle(fontSize: 12)),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: FilterChip(
                        label: const Text('Gạch xóa nhanh',
                            style: TextStyle(fontSize: 11.5)),
                        selected: scribble,
                        onSelected: (v) {
                          setModalState(() => scribble = v);
                          onUpdate(scribbleToErase: v);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilterChip(
                        label: const Text('Giữ vẽ hình học',
                            style: TextStyle(fontSize: 11.5)),
                        selected: holdShape,
                        onSelected: (v) {
                          setModalState(() => holdShape = v);
                          onUpdate(holdToSnapShape: v);
                        },
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Hiển thị thanh mục ưa thích',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                  value: showFavBar,
                  onChanged: (v) {
                    setModalState(() => showFavBar = v);
                    appState.setShowFavoritesBar(v);
                  },
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

Future<void> showEraserSettingsSheet({
  required BuildContext context,
  required EraserMode currentMode,
  required ValueChanged<EraserMode> onSelectMode,
  required VoidCallback onClearCurrentPage,
  double eraserRadius = 18.0,
  ValueChanged<double>? onEraserRadiusChanged,
}) {
  // Keep local state OUTSIDE modal builder so parent rebuilds NEVER reset the slider!
  EraserMode localMode = currentMode;
  double localRadius = eraserRadius.clamp(5.0, 35.0);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (sheetCtx, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text(
                    'Tùy chọn Tẩy',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                // Eraser size slider + live circular preview + 3 quick presets
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Cỡ tẩy',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${localRadius.round()} px',
                            style: const TextStyle(
                              color: EditorColors.activeBlue,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          const Spacer(),
                          // Live circular eraser size preview
                          Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.grey.withAlpha(26),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.grey.withAlpha(60),
                              ),
                            ),
                            child: Container(
                              width: (localRadius * 0.85).clamp(8.0, 38.0),
                              height: (localRadius * 0.85).clamp(8.0, 38.0),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: EditorColors.activeBlue.withAlpha(45),
                                border: Border.all(
                                  color: EditorColors.activeBlue,
                                  width: 1.6,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: localRadius,
                        min: 5.0,
                        max: 35.0,
                        divisions: 30,
                        activeColor: EditorColors.activeBlue,
                        onChanged: (val) {
                          setSheetState(() => localRadius = val);
                          onEraserRadiusChanged?.call(val);
                        },
                      ),
                      Row(
                        children: [
                          for (final preset in const [
                            ('Nhỏ', 8.0),
                            ('Vừa', 16.0),
                            ('Lớn', 28.0),
                          ])
                            Expanded(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                child: ChoiceChip(
                                  label: Center(
                                    child: Text(
                                      '${preset.$1} (${preset.$2.round()})',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  selected: (localRadius - preset.$2).abs() < 2.0,
                                  onSelected: (_) {
                                    setSheetState(() => localRadius = preset.$2);
                                    onEraserRadiusChanged?.call(preset.$2);
                                  },
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                const Divider(),
                RadioListTile<EraserMode>(
                  value: EraserMode.stroke,
                  groupValue: localMode,
                  title: const Text('Xóa nguyên nét (Stroke Eraser)'),
                  subtitle: const Text(
                    'Chạm vào bất kỳ phần nào của nét để xóa cả nét',
                  ),
                  onChanged: (v) {
                    if (v != null) {
                      setSheetState(() => localMode = v);
                      onSelectMode(v);
                    }
                  },
                ),
                RadioListTile<EraserMode>(
                  value: EraserMode.precision,
                  groupValue: localMode,
                  title: const Text('Xóa theo điểm (Precision Eraser)'),
                  subtitle: const Text('Cắt xóa chính xác từng đoạn nhỏ'),
                  onChanged: (v) {
                    if (v != null) {
                      setSheetState(() => localMode = v);
                      onSelectMode(v);
                    }
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(
                    Icons.delete_sweep_outlined,
                    color: Color(0xFFEF4444),
                  ),
                  title: const Text(
                    'Xóa toàn bộ nét viết trên trang này',
                    style: TextStyle(color: Color(0xFFEF4444)),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    onClearCurrentPage();
                  },
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Future<void> showColorPaletteSheet({
  required BuildContext context,
  required bool isHighlighter,
  required Color currentColor,
  required ValueChanged<Color> onSelectColor,
  VoidCallback? onPickEyedropper,
}) {
  Color localColor = currentColor;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (sheetCtx, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          24 + MediaQuery.of(sheetCtx).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HuaweiHsvColorPicker(
              initialColor: localColor,
              title: isHighlighter ? 'Màu bút dạ quang' : 'Bảng màu tùy chỉnh',
              onBack: () => Navigator.pop(ctx),
              onColorChanged: (c) {
                setSheetState(() => localColor = c);
                onSelectColor(c);
              },
              onPickEyedropper: onPickEyedropper == null
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      onPickEyedropper();
                    },
            ),
            const SizedBox(height: 14),
            _CuratedColorGrid(
              selectedColor: localColor,
              onSelect: (c) {
                setSheetState(() => localColor = c);
                onSelectColor(c);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> showPageTemplateSheet({
  required BuildContext context,
  required PaperTemplateType currentTemplate,
  required PaperColorType currentColor,
  required void Function(PaperTemplateType template, PaperColorType color) onApply,
}) {
  PaperTemplateType selectedTemplate = currentTemplate;
  PaperColorType selectedColor = currentColor;

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setModalState) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Mẫu giấy & Màu nền trang (10 mẫu tuyển chọn)',
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (final c in PaperColorType.values)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            label: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: PaperTemplateInfo.previewColor(c),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.black26),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    PaperTemplateInfo.colorLabel(c),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            selected: selectedColor == c,
                            onSelected: (_) {
                              setModalState(() => selectedColor = c);
                              onApply(selectedTemplate, selectedColor);
                            },
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 310,
                  child: GridView.count(
                    crossAxisCount: 4,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 0.78,
                    children: [
                      for (final tpl in PaperTemplateInfo.orderedTemplates)
                        InkWell(
                          onTap: () {
                            setModalState(() => selectedTemplate = tpl);
                            onApply(selectedTemplate, selectedColor);
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selectedTemplate == tpl
                                    ? EditorColors.activeBlue
                                    : Theme.of(ctx).colorScheme.outlineVariant,
                                width: selectedTemplate == tpl ? 2.2 : 1.0,
                              ),
                            ),
                            child: Column(
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(8),
                                    ),
                                    child: CustomPaint(
                                      painter: PaperTemplatePainter(
                                        templateType: tpl,
                                        paperColor: selectedColor,
                                      ),
                                      size: Size.infinite,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 4,
                                  ),
                                  child: Text(
                                    PaperTemplateInfo.templateLabel(tpl),
                                    maxLines: 2,
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

// =============================================================================
// RIGHT OVERFLOW SETTINGS DRAWER
// =============================================================================

class EditorSettingsDrawer extends StatelessWidget {
  final Notebook notebook;
  final int activePageIndex;
  final bool isCurrentPageBookmarked;
  final double refreshRateHz;
  final AppState appState;
  final VoidCallback onToggleBookmark;
  final VoidCallback onOpenTemplateSwitcher;
  final VoidCallback onToggleOrientation;
  final VoidCallback onClearPage;
  final VoidCallback onDeletePage;
  final VoidCallback onImportPdf;
  final VoidCallback onExportPdf;
  final VoidCallback onPickPdfExportDir;
  final VoidCallback onToggleLockNotebook;
  final VoidCallback onCheckForUpdate;
  final int audioRecordingsCount;
  final VoidCallback? onOpenAudioRecordings;

  const EditorSettingsDrawer({
    super.key,
    required this.notebook,
    required this.activePageIndex,
    required this.isCurrentPageBookmarked,
    required this.refreshRateHz,
    required this.appState,
    required this.onToggleBookmark,
    required this.onOpenTemplateSwitcher,
    required this.onToggleOrientation,
    required this.onClearPage,
    required this.onDeletePage,
    required this.onImportPdf,
    required this.onExportPdf,
    required this.onPickPdfExportDir,
    required this.onToggleLockNotebook,
    required this.onCheckForUpdate,
    this.audioRecordingsCount = 0,
    this.onOpenAudioRecordings,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Drawer(
      width: 320,
      backgroundColor: isDark ? EditorColors.obsidianSurface : Colors.white,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          children: [
            Row(
              children: [
                Text(
                  'Trang ${activePageIndex + 1} / ${notebook.pages.length}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: EditorColors.activeBlue.withAlpha(36),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${refreshRateHz.round()}Hz',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: EditorColors.activeBlue,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _drawerTile(
              icon: isCurrentPageBookmarked
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              title: isCurrentPageBookmarked
                  ? 'Bỏ đánh dấu trang'
                  : 'Đánh dấu trang',
              onTap: () {
                Navigator.pop(context);
                onToggleBookmark();
              },
            ),
            _drawerTile(
              icon: Icons.grid_on_rounded,
              title: 'Đổi mẫu giấy & màu nền',
              onTap: () {
                Navigator.pop(context);
                onOpenTemplateSwitcher();
              },
            ),
            _drawerTile(
              icon: Icons.screen_rotation_rounded,
              title: 'Xoay ngang / dọc trang',
              onTap: () {
                Navigator.pop(context);
                onToggleOrientation();
              },
            ),
            _drawerTile(
              icon: Icons.cleaning_services_outlined,
              title: 'Xóa nội dung trang hiện tại',
              onTap: () {
                Navigator.pop(context);
                onClearPage();
              },
            ),
            if (notebook.pages.length > 1)
              _drawerTile(
                icon: Icons.delete_outline_rounded,
                title: 'Xóa trang này',
                color: const Color(0xFFEF4444),
                onTap: () {
                  Navigator.pop(context);
                  onDeletePage();
                },
              ),
            const Divider(height: 24),
            if (onOpenAudioRecordings != null)
              _drawerTile(
                icon: Icons.mic_none_rounded,
                title: audioRecordingsCount > 0
                    ? 'Bản ghi âm trang này ($audioRecordingsCount)'
                    : 'Ghi âm bài giảng',
                onTap: () {
                  Navigator.pop(context);
                  onOpenAudioRecordings!();
                },
              ),
            _sectionLabel('Xuất & Nhập tài liệu'),
            _drawerTile(
              icon: Icons.picture_as_pdf_outlined,
              title: 'Nhập PDF làm nền ghi chú',
              onTap: () {
                Navigator.pop(context);
                onImportPdf();
              },
            ),
            _drawerTile(
              icon: Icons.ios_share_rounded,
              title: 'Xuất PDF / Chia sẻ / In',
              onTap: () {
                Navigator.pop(context);
                onExportPdf();
              },
            ),
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: const Icon(Icons.folder_outlined, size: 20),
              title: const Text(
                'Thư mục xuất PDF mặc định',
                style: TextStyle(fontSize: 13.5),
              ),
              subtitle: Text(
                appState.pdfExportDirectory ?? 'Documents/ChemNote',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5),
              ),
              onTap: () {
                Navigator.pop(context);
                onPickPdfExportDir();
              },
            ),
            const Divider(height: 24),
            _sectionLabel('Cài đặt nâng cao (MatePad & M-Pencil 3)'),
            _drawerTile(
              icon: notebook.isLocked
                  ? Icons.lock_open_rounded
                  : Icons.lock_outline_rounded,
              title: notebook.isLocked
                  ? 'Mở khóa sổ tay'
                  : 'Khóa sổ tay bằng mã PIN',
              onTap: () {
                Navigator.pop(context);
                onToggleLockNotebook();
              },
            ),
            SwitchListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: const Text('Cuộn dọc liên tiếp'),
              subtitle: Text(
                appState.verticalContinuousScroll
                    ? 'Đang bật (Kéo xuống để thêm trang)'
                    : 'Đang dùng lật trang ngang',
                style: const TextStyle(fontSize: 11.5),
              ),
              value: appState.verticalContinuousScroll,
              onChanged: appState.setVerticalContinuousScroll,
            ),
            SwitchListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: const Text('Chuyển động giấy tự do'),
              value: appState.freePaperMovement,
              onChanged: appState.setFreePaperMovement,
            ),
            SwitchListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: const Text('Theo dõi mức thu phóng nét'),
              value: appState.zoomAdaptiveStroke,
              onChanged: appState.setZoomAdaptiveStroke,
            ),
            SwitchListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: const Text('Chạm đúp để thu phóng'),
              value: appState.doubleTapToZoom,
              onChanged: appState.setDoubleTapToZoom,
            ),
            SwitchListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: const Text('Cử chỉ 2/3 ngón (Undo/Redo)'),
              value: appState.quickGesturesEnabled,
              onChanged: appState.setQuickGesturesEnabled,
            ),
            SwitchListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: const Text('Gõ đúp M-Pencil 3 đổi Tẩy'),
              value: appState.mPencilDoubleTapEraser,
              onChanged: appState.setMPencilDoubleTapEraser,
            ),
            SwitchListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: const Text('Luôn bật màn hình khi ghi chép'),
              value: appState.keepScreenAwake,
              onChanged: (v) => appState.setKeepScreenAwake(v),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: const Text('Chế độ Chỉ đọc (Read-Only)'),
              subtitle: const Text(
                'Tạm khóa viết/xoá để đọc tài liệu an toàn',
                style: TextStyle(fontSize: 11.5),
              ),
              value: appState.readOnlyMode,
              onChanged: appState.setReadOnlyMode,
            ),
            SwitchListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: const Text('Giao diện Obsidian Tối'),
              value: appState.isDarkMode,
              onChanged: appState.setDarkMode,
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Tốc độ lướt trang',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${appState.scrollSpeedMultiplier.toStringAsFixed(1)}×',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: EditorColors.activeBlue,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: appState.scrollSpeedMultiplier.clamp(1.0, 25.0),
                    min: 1.0,
                    max: 25.0,
                    divisions: 24,
                    activeColor: EditorColors.activeBlue,
                    onChanged: appState.setScrollSpeedMultiplier,
                  ),
                ],
              ),
            ),
            const Divider(height: 24),
            _drawerTile(
              icon: Icons.system_update_alt_rounded,
              title: 'Kiểm tra cập nhật APK (v$kAppVersion)',
              color: EditorColors.activeBlue,
              onTap: () {
                Navigator.pop(context);
                onCheckForUpdate();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: EditorColors.activeBlue,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _drawerTile({
    required IconData icon,
    required String title,
    Color? color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(icon, size: 20, color: color),
      title: Text(title, style: TextStyle(fontSize: 13.5, color: color)),
      onTap: onTap,
    );
  }
}

// =============================================================================
// COMPACT AUDIO NOTE REPLAY BAR (Synced with Handwriting Strokes)
// =============================================================================

class AudioReplayBar extends StatelessWidget {
  final AudioRecording recording;
  final int recordingIndex;
  final int totalRecordings;
  final bool isPlaying;
  final int positionMs;
  final double speed;
  final VoidCallback onTogglePlay;
  final ValueChanged<int> onSeek;
  final VoidCallback onCycleSpeed;
  final VoidCallback? onShowList;
  final VoidCallback? onStartNewRecording;
  final VoidCallback onDelete;
  final VoidCallback? onClose;

  const AudioReplayBar({
    super.key,
    required this.recording,
    this.recordingIndex = 1,
    this.totalRecordings = 1,
    required this.isPlaying,
    required this.positionMs,
    required this.speed,
    required this.onTogglePlay,
    required this.onSeek,
    required this.onCycleSpeed,
    this.onShowList,
    this.onStartNewRecording,
    required this.onDelete,
    this.onClose,
  });

  String _formatMs(int ms) {
    final totalSec = (ms / 1000).floor().clamp(0, 35999);
    final m = (totalSec ~/ 60).toString().padLeft(2, '0');
    final s = (totalSec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? EditorColors.obsidianSurface : Colors.white;
    final border =
        isDark ? Colors.white.withAlpha(20) : Colors.black.withAlpha(18);
    final maxMs = recording.durationMs > 0 ? recording.durationMs : 1000;
    final clampedPos = positionMs.clamp(0, maxMs);

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: bg,
        border: Border(bottom: BorderSide(color: border)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: isPlaying ? 'Tạm dừng' : 'Phát lại ghi âm đồng bộ nét viết',
            icon: Icon(
              isPlaying
                  ? Icons.pause_circle_filled_rounded
                  : Icons.play_circle_filled_rounded,
              color: EditorColors.activeBlue,
              size: 26,
            ),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            onPressed: onTogglePlay,
          ),
          const SizedBox(width: 4),
          if (onShowList != null)
            InkWell(
              onTap: onShowList,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  'Ghi âm ($recordingIndex)',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
          else
            Text(
              'Ghi âm ($recordingIndex)',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          const SizedBox(width: 6),
          Text(
            _formatMs(clampedPos),
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.5,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: clampedPos.toDouble(),
                min: 0,
                max: maxMs.toDouble(),
                activeColor: EditorColors.activeBlue,
                onChanged: (v) => onSeek(v.round()),
              ),
            ),
          ),
          Text(
            _formatMs(maxMs),
            style: const TextStyle(fontSize: 11.5, color: Colors.grey),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: onCycleSpeed,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: EditorColors.activeBlue.withAlpha(32),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${speed == speed.roundToDouble() ? speed.toInt() : speed}×',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: EditorColors.activeBlue,
                ),
              ),
            ),
          ),
          if (onShowList != null) ...[
            const SizedBox(width: 4),
            Tooltip(
              message: 'Danh sách bản ghi âm ($totalRecordings)',
              child: InkWell(
                onTap: onShowList,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withAlpha(18)
                        : Colors.black.withAlpha(12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.format_list_bulleted_rounded, size: 16),
                      if (totalRecordings > 1) ...[
                        const SizedBox(width: 3),
                        Text(
                          '$totalRecordings',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
          if (onStartNewRecording != null)
            IconButton(
              tooltip: 'Ghi âm mới',
              icon: const Icon(
                Icons.mic_none_rounded,
                size: 19,
                color: EditorColors.activeBlue,
              ),
              visualDensity: VisualDensity.compact,
              onPressed: onStartNewRecording,
            ),
          IconButton(
            tooltip: 'Xóa bản ghi âm này',
            icon: const Icon(
              Icons.delete_outline_rounded,
              size: 18,
              color: Color(0xFFEF4444),
            ),
            visualDensity: VisualDensity.compact,
            onPressed: onDelete,
          ),
          if (onClose != null)
            IconButton(
              tooltip: 'Ẩn thanh ghi âm',
              icon: const Icon(
                Icons.close_rounded,
                size: 18,
                color: Colors.grey,
              ),
              visualDensity: VisualDensity.compact,
              onPressed: onClose,
            ),
        ],
      ),
    );
  }
}

class AudioLiveRecordingBar extends StatelessWidget {
  final int elapsedMs;
  final int totalRecordings;
  final VoidCallback onStop;
  final VoidCallback? onShowList;

  const AudioLiveRecordingBar({
    super.key,
    required this.elapsedMs,
    this.totalRecordings = 0,
    required this.onStop,
    this.onShowList,
  });

  String _formatMs(int ms) {
    final totalSec = (ms / 1000).floor().clamp(0, 35999);
    final m = (totalSec ~/ 60).toString().padLeft(2, '0');
    final s = (totalSec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? EditorColors.obsidianSurface : Colors.white;
    final border =
        isDark ? Colors.white.withAlpha(20) : Colors.black.withAlpha(18);

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: bg,
        border: Border(bottom: BorderSide(color: border)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: Color(0xFFEF4444),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'Đang ghi âm...',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            _formatMs(elapsedMs),
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (totalRecordings > 0 && onShowList != null) ...[
            const SizedBox(width: 10),
            IconButton(
              tooltip: 'Danh sách bản ghi âm ($totalRecordings)',
              icon: const Icon(Icons.format_list_bulleted_rounded, size: 19),
              visualDensity: VisualDensity.compact,
              onPressed: onShowList,
            ),
          ],
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onStop,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: const Size(0, 30),
            ),
            icon: const Icon(Icons.stop_rounded, size: 16),
            label: const Text(
              'Dừng',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// Curated 5x6 Harmonized Study Color Palette Grid (30 colors, 1-tap selection).
class _CuratedColorGrid extends StatelessWidget {
  final Color selectedColor;
  final ValueChanged<Color> onSelect;

  const _CuratedColorGrid({
    required this.selectedColor,
    required this.onSelect,
  });

  static const List<Color> _palette30 = [
    // Row 1: Blacks & Grays
    Color(0xFF0F172A),
    Color(0xFF334155),
    Color(0xFF64748B),
    Color(0xFF94A3B8),
    Color(0xFFCBD5E1),
    Color(0xFFFFFFFF),
    // Row 2: Blues & Indigos
    Color(0xFF1E3A8A),
    Color(0xFF1D4ED8),
    Color(0xFF2563EB),
    Color(0xFF3B82F6),
    Color(0xFF0EA5E9),
    Color(0xFF4F46E5),
    // Row 3: Greens & Teals
    Color(0xFF064E3B),
    Color(0xFF047857),
    Color(0xFF10B981),
    Color(0xFF16A34A),
    Color(0xFF0D9488),
    Color(0xFF84CC16),
    // Row 4: Reds, Pinks & Oranges
    Color(0xFF991B1B),
    Color(0xFFDC2626),
    Color(0xFFEF4444),
    Color(0xFFEC4899),
    Color(0xFFF97316),
    Color(0xFFEA580C),
    // Row 5: Yellows, Purples & Browns
    Color(0xFFEAB308),
    Color(0xFFFACC15),
    Color(0xFF9333EA),
    Color(0xFF7C3AED),
    Color(0xFF92400E),
    Color(0xFF78350F),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int row = 0; row < 5; row++)
          Padding(
            padding: EdgeInsets.only(bottom: row < 4 ? 6 : 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (int col = 0; col < 6; col++)
                  () {
                    final c = _palette30[row * 6 + col];
                    // ignore: deprecated_member_use
                    final isSel = selectedColor.value == c.value;
                    return GestureDetector(
                      onTap: () => onSelect(c),
                      child: Container(
                        width: 28,
                        height: 22,
                        decoration: BoxDecoration(
                          color: c,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isSel
                                ? EditorColors.activeBlue
                                : Colors.black26,
                            width: isSel ? 2.4 : 1.0,
                          ),
                        ),
                      ),
                    );
                  }(),
              ],
            ),
          ),
      ],
    );
  }
}

/// Huawei Notes-style 2D HSV Color Picker:
/// - Top `<` back button + title
/// - Left: 2D Saturation × Value gradient square with draggable white ring selector
/// - Right: Vertical Rainbow Hue spectrum bar with draggable white ring selector
/// - Bottom: `[Live color rectangle] | [Editable #HEX box] | [Eyedropper button]`
class _HuaweiHsvColorPicker extends StatefulWidget {
  final Color initialColor;
  final String title;
  final VoidCallback onBack;
  final ValueChanged<Color> onColorChanged;
  final VoidCallback? onPickEyedropper;

  const _HuaweiHsvColorPicker({
    required this.initialColor,
    this.title = 'Chọn màu tùy chỉnh',
    required this.onBack,
    required this.onColorChanged,
    this.onPickEyedropper,
  });

  @override
  State<_HuaweiHsvColorPicker> createState() => _HuaweiHsvColorPickerState();
}

class _HuaweiHsvColorPickerState extends State<_HuaweiHsvColorPicker> {
  late HSVColor _hsv;
  late final TextEditingController _hexController;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initialColor);
    _hexController = TextEditingController(text: _formatHex(widget.initialColor));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  String _formatHex(Color c) {
    // ignore: deprecated_member_use
    final hex = (c.value & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0');
    return '#$hex';
  }

  void _updateHsv(HSVColor next) {
    final c = next.toColor();
    setState(() {
      _hsv = next;
      final formatted = _formatHex(c);
      if (_hexController.text.toUpperCase() != formatted) {
        _hexController.text = formatted;
      }
    });
    widget.onColorChanged(c);
  }

  void _onHexSubmitted(String raw) {
    final cleaned = raw.trim().replaceFirst('#', '');
    if (cleaned.length == 6) {
      final parsed = int.tryParse('FF$cleaned', radix: 16);
      if (parsed != null) {
        final c = Color(parsed);
        _updateHsv(HSVColor.fromColor(c));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color currentColor = _hsv.toColor();
    final Color pureHueColor = HSVColor.fromAHSV(1.0, _hsv.hue, 1.0, 1.0).toColor();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Top header with `<` back button
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded, size: 26),
              tooltip: 'Quay lại',
              onPressed: widget.onBack,
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: Text(
                widget.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 40),
          ],
        ),
        const SizedBox(height: 10),
        // Main 2D SV Square (left) + Vertical Rainbow Hue Bar (right)
        SizedBox(
          height: 196,
          child: Row(
            children: [
              // 2D Saturation × Value Square
              Expanded(
                child: LayoutBuilder(
                  builder: (ctx, box) {
                    void handleSv(Offset local) {
                      final s = (local.dx / box.maxWidth).clamp(0.0, 1.0);
                      final v = 1.0 - (local.dy / box.maxHeight).clamp(0.0, 1.0);
                      _updateHsv(_hsv.withSaturation(s).withValue(v));
                    }

                    return GestureDetector(
                      onPanDown: (d) => handleSv(d.localPosition),
                      onPanUpdate: (d) => handleSv(d.localPosition),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Horizontal white -> pure hue
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.white, pureHueColor],
                                ),
                              ),
                            ),
                            // Vertical transparent -> black
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Colors.transparent, Colors.black],
                                ),
                              ),
                            ),
                            // White ring selector
                            Positioned(
                              left: (_hsv.saturation * box.maxWidth - 10)
                                  .clamp(0.0, math.max(0.0, box.maxWidth - 20))
                                  .toDouble(),
                              top: ((1.0 - _hsv.value) * box.maxHeight - 10)
                                  .clamp(0.0, math.max(0.0, box.maxHeight - 20))
                                  .toDouble(),
                              child: IgnorePointer(
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: currentColor,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2.5,
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black45,
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 14),
              // Vertical Rainbow Hue Bar
              SizedBox(
                width: 28,
                child: LayoutBuilder(
                  builder: (ctx, box) {
                    void handleHue(Offset local) {
                      // Top = Red (360/0) -> Magenta (300) -> Blue (240) -> Cyan (180) -> Green (120) -> Yellow (60) -> Red (0)
                      final t = (local.dy / box.maxHeight).clamp(0.0, 1.0);
                      final hue = ((1.0 - t) * 360.0).clamp(0.0, 359.9);
                      _updateHsv(_hsv.withHue(hue));
                    }

                    final double hueT = (1.0 - (_hsv.hue / 360.0)).clamp(0.0, 1.0);
                    return GestureDetector(
                      onPanDown: (d) => handleHue(d.localPosition),
                      onPanUpdate: (d) => handleHue(d.localPosition),
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Color(0xFFFF0000), // Red
                                      Color(0xFFFF00FF), // Magenta
                                      Color(0xFF0000FF), // Blue
                                      Color(0xFF00FFFF), // Cyan
                                      Color(0xFF00FF00), // Green
                                      Color(0xFFFFFF00), // Yellow
                                      Color(0xFFFF0000), // Red
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: (hueT * box.maxHeight - 10)
                                .clamp(0.0, math.max(0.0, box.maxHeight - 20))
                                .toDouble(),
                            child: IgnorePointer(
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: pureHueColor,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2.5,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black45,
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Bottom row: [Live color rectangle] | [Editable #HEX box] | [Eyedropper]
        Row(
          children: [
            Container(
              width: 56,
              height: 38,
              decoration: BoxDecoration(
                color: currentColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.black26, width: 1.2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 38,
                child: TextField(
                  controller: _hexController,
                  onSubmitted: _onHexSubmitted,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    hintText: '#2F46B8',
                  ),
                ),
              ),
            ),
            if (widget.onPickEyedropper != null) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Ống nhỏ giọt hút màu trên trang',
                onPressed: widget.onPickEyedropper,
                icon: const Icon(Icons.colorize_rounded, size: 22),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
