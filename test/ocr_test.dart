import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:docuscan_pro/core/services/ocr_service.dart';
import 'package:docuscan_pro/core/services/pdf_service.dart';

void main() {
  group('OcrLanguage', () {
    test('Tesseract-only languages use 3-letter traineddata codes', () {
      const expected = {
        'ru': 'rus', 'ar': 'ara', 'fa': 'fas', 'ur': 'urd', 'th': 'tha',
        'he': 'heb', 'el': 'ell', 'bn': 'ben', 'ta': 'tam', 'uk': 'ukr',
        'bg': 'bul', 'sr': 'srp',
      };
      expected.forEach((code, tess) {
        final lang = OcrLanguage.fromCode(code)!;
        expect(lang.tesseractCode, tess, reason: code);
        expect(lang.usesMlKit, isFalse, reason: code);
      });
    });

    test('ML Kit languages map to their script', () {
      expect(OcrLanguage.fromCode('en')!.mlKitScript, OcrScript.latin);
      expect(OcrLanguage.fromCode('hi')!.mlKitScript, OcrScript.devanagari);
      expect(OcrLanguage.fromCode('zh')!.usesMlKit, isTrue);
      expect(OcrLanguage.fromCode('ja')!.tesseractCode, 'jpn');
    });

    test('fromCode accepts tesseract codes and rejects unknowns', () {
      expect(OcrLanguage.fromCode('rus')!.code, 'ru');
      expect(OcrLanguage.fromCode('xx'), isNull);
    });

    test('codes are unique and lists partition the supported set', () {
      final codes = OcrLanguage.supported.map((l) => l.code).toSet();
      final tess = OcrLanguage.supported.map((l) => l.tesseractCode).toSet();
      expect(codes.length, OcrLanguage.supported.length);
      expect(tess.length, OcrLanguage.supported.length);
      expect(
        OcrLanguage.onDevice.length + OcrLanguage.tesseract.length,
        OcrLanguage.supported.length,
      );
    });
  });

  group('CSV export', () {
    test('escapes commas, quotes and newlines', () {
      expect(OcrService.escapeCsvCell('plain'), 'plain');
      expect(OcrService.escapeCsvCell('a,b'), '"a,b"');
      expect(OcrService.escapeCsvCell('say "hi"'), '"say ""hi"""');
      expect(OcrService.escapeCsvCell('two\nlines'), '"two\nlines"');
      expect(OcrService.escapeCsvCell('cr\rhere'), '"cr\rhere"');
    });

    test('joins rows and cells', () {
      expect(
        OcrService.rowsToCsv([
          ['Name', 'Price'],
          ['Tea, green', r'$3'],
        ]),
        'Name,Price\n"Tea, green",\$3',
      );
    });
  });

  group('Text layer lines', () {
    test('Tesseract blocks are split into evenly spaced lines', () {
      final lines = OcrService.splitBlockIntoLines(
        'first\n\nsecond\n',
        const Rect.fromLTWH(10, 100, 200, 40),
      );
      expect(lines.map((l) => l.text), ['first', 'second']);
      expect(lines[0].boundingBox, const Rect.fromLTWH(10, 100, 200, 20));
      expect(lines[1].boundingBox, const Rect.fromLTWH(10, 120, 200, 20));
    });

    test('allLines prefers engine lines and falls back to block splitting', () {
      const mlKitLine = OcrTextLine(
        text: 'hello',
        boundingBox: Rect.fromLTWH(0, 0, 50, 10),
        words: [],
      );
      const result = OcrResult(
        fullText: 'hello\nfoo\nbar',
        engine: 'test',
        script: OcrScript.latin,
        blocks: [
          OcrTextBlock(text: 'hello', boundingBox: Rect.fromLTWH(0, 0, 50, 10), lines: [mlKitLine]),
          OcrTextBlock(text: 'foo\nbar', boundingBox: Rect.fromLTWH(0, 20, 50, 20), lines: []),
        ],
      );
      expect(result.allLines.map((l) => l.text), ['hello', 'foo', 'bar']);
    });

    test('OcrTextLayerPage serialises to the native contract', () {
      const page = OcrTextLayerPage(
        pageIndex: 2,
        imageWidth: 2480,
        imageHeight: 3508,
        lines: [
          OcrTextLayerLine(text: 'Hi', left: 1, top: 2, width: 3, height: 4),
        ],
      );
      expect(page.toMap(), {
        'pageIndex': 2,
        'imageWidth': 2480.0,
        'imageHeight': 3508.0,
        'lines': [
          {'text': 'Hi', 'left': 1.0, 'top': 2.0, 'width': 3.0, 'height': 4.0},
        ],
      });
    });
  });
}
