import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:chemnote/core/models/drawing_elements.dart';
import 'package:chemnote/features/pdf/pdf_import_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PdfImportService sharpness & page estimation', () {
    test('uses safe fallback DPI and high native long-edge target on MatePad 11.5"S', () {
      expect(PdfImportService.nativeTargetLongEdgePx, greaterThanOrEqualTo(2000));
      expect(PdfImportService.defaultPdfDpi, greaterThanOrEqualTo(132.0));
      expect(PdfImportService.defaultPdfDpi, lessThanOrEqualTo(180.0));
    });

    test('estimates page count from /Type /Page and /Count headers', () {
      final byPages = Uint8List.fromList(latin1.encode('''
%PDF-1.4
1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
2 0 obj << /Type /Pages /Kids [3 0 R 4 0 R 5 0 R] /Count 3 >> endobj
3 0 obj << /Type /Page /Parent 2 0 R >> endobj
4 0 obj << /Type /Page /Parent 2 0 R >> endobj
5 0 obj << /Type /Page /Parent 2 0 R >> endobj
'''));
      expect(PdfImportService.estimatePdfPageCount(byPages), 3);

      final compressedByCountOnly = Uint8List.fromList(latin1.encode('''
%PDF-1.7
1 0 obj << /Type /Pages /Count 72 /Kids [] >> endobj
'''));
      expect(PdfImportService.estimatePdfPageCount(compressedByCountOnly), 72);

      expect(PdfImportService.estimatePdfPageCount(Uint8List(0)), isNull);
      expect(
        PdfImportService.estimatePdfPageCount(Uint8List(25 * 1024 * 1024 + 1)),
        isNull,
      );
    });
  });

  group('PdfImportService Word (.docx) extraction', () {
    test('extracts paragraphs and OMML formulas past self-closing <w:p/> onto white pages', () async {
      const xml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
            xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math">
  <w:body>
    <w:p><w:r><w:t>Bài 1: Dung dịch chất điện li</w:t></w:r></w:p>
    <w:p w:rsidR="001234"/>
    <w:p><m:oMath><m:r><m:t>H2SO4 -> 2H+ + SO4(2-)</m:t></m:r></m:oMath></w:p>
  </w:body>
</w:document>''';
      final xmlBytes = utf8.encode(xml);
      final archive = Archive()
        ..addFile(ArchiveFile('word/document.xml', xmlBytes.length, xmlBytes));
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive)!);

      final result = await PdfImportService().importDocxBytes(
        bytes,
        fileName: 'hoa_hoc_11.docx',
      );

      expect(result.suggestedTitle, 'hoa_hoc_11');
      expect(result.pages, isNotEmpty);
      expect(result.pages.first.paperColor, PaperColorType.white);
      final combinedText =
          result.pages.first.textElements.map((e) => e.text).join('\n');
      expect(combinedText, contains('Bài 1: Dung dịch chất điện li'));
      expect(combinedText, contains('H2SO4 -> 2H+ + SO4(2-)'));
    });
  });
}
