import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/drawing_elements.dart';
import '../../core/models/note_page.dart';
import '../../core/services/hardware_service.dart';

/// Callback báo tiến độ nhập PDF / DOCX để hiển thị thanh tiến trình mượt mà.
typedef PdfImportProgressCallback = void Function(
  int currentPage,
  int? totalPages,
  String stage,
);

/// Kết quả sau khi nhập tệp PDF hoặc Word (`.docx`) thành danh sách các trang `NotePage`.
class PdfImportResult {
  const PdfImportResult({
    required this.sourceFileName,
    required this.suggestedTitle,
    required this.pages,
    this.isFallbackAttachment = false,
  });

  final String sourceFileName;
  final String suggestedTitle;
  final List<NotePage> pages;
  final bool isFallbackAttachment;
}

/// Ngoại lệ trong quá trình chọn hoặc chuyển đổi PDF / DOCX.
class PdfImportException implements Exception {
  const PdfImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Dịch vụ nhập tài liệu PDF (giáo trình, slide bài giảng Hóa học) và tệp Word (`.docx`)
/// thành các trang ghi chú `NotePage` để viết tay chú thích trực tiếp bằng M-Pencil 3.
class PdfImportService {
  PdfImportService({
    Uuid? uuid,
    Directory? overrideBaseDir,
  })  : _uuid = uuid ?? const Uuid(),
        _overrideBaseDir = overrideBaseDir;

  /// Độ phân giải mặc định 150 DPI cho fallback `Printing.raster` trên Web/Desktop: cân bằng độ nét và RAM.
  static const double defaultPdfDpi = 150.0;

  /// Cạnh dài mục tiêu (px) khi kết xuất PDF bằng Android `PdfRenderer` gốc (2K sắc nét, tốc độ cao, không OOM).
  static const int nativeTargetLongEdgePx = 2048;

  /// Đường dẫn chuẩn cho ảnh thu nhỏ (thumbnail) đi kèm trang PDF đã kết xuất.
  /// Giữ lượt raster 1 lần duy nhất; editor giải mã thumbnail `targetWidth: 320` trực tiếp từ PNG gốc (< 3ms).
  static String thumbnailPathForPdfPage(String pageImagePath) =>
      '$pageImagePath.thumb.png';

  /// Ước lượng nhanh số trang từ header/cấu trúc tệp PDF để hiển thị `%` tiến trình ngay từ trang đầu tiên.
  /// Bỏ qua tệp > 25 MB để tránh giải mã chuỗi khổng lồ trên heap Dart.
  static int? estimatePdfPageCount(Uint8List pdfBytes) {
    if (pdfBytes.isEmpty || pdfBytes.length > 25 * 1024 * 1024) return null;
    final text = latin1.decode(pdfBytes, allowInvalid: true);
    final directCount =
        RegExp(r'/Type\s*/Page(?![a-zA-Z0-9])').allMatches(text).length;
    var maxCount = 0;
    for (final m in RegExp(r'/Count\s+(\d+)').allMatches(text)) {
      final val = int.tryParse(m.group(1) ?? '') ?? 0;
      if (val > maxCount) maxCount = val;
    }
    if (directCount > 0) {
      return maxCount > directCount ? maxCount : directCount;
    }
    return maxCount > 0 ? maxCount : null;
  }

  final Uuid _uuid;
  final Directory? _overrideBaseDir;

  Future<Directory> _resolvePdfTargetDir(String importBatchId) async {
    final baseDir =
        _overrideBaseDir ?? await getApplicationDocumentsDirectory();
    final targetDir = Directory(
      '${baseDir.path}${Platform.pathSeparator}chemnote'
      '${Platform.pathSeparator}pdf_pages${Platform.pathSeparator}$importBatchId',
    );
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    return targetDir;
  }

  /// Mở trình chọn tệp của hệ thống để chọn PDF và chuyển đổi từng trang thành `NotePage`.
  /// Ưu tiên truyền trực tiếp đường dẫn đĩa xuống luồng native (`importPdfFile`) để tránh nạp toàn bộ PDF vào RAM.
  /// Trả về `null` nếu người dùng hủy chọn tệp.
  Future<PdfImportResult?> pickAndImportPdf({
    int startIndex = 0,
    double dpi = defaultPdfDpi,
    void Function(int currentPage)? onPageRendered,
    PdfImportProgressCallback? onProgress,
  }) async {
    final nativePick = await HardwareService.instance.pickDocumentFile(
      allowedExtensions: const <String>['pdf'],
    );
    Uint8List? bytes;
    String? pickedPath;
    String pickedName = 'tai_lieu.pdf';

    if (nativePick.handled) {
      final f = nativePick.file;
      if (f == null) return null;
      pickedPath = f.path;
      pickedName = f.name;
    } else {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['pdf'],
        withData: kIsWeb,
      );

      if (result == null || result.files.isEmpty) {
        return null;
      }

      final picked = result.files.first;
      bytes = picked.bytes;
      pickedPath = picked.path;
      pickedName = picked.name;
    }

