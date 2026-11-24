import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:docuscan_pro/core/services/storage_service.dart';
import 'package:docuscan_pro/core/services/pdf_service.dart';
import 'package:docuscan_pro/core/services/ocr_service.dart';
import 'package:docuscan_pro/core/constants/app_constants.dart';

/// Hybrid file conversion service.
/// On-device primary (custom Dart engine), cloud fallback for complex layouts.
class ConversionService {
  ConversionService._();

  static const _channel = MethodChannel('com.docuscanpro.app/conversion');

  // ── PDF to Word (On-Device) ──

  static Future<ConversionResult> pdfToWord(
    String pdfPath, {
    bool useCloud = false,
  }) async {
    if (useCloud) {
      return _pdfToWordCloud(pdfPath);
    }

    try {
      // On-device: Extract text from PDF pages via platform channel,
      // then generate DOCX using Dart
      final result = await _channel.invokeMethod<Map>('extractPdfContent', {
        'pdfPath': pdfPath,
      });

      final content = Map<String, dynamic>.from(result!);
      final pages = (content['pages'] as List).map((p) {
        return Map<String, dynamic>.from(p as Map);
      }).toList();

      // Judge whether the text layer is good enough (PRD §7 Q1): scanned or
      // image-heavy PDFs yield little or garbled text on-device.
      final quality = assessExtractedText(
        pages.map((p) => p['text'] as String? ?? '').toList(),
      );

      // Build DOCX content
      final docxContent = buildDocx(pages);

      final outputPath = await StorageService.getUniqueFilePath(
        StorageService.exportsDir,
        _getFileNameWithoutExtension(pdfPath),
        'docx',
      );

      await File(outputPath).writeAsBytes(docxContent);

      return ConversionResult(
        outputPath: outputPath,
        engine: ConversionEngine.onDevice,
        success: true,
        lowQuality: quality.isLowQuality,
        qualityNote: quality.reason,
        suggestCloud: quality.isLowQuality,
      );
    } catch (e) {
      return ConversionResult(
        outputPath: '',
        engine: ConversionEngine.onDevice,
        success: false,
        error: 'On-device conversion failed: $e',
        suggestCloud: true,
      );
    }
  }

  // ── On-device quality heuristic ──

  /// Pages with fewer non-whitespace characters than this count as
  /// "near-empty" (typically a scanned image with no text layer).
  static const int sparsePageCharThreshold = 40;

  /// Below this average of non-whitespace characters per page the whole
  /// document is considered sparse.
  static const int sparseAverageCharsPerPage = 100;

  /// Fraction of unreadable characters (U+FFFD, private-use glyphs, control
  /// chars) above which the text is considered garbled — PDFs with custom
  /// font encodings often extract this way.
  static const double garbledCharRatio = 0.15;

  /// Decides whether on-device PDF→Word text extraction is likely poor.
  static ExtractionQuality assessExtractedText(List<String> pageTexts) {
    final pageCount = pageTexts.length;
    if (pageCount == 0) {
      return const ExtractionQuality.low('The PDF has no pages to convert');
    }

    var totalChars = 0;
    var unreadable = 0;
    var sparsePages = 0;
    for (final text in pageTexts) {
      var pageChars = 0;
      for (final rune in text.runes) {
        if (rune == 0x20 || rune == 0x09 || rune == 0x0A || rune == 0x0D ||
            rune == 0xA0) {
          continue;
        }
        pageChars++;
        if (rune == 0xFFFD ||
            rune < 0x20 ||
            (rune >= 0xE000 && rune <= 0xF8FF)) {
          unreadable++;
        }
      }
      totalChars += pageChars;
      if (pageChars < sparsePageCharThreshold) sparsePages++;
    }

    if (totalChars == 0) {
      return const ExtractionQuality.low(
          'No text found — this looks like a scanned PDF');
    }
    if (unreadable / totalChars > garbledCharRatio) {
      return const ExtractionQuality.low(
          'Some text could not be decoded correctly');
    }
    if (sparsePages * 2 > pageCount ||
        totalChars / pageCount < sparseAverageCharsPerPage) {
      return const ExtractionQuality.low(
          'Very little text was found — pages may be scanned images');
    }
    return const ExtractionQuality.good();
  }

