import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'package:docuscan_pro/core/utils/file_utils.dart';

/// Displays a document thumbnail with built-in loading and error states.
///
/// Behaviour:
/// - If [thumbnailPath] is provided and the file exists, it is displayed as an
///   image.
/// - If [filePath] points to a PDF, a PDF icon with an optional page count
///   badge is shown.
/// - If [filePath] points to an image, it is shown directly.
/// - While loading, a shimmer placeholder is rendered.
/// - On error, a generic document icon is displayed.
class DocumentThumbnail extends StatelessWidget {
  /// Path to the original document file.
  final String filePath;

  /// Optional pre-generated thumbnail path (e.g., from a cache).
  final String? thumbnailPath;

  /// Width of the thumbnail container.
  final double width;

  /// Height of the thumbnail container.
  final double height;

  /// Corner radius of the thumbnail.
  final double borderRadius;

  /// For PDFs, the total number of pages (shown as a badge).
  final int? pageCount;

  const DocumentThumbnail({
    super.key,
    required this.filePath,
    this.thumbnailPath,
    this.width = 80,
    this.height = 100,
    this.borderRadius = 8,
    this.pageCount,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: width,
        height: height,
        child: _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    // 1. Pre-generated thumbnail.
    if (thumbnailPath != null && thumbnailPath!.isNotEmpty) {
      final file = File(thumbnailPath!);
      if (file.existsSync()) {
        return _imageWidget(file);
      }
    }

    // 2. PDF file – show icon.
    if (FileUtils.isPdfFile(filePath)) {
      return _pdfPlaceholder(context);
    }

    // 3. Image file – show the image itself.
    if (FileUtils.isImageFile(filePath)) {
      final file = File(filePath);
      if (file.existsSync()) {
        return _imageWidget(file);
      }
    }

    // 4. Fallback – generic document icon.
    return _fallbackPlaceholder(context);
  }

  // ---------------------------------------------------------------------------
  // Sub-widgets
  // ---------------------------------------------------------------------------

  Widget _imageWidget(File file) {
    return Image.file(
      file,
      width: width,
      height: height,
      fit: BoxFit.cover,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return _shimmerPlaceholder(context);
      },
      errorBuilder: (context, _, _) => _fallbackPlaceholder(context),
    );
  }

  Widget _pdfPlaceholder(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      color: Colors.red.shade50,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.picture_as_pdf_rounded,
            size: width * 0.5,
            color: Colors.red.shade400,
          ),
          if (pageCount != null)
            Positioned(
              bottom: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.shade400,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '$pageCount pg',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _shimmerPlaceholder(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Container(
        width: width,
        height: height,
        color: Colors.white,
      ),
    );
  }

  Widget _fallbackPlaceholder(BuildContext context) {
    return Container(
      color: Colors.grey.shade200,
      child: Icon(
        Icons.insert_drive_file_outlined,
        size: width * 0.45,
        color: Colors.grey.shade500,
      ),
    );
  }
}
