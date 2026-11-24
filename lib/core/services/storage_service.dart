import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:docuscan_pro/core/constants/app_constants.dart';

class StorageService {
  StorageService._();

  static late Directory _appDocumentsDir;
  static late Directory _scansDir;
  static late Directory _exportsDir;
  static late Directory _signaturesDir;
  static late Directory _tempDir;

  static Directory get appDocumentsDir => _appDocumentsDir;
  static Directory get scansDir => _scansDir;
  static Directory get exportsDir => _exportsDir;
  static Directory get signaturesDir => _signaturesDir;
  static Directory get tempDir => _tempDir;

  static Future<void> initialize() async {
    final baseDir = await getApplicationDocumentsDirectory();

    _appDocumentsDir = Directory('${baseDir.path}/${AppConstants.documentsFolder}');
    _scansDir = Directory('${_appDocumentsDir.path}/${AppConstants.scansFolder}');
    _exportsDir = Directory('${_appDocumentsDir.path}/${AppConstants.exportsFolder}');
    _signaturesDir = Directory('${_appDocumentsDir.path}/${AppConstants.signaturesFolder}');
    _tempDir = Directory('${_appDocumentsDir.path}/${AppConstants.tempFolder}');

    await Future.wait([
      _appDocumentsDir.create(recursive: true),
      _scansDir.create(recursive: true),
      _exportsDir.create(recursive: true),
      _signaturesDir.create(recursive: true),
      _tempDir.create(recursive: true),
    ]);
  }

  static Future<String> getUniqueFilePath(
    Directory directory,
    String baseName,
    String extension,
  ) async {
    var filePath = '${directory.path}/$baseName.$extension';
    var counter = 1;

    while (await File(filePath).exists()) {
      filePath = '${directory.path}/${baseName}_$counter.$extension';
      counter++;
    }

    return filePath;
  }

  static Future<int> getDirectorySize(Directory directory) async {
    int totalSize = 0;
    if (await directory.exists()) {
      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
    }
    return totalSize;
  }

  static Future<void> clearTemp() async {
    if (await _tempDir.exists()) {
      await _tempDir.delete(recursive: true);
      await _tempDir.create(recursive: true);
    }
  }

  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
