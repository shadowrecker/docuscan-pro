import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:docuscan_pro/core/services/storage_service.dart';

/// PDF service that handles PDF operations using Dart-based libraries
/// and platform channels to Apache PDFBox (Android) / native APIs (iOS).
class PdfService {
  PdfService._();

  static const _channel = MethodChannel('com.docuscanpro.app/pdf');

  // ── Create PDF from images ──

  static Future<String> createPdfFromImages(
    List<String> imagePaths, {
    String? title,
    double quality = 0.85,
    Directory? outputDir,
  }) async {
    final pdf = pw.Document(
      title: title ?? 'Scanned Document',
      creator: 'DocuScan Pro',
    );

    for (final path in imagePaths) {
      final imageBytes = await File(path).readAsBytes();
      final image = pw.MemoryImage(imageBytes);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (context) => pw.Center(
            child: pw.Image(image, fit: pw.BoxFit.contain),
          ),
        ),
      );
    }

    final fileName = title ?? 'scan_${DateTime.now().millisecondsSinceEpoch}';
    final outputPath = await StorageService.getUniqueFilePath(
      outputDir ?? StorageService.scansDir,
      fileName,
      'pdf',
    );

    final file = File(outputPath);
    await file.writeAsBytes(await pdf.save());

    return outputPath;
  }

  // ── Merge PDFs ──

  /// Merges [pdfPaths] in order. Uses the native bridge (PDFBox / PDFKit);
  /// if that is unavailable or fails, falls back to a pure-Dart merge with
  /// Syncfusion that copies each page's content as a vector template.
  static Future<String> mergePdfs(
    List<String> pdfPaths, {
    String? outputName,
  }) async {
    final name = outputName ?? 'merged_${DateTime.now().millisecondsSinceEpoch}';
    try {
      final result = await _channel.invokeMethod<String>('mergePdfs', {
        'pdfPaths': pdfPaths,
        'outputName': name,
        'outputDir': StorageService.exportsDir.path,
      });
      if (result != null) return result;
    } on PlatformException catch (e) {
      debugPrint('Native merge failed (${e.code}): ${e.message} — using Dart merge');
    } on MissingPluginException {
      debugPrint('Native merge unavailable — using Dart merge');
    }

    try {
      return await _mergePdfsDart(pdfPaths, outputName: name);
    } catch (e) {
      throw Exception('Failed to merge PDFs: $e');
    }
  }

  /// Pure-Dart merge. Each source page is drawn into a new page of the same
  /// size as a PDF template (vector content and text are preserved, so the
  /// output stays selectable/searchable). Interactive form fields, links and
  /// annotations are not carried over; encrypted inputs throw.
  static Future<String> _mergePdfsDart(
    List<String> pdfPaths, {
    required String outputName,
  }) async {
    final output = sf.PdfDocument();
    try {
      for (final path in pdfPaths) {
        final source = sf.PdfDocument(inputBytes: await File(path).readAsBytes());
        try {
          for (var i = 0; i < source.pages.count; i++) {
            final srcPage = source.pages[i];
            final size = srcPage.size;
            // One section per page so mixed page sizes are preserved.
            final section = output.sections!.add();
            section.pageSettings.margins.all = 0;
            section.pageSettings.size = size;
            section.pageSettings.rotate = srcPage.rotation;
            final page = section.pages.add();
            page.graphics.drawPdfTemplate(
              srcPage.createTemplate(),
              ui.Offset.zero,
              size,
            );
          }
        } finally {
          source.dispose();
        }
      }

      final outputPath = await StorageService.getUniqueFilePath(
        StorageService.exportsDir,
        outputName,
        'pdf',
      );
      await File(outputPath).writeAsBytes(await output.save());
      return outputPath;
    } finally {
      output.dispose();
    }
  }

  // ── Split PDF ──

  static Future<List<String>> splitPdf(
    String pdfPath,
    List<int> pageNumbers, {
    String? outputName,
  }) async {
    try {
      final result = await _channel.invokeMethod<List>('splitPdf', {
        'pdfPath': pdfPath,
        'pageNumbers': pageNumbers,
        'outputDir': StorageService.exportsDir.path,
      });
      return result!.cast<String>();
    } on PlatformException catch (e) {
      throw Exception('Failed to split PDF: ${e.message}');
    }
  }

  // ── Compress PDF ──

  static Future<String> compressPdf(
    String pdfPath, {
    required CompressionLevel level,
  }) async {
    try {
      final result = await _channel.invokeMethod<String>('compressPdf', {
        'pdfPath': pdfPath,
        'quality': level.quality,
        'dpi': level.dpi,
        'outputDir': StorageService.exportsDir.path,
      });
      return result!;
    } on PlatformException catch (e) {
      throw Exception('Failed to compress PDF: ${e.message}');
    }
  }

  // ── Password Protect PDF ──

  static Future<String> passwordProtectPdf(
    String pdfPath, {
    required String password,
    bool allowPrinting = true,
    bool allowCopying = false,
    bool allowEditing = false,
  }) async {
    try {
      final result = await _channel.invokeMethod<String>('encryptPdf', {
        'pdfPath': pdfPath,
        'password': password,
        'allowPrinting': allowPrinting,
        'allowCopying': allowCopying,
        'allowEditing': allowEditing,
        'outputDir': StorageService.exportsDir.path,
      });
      return result!;
    } on PlatformException catch (e) {
      throw Exception('Failed to encrypt PDF: ${e.message}');
    }
  }

  // ── Edit PDF Text ──

  static Future<String> editPdfText(
    String pdfPath,
    int pageIndex,
    Map<String, String> textReplacements, {
    Map<String, Map<String, dynamic>>? formatting,
  }) async {
    try {
      final result = await _channel.invokeMethod<String>('editPdfText', {
        'pdfPath': pdfPath,
        'pageIndex': pageIndex,
        'replacements': textReplacements,
        'formatting': formatting ?? {},
        'outputDir': StorageService.exportsDir.path,
      });
      return result!;
    } on PlatformException catch (e) {
      throw Exception('Failed to edit PDF: ${e.message}');
    }
  }

  // ── Insert Pages ──

  static Future<String> insertPages(
    String pdfPath,
    int insertAtIndex,
    List<String> pagePaths,
  ) async {
    try {
      final result = await _channel.invokeMethod<String>('insertPages', {
        'pdfPath': pdfPath,
        'insertAtIndex': insertAtIndex,
        'pagePaths': pagePaths,
        'outputDir': StorageService.exportsDir.path,
      });
      return result!;
    } on PlatformException catch (e) {
      throw Exception('Failed to insert pages: ${e.message}');
    }
  }

  // ── Page Management ──

  static Future<String> reorderPages(
    String pdfPath,
    List<int> newOrder,
  ) async {
    try {
      final result = await _channel.invokeMethod<String>('reorderPages', {
        'pdfPath': pdfPath,
        'newOrder': newOrder,
        'outputDir': StorageService.exportsDir.path,
      });
      return result!;
    } on PlatformException catch (e) {
      throw Exception('Failed to reorder pages: ${e.message}');
    }
  }

  static Future<String> deletePages(
    String pdfPath,
    List<int> pageIndices,
  ) async {
    try {
      final result = await _channel.invokeMethod<String>('deletePages', {
        'pdfPath': pdfPath,
        'pageIndices': pageIndices,
        'outputDir': StorageService.exportsDir.path,
      });
      return result!;
    } on PlatformException catch (e) {
      throw Exception('Failed to delete pages: ${e.message}');
    }
  }

  static Future<String> rotatePages(
    String pdfPath,
    List<int> pageIndices,
    int degrees,
  ) async {
    try {
      final result = await _channel.invokeMethod<String>('rotatePages', {
        'pdfPath': pdfPath,
        'pageIndices': pageIndices,
        'degrees': degrees,
        'outputDir': StorageService.exportsDir.path,
      });
      return result!;
    } on PlatformException catch (e) {
      throw Exception('Failed to rotate pages: ${e.message}');
    }
  }

  // ── Fill & Sign ──

  static Future<String> addSignatureToPdf(
    String pdfPath,
    int pageIndex,
    Uint8List signatureImageBytes,
    double x,
    double y,
    double width,
    double height,
  ) async {
    try {
      final result = await _channel.invokeMethod<String>('addImageToPdf', {
        'pdfPath': pdfPath,
        'pageIndex': pageIndex,
        'imageBytes': signatureImageBytes,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'outputDir': StorageService.exportsDir.path,
      });
      return result!;
    } on PlatformException catch (e) {
      throw Exception('Failed to add signature: ${e.message}');
    }
  }

  static Future<String> addTextToPdf(
    String pdfPath,
    int pageIndex,
    String text,
    double x,
    double y,
    double fontSize,
  ) async {
    try {
      final result = await _channel.invokeMethod<String>('addTextToPdf', {
        'pdfPath': pdfPath,
        'pageIndex': pageIndex,
        'text': text,
        'x': x,
        'y': y,
        'fontSize': fontSize,
        'outputDir': StorageService.exportsDir.path,
      });
      return result!;
    } on PlatformException catch (e) {
      throw Exception('Failed to add text: ${e.message}');
    }
  }

  // ── Form Fields ──

  static Future<List<PdfFormField>> getFormFields(String pdfPath) async {
    try {
      final result = await _channel.invokeMethod<List>('getFormFields', {
        'pdfPath': pdfPath,
      });
      if (result == null) return [];
      return result.map((f) {
        final field = Map<String, dynamic>.from(f);
        return PdfFormField(
          name: field['name'] as String? ?? '',
          type: field['type'] as String? ?? 'text',
          value: field['value'] as String? ?? '',
          page: field['page'] as int? ?? 0,
        );
      }).toList();
    } on PlatformException {
      return [];
    }
  }

  static Future<String> fillFormFields(
    String pdfPath,
    Map<String, String> fieldValues,
  ) async {
    try {
      final result = await _channel.invokeMethod<String>('fillFormFields', {
        'pdfPath': pdfPath,
        'fieldValues': fieldValues,
        'outputDir': StorageService.exportsDir.path,
      });
      return result!;
    } on PlatformException catch (e) {
      throw Exception('Failed to fill form: ${e.message}');
    }
  }

  // ── Searchable PDF (OCR text layer) ──

  /// Adds an invisible, selectable/searchable text layer to [pdfPath] using
  /// OCR results. Line boxes are in pixel coordinates of the rasterised page
  /// image that was OCR'd ([OcrTextLayerPage.imageWidth] × `imageHeight`);
  /// the native side scales them onto each PDF page.
  /// Returns the path of the new PDF (in the exports directory).
  static Future<String> addOcrTextLayer(
    String pdfPath, {
    required List<OcrTextLayerPage> pages,
  }) async {
    try {
      final result = await _channel.invokeMethod<String>('addOcrTextLayer', {
        'pdfPath': pdfPath,
        'outputDir': StorageService.exportsDir.path,
        'pages': pages.map((p) => p.toMap()).toList(),
      });
      return result!;
    } on PlatformException catch (e) {
      throw Exception('Failed to create searchable PDF: ${e.message}');
    } on MissingPluginException {
      throw Exception('Searchable PDF is not supported on this device yet');
    }
  }

  /// Reads the pixel dimensions of an encoded image (PNG/JPEG) from its
  /// header, without decoding the whole bitmap.
  static Future<ui.Size> getImageSize(String imagePath) async {
    final buffer = await ui.ImmutableBuffer.fromFilePath(imagePath);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      return ui.Size(descriptor.width.toDouble(), descriptor.height.toDouble());
    } finally {
      descriptor.dispose();
      buffer.dispose();
    }
  }

  // ── PDF to Images ──

  static Future<List<String>> pdfToImages(
    String pdfPath, {
    String format = 'png',
    int dpi = 300,
  }) async {
    try {
      final result = await _channel.invokeMethod<List>('pdfToImages', {
        'pdfPath': pdfPath,
        'format': format,
        'dpi': dpi,
        'outputDir': StorageService.tempDir.path,
      });
      return result!.cast<String>();
    } on PlatformException catch (e) {
      throw Exception('Failed to convert PDF to images: ${e.message}');
    }
  }

  // ── Get PDF Info ──

  static Future<Map<String, dynamic>> getPdfInfo(String pdfPath) async {
    try {
      final result = await _channel.invokeMethod<Map>('getPdfInfo', {
        'pdfPath': pdfPath,
      });
      return Map<String, dynamic>.from(result!);
    } on PlatformException catch (e) {
      throw Exception('Failed to get PDF info: ${e.message}');
    }
  }

  /// Page count of [pdfPath], read in Dart (no native bridge needed).
  /// Returns 1 if the file can't be parsed (e.g. encrypted).
  static Future<int> getPageCount(String pdfPath) async {
    try {
      final doc = sf.PdfDocument(inputBytes: await File(pdfPath).readAsBytes());
      try {
        return doc.pages.count;
      } finally {
        doc.dispose();
      }
    } catch (_) {
      return 1;
    }
  }

  // ── Flatten Annotations ──

  static Future<String> flattenAnnotations(String pdfPath) async {
    try {
      final result = await _channel.invokeMethod<String>('flattenAnnotations', {
        'pdfPath': pdfPath,
        'outputDir': StorageService.exportsDir.path,
      });
      return result!;
    } on PlatformException catch (e) {
      throw Exception('Failed to flatten annotations: ${e.message}');
    }
  }

  // ── Apply Annotations ──

  /// Writes annotations drawn in the editor overlay into a copy of the PDF.
  /// Each map comes from [AnnotationModel.toNative].
  static Future<String> applyAnnotations(
    String pdfPath,
    List<Map<String, dynamic>> annotations,
  ) async {
    try {
      final result = await _channel.invokeMethod<String>('applyAnnotations', {
        'pdfPath': pdfPath,
        'annotations': annotations,
        'outputDir': StorageService.exportsDir.path,
      });
      return result!;
    } on PlatformException catch (e) {
      throw Exception('Failed to save annotations: ${e.message}');
    }
  }
}

