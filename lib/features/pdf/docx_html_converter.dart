import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Kết quả chuyển đổi tệp `.docx` (OOXML) sang tài liệu HTML5 + CSS + MathML đầy đủ định dạng.
class DocxHtmlResult {
  const DocxHtmlResult({
    required this.html,
    this.isLandscape = false,
    this.marginTopPt = 48.0,
    this.marginBottomPt = 48.0,
    this.marginLeftPt = 54.0,
    this.marginRightPt = 54.0,
  });

  final String html;
  final bool isLandscape;
  final double marginTopPt;
  final double marginBottomPt;
  final double marginLeftPt;
  final double marginRightPt;
}

/// Bộ chuyển đổi `.docx` thuần Dart giữ nguyên font chữ, kích thước, màu sắc,
/// căn lề, bảng biểu (`colspan`/`rowspan`), ảnh nhúng nội tuyến và công thức OMML -> MathML.
class DocxHtmlConverter {
  DocxHtmlConverter._(
    this._mediaDataUris,
    this._styles,
    this._docDefaultStyle,
    this._numberingOrdered,
  );

  final Map<String, String> _mediaDataUris;
  final Map<String, _RunStyle> _styles;
  final _RunStyle _docDefaultStyle;
  final Map<String, bool> _numberingOrdered;
  final Map<String, int> _listCounters = <String, int>{};

  static final RegExp _nonHexRe = RegExp(r'^[0-9A-Fa-f]{6}$');

  /// Giải mã [docxBytes] và chuyển đổi thành tài liệu HTML5/CSS/MathML sẵn sàng kết xuất PDF.
  static DocxHtmlResult convert(Uint8List docxBytes) {
    final Archive archive = ZipDecoder().decodeBytes(docxBytes);

    final entryMap = <String, ArchiveFile>{};
    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      entryMap[_normalizeArchivePath(entry.name)] = entry;
    }

    final docXmlEntry = entryMap['word/document.xml'];
    if (docXmlEntry == null) {
      throw const FormatException(
        'Không tìm thấy word/document.xml trong tệp .docx.',
      );
    }

    // 1. Đọc quan hệ rId -> đường dẫn media trong word/_rels/document.xml.rels
    final relsEntry = entryMap['word/_rels/document.xml.rels'];
    final relTargets = <String, String>{};
    if (relsEntry != null) {
      final relXml = utf8.decode(
        relsEntry.content as List<int>,
        allowMalformed: true,
      );
      final relRoot = _XmlParser.parse(relXml);
      for (final node in relRoot.findAll('Relationship')) {
        final id = node.attrs['Id'] ?? '';
        final target = node.attrs['Target'] ?? '';
        if (id.isEmpty || target.isEmpty) continue;
        relTargets[id] = _resolveWordTarget(target);
      }
    }

    // 2. Mã hóa ảnh nhúng thành Data URI để Chromium WebView hiển thị trực tiếp
    final mediaDataUris = <String, String>{};
    relTargets.forEach((rId, archivePath) {
      final imgFile = entryMap[archivePath];
      if (imgFile == null) return;
      final mime = _imageMimeForPath(archivePath);
      if (mime == null) return;
      final rawBytes = imgFile.content as List<int>;
      if (rawBytes.isEmpty) return;
      mediaDataUris[rId] = 'data:$mime;base64,${base64Encode(rawBytes)}';
    });

    // 3. Đọc word/styles.xml (docDefaults + style kế thừa)
    final parsedStyles = _parseStylesXml(entryMap['word/styles.xml']);

    // 4. Đọc word/numbering.xml (danh sách có dấu đầu dòng vs đánh số)
    final numberingOrdered = _parseNumberingXml(entryMap['word/numbering.xml']);

    // 5. Đọc kích thước khổ giấy, lề & toàn bộ nội dung word/document.xml
    final docXml = utf8.decode(
      docXmlEntry.content as List<int>,
      allowMalformed: true,
    );
    final docRoot = _XmlParser.parse(docXml);
    final bodyNode = docRoot.firstDescendant('body');
    if (bodyNode == null) {
      throw const FormatException('Không tìm thấy thẻ <w:body> trong .docx.');
    }

    final sectionInfo = _extractSectionInfo(bodyNode);
    final converter = DocxHtmlConverter._(
      mediaDataUris,
      parsedStyles.styles,
      parsedStyles.docDefault,
      numberingOrdered,
    );

    final bodyHtml = StringBuffer();
    for (final child in bodyNode.children) {
      final local = child.localName;
      if (local == 'p') {
        bodyHtml.write(converter._renderParagraph(child));
      } else if (local == 'tbl') {
        bodyHtml.write(converter._renderTable(child));
      } else if (local == 'sdt') {
        final sdtContent = child.firstDescendant('sdtContent');
        if (sdtContent != null) {
          for (final nested in sdtContent.children) {
            if (nested.localName == 'p') {
              bodyHtml.write(converter._renderParagraph(nested));
            } else if (nested.localName == 'tbl') {
              bodyHtml.write(converter._renderTable(nested));
            }
          }
        }
      }
    }

    final defaultFontCss = _cssFontStack(
      parsedStyles.docDefault.fontFamily ?? 'Times New Roman',
    );
    final defaultSizePt = parsedStyles.docDefault.fontSizePt ?? 11.5;

    final fullHtml = '''<!DOCTYPE html>
<html lang="vi">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<style>
  @page {
    size: ${sectionInfo.isLandscape ? 'A4 landscape' : 'A4 portrait'};
    margin: ${sectionInfo.marginTopPt.toStringAsFixed(1)}pt ${sectionInfo.marginRightPt.toStringAsFixed(1)}pt ${sectionInfo.marginBottomPt.toStringAsFixed(1)}pt ${sectionInfo.marginLeftPt.toStringAsFixed(1)}pt;
  }
  * {
    box-sizing: border-box;
  }
  html, body {
    margin: 0;
    padding: 0;
    background: #ffffff;
    color: #111827;
    font-family: $defaultFontCss;
    font-size: ${defaultSizePt.toStringAsFixed(1)}pt;
    line-height: 1.42;
    -webkit-print-color-adjust: exact;
    print-color-adjust: exact;
  }
  p.docx-p {
    margin: 0 0 6pt 0;
    min-height: 1em;
    white-space: normal;
    word-wrap: break-word;
  }
  .page-break {
    break-before: page;
    page-break-before: always;
    height: 0;
    margin: 0;
    padding: 0;
  }
  table.docx-table {
    width: 100%;
    border-collapse: collapse;
    margin: 6pt 0 10pt 0;
    table-layout: auto;
    page-break-inside: auto;
  }
  table.docx-table tr {
    page-break-inside: avoid;
    break-inside: avoid;
  }
  table.docx-table td, table.docx-table th {
    border: 1px solid #475569;
    padding: 4pt 6pt;
    vertical-align: top;
    word-wrap: break-word;
  }
  table.docx-table p.docx-p:last-child {
    margin-bottom: 0;
  }
  img.docx-img {
    max-width: 100%;
    height: auto;
    vertical-align: middle;
  }
  .math-block {
    display: block;
    text-align: center;
    margin: 6pt 0;
  }
  math {
    font-family: "Cambria Math", "STIX Two Math", "Latin Modern Math", "Noto Serif", "Times New Roman", serif;
    font-size: 1.05em;
  }
  span.docx-list-marker {
    display: inline-block;
    min-width: 18pt;
    font-weight: 500;
  }
</style>
</head>
<body>
${bodyHtml.toString()}
</body>
</html>''';