  static Future<ConversionResult> _pdfToWordCloud(String pdfPath) async {
    try {
      final bytes = await File(pdfPath).readAsBytes();
      final base64Content = base64Encode(bytes);

      // This would call the Cloud Run microservice
      // For now, we define the interface
      final result = await _channel.invokeMethod<Map>('cloudConvert', {
        'fileContent': base64Content,
        'sourceFormat': 'pdf',
        'targetFormat': 'docx',
        'baseUrl': AppConstants.cloudConversionBaseUrl,
        'apiKey': AppConstants.cloudConversionApiKey,
      });

      final data = Map<String, dynamic>.from(result!);
      final outputBytes = base64Decode(data['content'] as String);

      final outputPath = await StorageService.getUniqueFilePath(
        StorageService.exportsDir,
        _getFileNameWithoutExtension(pdfPath),
        'docx',
      );

      await File(outputPath).writeAsBytes(outputBytes);

      return ConversionResult(
        outputPath: outputPath,
        engine: ConversionEngine.cloud,
        success: true,
      );
    } catch (e) {
      return ConversionResult(
        outputPath: '',
        engine: ConversionEngine.cloud,
        success: false,
        error: 'Cloud conversion failed: $e',
      );
    }
  }

  // ── PDF to Excel (On-Device) ──

  static Future<ConversionResult> pdfToExcel(
    String pdfPath, {
    bool useCloud = false,
  }) async {
    if (useCloud) {
      return _pdfToExcelCloud(pdfPath);
    }

    try {
      // Extract tables from each page using OCR
      final imagePaths = await PdfService.pdfToImages(pdfPath, dpi: 300);
      final allRows = <List<String>>[];

      for (final imagePath in imagePaths) {
        final tableResult = await OcrService.extractTable(imagePath);
        allRows.addAll(tableResult.rows);
      }

      if (allRows.isEmpty) {
        return const ConversionResult(
          outputPath: '',
          engine: ConversionEngine.onDevice,
          success: false,
          error: 'No tables found in PDF',
          suggestCloud: true,
        );
      }

      // Generate a proper XLSX file using the OOXML SpreadsheetML format.
      // Like DOCX, an XLSX is a ZIP archive of XML files.
      final xlsxBytes = _buildXlsxFromRows(allRows);

      final outputPath = await StorageService.getUniqueFilePath(
        StorageService.exportsDir,
        _getFileNameWithoutExtension(pdfPath),
        'xlsx',
      );

      await File(outputPath).writeAsBytes(xlsxBytes);

      return ConversionResult(
        outputPath: outputPath,
        engine: ConversionEngine.onDevice,
        success: true,
      );
    } catch (e) {
      return ConversionResult(
        outputPath: '',
        engine: ConversionEngine.onDevice,
        success: false,
        error: 'On-device extraction failed: $e',
        suggestCloud: true,
      );
    }
  }

  static Future<ConversionResult> _pdfToExcelCloud(String pdfPath) async {
    try {
      final bytes = await File(pdfPath).readAsBytes();
      final base64Content = base64Encode(bytes);

      final result = await _channel.invokeMethod<Map>('cloudConvert', {
        'fileContent': base64Content,
        'sourceFormat': 'pdf',
        'targetFormat': 'xlsx',
        'baseUrl': AppConstants.cloudConversionBaseUrl,
        'apiKey': AppConstants.cloudConversionApiKey,
      });

      final data = Map<String, dynamic>.from(result!);
      final outputBytes = base64Decode(data['content'] as String);

      final outputPath = await StorageService.getUniqueFilePath(
        StorageService.exportsDir,
        _getFileNameWithoutExtension(pdfPath),
        'xlsx',
      );

      await File(outputPath).writeAsBytes(outputBytes);

      return ConversionResult(
        outputPath: outputPath,
        engine: ConversionEngine.cloud,
        success: true,
      );
    } catch (e) {
      return ConversionResult(
        outputPath: '',
        engine: ConversionEngine.cloud,
        success: false,
        error: 'Cloud conversion failed: $e',
      );
    }
  }

