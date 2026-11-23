enum ToolType {
  fountainPen,
  ballpointPen,
  brushPen,
  highlighter,
  pencil,
  studyTape,
  laserPointer,
}

enum ShapeType {
  none,
  line,
  circle,
  rectangle,
  triangle,
  hexagon,
}

enum PaperTemplateType {
  blank,
  ruled,
  grid,
  dotted,
  cornell,
  hexagonal,
  sageRibbon,
  pastelGrid,
  vintageCream,
  twoColumnStudy,
}

enum PaperColorType {
  white,
  cream,
  dark,
}

T _enumByName<T extends Enum>(List<T> values, Object? raw, T fallback) {
  if (raw is String) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
  } else if (raw is int && raw >= 0 && raw < values.length) {
    return values[raw];
  }
  return fallback;
}

PaperTemplateType paperTemplateFromJson(Object? raw) {
  if (raw is String) {
    if (raw == 'titrationGraph') return PaperTemplateType.grid;
    if (raw == 'labReport') return PaperTemplateType.sageRibbon;
  }
  return _enumByName(PaperTemplateType.values, raw, PaperTemplateType.sageRibbon);
}

PaperColorType paperColorFromJson(Object? raw) =>
    _enumByName(PaperColorType.values, raw, PaperColorType.cream);

ToolType toolTypeFromJson(Object? raw) =>
    _enumByName(ToolType.values, raw, ToolType.fountainPen);

class StrokePoint {
  final double x;
  final double y;
  final double pressure;
  final double tilt;
  final int timestamp;

  const StrokePoint({
    required this.x,
    required this.y,
    this.pressure = 0.5,
    this.tilt = 0.0,
    this.timestamp = 0,
  });

  StrokePoint copyWith({
    double? x,
    double? y,
    double? pressure,
    double? tilt,
    int? timestamp,
  }) {
    return StrokePoint(
      x: x ?? this.x,
      y: y ?? this.y,
      pressure: pressure ?? this.pressure,
      tilt: tilt ?? this.tilt,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'x': x,
      'y': y,
      'pressure': pressure,
      'tilt': tilt,
      'timestamp': timestamp,
    };
  }

  factory StrokePoint.fromJson(Map<String, dynamic> json) {
    return StrokePoint(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      pressure: (json['pressure'] as num?)?.toDouble() ?? 0.5,
      tilt: (json['tilt'] as num?)?.toDouble() ?? 0.0,
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
    );
  }
}

class Stroke {
  final String id;
  final ToolType toolType;
  final int colorValue;
  final double width;
  final List<StrokePoint> points;
  final bool isSmoothed;
  final ShapeType shapeType;
  final String? audioId;
  final int? audioTimeMs;

  const Stroke({
    required this.id,
    required this.toolType,
    required this.colorValue,
    required this.width,
    required this.points,
    this.isSmoothed = false,
    this.shapeType = ShapeType.none,
    this.audioId,
    this.audioTimeMs,
  });

  Stroke copyWith({
    String? id,
    ToolType? toolType,
    int? colorValue,
    double? width,
    List<StrokePoint>? points,
    bool? isSmoothed,
    ShapeType? shapeType,
    String? audioId,
    int? audioTimeMs,
  }) {
    return Stroke(
      id: id ?? this.id,
      toolType: toolType ?? this.toolType,
      colorValue: colorValue ?? this.colorValue,
      width: width ?? this.width,
      points: points ?? this.points,
      isSmoothed: isSmoothed ?? this.isSmoothed,
      shapeType: shapeType ?? this.shapeType,
      audioId: audioId ?? this.audioId,
      audioTimeMs: audioTimeMs ?? this.audioTimeMs,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'toolType': toolType.name,
      'colorValue': colorValue,
      'width': width,
      'points': points.map((p) => p.toJson()).toList(),
      'isSmoothed': isSmoothed,
      'shapeType': shapeType.name,
      if (audioId != null) 'audioId': audioId,
      if (audioTimeMs != null) 'audioTimeMs': audioTimeMs,
    };
  }