    return DocxHtmlResult(
      html: fullHtml,
      isLandscape: sectionInfo.isLandscape,
      marginTopPt: sectionInfo.marginTopPt,
      marginBottomPt: sectionInfo.marginBottomPt,
      marginLeftPt: sectionInfo.marginLeftPt,
      marginRightPt: sectionInfo.marginRightPt,
    );
  }

  String _renderParagraph(_XmlNode pNode, {bool insideTable = false}) {
    final out = StringBuffer();
    final pPr = pNode.firstChild('pPr');

    // Kiểm tra ngắt trang trước đoạn văn
    if (!insideTable && pPr?.firstChild('pageBreakBefore') != null) {
      out.write('<div class="page-break"></div>');
    }

    // Lấy style đoạn văn kế thừa từ styles.xml
    final pStyleId = pPr?.firstChild('pStyle')?.attrs['val'];
    final baseStyle = pStyleId != null && _styles.containsKey(pStyleId)
        ? _docDefaultStyle.merge(_styles[pStyleId]!)
        : _docDefaultStyle;

    final pCss = StringBuffer();
    final align =
        _mapJc(pPr?.firstChild('jc')?.attrs['val']) ?? baseStyle.align;
    if (align != null) {
      pCss.write('text-align:$align;');
    }

    final spacing = pPr?.firstChild('spacing');
    final beforePt = _twipsToPt(spacing?.attrs['before']) ??
        baseStyle.spaceBeforePt;
    final afterPt = _twipsToPt(spacing?.attrs['after']) ??
        baseStyle.spaceAfterPt;
    if (beforePt != null) {
      pCss.write('margin-top:${beforePt.toStringAsFixed(1)}pt;');
    }
    if (afterPt != null) {
      pCss.write('margin-bottom:${afterPt.toStringAsFixed(1)}pt;');
    }
    final lineAttr = double.tryParse(spacing?.attrs['line'] ?? '');
    final lineRule = spacing?.attrs['lineRule'] ?? 'auto';
    if (lineAttr != null && lineAttr > 0) {
      if (lineRule == 'auto') {
        final mult = (lineAttr / 240.0).clamp(1.05, 2.5);
        pCss.write('line-height:${mult.toStringAsFixed(2)};');
      } else {
        final pt = (lineAttr / 20.0).clamp(10.0, 48.0);
        pCss.write('line-height:${pt.toStringAsFixed(1)}pt;');
      }
    }

    final ind = pPr?.firstChild('ind');
    final leftPt = _twipsToPt(ind?.attrs['left'] ?? ind?.attrs['start']) ??
        baseStyle.indentLeftPt;
    final firstLinePt = _twipsToPt(ind?.attrs['firstLine']);
    final hangingPt = _twipsToPt(ind?.attrs['hanging']);
    double totalLeft = leftPt ?? 0.0;
    if (hangingPt != null && hangingPt > 0) {
      pCss.write('text-indent:-${hangingPt.toStringAsFixed(1)}pt;');
    } else if (firstLinePt != null && firstLinePt > 0) {
      pCss.write('text-indent:${firstLinePt.toStringAsFixed(1)}pt;');
    }

    // Đánh dấu đầu dòng/số thứ tự từ <w:numPr>
    final numPr = pPr?.firstChild('numPr');
    String listMarkerHtml = '';
    if (numPr != null) {
      final numId = numPr.firstChild('numId')?.attrs['val'] ?? '';
      final ilvl =
          int.tryParse(numPr.firstChild('ilvl')?.attrs['val'] ?? '0') ?? 0;
      if (numId.isNotEmpty && numId != '0') {
        totalLeft += (ilvl + 1) * 18.0;
        final isOrdered = _numberingOrdered[numId] ?? false;
        if (isOrdered) {
          final key = '$numId:$ilvl';
          final nextNum = (_listCounters[key] ?? 0) + 1;
          _listCounters[key] = nextNum;
          listMarkerHtml = '<span class="docx-list-marker">$nextNum.</span>';
        } else {
          final bullet = ilvl == 0 ? '&bull;' : (ilvl == 1 ? '&#9702;' : '&#9642;');
          listMarkerHtml = '<span class="docx-list-marker">$bullet</span>';
        }
      }
    }

    if (totalLeft > 0) {
      pCss.write('margin-left:${totalLeft.toStringAsFixed(1)}pt;');
    }

    final shdFill = _normalizeHexColor(pPr?.firstChild('shd')?.attrs['fill']);
    if (shdFill != null) {
      pCss.write('background-color:$shdFill;padding:2pt 4pt;');
    }

    // Viền đoạn văn (<w:pBdr>)
    final pBdr = pPr?.firstChild('pBdr');
    if (pBdr != null) {
      for (final side in const ['top', 'bottom', 'left', 'right']) {
        final b = pBdr.firstChild(side);
        if (b != null && b.attrs['val'] != 'none' && b.attrs['val'] != 'nil') {
          final bColor = _normalizeHexColor(b.attrs['color']) ?? '#334155';
          pCss.write('border-$side:1px solid $bColor;');
        }
      }
    }

    // Dựng nội dung bên trong đoạn văn
    final inner = StringBuffer();
    if (listMarkerHtml.isNotEmpty) {
      inner.write(listMarkerHtml);
    }

    for (final child in pNode.children) {
      final local = child.localName;
      if (local == 'pPr') continue;
      if (local == 'r') {
        inner.write(_renderRun(child, baseStyle));
      } else if (local == 'hyperlink') {
        for (final hChild in child.children) {
          if (hChild.localName == 'r') {
            inner.write(_renderRun(hChild, baseStyle, forceUnderlineLink: true));
          }
        }
      } else if (local == 'oMathPara') {
        inner.write(_renderOMathPara(child));
      } else if (local == 'oMath') {
        inner.write(_renderOMath(child, displayBlock: false));
      } else if (local == 'sdt') {
        final content = child.firstDescendant('sdtContent');
        if (content != null) {
          for (final sub in content.children) {
            if (sub.localName == 'r') {
              inner.write(_renderRun(sub, baseStyle));
            } else if (sub.localName == 'oMath') {
              inner.write(_renderOMath(sub, displayBlock: false));
            }
          }
        }
      }
    }

    final contentStr = inner.toString();
    // Nếu đoạn chỉ chứa <div class="page-break"></div> thuần túy thì không thêm thẻ <p> thừa
    if (contentStr.trim() == '<div class="page-break"></div>') {
      out.write(contentStr);
      return out.toString();
    }

    out.write('<p class="docx-p"');
    if (pCss.isNotEmpty) {
      out.write(' style="${pCss.toString()}"');
    }
    out.write('>');
    if (contentStr.isEmpty) {
      out.write('&nbsp;');
    } else {
      out.write(contentStr);
    }
    out.write('</p>');
    return out.toString();
  }

  String _renderRun(
    _XmlNode rNode,
    _RunStyle inherited, {
    bool forceUnderlineLink = false,
  }) {
    final rPr = rNode.firstChild('rPr');
    var style = inherited;
    final rStyleId = rPr?.firstChild('rStyle')?.attrs['val'];
    if (rStyleId != null && _styles.containsKey(rStyleId)) {
      style = style.merge(_styles[rStyleId]!);
    }
    if (rPr != null) {
      style = style.merge(_parseRunProperties(rPr));
    }

    final spanCss = StringBuffer();
    if (style.fontFamily != null &&
        style.fontFamily != _docDefaultStyle.fontFamily) {
      spanCss.write('font-family:${_cssFontStack(style.fontFamily!)};');
    }
    if (style.fontSizePt != null &&
        style.fontSizePt != _docDefaultStyle.fontSizePt) {
      spanCss.write('font-size:${style.fontSizePt!.toStringAsFixed(1)}pt;');
    }
    if (style.bold == true) {
      spanCss.write('font-weight:700;');
    }
    if (style.italic == true) {
      spanCss.write('font-style:italic;');
    }
    if (forceUnderlineLink) {
      spanCss.write('color:#1D4ED8;text-decoration:underline;');
    } else {
      if (style.colorHex != null) {
        spanCss.write('color:${style.colorHex};');
      }
      final dec = <String>[];
      if (style.underline == true) dec.add('underline');
      if (style.strike == true) dec.add('line-through');
      if (dec.isNotEmpty) {
        spanCss.write('text-decoration:${dec.join(' ')};');
      }
    }
    if (style.highlightHex != null) {
      spanCss.write('background-color:${style.highlightHex};');
    }
    if (style.allCaps == true) {
      spanCss.write('text-transform:uppercase;');
    }

    final buf = StringBuffer();
    for (final child in rNode.children) {
      final local = child.localName;
      if (local == 'rPr') continue;
      if (local == 't' || local == 'delText') {
        buf.write(_escapeHtml(child.innerText));
      } else if (local == 'br' || local == 'cr') {
        if (child.attrs['type'] == 'page') {
          buf.write('<div class="page-break"></div>');
        } else {
          buf.write('<br/>');
        }
      } else if (local == 'tab') {
        buf.write('&emsp;');
      } else if (local == 'sym') {
        final hex = child.attrs['char'];
        final code = hex != null ? int.tryParse(hex, radix: 16) : null;
        if (code != null) {
          buf.write('&#$code;');
        }
      } else if (local == 'drawing') {
        buf.write(_renderDrawing(child));
      } else if (local == 'pict') {
        buf.write(_renderLegacyPict(child));
      } else if (local == 'oMath') {
        buf.write(_renderOMath(child, displayBlock: false));
      }
    }

    var content = buf.toString();
    if (content.isEmpty) return '';

    // Nếu đoạn chỉ chứa ngắt trang hoặc hình ảnh nguyên khối, giữ nguyên CSS text nếu có chữ
    if (style.vertAlign == 'subscript') {
      content = '<sub>$content</sub>';
    } else if (style.vertAlign == 'superscript') {
      content = '<sup>$content</sup>';
    }

    if (spanCss.isEmpty) return content;
    return '<span style="${spanCss.toString()}">$content</span>';
  }

  String _renderDrawing(_XmlNode drawingNode) {
    final blip = drawingNode.firstDescendant('blip');
    if (blip == null) return '';
    final rId = blip.attrs['embed'] ?? blip.attrs['link'] ?? '';
    final dataUri = _mediaDataUris[rId];
    if (dataUri == null) return '';

    final extent = drawingNode.firstDescendant('extent');
    final cx = double.tryParse(extent?.attrs['cx'] ?? '');
    final cy = double.tryParse(extent?.attrs['cy'] ?? '');
    final styleBuf = StringBuffer('max-width:100%;height:auto;');
    if (cx != null && cx > 0) {
      // EMU -> CSS px (9525 EMU = 1px @ 96 DPI)
      final wPx = (cx / 9525.0).clamp(8.0, 900.0);
      styleBuf.write('width:${wPx.toStringAsFixed(0)}px;');
    } else if (cy != null && cy > 0) {
      final hPx = (cy / 9525.0).clamp(8.0, 1100.0);
      styleBuf.write('height:${hPx.toStringAsFixed(0)}px;width:auto;');
    }
    return '<img class="docx-img" src="$dataUri" style="${styleBuf.toString()}" />';
  }

  String _renderLegacyPict(_XmlNode pictNode) {
    final imgData = pictNode.firstDescendant('imagedata');
    if (imgData == null) return '';
    final rId = imgData.attrs['id'] ?? imgData.attrs['relid'] ?? '';
    final dataUri = _mediaDataUris[rId];
    if (dataUri == null) return '';
    return '<img class="docx-img" src="$dataUri" />';
  }

  String _renderTable(_XmlNode tblNode) {
    final tblPr = tblNode.firstChild('tblPr');
    final tblBorders = tblPr?.firstChild('tblBorders');
    final bool noTableBorders = tblBorders != null &&
        _areAllBordersNone(tblBorders, const ['top', 'bottom', 'left', 'right', 'insideH', 'insideV']);

    // Đọc độ rộng cột nếu có <w:tblGrid>
    final gridCols = <double>[];
    final tblGrid = tblNode.firstChild('tblGrid');
    if (tblGrid != null) {
      for (final col in tblGrid.children) {
        if (col.localName == 'gridCol') {
          final wPt = _twipsToPt(col.attrs['w']);
          if (wPt != null && wPt > 0) gridCols.add(wPt);
        }
      }
    }
    final double totalGridPt = gridCols.fold(0.0, (a, b) => a + b);

    final rowNodes = tblNode.children.where((c) => c.localName == 'tr').toList();
    if (rowNodes.isEmpty) return '';

    // Tiền xử lý rowspan cho các ô gộp dọc (<w:vMerge>)
    final rowspanGrid = List.generate(rowNodes.length, (_) => <int, int>{});
    final skippedCells = List.generate(rowNodes.length, (_) => <int>{});
    final activeVMergeStartRow = <int, int>{};

    for (var rIdx = 0; rIdx < rowNodes.length; rIdx++) {
      final tcNodes =
          rowNodes[rIdx].children.where((c) => c.localName == 'tc').toList();
      var colCursor = 0;
      for (var cIdx = 0; cIdx < tcNodes.length; cIdx++) {
        final tc = tcNodes[cIdx];
        final tcPr = tc.firstChild('tcPr');
        final colspan =
            (int.tryParse(tcPr?.firstChild('gridSpan')?.attrs['val'] ?? '1') ??
                    1)
                .clamp(1, 50);
        final vMerge = tcPr?.firstChild('vMerge');
        if (vMerge != null) {
          final val = vMerge.attrs['val'] ?? '';
          if (val == 'restart') {
            activeVMergeStartRow[colCursor] = rIdx;
            rowspanGrid[rIdx][cIdx] = 1;
          } else {
            final startRow = activeVMergeStartRow[colCursor];
            if (startRow != null) {
              // Tìm cell index tại startRow tương ứng colCursor
              final startRowCells = rowNodes[startRow]
                  .children
                  .where((c) => c.localName == 'tc')
                  .toList();
              var scanCol = 0;
              for (var sc = 0; sc < startRowCells.length; sc++) {
                if (scanCol == colCursor) {
                  rowspanGrid[startRow][sc] =
                      (rowspanGrid[startRow][sc] ?? 1) + 1;
                  break;
                }
                final scSpan = int.tryParse(startRowCells[sc]
                            .firstChild('tcPr')
                            ?.firstChild('gridSpan')
                            ?.attrs['val'] ??
                        '1') ??
                    1;
                scanCol += scSpan;
              }
              skippedCells[rIdx].add(cIdx);
            }
          }
        } else {
          for (var k = colCursor; k < colCursor + colspan; k++) {
            activeVMergeStartRow.remove(k);
          }
        }
        colCursor += colspan;
      }
    }

    final buf = StringBuffer('<table class="docx-table">');
    for (var rIdx = 0; rIdx < rowNodes.length; rIdx++) {
      final row = rowNodes[rIdx];
      final tcNodes = row.children.where((c) => c.localName == 'tc').toList();
      buf.write('<tr>');
      var colCursor = 0;
      for (var cIdx = 0; cIdx < tcNodes.length; cIdx++) {
        final tc = tcNodes[cIdx];
        final tcPr = tc.firstChild('tcPr');
        final colspan =
            (int.tryParse(tcPr?.firstChild('gridSpan')?.attrs['val'] ?? '1') ??
                    1)
                .clamp(1, 50);
        if (skippedCells[rIdx].contains(cIdx)) {
          colCursor += colspan;
          continue;
        }
        final rowspan = (rowspanGrid[rIdx][cIdx] ?? 1).clamp(1, 200);

        final tdCss = StringBuffer();
        if (noTableBorders) {
          tdCss.write('border:none;');
        }
        final cellBorders = tcPr?.firstChild('tcBorders');
        if (cellBorders != null) {
          for (final side in const ['top', 'bottom', 'left', 'right']) {
            final b = cellBorders.firstChild(side);
            if (b != null) {
              if (b.attrs['val'] == 'none' || b.attrs['val'] == 'nil') {
                tdCss.write('border-$side:none;');
              } else {
                final bCol = _normalizeHexColor(b.attrs['color']) ?? '#475569';
                tdCss.write('border-$side:1px solid $bCol;');
              }
            }
          }
        }

        final shdFill =
            _normalizeHexColor(tcPr?.firstChild('shd')?.attrs['fill']);
        if (shdFill != null) {
          tdCss.write('background-color:$shdFill;');
        }
        final vAlign = tcPr?.firstChild('vAlign')?.attrs['val'];
        if (vAlign == 'center') {
          tdCss.write('vertical-align:middle;');
        } else if (vAlign == 'bottom') {
          tdCss.write('vertical-align:bottom;');
        }

        // Độ rộng ô theo phần trăm để vừa vặn chiều ngang trang
        if (totalGridPt > 0 && colCursor < gridCols.length) {
          var sumW = 0.0;
          for (var k = colCursor;
              k < colCursor + colspan && k < gridCols.length;
              k++) {
            sumW += gridCols[k];
          }
          if (sumW > 0) {
            final pct = ((sumW / totalGridPt) * 100.0).clamp(2.0, 100.0);
            tdCss.write('width:${pct.toStringAsFixed(1)}%;');
          }
        }

        buf.write('<td');
        if (colspan > 1) buf.write(' colspan="$colspan"');
        if (rowspan > 1) buf.write(' rowspan="$rowspan"');
        if (tdCss.isNotEmpty) buf.write(' style="${tdCss.toString()}"');
        buf.write('>');

        for (final cellChild in tc.children) {
          if (cellChild.localName == 'p') {
            buf.write(_renderParagraph(cellChild, insideTable: true));
          } else if (cellChild.localName == 'tbl') {
            buf.write(_renderTable(cellChild));
          }
        }
        buf.write('</td>');
        colCursor += colspan;
      }
      buf.write('</tr>');
    }
    buf.write('</table>');
    return buf.toString();
  }

  // ===========================================================================
  // OMML -> HTML5 MATHML CONVERTER (Chromium Native MathML Core)
  // ===========================================================================

  String _renderOMathPara(_XmlNode oMathParaNode) {
    final buf = StringBuffer('<div class="math-block">');
    for (final child in oMathParaNode.children) {
      if (child.localName == 'oMath') {
        buf.write(_renderOMath(child, displayBlock: true));
      } else if (child.localName == 'oMathParaPr') {
        continue;
      } else {
        buf.write(_renderOMathChildren(child));
      }
    }
    buf.write('</div>');
    return buf.toString();
  }

  String _renderOMath(_XmlNode oMathNode, {required bool displayBlock}) {
    final inner = _renderOMathChildren(oMathNode);
    if (inner.trim().isEmpty) return '';
    return '<math xmlns="http://www.w3.org/1998/Math/MathML" '
        'display="${displayBlock ? 'block' : 'inline'}">$inner</math>';
  }

  String _renderOMathChildren(_XmlNode container) {
    final buf = StringBuffer();
    for (final child in container.children) {
      buf.write(_renderOMathNode(child));
    }
    return buf.toString();
  }

  String _renderOMathArg(_XmlNode? container, {bool wrapInMrow = true}) {
    if (container == null) return wrapInMrow ? '<mrow></mrow>' : '';
    final inner = _renderOMathChildren(container);
    if (!wrapInMrow) return inner;
    return '<mrow>$inner</mrow>';
  }

  String _renderOMathNode(_XmlNode node) {
    switch (node.localName) {
      case 'r':
        return _renderOMathRun(node);
      case 'f':
        return _renderOMathFraction(node);
      case 'sSub':
        final base = _renderOMathArg(node.firstChild('e'));
        final sub = _renderOMathArg(node.firstChild('sub'));
        return '<msub>$base$sub</msub>';
      case 'sSup':
        final base = _renderOMathArg(node.firstChild('e'));
        final sup = _renderOMathArg(node.firstChild('sup'));
        return '<msup>$base$sup</msup>';
      case 'sSubSup':
        final base = _renderOMathArg(node.firstChild('e'));
        final sub = _renderOMathArg(node.firstChild('sub'));
        final sup = _renderOMathArg(node.firstChild('sup'));
        return '<msubsup>$base$sub$sup</msubsup>';
      case 'sPre':
        final base = _renderOMathArg(node.firstChild('e'));
        final sub = _renderOMathArg(node.firstChild('sub'));
        final sup = _renderOMathArg(node.firstChild('sup'));
        return '<mmultiscripts>$base<mprescripts/>$sub$sup</mmultiscripts>';
      case 'rad':
        final radPr = node.firstChild('radPr');
        final degHide = radPr?.firstChild('degHide')?.attrs['val'];
        final degNode = node.firstChild('deg');
        final degContent =
            degNode != null ? _renderOMathChildren(degNode).trim() : '';
        final base = _renderOMathArg(node.firstChild('e'));
        if (degHide == '1' || degHide == 'true' || degContent.isEmpty) {
          return '<msqrt>$base</msqrt>';
        }
        return '<mroot>$base<mrow>$degContent</mrow></mroot>';
      case 'nary':
        return _renderOMathNary(node);
      case 'd':
        return _renderOMathDelimiter(node);
      case 'limLow':
        final base = _renderOMathArg(node.firstChild('e'));
        final lim = _renderOMathArg(node.firstChild('lim'));
        return '<munder>$base$lim</munder>';
      case 'limUpp':
        final base = _renderOMathArg(node.firstChild('e'));
        final lim = _renderOMathArg(node.firstChild('lim'));
        return '<mover>$base$lim</mover>';
      case 'acc':
        final chr =
            node.firstChild('accPr')?.firstChild('chr')?.attrs['val'] ?? '\u0302';
        final base = _renderOMathArg(node.firstChild('e'));
        return '<mover accent="true">$base<mo>${_escapeHtml(chr)}</mo></mover>';
      case 'bar':
        final pos = node.firstChild('barPr')?.firstChild('pos')?.attrs['val'];
        final base = _renderOMathArg(node.firstChild('e'));
        if (pos == 'bot') {
          return '<munder>$base<mo>&#x00AF;</mo></munder>';
        }
        return '<mover>$base<mo>&#x00AF;</mo></mover>';
      case 'groupChr':
        final gcPr = node.firstChild('groupChrPr');
        final chr = gcPr?.firstChild('chr')?.attrs['val'] ?? '\u23DF';
        final pos = gcPr?.firstChild('pos')?.attrs['val'] ?? 'bot';
        final base = _renderOMathArg(node.firstChild('e'));
        if (pos == 'top') {
          return '<mover>$base<mo>${_escapeHtml(chr)}</mo></mover>';
        }
        return '<munder>$base<mo>${_escapeHtml(chr)}</mo></munder>';
      case 'm':
        return _renderOMathMatrix(node);
      case 'eqArr':
        final buf = StringBuffer('<mtable>');
        for (final child in node.children) {
          if (child.localName == 'e') {
            buf.write('<mtr><mtd>${_renderOMathChildren(child)}</mtd></mtr>');
          }
        }
        buf.write('</mtable>');
        return buf.toString();
      case 'func':
        final fName = _renderOMathArg(node.firstChild('fName'));
        final e = _renderOMathArg(node.firstChild('e'));
        return '<mrow>$fName<mo>&#x2061;</mo>$e</mrow>';
      case 'box':
      case 'borderBox':
        return _renderOMathArg(node.firstChild('e'));
      case 'phant':
        final show =
            node.firstChild('phantPr')?.firstChild('show')?.attrs['val'];
        final inner = _renderOMathArg(node.firstChild('e'));
        if (show == '0' || show == 'false') {
          return '<mphantom>$inner</mphantom>';
        }
        return inner;
      case 'rPr':
      case 'fPr':
      case 'radPr':
      case 'naryPr':
      case 'dPr':
      case 'accPr':
      case 'barPr':
      case 'groupChrPr':
      case 'mPr':
      case 'eqArrPr':
      case 'funcPr':
      case 'ctrlPr':
      case 'argPr':
        return '';
      default:
        return _renderOMathChildren(node);
    }
  }

  String _renderOMathFraction(_XmlNode node) {
    final fType = node.firstChild('fPr')?.firstChild('type')?.attrs['val'];
    final num = _renderOMathArg(node.firstChild('num'));
    final den = _renderOMathArg(node.firstChild('den'));
    if (fType == 'noBar') {
      return '<mfrac linethickness="0">$num$den</mfrac>';
    }
    return '<mfrac>$num$den</mfrac>';
  }

  String _renderOMathNary(_XmlNode node) {
    final naryPr = node.firstChild('naryPr');
    final chr = naryPr?.firstChild('chr')?.attrs['val'] ?? '\u222B';
    final subHide = naryPr?.firstChild('subHide')?.attrs['val'];
    final supHide = naryPr?.firstChild('supHide')?.attrs['val'];
    final subNode = node.firstChild('sub');
    final supNode = node.firstChild('sup');
    final subContent = (subHide == '1' || subNode == null)
        ? ''
        : _renderOMathChildren(subNode).trim();
    final supContent = (supHide == '1' || supNode == null)
        ? ''
        : _renderOMathChildren(supNode).trim();
    final base = _renderOMathArg(node.firstChild('e'));

    final op = '<mo>${_escapeHtml(chr)}</mo>';
    final String head;
    if (subContent.isNotEmpty && supContent.isNotEmpty) {
      head = '<msubsup>$op<mrow>$subContent</mrow><mrow>$supContent</mrow></msubsup>';
    } else if (subContent.isNotEmpty) {
      head = '<msub>$op<mrow>$subContent</mrow></msub>';
    } else if (supContent.isNotEmpty) {
      head = '<msup>$op<mrow>$supContent</mrow></msup>';
    } else {
      head = op;
    }
    return '$head$base';
  }

  String _renderOMathDelimiter(_XmlNode node) {
    final dPr = node.firstChild('dPr');
    final begNode = dPr?.firstChild('begChr');
    final endNode = dPr?.firstChild('endChr');
    final sepNode = dPr?.firstChild('sepChr');

    final begChr = begNode != null ? (begNode.attrs['val'] ?? '(') : '(';
    final endChr = endNode != null ? (endNode.attrs['val'] ?? ')') : ')';
    final sepChr = sepNode != null ? (sepNode.attrs['val'] ?? ',') : ',';

    final args = node.children.where((c) => c.localName == 'e').toList();
    final buf = StringBuffer('<mrow>');
    if (begChr.isNotEmpty) {
      buf.write('<mo>${_escapeHtml(begChr)}</mo>');
    }
    for (var i = 0; i < args.length; i++) {
      if (i > 0 && sepChr.isNotEmpty) {
        buf.write('<mo>${_escapeHtml(sepChr)}</mo>');
      }
      buf.write(_renderOMathArg(args[i]));
    }
    if (endChr.isNotEmpty) {
      buf.write('<mo>${_escapeHtml(endChr)}</mo>');
    }
    buf.write('</mrow>');
    return buf.toString();
  }

  String _renderOMathMatrix(_XmlNode node) {
    final buf = StringBuffer('<mtable>');
    for (final row in node.children) {
      if (row.localName != 'mr') continue;
      buf.write('<mtr>');
      for (final cell in row.children) {
        if (cell.localName != 'e') continue;
        buf.write('<mtd>${_renderOMathChildren(cell)}</mtd>');
      }
      buf.write('</mtr>');
    }
    buf.write('</mtable>');
    return buf.toString();
  }

  String _renderOMathRun(_XmlNode node) {
    final mRPr = node.firstChild('rPr');
    final bool isNormalText = mRPr?.firstChild('nor') != null;
    final sty = mRPr?.firstChild('sty')?.attrs['val'];
    String? variantAttr;
    if (sty == 'p') {
      variantAttr = ' mathvariant="normal"';
    } else if (sty == 'b') {
      variantAttr = ' mathvariant="bold"';
    } else if (sty == 'bi') {
      variantAttr = ' mathvariant="bold-italic"';
    }

    // Hỗ trợ định dạng màu sắc / font / kích thước inline nếu có trong <w:rPr>
    final wRPr = node.firstChild('rPr', prefix: 'w');
    final hexColor = _normalizeHexColor(wRPr?.firstChild('color')?.attrs['val']);
    final colorStyle = hexColor != null ? ' style="color:$hexColor;"' : '';

    final buf = StringBuffer();
    for (final child in node.children) {
      if (child.localName == 't') {
        final raw = child.innerText;
        if (raw.isEmpty) continue;
        if (isNormalText) {
          buf.write('<mtext$colorStyle>${_escapeHtml(raw)}</mtext>');
        } else {
          buf.write(_tokenizeMathText(raw, variantAttr ?? '', colorStyle));
        }
      }
    }
    return buf.toString();
  }

  static String _tokenizeMathText(
    String raw,
    String variantAttr,
    String colorStyle,
  ) {
    const operators = '+-=*/×÷±∓≤≥≠≈≡→←↔⇌⟶⟵↑↓()[]{}|,:;!?°′″∑∏∫√∞∂∇∈∉⊂⊆∪∩∀∃·∙⋅^_~<>';
    final buf = StringBuffer();
    var i = 0;
    while (i < raw.length) {
      final ch = raw[i];
      if (ch == ' ' || ch == '\t' || ch == '\u00A0') {
        i++;
        continue;
      }
      final code = ch.codeUnitAt(0);
      if (code >= 0x30 && code <= 0x39) {
        final start = i;
        i++;
        while (i < raw.length) {
          final c = raw.codeUnitAt(i);
          if ((c >= 0x30 && c <= 0x39) ||
              (raw[i] == '.' &&
                  i + 1 < raw.length &&
                  raw.codeUnitAt(i + 1) >= 0x30 &&
                  raw.codeUnitAt(i + 1) <= 0x39)) {
            i++;
          } else {
            break;
          }
        }
        buf.write(
          '<mn$colorStyle>${_escapeHtml(raw.substring(start, i))}</mn>',
        );
      } else if (operators.contains(ch)) {
        i++;
        buf.write('<mo$colorStyle>${_escapeHtml(ch)}</mo>');
      } else {
        i++;
        buf.write('<mi$variantAttr$colorStyle>${_escapeHtml(ch)}</mi>');
      }
    }
    return buf.toString();
  }

  // ===========================================================================
  // HELPERS: STYLES, NUMBERING, SECTION, PATHS, XML PARSING
  // ===========================================================================

  static _ParsedStyles _parseStylesXml(ArchiveFile? stylesFile) {
    var docDefault = const _RunStyle();
    final rawStyles = <String, _RawStyleDef>{};
    if (stylesFile == null) {
      return _ParsedStyles(docDefault: docDefault, styles: const {});
    }
    final xml = utf8.decode(
      stylesFile.content as List<int>,
      allowMalformed: true,
    );
    final root = _XmlParser.parse(xml);

    final docDefaults = root.firstDescendant('docDefaults');
    if (docDefaults != null) {
      final rPr = docDefaults.firstDescendant('rPr');
      if (rPr != null) {
        docDefault = docDefault.merge(_parseRunProperties(rPr));
      }
      final pPr = docDefaults.firstDescendant('pPr');
      if (pPr != null) {
        docDefault = docDefault.merge(_parseParagraphStyleProps(pPr));
      }
    }

    for (final stNode in root.findAll('style')) {
      final styleId = stNode.attrs['styleId'];
      if (styleId == null || styleId.isEmpty) continue;
      final basedOn = stNode.firstChild('basedOn')?.attrs['val'];
      var own = const _RunStyle();
      final pPr = stNode.firstChild('pPr');
      if (pPr != null) {
        own = own.merge(_parseParagraphStyleProps(pPr));
      }
      final rPr = stNode.firstChild('rPr');
      if (rPr != null) {
        own = own.merge(_parseRunProperties(rPr));
      }
      rawStyles[styleId] = _RawStyleDef(basedOn: basedOn, own: own);
    }

    final resolved = <String, _RunStyle>{};
    _RunStyle resolve(String id, int depth) {
      if (resolved.containsKey(id)) return resolved[id]!;
      final def = rawStyles[id];
      if (def == null) return const _RunStyle();
      if (depth > 6 || def.basedOn == null || def.basedOn == id) {
        return resolved[id] = def.own;
      }
      return resolved[id] = resolve(def.basedOn!, depth + 1).merge(def.own);
    }

    for (final id in rawStyles.keys) {
      resolve(id, 0);
    }

    return _ParsedStyles(docDefault: docDefault, styles: resolved);
  }

  static _RunStyle _parseParagraphStyleProps(_XmlNode pPr) {
    final jc = _mapJc(pPr.firstChild('jc')?.attrs['val']);
    final spacing = pPr.firstChild('spacing');
    final beforePt = _twipsToPt(spacing?.attrs['before']);
    final afterPt = _twipsToPt(spacing?.attrs['after']);
    final ind = pPr.firstChild('ind');
    final leftPt = _twipsToPt(ind?.attrs['left'] ?? ind?.attrs['start']);
    return _RunStyle(
      align: jc,
      spaceBeforePt: beforePt,
      spaceAfterPt: afterPt,
      indentLeftPt: leftPt,
    );
  }

  static _RunStyle _parseRunProperties(_XmlNode rPr) {
    final rFonts = rPr.firstChild('rFonts');
    final fontFamily = rFonts?.attrs['ascii'] ??
        rFonts?.attrs['hAnsi'] ??
        rFonts?.attrs['cs'];
    final szRaw = double.tryParse(rPr.firstChild('sz')?.attrs['val'] ?? '');
    final fontSizePt = szRaw != null && szRaw > 0 ? szRaw / 2.0 : null;
    final colorHex = _normalizeHexColor(rPr.firstChild('color')?.attrs['val']);
    final highlightHex =
        _highlightToHex(rPr.firstChild('highlight')?.attrs['val']);

    bool? flagOf(String name) {
      final el = rPr.firstChild(name);
      if (el == null) return null;
      final val = el.attrs['val'];
      return val != '0' && val != 'false' && val != 'none';
    }

    final uEl = rPr.firstChild('u');
    final bool? underline = uEl == null
        ? null
        : (uEl.attrs['val'] != 'none' && uEl.attrs['val'] != 'false');

    final vertAlign = rPr.firstChild('vertAlign')?.attrs['val'];

    return _RunStyle(
      fontFamily: fontFamily,
      fontSizePt: fontSizePt,
      colorHex: colorHex,
      highlightHex: highlightHex,
      bold: flagOf('b'),
      italic: flagOf('i'),
      underline: underline,
      strike: flagOf('strike') ?? flagOf('dstrike'),
      allCaps: flagOf('caps'),
      vertAlign: vertAlign,
    );
  }

  static Map<String, bool> _parseNumberingXml(ArchiveFile? numFile) {
    final result = <String, bool>{};
    if (numFile == null) return result;
    final xml = utf8.decode(
      numFile.content as List<int>,
      allowMalformed: true,
    );
    final root = _XmlParser.parse(xml);
    final abstractIsOrdered = <String, bool>{};
    for (final absNode in root.findAll('abstractNum')) {
      final absId = absNode.attrs['abstractNumId'];
      if (absId == null) continue;
      final lvl0 = absNode.children.firstWhere(
        (c) => c.localName == 'lvl' && (c.attrs['ilvl'] ?? '0') == '0',
        orElse: () => const _XmlNode.empty(),
      );
      final fmt = lvl0.firstChild('numFmt')?.attrs['val'] ?? '';
      abstractIsOrdered[absId] = fmt != 'bullet' && fmt.isNotEmpty;
    }
    for (final numNode in root.findAll('num')) {
      final numId = numNode.attrs['numId'];
      final absId = numNode.firstChild('abstractNumId')?.attrs['val'];
      if (numId != null && absId != null) {
        result[numId] = abstractIsOrdered[absId] ?? false;
      }
    }
    return result;
  }

  static _SectionInfo _extractSectionInfo(_XmlNode bodyNode) {
    final sectPr =
        bodyNode.firstChild('sectPr') ?? bodyNode.firstDescendant('sectPr');
    if (sectPr == null) return const _SectionInfo();
    final pgSz = sectPr.firstChild('pgSz');
    final w = double.tryParse(pgSz?.attrs['w'] ?? '');
    final h = double.tryParse(pgSz?.attrs['h'] ?? '');
    final isLandscape =
        pgSz?.attrs['orient'] == 'landscape' || (w != null && h != null && w > h);
    final pgMar = sectPr.firstChild('pgMar');
    return _SectionInfo(
      isLandscape: isLandscape,
      marginTopPt:
          (_twipsToPt(pgMar?.attrs['top']) ?? 48.0).clamp(18.0, 96.0),
      marginBottomPt:
          (_twipsToPt(pgMar?.attrs['bottom']) ?? 48.0).clamp(18.0, 96.0),
      marginLeftPt:
          (_twipsToPt(pgMar?.attrs['left']) ?? 54.0).clamp(18.0, 96.0),
      marginRightPt:
          (_twipsToPt(pgMar?.attrs['right']) ?? 54.0).clamp(18.0, 96.0),
    );
  }

  static bool _areAllBordersNone(_XmlNode borders, List<String> sides) {
    var sawSide = false;
    for (final s in sides) {
      final b = borders.firstChild(s);
      if (b == null) continue;
      sawSide = true;
      final v = b.attrs['val'];
      if (v != 'none' && v != 'nil') return false;
    }
    return sawSide;
  }

  static String? _mapJc(String? val) {
    switch (val) {
      case 'center':
        return 'center';
      case 'right':
      case 'end':
        return 'right';
      case 'both':
      case 'distribute':
        return 'justify';
      case 'left':
      case 'start':
        return 'left';
      default:
        return null;
    }
  }

  static double? _twipsToPt(String? raw) {
    final v = double.tryParse(raw ?? '');
    if (v == null || v < 0) return null;
    return v / 20.0;
  }

  static String? _normalizeHexColor(String? raw) {
    if (raw == null || raw.isEmpty || raw == 'auto') return null;
    final clean = raw.startsWith('#') ? raw.substring(1) : raw;
    if (_nonHexRe.hasMatch(clean)) {
      return '#${clean.toUpperCase()}';
    }
    return null;
  }

  static String? _highlightToHex(String? val) {
    switch (val) {
      case 'yellow':
        return '#FEF08A';
      case 'green':
        return '#BBF7D0';
      case 'cyan':
        return '#A5F3FC';
      case 'magenta':
        return '#F5D0FE';
      case 'blue':
        return '#BFDBFE';
      case 'red':
        return '#FECACA';
      case 'darkYellow':
        return '#FDE047';
      case 'lightGray':
        return '#E5E7EB';
      default:
        return null;
    }
  }

  static String _cssFontStack(String fontName) {
    final escaped = fontName.replaceAll("'", '').replaceAll('"', '').trim();
    final lower = escaped.toLowerCase();
    if (lower == 'times new roman' ||
        lower.contains('cambria') ||
        lower == 'georgia' ||
        lower.contains('garamond') ||
        lower.contains('palatino')) {
      return "'$escaped', 'Liberation Serif', 'Noto Serif', Georgia, 'Times New Roman', serif";
    }
    if (lower.contains('consolas') ||
        lower.contains('courier') ||
        lower.contains('mono')) {
      return "'$escaped', 'DejaVu Sans Mono', monospace";
    }
    return "'$escaped', 'Liberation Sans', 'Noto Sans', Roboto, Arial, sans-serif";
  }

  static String _normalizeArchivePath(String raw) {
    return raw.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '').toLowerCase();
  }

  static String _resolveWordTarget(String target) {
    var clean = target.replaceAll('\\', '/');
    if (clean.startsWith('/')) {
      return _normalizeArchivePath(clean);
    }
    final parts = <String>['word'];
    for (final seg in clean.split('/')) {
      if (seg.isEmpty || seg == '.') continue;
      if (seg == '..') {
        if (parts.length > 1) parts.removeLast();
      } else {
        parts.add(seg);
      }
    }
    return parts.join('/').toLowerCase();
  }

  static String? _imageMimeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    if (lower.endsWith('.svg')) return 'image/svg+xml';
    return null;
  }

  static String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }
}

