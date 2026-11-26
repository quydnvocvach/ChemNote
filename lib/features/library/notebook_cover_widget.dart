import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models/notebook.dart';
import '../../core/theme/app_theme.dart';
import '../canvas/paper_templates.dart';

class NotebookCoverWidget extends StatelessWidget {
  final Notebook notebook;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onMorePressed;
  final bool selectionMode;
  final bool isSelected;

  const NotebookCoverWidget({
    super.key,
    required this.notebook,
    required this.onTap,
    this.onLongPress,
    this.onMorePressed,
    this.selectionMode = false,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final coverColor = Color(notebook.coverColorValue);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return RepaintBoundary(
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Thân bìa sổ tay (dịch sang phải 6px để nhường chỗ cho vòng lò xo)
                Positioned.fill(
                  left: 6,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(4),
                        bottomLeft: Radius.circular(4),
                        topRight: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
                      border: selectionMode && isSelected
                          ? Border.all(
                              color: AppTheme.accentBlue,
                              width: 2.6,
                            )
                          : null,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.16),
                          blurRadius: 12,
                          offset: const Offset(3, 6),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(4),
                        bottomLeft: Radius.circular(4),
                        topRight: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (notebook.customCoverImagePath != null &&
                              notebook.customCoverImagePath!.isNotEmpty)
                            Image.file(
                              File(notebook.customCoverImagePath!),
                              fit: BoxFit.cover,
                              cacheWidth: 420,
                              filterQuality: FilterQuality.medium,
                              gaplessPlayback: true,
                              errorBuilder: (_, __, ___) => _CoverBackground(
                                color: coverColor,
                                style: notebook.coverStyle,
                              ),
                            )
                          else if (notebook.useFirstPageAsCover)
                            CustomPaint(
                              painter: PaperTemplatePainter(
                                templateType: notebook.defaultTemplate,
                                paperColor: notebook.defaultPaperColor,
                                isLandscape: notebook.defaultOrientationLandscape,
                                isInfiniteWhiteboard: notebook.isWhiteboard,
                              ),
                            )
                          else
                            _CoverBackground(
                              color: coverColor,
                              style: notebook.coverStyle,
                            ),
                          // Nếp gấp gáy sổ
                          Positioned(
                            left: 0,
                            top: 0,
                            bottom: 0,
                            width: 14,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.black.withValues(alpha: 0.36),
                                    Colors.black.withValues(alpha: 0.06),
                                    Colors.white.withValues(alpha: 0.10),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Thanh biểu tượng trạng thái góc trên + nhãn tiêu đề
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 10, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    if (notebook.isWhiteboard)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.42),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.all_inclusive_rounded,
                                              size: 11,
                                              color: Colors.white,
                                            ),
                                            SizedBox(width: 3),
                                            Text(
                                              'Vô cực',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    else
                                      const SizedBox.shrink(),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (notebook.isFavorite) ...[
                                          const _BadgePill(
                                            icon: Icons.star_rounded,
                                            color: Color(0xFFFBBF24),
                                            tooltip: 'Ưa thích',
                                          ),
                                          const SizedBox(width: 4),
                                        ],
                                        if (notebook.isLocked) ...[
                                          const _BadgePill(
                                            icon: Icons.lock_rounded,
                                            color: Color(0xFFF87171),
                                            tooltip: 'Đã khóa mã PIN',
                                          ),
                                          const SizedBox(width: 4),
                                        ],
                                        _SyncStatusBadge(status: notebook.syncStatus),
                                      ],
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.94),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        notebook.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFF0F172A),
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12.5,
                                          height: 1.22,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${notebook.pages.length} trang',
                                        style: const TextStyle(
                                          color: Color(0xFF64748B),
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (selectionMode && isSelected)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: ColoredBox(
                                  color: AppTheme.accentBlue.withValues(alpha: 0.16),
                                ),
                              ),
                            ),
                          if (selectionMode)
                            Positioned(
                              left: 16,
                              top: 8,
                              child: IgnorePointer(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 140),
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppTheme.accentBlue
                                        : Colors.black.withValues(alpha: 0.48),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 1.8,
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black26,
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                  child: isSelected
                                      ? const Icon(
                                          Icons.check_rounded,
                                          size: 15,
                                          color: Colors.white,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Gáy lò xo xoắn kim loại chân thực (Spiral coil-ring spine)
                Positioned(
                  left: 0,
                  top: 10,
                  bottom: 10,
                  width: 18,
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _SpiralSpinePainter(isDark: isDark),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notebook.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      _formatDate(notebook.updatedAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (onMorePressed != null && !selectionMode)
                IconButton(
                  onPressed: onMorePressed,
                  icon: const Icon(Icons.more_vert_rounded, size: 18),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  tooltip: 'Tùy chọn sổ tay',
                ),
            ],
          ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    final yyyy = date.year;
    return '$dd/$mm/$yyyy';
  }
}

class _BadgePill extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;

  const _BadgePill({
    required this.icon,
    required this.color,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.34),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(icon, size: 13, color: color),
      ),
    );
  }
}