/// One page of OCR output for [PdfService.addOcrTextLayer].
class OcrTextLayerPage {
  final int pageIndex;
  final double imageWidth;
  final double imageHeight;
  final List<OcrTextLayerLine> lines;

  const OcrTextLayerPage({
    required this.pageIndex,
    required this.imageWidth,
    required this.imageHeight,
    required this.lines,
  });

  Map<String, dynamic> toMap() => {
        'pageIndex': pageIndex,
        'imageWidth': imageWidth,
        'imageHeight': imageHeight,
        'lines': lines.map((l) => l.toMap()).toList(),
      };
}

/// A single line of recognised text with its box in image pixels.
class OcrTextLayerLine {
  final String text;
  final double left;
  final double top;
  final double width;
  final double height;

  const OcrTextLayerLine({
    required this.text,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  Map<String, dynamic> toMap() => {
        'text': text,
        'left': left,
        'top': top,
        'width': width,
        'height': height,
      };
}

class PdfFormField {
  final String name;
  final String type;
  final String value;
  final int page;

  const PdfFormField({
    required this.name,
    required this.type,
    required this.value,
    required this.page,
  });
}

enum CompressionLevel {
  high(quality: 50, dpi: 72, label: 'High Compression'),
  medium(quality: 75, dpi: 150, label: 'Medium Compression'),
  low(quality: 90, dpi: 300, label: 'Low Compression');

  const CompressionLevel({
    required this.quality,
    required this.dpi,
    required this.label,
  });

  final int quality;
  final int dpi;
  final String label;
}