  // ── PDF to Image ──

  static Future<ConversionResult> pdfToImage(
    String pdfPath, {
    String format = 'png',
    int dpi = 300,
  }) async {
    try {
      final imagePaths = await PdfService.pdfToImages(
        pdfPath,
        format: format,
        dpi: dpi,
      );

      return ConversionResult(
        outputPath: imagePaths.first,
        outputPaths: imagePaths,
        engine: ConversionEngine.onDevice,
        success: true,
      );
    } catch (e) {
      return ConversionResult(
        outputPath: '',
        engine: ConversionEngine.onDevice,
        success: false,
        error: 'Failed to convert PDF to images: $e',
      );
    }
  }

  // ── Image to PDF ──

  static Future<ConversionResult> imageToPdf(
    List<String> imagePaths, {
    String? title,
  }) async {
    try {
      final outputPath = await PdfService.createPdfFromImages(
        imagePaths,
        title: title,
      );

      return ConversionResult(
        outputPath: outputPath,
        engine: ConversionEngine.onDevice,
        success: true,
      );
    } catch (e) {
      return ConversionResult(
        outputPath: '',
        engine: ConversionEngine.onDevice,
        success: false,
        error: 'Failed to convert images to PDF: $e',
      );
    }
  }

  // ── Helpers ──

  /// Builds a minimal but valid WordprocessingML (.docx) package from the
  /// extracted page texts: one paragraph per line, a page break between PDF
  /// pages, and a default style (Calibri 11pt).
  static List<int> buildDocx(List<Map<String, dynamic>> pages) {
    final body = StringBuffer();
    for (var i = 0; i < pages.length; i++) {
      final text = pages[i]['text'] as String? ?? '';
      for (final para in text.split('\n')) {
        if (para.trim().isEmpty) continue;
        // xml:space="preserve" keeps leading/trailing spaces.
        body.write('<w:p><w:r><w:t xml:space="preserve">'
            '${_escapeXml(para.trimRight())}</w:t></w:r></w:p>');
      }
      // Page break between pages (not after the last one).
      if (i < pages.length - 1) {
        body.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
      }
    }
    // A body needs at least one block-level element.
    if (body.isEmpty) body.write('<w:p/>');

    final documentXml = '$_xmlHeader'
        '<w:document xmlns:w="$_wNs">'
        '<w:body>$body'
        '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" '
        'w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>'
        '</w:body></w:document>';

    final archive = Archive()
      ..addFile(ArchiveFile.string('[Content_Types].xml', '$_xmlHeader'
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/word/document.xml" '
          'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
          '<Override PartName="/word/styles.xml" '
          'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
          '</Types>'))
      ..addFile(ArchiveFile.string('_rels/.rels', '$_xmlHeader'
          '<Relationships xmlns="$_relsNs">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
          '</Relationships>'))
      ..addFile(ArchiveFile.string('word/document.xml', documentXml))
      ..addFile(ArchiveFile.string('word/_rels/document.xml.rels', '$_xmlHeader'
          '<Relationships xmlns="$_relsNs">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
          '</Relationships>'))
      ..addFile(ArchiveFile.string('word/styles.xml', '$_xmlHeader'
          '<w:styles xmlns:w="$_wNs">'
          '<w:docDefaults><w:rPrDefault><w:rPr>'
          '<w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Calibri" w:cs="Calibri"/>'
          '<w:sz w:val="22"/><w:szCs w:val="22"/>'
          '</w:rPr></w:rPrDefault>'
          '<w:pPrDefault><w:pPr><w:spacing w:after="160" w:line="259" w:lineRule="auto"/></w:pPr></w:pPrDefault>'
          '</w:docDefaults>'
          '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>'
          '</w:styles>'));

    return ZipEncoder().encode(archive);
  }