class _SectionInfo {
  const _SectionInfo({
    this.isLandscape = false,
    this.marginTopPt = 48.0,
    this.marginBottomPt = 48.0,
    this.marginLeftPt = 54.0,
    this.marginRightPt = 54.0,
  });

  final bool isLandscape;
  final double marginTopPt;
  final double marginBottomPt;
  final double marginLeftPt;
  final double marginRightPt;
}

class _ParsedStyles {
  const _ParsedStyles({required this.docDefault, required this.styles});

  final _RunStyle docDefault;
  final Map<String, _RunStyle> styles;
}

class _RawStyleDef {
  const _RawStyleDef({this.basedOn, required this.own});

  final String? basedOn;
  final _RunStyle own;
}

class _RunStyle {
  const _RunStyle({
    this.fontFamily,
    this.fontSizePt,
    this.colorHex,
    this.highlightHex,
    this.bold,
    this.italic,
    this.underline,
    this.strike,
    this.allCaps,
    this.vertAlign,
    this.align,
    this.spaceBeforePt,
    this.spaceAfterPt,
    this.indentLeftPt,
  });

  final String? fontFamily;
  final double? fontSizePt;
  final String? colorHex;
  final String? highlightHex;
  final bool? bold;
  final bool? italic;
  final bool? underline;
  final bool? strike;
  final bool? allCaps;
  final String? vertAlign;
  final String? align;
  final double? spaceBeforePt;
  final double? spaceAfterPt;
  final double? indentLeftPt;

