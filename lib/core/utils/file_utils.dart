import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

/// Utility class providing static helper methods for file operations.
class FileUtils {
  FileUtils._();

  /// Common image file extensions.
  static const _imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.bmp',
    '.webp',
    '.heic',
    '.heif',
    '.tiff',
    '.tif',
  };

  /// Returns the file extension including the dot (e.g., `.pdf`).
  ///
  /// Returns an empty string if the path has no extension.
  static String getFileExtension(String path) {
    return p.extension(path).toLowerCase();
  }

  /// Returns the full file name with extension from a path.
  static String getFileName(String path) {
    return p.basename(path);
  }

  /// Returns the file name without its extension.
  static String getFileNameWithoutExtension(String path) {
    return p.basenameWithoutExtension(path);
  }

  /// Formats a byte count into a human-readable file size string.
  ///
  /// Examples:
  /// - `formatFileSize(512)` -> `"512 B"`
  /// - `formatFileSize(1536)` -> `"1.5 KB"`
  /// - `formatFileSize(1048576)` -> `"1.0 MB"`
  static String formatFileSize(int bytes) {
    if (bytes < 0) return '0 B';

    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    int unitIndex = 0;
    double size = bytes.toDouble();

    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }

    if (unitIndex == 0) {
      return '${size.toInt()} ${units[unitIndex]}';
    }
    return '${size.toStringAsFixed(1)} ${units[unitIndex]}';
  }

  /// Returns `true` if the file path has a recognized image extension.
  static bool isImageFile(String path) {
    final ext = getFileExtension(path);
    return _imageExtensions.contains(ext);
  }

  /// Returns `true` if the file path has a `.pdf` extension.
  static bool isPdfFile(String path) {
    return getFileExtension(path) == '.pdf';
  }

  /// Returns the MIME type for the given file path, or
  /// `application/octet-stream` if unknown.
  static String getMimeType(String path) {
    return lookupMimeType(path) ?? 'application/octet-stream';
  }

  /// Generates a unique file name by appending a millisecond timestamp.
  ///
  /// Example: `generateUniqueFileName('scan', 'pdf')` ->
  /// `"scan_1711234567890.pdf"`
  static String generateUniqueFileName(String baseName, String extension) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final sanitizedBase = baseName.replaceAll(RegExp(r'[^\w\-.]'), '_');
    final ext = extension.startsWith('.') ? extension : '.$extension';
    return '${sanitizedBase}_$timestamp$ext';
  }
}