  static const _xmlHeader =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
  static const _wNs =
      'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
  static const _relsNs =
      'http://schemas.openxmlformats.org/package/2006/relationships';

  /// Builds a valid XLSX file from extracted table rows using OOXML
  /// SpreadsheetML format — a ZIP archive of XML, just like DOCX.
  static List<int> _buildXlsxFromRows(List<List<String>> rows) {
    final archive = Archive();

    // Content Types
    const contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '</Types>';
    archive.addFile(ArchiveFile.string('[Content_Types].xml', contentTypes));

    // Top-level rels
    const rels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>';
    archive.addFile(ArchiveFile.string('_rels/.rels', rels));

    // Workbook
    const workbook = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>';
    archive.addFile(ArchiveFile.string('xl/workbook.xml', workbook));

    // Workbook rels
    const wbRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
        '</Relationships>';
    archive.addFile(ArchiveFile.string('xl/_rels/workbook.xml.rels', wbRels));

    // Sheet data
    final sheetXml = StringBuffer();
    sheetXml.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    sheetXml.writeln('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">');
    sheetXml.writeln('<sheetData>');

    for (int r = 0; r < rows.length; r++) {
      sheetXml.write('<row r="${r + 1}">');
      for (int c = 0; c < rows[r].length; c++) {
        final cellRef = '${columnName(c)}${r + 1}';
        final value = _escapeXml(rows[r][c]);
        sheetXml.write('<c r="$cellRef" t="inlineStr"><is><t>$value</t></is></c>');
      }
      sheetXml.writeln('</row>');
    }

    sheetXml.writeln('</sheetData>');
    sheetXml.writeln('</worksheet>');

    archive.addFile(
        ArchiveFile.string('xl/worksheets/sheet1.xml', sheetXml.toString()));

    return ZipEncoder().encode(archive);
  }

  /// Spreadsheet column name for a zero-based index: 0 → A, 25 → Z, 26 → AA.
  static String columnName(int index) {
    var n = index + 1;
    final buffer = StringBuffer();
    while (n > 0) {
      final rem = (n - 1) % 26;
      buffer.write(String.fromCharCode(65 + rem));
      n = (n - 1) ~/ 26;
    }
    return buffer.toString().split('').reversed.join();
  }

  /// Escapes XML special characters and drops characters that are not
  /// allowed in XML 1.0 at all (control chars, lone surrogates, U+FFFE/F),
  /// which would otherwise make Word refuse to open the file.
  static String _escapeXml(String text) {
    return text
        .replaceAll(
            RegExp('[\u0000-\u0008\u000B\u000C\u000E-\u001F\uFFFE\uFFFF]'),
            '')
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  static String _getFileNameWithoutExtension(String path) {
    final fileName = path.split('/').last;
    final dotIndex = fileName.lastIndexOf('.');
    return dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
  }
}

enum ConversionEngine { onDevice, cloud }

class ConversionResult {
  final String outputPath;
  final List<String>? outputPaths;
  final ConversionEngine engine;
  final bool success;
  final String? error;

  /// The cloud engine is likely to do better (on-device failed, or produced
  /// a low-quality result).
  final bool suggestCloud;

  /// On-device conversion succeeded but the output is probably poor (e.g.
  /// scanned PDF with no text layer). [qualityNote] says why.
  final bool lowQuality;
  final String? qualityNote;

  const ConversionResult({
    required this.outputPath,
    required this.engine,
    required this.success,
    this.outputPaths,
    this.error,
    this.suggestCloud = false,
    this.lowQuality = false,
    this.qualityNote,
  });
}

/// Outcome of [ConversionService.assessExtractedText].
class ExtractionQuality {
  final bool isLowQuality;
  final String? reason;

  const ExtractionQuality.good()
      : isLowQuality = false,
        reason = null;
  const ExtractionQuality.low(this.reason) : isLowQuality = true;
}
