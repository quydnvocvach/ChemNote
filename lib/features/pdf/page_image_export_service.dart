import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/models/drawing_elements.dart';
import '../../core/models/note_page.dart';
import '../../core/models/notebook.dart';
import '../../core/services/hardware_service.dart';
import '../canvas/canvas_painter.dart';
import '../canvas/paper_templates.dart';
import 'pdf_export_service.dart';

/// Dịch vụ kết xuất từng trang `NotePage` sang ảnh PNG độ phân giải cao (gồm nền giấy/PDF gốc,
/// hình ảnh, nét viết tay, văn bản, khuôn Hóa học, giấy nhớ, băng che và chữ ký watermark
/// trên mẫu giấy xanh lá).
class PageImageExportService {
  PageImageExportService({Directory? overrideExportDir})
      : _overrideExportDir = overrideExportDir;

  final Directory? _overrideExportDir;

  static const String defaultAndroidPicturesExportPath =
      '/storage/emulated/0/Pictures/ChemNote';
  static const String defaultAndroidDownloadExportPath =
      '/storage/emulated/0/Download/ChemNote';

  static const String kWatermarkText = PdfExportService.kWatermarkText;
  static const String kWatermarkFontFamily = 'WatermarkCormorant';

  static bool _testFontLoaded = false;

