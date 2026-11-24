import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../../core/models/drawing_elements.dart';

/// Cropping mode inside [ImageCropDialog].
enum ImageCropMode {
  rectangle,
  freehand,
}

/// Non-destructive crop output in normalized `0.0..1.0` coordinates relative to
/// the original full-resolution [ui.Image].
class ImageCropResult {
  final double cropLeft;
  final double cropTop;
  final double cropRight;
  final double cropBottom;
  final List<StrokePoint> freehandClipPath;

  const ImageCropResult({
    required this.cropLeft,
    required this.cropTop,
    required this.cropRight,
    required this.cropBottom,
    this.freehandClipPath = const [],
  });
}

/// High-resolution, non-destructive image cropper supporting:
/// - **Cắt hình chữ nhật**: Ultra-fine cropping down to 8×8 px (min normalized
///   fraction 0.005) with zoomable preview so tiny lines/equations stay crisp.
/// - **Cắt tùy chỉnh**: Freeform lasso polygon clipping directly over the image.
class ImageCropDialog extends StatefulWidget {
  final ui.Image image;
  final ImageCropMode initialMode;
  final double initialCropLeft;
  final double initialCropTop;
  final double initialCropRight;
  final double initialCropBottom;
  final List<StrokePoint> initialFreehandPath;

  const ImageCropDialog({
    super.key,
    required this.image,
    this.initialMode = ImageCropMode.rectangle,
    this.initialCropLeft = 0.0,
    this.initialCropTop = 0.0,
    this.initialCropRight = 1.0,
    this.initialCropBottom = 1.0,
    this.initialFreehandPath = const [],
  });

  static Future<ImageCropResult?> show(
    BuildContext context, {
    required ui.Image image,
    ImageCropMode initialMode = ImageCropMode.rectangle,
    double initialCropLeft = 0.0,
    double initialCropTop = 0.0,
    double initialCropRight = 1.0,
    double initialCropBottom = 1.0,
    List<StrokePoint> initialFreehandPath = const [],
  }) {
    return showDialog<ImageCropResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ImageCropDialog(
        image: image,
        initialMode: initialMode,
        initialCropLeft: initialCropLeft,
        initialCropTop: initialCropTop,
        initialCropRight: initialCropRight,
        initialCropBottom: initialCropBottom,
        initialFreehandPath: initialFreehandPath,
      ),
    );
  }

  @override
  State<ImageCropDialog> createState() => _ImageCropDialogState();
}

enum _CropDragHandle {
  none,
  move,
  topLeft,
  topCenter,
  topRight,
  middleLeft,
  middleRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
}

class _ImageCropDialogState extends State<ImageCropDialog> {
  static const double _minCropFraction = 0.005;

  late ImageCropMode _mode;
  late double _left;
  late double _top;
  late double _right;
  late double _bottom;
  late List<Offset> _freehandNorm;

