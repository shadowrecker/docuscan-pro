import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// OCR service providing text recognition via ML Kit (primary)
/// and Tesseract 5 (extended languages) via platform channel.
class OcrService {
  OcrService._();

  static const _channel = MethodChannel('com.docuscanpro.app/ocr');

  // ── ML Kit Text Recognition ──

  static Future<OcrResult> recognizeText(
    String imagePath, {
    OcrScript script = OcrScript.latin,
  }) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final scriptType = _getTextRecognitionScript(script);
    final textRecognizer = TextRecognizer(script: scriptType);

    try {
      final recognizedText = await textRecognizer.processImage(inputImage);
      return OcrResult(
        fullText: recognizedText.text,
        blocks: recognizedText.blocks.map((block) {
          return OcrTextBlock(
            text: block.text,
            boundingBox: block.boundingBox,
            lines: block.lines.map((line) {
              return OcrTextLine(
                text: line.text,
                boundingBox: line.boundingBox,
                words: line.elements.map((element) {
                  return OcrWord(
                    text: element.text,
                    boundingBox: element.boundingBox,
                    confidence: 0.0, // ML Kit v2 doesn't expose confidence per word
                  );
                }).toList(),
              );
            }).toList(),
          );
        }).toList(),
        engine: 'ML Kit',
        script: script,
      );
    } finally {
      textRecognizer.close();
    }
  }

  // ── Tesseract OCR (for extended languages) ──

  static Future<OcrResult> recognizeTextTesseract(
    String imagePath, {
    required String languageCode,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map>('recognizeText', {
        'imagePath': imagePath,
        'languageCode': languageCode,
      });

      final data = Map<String, dynamic>.from(result!);
      return OcrResult(
        fullText: data['text'] as String? ?? '',
        blocks: (data['blocks'] as List?)?.map((block) {
          final b = Map<String, dynamic>.from(block as Map);
          final text = b['text'] as String? ?? '';
          final bounds = _rectFromMap(b['bounds']);
          return OcrTextBlock(
            text: text,
            boundingBox: bounds,
            lines: splitBlockIntoLines(text, bounds),
          );
        }).toList() ?? [],
        engine: 'Tesseract',
        script: OcrScript.latin,
      );
    } on PlatformException catch (e) {
      if (e.code == 'LANGUAGE_NOT_DOWNLOADED') {
        throw OcrLanguageNotDownloadedException(languageCode);
      }
      throw Exception('Tesseract OCR failed: ${e.message}');
    }
  }

  /// Recognises text with the engine appropriate for [language]: ML Kit for
  /// its on-device scripts, Tesseract (by 3-letter code) for everything else.
  ///
  /// Throws [OcrLanguageNotDownloadedException] if a Tesseract pack is missing.
  static Future<OcrResult> recognize(
    String imagePath, {
    required OcrLanguage language,
  }) {
    if (language.usesMlKit) {
      return recognizeText(imagePath, script: language.mlKitScript!);
    }
    return recognizeTextTesseract(
      imagePath,
      languageCode: language.tesseractCode,
    );
  }

  /// Tesseract (via the native bridge) only reports block-level boxes. For a
  /// searchable text layer we need line boxes, so split the block text on
  /// newlines and divide the block height evenly between the lines.
  static List<OcrTextLine> splitBlockIntoLines(String text, Rect bounds) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return const [];
    final lineHeight = bounds.height / lines.length;
    return [
      for (var i = 0; i < lines.length; i++)
        OcrTextLine(
          text: lines[i],
          boundingBox: Rect.fromLTWH(
            bounds.left,
            bounds.top + i * lineHeight,
            bounds.width,
            lineHeight,
          ),
          words: const [],
        ),
    ];
  }

  // ── Table Extraction ──

  static Future<TableExtractionResult> extractTable(String imagePath) async {
    // First, run OCR to get text blocks with positions
    final ocrResult = await recognizeText(imagePath);

    // Simple table detection: group text blocks by vertical position (rows)
    // and horizontal position (columns)
    final rows = <List<String>>[];
    if (ocrResult.blocks.isEmpty) {
      return const TableExtractionResult(rows: [], csvContent: '');
    }

    // Sort blocks by Y position to identify rows
    final sortedBlocks = List<OcrTextBlock>.from(ocrResult.blocks)
      ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    // Group into rows based on vertical proximity
    double currentRowTop = sortedBlocks.first.boundingBox.top;
    List<OcrTextBlock> currentRow = [];
    final rowGroups = <List<OcrTextBlock>>[];

    for (final block in sortedBlocks) {
      if ((block.boundingBox.top - currentRowTop).abs() < 20) {
        currentRow.add(block);
      } else {
        if (currentRow.isNotEmpty) rowGroups.add(List.from(currentRow));
        currentRow = [block];
        currentRowTop = block.boundingBox.top;
      }
    }
    if (currentRow.isNotEmpty) rowGroups.add(currentRow);

    // Sort each row by X position (left to right)
    for (final row in rowGroups) {
      row.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
      rows.add(row.map((b) => b.text).toList());
    }

    return TableExtractionResult(
      rows: rows,
      csvContent: rowsToCsv(rows),
    );
  }

  /// Serialises [rows] as RFC 4180-style CSV (`\n` line separator).
  static String rowsToCsv(List<List<String>> rows) {
    return rows.map((row) => row.map(escapeCsvCell).join(',')).join('\n');
  }

  /// Quotes a CSV cell if it contains a comma, quote, CR or LF.
  static String escapeCsvCell(String cell) {
    if (cell.contains(',') ||
        cell.contains('"') ||
        cell.contains('\n') ||
        cell.contains('\r')) {
      return '"${cell.replaceAll('"', '""')}"';
    }
    return cell;
  }

  // ── Download Language Pack (Tesseract) ──

  static Future<bool> downloadLanguagePack(String languageCode) async {
    try {
      final result = await _channel.invokeMethod<bool>('downloadLanguagePack', {
        'languageCode': languageCode,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('Failed to download language pack: ${e.message}');
      return false;
    }
  }

  static Future<List<String>> getAvailableLanguages() async {
    try {
      final result = await _channel.invokeMethod<List>('getAvailableLanguages');
      return result?.cast<String>() ?? [];
    } on PlatformException {
      return [];
    }
  }

  // ── Helpers ──

  static TextRecognitionScript _getTextRecognitionScript(OcrScript script) {
    switch (script) {
      case OcrScript.latin:
        return TextRecognitionScript.latin;
      case OcrScript.chinese:
        return TextRecognitionScript.chinese;
      case OcrScript.devanagari:
        return TextRecognitionScript.devanagiri; // (sic) plugin spelling
      case OcrScript.japanese:
        return TextRecognitionScript.japanese;
      case OcrScript.korean:
        return TextRecognitionScript.korean;
    }
  }

  static Rect _rectFromMap(dynamic map) {
    if (map == null) return Rect.zero;
    final m = Map<String, dynamic>.from(map);
    return Rect.fromLTWH(
      (m['left'] as num).toDouble(),
      (m['top'] as num).toDouble(),
      (m['width'] as num).toDouble(),
      (m['height'] as num).toDouble(),
    );
  }
}

// ── OCR Data Models ──

enum OcrScript { latin, chinese, devanagari, japanese, korean }

class OcrResult {
  final String fullText;
  final List<OcrTextBlock> blocks;
  final String engine;
  final OcrScript script;

  const OcrResult({
    required this.fullText,
    required this.blocks,
    required this.engine,
    required this.script,
  });

  bool get isEmpty => fullText.trim().isEmpty;
  bool get isNotEmpty => !isEmpty;

  /// All recognised lines in reading order (as returned by the engine), with
  /// boxes in the pixel coordinates of the source image.
  List<OcrTextLine> get allLines => [
        for (final block in blocks)
          if (block.lines.isNotEmpty)
            ...block.lines
          else if (block.text.trim().isNotEmpty)
            ...OcrService.splitBlockIntoLines(block.text, block.boundingBox),
      ];
}

class OcrTextBlock {
  final String text;
  final Rect boundingBox;
  final List<OcrTextLine> lines;

  const OcrTextBlock({
    required this.text,
    required this.boundingBox,
    required this.lines,
  });
}

class OcrTextLine {
  final String text;
  final Rect boundingBox;
  final List<OcrWord> words;

  const OcrTextLine({
    required this.text,
    required this.boundingBox,
    required this.words,
  });
}

class OcrWord {
  final String text;
  final Rect boundingBox;
  final double confidence;

  const OcrWord({
    required this.text,
    required this.boundingBox,
    required this.confidence,
  });
}

class TableExtractionResult {
  final List<List<String>> rows;
  final String csvContent;

  const TableExtractionResult({
    required this.rows,
    required this.csvContent,
  });

  bool get isEmpty => rows.isEmpty;
  int get rowCount => rows.length;
  int get columnCount => rows.isEmpty ? 0 : rows.first.length;
}

// Language definitions for the OCR language picker
class OcrLanguage {
  /// Stable 2-letter identifier (ISO 639-1); this is what gets persisted in
  /// the `ocrLanguages` setting.
  final String code;
  final String name;

  /// Tesseract traineddata name (ISO 639-2/T, e.g. `rus`, `chi_sim`). Used
  /// for language-pack download and Tesseract recognition.
  final String tesseractCode;
  final OcrScript? mlKitScript;
  final bool requiresTesseract;

  const OcrLanguage({
    required this.code,
    required this.name,
    required this.tesseractCode,
    this.mlKitScript,
    this.requiresTesseract = false,
  });

  /// Whether this language is recognised on-device by ML Kit (no download).
  bool get usesMlKit => !requiresTesseract && mlKitScript != null;

  static const OcrLanguage english = OcrLanguage(
      code: 'en', name: 'English', tesseractCode: 'eng', mlKitScript: OcrScript.latin);

  static const List<OcrLanguage> supported = [
    english,
    OcrLanguage(code: 'es', name: 'Spanish', tesseractCode: 'spa', mlKitScript: OcrScript.latin),
    OcrLanguage(code: 'fr', name: 'French', tesseractCode: 'fra', mlKitScript: OcrScript.latin),
    OcrLanguage(code: 'de', name: 'German', tesseractCode: 'deu', mlKitScript: OcrScript.latin),
    OcrLanguage(code: 'pt', name: 'Portuguese', tesseractCode: 'por', mlKitScript: OcrScript.latin),
    OcrLanguage(code: 'it', name: 'Italian', tesseractCode: 'ita', mlKitScript: OcrScript.latin),
    OcrLanguage(code: 'nl', name: 'Dutch', tesseractCode: 'nld', mlKitScript: OcrScript.latin),
    OcrLanguage(code: 'pl', name: 'Polish', tesseractCode: 'pol', mlKitScript: OcrScript.latin),
    OcrLanguage(code: 'tr', name: 'Turkish', tesseractCode: 'tur', mlKitScript: OcrScript.latin),
    OcrLanguage(code: 'vi', name: 'Vietnamese', tesseractCode: 'vie', mlKitScript: OcrScript.latin),
    OcrLanguage(code: 'id', name: 'Indonesian', tesseractCode: 'ind', mlKitScript: OcrScript.latin),
    OcrLanguage(code: 'zh', name: 'Chinese', tesseractCode: 'chi_sim', mlKitScript: OcrScript.chinese),
    OcrLanguage(code: 'hi', name: 'Hindi', tesseractCode: 'hin', mlKitScript: OcrScript.devanagari),
    OcrLanguage(code: 'mr', name: 'Marathi', tesseractCode: 'mar', mlKitScript: OcrScript.devanagari),
    OcrLanguage(code: 'ja', name: 'Japanese', tesseractCode: 'jpn', mlKitScript: OcrScript.japanese),
    OcrLanguage(code: 'ko', name: 'Korean', tesseractCode: 'kor', mlKitScript: OcrScript.korean),
    OcrLanguage(code: 'ru', name: 'Russian', tesseractCode: 'rus', requiresTesseract: true),
    OcrLanguage(code: 'ar', name: 'Arabic', tesseractCode: 'ara', requiresTesseract: true),
    OcrLanguage(code: 'fa', name: 'Farsi', tesseractCode: 'fas', requiresTesseract: true),
    OcrLanguage(code: 'ur', name: 'Urdu', tesseractCode: 'urd', requiresTesseract: true),
    OcrLanguage(code: 'th', name: 'Thai', tesseractCode: 'tha', requiresTesseract: true),
    OcrLanguage(code: 'he', name: 'Hebrew', tesseractCode: 'heb', requiresTesseract: true),
    OcrLanguage(code: 'el', name: 'Greek', tesseractCode: 'ell', requiresTesseract: true),
    OcrLanguage(code: 'bn', name: 'Bengali', tesseractCode: 'ben', requiresTesseract: true),
    OcrLanguage(code: 'ta', name: 'Tamil', tesseractCode: 'tam', requiresTesseract: true),
    OcrLanguage(code: 'uk', name: 'Ukrainian', tesseractCode: 'ukr', requiresTesseract: true),
    OcrLanguage(code: 'bg', name: 'Bulgarian', tesseractCode: 'bul', requiresTesseract: true),
    OcrLanguage(code: 'sr', name: 'Serbian', tesseractCode: 'srp', requiresTesseract: true),
  ];

  /// ML Kit-backed languages (no download needed).
  static List<OcrLanguage> get onDevice =>
      supported.where((l) => l.usesMlKit).toList();

  /// Tesseract-backed languages (traineddata download needed).
  static List<OcrLanguage> get tesseract =>
      supported.where((l) => !l.usesMlKit).toList();

  /// Looks up a language by its 2-letter [code] (or its Tesseract code).
  /// Returns null for unknown codes.
  static OcrLanguage? fromCode(String code) {
    for (final lang in supported) {
      if (lang.code == code || lang.tesseractCode == code) return lang;
    }
    return null;
  }

  @override
  bool operator ==(Object other) => other is OcrLanguage && other.code == code;

  @override
  int get hashCode => code.hashCode;
}

/// Thrown when a Tesseract language is requested whose traineddata has not
/// been downloaded yet (native error code `LANGUAGE_NOT_DOWNLOADED`).
class OcrLanguageNotDownloadedException implements Exception {
  final String tesseractCode;
  const OcrLanguageNotDownloadedException(this.tesseractCode);

  @override
  String toString() => 'Language pack "$tesseractCode" is not downloaded';
}