    if (pickedPath != null && pickedPath.isNotEmpty) {
      return importPdfFile(
        File(pickedPath),
        fileNameOverride: pickedName,
        startIndex: startIndex,
        dpi: dpi,
        onPageRendered: onPageRendered,
        onProgress: onProgress,
      );
    }

    if (bytes == null || bytes.isEmpty) {
      throw const PdfImportException('Không thể đọc dữ liệu từ tệp PDF đã chọn.');
    }

    return importPdfBytes(
      bytes,
      fileName: pickedName,
      startIndex: startIndex,
      dpi: dpi,
      onPageRendered: onPageRendered,
      onProgress: onProgress,
    );
  }

  /// Nhập trực tiếp từ một `File` PDF có sẵn trên thiết bị.
  /// Trên Android dùng `PdfRenderer` gốc kết xuất từng trang trực tiếp ra đĩa (không OOM).
  Future<PdfImportResult> importPdfFile(
    File pdfFile, {
    String? fileNameOverride,
    int startIndex = 0,
    double dpi = defaultPdfDpi,
    void Function(int currentPage)? onPageRendered,
    PdfImportProgressCallback? onProgress,
  }) async {
    if (!await pdfFile.exists()) {
      throw PdfImportException('Không tìm thấy tệp PDF: ${pdfFile.path}');
    }
    final fileName =
        (fileNameOverride != null && fileNameOverride.trim().isNotEmpty)
            ? fileNameOverride.trim()
            : (pdfFile.uri.pathSegments.isNotEmpty
                ? pdfFile.uri.pathSegments.last
                : 'tai_lieu.pdf');

    onProgress?.call(0, null, 'Đang mở tệp PDF...');
    await Future<void>.delayed(Duration.zero);

    if (!kIsWeb) {
      final importBatchId = _uuid.v4();
      final targetDir = await _resolvePdfTargetDir(importBatchId);
      StreamSubscription<({int currentPage, int? totalPages, String stage})>?
          progressSub;
      if (onProgress != null) {
        progressSub =
            HardwareService.instance.onPdfImportProgress.listen((event) {
          onProgress(
            event.currentPage,
            event.totalPages,
            event.stage.isNotEmpty
                ? event.stage
                : 'Đang nhập trang PDF ${event.currentPage}...',
          );
        });
      }
      try {
        final nativePages = await HardwareService.instance.renderPdfToPngs(
          pdfPath: pdfFile.path,
          outputDir: targetDir.path,
          batchId: importBatchId,
          maxLongEdge: nativeTargetLongEdgePx,
        );
        if (nativePages != null) {
          if (nativePages.isEmpty) {
            throw const PdfImportException(
              'Tệp PDF không chứa trang nào hợp lệ.',
            );
          }
          final pages = <NotePage>[];
          final now = DateTime.now();
          for (final rendered in nativePages) {
            pages.add(
              NotePage(
                id: _uuid.v4(),
                index: startIndex + rendered.pageNumber - 1,
                templateType: PaperTemplateType.blank,
                paperColor: PaperColorType.white,
                isLandscape: rendered.isLandscape,
                // Khóa slide PDF ở lớp nền bất biến (không bao giờ đưa vào imageElements)
                pdfBackgroundPath: rendered.path,
                pdfPageNumber: rendered.pageNumber,
                title: 'Trang ${rendered.pageNumber}',
                updatedAt: now,
              ),
            );
            onPageRendered?.call(rendered.pageNumber);
          }
          onProgress?.call(
            pages.length,
            pages.length,
            'Hoàn tất nhập ${pages.length} trang PDF',
          );
          return PdfImportResult(
            sourceFileName: fileName,
            suggestedTitle: _stripExtension(fileName),
            pages: pages,
          );
        }
        if (await targetDir.exists()) {
          await targetDir.delete(recursive: true);
        }
      } on PlatformException catch (e) {
        if (await targetDir.exists()) {
          try {
            await targetDir.delete(recursive: true);
          } catch (_) {}
        }
        if (e.code == 'PDF_PROTECTED') {
          throw const PdfImportException(
            'Tệp PDF được bảo vệ bằng mật khẩu nên không thể nhập.',
          );
        }
        final fileSize = await pdfFile.length();
        if (fileSize > 25 * 1024 * 1024) {
          throw PdfImportException(
            e.message ?? 'Không thể giải mã tệp PDF dung lượng lớn.',
          );
        }
        // Fallback sang Printing.raster với tệp nhỏ nếu cần.
      } finally {
        await progressSub?.cancel();
      }
    }

    final bytes = await pdfFile.readAsBytes();
    return importPdfBytes(
      bytes,
      fileName: fileName,
      startIndex: startIndex,
      dpi: dpi,
      onPageRendered: onPageRendered,
      onProgress: onProgress,
    );
  }

