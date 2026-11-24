import 'drawing_elements.dart';
import 'note_page.dart';

enum SyncStatus {
  localOnly,
  synced,
  pendingUpload,
  syncing,
  error,
}

SyncStatus _syncStatusFromJson(Object? raw) {
  if (raw is String) {
    for (final value in SyncStatus.values) {
      if (value.name == raw) return value;
    }
  } else if (raw is int && raw >= 0 && raw < SyncStatus.values.length) {
    return SyncStatus.values[raw];
  }
  return SyncStatus.localOnly;
}

class Notebook {
  final String id;
  final String title;
  final String? folderId;
  final String coverStyle;
  final int coverColorValue;
  final PaperTemplateType defaultTemplate;
  final PaperColorType defaultPaperColor;
  final bool defaultOrientationLandscape;
  final List<NotePage> pages;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;
  final String? driveFileId;
  final String? drivePdfFileId;
  final bool isFavorite;
  final bool isLocked;
  final String? pinCode;
  final bool isTrashed;
  final DateTime? trashedAt;
  final bool isWhiteboard;
  final String? customCoverImagePath;
  final bool useFirstPageAsCover;

  const Notebook({
    required this.id,
    required this.title,
    this.folderId,
    this.coverStyle = 'classic',
    this.coverColorValue = 0xFF2B4C7E,
    this.defaultTemplate = PaperTemplateType.ruled,
    this.defaultPaperColor = PaperColorType.cream,
    this.defaultOrientationLandscape = false,
    this.pages = const [],
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = SyncStatus.localOnly,
    this.driveFileId,
    this.drivePdfFileId,
    this.isFavorite = false,
    this.isLocked = false,
    this.pinCode,
    this.isTrashed = false,
    this.trashedAt,
    this.isWhiteboard = false,
    this.customCoverImagePath,
    this.useFirstPageAsCover = false,
  });

  Notebook copyWith({
    String? id,
    String? title,
    String? folderId,
    bool clearFolderId = false,
    String? coverStyle,
    int? coverColorValue,
    PaperTemplateType? defaultTemplate,
    PaperColorType? defaultPaperColor,
    bool? defaultOrientationLandscape,
    List<NotePage>? pages,
    DateTime? createdAt,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
    String? driveFileId,
    bool clearDriveFileId = false,
    String? drivePdfFileId,
    bool clearDrivePdfFileId = false,
    bool? isFavorite,
    bool? isLocked,
    String? pinCode,
    bool clearPinCode = false,
    bool? isTrashed,
    DateTime? trashedAt,
    bool clearTrashedAt = false,
    bool? isWhiteboard,
    String? customCoverImagePath,
    bool clearCustomCoverImagePath = false,
    bool? useFirstPageAsCover,
  }) {
    return Notebook(
      id: id ?? this.id,
      title: title ?? this.title,
      folderId: clearFolderId ? null : (folderId ?? this.folderId),
      coverStyle: coverStyle ?? this.coverStyle,
      coverColorValue: coverColorValue ?? this.coverColorValue,
      defaultTemplate: defaultTemplate ?? this.defaultTemplate,
      defaultPaperColor: defaultPaperColor ?? this.defaultPaperColor,
      defaultOrientationLandscape:
          defaultOrientationLandscape ?? this.defaultOrientationLandscape,
      pages: pages ?? this.pages,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      driveFileId: clearDriveFileId ? null : (driveFileId ?? this.driveFileId),
      drivePdfFileId: clearDrivePdfFileId
          ? null
          : (drivePdfFileId ?? this.drivePdfFileId),
      isFavorite: isFavorite ?? this.isFavorite,
      isLocked: isLocked ?? this.isLocked,
      pinCode: clearPinCode ? null : (pinCode ?? this.pinCode),
      isTrashed: isTrashed ?? this.isTrashed,
      trashedAt: clearTrashedAt ? null : (trashedAt ?? this.trashedAt),
      isWhiteboard: isWhiteboard ?? this.isWhiteboard,
      customCoverImagePath: clearCustomCoverImagePath
          ? null
          : (customCoverImagePath ?? this.customCoverImagePath),
      useFirstPageAsCover: useFirstPageAsCover ?? this.useFirstPageAsCover,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'folderId': folderId,
      'coverStyle': coverStyle,
      'coverColorValue': coverColorValue,
      'defaultTemplate': defaultTemplate.name,
      'defaultPaperColor': defaultPaperColor.name,
      'defaultOrientationLandscape': defaultOrientationLandscape,
      'pages': pages.map((p) => p.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'syncStatus': syncStatus.name,
      'driveFileId': driveFileId,
      'drivePdfFileId': drivePdfFileId,
      'isFavorite': isFavorite,
      'isLocked': isLocked,
      'pinCode': pinCode,
      'isTrashed': isTrashed,
      'trashedAt': trashedAt?.toIso8601String(),
      'isWhiteboard': isWhiteboard,
      'customCoverImagePath': customCoverImagePath,
      'useFirstPageAsCover': useFirstPageAsCover,
    };
  }

  factory Notebook.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final rawPages = json['pages'] as List<dynamic>? ?? const [];
    return Notebook(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Sổ tay mới',
      folderId: json['folderId'] as String?,
      coverStyle: json['coverStyle'] as String? ?? 'classic',
      coverColorValue: (json['coverColorValue'] as num?)?.toInt() ?? 0xFF2B4C7E,
      defaultTemplate: paperTemplateFromJson(json['defaultTemplate']),
      defaultPaperColor: paperColorFromJson(json['defaultPaperColor']),
      defaultOrientationLandscape:
          json['defaultOrientationLandscape'] as bool? ?? false,
      pages: rawPages
          .map((e) => NotePage.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? now
          : now,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String) ?? now
          : now,
      syncStatus: _syncStatusFromJson(json['syncStatus']),
      driveFileId: json['driveFileId'] as String?,
      drivePdfFileId: json['drivePdfFileId'] as String?,
      isFavorite: json['isFavorite'] as bool? ?? false,
      isLocked: json['isLocked'] as bool? ?? false,
      pinCode: json['pinCode'] as String?,
      isTrashed: json['isTrashed'] as bool? ?? false,
      trashedAt: json['trashedAt'] != null
          ? DateTime.tryParse(json['trashedAt'] as String)
          : null,
      isWhiteboard: json['isWhiteboard'] as bool? ?? false,
      customCoverImagePath: json['customCoverImagePath'] as String?,
      useFirstPageAsCover: json['useFirstPageAsCover'] as bool? ?? false,
    );
  }
}