  Future<void> _ensureWatermarkFontRegistered() async {
    if (_testFontLoaded) return;
    _testFontLoaded = true;
    try {
      final data = await rootBundle.load(PdfExportService.kWatermarkFontAsset);
      final loader = FontLoader(kWatermarkFontFamily)
        ..addFont(Future<ByteData>.value(data));
      await loader.load();
    } catch (_) {
      try {
        final file = File(PdfExportService.kWatermarkFontAsset);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final loader = FontLoader(kWatermarkFontFamily)
            ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
          await loader.load();
        }
      } catch (_) {}
    }
  }

  /// Kết xuất một [NotePage] sang dữ liệu PNG nhị phân.
  Future<Uint8List> renderPageToPngBytes(
    NotePage page, {
    double scale = 2.0,
  }) async {
    await _ensureWatermarkFontRegistered();

    final bool isWhiteboard = page.isInfiniteWhiteboard;
    final Size pageSize = PaperMetrics.pageSize(
      isLandscape: page.isLandscape,
      isInfiniteWhiteboard: isWhiteboard,
    );

    final _ImageExportViewport viewport = _computeViewport(
      page,
      pageSize: pageSize,
      isWhiteboard: isWhiteboard,
      requestedScale: scale,
    );

    final List<ui.Image> decodedToDispose = <ui.Image>[];
    ui.Picture? picture;
    ui.Image? outputImage;

    try {
      ui.Image? pdfBgImage;
      if (!isWhiteboard &&
          page.pdfBackgroundPath != null &&
          page.pdfBackgroundPath!.isNotEmpty) {
        pdfBgImage = await _decodeFileImage(page.pdfBackgroundPath!);
        if (pdfBgImage != null) {
          decodedToDispose.add(pdfBgImage);
        }
      }

      final Map<String, ui.Image> elementImageCache = <String, ui.Image>{};
      for (final img in page.imageElements) {
        if (img.filePath.isEmpty || elementImageCache.containsKey(img.filePath)) {
          continue;
        }
        final decoded = await _decodeFileImage(img.filePath);
        if (decoded != null) {
          elementImageCache[img.filePath] = decoded;
          decodedToDispose.add(decoded);
        }
      }

      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      canvas.scale(viewport.scale, viewport.scale);
      if (isWhiteboard) {
        canvas.translate(-viewport.originX, -viewport.originY);
      }

      final List<StickyNoteElement> sortedStickies =
          List<StickyNoteElement>.from(page.stickyNotes)
            ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
      final bool hasStickies = sortedStickies.isNotEmpty;
      final int? baseMaxZ = hasStickies ? sortedStickies.first.zIndex : null;

      bool hasCanvasItemInRange(int minExcl, int? maxIncl) {
        bool match(int z) => z > minExcl && (maxIncl == null || z <= maxIncl);
        return page.strokes.any((s) => match(s.zIndex)) ||
            page.imageElements.any((e) => match(e.zIndex)) ||
            page.stencilElements.any((e) => match(e.zIndex));
      }

      // 1. Nền giấy + PDF nền + các phần tử trước sticky note đầu tiên
      CanvasPainter(
        page: page,
        pdfBackgroundImage: pdfBgImage,
        elementImageCache: elementImageCache,
        drawBackground: true,
        drawOverlays: !hasStickies,
        drawTapes: false,
        maxZInclusive: baseMaxZ,
      ).paint(canvas, pageSize);

      // 2. Giấy nhớ (Sticky Notes) xen kẽ đúng thứ tự Z-index với các nét/ảnh phía trên
      for (int si = 0; si < sortedStickies.length; si++) {
        _paintStickyNote(canvas, sortedStickies[si]);
        final int minExcl = sortedStickies[si].zIndex;
        final int? maxIncl = si + 1 < sortedStickies.length
            ? sortedStickies[si + 1].zIndex
            : null;
        if (hasCanvasItemInRange(minExcl, maxIncl) ||
            si == sortedStickies.length - 1) {
          CanvasPainter(
            page: page,
            elementImageCache: elementImageCache,
            drawBackground: false,
            drawOverlays: si == sortedStickies.length - 1,
            drawTapes: false,
            minZExclusive: minExcl,
            maxZInclusive: maxIncl,
          ).paint(canvas, pageSize);
        }
      }

      // 3. Thẻ tệp đính kèm
      for (final att in page.attachmentElements) {
        _paintAttachmentChip(canvas, att);
      }

      // 4. Các khối văn bản (wrap đúng width)
      for (final txt in page.textElements) {
        _paintTextElement(canvas, txt);
      }

      // 5. Băng che học tập chưa lật (Study Tapes)
      for (final tape in page.tapeElements) {
        if (!tape.isRevealed) {
          _paintStudyTape(canvas, tape);
        }
      }

      // 6. Chữ ký watermark trên dải xanh lá của mẫu giấy sageRibbon
      if (!isWhiteboard &&
          pdfBgImage == null &&
          page.templateType == PaperTemplateType.sageRibbon) {
        _paintSageWatermark(canvas, pageSize);
      }

      picture = recorder.endRecording();
      outputImage = await picture.toImage(
        viewport.pixelWidth,
        viewport.pixelHeight,
      );
      final ByteData? byteData = await outputImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) {
        throw const FileSystemException('Không thể mã hóa trang thành PNG.');
      }
      return byteData.buffer.asUint8List();
    } finally {
      outputImage?.dispose();
      picture?.dispose();
      for (final img in decodedToDispose) {
        img.dispose();
      }
    }
  }

  /// Xuất danh sách trang thành các tệp PNG trong bộ nhớ thiết bị và báo MediaScanner quét ngay.
  Future<List<File>> exportPagesToPngFiles({
    required Notebook notebook,
    required List<NotePage> pages,
    String? customDirectory,
    double scale = 2.0,
    PdfExportProgressCallback? onProgress,
  }) async {
    if (pages.isEmpty) {
      throw const FileSystemException('Không có trang nào được chọn để xuất.');
    }

    final Directory targetDir = await _resolveWritableExportDir(
      customDirectory: customDirectory,
    );
    final String safeTitle = _sanitizeTitle(notebook.title);
    final int stamp = DateTime.now().millisecondsSinceEpoch;
    final List<File> savedFiles = <File>[];

    for (int i = 0; i < pages.length; i++) {
      final page = pages[i];
      onProgress?.call(
        i + 1,
        pages.length,
        'Đang xuất ảnh trang ${i + 1}/${pages.length}...',
      );
      await Future<void>.delayed(Duration.zero);

      final Uint8List pngBytes = await renderPageToPngBytes(page, scale: scale);
      final int pageNum = page.index + 1;
      final String fileName = pages.length == 1
          ? '${safeTitle}_Trang_${pageNum}_$stamp.png'
          : '${safeTitle}_Trang_${pageNum}_${i + 1}_$stamp.png';
      final File file = File(
        '${targetDir.path}${Platform.pathSeparator}$fileName',
      );
      await file.writeAsBytes(pngBytes, flush: true);
      await HardwareService.instance.scanMediaFile(
        file.path,
        mimeType: 'image/png',
      );
      savedFiles.add(file);
    }

    return savedFiles;
  }

  /// Kết xuất danh sách trang sang ảnh PNG tạm và mở hộp thoại chia sẻ hệ thống.
  Future<List<File>> sharePagesAsPngs({
    required Notebook notebook,
    required List<NotePage> pages,
    double scale = 2.0,
    PdfExportProgressCallback? onProgress,
  }) async {
    if (pages.isEmpty) {
      throw const FileSystemException('Không có trang nào được chọn để chia sẻ.');
    }

    final Directory tempDir = await getTemporaryDirectory();
    final Directory shareDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}chemnote_share_images',
    );
    if (!await shareDir.exists()) {
      await shareDir.create(recursive: true);
    }

    final String safeTitle = _sanitizeTitle(notebook.title);
    final int stamp = DateTime.now().millisecondsSinceEpoch;
    final List<File> files = <File>[];

    for (int i = 0; i < pages.length; i++) {
      final page = pages[i];
      onProgress?.call(
        i + 1,
        pages.length,
        'Đang tạo ảnh chia sẻ ${i + 1}/${pages.length}...',
      );
      await Future<void>.delayed(Duration.zero);

      final Uint8List pngBytes = await renderPageToPngBytes(page, scale: scale);
      final int pageNum = page.index + 1;
      final File file = File(
        '${shareDir.path}${Platform.pathSeparator}${safeTitle}_Trang_${pageNum}_$stamp.png',
      );
      await file.writeAsBytes(pngBytes, flush: true);
      files.add(file);
    }

    await Share.shareXFiles(
      files.map((f) => XFile(f.path, mimeType: 'image/png')).toList(),
      subject: notebook.title,
      text: 'Trang ghi chú ChemNote: ${notebook.title}',
    );
    return files;
  }

  Future<ui.Image?> _decodeFileImage(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  _ImageExportViewport _computeViewport(
    NotePage page, {
    required Size pageSize,
    required bool isWhiteboard,
    required double requestedScale,
  }) {
    if (!isWhiteboard) {
      final double clampedScale = requestedScale.clamp(1.0, 3.0);
      return _ImageExportViewport(
        originX: 0.0,
        originY: 0.0,
        scale: clampedScale,
        pixelWidth: math.max(1, (pageSize.width * clampedScale).round()),
        pixelHeight: math.max(1, (pageSize.height * clampedScale).round()),
      );
    }

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    void includeRect(double x, double y, double w, double h) {
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x + w > maxX) maxX = x + w;
      if (y + h > maxY) maxY = y + h;
    }

    for (final stroke in page.strokes) {
      if (stroke.toolType == ToolType.laserPointer || stroke.points.isEmpty) {
        continue;
      }
      final pad = math.max(2.0, stroke.width);
      for (final p in stroke.points) {
        includeRect(p.x - pad, p.y - pad, pad * 2, pad * 2);
      }
    }
    for (final s in page.stencilElements) {
      includeRect(s.x, s.y, s.width, s.height + 18);
    }
    for (final t in page.textElements) {
      includeRect(t.x, t.y, t.width, t.height);
    }
    for (final img in page.imageElements) {
      includeRect(img.x, img.y, img.width, img.height);
    }
    for (final att in page.attachmentElements) {
      includeRect(att.x, att.y, att.width, att.height);
    }
    for (final tape in page.tapeElements) {
      if (!tape.isRevealed) {
        includeRect(tape.x, tape.y, tape.width, tape.height);
      }
    }
    for (final note in page.stickyNotes) {
      includeRect(
        note.x,
        note.y,
        note.width,
        note.isCollapsed ? 38.0 : note.height,
      );
    }

    if (!minX.isFinite || !minY.isFinite) {
      minX = 2200.0;
      minY = 2438.0;
      maxX = 3800.0;
      maxY = 3561.0;
    } else {
      const double padding = 72.0;
      minX = math.max(0.0, minX - padding);
      minY = math.max(0.0, minY - padding);
      maxX = math.min(pageSize.width, maxX + padding);
      maxY = math.min(pageSize.height, maxY + padding);
    }

    final double contentW = math.max(400.0, maxX - minX);
    final double contentH = math.max(300.0, maxY - minY);
    final double maxEdge = math.max(contentW, contentH);
    final double cappedScale = math.min(requestedScale, 2400.0 / maxEdge);
    final double effScale = cappedScale.clamp(0.4, 2.0);
    return _ImageExportViewport(
      originX: minX,
      originY: minY,
      scale: effScale,
      pixelWidth: math.max(1, (contentW * effScale).round()),
      pixelHeight: math.max(1, (contentH * effScale).round()),
    );
  }

  void _paintTextElement(Canvas canvas, TextElement el) {
    if (el.text.trim().isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(
        text: el.text,
        style: TextStyle(
          fontSize: el.fontSize,
          color: Color(el.colorValue),
          fontWeight: el.isBold ? FontWeight.w700 : FontWeight.w400,
          fontStyle: el.isItalic ? FontStyle.italic : FontStyle.normal,
          height: 1.32,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: null,
    )..layout(maxWidth: math.max(24.0, el.width));
    tp.paint(canvas, Offset(el.x, el.y));
  }

  void _paintStudyTape(Canvas canvas, TapeElement tape) {
    final Rect rect = Rect.fromLTWH(tape.x, tape.y, tape.width, tape.height);
    final RRect rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));
    final Color baseColor = Color(tape.colorValue);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = baseColor
        ..style = PaintingStyle.fill,
    );
    canvas.save();
    canvas.clipRRect(rrect);
    final Paint stripePaint = Paint()
      ..color = Colors.black.withAlpha(24)
      ..strokeWidth = 2.0;
    const double step = 12.0;
    for (double x = rect.left - rect.height; x < rect.right + rect.height; x += step) {
      canvas.drawLine(
        Offset(x, rect.bottom),
        Offset(x + rect.height, rect.top),
        stripePaint,
      );
    }
    canvas.restore();
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = Colors.black.withAlpha(45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
  }

  void _paintAttachmentChip(Canvas canvas, AttachmentElement att) {
    final Rect card = Rect.fromLTWH(att.x, att.y, att.width, att.height);
    final RRect cardRr =
        RRect.fromRectAndRadius(card, const Radius.circular(12));
    canvas.drawRRect(
      cardRr,
      Paint()
        ..color = const Color(0xFFF8FAFC)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      cardRr,
      Paint()
        ..color = const Color(0xFFCBD5E1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    final String ext =
        att.fileExtension.trim().isEmpty ? 'FILE' : att.fileExtension.trim();
    final Color badgeColor = switch (ext.toUpperCase()) {
      'PDF' => const Color(0xFFDC2626),
      'DOC' || 'DOCX' => const Color(0xFF2563EB),
      'PPT' || 'PPTX' => const Color(0xFFEA580C),
      _ => const Color(0xFF475569),
    };
    final RRect badgeRr = RRect.fromRectAndRadius(
      Rect.fromLTWH(card.left + 10, card.top + 12, 40, card.height - 24),
      const Radius.circular(8),
    );
    canvas.drawRRect(badgeRr, Paint()..color = badgeColor);

    final badgeTp = TextPainter(
      text: TextSpan(
        text: ext.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 38);
    badgeTp.paint(
      canvas,
      Offset(
        badgeRr.left + (badgeRr.width - badgeTp.width) * 0.5,
        badgeRr.top + (badgeRr.height - badgeTp.height) * 0.5,
      ),
    );

    final nameTp = TextPainter(
      text: TextSpan(
        text: att.fileName,
        style: const TextStyle(
          color: Color(0xFF0F172A),
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '...',
    )..layout(maxWidth: math.max(32.0, card.width - 68));
    nameTp.paint(
      canvas,
      Offset(card.left + 58, card.top + (card.height - nameTp.height) * 0.5),
    );
  }

  void _paintStickyNote(Canvas canvas, StickyNoteElement note) {
    final Color bgColor = Color(note.colorValue);
    final Color headerColor =
        Color.lerp(bgColor, Colors.black, 0.08) ?? bgColor;
    final Color borderColor =
        Color.lerp(bgColor, Colors.black, 0.22) ?? const Color(0xFFD4C04A);

    if (note.isCollapsed) {
      final Rect pill = Rect.fromLTWH(note.x, note.y, note.width, 36.0);
      final RRect pillRr =
          RRect.fromRectAndRadius(pill, const Radius.circular(18));
      canvas.drawRRect(pillRr, Paint()..color = bgColor);
      canvas.drawRRect(
        pillRr,
        Paint()
          ..color = borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
      final String label =
          note.text.trim().isEmpty ? 'Ghi chú dán' : note.text.trim();
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Color(0xFF1F2937),
            fontSize: 12.0,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      )..layout(maxWidth: math.max(24.0, note.width - 28));
      tp.paint(
        canvas,
        Offset(pill.left + 14, pill.top + (pill.height - tp.height) * 0.5),
      );
      return;
    }

    final Rect card = Rect.fromLTWH(note.x, note.y, note.width, note.height);
    final RRect cardRr =
        RRect.fromRectAndRadius(card, const Radius.circular(10));
    if (!note.isTransparent) {
      canvas.drawRRect(cardRr, Paint()..color = bgColor);
    }
    canvas.save();
    canvas.clipRRect(cardRr);

    const double headerH = 28.0;
    final Rect headerRect =
        Rect.fromLTWH(card.left, card.top, card.width, headerH);
    canvas.drawRect(
      headerRect,
      Paint()
        ..color = note.isTransparent
            ? headerColor.withAlpha(110)
            : headerColor,
    );
    final headerTp = TextPainter(
      text: const TextSpan(
        text: 'Ghi chú',
        style: TextStyle(
          color: Color(0xFF1F2937),
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: math.max(20.0, card.width - 20));
    headerTp.paint(
      canvas,
      Offset(card.left + 10, card.top + (headerH - headerTp.height) * 0.5),
    );

    final Rect bodyRect = Rect.fromLTWH(
      card.left,
      card.top + headerH,
      card.width,
      math.max(1.0, card.height - headerH),
    );
    if (note.text.trim().isNotEmpty) {
      final bodyTp = TextPainter(
        text: TextSpan(
          text: note.text,
          style: const TextStyle(
            color: Color(0xFF1F2937),
            fontSize: 13.0,
            height: 1.32,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: null,
      )..layout(maxWidth: math.max(20.0, bodyRect.width - 16));
      bodyTp.paint(canvas, Offset(bodyRect.left + 8, bodyRect.top + 8));
    }

    if (note.strokes.isNotEmpty) {
      canvas.save();
      canvas.clipRect(bodyRect);
      canvas.translate(bodyRect.left, bodyRect.top);
      final NotePage stickyStrokePage = NotePage(
        id: 'sticky_${note.id}',
        index: 0,
        strokes: note.strokes,
        updatedAt: note.updatedAt,
      );
      CanvasPainter(
        page: stickyStrokePage,
        drawBackground: false,
        drawOverlays: false,
        drawTapes: false,
      ).paint(canvas, bodyRect.size);
      canvas.restore();
    }

    canvas.restore();
    canvas.drawRRect(
      cardRr,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  void _paintSageWatermark(Canvas canvas, Size pageSize) {
    final double footerH = pageSize.height * (100.0 / 2263.0);
    final double rightPad = pageSize.width * (48.0 / 1600.0);
    final double fontSize = pageSize.height * (38.0 / 2263.0);
    final tp = TextPainter(
      text: TextSpan(
        text: kWatermarkText,
        style: TextStyle(
          fontFamily: kWatermarkFontFamily,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          fontStyle: FontStyle.italic,
          color: const Color(0xFF141815),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final double dx = pageSize.width - rightPad - tp.width;
    final double dy = (pageSize.height - footerH) + (footerH - tp.height) * 0.5;
    tp.paint(canvas, Offset(dx, dy));
  }

  Future<Directory> _resolveWritableExportDir({
    String? customDirectory,
  }) async {
    final dirs = <Directory>[];
    if (_overrideExportDir != null) {
      dirs.add(_overrideExportDir!);
    } else {
      if (customDirectory != null && customDirectory.trim().isNotEmpty) {
        dirs.add(Directory(customDirectory.trim()));
      }
      if (Platform.isAndroid) {
        dirs.add(Directory(defaultAndroidPicturesExportPath));
        dirs.add(Directory(defaultAndroidDownloadExportPath));
        try {
          final ext = await getExternalStorageDirectory();
          if (ext != null) {
            dirs.add(
              Directory(
                '${ext.path}${Platform.pathSeparator}Pictures'
                '${Platform.pathSeparator}ChemNote',
              ),
            );
          }
        } catch (_) {}
      }
      try {
        final docs = await getApplicationDocumentsDirectory();
        dirs.add(
          Directory('${docs.path}${Platform.pathSeparator}ChemNote_Images'),
        );
      } catch (_) {}
    }

    Object? lastErr;
    for (final dir in dirs) {
      try {
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        final probe = File(
          '${dir.path}${Platform.pathSeparator}.chemnote_probe_${DateTime.now().microsecondsSinceEpoch}',
        );
        await probe.writeAsString('ok');
        await probe.delete();
        return dir;
      } catch (e) {
        lastErr = e;
      }
    }
    throw FileSystemException(
      'Không tìm thấy thư mục có quyền ghi để lưu ảnh PNG: $lastErr',
    );
  }

  String _sanitizeTitle(String raw) {
    final cleaned = raw
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9\u00C0-\u1EF9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return cleaned.isEmpty ? 'ChemNote' : cleaned;
  }
}

class _ImageExportViewport {
  const _ImageExportViewport({
    required this.originX,
    required this.originY,
    required this.scale,
    required this.pixelWidth,
    required this.pixelHeight,
  });

  final double originX;
  final double originY;
  final double scale;
  final int pixelWidth;
  final int pixelHeight;
}