  /// Kết xuất từng trang PDF thành ảnh PNG khóa cố định ở `NotePage.pdfBackgroundPath`.
  Future<PdfImportResult> importPdfBytes(
    Uint8List pdfBytes, {
    required String fileName,
    int startIndex = 0,
    double dpi = defaultPdfDpi,
    void Function(int currentPage)? onPageRendered,
    PdfImportProgressCallback? onProgress,
  }) async {
    final estimatedTotal = estimatePdfPageCount(pdfBytes);
    onProgress?.call(0, estimatedTotal, 'Đang chuẩn bị giải mã tệp PDF...');
    await Future<void>.delayed(Duration.zero);

    final importBatchId = _uuid.v4();
    final targetDir = await _resolvePdfTargetDir(importBatchId);

    final pages = <NotePage>[];
    final writeFutures = <Future<void>>[];
    var pageNumber = 0;

    try {
      await for (final raster in Printing.raster(pdfBytes, dpi: dpi)) {
        pageNumber++;
        final totalHint = estimatedTotal != null
            ? (pageNumber > estimatedTotal ? pageNumber : estimatedTotal)
            : null;
        onProgress?.call(
          pageNumber,
          totalHint,
          totalHint != null
              ? 'Đang xử lý trang PDF $pageNumber/$totalHint...'
              : 'Đang xử lý trang PDF $pageNumber...',
        );

        final pngBytes = await raster.toPng();
        final filePath =
            '${targetDir.path}${Platform.pathSeparator}${importBatchId}_page_$pageNumber.png';
        writeFutures.add(File(filePath).writeAsBytes(pngBytes, flush: true));
        if (writeFutures.length >= 4) {
          await Future.wait(writeFutures);
          writeFutures.clear();
        }

        final isLandscape = raster.width > raster.height;
        pages.add(
          NotePage(
            id: _uuid.v4(),
            index: startIndex + pageNumber - 1,
            templateType: PaperTemplateType.blank,
            paperColor: PaperColorType.white,
            isLandscape: isLandscape,
            // Khóa slide PDF ở lớp nền bất biến (không bao giờ đưa vào imageElements)
            pdfBackgroundPath: filePath,
            pdfPageNumber: pageNumber,
            title: 'Trang $pageNumber',
            updatedAt: DateTime.now(),
          ),
        );

        onPageRendered?.call(pageNumber);
        await Future<void>.delayed(Duration.zero);
      }

      if (writeFutures.isNotEmpty) {
        onProgress?.call(
          pageNumber,
          pageNumber,
          'Đang hoàn tất lưu $pageNumber trang PDF...',
        );
        await Future.wait(writeFutures);
        writeFutures.clear();
      }
      onProgress?.call(
        pageNumber,
        pageNumber,
        'Hoàn tất nhập $pageNumber trang PDF',
      );
    } catch (e) {
      throw PdfImportException('Không thể giải mã các trang PDF: $e');
    }

    if (pages.isEmpty) {
      throw const PdfImportException('Tệp PDF không chứa trang nào hợp lệ.');
    }

    final suggestedTitle = _stripExtension(fileName);
    return PdfImportResult(
      sourceFileName: fileName,
      suggestedTitle: suggestedTitle,
      pages: pages,
    );
  }

