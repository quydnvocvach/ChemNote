import 'dart:convert';
import 'dart:typed_data';

import 'package:chemnote/features/pdf/pdf_import_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PdfImportService sharpness & page estimation', () {
    test('uses high default DPI for sharp text on MatePad 11.5"S', () {
      expect(PdfImportService.defaultPdfDpi, greaterThanOrEqualTo(200.0));
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
    });
  });
}