class _SyncStatusBadge extends StatelessWidget {
  final SyncStatus status;

  const _SyncStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String tooltip) = switch (status) {
      SyncStatus.synced => (
          Icons.cloud_done_rounded,
          const Color(0xFF10B981),
          'Đã đồng bộ Google Drive'
        ),
      SyncStatus.syncing => (
          Icons.cloud_sync_rounded,
          const Color(0xFF38BDF8),
          'Đang đồng bộ...'
        ),
      SyncStatus.pendingUpload => (
          Icons.cloud_upload_outlined,
          const Color(0xFFF59E0B),
          'Chờ tải lên Drive'
        ),
      SyncStatus.error => (
          Icons.cloud_off_rounded,
          const Color(0xFFEF4444),
          'Lỗi đồng bộ'
        ),
      SyncStatus.localOnly => (
          Icons.tablet_android_rounded,
          Colors.white70,
          'Chỉ lưu trên máy'
        ),
    };

    return _BadgePill(icon: icon, color: color, tooltip: tooltip);
  }
}

/// Vẽ các vòng lò xo xoắn kim loại (spiral coil rings) dọc theo gáy trái của sổ tay.
class _SpiralSpinePainter extends CustomPainter {
  final bool isDark;

  const _SpiralSpinePainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    const ringCount = 9;
    if (size.height <= 0) return;
    final step = size.height / (ringCount + 0.5);

    final holePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;

    final wireShadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;

    final wirePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFE2E8F0),
          Color(0xFF94A3B8),
          Color(0xFF475569),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < ringCount; i++) {
      final y = step * (i + 0.75);
      // Lỗ đục trên bìa sổ
      canvas.drawCircle(Offset(13.5, y), 2.8, holePaint);

      // Cung lò xo kim loại uốn từ mép trái vào lỗ đục
      final arcRect = Rect.fromLTWH(1.5, y - 3.6, 13.0, 7.2);
      canvas.drawArc(arcRect, math.pi * 0.65, math.pi * 1.45, false, wireShadow);
      canvas.drawArc(arcRect, math.pi * 0.65, math.pi * 1.45, false, wirePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SpiralSpinePainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

class _CoverBackground extends StatelessWidget {
  final Color color;
  final String style;

  const _CoverBackground({
    required this.color,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final darker = Color.lerp(color, Colors.black, 0.28) ?? color;
    final lighter = Color.lerp(color, Colors.white, 0.14) ?? color;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: style == 'gradient' ? [lighter, darker] : [color, darker],
        ),
      ),
      child: CustomPaint(
        painter: _CoverPatternPainter(style: style),
      ),
    );
  }
}

class _CoverPatternPainter extends CustomPainter {
  final String style;

  const _CoverPatternPainter({required this.style});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.13)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    if (style == 'molecular') {
      _drawHexagon(canvas, Offset(size.width * 0.65, size.height * 0.30), 26, paint);
      _drawHexagon(canvas, Offset(size.width * 0.88, size.height * 0.44), 20, paint);
      canvas.drawCircle(
        Offset(size.width * 0.65, size.height * 0.30),
        15,
        paint,
      );
    } else if (style == 'lab') {
      const step = 20.0;
      for (double x = 18; x < size.width; x += step) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
      for (double y = 0; y < size.height; y += step) {
        canvas.drawLine(Offset(14, y), Offset(size.width, y), paint);
      }
    } else if (style == 'classic') {
      final rect = Rect.fromLTWH(20, 12, size.width - 30, size.height - 24);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        paint,
      );
    }
  }

  void _drawHexagon(Canvas canvas, Offset center, double radius, Paint paint) {
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = (math.pi / 3) * i - math.pi / 6;
      final pt = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CoverPatternPainter oldDelegate) =>
      oldDelegate.style != style;
}
