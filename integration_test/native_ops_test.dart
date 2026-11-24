// On-device checks for the native PDF/OCR bridges (PDFBox + Tesseract on
// Android, PDFKit + SwiftyTesseract on iOS). Run with:
//   flutter test integration_test/native_ops_test.dart -d <device>
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:docuscan_pro/core/services/conversion_service.dart';
import 'package:docuscan_pro/core/services/ocr_service.dart';
import 'package:docuscan_pro/core/services/pdf_service.dart';
import 'package:docuscan_pro/core/services/storage_service.dart';

late Directory work;

Future<String> savePdf(String name, pw.Document doc) async {
  final file = File('${work.path}/$name');
  await file.writeAsBytes(await doc.save());
  return file.path;
}

Future<String> textPdf(String name, List<String> lines) {
  final doc = pw.Document();
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.letter,
    build: (_) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [for (final l in lines) pw.Padding(padding: const pw.EdgeInsets.only(bottom: 10), child: pw.Text(l, style: const pw.TextStyle(fontSize: 14)))],
    ),
  ));
  return savePdf(name, doc);
}

/// White page image with large black text, like a scanned document.
Uint8List scanImage(String text) {
  final image = img.Image(width: 1275, height: 1650);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  img.drawString(image, text, font: img.arial48, x: 120, y: 200, color: img.ColorRgb8(0, 0, 0));
  return img.encodePng(image);
}

Future<String> imagePdf(String name, Uint8List png) {
  final doc = pw.Document();
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.letter,
    margin: pw.EdgeInsets.zero,
    build: (_) => pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.fill),
  ));
  return savePdf(name, doc);
}

Future<String> pageText(String pdfPath, [int page = 0]) async {
  final images = await PdfService.pdfToImages(pdfPath, dpi: 72);
  expect(images, isNotEmpty);
  // Text comes from the native text extractor used by on-device conversion.
  final result = await ConversionService.pdfToWord(pdfPath);
  expect(result.success, isTrue, reason: result.error);
  final docx = ZipDecoder().decodeBytes(await File(result.outputPath).readAsBytes());
  final xml = String.fromCharCodes(docx.findFile('word/document.xml')!.content as List<int>);
  return xml.replaceAll(RegExp(r'<[^>]+>'), ' ');
}