  _RunStyle merge(_RunStyle other) {
    return _RunStyle(
      fontFamily: other.fontFamily ?? fontFamily,
      fontSizePt: other.fontSizePt ?? fontSizePt,
      colorHex: other.colorHex ?? colorHex,
      highlightHex: other.highlightHex ?? highlightHex,
      bold: other.bold ?? bold,
      italic: other.italic ?? italic,
      underline: other.underline ?? underline,
      strike: other.strike ?? strike,
      allCaps: other.allCaps ?? allCaps,
      vertAlign: other.vertAlign ?? vertAlign,
      align: other.align ?? align,
      spaceBeforePt: other.spaceBeforePt ?? spaceBeforePt,
      spaceAfterPt: other.spaceAfterPt ?? spaceAfterPt,
      indentLeftPt: other.indentLeftPt ?? indentLeftPt,
    );
  }
}

// =============================================================================
// MINIMAL ZERO-DEPENDENCY RECURSIVE XML PARSER FOR OOXML
// =============================================================================

class _XmlNode {
  const _XmlNode({
    required this.tag,
    required this.prefix,
    required this.localName,
    required this.attrs,
    required this.children,
    required this.text,
  });

  const _XmlNode.empty()
      : tag = '',
        prefix = '',
        localName = '',
        attrs = const {},
        children = const [],
        text = '';

