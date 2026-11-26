import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/models/drawing_elements.dart';
import '../../core/models/note_page.dart';
import '../../core/models/notebook.dart';

/// Callback báo tiến độ xuất PDF từng bước để hiển thị thanh tiến trình mượt mà.
typedef PdfExportProgressCallback = void Function(
  int currentStep,
  int totalSteps,
  String stage,
);

/// Dịch vụ xuất sổ tay `Notebook` sang tệp PDF nhiều trang (gồm giấy nền/PDF gốc,
/// nét viết tay, văn bản, hình ảnh và các khuôn vẽ Hóa học), đồng thời hỗ trợ in & chia sẻ.
class PdfExportService {
  PdfExportService({Directory? overrideExportDir})
      : _overrideExportDir = overrideExportDir;

  final Directory? _overrideExportDir;

  /// Kích thước logic tham chiếu của khung vẽ canvas (tỷ lệ chuẩn A4).
  static const double defaultCanvasWidth = 794.0;
  static const double defaultCanvasHeight = 1123.0;

  static const String kWatermarkText = 'Đinh Ngọc Quý';
  static const String kWatermarkFontAsset =
      'assets/fonts/CormorantGaramond-SemiBoldItalic.ttf';
  static pw.Font? _cachedWatermarkFont;

  Future<pw.Font?> _loadWatermarkFont() async {
    if (_cachedWatermarkFont != null) return _cachedWatermarkFont;
    try {
      final data = await rootBundle.load(kWatermarkFontAsset);
      _cachedWatermarkFont = pw.Font.ttf(data);
      return _cachedWatermarkFont;
    } catch (_) {
      try {
        final file = File(kWatermarkFontAsset);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          _cachedWatermarkFont = pw.Font.ttf(ByteData.sublistView(bytes));
          return _cachedWatermarkFont;
        }
      } catch (_) {}
      return null;
    }
  }

  /// Tạo dữ liệu nhị phân PDF nhiều trang từ một `Notebook`.
  Future<Uint8List> buildNotebookPdfBytes(
    Notebook notebook, {
    double canvasWidth = defaultCanvasWidth,
    double canvasHeight = defaultCanvasHeight,
    PdfExportProgressCallback? onProgress,
  }) async {
    final doc = pw.Document(
      title: notebook.title,
      author: 'ChemNote',
      creator: 'ChemNote Flutter',
    );

    final pages = notebook.pages.isEmpty
        ? <NotePage>[
            NotePage(
              id: 'empty',
              index: 0,
              templateType: notebook.defaultTemplate,
              paperColor: notebook.defaultPaperColor,
              isLandscape: notebook.defaultOrientationLandscape,
              updatedAt: notebook.updatedAt,
            ),
          ]
        : notebook.pages;

    final totalPages = pages.length;
    final bool needsWatermark = pages.any(
      (p) =>
          !(p.isInfiniteWhiteboard || notebook.isWhiteboard) &&
          (p.pdfBackgroundPath == null || p.pdfBackgroundPath!.isEmpty) &&
          p.templateType == PaperTemplateType.sageRibbon,
    );
    final pw.Font? watermarkFont =
        needsWatermark ? await _loadWatermarkFont() : null;

    // Bộ nhớ đệm ảnh đã giải mã theo đường dẫn tệp để tránh đọc lại đĩa nhiều lần.
    final imageCache = <String, pw.MemoryImage>{};

    Future<pw.MemoryImage?> loadCachedImage(String path) async {
      if (path.isEmpty) return null;
      final cached = imageCache[path];
      if (cached != null) return cached;
      final file = File(path);
      if (!await file.exists()) return null;
      try {
        final mem = pw.MemoryImage(await file.readAsBytes());
        imageCache[path] = mem;
        return mem;
      } catch (_) {
        return null;
      }
    }

    for (var i = 0; i < totalPages; i++) {
      final page = pages[i];
      onProgress?.call(
        i + 1,
        totalPages,
        'Đang dựng trang ${i + 1}/$totalPages...',
      );
      await Future<void>.delayed(Duration.zero);

      final isWhiteboard = page.isInfiniteWhiteboard || notebook.isWhiteboard;
      final viewport = _computePageViewport(
        page,
        isWhiteboard: isWhiteboard,
        canvasWidth: canvasWidth,
        canvasHeight: canvasHeight,
      );
      final pageFormat = viewport.pageFormat;
      final originX = viewport.originX;
      final originY = viewport.originY;
      final scaleX = viewport.scaleX;
      final scaleY = viewport.scaleY;

      // Tải trước ảnh nền PDF (nếu có, dùng cache chống trùng lặp)
      pw.MemoryImage? pdfBgImage;
      if (page.pdfBackgroundPath != null &&
          page.pdfBackgroundPath!.isNotEmpty) {
        pdfBgImage = await loadCachedImage(page.pdfBackgroundPath!);
      }

      // Tải trước các ảnh đính kèm trên trang (dùng cache chống trùng lặp)
      final loadedImages = <String, pw.MemoryImage>{};
      for (final img in page.imageElements) {
        final mem = await loadCachedImage(img.filePath);
        if (mem != null) {
          loadedImages[img.id] = mem;
        }
      }

      doc.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: pw.EdgeInsets.zero,
          build: (pw.Context ctx) {
            final bgColor = _paperPdfColor(page.paperColor);
            final lineColor = _templateLineColor(page.paperColor);

            return pw.Container(
              width: pageFormat.width,
              height: pageFormat.height,
              color: bgColor,
              child: pw.Stack(
                children: [
                  // 1. Ảnh nền PDF gốc hoặc mẫu giấy Hóa học
                  if (pdfBgImage != null)
                    pw.Positioned.fill(
                      child: pw.Image(pdfBgImage, fit: pw.BoxFit.contain),
                    )
                  else
                    pw.Positioned.fill(
                      child: pw.CustomPaint(
                        size: PdfPoint(pageFormat.width, pageFormat.height),
                        painter: (PdfGraphics canvas, PdfPoint size) {
                          _paintPaperTemplate(
                            canvas,
                            size,
                            page.templateType,
                            lineColor,
                            page.paperColor == PaperColorType.dark,
                          );
                        },
                      ),
                    ),

                  // 2. Các hình ảnh được chèn vào trang (hỗ trợ cắt không phá hủy cropLeft/Top/Right/Bottom)
                  for (final img in page.imageElements)
                    if (loadedImages.containsKey(img.id))
                      _buildCroppedPdfImage(
                        img,
                        loadedImages[img.id]!,
                        scaleX,
                        scaleY,
                        originX: originX,
                        originY: originY,
                      ),

                  // 2b. Các thẻ tệp tin đính kèm (PDF, DOC, PPT, tệp khác)
                  for (final att in page.attachmentElements)
                    _buildAttachmentChip(
                      att,
                      scaleX,
                      scaleY,
                      originX: originX,
                      originY: originY,
                    ),

                  // 3. Các khuôn vẽ Hóa học (stencils) + nhãn vector
                  if (page.stencilElements.isNotEmpty)
                    pw.Positioned.fill(
                      child: pw.CustomPaint(
                        size: PdfPoint(pageFormat.width, pageFormat.height),
                        painter: (PdfGraphics canvas, PdfPoint size) {
                          for (final stencil in page.stencilElements) {
                            _paintStencilVector(
                              canvas,
                              size,
                              stencil,
                              scaleX,
                              scaleY,
                              originX: originX,
                              originY: originY,
                            );
                          }
                        },
                      ),
                    ),
                  for (final stencil in page.stencilElements)
                    pw.Positioned(
                      left: (stencil.x - originX) * scaleX,
                      top: (stencil.y - originY + stencil.height) * scaleY + 2,
                      child: pw.Container(
                        width: stencil.width * scaleX,
                        alignment: pw.Alignment.center,
                        child: pw.Text(
                          _stencilDisplayLabel(stencil.stencilId),
                          style: pw.TextStyle(
                            fontSize: 8,
                            color: _pdfColorFromArgb(stencil.colorValue),
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                  // 4. Các nét vẽ tay & hình học
                  if (page.strokes.isNotEmpty)
                    pw.Positioned.fill(
                      child: pw.CustomPaint(
                        size: PdfPoint(pageFormat.width, pageFormat.height),
                        painter: (PdfGraphics canvas, PdfPoint size) {
                          for (final stroke in page.strokes) {
                            _paintStroke(
                              canvas,
                              size,
                              stroke,
                              scaleX,
                              scaleY,
                              originX: originX,
                              originY: originY,
                            );
                          }
                        },
                      ),
                    ),

                  // 5. Các khối văn bản
                  for (final textEl in page.textElements)
                    pw.Positioned(
                      left: (textEl.x - originX) * scaleX,
                      top: (textEl.y - originY) * scaleY,
                      child: pw.SizedBox(
                        width: textEl.width * scaleX,
                        child: pw.Text(
                          textEl.text,
                          style: pw.TextStyle(
                            fontSize: math.max(8, textEl.fontSize * scaleX),
                            color: _pdfColorFromArgb(textEl.colorValue),
                            fontWeight: textEl.isBold
                                ? pw.FontWeight.bold
                                : pw.FontWeight.normal,
                            fontStyle: textEl.isItalic
                                ? pw.FontStyle.italic
                                : pw.FontStyle.normal,
                          ),
                        ),
                      ),
                    ),

                  // 6. Băng che học tập (Study Tape — chỉ vẽ các băng chưa mở lật)
                  if (page.tapeElements.any((t) => !t.isRevealed))
                    pw.Positioned.fill(
                      child: pw.CustomPaint(
                        size: PdfPoint(pageFormat.width, pageFormat.height),
                        painter: (PdfGraphics canvas, PdfPoint size) {
                          for (final tape in page.tapeElements) {
                            if (tape.isRevealed) continue;
                            _paintStudyTape(
                              canvas,
                              size,
                              tape,
                              scaleX,
                              scaleY,
                              originX: originX,
                              originY: originY,
                            );
                          }
                        },
                      ),
                    ),

                  // 7. Giấy nhớ dán (Sticky Notes — sắp xếp theo zIndex, thẻ pastel hoặc viên thuốc thu gọn)
                  for (final note in (List<StickyNoteElement>.from(
                    page.stickyNotes,
                  )..sort((a, b) => a.zIndex.compareTo(b.zIndex))))
                    _buildStickyNoteCard(
                      note,
                      scaleX,
                      scaleY,
                      originX: originX,
                      originY: originY,
                    ),

                  // 8. Chữ ký watermark trên góc dưới phải dải xanh lá của mẫu giấy sageRibbon
                  if (!isWhiteboard &&
                      pdfBgImage == null &&
                      page.templateType == PaperTemplateType.sageRibbon &&
                      watermarkFont != null)
                    pw.Positioned(
                      right: pageFormat.width * (48.0 / 1600.0),
                      bottom: 0,
                      child: pw.Container(
                        height: pageFormat.height * (100.0 / 2263.0),
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text(
                          kWatermarkText,
                          style: pw.TextStyle(
                            font: watermarkFont,
                            fontSize: pageFormat.height * (38.0 / 2263.0),
                            color: PdfColor.fromInt(0xFF141815),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      );
    }

    onProgress?.call(
      totalPages,
      totalPages,
      'Đang nén và đóng gói tệp PDF...',
    );
    await Future<void>.delayed(Duration.zero);

    return doc.save();
  }

  /// Đường dẫn xuất PDF mặc định trên Android / HarmonyOS.
  static const String defaultAndroidExportPath =
      '/storage/emulated/0/Documents/ChemNote';

  /// Xuất sổ tay thành tệp PDF và lưu vào thư mục người dùng chọn (hoặc Documents/ChemNote).
  Future<File> exportNotebookToFile(
    Notebook notebook, {
    String? customFileName,
    String? customDirectory,
    PdfExportProgressCallback? onProgress,
  }) async {
    final totalPages = notebook.pages.isEmpty ? 1 : notebook.pages.length;
    final bytes = await buildNotebookPdfBytes(
      notebook,
      onProgress: onProgress,
    );

    onProgress?.call(
      totalPages,
      totalPages,
      'Đang lưu tệp vào bộ nhớ...',
    );
    await Future<void>.delayed(Duration.zero);

    final rawName = (customFileName ?? notebook.title).trim();
    final safeName = rawName
        .replaceAll(RegExp(r'[^a-zA-Z0-9_\-\s]'), '')
        .replaceAll(RegExp(r'\s+'), '_');
    final fileName =
        '${safeName.isEmpty ? 'ChemNote' : safeName}_${DateTime.now().millisecondsSinceEpoch}.pdf';

    final candidates = await _candidateExportDirectories(
      customDirectory: customDirectory,
    );

    Object? lastError;
    for (final dir in candidates) {
      try {
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        final file = File('${dir.path}${Platform.pathSeparator}$fileName');
        await file.writeAsBytes(bytes, flush: true);
        return file;
      } catch (e) {
        lastError = e;
      }
    }

    throw FileSystemException(
      'Không thể lưu tệp PDF vào bất kỳ thư mục nào: $lastError',
    );
  }

  /// Xuất PDF và mở hộp thoại chia sẻ của hệ thống (Android & HarmonyOS).
  Future<File> shareNotebookPdf(
    Notebook notebook, {
    String? customDirectory,
    PdfExportProgressCallback? onProgress,
  }) async {
    final file = await exportNotebookToFile(
      notebook,
      customDirectory: customDirectory,
      onProgress: onProgress,
    );
    await Share.shareXFiles(
      <XFile>[XFile(file.path)],
      subject: '${notebook.title}.pdf',
      text: 'Sổ tay ChemNote: ${notebook.title}',
    );
    return file;
  }

  /// Mở trình xem trước & in PDF của hệ thống bằng `printing`.
  Future<void> printNotebookPdf(Notebook notebook) async {
    await Printing.layoutPdf(
      name: '${notebook.title}.pdf',
      onLayout: (PdfPageFormat _) => buildNotebookPdfBytes(notebook),
    );
  }

  Future<List<Directory>> _candidateExportDirectories({
    String? customDirectory,
  }) async {
    final dirs = <Directory>[];

    if (_overrideExportDir != null) {
      dirs.add(_overrideExportDir!);
      return dirs;
    }

    if (customDirectory != null && customDirectory.trim().isNotEmpty) {
      dirs.add(Directory(customDirectory.trim()));
    }

    if (Platform.isAndroid) {
      dirs.add(Directory(defaultAndroidExportPath));
      try {
        final ext = await getExternalStorageDirectory();
        if (ext != null) {
          dirs.add(
            Directory(
              '${ext.path}${Platform.pathSeparator}Documents'
              '${Platform.pathSeparator}ChemNote',
            ),
          );
        }
      } catch (_) {}
    }

    try {
      final docs = await getApplicationDocumentsDirectory();
      dirs.add(
        Directory('${docs.path}${Platform.pathSeparator}ChemNote'),
      );
    } catch (_) {}

    return dirs;
  }

  PdfColor _paperPdfColor(PaperColorType color) {
    return switch (color) {
      PaperColorType.white => PdfColors.white,
      PaperColorType.cream => PdfColor.fromInt(0xFFFAF6EC),
      PaperColorType.dark => PdfColor.fromInt(0xFF1E1E24),
    };
  }

  PdfColor _templateLineColor(PaperColorType color) {
    return switch (color) {
      PaperColorType.white => PdfColor.fromInt(0xFFD6DDE6),
      PaperColorType.cream => PdfColor.fromInt(0xFFD9CFB8),
      PaperColorType.dark => PdfColor.fromInt(0xFF3A3A46),
    };
  }

  PdfColor _pdfColorFromArgb(int argb) {
    final r = ((argb >> 16) & 0xFF) / 255.0;
    final g = ((argb >> 8) & 0xFF) / 255.0;
    final b = (argb & 0xFF) / 255.0;
    return PdfColor(r, g, b);
  }

  double _alphaFromArgb(int argb) => ((argb >> 24) & 0xFF) / 255.0;

  void _paintPaperTemplate(
    PdfGraphics canvas,
    PdfPoint size,
    PaperTemplateType template,
    PdfColor lineColor,
    bool isDark,
  ) {
    if (template == PaperTemplateType.blank) return;

    canvas.saveContext();
    canvas.setStrokeColor(lineColor);
    canvas.setLineWidth(0.6);

    switch (template) {
      case PaperTemplateType.blank:
        break;
      case PaperTemplateType.ruled:
        const spacing = 22.0;
        for (double y = size.y - 54; y >= 32; y -= spacing) {
          canvas.moveTo(28, y);
          canvas.lineTo(size.x - 28, y);
        }
        canvas.strokePath();
        // Lề đỏ bên trái
        canvas.setStrokeColor(
          isDark ? PdfColor.fromInt(0xFF7F3B3B) : PdfColor.fromInt(0xFFE5A1A1),
        );
        canvas.moveTo(64, 20);
        canvas.lineTo(64, size.y - 20);
        canvas.strokePath();
        break;

      case PaperTemplateType.grid:
        const step = 20.0;
        for (double x = 20; x < size.x - 10; x += step) {
          canvas.moveTo(x, 20);
          canvas.lineTo(x, size.y - 20);
        }
        for (double y = 20; y < size.y - 10; y += step) {
          canvas.moveTo(20, y);
          canvas.lineTo(size.x - 20, y);
        }
        canvas.strokePath();
        break;

      case PaperTemplateType.dotted:
        canvas.setFillColor(lineColor);
        const step = 20.0;
        for (double x = 24; x < size.x - 16; x += step) {
          for (double y = 24; y < size.y - 16; y += step) {
            canvas.drawEllipse(x, y, 0.9, 0.9);
          }
        }
        canvas.fillPath();
        break;

      case PaperTemplateType.cornell:
        const topHeaderY = 82.0;
        const bottomSummaryY = 110.0;
        final cueX = size.x * 0.28;
        // Các dòng ghi chú chính
        for (double y = size.y - topHeaderY - 22; y >= bottomSummaryY + 12; y -= 22) {
          canvas.moveTo(cueX + 8, y);
          canvas.lineTo(size.x - 24, y);
        }
        canvas.strokePath();
        // Khung chia vùng Cornell
        canvas.setLineWidth(1.1);
        canvas.moveTo(24, size.y - topHeaderY);
        canvas.lineTo(size.x - 24, size.y - topHeaderY);
        canvas.moveTo(24, bottomSummaryY);
        canvas.lineTo(size.x - 24, bottomSummaryY);
        canvas.moveTo(cueX, bottomSummaryY);
        canvas.lineTo(cueX, size.y - topHeaderY);
        canvas.strokePath();
        break;

      case PaperTemplateType.hexagonal:
        const r = 14.0;
        final dx = r * math.sqrt(3);
        final dy = r * 1.5;
        var row = 0;
        for (double cy = 28; cy < size.y - 20; cy += dy) {
          final xOffset = (row.isOdd ? dx / 2 : 0.0) + 28;
          for (double cx = xOffset; cx < size.x - 20; cx += dx) {
            for (var i = 0; i < 6; i++) {
              final angle = (math.pi / 3) * i - math.pi / 6;
              final vx = cx + r * math.cos(angle);
              final vy = cy + r * math.sin(angle);
              if (i == 0) {
                canvas.moveTo(vx, vy);
              } else {
                canvas.lineTo(vx, vy);
              }
            }
            canvas.closePath();
          }
          row++;
        }
        canvas.strokePath();
        break;

      case PaperTemplateType.sageRibbon:
        final bool isLandscapePage = size.x > size.y;
        final double headerH = size.y * (163.0 / 2263.0);
        final double topDividerH = size.y * (6.2 / 2263.0);
        final double footerH = size.y * (100.0 / 2263.0);
        final double bottomDividerH = size.y * (4.7 / 2263.0);

        final sageBand = isDark
            ? PdfColor.fromInt(0xFF334034)
            : PdfColor.fromInt(0xFFB4C3AC);
        final sageDivider = isDark
            ? PdfColor.fromInt(0xFF566B58)
            : PdfColor.fromInt(0xFF798D6E);
        final peachRibbon = isDark
            ? PdfColor.fromInt(0xFFC89B82)
            : PdfColor.fromInt(0xFFFFD8BE);
        final ruledColor = isDark
            ? PdfColor.fromInt(0xFF303532)
            : PdfColor.fromInt(0xFFD2D9CF);

        // Dải tiêu đề & chân trang xanh xô thơm theo đúng tỉ lệ mẫu chuẩn
        canvas.setFillColor(sageBand);
        canvas.drawRect(0, size.y - headerH, size.x, headerH);
        canvas.drawRect(0, 0, size.x, footerH);
        canvas.fillPath();

        // Hai đường phân cách ngang đậm ở header & footer
        canvas.setFillColor(sageDivider);
        canvas.drawRect(0, size.y - headerH - topDividerH, size.x, topDividerH);
        canvas.drawRect(0, footerH, size.x, bottomDividerH);
        canvas.fillPath();

        // Các dòng kẻ ngang tràn lề 2 bên (26 dòng cho khổ dọc)
        canvas.setStrokeColor(ruledColor);
        canvas.setLineWidth(size.y * (2.4 / 2263.0));
        if (!isLandscapePage) {
          for (int i = 0; i < 26; i++) {
            final double yFromTop = size.y * ((242.5 + i * 75.04) / 2263.0);
            final double pdfY = size.y - yFromTop;
            canvas.moveTo(0, pdfY);
            canvas.lineTo(size.x, pdfY);
          }
        } else {
          final double spacing = size.x * (75.04 / 2263.0);
          final double startY = size.y - (headerH + topDividerH + spacing);
          final double minY = footerH + bottomDividerH + spacing * 0.45;
          for (double y = startY; y >= minY; y -= spacing) {
            canvas.moveTo(0, y);
            canvas.lineTo(size.x, y);
          }
        }
        canvas.strokePath();

        // Dải ruy-băng đào đuôi én ở góc trên bên trái (tô đặc, không viền)
        final double ribLeft = size.x * (99.4 / 1600.0);
        final double ribRight = size.x * (204.3 / 1600.0);
        final double ribMidX = (ribLeft + ribRight) * 0.5;
        final double ribBottomFromTop = isLandscapePage
            ? (headerH + topDividerH + size.y * 0.045)
            : (size.y * (236.0 / 2263.0));
        final double ribNotchFromTop = isLandscapePage
            ? (headerH + topDividerH + size.y * 0.010)
            : (size.y * (181.0 / 2263.0));
        final double ribTop = size.y;
        final double ribBottom = size.y - ribBottomFromTop;
        final double ribNotch = size.y - ribNotchFromTop;
        canvas.setFillColor(peachRibbon);
        canvas.moveTo(ribLeft, ribTop);
        canvas.lineTo(ribRight, ribTop);
        canvas.lineTo(ribRight, ribBottom);
        canvas.lineTo(ribMidX, ribNotch);
        canvas.lineTo(ribLeft, ribBottom);
        canvas.closePath();
        canvas.fillPath();
        break;

      case PaperTemplateType.pastelGrid:
        const headerH = 44.0;
        final bannerColor = isDark
            ? PdfColor.fromInt(0xFF282E3F)
            : PdfColor.fromInt(0xFFE6ECF8);
        final bannerBorder = isDark
            ? PdfColor.fromInt(0xFF47526B)
            : PdfColor.fromInt(0xFFC5D0E6);

        // Dải tiêu đề pastel xanh-oải hương
        canvas.setFillColor(bannerColor);
        canvas.drawRect(0, size.y - headerH, size.x, headerH);
        canvas.fillPath();

        canvas.setStrokeColor(bannerBorder);
        canvas.setLineWidth(0.9);
        canvas.moveTo(0, size.y - headerH);
        canvas.lineTo(size.x, size.y - headerH);
        // Hai gạch chân gọn cho Ngày / Chủ đề
        canvas.moveTo(24, size.y - 30);
        canvas.lineTo(size.x * 0.56, size.y - 30);
        canvas.moveTo(size.x * 0.64, size.y - 30);
        canvas.lineTo(size.x - 24, size.y - 30);
        canvas.strokePath();

        // Lưới ô ly 5mm mảnh
        canvas.setStrokeColor(lineColor);
        canvas.setLineWidth(0.45);
        const step = 14.2;
        for (double x = 18; x < size.x - 14; x += step) {
          canvas.moveTo(x, 18);
          canvas.lineTo(x, size.y - headerH);
        }
        for (double y = size.y - headerH - step; y >= 18; y -= step) {
          canvas.moveTo(18, y);
          canvas.lineTo(size.x - 18, y);
        }
        canvas.strokePath();
        break;

      case PaperTemplateType.vintageCream:
        final frameColor = isDark
            ? PdfColor.fromInt(0xFF5D5346)
            : PdfColor.fromInt(0xFFC9B79C);
        final sepiaLine = isDark
            ? PdfColor.fromInt(0xFF3E3830)
            : PdfColor.fromInt(0xFFDCCBB1);

        // Khung viền kép cổ điển
        canvas.setStrokeColor(frameColor);
        canvas.setLineWidth(1.0);
        canvas.drawRect(18, 18, size.x - 36, size.y - 36);
        canvas.strokePath();
        canvas.setLineWidth(0.5);
        canvas.drawRect(22, 22, size.x - 44, size.y - 44);
        canvas.strokePath();

        // Đường phân cách vùng tiêu đề (Title / Date / No.)
        final headerY = size.y - 66;
        canvas.setLineWidth(0.8);
        canvas.moveTo(22, headerY);
        canvas.lineTo(size.x - 22, headerY);
        canvas.strokePath();

        // Dòng kẻ ngang màu nâu ấm
        canvas.setStrokeColor(sepiaLine);
        canvas.setLineWidth(0.55);
        for (double y = headerY - 22; y >= 34; y -= 22) {
          canvas.moveTo(30, y);
          canvas.lineTo(size.x - 30, y);
        }
        canvas.strokePath();
        break;

      case PaperTemplateType.twoColumnStudy:
        final headerY = size.y - 48;
        final midX = size.x / 2;

        // Đường kẻ tiêu đề phía trên
        canvas.setStrokeColor(lineColor);
        canvas.setLineWidth(1.0);
        canvas.moveTo(24, headerY);
        canvas.lineTo(size.x - 24, headerY);
        canvas.strokePath();

        // Dòng kẻ ngang cho cả 2 cột
        canvas.setLineWidth(0.55);
        for (double y = headerY - 22; y >= 28; y -= 22) {
          canvas.moveTo(24, y);
          canvas.lineTo(size.x - 24, y);
        }
        canvas.strokePath();

        // Đường nét đứt chia đôi giữa trang (Tóm tắt / Lời giải)
        canvas.setLineWidth(0.9);
        for (double y = 28; y < headerY - 4; y += 9) {
          final topSeg = math.min(y + 4.5, headerY - 4);
          canvas.moveTo(midX, y);
          canvas.lineTo(midX, topSeg);
        }
        canvas.strokePath();
        break;
    }

    canvas.restoreContext();
  }

  void _paintStroke(
    PdfGraphics canvas,
    PdfPoint size,
    Stroke stroke,
    double scaleX,
    double scaleY, {
    double originX = 0.0,
    double originY = 0.0,
  }) {
    if (stroke.points.isEmpty) return;
    if (stroke.toolType == ToolType.laserPointer) return;

    final baseAlpha = _alphaFromArgb(stroke.colorValue);
    final (opacity, widthMultiplier) = switch (stroke.toolType) {
      ToolType.highlighter => (0.35, 1.8),
      ToolType.pencil => ((baseAlpha * 0.72).clamp(0.15, 0.85), 0.9),
      ToolType.studyTape => (0.94, 2.2),
      ToolType.brushPen => (baseAlpha, 1.15),
      ToolType.fountainPen || ToolType.ballpointPen => (baseAlpha, 1.0),
      ToolType.laserPointer => (0.0, 1.0),
    };

    // Chỉ dùng saveContext/setGraphicState khi nét có độ trong suốt < 1.0
    // để tránh tạo thừa đối tượng ExtGState trong PDF cho từng nét viết tay.
    final needsAlphaState = opacity < 0.999;
    if (needsAlphaState) {
      canvas.saveContext();
      canvas.setGraphicState(
        PdfGraphicState(strokeOpacity: opacity, fillOpacity: opacity),
      );
    }

    final color = _pdfColorFromArgb(stroke.colorValue);
    final scaledWidth = math.max(
      0.8,
      stroke.width * scaleX * widthMultiplier,
    );

    double mapX(double x) => (x - originX) * scaleX;
    double mapY(double y) => size.y - ((y - originY) * scaleY);

    final pts = _thinPointsForPdf(
      stroke.points,
      isShape: stroke.shapeType != ShapeType.none,
    );

    if (pts.length == 1) {
      final p = pts.first;
      final r = scaledWidth / 2;
      canvas.setFillColor(color);
      canvas.drawEllipse(mapX(p.x), mapY(p.y), r, r);
      canvas.fillPath();
      if (needsAlphaState) {
        canvas.restoreContext();
      }
      return;
    }

    canvas.setStrokeColor(color);
    canvas.setLineCap(PdfLineCap.round);
    canvas.setLineJoin(PdfLineJoin.round);
    canvas.setLineWidth(scaledWidth);

    final first = pts.first;
    canvas.moveTo(mapX(first.x), mapY(first.y));
    for (var i = 1; i < pts.length; i++) {
      final pt = pts[i];
      canvas.lineTo(mapX(pt.x), mapY(pt.y));
    }
    canvas.strokePath();

    if (needsAlphaState) {
      canvas.restoreContext();
    }
  }

  /// Giảm mật độ điểm thừa cho nét viết tay 240Hz trước khi dựng PDF
  /// (loại bỏ các điểm cách nhau < 1.8 logical px, luôn giữ điểm đầu, điểm cuối và góc nhọn).
  List<StrokePoint> _thinPointsForPdf(
    List<StrokePoint> points, {
    bool isShape = false,
  }) {
    if (points.length <= 2) return points;
    final minDistSq = isShape ? 0.25 : 3.24; // 1.8 * 1.8 = 3.24
    final result = <StrokePoint>[points.first];
    var lastKept = points.first;

    for (var i = 1; i < points.length - 1; i++) {
      final curr = points[i];
      final dx = curr.x - lastKept.x;
      final dy = curr.y - lastKept.y;
      final distSq = dx * dx + dy * dy;

      if (distSq >= minDistSq) {
        result.add(curr);
        lastKept = curr;
        continue;
      }

      // Luôn giữ lại điểm góc nhọn để nét chữ không bị tù
      if (!isShape && distSq > 0.25) {
        final next = points[i + 1];
        final ndx = next.x - curr.x;
        final ndy = next.y - curr.y;
        final nextDistSq = ndx * ndx + ndy * ndy;
        if (nextDistSq > 0.25) {
          final cosAngle =
              (dx * ndx + dy * ndy) / math.sqrt(distSq * nextDistSq);
          if (cosAngle < 0.72) {
            result.add(curr);
            lastKept = curr;
          }
        }
      }
    }

    result.add(points.last);
    return result;
  }

  void _paintStudyTape(
    PdfGraphics canvas,
    PdfPoint size,
    TapeElement tape,
    double scaleX,
    double scaleY, {
    double originX = 0.0,
    double originY = 0.0,
  }) {
    final left = (tape.x - originX) * scaleX;
    final w = math.max(8.0, tape.width * scaleX);
    final h = math.max(8.0, tape.height * scaleY);
    final bottom = size.y - ((tape.y - originY + tape.height) * scaleY);

    canvas.saveContext();
    canvas.setGraphicState(
      const PdfGraphicState(fillOpacity: 0.95, strokeOpacity: 0.95),
    );
    canvas.setFillColor(_pdfColorFromArgb(tape.colorValue));
    canvas.drawRRect(left, bottom, w, h, 4, 4);
    canvas.fillPath();

    // Đường viền mảnh để phân biệt rõ băng che học tập khi in
    canvas.setGraphicState(const PdfGraphicState(strokeOpacity: 0.35));
    canvas.setStrokeColor(PdfColors.white);
    canvas.setLineWidth(0.7);
    canvas.drawRRect(left + 1.5, bottom + 1.5, w - 3, h - 3, 3, 3);
    canvas.strokePath();
    canvas.restoreContext();
  }

  void _paintStencilVector(
    PdfGraphics canvas,
    PdfPoint size,
    StencilElement stencil,
    double scaleX,
    double scaleY, {
    double originX = 0.0,
    double originY = 0.0,
  }) {
    canvas.saveContext();
    canvas.setStrokeColor(_pdfColorFromArgb(stencil.colorValue));
    canvas.setLineWidth(math.max(1.0, stencil.strokeWidth * scaleX));
    canvas.setLineCap(PdfLineCap.round);
    canvas.setLineJoin(PdfLineJoin.round);

    final left = (stencil.x - originX) * scaleX;
    final w = stencil.width * scaleX;
    final h = stencil.height * scaleY;
    final bottom = size.y - ((stencil.y - originY + stencil.height) * scaleY);
    final cx = left + w / 2;
    final cy = bottom + h / 2;
    final id = stencil.stencilId.toLowerCase();

    if (id.contains('benzene') || id.contains('cyclohexane') || id.contains('hex')) {
      final r = math.min(w, h) * 0.42;
      for (var i = 0; i < 6; i++) {
        final angle = (math.pi / 3) * i - math.pi / 2;
        final vx = cx + r * math.cos(angle);
        final vy = cy + r * math.sin(angle);
        if (i == 0) {
          canvas.moveTo(vx, vy);
        } else {
          canvas.lineTo(vx, vy);
        }
      }
      canvas.closePath();
      canvas.strokePath();
      if (id.contains('benzene')) {
        canvas.drawEllipse(cx, cy, r * 0.58, r * 0.58);
        canvas.strokePath();
      }
    } else if (id.contains('cyclopentane') || id.contains('pent')) {
      final r = math.min(w, h) * 0.42;
      for (var i = 0; i < 5; i++) {
        final angle = (2 * math.pi / 5) * i + math.pi / 2;
        final vx = cx + r * math.cos(angle);
        final vy = cy + r * math.sin(angle);
        if (i == 0) {
          canvas.moveTo(vx, vy);
        } else {
          canvas.lineTo(vx, vy);
        }
      }
      canvas.closePath();
      canvas.strokePath();
    } else if (id.contains('arrow') || id.contains('equilibrium')) {
      canvas.moveTo(left + w * 0.1, cy);
      canvas.lineTo(left + w * 0.9, cy);
      canvas.moveTo(left + w * 0.75, cy + h * 0.15);
      canvas.lineTo(left + w * 0.9, cy);
      canvas.lineTo(left + w * 0.75, cy - h * 0.15);
      canvas.strokePath();
    } else {
      // Khung dấu chuẩn vector cho dụng cụ phòng thí nghiệm / khuôn hóa học khác
      canvas.drawRRect(left + 4, bottom + 4, w - 8, h - 8, 6, 6);
      canvas.strokePath();
    }

    canvas.restoreContext();
  }

  pw.Widget _buildCroppedPdfImage(
    ImageElement img,
    pw.MemoryImage memImage,
    double scaleX,
    double scaleY, {
    double originX = 0.0,
    double originY = 0.0,
  }) {
    final displayW = math.max(4.0, img.width * scaleX);
    final displayH = math.max(4.0, img.height * scaleY);
    final cLeft = img.cropLeft.clamp(0.0, 0.995);
    final cTop = img.cropTop.clamp(0.0, 0.995);
    final cRight = img.cropRight.clamp(cLeft + 0.005, 1.0);
    final cBottom = img.cropBottom.clamp(cTop + 0.005, 1.0);
    final isCropped =
        cLeft > 0.001 || cTop > 0.001 || cRight < 0.999 || cBottom < 0.999;

    final pw.Widget imageChild;
    if (!isCropped) {
      imageChild = pw.Image(
        memImage,
        width: displayW,
        height: displayH,
        fit: pw.BoxFit.contain,
      );
    } else {
      final cropW = cRight - cLeft;
      final cropH = cBottom - cTop;
      final fullW = displayW / cropW;
      final fullH = displayH / cropH;
      imageChild = pw.ClipRect(
        child: pw.SizedBox(
          width: displayW,
          height: displayH,
          child: pw.Stack(
            children: [
              pw.Positioned(
                left: -cLeft * fullW,
                top: -cTop * fullH,
                child: pw.Image(
                  memImage,
                  width: fullW,
                  height: fullH,
                  fit: pw.BoxFit.fill,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return pw.Positioned(
      left: (img.x - originX) * scaleX,
      top: (img.y - originY) * scaleY,
      child: pw.Transform.rotate(
        angle: -img.rotation,
        child: imageChild,
      ),
    );
  }

  pw.Widget _buildAttachmentChip(
    AttachmentElement att,
    double scaleX,
    double scaleY, {
    double originX = 0.0,
    double originY = 0.0,
  }) {
    final w = math.max(90.0, att.width * scaleX);
    final h = math.max(30.0, att.height * scaleY);
    final ext = att.fileExtension.replaceFirst('.', '').toUpperCase();
    final badgeLabel = ext.isEmpty ? 'FILE' : ext;
    final badgeColor = _attachmentBadgeColor(badgeLabel);

    return pw.Positioned(
      left: (att.x - originX) * scaleX,
      top: (att.y - originY) * scaleY,
      child: pw.Container(
        width: w,
        height: h,
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: pw.BoxDecoration(
          color: PdfColor.fromInt(0xFFF3F4F6),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          border: pw.Border.all(
            color: PdfColor.fromInt(0xFFD1D5DB),
            width: 0.8,
          ),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              decoration: pw.BoxDecoration(
                color: badgeColor,
                borderRadius:
                    const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Text(
                badgeLabel.length > 4 ? badgeLabel.substring(0, 4) : badgeLabel,
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 7,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(width: 6),
            pw.Expanded(
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    att.fileName,
                    maxLines: 1,
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromInt(0xFF111827),
                    ),
                  ),
                  pw.SizedBox(height: 1),
                  pw.Text(
                    _formatFileSize(att.fileSizeBytes),
                    style: pw.TextStyle(
                      fontSize: 6.5,
                      color: PdfColor.fromInt(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  PdfColor _attachmentBadgeColor(String ext) {
    return switch (ext) {
      'PDF' => PdfColor.fromInt(0xFFDC2626),
      'DOC' || 'DOCX' => PdfColor.fromInt(0xFF2563EB),
      'PPT' || 'PPTX' => PdfColor.fromInt(0xFFEA580C),
      'XLS' || 'XLSX' => PdfColor.fromInt(0xFF16A34A),
      _ => PdfColor.fromInt(0xFF4B5563),
    };
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return 'Tệp đính kèm';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  _PageViewport _computePageViewport(
    NotePage page, {
    required bool isWhiteboard,
    required double canvasWidth,
    required double canvasHeight,
  }) {
    if (!isWhiteboard) {
      final pageFormat =
          page.isLandscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;
      final logicalWidth = page.isLandscape ? canvasHeight : canvasWidth;
      final logicalHeight = page.isLandscape ? canvasWidth : canvasHeight;
      return _PageViewport(
        originX: 0.0,
        originY: 0.0,
        scaleX: pageFormat.width / logicalWidth,
        scaleY: pageFormat.height / logicalHeight,
        pageFormat: pageFormat,
      );
    }

    final pageFormat = PdfPageFormat.a4.landscape;
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;

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
      includeRect(s.x, s.y, s.width, s.height + 16);
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

    // Nếu bảng vô cực đang trống -> dùng vùng trung tâm 1200x900 quanh (3000, 3000)
    if (!minX.isFinite || !minY.isFinite) {
      minX = 2400.0;
      minY = 2550.0;
      maxX = 3600.0;
      maxY = 3450.0;
    } else {
      const padding = 48.0;
      minX -= padding;
      minY -= padding;
      maxX += padding;
      maxY += padding;
    }

    final contentW = math.max(400.0, maxX - minX);
    final contentH = math.max(300.0, maxY - minY);
    const pdfMargin = 24.0;
    final availW = pageFormat.width - pdfMargin * 2;
    final availH = pageFormat.height - pdfMargin * 2;
    final scale = math.min(availW / contentW, availH / contentH);

    final renderedW = contentW * scale;
    final renderedH = contentH * scale;
    final offsetX = (pageFormat.width - renderedW) / 2;
    final offsetY = (pageFormat.height - renderedH) / 2;

    return _PageViewport(
      originX: minX - (offsetX / scale),
      originY: minY - (offsetY / scale),
      scaleX: scale,
      scaleY: scale,
      pageFormat: pageFormat,
    );
  }

  pw.Widget _buildStickyNoteCard(
    StickyNoteElement note,
    double scaleX,
    double scaleY, {
    double originX = 0.0,
    double originY = 0.0,
  }) {
    final baseColor = _pdfColorFromArgb(note.colorValue);
    final headerColor = _darkenPdfColor(baseColor, 0.07);
    final borderColor = _darkenPdfColor(baseColor, 0.16);
    final inkColor = PdfColor.fromInt(0xFF1E293B);
    final left = (note.x - originX) * scaleX;
    final top = (note.y - originY) * scaleY;

    if (note.isCollapsed) {
      final firstLine = note.text
          .trim()
          .split('\n')
          .firstWhere((l) => l.trim().isNotEmpty, orElse: () => 'Ghi chú');
      final pillW = math.max(96.0, note.width * scaleX);
      return pw.Positioned(
        left: left,
        top: top,
        child: pw.Opacity(
          opacity: note.isTransparent ? 0.45 : 1.0,
          child: pw.Container(
            width: pillW,
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: pw.BoxDecoration(
              color: baseColor,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              border: pw.Border.all(color: borderColor, width: 0.8),
            ),
            child: pw.Text(
              firstLine,
              maxLines: 1,
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: inkColor,
              ),
            ),
          ),
        ),
      );
    }

    final cardW = math.max(90.0, note.width * scaleX);
    final cardH = math.max(68.0, note.height * scaleY);
    final headerH = math.min(18.0, math.max(12.0, cardH * 0.16));
    final bodyW = cardW;
    final bodyH = math.max(20.0, cardH - headerH);
    final localScaleX = bodyW / math.max(1.0, note.width);
    final localScaleY = bodyH / math.max(1.0, note.height - 32.0);
    final bodyFontSize = (9.5 * scaleX).clamp(7.0, 11.0);

    return pw.Positioned(
      left: left,
      top: top,
      child: pw.Opacity(
        opacity: note.isTransparent ? 0.42 : 1.0,
        child: pw.Container(
          width: cardW,
          height: cardH,
          decoration: pw.BoxDecoration(
            color: baseColor,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            border: pw.Border.all(color: borderColor, width: 0.8),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Container(
                height: headerH,
                padding: const pw.EdgeInsets.symmetric(horizontal: 6),
                alignment: pw.Alignment.centerLeft,
                decoration: pw.BoxDecoration(
                  color: headerColor,
                  borderRadius: const pw.BorderRadius.only(
                    topLeft: pw.Radius.circular(5.5),
                    topRight: pw.Radius.circular(5.5),
                  ),
                ),
                child: pw.Text(
                  'Ghi chú',
                  style: pw.TextStyle(
                    fontSize: 6.5,
                    fontWeight: pw.FontWeight.bold,
                    color: inkColor,
                  ),
                ),
              ),
              pw.Expanded(
                child: pw.ClipRect(
                  child: pw.Stack(
                    children: [
                      if (note.text.trim().isNotEmpty)
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                            note.text,
                            style: pw.TextStyle(
                              fontSize: bodyFontSize,
                              color: inkColor,
                              lineSpacing: 1.8,
                            ),
                          ),
                        ),
                      if (note.strokes.isNotEmpty)
                        pw.Positioned.fill(
                          child: pw.CustomPaint(
                            size: PdfPoint(bodyW, bodyH),
                            painter: (PdfGraphics canvas, PdfPoint size) {
                              for (final stroke in note.strokes) {
                                _paintStroke(
                                  canvas,
                                  size,
                                  stroke,
                                  localScaleX,
                                  localScaleY,
                                );
                              }
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  PdfColor _darkenPdfColor(PdfColor color, double amount) {
    return PdfColor(
      (color.red - amount).clamp(0.0, 1.0),
      (color.green - amount).clamp(0.0, 1.0),
      (color.blue - amount).clamp(0.0, 1.0),
    );
  }

  String _stencilDisplayLabel(String stencilId) {
    final cleaned = stencilId.replaceAll('_', ' ').trim();
    if (cleaned.isEmpty) return 'Stencil';
    return cleaned[0].toUpperCase() + cleaned.substring(1);
  }
}

class _PageViewport {
  const _PageViewport({
    required this.originX,
    required this.originY,
    required this.scaleX,
    required this.scaleY,
    required this.pageFormat,
  });

  final double originX;
  final double originY;
  final double scaleX;
  final double scaleY;
  final PdfPageFormat pageFormat;
}