  /// Mở trình chọn tệp cho `.docx` (hoặc `.doc`/`.ppt`/`.pptx`).
  /// - Với `.docx`: giải nén thuần Dart và phân trang nội dung Word + ảnh nhúng thành `NotePage` để viết chú thích trực tiếp.
  /// - Với `.doc`/`.ppt`/`.pptx`: tự động chuyển sang thẻ đính kèm an toàn kèm hướng dẫn.
  Future<PdfImportResult?> pickAndImportDocx({
    int startIndex = 0,
    PdfImportProgressCallback? onProgress,
  }) async {
    final nativePick = await HardwareService.instance.pickDocumentFile(
      allowedExtensions: const <String>['docx', 'doc', 'ppt', 'pptx'],
    );
    Uint8List? bytes;
    String? pickedPath;
    String pickedName = 'tai_lieu.docx';
    int pickedSize = 0;

    if (nativePick.handled) {
      final f = nativePick.file;
      if (f == null) return null;
      pickedPath = f.path;
      pickedName = f.name;
      pickedSize = f.size;
    } else {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['docx', 'doc', 'ppt', 'pptx'],
        withData: kIsWeb,
      );

      if (result == null || result.files.isEmpty) {
        return null;
      }

      final picked = result.files.first;
      bytes = picked.bytes;
      pickedPath = picked.path;
      pickedName = picked.name;
      pickedSize = picked.size;
    }

    final ext = _extensionOf(pickedName);
    if (ext != 'docx') {
      return _buildFallbackAttachmentResult(
        fileName: pickedName,
        sourcePath: pickedPath ?? '',
        fileSizeBytes: pickedSize,
        extension: ext,
        startIndex: startIndex,
      );
    }

    if (bytes == null && pickedPath != null) {
      bytes = await File(pickedPath).readAsBytes();
    }
    if (bytes == null || bytes.isEmpty) {
      throw const PdfImportException(
        'Không thể đọc dữ liệu từ tệp Word (.docx) đã chọn.',
      );
    }

