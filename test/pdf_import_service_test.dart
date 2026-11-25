import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:chemnote/core/models/drawing_elements.dart';
import 'package:chemnote/features/pdf/docx_html_converter.dart';
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

    test('DocxHtmlConverter preserves fonts, colors, tables, inline images & OMML MathML', () {
      const stylesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:docDefaults>
    <w:rPrDefault>
      <w:rPr>
        <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/>
        <w:sz w:val="22"/>
      </w:rPr>
    </w:rPrDefault>
  </w:docDefaults>
  <w:style w:type="paragraph" w:styleId="Normal">
    <w:rPr><w:rFonts w:ascii="Calibri"/></w:rPr>
  </w:style>
</w:styles>''';

      const relsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/chem_fig.png"/>
</Relationships>''';

      const docXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
            xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"
            xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
            xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing">
  <w:body>
    <w:p>
      <w:pPr><w:jc w:val="center"/></w:pPr>
      <w:r>
        <w:rPr>
          <w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/>
          <w:b/><w:i/>
          <w:color w:val="C00000"/>
          <w:sz w:val="28"/>
        </w:rPr>
        <w:t>Phản ứng oxi hóa khử</w:t>
      </w:r>
    </w:p>
    <w:p>
      <m:oMath>
        <m:f><m:num><m:r><m:t>1</m:t></m:r></m:num><m:den><m:r><m:t>2</m:t></m:r></m:den></m:f>
        <m:sSubSup>
          <m:e><m:r><m:rPr><m:nor/></m:rPr><m:t>SO</m:t></m:r></m:e>
          <m:sub><m:r><m:t>4</m:t></m:r></m:sub>
          <m:sup><m:r><m:t>2-</m:t></m:r></m:sup>
        </m:sSubSup>
        <m:rad><m:radPr><m:degHide m:val="1"/></m:radPr><m:e><m:r><m:t>2</m:t></m:r></m:e></m:rad>
        <m:limUpp><m:e><m:r><m:t>→</m:t></m:r></m:e><m:lim><m:r><m:t>t°</m:t></m:r></m:lim></m:limUpp>
      </m:oMath>
    </w:p>
    <w:tbl>
      <w:tr>
        <w:tc><w:tcPr><w:gridSpan w:val="2"/></w:tcPr><w:p><w:r><w:t>Bảng hóa trị</w:t></w:r></w:p></w:tc>
      </w:tr>
    </w:tbl>
    <w:p>
      <w:r>
        <w:drawing>
          <wp:inline>
            <wp:extent cx="952500" cy="476250"/>
            <a:graphic><a:graphicData><pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:blipFill><a:blip r:embed="rId1"/></pic:blipFill></pic:pic></a:graphicData></a:graphic>
          </wp:inline>
        </w:drawing>
      </w:r>
    </w:p>
  </w:body>
</w:document>''';

      final stylesBytes = utf8.encode(stylesXml);
      final relsBytes = utf8.encode(relsXml);
      final docBytes = utf8.encode(docXml);
      final fakePng = Uint8List.fromList(const [0x89, 0x50, 0x4E, 0x47]);

      final archive = Archive()
        ..addFile(ArchiveFile('word/styles.xml', stylesBytes.length, stylesBytes))
        ..addFile(ArchiveFile('word/_rels/document.xml.rels', relsBytes.length, relsBytes))
        ..addFile(ArchiveFile('word/media/chem_fig.png', fakePng.length, fakePng))
        ..addFile(ArchiveFile('word/document.xml', docBytes.length, docBytes));
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive)!);

      final result = DocxHtmlConverter.convert(bytes);
      expect(result.html, contains('Times New Roman'));
      expect(result.html, contains('14.0pt'));
      expect(result.html, contains('font-weight:700'));
      expect(result.html, contains('font-style:italic'));
      expect(result.html, contains('#C00000'));
      expect(result.html, contains('text-align:center'));
      expect(result.html, contains('<math'));
      expect(result.html, contains('<mfrac>'));
      expect(result.html, contains('<msubsup>'));
      expect(result.html, contains('<msqrt>'));
      expect(result.html, contains('<mover>'));
      expect(result.html, contains('<table'));
      expect(result.html, contains('colspan="2"'));
      expect(result.html, contains('data:image/png;base64,'));
    });
  });
}
