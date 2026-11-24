/// Image filter applied during or after scanning.
enum ScanFilter {
  original,
  enhanced,
  grayscale,
  bw;

  String toJson() => name;

  static ScanFilter fromJson(String value) {
    return ScanFilter.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ScanFilter.enhanced,
    );
  }

  /// A human-readable label for display in the UI.
  String get displayName {
    switch (this) {
      case ScanFilter.original:
        return 'Original';
      case ScanFilter.enhanced:
        return 'Enhanced';
      case ScanFilter.grayscale:
        return 'Grayscale';
      case ScanFilter.bw:
        return 'Black & White';
    }
  }
}

/// Configuration for the document scanning pipeline.
class ScanSettingsModel {
  /// The image filter to apply to scanned pages.
  final ScanFilter filter;

  /// Target DPI resolution for the scan output.
  final double resolution;

  /// Whether automatic edge detection and perspective correction is enabled.
  final bool autoEdgeDetection;

  /// Whether the scanner should remain open for capturing multiple pages
  /// in a single session.
  final bool multiPageMode;

  const ScanSettingsModel({
    this.filter = ScanFilter.enhanced,
    this.resolution = 300.0,
    this.autoEdgeDetection = true,
    this.multiPageMode = false,
  });

  /// Sensible production defaults.
  static const ScanSettingsModel defaults = ScanSettingsModel();

  /// Deserialises a JSON map into a [ScanSettingsModel].
  factory ScanSettingsModel.fromJson(Map<String, dynamic> json) {
    return ScanSettingsModel(
      filter: ScanFilter.fromJson(json['filter'] as String? ?? 'enhanced'),
      resolution: (json['resolution'] as num?)?.toDouble() ?? 300.0,
      autoEdgeDetection: json['autoEdgeDetection'] as bool? ?? true,
      multiPageMode: json['multiPageMode'] as bool? ?? false,
    );
  }

  /// Serialises this settings object to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'filter': filter.toJson(),
      'resolution': resolution,
      'autoEdgeDetection': autoEdgeDetection,
      'multiPageMode': multiPageMode,
    };
  }

  /// Returns a copy with the given fields replaced.
  ScanSettingsModel copyWith({
    ScanFilter? filter,
    double? resolution,
    bool? autoEdgeDetection,
    bool? multiPageMode,
  }) {
    return ScanSettingsModel(
      filter: filter ?? this.filter,
      resolution: resolution ?? this.resolution,
      autoEdgeDetection: autoEdgeDetection ?? this.autoEdgeDetection,
      multiPageMode: multiPageMode ?? this.multiPageMode,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScanSettingsModel &&
          runtimeType == other.runtimeType &&
          filter == other.filter &&
          resolution == other.resolution &&
          autoEdgeDetection == other.autoEdgeDetection &&
          multiPageMode == other.multiPageMode;

  @override
  int get hashCode => Object.hash(filter, resolution, autoEdgeDetection, multiPageMode);

  @override
  String toString() =>
      'ScanSettingsModel(filter: ${filter.name}, resolution: $resolution, '
      'autoEdge: $autoEdgeDetection, multiPage: $multiPageMode)';
}