    return importDocxBytes(
      bytes,
      fileName: pickedName,
      startIndex: startIndex,
      onProgress: onProgress,
    );
  }

  /// Nhập trực tiếp một tệp `.docx` có sẵn trên thiết bị (hoặc fallback thẻ đính kèm cho `.doc`/`.ppt`/`.pptx`).
  Future<PdfImportResult> importDocxFile(
    File file, {
    int startIndex = 0,
    PdfImportProgressCallback? onProgress,
  }) async {
    if (!await file.exists()) {
      throw PdfImportException('Không tìm thấy tệp tài liệu: ${file.path}');
    }
    final fileName = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last
        : 'tai_lieu.docx';
    final ext = _extensionOf(fileName);
    if (ext != 'docx') {
      final stat = await file.stat();
      return _buildFallbackAttachmentResult(
        fileName: fileName,
        sourcePath: file.path,
        fileSizeBytes: stat.size,
        extension: ext,
        startIndex: startIndex,
      );
    }

    final bytes = await file.readAsBytes();
    return importDocxBytes(
      bytes,
      fileName: fileName,
      startIndex: startIndex,
      onProgress: onProgress,
    );
  }

  /// Phân tích tệp `.docx` thuần Dart (`word/document.xml` + `word/media/*`) và chia trang A4.
  Future<PdfImportResult> importDocxBytes(
    Uint8List docxBytes, {
    required String fileName,
    int startIndex = 0,
    PdfImportProgressCallback? onProgress,
  }) async {
    onProgress?.call(0, null, 'Đang giải nén tệp Word (.docx)...');
    await Future<void>.delayed(Duration.zero);

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(docxBytes);
    } catch (e) {
      throw PdfImportException('Tệp .docx không hợp lệ hoặc bị hỏng: $e');
    }

    ArchiveFile? documentXmlFile;
    final mediaFiles = <ArchiveFile>[];
    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      final lower = entry.name.toLowerCase();
      if (lower == 'word/document.xml') {
        documentXmlFile = entry;
      } else if (lower.startsWith('word/media/') &&
          (lower.endsWith('.png') ||
              lower.endsWith('.jpg') ||
              lower.endsWith('.jpeg') ||
              lower.endsWith('.webp'))) {
        mediaFiles.add(entry);
      }
    }

    if (documentXmlFile == null) {
      throw const PdfImportException(
        'Không tìm thấy nội dung word/document.xml trong tệp .docx.',
      );
    }

    onProgress?.call(0, null, 'Đang trích xuất văn bản & hình ảnh...');
    await Future<void>.delayed(Duration.zero);

    final xmlBytes = documentXmlFile.content as List<int>;
    final xmlContent = utf8.decode(xmlBytes, allowMalformed: true);
    final paragraphs = _extractDocxParagraphs(xmlContent);

    // Lưu các hình ảnh nhúng từ word/media/ (nếu có) vào thư mục ứng dụng
    final savedMediaPaths = <String>[];
    if (mediaFiles.isNotEmpty) {
      final baseDir =
          _overrideBaseDir ?? await getApplicationDocumentsDirectory();
      final batchId = _uuid.v4();
      final mediaDir = Directory(
        '${baseDir.path}${Platform.pathSeparator}chemnote'
        '${Platform.pathSeparator}docx_media${Platform.pathSeparator}$batchId',
      );
      if (!await mediaDir.exists()) {
        await mediaDir.create(recursive: true);
      }
      for (var i = 0; i < mediaFiles.length; i++) {
        final mf = mediaFiles[i];
        final rawName = mf.name.split('/').last;
        final safeName = rawName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        final outPath =
            '${mediaDir.path}${Platform.pathSeparator}${i}_$safeName';
        await File(outPath).writeAsBytes(
          Uint8List.fromList(mf.content as List<int>),
          flush: true,
        );
        savedMediaPaths.add(outPath);
      }
    }

    // Phân trang văn bản sạch sẽ trên trang A4 (~38 dòng/trang, lề gọn gàng)
    final pageBlocks = _paginateParagraphs(paragraphs, maxLinesPerPage: 38);
    if (pageBlocks.isEmpty && savedMediaPaths.isEmpty) {
      pageBlocks.add('(Tài liệu Word trống)');
    }

    final totalPages = pageBlocks.length + (savedMediaPaths.isNotEmpty && pageBlocks.isEmpty ? 1 : 0);
    final pages = <NotePage>[];
    final now = DateTime.now();

    for (var i = 0; i < pageBlocks.length; i++) {
      final pageNum = i + 1;
      onProgress?.call(
        pageNum,
        totalPages,
        'Đang dựng trang Word $pageNum/$totalPages...',
      );
      await Future<void>.delayed(Duration.zero);

      final textEl = TextElement(
        id: _uuid.v4(),
        x: 56.0,
        y: 56.0,
        width: 682.0,
        height: 1010.0,
        text: pageBlocks[i],
        fontSize: 16.0,
        colorValue: 0xFF1F2937,
      );

      pages.add(
        NotePage(
          id: _uuid.v4(),
          index: startIndex + pages.length,
          templateType: PaperTemplateType.blank,
          paperColor: PaperColorType.white,
          isLandscape: false,
          textElements: <TextElement>[textEl],
          title: 'Trang $pageNum',
          updatedAt: now,
        ),
      );
    }

    // Đặt ảnh nhúng (nếu có) thành trang ảnh hoặc nối gọn phía sau để dễ chú thích
    if (savedMediaPaths.isNotEmpty) {
      const imgsPerPage = 2;
      for (var i = 0; i < savedMediaPaths.length; i += imgsPerPage) {
        final chunk = savedMediaPaths.sublist(
          i,
          (i + imgsPerPage).clamp(0, savedMediaPaths.length),
        );
        final imgElements = <ImageElement>[];
        for (var j = 0; j < chunk.length; j++) {
          imgElements.add(
            ImageElement(
              id: _uuid.v4(),
              x: 72.0,
              y: 72.0 + j * 490.0,
              width: 650.0,
              height: 440.0,
              filePath: chunk[j],
            ),
          );
        }
        final pageNum = pages.length + 1;
        pages.add(
          NotePage(
            id: _uuid.v4(),
            index: startIndex + pages.length,
            templateType: PaperTemplateType.blank,
            paperColor: PaperColorType.white,
            isLandscape: false,
            imageElements: imgElements,
            title: 'Hình ảnh Word ($pageNum)',
            updatedAt: now,
          ),
        );
      }
    }

    return PdfImportResult(
      sourceFileName: fileName,
      suggestedTitle: _stripExtension(fileName),
      pages: pages,
    );
  }

  PdfImportResult _buildFallbackAttachmentResult({
    required String fileName,
    required String sourcePath,
    required int fileSizeBytes,
    required String extension,
    required int startIndex,
  }) {
    final now = DateTime.now();
    final upperExt = extension.isEmpty ? 'FILE' : extension.toUpperCase();
    final page = NotePage(
      id: _uuid.v4(),
      index: startIndex,
      templateType: PaperTemplateType.blank,
      paperColor: PaperColorType.white,
      title: _stripExtension(fileName),
      attachmentElements: <AttachmentElement>[
        AttachmentElement(
          id: _uuid.v4(),
          x: 64.0,
          y: 72.0,
          width: 320.0,
          height: 76.0,
          fileName: fileName,
          filePath: sourcePath,
          fileExtension: upperExt,
          fileSizeBytes: fileSizeBytes,
        ),
      ],
      textElements: <TextElement>[
        TextElement(
          id: _uuid.v4(),
          x: 64.0,
          y: 170.0,
          width: 660.0,
          height: 120.0,
          text:
              'Tệp $upperExt đã được đính kèm vào trang.\nMẹo: Lưu tệp dưới dạng .docx hoặc .pdf để ChemNote tự động phân trang và viết chú thích trực tiếp lên nội dung.',
          fontSize: 15.0,
          colorValue: 0xFF4B5563,
        ),
      ],
      updatedAt: now,
    );

    return PdfImportResult(
      sourceFileName: fileName,
      suggestedTitle: _stripExtension(fileName),
      pages: <NotePage>[page],
      isFallbackAttachment: true,
    );
  }

  /// Trích xuất danh sách đoạn văn sạch từ `word/document.xml` (hỗ trợ `<w:p>`, `<w:t>`, `<m:t>` công thức, `<w:br/>`, `<w:tab/>`, bỏ qua thẻ tự đóng `<w:p/>`).
  static List<String> _extractDocxParagraphs(String xml) {
    final paragraphs = <String>[];
    final pRegex = RegExp(r'<w:p(?:\s[^>]*)?(?<!/)>([\s\S]*?)</w:p>');
    final tokenRegex = RegExp(
      r'<(?:w|m):t\b[^>]*>([\s\S]*?)</(?:w|m):t>|<w:br\b[^>]*/>|<w:cr\b[^>]*/>|<w:tab\b[^>]*/>',
    );

    for (final pMatch in pRegex.allMatches(xml)) {
      final pBody = pMatch.group(1) ?? '';
      final buf = StringBuffer();
      for (final tok in tokenRegex.allMatches(pBody)) {
        final full = tok.group(0) ?? '';
        if (full.startsWith('<w:br') || full.startsWith('<w:cr')) {
          buf.write('\n');
        } else if (full.startsWith('<w:tab')) {
          buf.write('    ');
        } else {
          final rawText = tok.group(1) ?? '';
          buf.write(_decodeXmlEntities(rawText));
        }
      }
      final line = buf.toString().trimRight();
      if (line.isNotEmpty) {
        paragraphs.add(line);
      }
    }
    return paragraphs;
  }

  /// Chia các đoạn văn Word thành từng trang A4 gọn gàng (~38 dòng/trang).
  static List<String> _paginateParagraphs(
    List<String> paragraphs, {
    int maxLinesPerPage = 38,
    int approxCharsPerLine = 68,
  }) {
    final pages = <String>[];
    final currentBuf = StringBuffer();
    var currentLines = 0;

    for (final para in paragraphs) {
      final subLines = para.split('\n');
      var paraVisualLines = 0;
      for (final s in subLines) {
        paraVisualLines +=
            (s.length / approxCharsPerLine).ceil().clamp(1, 200);
      }
      // Thêm 1 dòng trống giữa các đoạn
      final cost = paraVisualLines + 1;

      if (currentLines > 0 && currentLines + cost > maxLinesPerPage) {
        pages.add(currentBuf.toString().trimRight());
        currentBuf.clear();
        currentLines = 0;
      }

      if (currentBuf.isNotEmpty) {
        currentBuf.write('\n\n');
      }
      currentBuf.write(para);
      currentLines += cost;
    }

    if (currentBuf.isNotEmpty) {
      pages.add(currentBuf.toString().trimRight());
    }
    return pages;
  }

  static String _decodeXmlEntities(String input) {
    var out = input
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
    out = out.replaceAllMapped(RegExp(r'&#x([0-9A-Fa-f]+);'), (m) {
      final code = int.tryParse(m.group(1)!, radix: 16);
      return code != null ? String.fromCharCode(code) : m.group(0)!;
    });
    out = out.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1)!);
      return code != null ? String.fromCharCode(code) : m.group(0)!;
    });
    return out;
  }

  String _extensionOf(String fileName) {
    final idx = fileName.lastIndexOf('.');
    if (idx < 0 || idx == fileName.length - 1) return '';
    return fileName.substring(idx + 1).toLowerCase();
  }

  String _stripExtension(String fileName) {
    final trimmed = fileName.trim();
    final idx = trimmed.lastIndexOf('.');
    if (idx > 0) {
      return trimmed.substring(0, idx);
    }
    return trimmed.isEmpty ? 'Tài liệu nhập' : trimmed;
  }
}
