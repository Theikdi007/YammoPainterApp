import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pandapainterapp/models/shape_recognizer.dart';

/// Samples [perEdge] points along each edge connecting [corners] in order.
/// When [closed], the last corner connects back to the first.
List<Offset> _alongEdges(
  List<Offset> corners, {
  int perEdge = 12,
  bool closed = true,
}) {
  final pts = <Offset>[];
  final count = closed ? corners.length : corners.length - 1;
  for (var c = 0; c < count; c++) {
    final a = corners[c];
    final b = corners[(c + 1) % corners.length];
    for (var i = 0; i < perEdge; i++) {
      final t = i / perEdge;
      pts.add(Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t));
    }
  }
  // Close the loop back onto the first point so it reads as closed.
  if (closed) pts.add(corners.first);
  return pts;
}

void main() {
  group('recognizeShape', () {
    test('snaps a freehand circle to a closed ellipse', () {
      final pts = [
        for (var i = 0; i < 48; i++)
          Offset(
            100 + 50 * math.cos(i / 48 * 2 * math.pi),
            100 + 50 * math.sin(i / 48 * 2 * math.pi),
          ),
        const Offset(150, 100), // close the loop
      ];
      final shape = recognizeShape(pts);
      expect(shape, isNotNull);
      expect(shape!.closed, isTrue);
      expect(shape.points.length, greaterThan(16)); // smooth ellipse polygon
    });

    test('snaps a rectangle to a closed 4-point polygon', () {
      final shape = recognizeShape(
        _alongEdges(const [
          Offset(50, 50),
          Offset(150, 50),
          Offset(150, 120),
          Offset(50, 120),
        ]),
      );
      expect(shape, isNotNull);
      expect(shape!.closed, isTrue);
      expect(shape.points.length, 4);
    });

    test('snaps a wobbly hand-drawn rectangle to 4 points', () {
      final clean = _alongEdges(
        const [
          Offset(60, 80),
          Offset(220, 80),
          Offset(220, 200),
          Offset(60, 200),
        ],
        perEdge: 14,
      );
      final noisy = [
        for (var i = 0; i < clean.length; i++)
          clean[i] +
              Offset(((i * 7) % 5 - 2).toDouble(), ((i * 3) % 5 - 2).toDouble()),
      ];
      final shape = recognizeShape(noisy);
      expect(shape, isNotNull);
      expect(shape!.closed, isTrue);
      expect(shape.points.length, 4);
    });

    test('snaps a wobbly hand-drawn triangle to 3 points', () {
      final clean = _alongEdges(
        const [Offset(140, 50), Offset(230, 210), Offset(50, 210)],
        perEdge: 16,
      );
      final noisy = [
        for (var i = 0; i < clean.length; i++)
          clean[i] +
              Offset(((i * 5) % 5 - 2).toDouble(), ((i * 11) % 5 - 2).toDouble()),
      ];
      final shape = recognizeShape(noisy);
      expect(shape, isNotNull);
      expect(shape!.points.length, 3);
    });

    test('snaps a triangle to a closed 3-point polygon', () {
      final shape = recognizeShape(
        _alongEdges(const [
          Offset(100, 40),
          Offset(160, 140),
          Offset(40, 140),
        ]),
      );
      expect(shape, isNotNull);
      expect(shape!.closed, isTrue);
      expect(shape.points.length, 3);
    });

    test('snaps a near-straight stroke to a 2-point line', () {
      final pts = [
        for (var i = 0; i <= 20; i++) Offset(40 + i * 8.0, 100 + (i.isEven ? 1 : -1)),
      ];
      final shape = recognizeShape(pts);
      expect(shape, isNotNull);
      expect(shape!.closed, isFalse);
      expect(shape.points.length, 2);
    });

    test('leaves an irregular open scribble as freehand (null)', () {
      final pts = [
        for (var i = 0; i < 24; i++)
          Offset(40 + i * 6.0, 100 + (i % 3) * 40 - (i % 2) * 25),
      ];
      expect(recognizeShape(pts), isNull);
    });

    test('ignores a tiny stroke (too small to be a shape)', () {
      final pts = [
        for (var i = 0; i < 10; i++)
          Offset(100 + math.cos(i.toDouble()) * 3, 100 + math.sin(i.toDouble()) * 3),
      ];
      expect(recognizeShape(pts), isNull);
    });
  });
}
