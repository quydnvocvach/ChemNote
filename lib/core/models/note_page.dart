import 'drawing_elements.dart';

class NotePage {
  final String id;
  final int index;
  final PaperTemplateType templateType;
  final PaperColorType paperColor;
  final bool isLandscape;
  final List<Stroke> strokes;
  final List<TextElement> textElements;
  final List<ImageElement> imageElements;
  final List<StencilElement> stencilElements;
  final List<TapeElement> tapeElements;
  final List<AttachmentElement> attachmentElements;
  final String? pdfBackgroundPath;
  final int? pdfPageNumber;
  final bool isBookmarked;
  final String? title;
  final DateTime updatedAt;

  const NotePage({
    required this.id,
    required this.index,
    this.templateType = PaperTemplateType.sageRibbon,
    this.paperColor = PaperColorType.cream,
    this.isLandscape = false,
    this.strokes = const [],
    this.textElements = const [],
    this.imageElements = const [],
    this.stencilElements = const [],
    this.tapeElements = const [],
    this.attachmentElements = const [],
    this.pdfBackgroundPath,
    this.pdfPageNumber,
    this.isBookmarked = false,
    this.title,
    required this.updatedAt,
  });

  NotePage copyWith({
    String? id,
    int? index,
    PaperTemplateType? templateType,
    PaperColorType? paperColor,
    bool? isLandscape,
    List<Stroke>? strokes,
    List<TextElement>? textElements,
    List<ImageElement>? imageElements,
    List<StencilElement>? stencilElements,
    List<TapeElement>? tapeElements,
    List<AttachmentElement>? attachmentElements,
    String? pdfBackgroundPath,
    bool clearPdfBackground = false,
    int? pdfPageNumber,
    bool? isBookmarked,
    String? title,
    bool clearTitle = false,
    DateTime? updatedAt,
  }) {
    return NotePage(
      id: id ?? this.id,
      index: index ?? this.index,
      templateType: templateType ?? this.templateType,
      paperColor: paperColor ?? this.paperColor,
      isLandscape: isLandscape ?? this.isLandscape,
      strokes: strokes ?? this.strokes,
      textElements: textElements ?? this.textElements,
      imageElements: imageElements ?? this.imageElements,
      stencilElements: stencilElements ?? this.stencilElements,
      tapeElements: tapeElements ?? this.tapeElements,
      attachmentElements: attachmentElements ?? this.attachmentElements,
      pdfBackgroundPath: clearPdfBackground
          ? null
          : (pdfBackgroundPath ?? this.pdfBackgroundPath),
      pdfPageNumber:
          clearPdfBackground ? null : (pdfPageNumber ?? this.pdfPageNumber),
      isBookmarked: isBookmarked ?? this.isBookmarked,
      title: clearTitle ? null : (title ?? this.title),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'index': index,
      'templateType': templateType.name,
      'paperColor': paperColor.name,
      'isLandscape': isLandscape,
      'strokes': strokes.map((s) => s.toJson()).toList(),
      'textElements': textElements.map((t) => t.toJson()).toList(),
      'imageElements': imageElements.map((i) => i.toJson()).toList(),
      'stencilElements': stencilElements.map((s) => s.toJson()).toList(),
      'tapeElements': tapeElements.map((t) => t.toJson()).toList(),
      'attachmentElements': attachmentElements.map((a) => a.toJson()).toList(),
      'pdfBackgroundPath': pdfBackgroundPath,
      'pdfPageNumber': pdfPageNumber,
      'isBookmarked': isBookmarked,
      'title': title,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory NotePage.fromJson(Map<String, dynamic> json) {
    final rawStrokes = json['strokes'] as List<dynamic>? ?? const [];
    final rawTexts = json['textElements'] as List<dynamic>? ?? const [];
    final rawImages = json['imageElements'] as List<dynamic>? ?? const [];
    final rawStencils = json['stencilElements'] as List<dynamic>? ?? const [];
    final rawTapes = json['tapeElements'] as List<dynamic>? ?? const [];
    final rawAttachments =
        json['attachmentElements'] as List<dynamic>? ?? const [];

    return NotePage(
      id: json['id'] as String,
      index: (json['index'] as num?)?.toInt() ?? 0,
      templateType: paperTemplateFromJson(json['templateType']),
      paperColor: paperColorFromJson(json['paperColor']),
      isLandscape: json['isLandscape'] as bool? ?? false,
      strokes: rawStrokes
          .map((e) => Stroke.fromJson(e as Map<String, dynamic>))
          .toList(),
      textElements: rawTexts
          .map((e) => TextElement.fromJson(e as Map<String, dynamic>))
          .toList(),
      imageElements: rawImages
          .map((e) => ImageElement.fromJson(e as Map<String, dynamic>))
          .toList(),
      stencilElements: rawStencils
          .map((e) => StencilElement.fromJson(e as Map<String, dynamic>))
          .toList(),
      tapeElements: rawTapes
          .map((e) => TapeElement.fromJson(e as Map<String, dynamic>))
          .toList(),
      attachmentElements: rawAttachments
          .map((e) => AttachmentElement.fromJson(e as Map<String, dynamic>))
          .toList(),
      pdfBackgroundPath: json['pdfBackgroundPath'] as String?,
      pdfPageNumber: (json['pdfPageNumber'] as num?)?.toInt(),
      isBookmarked: json['isBookmarked'] as bool? ?? false,
      title: json['title'] as String?,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
