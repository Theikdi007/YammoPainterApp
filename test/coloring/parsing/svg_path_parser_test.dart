import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:yammopatinerapp/coloring/coloring_page.dart';
import 'package:yammopatinerapp/coloring/parsing/svg_path_parser.dart';

void main() {
  group('parsePath — happy path', () {
    test('parses a simple line', () {
      final p = parsePath('M0 0 L10 10');
      expect(p.getBounds(), const Rect.fromLTRB(0, 0, 10, 10));
    });

    test('parses comma-separated coordinates', () {
      final p = parsePath('M0,0 L10,20');
      expect(p.getBounds(), const Rect.fromLTRB(0, 0, 10, 20));
    });

    test('parses a closed rectangle', () {
      final p = parsePath('M5 5 L25 5 L25 25 L5 25 Z');
      expect(p.getBounds(), const Rect.fromLTRB(5, 5, 25, 25));
    });

    test('parses a cubic bezier', () {
      final p = parsePath('M0 0 C5 0 10 5 10 10');
      final b = p.getBounds();
      expect(b.left, 0);
      expect(b.top, 0);
      expect(b.right, closeTo(10, 0.01));
      expect(b.bottom, closeTo(10, 0.01));
    });

    test('tolerates leading whitespace', () {
      final p = parsePath('   M0 0 L4 4');
      expect(p.getBounds(), const Rect.fromLTRB(0, 0, 4, 4));
    });
  });

  group('parsePath — error path', () {
    test('throws on empty string', () {
      expect(
        () => parsePath(''),
        throwsA(
          isA<ColoringParseException>().having(
            (e) => e.offendingPath,
            'offendingPath',
            '',
          ),
        ),
      );
    });

    test('throws on whitespace-only input', () {
      expect(() => parsePath('   '), throwsA(isA<ColoringParseException>()));
    });

    test('throws when the data does not start with a moveto', () {
      expect(
        () => parsePath('not a path'),
        throwsA(
          isA<ColoringParseException>().having(
            (e) => e.offendingPath,
            'offendingPath',
            'not a path',
          ),
        ),
      );
    });

    test('throws when the data starts with a non-M command', () {
      expect(
        () => parsePath('L10 10'),
        throwsA(isA<ColoringParseException>()),
      );
    });

    test('preserves the offending string in the exception message', () {
      try {
        parsePath('Q nope');
        fail('expected ColoringParseException');
      } on ColoringParseException catch (e) {
        expect(e.toString(), contains('Q nope'));
      }
    });
  });
}
