import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

import 'package:docuscan_pro/core/services/conversion_service.dart';

void main() {
  group('ConversionService.assessExtractedText', () {
    final paragraph = 'The quick brown fox jumps over the lazy dog. ' * 10;

    test('text-heavy PDF is good quality', () {
      final q = ConversionService.assessExtractedText([paragraph, paragraph]);
      expect(q.isLowQuality, isFalse);
    });

    test('no text at all (scanned PDF) is low quality', () {
      final q = ConversionService.assessExtractedText(['', '  \n ', '']);
      expect(q.isLowQuality, isTrue);
      expect(q.reason, contains('scanned'));
    });

    test('mostly empty pages are low quality', () {
      final q = ConversionService.assessExtractedText(
          [paragraph, 'Page 2', 'Page 3', '']);
      expect(q.isLowQuality, isTrue);
    });

    test('garbled glyphs (custom font encodings) are low quality', () {
      final garbled = '� ' * 60 + 'ok';
      final q = ConversionService.assessExtractedText([garbled]);
      expect(q.isLowQuality, isTrue);
      expect(q.reason, contains('decoded'));
    });

    test('empty document is low quality', () {
      expect(ConversionService.assessExtractedText([]).isLowQuality, isTrue);
    });
  });

  group('ConversionService.buildDocx', () {
    test('produces a well-formed OOXML package', () {
      final bytes = ConversionService.buildDocx([
        {'text': 'Hello <world> & "friends"\n  indented'},
        {'text': 'Page two\u0001 with a control char'},
      ]);
      final archive = ZipDecoder().decodeBytes(bytes);
      final names = archive.files.map((f) => f.name).toSet();
      expect(names, containsAll(<String>[
        '[Content_Types].xml',
        '_rels/.rels',
        'word/document.xml',
        'word/_rels/document.xml.rels',
        'word/styles.xml',
      ]));

      // Every part must parse as XML.
      for (final file in archive.files) {
        XmlDocument.parse(utf8.decode(file.content));
      }

      final doc = XmlDocument.parse(
          utf8.decode(archive.findFile('word/document.xml')!.content));
      final texts = doc.findAllElements('w:t').map((e) => e.innerText).toList();
      expect(texts, ['Hello <world> & "friends"', '  indented',
          'Page two with a control char']);
      // Exactly one page break between the two pages.
      expect(doc.findAllElements('w:br').length, 1);

      // Every override in [Content_Types].xml points at an existing part.
      final types = XmlDocument.parse(
          utf8.decode(archive.findFile('[Content_Types].xml')!.content));
      for (final o in types.findAllElements('Override')) {
        expect(names, contains(o.getAttribute('PartName')!.substring(1)));
      }
    });
  });

  test('columnName handles multi-letter spreadsheet columns', () {
    expect(ConversionService.columnName(0), 'A');
    expect(ConversionService.columnName(25), 'Z');
    expect(ConversionService.columnName(26), 'AA');
    expect(ConversionService.columnName(27), 'AB');
    expect(ConversionService.columnName(701), 'ZZ');
    expect(ConversionService.columnName(702), 'AAA');
  });
}