  final String tag;
  final String prefix;
  final String localName;
  final Map<String, String> attrs;
  final List<_XmlNode> children;
  final String text;

  String get innerText {
    if (children.isEmpty) return text;
    final buf = StringBuffer(text);
    for (final c in children) {
      buf.write(c.innerText);
    }
    return buf.toString();
  }

  _XmlNode? firstChild(String local, {String? prefix}) {
    for (final c in children) {
      if (c.localName == local && (prefix == null || c.prefix == prefix)) {
        return c;
      }
    }
    return null;
  }

  _XmlNode? firstDescendant(String local) {
    for (final c in children) {
      if (c.localName == local) return c;
      final nested = c.firstDescendant(local);
      if (nested != null) return nested;
    }
    return null;
  }

  List<_XmlNode> findAll(String local) {
    final results = <_XmlNode>[];
    void walk(_XmlNode n) {
      for (final c in n.children) {
        if (c.localName == local) results.add(c);
        walk(c);
      }
    }
    walk(this);
    return results;
  }
}

class _XmlParser {
  _XmlParser(this._src);

  final String _src;
  int _pos = 0;

  static _XmlNode parse(String xml) {
    final cleaned = xml.startsWith('\uFEFF') ? xml.substring(1) : xml;
    final parser = _XmlParser(cleaned);
    final rootChildren = <_XmlNode>[];
    parser._parseChildren(rootChildren, stopTag: null);
    if (rootChildren.length == 1) return rootChildren.first;
    return _XmlNode(
      tag: 'root',
      prefix: '',
      localName: 'root',
      attrs: const {},
      children: rootChildren,
      text: '',
    );
  }