img.Color pixelAt(String imagePath, double fx, double fy) {
  final image = img.decodeImage(File(imagePath).readAsBytesSync())!;
  return image.getPixel((image.width * fx).round(), (image.height * fy).round());
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await StorageService.initialize();
    work = await Directory('${StorageService.tempDir.path}/itest').create(recursive: true);
  });

  testWidgets('edit text: replaces in the content stream, keeping the original font', (_) async {
    final src = await textPdf('edit.pdf', ['Invoice number 1042', 'Total due: 250.00 USD', 'Thank you']);
    final out = await PdfService.editPdfText(src, 0, {'250.00': '275.50'});
    final text = await pageText(out);
    expect(text, contains('275.50'));
    if (Platform.isAndroid) {
      expect(text, isNot(contains('250.00')), reason: 'in-stream edit should remove the old text');
    }
    // iOS: PDFKit can't rewrite content streams, so the edit covers the old
    // text and draws the new text over it; the old glyphs stay in the file
    // (known limitation, see PdfHandler.swift editPdfText).
  });

  testWidgets('edit text: style change falls back to cover-and-redraw', (_) async {
    final src = await textPdf('edit2.pdf', ['Hello World']);
    final out = await PdfService.editPdfText(src, 0, {'World': 'There'}, formatting: {
      'World': {'fontSize': 14.0, 'bold': true, 'italic': false},
    });
    expect(await pageText(out), contains('There'));
  });

  testWidgets('edit text: reports text that is not on the page', (_) async {
    final src = await textPdf('edit3.pdf', ['Hello']);
    expect(() => PdfService.editPdfText(src, 0, {'Missing words': 'x'}), throwsException);
  });

  testWidgets('compress: shrinks a photo-like PDF and never grows a text PDF', (_) async {
    final rnd = Random(7);
    final photo = img.Image(width: 1600, height: 2000);
    for (final p in photo) {
      final n = rnd.nextInt(40);
      p..r = (p.x * 255 ~/ 1600 + n) & 0xFF..g = (p.y * 255 ~/ 2000 + n) & 0xFF..b = 128 + n;
    }
    final heavy = await imagePdf('heavy.pdf', img.encodePng(photo));
    final heavySize = File(heavy).lengthSync();
    final out = await PdfService.compressPdf(heavy, level: CompressionLevel.high);
    expect(File(out).lengthSync(), lessThan(heavySize * 0.8), reason: '$heavySize → ${File(out).lengthSync()}');

    final light = await textPdf('light.pdf', ['Just text']);
    final out2 = await PdfService.compressPdf(light, level: CompressionLevel.high);
    expect(File(out2).lengthSync(), lessThanOrEqualTo(File(light).lengthSync()));
  });

  testWidgets('password: output is encrypted and needs the password', (_) async {
    final src = await textPdf('secret.pdf', ['Confidential']);
    final out = await PdfService.passwordProtectPdf(src, password: 's3cret', allowCopying: false);
    final bytes = await File(out).readAsBytes();
    expect(String.fromCharCodes(bytes).contains('/Encrypt'), isTrue);
    expect(() => PdfService.getPdfInfo(out), throwsException, reason: 'should not open without a password');
  });

  testWidgets('forms: lists, fills and persists AcroForm fields', (_) async {
    final doc = pw.Document();
    doc.addPage(pw.Page(build: (_) => pw.Column(children: [
          pw.Row(children: [pw.Text('Name: '), pw.TextField(name: 'full_name', width: 200, height: 20)]),
          pw.Row(children: [pw.Text('Agree: '), pw.Checkbox(name: 'agree', value: false)]),
        ])));
    final src = await savePdf('form.pdf', doc);
    final fields = await PdfService.getFormFields(src);
    expect(fields.map((f) => f.name), containsAll(['full_name', 'agree']));

    final out = await PdfService.fillFormFields(src, {'full_name': 'Ada Lovelace', 'agree': 'true'});
    final back = {for (final f in await PdfService.getFormFields(out)) f.name: f};
    expect(back['full_name']!.value, 'Ada Lovelace');
    expect(back['agree']!.value.toLowerCase(), isNot(anyOf('', 'off', 'false')));
  });

  testWidgets('annotations: highlight is painted where it was drawn', (_) async {
    final src = await textPdf('annot.pdf', ['Some text to highlight']);
    final out = await PdfService.applyAnnotations(src, [
      {'pageIndex': 0, 'type': 'highlight', 'color': 0xFFFF0000, 'rect': {'x': 0.5, 'y': 0.5, 'width': 0.3, 'height': 0.1}},
      {'pageIndex': 0, 'type': 'freehand', 'color': 0xFF0000FF, 'strokeWidth': 0.01, 'viewWidth': 1.0,
        'points': [{'x': 0.1, 'y': 0.9}, {'x': 0.4, 'y': 0.9}]},
      {'pageIndex': 0, 'type': 'stickyNote', 'color': 0xFFFFC107, 'rect': {'x': 0.9, 'y': 0.1, 'width': 0, 'height': 0}, 'text': 'Note'},
    ]);
    final image = (await PdfService.pdfToImages(out, format: 'jpg', dpi: 72)).first;
    final inside = pixelAt(image, 0.65, 0.55);
    expect(inside.r > 200 && inside.g < 220 && inside.b < 220, isTrue, reason: 'highlight pixel was $inside');
    final outside = pixelAt(image, 0.65, 0.3);
    expect(outside.r > 240 && outside.g > 240, isTrue, reason: 'unmarked pixel was $outside');
    final ink = pixelAt(image, 0.25, 0.9);
    expect(ink.b > 150 && ink.r < 120, isTrue, reason: 'ink pixel was $ink');
  });

  testWidgets('pdfToImages: JPEG pages have a white background', (_) async {
    final src = await textPdf('bg.pdf', ['x']);
    final image = (await PdfService.pdfToImages(src, format: 'jpg', dpi: 72)).first;
    final p = pixelAt(image, 0.9, 0.9);
    expect(p.r > 240 && p.g > 240 && p.b > 240, isTrue, reason: 'background pixel was $p');
  });

  testWidgets('OCR: ML Kit reads a rendered page', (_) async {
    final scan = await imagePdf('mlkit.pdf', scanImage('INVOICE TOTAL 42'));
    final page = (await PdfService.pdfToImages(scan, dpi: 150)).first;
    final result = await OcrService.recognizeText(page);
    expect(result.fullText.toUpperCase(), contains('INVOICE'));
  });

  testWidgets('OCR: Tesseract downloads a pack and reads a page', (_) async {
    expect(await OcrService.downloadLanguagePack('eng'), isTrue);
    expect(await OcrService.getAvailableLanguages(), contains('eng'));
    final scan = await imagePdf('tess.pdf', scanImage('SEARCHABLE WORDS'));
    final page = (await PdfService.pdfToImages(scan, dpi: 150)).first;
    final result = await OcrService.recognizeTextTesseract(page, languageCode: 'eng');
    expect(result.fullText.toUpperCase(), contains('SEARCHABLE'));
    expect(result.blocks, isNotEmpty);
  });

  testWidgets('OCR text layer makes a scanned page searchable', (_) async {
    final scan = await imagePdf('scan.pdf', scanImage('HELLO SCANNED'));
    expect((await pageText(scan)).trim(), isNot(contains('HELLO')));
    final out = await PdfService.addOcrTextLayer(scan, pages: const [
      OcrTextLayerPage(pageIndex: 0, imageWidth: 1275, imageHeight: 1650, lines: [
        OcrTextLayerLine(text: 'HELLO SCANNED', left: 120, top: 200, width: 500, height: 50),
      ]),
    ]);
    expect(await pageText(out), contains('HELLO SCANNED'));
    final image = (await PdfService.pdfToImages(out, format: 'jpg', dpi: 72)).first;
    final p = pixelAt(image, 0.5, 0.6);
    expect(p.r > 240, isTrue, reason: 'text layer must be invisible');
  });

  testWidgets('page operations: reorder, delete, split, rotate, insert, merge', (_) async {
    final pages = [for (final n in ['A', 'B', 'C']) await textPdf('$n.pdf', ['Page $n'])];
    final three = await PdfService.mergePdfs(pages, outputName: 'three_${DateTime.now().millisecondsSinceEpoch}');
    expect(await PdfService.getPageCount(three), 3);

    Future<List<String>> order(String path) async {
      final text = await pageText(path);
      return RegExp(r'Page ([ABC])').allMatches(text).map((m) => m.group(1)!).toList();
    }

    expect(await order(await PdfService.reorderPages(three, [2, 0, 1])), ['C', 'A', 'B']);
    expect(await order(await PdfService.deletePages(three, [1])), ['A', 'C']);
    expect(await order((await PdfService.splitPdf(three, [2, 0])).first), ['A', 'C']);

    final rotated = await PdfService.rotatePages(three, [0], -90);
    final rotatedImage = img.decodeImage(File((await PdfService.pdfToImages(rotated, dpi: 36)).first).readAsBytesSync())!;
    expect(rotatedImage.width, greaterThan(rotatedImage.height), reason: 'page 1 should be landscape after rotating');

    final photo = '${work.path}/photo.png';
    await File(photo).writeAsBytes(scanImage('PHOTO'));
    final inserted = await PdfService.insertPages(three, 1, [photo, pages[0]]);
    expect(await PdfService.getPageCount(inserted), 5);
    expect(await order(inserted), ['A', 'A', 'B', 'C']);
  });

  testWidgets('signature image is drawn onto the page', (_) async {
    final src = await textPdf('sign.pdf', ['Sign below']);
    final sig = img.Image(width: 200, height: 80);
    img.fill(sig, color: img.ColorRgb8(0, 0, 255));
    final out = await PdfService.addSignatureToPdf(src, 0, img.encodePng(sig), 300, 600, 200, 80);
    final image = (await PdfService.pdfToImages(out, format: 'jpg', dpi: 72)).first;
    // Letter page is 612×792pt; the signature spans x 300–500, y 600–680 from the top.
    final p = pixelAt(image, 400 / 612, 640 / 792);
    expect(p.b > 200 && p.r < 60, isTrue, reason: 'signature pixel was $p');
    expect(await pageText(out), contains('Sign below'));
  });
}
