import 'dart:io';

import 'package:uuid/uuid.dart';

/// The type classification of a document within DocuScan Pro.
enum DocumentType {
  scan,
  pdf,
  image,
  converted;

  String toJson() => name;

  static DocumentType fromJson(String value) {
    return DocumentType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => DocumentType.pdf,
    );
  }
}

/// Core document model representing a scanned, imported, or converted document.
class DocumentModel {
  final String id;
  final String title;
  final String filePath;
  final String? thumbnailPath;
  final DocumentType type;
  final int pageCount;
  final int fileSize;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final List<String> tags;
  final bool isPasswordProtected;
  final String? ocrText;
  final String? parentFolderId;

  const DocumentModel({
    required this.id,
    required this.title,
    required this.filePath,
    this.thumbnailPath,
    required this.type,
    required this.pageCount,
    required this.fileSize,
    required this.createdAt,
    required this.modifiedAt,
    this.tags = const [],
    this.isPasswordProtected = false,
    this.ocrText,
    this.parentFolderId,
  });

  /// Creates a [DocumentModel] from a JSON map (e.g. decoded from storage).
  factory DocumentModel.fromJson(Map<String, dynamic> json) {
    return DocumentModel(
      id: json['id'] as String,
      title: json['title'] as String,
      filePath: json['filePath'] as String,
      thumbnailPath: json['thumbnailPath'] as String?,
      type: DocumentType.fromJson(json['type'] as String),
      pageCount: json['pageCount'] as int,
      fileSize: json['fileSize'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
      modifiedAt: DateTime.parse(json['modifiedAt'] as String),
      tags: (json['tags'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      isPasswordProtected: json['isPasswordProtected'] as bool? ?? false,
      ocrText: json['ocrText'] as String?,
      parentFolderId: json['parentFolderId'] as String?,
    );
  }

  /// Serialises this document to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'filePath': filePath,
      'thumbnailPath': thumbnailPath,
      'type': type.toJson(),
      'pageCount': pageCount,
      'fileSize': fileSize,
      'createdAt': createdAt.toIso8601String(),
      'modifiedAt': modifiedAt.toIso8601String(),
      'tags': tags,
      'isPasswordProtected': isPasswordProtected,
      'ocrText': ocrText,
      'parentFolderId': parentFolderId,
    };
  }

  /// Returns a copy of this model with the given fields replaced.
  DocumentModel copyWith({
    String? id,
    String? title,
    String? filePath,
    String? thumbnailPath,
    bool clearThumbnailPath = false,
    DocumentType? type,
    int? pageCount,
    int? fileSize,
    DateTime? createdAt,
    DateTime? modifiedAt,
    List<String>? tags,
    bool? isPasswordProtected,
    String? ocrText,
    bool clearOcrText = false,
    String? parentFolderId,
    bool clearParentFolderId = false,
  }) {
    return DocumentModel(
      id: id ?? this.id,
      title: title ?? this.title,
      filePath: filePath ?? this.filePath,
      thumbnailPath:
          clearThumbnailPath ? null : (thumbnailPath ?? this.thumbnailPath),
      type: type ?? this.type,
      pageCount: pageCount ?? this.pageCount,
      fileSize: fileSize ?? this.fileSize,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      tags: tags ?? List.unmodifiable(this.tags),
      isPasswordProtected: isPasswordProtected ?? this.isPasswordProtected,
      ocrText: clearOcrText ? null : (ocrText ?? this.ocrText),
      parentFolderId: clearParentFolderId
          ? null
          : (parentFolderId ?? this.parentFolderId),
    );
  }

  /// Creates a new [DocumentModel] by inspecting a [File] on disk.
  ///
  /// The [title] defaults to the file name (without extension) if not provided.
  /// The [type] is inferred from the file extension when not specified.
  static Future<DocumentModel> createFromFile(
    File file, {
    String? title,
    DocumentType? type,
    int pageCount = 1,
    String? parentFolderId,
  }) async {
    final stat = await file.stat();
    final fileName = file.uri.pathSegments.last;
    final extension = fileName.contains('.')
        ? fileName.substring(fileName.lastIndexOf('.') + 1).toLowerCase()
        : '';

    final inferredType = type ?? _inferType(extension);
    final inferredTitle =
        title ?? fileName.replaceAll(RegExp(r'\.[^.]+$'), '');

    final now = DateTime.now();

    return DocumentModel(
      id: const Uuid().v4(),
      title: inferredTitle,
      filePath: file.path,
      type: inferredType,
      pageCount: pageCount,
      fileSize: stat.size,
      createdAt: now,
      modifiedAt: now,
      parentFolderId: parentFolderId,
    );
  }

  /// Infers a [DocumentType] from a file extension string.
  static DocumentType _inferType(String extension) {
    switch (extension) {
      case 'pdf':
        return DocumentType.pdf;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'webp':
      case 'heic':
        return DocumentType.image;
      case 'docx':
      case 'xlsx':
      case 'pptx':
      case 'csv':
      case 'txt':
        return DocumentType.converted;
      default:
        return DocumentType.scan;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentModel && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'DocumentModel(id: $id, title: $title, type: ${type.name}, pages: $pageCount)';
}
