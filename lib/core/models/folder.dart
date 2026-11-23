class Folder {
  final String id;
  final String name;
  final String? parentId;
  final int colorValue;
  final String iconName;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Folder({
    required this.id,
    required this.name,
    this.parentId,
    this.colorValue = 0xFF3B6B8C,
    this.iconName = 'folder',
    required this.createdAt,
    required this.updatedAt,
  });

  Folder copyWith({
    String? id,
    String? name,
    String? parentId,
    bool clearParentId = false,
    int? colorValue,
    String? iconName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Folder(
      id: id ?? this.id,
      name: name ?? this.name,
      parentId: clearParentId ? null : (parentId ?? this.parentId),
      colorValue: colorValue ?? this.colorValue,
      iconName: iconName ?? this.iconName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'parentId': parentId,
      'colorValue': colorValue,
      'iconName': iconName,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Folder.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return Folder(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Thư mục mới',
      parentId: json['parentId'] as String?,
      colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xFF3B6B8C,
      iconName: json['iconName'] as String? ?? 'folder',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? now
          : now,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String) ?? now
          : now,
    );
  }
}
