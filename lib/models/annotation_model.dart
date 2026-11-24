import 'package:uuid/uuid.dart';

/// The visual type of an annotation placed on a document page.
enum AnnotationType {
  highlight,
  underline,
  strikethrough,
  freehand,
  textNote,
  stickyNote;

  String toJson() => name;

  static AnnotationType fromJson(String value) {
    return AnnotationType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => AnnotationType.highlight,
    );
  }
}

/// Represents a single annotation on a specific page of a document.
class AnnotationModel {
  /// Unique identifier for this annotation.
  final String id;

  /// Zero-based page index the annotation belongs to.
  final int pageIndex;

  /// The kind of annotation (highlight, freehand, etc.).
  final AnnotationType type;

  /// The ARGB colour value stored as an integer (e.g. `0xFFFF0000` for red).
  final int color;

  /// Ordered list of points for freehand annotations.
  /// Each map contains `x` and `y` keys with normalised coordinates (0.0-1.0).
  final List<Map<String, double>> points;

  /// Bounding rectangle for the annotation.
  /// Keys: `x`, `y`, `width`, `height` (normalised 0.0-1.0 relative to page).
  final Map<String, double> rect;

  /// Optional text content for [AnnotationType.textNote] and
  /// [AnnotationType.stickyNote] annotations.
  final String? text;

  /// Stroke width for [AnnotationType.freehand], as a fraction of the page
  /// width, so a stroke keeps its look at any zoom and in the saved PDF.
  final double strokeWidth;

  /// Timestamp when the annotation was created.
  final DateTime createdAt;

  const AnnotationModel({
    required this.id,
    required this.pageIndex,
    required this.type,
    required this.color,
    this.points = const [],
    this.rect = const {},
    this.text,
    this.strokeWidth = defaultStrokeWidth,
    required this.createdAt,
  });

  static const double defaultStrokeWidth = 0.008;

  /// Convenience factory that auto-generates an [id] and [createdAt] timestamp.
  factory AnnotationModel.create({
    required int pageIndex,
    required AnnotationType type,
    required int color,
    List<Map<String, double>> points = const [],
    Map<String, double> rect = const {},
    String? text,
    double strokeWidth = defaultStrokeWidth,
  }) {
    return AnnotationModel(
      id: const Uuid().v4(),
      pageIndex: pageIndex,
      type: type,
      color: color,
      points: points,
      rect: rect,
      text: text,
      strokeWidth: strokeWidth,
      createdAt: DateTime.now(),
    );
  }

  /// Deserialises a JSON map into an [AnnotationModel].
  factory AnnotationModel.fromJson(Map<String, dynamic> json) {
    return AnnotationModel(
      id: json['id'] as String,
      pageIndex: json['pageIndex'] as int,
      type: AnnotationType.fromJson(json['type'] as String),
      color: json['color'] as int,
      points: (json['points'] as List<dynamic>?)
              ?.map((p) => (p as Map<String, dynamic>).map(
                    (k, v) => MapEntry(k, (v as num).toDouble()),
                  ))
              .toList() ??
          const [],
      rect: (json['rect'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, (v as num).toDouble()),
          ) ??
          const {},
      text: json['text'] as String?,
      strokeWidth:
          (json['strokeWidth'] as num?)?.toDouble() ?? defaultStrokeWidth,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  /// Serialises this annotation to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'pageIndex': pageIndex,
      'type': type.toJson(),
      'color': color,
      'points': points,
      'rect': rect,
      'text': text,
      'strokeWidth': strokeWidth,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// The shape sent to the native `applyAnnotations` method. Coordinates are
  /// normalised (0–1) to the page as displayed; the stroke width is likewise a
  /// fraction of the page width (hence `viewWidth: 1`).
  Map<String, dynamic> toNative() {
    return {
      'pageIndex': pageIndex,
      'type': type.name,
      'color': color,
      'points': points,
      'rect': rect,
      'text': text,
      'strokeWidth': strokeWidth,
      'viewWidth': 1.0,
    };
  }

  /// Returns a copy with the given fields replaced.
  AnnotationModel copyWith({
    String? id,
    int? pageIndex,
    AnnotationType? type,
    int? color,
    List<Map<String, double>>? points,
    Map<String, double>? rect,
    String? text,
    bool clearText = false,
    double? strokeWidth,
    DateTime? createdAt,
  }) {
    return AnnotationModel(
      id: id ?? this.id,
      pageIndex: pageIndex ?? this.pageIndex,
      type: type ?? this.type,
      color: color ?? this.color,
      points: points ?? this.points,
      rect: rect ?? this.rect,
      text: clearText ? null : (text ?? this.text),
      strokeWidth: strokeWidth ?? this.strokeWidth,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnnotationModel &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'AnnotationModel(id: $id, page: $pageIndex, type: ${type.name})';
}