  factory Stroke.fromJson(Map<String, dynamic> json) {
    final rawPoints = json['points'] as List<dynamic>? ?? const [];
    return Stroke(
      id: json['id'] as String,
      toolType: toolTypeFromJson(json['toolType']),
      colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xFF1F2937,
      width: (json['width'] as num?)?.toDouble() ?? 2.5,
      points: rawPoints
          .map((e) => StrokePoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      isSmoothed: json['isSmoothed'] as bool? ?? false,
      shapeType: _enumByName(
        ShapeType.values,
        json['shapeType'],
        ShapeType.none,
      ),
      audioId: json['audioId'] as String?,
      audioTimeMs: (json['audioTimeMs'] as num?)?.toInt(),
    );
  }
}

/// Bản ghi âm bài giảng gắn với từng trang (Audio Note Replay).
class AudioRecording {
  final String id;
  final String filePath;
  final int durationMs;
  final DateTime createdAt;

  const AudioRecording({
    required this.id,
    required this.filePath,
    this.durationMs = 0,
    required this.createdAt,
  });

  AudioRecording copyWith({
    String? id,
    String? filePath,
    int? durationMs,
    DateTime? createdAt,
  }) {
    return AudioRecording(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      durationMs: durationMs ?? this.durationMs,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'filePath': filePath,
      'durationMs': durationMs,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory AudioRecording.fromJson(Map<String, dynamic> json) {
    return AudioRecording(
      id: json['id'] as String,
      filePath: json['filePath'] as String? ?? '',
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

/// Giấy nhớ dán (Sticky Note) kiểu GoodNotes 6 có thể kéo thả, đổi màu pastel và thu gọn.
class StickyNoteElement {
  final String id;
  final double x;
  final double y;
  final double width;
  final double height;
  final String text;
  final int colorValue;
  final bool isCollapsed;
  final DateTime updatedAt;

  StickyNoteElement({
    required this.id,
    required this.x,
    required this.y,
    this.width = 210.0,
    this.height = 190.0,
    this.text = '',
    this.colorValue = 0xFFFEF08A,
    this.isCollapsed = false,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  StickyNoteElement copyWith({
    String? id,
    double? x,
    double? y,
    double? width,
    double? height,
    String? text,
    int? colorValue,
    bool? isCollapsed,
    DateTime? updatedAt,
  }) {
    return StickyNoteElement(
      id: id ?? this.id,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      text: text ?? this.text,
      colorValue: colorValue ?? this.colorValue,
      isCollapsed: isCollapsed ?? this.isCollapsed,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'text': text,
      'colorValue': colorValue,
      'isCollapsed': isCollapsed,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory StickyNoteElement.fromJson(Map<String, dynamic> json) {
    return StickyNoteElement(
      id: json['id'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num?)?.toDouble() ?? 210.0,
      height: (json['height'] as num?)?.toDouble() ?? 190.0,
      text: json['text'] as String? ?? '',
      colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xFFFEF08A,
      isCollapsed: json['isCollapsed'] as bool? ?? false,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class TextElement {
  final String id;
  final double x;
  final double y;
  final double width;
  final double height;
  final String text;
  final double fontSize;
  final int colorValue;
  final bool isBold;
  final bool isItalic;

  const TextElement({
    required this.id,
    required this.x,
    required this.y,
    this.width = 220.0,
    this.height = 60.0,
    required this.text,
    this.fontSize = 18.0,
    this.colorValue = 0xFF1F2937,
    this.isBold = false,
    this.isItalic = false,
  });

  TextElement copyWith({
    String? id,
    double? x,
    double? y,
    double? width,
    double? height,
    String? text,
    double? fontSize,
    int? colorValue,
    bool? isBold,
    bool? isItalic,
  }) {
    return TextElement(
      id: id ?? this.id,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      text: text ?? this.text,
      fontSize: fontSize ?? this.fontSize,
      colorValue: colorValue ?? this.colorValue,
      isBold: isBold ?? this.isBold,
      isItalic: isItalic ?? this.isItalic,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'text': text,
      'fontSize': fontSize,
      'colorValue': colorValue,
      'isBold': isBold,
      'isItalic': isItalic,
    };
  }

  factory TextElement.fromJson(Map<String, dynamic> json) {
    return TextElement(
      id: json['id'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num?)?.toDouble() ?? 220.0,
      height: (json['height'] as num?)?.toDouble() ?? 60.0,
      text: json['text'] as String? ?? '',
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 18.0,
      colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xFF1F2937,
      isBold: json['isBold'] as bool? ?? false,
      isItalic: json['isItalic'] as bool? ?? false,
    );
  }
}

/// Hình ảnh độ phân giải gốc với vùng cắt không phá hủy (normalized 0..1)
/// và đường cắt tự do tùy chọn (`freehandClipPath`).
class ImageElement {
  final String id;
  final double x;
  final double y;
  final double width;
  final double height;
  final double rotation;
  final String filePath;
  final double cropLeft;
  final double cropTop;
  final double cropRight;
  final double cropBottom;
  final List<StrokePoint> freehandClipPath;

  const ImageElement({
    required this.id,
    required this.x,
    required this.y,
    this.width = 240.0,
    this.height = 180.0,
    this.rotation = 0.0,
    required this.filePath,
    this.cropLeft = 0.0,
    this.cropTop = 0.0,
    this.cropRight = 1.0,
    this.cropBottom = 1.0,
    this.freehandClipPath = const [],
  });

  ImageElement copyWith({
    String? id,
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotation,
    String? filePath,
    double? cropLeft,
    double? cropTop,
    double? cropRight,
    double? cropBottom,
    List<StrokePoint>? freehandClipPath,
  }) {
    return ImageElement(
      id: id ?? this.id,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      rotation: rotation ?? this.rotation,
      filePath: filePath ?? this.filePath,
      cropLeft: cropLeft ?? this.cropLeft,
      cropTop: cropTop ?? this.cropTop,
      cropRight: cropRight ?? this.cropRight,
      cropBottom: cropBottom ?? this.cropBottom,
      freehandClipPath: freehandClipPath ?? this.freehandClipPath,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'rotation': rotation,
      'filePath': filePath,
      'cropLeft': cropLeft,
      'cropTop': cropTop,
      'cropRight': cropRight,
      'cropBottom': cropBottom,
      'freehandClipPath': freehandClipPath.map((p) => p.toJson()).toList(),
    };
  }

  factory ImageElement.fromJson(Map<String, dynamic> json) {
    final rawClip = json['freehandClipPath'] as List<dynamic>? ?? const [];
    return ImageElement(
      id: json['id'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num?)?.toDouble() ?? 240.0,
      height: (json['height'] as num?)?.toDouble() ?? 180.0,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      filePath: json['filePath'] as String? ?? '',
      cropLeft: ((json['cropLeft'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 0.995),
      cropTop: ((json['cropTop'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 0.995),
      cropRight:
          ((json['cropRight'] as num?)?.toDouble() ?? 1.0).clamp(0.005, 1.0),
      cropBottom:
          ((json['cropBottom'] as num?)?.toDouble() ?? 1.0).clamp(0.005, 1.0),
      freehandClipPath: rawClip
          .map((e) => StrokePoint.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Thẻ tệp tin đính kèm trên trang ghi chú (PDF, DOC, PPT hoặc tệp bất kỳ).
class AttachmentElement {
  final String id;
  final double x;
  final double y;
  final double width;
  final double height;
  final String fileName;
  final String filePath;
  final String fileExtension;
  final int fileSizeBytes;

  const AttachmentElement({
    required this.id,
    required this.x,
    required this.y,
    this.width = 230.0,
    this.height = 68.0,
    required this.fileName,
    required this.filePath,
    required this.fileExtension,
    this.fileSizeBytes = 0,
  });

  AttachmentElement copyWith({
    String? id,
    double? x,
    double? y,
    double? width,
    double? height,
    String? fileName,
    String? filePath,
    String? fileExtension,
    int? fileSizeBytes,
  }) {
    return AttachmentElement(
      id: id ?? this.id,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      fileExtension: fileExtension ?? this.fileExtension,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'fileName': fileName,
      'filePath': filePath,
      'fileExtension': fileExtension,
      'fileSizeBytes': fileSizeBytes,
    };
  }

  factory AttachmentElement.fromJson(Map<String, dynamic> json) {
    return AttachmentElement(
      id: json['id'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num?)?.toDouble() ?? 230.0,
      height: (json['height'] as num?)?.toDouble() ?? 68.0,
      fileName: json['fileName'] as String? ?? 'Tệp đính kèm',
      filePath: json['filePath'] as String? ?? '',
      fileExtension: json['fileExtension'] as String? ?? '',
      fileSizeBytes: (json['fileSizeBytes'] as num?)?.toInt() ?? 0,
    );
  }
}

class StencilElement {
  final String id;
  final String stencilId;
  final double x;
  final double y;
  final double width;
  final double height;
  final double rotation;
  final int colorValue;
  final double strokeWidth;

  const StencilElement({
    required this.id,
    required this.stencilId,
    required this.x,
    required this.y,
    this.width = 120.0,
    this.height = 120.0,
    this.rotation = 0.0,
    this.colorValue = 0xFF1F2937,
    this.strokeWidth = 2.0,
  });

  StencilElement copyWith({
    String? id,
    String? stencilId,
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotation,
    int? colorValue,
    double? strokeWidth,
  }) {
    return StencilElement(
      id: id ?? this.id,
      stencilId: stencilId ?? this.stencilId,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      rotation: rotation ?? this.rotation,
      colorValue: colorValue ?? this.colorValue,
      strokeWidth: strokeWidth ?? this.strokeWidth,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'stencilId': stencilId,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'rotation': rotation,
      'colorValue': colorValue,
      'strokeWidth': strokeWidth,
    };
  }

  factory StencilElement.fromJson(Map<String, dynamic> json) {
    return StencilElement(
      id: json['id'] as String,
      stencilId: json['stencilId'] as String? ?? 'benzene',
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num?)?.toDouble() ?? 120.0,
      height: (json['height'] as num?)?.toDouble() ?? 120.0,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xFF1F2937,
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 2.0,
    );
  }
}

/// Băng che học tập (Study Tape) để che công thức / đáp án, chạm để lật xem.
class TapeElement {
  final String id;
  final double x;
  final double y;
  final double width;
  final double height;
  final int colorValue;
  final bool isRevealed;

  const TapeElement({
    required this.id,
    required this.x,
    required this.y,
    this.width = 180.0,
    this.height = 44.0,
    this.colorValue = 0xFF3B82F6,
    this.isRevealed = false,
  });

  TapeElement copyWith({
    String? id,
    double? x,
    double? y,
    double? width,
    double? height,
    int? colorValue,
    bool? isRevealed,
  }) {
    return TapeElement(
      id: id ?? this.id,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      colorValue: colorValue ?? this.colorValue,
      isRevealed: isRevealed ?? this.isRevealed,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'colorValue': colorValue,
      'isRevealed': isRevealed,
    };
  }

  factory TapeElement.fromJson(Map<String, dynamic> json) {
    return TapeElement(
      id: json['id'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num?)?.toDouble() ?? 180.0,
      height: (json['height'] as num?)?.toDouble() ?? 44.0,
      colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xFF3B82F6,
      isRevealed: json['isRevealed'] as bool? ?? false,
    );
  }
}

/// Bút ưa thích gắn trên thanh nổi bên trái (chỉ chứa bút do người dùng tự ghim bằng nút Sao).
class PenPreset {
  final String id;
  final ToolType toolType;
  final int colorValue;
  final double width;
  final String label;
  final double opacity;
  final double pressureSensitivity;

  const PenPreset({
    required this.id,
    required this.toolType,
    required this.colorValue,
    required this.width,
    required this.label,
    this.opacity = 1.0,
    this.pressureSensitivity = 0.75,
  });

  PenPreset copyWith({
    String? id,
    ToolType? toolType,
    int? colorValue,
    double? width,
    String? label,
    double? opacity,
    double? pressureSensitivity,
  }) {
    return PenPreset(
      id: id ?? this.id,
      toolType: toolType ?? this.toolType,
      colorValue: colorValue ?? this.colorValue,
      width: width ?? this.width,
      label: label ?? this.label,
      opacity: opacity ?? this.opacity,
      pressureSensitivity: pressureSensitivity ?? this.pressureSensitivity,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'toolType': toolType.name,
      'colorValue': colorValue,
      'width': width,
      'label': label,
      'opacity': opacity,
      'pressureSensitivity': pressureSensitivity,
    };
  }

  factory PenPreset.fromJson(Map<String, dynamic> json) {
    return PenPreset(
      id: json['id'] as String,
      toolType: toolTypeFromJson(json['toolType']),
      colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xFF111827,
      width: (json['width'] as num?)?.toDouble() ?? 2.4,
      label: json['label'] as String? ?? 'Bút máy',
      opacity: ((json['opacity'] as num?)?.toDouble() ?? 1.0).clamp(0.05, 1.0),
      pressureSensitivity:
          ((json['pressureSensitivity'] as num?)?.toDouble() ?? 0.75)
              .clamp(0.0, 1.0),
    );
  }
}