  double _previewZoom = 1.0;
  _CropDragHandle _activeHandle = _CropDragHandle.none;
  Offset? _lastDragNorm;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _left = widget.initialCropLeft.clamp(0.0, 0.99);
    _top = widget.initialCropTop.clamp(0.0, 0.99);
    _right = widget.initialCropRight.clamp(_left + _minCropFraction, 1.0);
    _bottom = widget.initialCropBottom.clamp(_top + _minCropFraction, 1.0);
    _freehandNorm = widget.initialFreehandPath
        .map((p) => Offset(p.x.clamp(0.0, 1.0), p.y.clamp(0.0, 1.0)))
        .toList();
  }

  double get _minFracX =>
      math.max(_minCropFraction, 8.0 / math.max(1, widget.image.width));
  double get _minFracY =>
      math.max(_minCropFraction, 8.0 / math.max(1, widget.image.height));

  int get _cropPixelWidth =>
      math.max(1, ((_right - _left) * widget.image.width).round());
  int get _cropPixelHeight =>
      math.max(1, ((_bottom - _top) * widget.image.height).round());

  _CropDragHandle _hitTestHandle(Offset local, Size imgBox) {
    final l = _left * imgBox.width;
    final t = _top * imgBox.height;
    final r = _right * imgBox.width;
    final b = _bottom * imgBox.height;
    final cx = (l + r) * 0.5;
    final cy = (t + b) * 0.5;
    const hitR = 34.0;
    const edgeBand = 24.0;

    bool near(double x, double y) => (local - Offset(x, y)).distance <= hitR;

    if (near(l, t)) return _CropDragHandle.topLeft;
    if (near(r, t)) return _CropDragHandle.topRight;
    if (near(l, b)) return _CropDragHandle.bottomLeft;
    if (near(r, b)) return _CropDragHandle.bottomRight;
    if (near(cx, t)) return _CropDragHandle.topCenter;
    if (near(cx, b)) return _CropDragHandle.bottomCenter;
    if (near(l, cy)) return _CropDragHandle.middleLeft;
    if (near(r, cy)) return _CropDragHandle.middleRight;

    if ((local.dy - t).abs() <= edgeBand &&
        local.dx >= l - hitR &&
        local.dx <= r + hitR) {
      return _CropDragHandle.topCenter;
    }
    if ((local.dy - b).abs() <= edgeBand &&
        local.dx >= l - hitR &&
        local.dx <= r + hitR) {
      return _CropDragHandle.bottomCenter;
    }
    if ((local.dx - l).abs() <= edgeBand &&
        local.dy >= t - hitR &&
        local.dy <= b + hitR) {
      return _CropDragHandle.middleLeft;
    }
    if ((local.dx - r).abs() <= edgeBand &&
        local.dy >= t - hitR &&
        local.dy <= b + hitR) {
      return _CropDragHandle.middleRight;
    }
    if (Rect.fromLTRB(l, t, r, b).contains(local)) {
      return _CropDragHandle.move;
    }
    return _CropDragHandle.none;
  }

  void _handlePanStart(DragStartDetails d, Size imgBox, [double hitPad = 0.0]) {
    final local = d.localPosition - Offset(hitPad, hitPad);
    final norm = Offset(
      (local.dx / imgBox.width).clamp(0.0, 1.0),
      (local.dy / imgBox.height).clamp(0.0, 1.0),
    );
    if (_mode == ImageCropMode.freehand) {
      setState(() => _freehandNorm = [norm]);
    } else {
      _activeHandle = _hitTestHandle(local, imgBox);
      _lastDragNorm = norm;
    }
  }

  void _handlePanUpdate(
      DragUpdateDetails d, Size imgBox, [double hitPad = 0.0]) {
    final local = d.localPosition - Offset(hitPad, hitPad);
    final norm = Offset(
      (local.dx / imgBox.width).clamp(0.0, 1.0),
      (local.dy / imgBox.height).clamp(0.0, 1.0),
    );
    if (_mode == ImageCropMode.freehand) {
      if (_freehandNorm.isEmpty ||
          (_freehandNorm.last - norm).distance > 0.004) {
        setState(() => _freehandNorm = [..._freehandNorm, norm]);
      }
      return;
    }

    if (_activeHandle == _CropDragHandle.none || _lastDragNorm == null) return;
    final dx = norm.dx - _lastDragNorm!.dx;
    final dy = norm.dy - _lastDragNorm!.dy;
    _lastDragNorm = norm;

    setState(() {
      switch (_activeHandle) {
        case _CropDragHandle.move:
          final w = _right - _left;
          final h = _bottom - _top;
          _left = (_left + dx).clamp(0.0, 1.0 - w);
          _top = (_top + dy).clamp(0.0, 1.0 - h);
          _right = _left + w;
          _bottom = _top + h;
          break;
        case _CropDragHandle.topLeft:
          _left = (_left + dx).clamp(0.0, _right - _minFracX);
          _top = (_top + dy).clamp(0.0, _bottom - _minFracY);
          break;
        case _CropDragHandle.topCenter:
          _top = (_top + dy).clamp(0.0, _bottom - _minFracY);
          break;
        case _CropDragHandle.topRight:
          _right = (_right + dx).clamp(_left + _minFracX, 1.0);
          _top = (_top + dy).clamp(0.0, _bottom - _minFracY);
          break;
        case _CropDragHandle.middleLeft:
          _left = (_left + dx).clamp(0.0, _right - _minFracX);
          break;
        case _CropDragHandle.middleRight:
          _right = (_right + dx).clamp(_left + _minFracX, 1.0);
          break;
        case _CropDragHandle.bottomLeft:
          _left = (_left + dx).clamp(0.0, _right - _minFracX);
          _bottom = (_bottom + dy).clamp(_top + _minFracY, 1.0);
          break;
        case _CropDragHandle.bottomCenter:
          _bottom = (_bottom + dy).clamp(_top + _minFracY, 1.0);
          break;
        case _CropDragHandle.bottomRight:
          _right = (_right + dx).clamp(_left + _minFracX, 1.0);
          _bottom = (_bottom + dy).clamp(_top + _minFracY, 1.0);
          break;
        case _CropDragHandle.none:
          break;
      }
    });
  }

  void _handlePanEnd(DragEndDetails d) {
    _activeHandle = _CropDragHandle.none;
    _lastDragNorm = null;
  }

  void _confirmCrop() {
    if (_mode == ImageCropMode.freehand && _freehandNorm.length >= 3) {
      double minX = 1.0, minY = 1.0, maxX = 0.0, maxY = 0.0;
      for (final p in _freehandNorm) {
        if (p.dx < minX) minX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy > maxY) maxY = p.dy;
      }
      final w = math.max(_minFracX, maxX - minX);
      final h = math.max(_minFracY, maxY - minY);
      final clampedLeft = minX.clamp(0.0, 1.0 - w);
      final clampedTop = minY.clamp(0.0, 1.0 - h);
      final clampedRight = (clampedLeft + w).clamp(clampedLeft + _minFracX, 1.0);
      final clampedBottom = (clampedTop + h).clamp(clampedTop + _minFracY, 1.0);

      // Store freehand polygon normalized relative to the cropped bounding box
      final localPoly = _freehandNorm
          .map((p) => StrokePoint(
                x: ((p.dx - clampedLeft) / (clampedRight - clampedLeft))
                    .clamp(0.0, 1.0),
                y: ((p.dy - clampedTop) / (clampedBottom - clampedTop))
                    .clamp(0.0, 1.0),
              ))
          .toList();

      Navigator.of(context).pop(
        ImageCropResult(
          cropLeft: clampedLeft,
          cropTop: clampedTop,
          cropRight: clampedRight,
          cropBottom: clampedBottom,
          freehandClipPath: localPoly,
        ),
      );
      return;
    }

    Navigator.of(context).pop(
      ImageCropResult(
        cropLeft: _left,
        cropTop: _top,
        cropRight: _right,
        cropBottom: _bottom,
        freehandClipPath: const [],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final imgAspect =
        widget.image.width / math.max(1, widget.image.height).toDouble();

    return Dialog(
      backgroundColor: const Color(0xFF16181D),
      insetPadding: const EdgeInsets.all(18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 680),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
              child: Row(
                children: [
                  Icon(
                    _mode == ImageCropMode.rectangle
                        ? Icons.crop_rounded
                        : Icons.gesture_rounded,
                    color: const Color(0xFF3B82F6),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _mode == ImageCropMode.rectangle
                              ? 'Cắt hình chữ nhật (Giữ nguyên độ phân giải gốc)'
                              : 'Cắt tùy chỉnh (Khoanh vùng tự do)',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Vùng chọn: $_cropPixelWidth × $_cropPixelHeight px (Gốc: ${widget.image.width} × ${widget.image.height})',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SegmentedButton<ImageCropMode>(
                    segments: const [
                      ButtonSegment(
                        value: ImageCropMode.rectangle,
                        icon: Icon(Icons.crop_rounded, size: 16),
                        label: Text('Chữ nhật', style: TextStyle(fontSize: 11.5)),
                      ),
                      ButtonSegment(
                        value: ImageCropMode.freehand,
                        icon: Icon(Icons.gesture_rounded, size: 16),
                        label: Text('Tùy chỉnh', style: TextStyle(fontSize: 11.5)),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) => setState(() => _mode = s.first),
                    showSelectedIcon: false,
                  ),
                ],
              ),
            ),

            // Zoomable Crop Preview Canvas
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B0C10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: LayoutBuilder(
                  builder: (ctx, constraints) {
                    const double hitPad = 28.0;
                    final maxW =
                        math.max(40.0, constraints.maxWidth - hitPad * 2);
                    final maxH =
                        math.max(40.0, constraints.maxHeight - hitPad * 2);
                    double boxW = maxW;
                    double boxH = boxW / imgAspect;
                    if (boxH > maxH) {
                      boxH = maxH;
                      boxW = boxH * imgAspect;
                    }
                    final imgBox = Size(boxW * _previewZoom, boxH * _previewZoom);

                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        child: Container(
                          constraints: BoxConstraints(
                            minWidth: constraints.maxWidth,
                            minHeight: constraints.maxHeight,
                          ),
                          alignment: Alignment.center,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanStart: (d) =>
                                _handlePanStart(d, imgBox, hitPad),
                            onPanUpdate: (d) =>
                                _handlePanUpdate(d, imgBox, hitPad),
                            onPanEnd: _handlePanEnd,
                            child: Padding(
                              padding: const EdgeInsets.all(hitPad),
                              child: CustomPaint(
                                size: imgBox,
                                painter: _CropCanvasPainter(
                                  image: widget.image,
                                  mode: _mode,
                                  left: _left,
                                  top: _top,
                                  right: _right,
                                  bottom: _bottom,
                                  freehandNorm: _freehandNorm,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // Bottom Zoom + Action Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Row(
                children: [
                  const Icon(Icons.zoom_in_rounded, size: 17, color: Colors.white60),
                  SizedBox(
                    width: 140,
                    child: Slider(
                      value: _previewZoom,
                      min: 1.0,
                      max: 4.0,
                      divisions: 12,
                      onChanged: (v) => setState(() => _previewZoom = v),
                    ),
                  ),
                  Text(
                    '${(_previewZoom * 100).round()}%',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _left = 0.0;
                        _top = 0.0;
                        _right = 1.0;
                        _bottom = 1.0;
                        _freehandNorm = [];
                      });
                    },
                    child: const Text('Đặt lại'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Hủy'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _confirmCrop,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Áp dụng cắt'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CropCanvasPainter extends CustomPainter {
  final ui.Image image;
  final ImageCropMode mode;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final List<Offset> freehandNorm;

  const _CropCanvasPainter({
    required this.image,
    required this.mode,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.freehandNorm,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fullRect = Offset.zero & size;
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    canvas.drawImageRect(
      image,
      src,
      fullRect,
      Paint()..filterQuality = FilterQuality.high,
    );

    if (mode == ImageCropMode.rectangle) {
      final cropRect = Rect.fromLTRB(
        left * size.width,
        top * size.height,
        right * size.width,
        bottom * size.height,
      );

      // Dim outside crop rect
      final scrim = Path()
        ..addRect(fullRect)
        ..addRect(cropRect)
        ..fillType = PathFillType.evenOdd;
      canvas.drawPath(scrim, Paint()..color = Colors.black.withAlpha(150));

      // Rule of thirds subtle grid
      final gridPaint = Paint()
        ..color = Colors.white.withAlpha(75)
        ..strokeWidth = 0.8;
      final thirdW = cropRect.width / 3;
      final thirdH = cropRect.height / 3;
      for (int i = 1; i <= 2; i++) {
        canvas.drawLine(
          Offset(cropRect.left + thirdW * i, cropRect.top),
          Offset(cropRect.left + thirdW * i, cropRect.bottom),
          gridPaint,
        );
        canvas.drawLine(
          Offset(cropRect.left, cropRect.top + thirdH * i),
          Offset(cropRect.right, cropRect.top + thirdH * i),
          gridPaint,
        );
      }

      // Blue border
      canvas.drawRect(
        cropRect,
        Paint()
          ..color = const Color(0xFF3B82F6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );

      // 8 handles (4 corners + 4 edge midpoints)
      final fill = Paint()..color = Colors.white;
      final stroke = Paint()
        ..color = const Color(0xFF3B82F6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      final pts = [
        cropRect.topLeft,
        cropRect.topCenter,
        cropRect.topRight,
        cropRect.centerLeft,
        cropRect.centerRight,
        cropRect.bottomLeft,
        cropRect.bottomCenter,
        cropRect.bottomRight,
      ];
      for (final p in pts) {
        canvas.drawCircle(p, 6.0, fill);
        canvas.drawCircle(p, 6.0, stroke);
      }
    } else {
      // Freehand polygon overlay
      if (freehandNorm.length >= 2) {
        final poly = Path()
          ..moveTo(
            freehandNorm.first.dx * size.width,
            freehandNorm.first.dy * size.height,
          );
        for (int i = 1; i < freehandNorm.length; i++) {
          poly.lineTo(
            freehandNorm[i].dx * size.width,
            freehandNorm[i].dy * size.height,
          );
        }
        poly.close();

        final scrim = Path()
          ..addRect(fullRect)
          ..addPath(poly, Offset.zero)
          ..fillType = PathFillType.evenOdd;
        canvas.drawPath(scrim, Paint()..color = Colors.black.withAlpha(145));

        canvas.drawPath(
          poly,
          Paint()
            ..color = const Color(0xFF3B82F6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CropCanvasPainter oldDelegate) => true;
}