  void _parseChildren(List<_XmlNode> out, {required String? stopTag}) {
    final n = _src.length;
    while (_pos < n) {
      final lt = _src.indexOf('<', _pos);
      if (lt < 0) {
        final tail = _src.substring(_pos);
        if (tail.isNotEmpty) {
          out.add(_textNode(_decodeXmlEntities(tail)));
        }
        _pos = n;
        return;
      }
      if (lt > _pos) {
        final rawText = _src.substring(_pos, lt);
        if (rawText.isNotEmpty) {
          out.add(_textNode(_decodeXmlEntities(rawText)));
        }
      }
      _pos = lt;

      // Comment <!-- ... -->
      if (_src.startsWith('<!--', _pos)) {
        final end = _src.indexOf('-->', _pos + 4);
        _pos = end < 0 ? n : end + 3;
        continue;
      }

      // CDATA <![CDATA[ ... ]]>
      if (_src.startsWith('<![CDATA[', _pos)) {
        final end = _src.indexOf(']]>', _pos + 9);
        if (end < 0) {
          out.add(_textNode(_src.substring(_pos + 9)));
          _pos = n;
          return;
        }
        out.add(_textNode(_src.substring(_pos + 9, end)));
        _pos = end + 3;
        continue;
      }

      // Processing instruction <? ... ?> or <!DOCTYPE ... >
      if (_src.startsWith('<?', _pos)) {
        final end = _src.indexOf('?>', _pos + 2);
        _pos = end < 0 ? n : end + 2;
        continue;
      }
      if (_src.startsWith('<!', _pos)) {
        final end = _src.indexOf('>', _pos + 2);
        _pos = end < 0 ? n : end + 1;
        continue;
      }

      // Closing tag </...>
      if (_src.startsWith('</', _pos)) {
        final closeEnd = _src.indexOf('>', _pos + 2);
        final closeTag = (closeEnd < 0
                ? _src.substring(_pos + 2)
                : _src.substring(_pos + 2, closeEnd))
            .trim();
        _pos = closeEnd < 0 ? n : closeEnd + 1;
        if (stopTag != null && closeTag == stopTag) {
          return;
        }
        // Không khớp thẻ đóng -> bỏ qua an toàn
        continue;
      }

      // Opening tag <name attrs... > or <name attrs... />
      _pos++; // skip '<'
      final tagName = _readName();
      if (tagName.isEmpty) {
        _pos++;
        continue;
      }
      final attrs = _readAttributes();
      _skipWhitespace();
      bool selfClosing = false;
      if (_pos < n && _src[_pos] == '/') {
        selfClosing = true;
        _pos++;
      }
      if (_pos < n && _src[_pos] == '>') {
        _pos++;
      }

      final colon = tagName.indexOf(':');
      final prefix = colon >= 0 ? tagName.substring(0, colon) : '';
      final local = colon >= 0 ? tagName.substring(colon + 1) : tagName;

      final children = <_XmlNode>[];
      if (!selfClosing) {
        _parseChildren(children, stopTag: tagName);
      }

      // Gộp các text node trực tiếp nếu chỉ toàn chữ đơn giản
      String directText = '';
      if (children.isNotEmpty && children.every((c) => c.tag == '#text')) {
        directText = children.map((c) => c.text).join();
        children.clear();
      }

      out.add(
        _XmlNode(
          tag: tagName,
          prefix: prefix,
          localName: local,
          attrs: attrs,
          children: children,
          text: directText,
        ),
      );
    }
  }

