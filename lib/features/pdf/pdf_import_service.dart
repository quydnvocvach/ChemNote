import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/drawing_elements.dart';
import '../../core/models/note_page.dart';

/// Kết quả sau khi nhập tệp PDF thành danh sách các trang `NotePage` có ảnh nền PNG.
class PdfImportResult {
  const PdfImportResult({
    required this.sourceFileName,
    required this.suggestedTitle,
    required this.pages,
  });

  final String sourceFileName;
  final String suggestedTitle;
  final List<NotePage> pages;
}

/// Ngoại lệ trong quá trình chọn hoặc chuyển đổi PDF.
class PdfImportException implements Exception {
  const PdfImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Dịch vụ nhập tài liệu PDF (giáo trình, slide bài giảng Hóa học) thành các trang ghi chú
/// có nền ảnh PNG để sinh viên viết tay chú thích trực tiếp lên trên.
class PdfImportService {
  PdfImportService({
    Uuid? uuid,
    Directory? overrideBaseDir,
  })  : _uuid = uuid ?? const Uuid(),
        _overrideBaseDir = overrideBaseDir;

  final Uuid _uuid;
  final Directory? _overrideBaseDir;

  /// Mở trình chọn tệp của hệ thống để chọn PDF và chuyển đổi từng trang thành `NotePage`.
  /// Trả về `null` nếu người dùng hủy chọn tệp.
  Future<PdfImportResult?> pickAndImportPdf({
    int startIndex = 0,
    double dpi = 150.0,
    void Function(int currentPage)? onPageRendered,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['pdf'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final picked = result.files.first;
    Uint8List? bytes = picked.bytes;
    if (bytes == null && picked.path != null) {
      bytes = await File(picked.path!).readAsBytes();
    }

    if (bytes == null || bytes.isEmpty) {
      throw const PdfImportException('Không thể đọc dữ liệu từ tệp PDF đã chọn.');
    }

    return importPdfBytes(
      bytes,
      fileName: picked.name,
      startIndex: startIndex,
      dpi: dpi,
      onPageRendered: onPageRendered,
    );
  }

  /// Nhập trực tiếp từ một `File` PDF có sẵn trên thiết bị.
  Future<PdfImportResult> importPdfFile(
    File pdfFile, {
    int startIndex = 0,
    double dpi = 150.0,
    void Function(int currentPage)? onPageRendered,
  }) async {
    if (!await pdfFile.exists()) {
      throw PdfImportException('Không tìm thấy tệp PDF: ${pdfFile.path}');
    }
    final bytes = await pdfFile.readAsBytes();
    final fileName = pdfFile.uri.pathSegments.isNotEmpty
        ? pdfFile.uri.pathSegments.last
        : 'tai_lieu.pdf';

    return importPdfBytes(
      bytes,
      fileName: fileName,
      startIndex: startIndex,
      dpi: dpi,
      onPageRendered: onPageRendered,
    );
  }

  /// Kết xuất từng trang PDF thành ảnh PNG lưu trong thư mục ứng dụng và trả về danh sách `NotePage`.
  Future<PdfImportResult> importPdfBytes(
    Uint8List pdfBytes, {
    required String fileName,
    int startIndex = 0,
    double dpi = 150.0,
    void Function(int currentPage)? onPageRendered,
  }) async {
    final baseDir =
        _overrideBaseDir ?? await getApplicationDocumentsDirectory();
    final importBatchId = _uuid.v4();
    final targetDir = Directory(
      '${baseDir.path}${Platform.pathSeparator}chemnote'
      '${Platform.pathSeparator}pdf_pages${Platform.pathSeparator}$importBatchId',
    );
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final pages = <NotePage>[];
    var pageNumber = 0;

    try {
      await for (final raster in Printing.raster(pdfBytes, dpi: dpi)) {
        pageNumber++;
        final pngBytes = await raster.toPng();
        final filePath =
            '${targetDir.path}${Platform.pathSeparator}page_$pageNumber.png';
        await File(filePath).writeAsBytes(pngBytes, flush: true);

        final isLandscape = raster.width > raster.height;
        pages.add(
          NotePage(
            id: _uuid.v4(),
            index: startIndex + pageNumber - 1,
            templateType: PaperTemplateType.blank,
            paperColor: PaperColorType.white,
            isLandscape: isLandscape,
            pdfBackgroundPath: filePath,
            pdfPageNumber: pageNumber,
            title: 'Trang $pageNumber',
            updatedAt: DateTime.now(),
          ),
        );

        onPageRendered?.call(pageNumber);
      }
    } catch (e) {
      throw PdfImportException('Không thể giải mã các trang PDF: $e');
    }

    if (pages.isEmpty) {
      throw const PdfImportException('Tệp PDF không chứa trang nào hợp lệ.');
    }

    final suggestedTitle = _stripPdfExtension(fileName);
    return PdfImportResult(
      sourceFileName: fileName,
      suggestedTitle: suggestedTitle,
      pages: pages,
    );
  }

  String _stripPdfExtension(String fileName) {
    final trimmed = fileName.trim();
    if (trimmed.toLowerCase().endsWith('.pdf') && trimmed.length > 4) {
      return trimmed.substring(0, trimmed.length - 4);
    }
    return trimmed.isEmpty ? 'Tài liệu PDF' : trimmed;
  }
}
