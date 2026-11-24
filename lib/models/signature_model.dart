import 'package:uuid/uuid.dart';

/// Represents a saved user signature that can be applied to documents.
class SignatureModel {
  /// Unique identifier for this signature.
  final String id;

  /// User-given name for the signature (e.g. "Work Signature").
  final String name;

  /// File-system path to the saved signature image (PNG).
  final String imagePath;

  /// Timestamp when the signature was created.
  final DateTime createdAt;

  /// Whether this is the user's default signature for quick-apply.
  final bool isDefault;

  const SignatureModel({
    required this.id,
    required this.name,
    required this.imagePath,
    required this.createdAt,
    this.isDefault = false,
  });

  /// Convenience factory that auto-generates an [id] and [createdAt] timestamp.
  factory SignatureModel.create({
    required String name,
    required String imagePath,
    bool isDefault = false,
  }) {
    return SignatureModel(
      id: const Uuid().v4(),
      name: name,
      imagePath: imagePath,
      createdAt: DateTime.now(),
      isDefault: isDefault,
    );
  }

  /// Deserialises a JSON map into a [SignatureModel].
  factory SignatureModel.fromJson(Map<String, dynamic> json) {
    return SignatureModel(
      id: json['id'] as String,
      name: json['name'] as String,
      imagePath: json['imagePath'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      isDefault: json['isDefault'] as bool? ?? false,
    );
  }

  /// Serialises this signature to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'imagePath': imagePath,
      'createdAt': createdAt.toIso8601String(),
      'isDefault': isDefault,
    };
  }

  /// Returns a copy with the given fields replaced.
  SignatureModel copyWith({
    String? id,
    String? name,
    String? imagePath,
    DateTime? createdAt,
    bool? isDefault,
  }) {
    return SignatureModel(
      id: id ?? this.id,
      name: name ?? this.name,
      imagePath: imagePath ?? this.imagePath,
      createdAt: createdAt ?? this.createdAt,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SignatureModel &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'SignatureModel(id: $id, name: $name, isDefault: $isDefault)';
}