  static _XmlNode _textNode(String text) => _XmlNode(
        tag: '#text',
        prefix: '',
        localName: '#text',
        attrs: const {},
        children: const [],
        text: text,
      );

  void _skipWhitespace() {
    while (_pos < _src.length) {
      final c = _src.codeUnitAt(_pos);
      if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) {
        _pos++;
      } else {
        break;
      }
    }
  }

  String _readName() {
    final start = _pos;
    while (_pos < _src.length) {
      final c = _src.codeUnitAt(_pos);
      if (c == 0x20 ||
          c == 0x09 ||
          c == 0x0A ||
          c == 0x0D ||
          c == 0x3D /* = */ ||
          c == 0x2F /* / */ ||
          c == 0x3E /* > */) {
        break;
      }
      _pos++;
    }
    return _src.substring(start, _pos);
  }

  Map<String, String> _readAttributes() {
    final attrs = <String, String>{};
    final n = _src.length;
    while (_pos < n) {
      _skipWhitespace();
      if (_pos >= n) break;
      final c = _src[_pos];
      if (c == '/' || c == '>') break;

      final attrFullName = _readName();
      if (attrFullName.isEmpty) {
        _pos++;
        continue;
      }
      _skipWhitespace();
      var value = '';
      if (_pos < n && _src[_pos] == '=') {
        _pos++;
        _skipWhitespace();
        if (_pos < n && (_src[_pos] == '"' || _src[_pos] == "'")) {
          final quote = _src[_pos];
          _pos++;
          final valStart = _pos;
          final valEnd = _src.indexOf(quote, valStart);
          if (valEnd < 0) {
            value = _decodeXmlEntities(_src.substring(valStart));
            _pos = n;
          } else {
            value = _decodeXmlEntities(_src.substring(valStart, valEnd));
            _pos = valEnd + 1;
          }
        }
      }
      final colon = attrFullName.indexOf(':');
      final localAttr =
          colon >= 0 ? attrFullName.substring(colon + 1) : attrFullName;
      attrs[localAttr] = value;
      // Giữ thêm tên đầy đủ cho thuộc tính đặc biệt như xml:space nếu cần
      if (colon >= 0) {
        attrs[attrFullName] = value;
      }
    }
    return attrs;
  }

  static String _decodeXmlEntities(String input) {
    if (!input.contains('&')) return input;
    var out = input
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
    return out.replaceAll('&amp;', '&');
  }
}
